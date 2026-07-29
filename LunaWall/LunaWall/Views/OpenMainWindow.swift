import AppKit
import SwiftUI

enum AppWindowID {
    static let main = "main"
}

/// AppKit Dock-reopen bridge. Registered from the main window (and menu bar as backup);
/// `OpenWindowAction` remains usable after the window is closed.
@MainActor
enum OpenMainWindow {
    private static var action: OpenWindowAction?

    static func register(_ openWindow: OpenWindowAction) {
        action = openWindow
    }

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        action?(id: AppWindowID.main)
    }
}
