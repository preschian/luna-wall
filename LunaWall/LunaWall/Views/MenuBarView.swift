import AppKit
import SwiftUI

/// Lightweight menu bar entry point — primary UI lives in `MainWindowView`.
struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show LunaWall") {
            OpenMainWindow.show()
        }
        .keyboardShortcut("o")

        Divider()

        if let image = appState.currentImage {
            Text(image.displayTitle)
            Text(image.displayDate)
            if appState.isPinned {
                Text("Pinned")
            }
        } else {
            Text("No wallpaper loaded yet.")
        }

        Text(appState.statusMessage)

        Divider()

        Button("Refresh Now") {
            appState.refresh(force: true)
        }
        .keyboardShortcut("r")
        .disabled(appState.isRefreshing)

        if appState.isPinned {
            Button("Follow Today") {
                appState.followToday()
            }
            .disabled(appState.isRefreshing)
        }

        Divider()

        Button("Quit LunaWall") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        .onAppear {
            OpenMainWindow.register(openWindow)
        }
    }
}
