import SwiftUI

@main
struct LunaWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("LunaWall", systemImage: "photo.on.rectangle.angled") {
            MenuBarView(appState: appDelegate.appState)
        }
        .menuBarExtraStyle(.window)
    }
}
