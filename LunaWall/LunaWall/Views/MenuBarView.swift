import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            details
            if !appState.recentImages.isEmpty {
                Divider()
                recentHistory
            }
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
                HStack(spacing: 6) {
                    Text(image.displayDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if appState.isPinned {
                        Text("Pinned")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
            }
        } else {
            Text("No wallpaper loaded yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recentHistory: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(appState.recentImages) { image in
                        historyRow(for: image)
                    }
                }
            }
            .frame(maxHeight: 180)

            if appState.isPinned {
                Button {
                    appState.followToday()
                } label: {
                    Label("Follow Today", systemImage: "sun.max")
                }
                .disabled(appState.isRefreshing)
            }
        }
    }

    private func historyRow(for image: BingImage) -> some View {
        let isCurrent = appState.currentImage?.hsh == image.hsh
        return Button {
            appState.applyImage(image)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(image.title)
                        .font(.caption.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(image.displayDate)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(appState.isRefreshing || isCurrent)
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
