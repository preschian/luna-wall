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
    }

    var currentImage: BingImage?
    var statusMessage = "Ready"
    var isRefreshing = false
    var lastError: String?
    var autoRefreshEnabled: Bool {
        didSet { UserDefaults.standard.set(autoRefreshEnabled, forKey: DefaultsKey.autoRefreshEnabled) }
    }
    var launchAtLoginEnabled: Bool

    private let bingService = BingWallpaperService()
    private let wallpaperService = WallpaperService()
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var didStart = false

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.autoRefreshEnabled) == nil {
            defaults.set(true, forKey: DefaultsKey.autoRefreshEnabled)
        }
        autoRefreshEnabled = defaults.bool(forKey: DefaultsKey.autoRefreshEnabled)
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
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        didStart = false
    }

    func refresh(force: Bool) {
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask = Task {
            await performRefresh(force: force, generation: generation)
        }
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

    private func performRefresh(force: Bool, generation: Int) async {
        isRefreshing = true
        lastError = nil
        statusMessage = "Fetching Bing wallpaper…"

        defer {
            if generation == refreshGeneration {
                isRefreshing = false
            }
        }

        do {
            let image = try await bingService.fetchToday()
            guard generation == refreshGeneration else { return }

            currentImage = image

            let lastHash = UserDefaults.standard.string(forKey: DefaultsKey.lastAppliedHash)
            if !force, lastHash == image.hsh {
                statusMessage = "Already up to date"
                return
            }

            statusMessage = "Downloading…"
            let fileURL = wallpaperService.localFileURL(for: image)
            try await bingService.download(image, to: fileURL)
            guard generation == refreshGeneration else { return }

            statusMessage = "Setting wallpaper…"
            try wallpaperService.setDesktopImage(at: fileURL)

            UserDefaults.standard.set(image.hsh, forKey: DefaultsKey.lastAppliedHash)
            UserDefaults.standard.set(image.startdate, forKey: DefaultsKey.lastAppliedDate)

            statusMessage = "Updated · \(image.displayDate)"
        } catch {
            guard generation == refreshGeneration, !Self.isCancellation(error) else { return }
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
