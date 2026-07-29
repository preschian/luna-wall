import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Single shared state so SwiftUI’s adaptor instance and the real NSApp delegate stay in sync.
    static let sharedState = AppState()

    var appState: AppState { Self.sharedState }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.sharedState.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.sharedState.stop()
    }

    /// Keep the process alive for menu-bar quick actions and scheduled refresh.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Re-open the main window when the Dock icon is clicked after all windows were closed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            OpenMainWindow.show()
        }
        return true
    }
}
