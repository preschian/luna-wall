import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    private enum DefaultsKey {
        static let lastAppliedHash = "lastAppliedHash"
        static let lastAppliedDate = "lastAppliedDate"
        static let autoRefreshEnabled = "autoRefreshEnabled"
        static let pinnedHash = "pinnedHash"
        static let retentionDays = "retentionDays"
    }

    private enum TargetPolicy: Sendable {
        case followPin
        case forceToday
        case exact(BingImage)
    }

    /// Number of recent Bing days to fetch (API caps at 8).
    static let historyCount = 8

    @Published var currentImage: BingImage?
    @Published var recentImages: [BingImage] = []
    @Published var statusMessage = "Ready"
    @Published var isRefreshing = false
    @Published var isWarmingLibrary = false
    @Published var lastError: String?
    @Published var autoRefreshEnabled: Bool {
        didSet { UserDefaults.standard.set(autoRefreshEnabled, forKey: DefaultsKey.autoRefreshEnabled) }
    }
    /// When set, auto-refresh keeps this image instead of switching to today’s.
    @Published var pinnedHash: String? {
        didSet { UserDefaults.standard.set(pinnedHash, forKey: DefaultsKey.pinnedHash) }
    }
    @Published var launchAtLoginEnabled: Bool
    /// Days of catalog history to keep; 0 keeps everything.
    @Published var retentionDays: Int {
        didSet {
            guard retentionDays != oldValue else { return }
            UserDefaults.standard.set(retentionDays, forKey: DefaultsKey.retentionDays)
            recentImages = LibraryStore.trim(retentionDays: retentionDays)
            wallpaperService.evict(except: recentImages)
        }
    }

    var isPinned: Bool { pinnedHash != nil }

    private let bingService = BingWallpaperService()
    private let wallpaperService = WallpaperService()
    private var operationTask: Task<Void, Never>?
    private var libraryTask: Task<Void, Never>?
    private var operationGeneration = 0
    private var libraryGeneration = 0
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var didStart = false
    private var consecutiveRefreshFailures = 0
    private var earliestRetryAt: Date?

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.autoRefreshEnabled) == nil {
            defaults.set(true, forKey: DefaultsKey.autoRefreshEnabled)
        }
        autoRefreshEnabled = defaults.bool(forKey: DefaultsKey.autoRefreshEnabled)
        pinnedHash = defaults.string(forKey: DefaultsKey.pinnedHash)
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled
        retentionDays = defaults.integer(forKey: DefaultsKey.retentionDays)
        recentImages = LibraryStore.load()
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
        libraryGeneration += 1
        operationTask?.cancel()
        operationTask = nil
        libraryTask?.cancel()
        libraryTask = nil
        isRefreshing = false
        isWarmingLibrary = false
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        didStart = false
    }

    /// Fetches recent images and applies the pinned day, or today’s wallpaper when unpinned.
    func refresh(force: Bool) {
        beginOperation { generation in
            await self.performOperation(force: force, policy: .followPin, generation: generation)
        }
    }

    /// Applies a specific archive image. Pins past days so auto-refresh won’t replace them.
    func applyImage(_ image: BingImage) {
        beginOperation { generation in
            await self.performOperation(force: true, policy: .exact(image), generation: generation)
        }
    }

    /// Resumes following today’s Bing image. Clears the pin only after today applies successfully.
    func followToday() {
        beginOperation { generation in
            await self.performOperation(force: true, policy: .forceToday, generation: generation)
        }
    }

    func fileURL(for image: BingImage) -> URL {
        wallpaperService.localFileURL(for: image)
    }

    func thumbnailURL(for image: BingImage) -> URL {
        wallpaperService.thumbnailFileURL(for: image)
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

    func openCopyrightPage(for image: BingImage? = nil) {
        guard let url = (image ?? currentImage)?.infoURL else { return }
        NSWorkspace.shared.open(url)
    }

    var cacheDirectory: URL { wallpaperService.storageDirectory }

    /// Reveals the cached file for `image`, falling back to the cache folder itself.
    func revealInFinder(_ image: BingImage?) {
        let fileURL = image.map { wallpaperService.localFileURL(for: $0) }
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.open(cacheDirectory)
        }
    }

    /// Holds the applied image on the desktop even once Bing rolls over to a new day.
    func pinCurrent() {
        pinnedHash = currentImage?.hsh
    }

    /// "1.4 GB cached across 214 images. …" — the settings footer.
    func cacheSummary() -> String {
        let usage = wallpaperService.cacheUsage()
        let size = ByteCountFormatter.string(fromByteCount: usage.bytes, countStyle: .file)
        return "\(size) cached across \(recentImages.count) images (\(usage.files) files). "
            + "Thumbnails are kept; full-resolution files older than a year can be re-downloaded on demand."
    }

    /// Frees space by deleting full-resolution files over a year old; thumbnails stay.
    func cleanUpCache() {
        wallpaperService.deleteFullResolution(
            olderThan: LibraryStore.dateKey(daysAgo: 365),
            keep: currentImage,
            library: recentImages
        )
        lastError = nil
    }

    private func beginOperation(_ work: @escaping @MainActor (Int) async -> Void) {
        operationTask?.cancel()
        libraryTask?.cancel()
        operationGeneration += 1
        libraryGeneration += 1
        let generation = operationGeneration
        isRefreshing = true
        isWarmingLibrary = false
        lastError = nil
        operationTask = Task {
            defer {
                if generation == operationGeneration {
                    isRefreshing = false
                }
            }
            await work(generation)
        }
    }

    private func performOperation(force: Bool, policy: TargetPolicy, generation: Int) async {
        if !force, let earliestRetryAt, Date() < earliestRetryAt {
            statusMessage = "Waiting to retry…"
            return
        }

        statusMessage = "Fetching Bing wallpaper…"

        do {
            let images = try await bingService.fetchImages(count: Self.historyCount)
            guard generation == operationGeneration else { return }

            consecutiveRefreshFailures = 0
            earliestRetryAt = nil
            // Bing only serves 8 days; merge them into the catalog so the library keeps growing.
            recentImages = LibraryStore.mergeAndSave(images, retentionDays: retentionDays)

            guard let today = images.first else {
                throw BingWallpaperError.emptyArchive
            }

            let target = Self.resolveTarget(images: recentImages, today: today, pinnedHash: pinnedHash, policy: policy)
            let lastHash = UserDefaults.standard.string(forKey: DefaultsKey.lastAppliedHash)
            let fileURL = wallpaperService.localFileURL(for: target)
            let cachePresent = FileManager.default.fileExists(atPath: fileURL.path)

            if !force, lastHash == target.hsh, cachePresent {
                currentImage = target
                applyPinPolicy(applied: target, today: today)
                statusMessage = pinnedHash == nil
                    ? "Already up to date"
                    : "Pinned · \(target.displayDate)"
            } else {
                try await applyWallpaper(target, today: today, generation: generation)
            }

            guard generation == operationGeneration else { return }
            scheduleLibraryWarmup(images)
        } catch {
            guard generation == operationGeneration, !Self.isCancellation(error) else { return }
            consecutiveRefreshFailures += 1
            let delay = min(pow(2.0, Double(min(consecutiveRefreshFailures, 5))), 60)
            earliestRetryAt = Date().addingTimeInterval(delay)
            lastError = error.localizedDescription
            statusMessage = "Update failed"
        }
    }

    private static func resolveTarget(
        images: [BingImage],
        today: BingImage,
        pinnedHash: String?,
        policy: TargetPolicy
    ) -> BingImage {
        switch policy {
        case .forceToday:
            return today
        case .exact(let requested):
            return images.first(where: { $0.hsh == requested.hsh }) ?? requested
        case .followPin:
            if let pinnedHash, let pinned = images.first(where: { $0.hsh == pinnedHash }) {
                return pinned
            }
            return today
        }
    }

    private func applyPinPolicy(applied: BingImage, today: BingImage) {
        // Past days always pin; today only stays pinned when the user pinned it explicitly.
        if applied.hsh == today.hsh, pinnedHash != applied.hsh {
            pinnedHash = nil
        } else {
            pinnedHash = applied.hsh
        }
    }

    private func applyWallpaper(_ image: BingImage, today: BingImage, generation: Int) async throws {
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
        applyPinPolicy(applied: image, today: today)
        statusMessage = pinnedHash == nil
            ? "Updated · \(image.displayDate)"
            : "Pinned · \(image.displayDate)"
    }

    /// Downloads missing archive images and thumbs after the desktop target is handled.
    private func scheduleLibraryWarmup(_ images: [BingImage]) {
        libraryTask?.cancel()
        libraryGeneration += 1
        let generation = libraryGeneration
        libraryTask = Task {
            await self.warmupLibrary(images, generation: generation)
        }
    }

    private func warmupLibrary(_ images: [BingImage], generation: Int) async {
        isWarmingLibrary = true
        defer {
            if generation == libraryGeneration {
                isWarmingLibrary = false
            }
        }

        let pending = images.filter {
            !FileManager.default.fileExists(atPath: wallpaperService.localFileURL(for: $0).path)
        }

        if !pending.isEmpty {
            statusMessage = "Downloading library 0/\(pending.count)…"
            var finished = 0
            var failures = 0

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
                    guard generation == libraryGeneration else {
                        group.cancelAll()
                        return
                    }
                    if success {
                        finished += 1
                    } else {
                        failures += 1
                    }
                    statusMessage = "Downloading library \(finished)/\(pending.count)…"
                }
            }

            if failures > 0, finished == 0 {
                lastError = "Could not download the wallpaper library."
            } else if failures > 0 {
                lastError = "Some library downloads failed (\(failures))."
            }
        }

        guard generation == libraryGeneration else { return }

        for image in images {
            guard generation == libraryGeneration else { return }
            let source = wallpaperService.localFileURL(for: image)
            let thumb = wallpaperService.thumbnailFileURL(for: image)
            _ = await WallpaperService.loadThumbnailImage(source: source, destination: thumb)
        }

        guard generation == libraryGeneration else { return }
        // Keep every catalog day; only orphan files outside the catalog are dropped.
        wallpaperService.evict(except: recentImages)

        if pinnedHash == nil {
            statusMessage = currentImage.map { "Updated · \($0.displayDate)" } ?? "Ready"
        } else if let currentImage {
            statusMessage = "Pinned · \(currentImage.displayDate)"
        }
    }

    private nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func startScheduler() {
        timer?.invalidate()
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
