import SwiftUI

@main
struct LunaWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Primary UI: standard macOS window (see issue #6).
        Window("LunaWall", id: AppWindowID.main) {
            MainWindowView(appState: AppDelegate.sharedState)
        }
        .defaultSize(width: 780, height: 620)

        // Secondary entry: quick actions without opening the full window.
        MenuBarExtra("LunaWall", systemImage: "photo.on.rectangle.angled") {
            MenuBarView(appState: AppDelegate.sharedState)
        }
    }
}
