import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            details
            Divider()
            controls
            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LunaWall")
                    .font(.headline)
                Text(appState.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if appState.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        if let image = appState.currentImage {
            VStack(alignment: .leading, spacing: 6) {
                Text(image.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(image.copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(image.displayDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text("No wallpaper loaded yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                appState.refresh(force: true)
            } label: {
                Label("Refresh Now", systemImage: "arrow.clockwise")
            }
            .disabled(appState.isRefreshing)
            .keyboardShortcut("r")

            Toggle("Auto-refresh daily", isOn: $appState.autoRefreshEnabled)

            Toggle("Launch at login", isOn: Binding(
                get: { appState.launchAtLoginEnabled },
                set: { appState.toggleLaunchAtLogin($0) }
            ))

            if appState.currentImage?.infoURL != nil {
                Button {
                    appState.openCopyrightPage()
                } label: {
                    Label("About This Image", systemImage: "safari")
                }
            }

            Divider()

            Button("Quit LunaWall") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
