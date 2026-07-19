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
}
