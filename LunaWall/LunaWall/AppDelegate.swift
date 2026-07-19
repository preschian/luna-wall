import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stop()
    }
}
