import SwiftUI

@main
struct LunaWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("LunaWall", systemImage: "photo.on.rectangle.angled") {
            MenuBarExtraContent(appState: AppDelegate.sharedState)
        }
        .menuBarExtraStyle(.window)
    }
}

/// MenuBarExtra often fails to refresh @Observable trees; ObservedObject + local snapshot is reliable.
private struct MenuBarExtraContent: View {
    @ObservedObject var appState: AppState
    @State private var snapshot = MenuSnapshot()

    var body: some View {
        MenuBarView(appState: appState, snapshot: snapshot)
            .onAppear(perform: syncSnapshot)
            .onReceive(appState.objectWillChange) { _ in
                // Defer so @Published values are committed before we copy them.
                DispatchQueue.main.async(execute: syncSnapshot)
            }
            .task {
                // MenuBarExtra can drop Combine invalidations; poll lightly while open.
                while !Task.isCancelled {
                    syncSnapshot()
                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
    }

    private func syncSnapshot() {
        let next = MenuSnapshot(
            recentImages: appState.recentImages,
            currentImage: appState.currentImage,
            libraryRevision: appState.libraryRevision,
            statusMessage: appState.statusMessage,
            isRefreshing: appState.isRefreshing,
            lastError: appState.lastError,
            isPinned: appState.isPinned,
            autoRefreshEnabled: appState.autoRefreshEnabled,
            launchAtLoginEnabled: appState.launchAtLoginEnabled
        )
        if next != snapshot {
            snapshot = next
        }
        if appState.recentImages.isEmpty, !appState.isRefreshing {
            appState.refresh(force: false)
        }
    }
}

struct MenuSnapshot: Equatable {
    var recentImages: [BingImage] = []
    var currentImage: BingImage?
    var libraryRevision = 0
    var statusMessage = "Ready"
    var isRefreshing = false
    var lastError: String?
    var isPinned = false
    var autoRefreshEnabled = true
    var launchAtLoginEnabled = false
}
