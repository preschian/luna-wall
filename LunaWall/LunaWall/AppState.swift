import AppKit
import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    private enum DefaultsKey {
        static let lastAppliedHash = "lastAppliedHash"
        static let lastAppliedDate = "lastAppliedDate"
        static let autoRefreshEnabled = "autoRefreshEnabled"
        static let pinnedHash = "pinnedHash"
    }

    /// Number of recent Bing days to fetch (API caps at 8).
    static let historyCount = 8

    @Published var currentImage: BingImage?
    @Published var recentImages: [BingImage] = []
    /// Bumped when cached library files change so thumbnails reload.
    @Published var libraryRevision = 0
    @Published var statusMessage = "Ready"
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var autoRefreshEnabled: Bool {
        didSet { UserDefaults.standard.set(autoRefreshEnabled, forKey: DefaultsKey.autoRefreshEnabled) }
    }
    /// When set, auto-refresh keeps this image instead of switching to today’s.
    @Published var pinnedHash: String? {
        didSet { UserDefaults.standard.set(pinnedHash, forKey: DefaultsKey.pinnedHash) }
    }
    @Published var launchAtLoginEnabled: Bool

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

    /// Fetches recent images and applies the pinned day, or today’s wallpaper when unpinned.
    func refresh(force: Bool) {
        beginOperation { generation in
            await self.performRefresh(force: force, preferToday: false, generation: generation)
        }
    }

    /// Applies a specific archive image. Pins past days so auto-refresh won’t replace them.
    func applyImage(_ image: BingImage) {
        beginOperation { generation in
            await self.performApplySelected(image, generation: generation)
        }
    }

    /// Resumes following today’s Bing image. Clears the pin only after today applies successfully.
    func followToday() {
        beginOperation { generation in
            await self.performRefresh(force: true, preferToday: true, generation: generation)
        }
    }

    func fileURL(for image: BingImage) -> URL {
        wallpaperService.localFileURL(for: image)
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

    private func performRefresh(force: Bool, preferToday: Bool, generation: Int) async {
        statusMessage = "Fetching Bing wallpaper…"

        do {
            let images = try await bingService.fetchImages(count: Self.historyCount)
            guard generation == operationGeneration else { return }

            recentImages = images
            guard let today = images.first else {
                throw BingWallpaperError.emptyArchive
            }

            await prefetchLibrary(images, generation: generation)
            guard generation == operationGeneration else { return }

            let pinnedImage: BingImage? = {
                guard !preferToday, let hash = pinnedHash else { return nil }
                return images.first(where: { $0.hsh == hash })
            }()
            let target = pinnedImage ?? today

            let lastHash = UserDefaults.standard.string(forKey: DefaultsKey.lastAppliedHash)
            let fileURL = wallpaperService.localFileURL(for: target)
            let cachePresent = FileManager.default.fileExists(atPath: fileURL.path)
            if !force, lastHash == target.hsh, cachePresent {
                currentImage = target
                // Drop an expired pin (or follow-today noop) only once we know today is already applied.
                if target.hsh == today.hsh {
                    pinnedHash = nil
                }
                statusMessage = pinnedHash == nil
                    ? "Already up to date"
                    : "Pinned · \(target.displayDate)"
                return
            }

            await performApply(target, today: today, generation: generation)
        } catch {
            guard generation == operationGeneration, !Self.isCancellation(error) else { return }
            lastError = error.localizedDescription
            statusMessage = "Update failed"
        }
    }

    /// Downloads any missing recent wallpapers so the library and Recent list are fully populated.
    private func prefetchLibrary(_ images: [BingImage], generation: Int) async {
        let pending = images.filter {
            !FileManager.default.fileExists(atPath: wallpaperService.localFileURL(for: $0).path)
        }
        guard !pending.isEmpty else {
            libraryRevision &+= 1
            return
        }

        statusMessage = "Downloading library 0/\(pending.count)…"
        var finished = 0

        await withTaskGroup(of: Bool.self) { group in
            for image in pending {
                let destination = wallpaperService.localFileURL(for: image)
                let service = bingService
                group.addTask {
                    do {
                        try await service.download(image, to: destination)
                        return true
                    } catch {
                        return false
                    }
                }
            }

            for await success in group {
                guard generation == operationGeneration else {
                    group.cancelAll()
                    return
                }
                if success {
                    finished += 1
                    libraryRevision &+= 1
                }
                statusMessage = "Downloading library \(finished)/\(pending.count)…"
            }
        }

        libraryRevision &+= 1
    }

    private func performApplySelected(_ image: BingImage, generation: Int) async {
        do {
            let today: BingImage
            if let knownToday = recentImages.first {
                today = knownToday
            } else {
                statusMessage = "Fetching Bing wallpaper…"
                let images = try await bingService.fetchImages(count: Self.historyCount)
                guard generation == operationGeneration else { return }
                recentImages = images
                await prefetchLibrary(images, generation: generation)
                guard generation == operationGeneration else { return }
                guard let first = images.first else {
                    throw BingWallpaperError.emptyArchive
                }
                today = first
            }
            await performApply(image, today: today, generation: generation)
        } catch {
            guard generation == operationGeneration, !Self.isCancellation(error) else { return }
            lastError = error.localizedDescription
            statusMessage = "Update failed"
        }
    }

    private func performApply(_ image: BingImage, today: BingImage, generation: Int) async {
        do {
            let fileURL = wallpaperService.localFileURL(for: image)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                statusMessage = "Downloading…"
                try await bingService.download(image, to: fileURL)
                guard generation == operationGeneration else { return }
                libraryRevision &+= 1
            }

            statusMessage = "Setting wallpaper…"
            try wallpaperService.setDesktopImage(at: fileURL)
            guard generation == operationGeneration else { return }

            currentImage = image
            UserDefaults.standard.set(image.hsh, forKey: DefaultsKey.lastAppliedHash)
            UserDefaults.standard.set(image.startdate, forKey: DefaultsKey.lastAppliedDate)

            if image.hsh == today.hsh {
                pinnedHash = nil
                statusMessage = "Updated · \(image.displayDate)"
            } else {
                pinnedHash = image.hsh
                statusMessage = "Pinned · \(image.displayDate)"
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
