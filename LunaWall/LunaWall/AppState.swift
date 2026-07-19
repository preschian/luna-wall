import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    private enum DefaultsKey {
        static let lastAppliedHash = "lastAppliedHash"
        static let lastAppliedDate = "lastAppliedDate"
        static let autoRefreshEnabled = "autoRefreshEnabled"
        static let pinnedHash = "pinnedHash"
    }

    /// Number of recent Bing days to fetch (API caps at 8).
    static let historyCount = 8

    var currentImage: BingImage?
    var recentImages: [BingImage] = []
    var statusMessage = "Ready"
    var isRefreshing = false
    var lastError: String?
    var autoRefreshEnabled: Bool {
        didSet { UserDefaults.standard.set(autoRefreshEnabled, forKey: DefaultsKey.autoRefreshEnabled) }
    }
    /// When set, auto-refresh keeps this image instead of switching to today’s.
    var pinnedHash: String? {
        didSet { UserDefaults.standard.set(pinnedHash, forKey: DefaultsKey.pinnedHash) }
    }
    var launchAtLoginEnabled: Bool

    var isPinned: Bool { pinnedHash != nil }

    private let bingService = BingWallpaperService()
    private let wallpaperService = WallpaperService()
    private var operationTask: Task<Void, Never>?
    private var operationGeneration = 0
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var didStart = false

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.autoRefreshEnabled) == nil {
            defaults.set(true, forKey: DefaultsKey.autoRefreshEnabled)
        }
        autoRefreshEnabled = defaults.bool(forKey: DefaultsKey.autoRefreshEnabled)
        pinnedHash = defaults.string(forKey: DefaultsKey.pinnedHash)
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        refresh(force: false)
        startScheduler()
        observeWake()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        operationGeneration += 1
        operationTask?.cancel()
        operationTask = nil
        isRefreshing = false
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        didStart = false
    }

    /// Fetches recent images and, unless pinned, applies today’s wallpaper.
    func refresh(force: Bool) {
        beginOperation { generation in
            await self.performRefresh(force: force, generation: generation)
        }
    }

    /// Applies a specific archive image. Pins past days so auto-refresh won’t replace them.
    func applyImage(_ image: BingImage) {
        beginOperation { generation in
            await self.performApply(image, pinIfNotToday: true, generation: generation)
        }
    }

    /// Clears a manual pin and resumes following today’s Bing image.
    func followToday() {
        pinnedHash = nil
        refresh(force: true)
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
            lastError = nil
        } catch {
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
            lastError = error.localizedDescription
            statusMessage = "Could not update login item"
        }
    }

    func openCopyrightPage() {
        guard let url = currentImage?.infoURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func beginOperation(_ work: @escaping @MainActor (Int) async -> Void) {
        operationTask?.cancel()
        operationGeneration += 1
        let generation = operationGeneration
        operationTask = Task {
            isRefreshing = true
            lastError = nil
            defer {
                if generation == operationGeneration {
                    isRefreshing = false
                }
            }
            await work(generation)
        }
    }

    private func performRefresh(force: Bool, generation: Int) async {
        statusMessage = "Fetching Bing wallpaper…"

        do {
            let images = try await bingService.fetchImages(count: Self.historyCount)
            guard generation == operationGeneration else { return }

            recentImages = images
            guard let today = images.first else {
                throw BingWallpaperError.emptyArchive
            }

            if let pinnedHash,
               let pinned = images.first(where: { $0.hsh == pinnedHash }) {
                currentImage = pinned
                let lastHash = UserDefaults.standard.string(forKey: DefaultsKey.lastAppliedHash)
                let fileURL = wallpaperService.localFileURL(for: pinned)
                let needsApply = force
                    || lastHash != pinned.hsh
                    || !FileManager.default.fileExists(atPath: fileURL.path)
                if needsApply {
                    await performApply(pinned, pinIfNotToday: true, generation: generation)
                } else {
                    statusMessage = "Pinned · \(pinned.displayDate)"
                }
                return
            }

            // Pin no longer in the recent window (or was cleared) — follow today.
            if pinnedHash != nil {
                self.pinnedHash = nil
            }

            currentImage = today

            let lastHash = UserDefaults.standard.string(forKey: DefaultsKey.lastAppliedHash)
            if !force, lastHash == today.hsh {
                statusMessage = "Already up to date"
                return
            }

            await performApply(today, pinIfNotToday: false, generation: generation)
        } catch {
            guard generation == operationGeneration, !Self.isCancellation(error) else { return }
            lastError = error.localizedDescription
            statusMessage = "Update failed"
        }
    }

    private func performApply(_ image: BingImage, pinIfNotToday: Bool, generation: Int) async {
        do {
            let fileURL = wallpaperService.localFileURL(for: image)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                statusMessage = "Downloading…"
                try await bingService.download(image, to: fileURL)
                guard generation == operationGeneration else { return }
            }

            statusMessage = "Setting wallpaper…"
            try wallpaperService.setDesktopImage(at: fileURL)
            guard generation == operationGeneration else { return }

            currentImage = image
            UserDefaults.standard.set(image.hsh, forKey: DefaultsKey.lastAppliedHash)
            UserDefaults.standard.set(image.startdate, forKey: DefaultsKey.lastAppliedDate)

            let todayHash = recentImages.first?.hsh
            if pinIfNotToday, let todayHash, image.hsh != todayHash {
                pinnedHash = image.hsh
                statusMessage = "Pinned · \(image.displayDate)"
            } else {
                pinnedHash = nil
                statusMessage = "Updated · \(image.displayDate)"
            }
        } catch {
            guard generation == operationGeneration, !Self.isCancellation(error) else { return }
            lastError = error.localizedDescription
            statusMessage = "Update failed"
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func startScheduler() {
        timer?.invalidate()
        // Check periodically so a new Bing day is picked up without needing a restart.
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.autoRefreshEnabled else { return }
                self.refresh(force: false)
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.autoRefreshEnabled else { return }
                self.refresh(force: false)
            }
        }
    }
}
