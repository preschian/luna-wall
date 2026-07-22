import AppKit
import SwiftUI

enum AppWindowID {
    static let main = "main"
}

/// Bridges AppKit reopen / menu-bar actions to SwiftUI `openWindow`.
@MainActor
enum OpenMainWindow {
    static var action: OpenWindowAction?

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let action {
            action(id: AppWindowID.main)
            return
        }
        if let window = NSApp.windows.first(where: { $0.canBecomeMain || $0.canBecomeKey }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func register(_ openWindow: OpenWindowAction) {
        action = openWindow
    }
}
