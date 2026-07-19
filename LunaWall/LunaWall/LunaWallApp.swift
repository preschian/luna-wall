import SwiftUI

@main
struct LunaWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("LunaWall", systemImage: "photo.on.rectangle.angled") {
            // Temporary MenuBarExtra adaptor — see github.com/preschian/luna-wall/issues/6.
            MenuBarExtraContent(appState: AppDelegate.sharedState)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Forces MenuBarExtra to redraw on @Published changes without polling or re-entrancy.
private struct MenuBarExtraContent: View {
    @ObservedObject var appState: AppState
    @State private var redrawToken = 0

    var body: some View {
        MenuBarView(appState: appState)
            .id(redrawToken)
            .onReceive(appState.objectWillChange) { _ in
                DispatchQueue.main.async {
                    redrawToken &+= 1
                }
            }
    }
}
