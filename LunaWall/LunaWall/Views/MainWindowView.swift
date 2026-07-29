import AppKit
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    private let historyColumns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    currentSection
                    historySection
                    settingsSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(.background)
        // Register once at launch so Dock reopen works after the window is closed.
        .onAppear {
            OpenMainWindow.register(openWindow)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LunaWall")
                    .font(.title2.weight(.semibold))
                Text(appState.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if appState.isRefreshing || appState.isWarmingLibrary {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                appState.refresh(force: true)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(appState.isRefreshing)
            .keyboardShortcut("r")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var currentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Wallpaper")
                .font(.headline)

            if let image = appState.currentImage {
                HStack(alignment: .top, spacing: 16) {
                    LibraryThumbnail(
                        sourceURL: appState.fileURL(for: image),
                        thumbnailURL: appState.thumbnailURL(for: image),
                        width: 280,
                        height: 158
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(image.displayTitle)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                        Text(image.copyright)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack(spacing: 8) {
                            Text(image.displayDate)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            if appState.isPinned {
                                Text("Pinned")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.orange)
                            }
                        }

                        HStack(spacing: 8) {
                            if appState.isPinned {
                                Button {
                                    appState.followToday()
                                } label: {
                                    Label("Follow Today", systemImage: "sun.max")
                                }
                                .disabled(appState.isRefreshing)
                            }

                            if image.infoURL != nil {
                                Button {
                                    appState.openCopyrightPage()
                                } label: {
                                    Label("About This Image", systemImage: "safari")
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(appState.isRefreshing ? "Loading wallpaper…" : "No wallpaper loaded yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.headline)

            if appState.recentImages.isEmpty {
                Text(appState.isRefreshing ? "Loading…" : "No recent images yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: historyColumns, spacing: 12) {
                    ForEach(appState.recentImages) { image in
                        historyCard(for: image)
                    }
                }
            }
        }
    }

    private func historyCard(for image: BingImage) -> some View {
        let isCurrent = appState.currentImage?.hsh == image.hsh
        return Button {
            appState.applyImage(image)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    LibraryThumbnail(
                        sourceURL: appState.fileURL(for: image),
                        thumbnailURL: appState.thumbnailURL(for: image),
                        width: 160,
                        height: 90
                    )
                    .frame(maxWidth: .infinity)
                    .clipped()

                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isCurrent ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: isCurrent ? 2 : 1
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(image.displayTitle)
                        .font(.caption.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(image.displayDate)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(appState.isRefreshing || isCurrent)
        .help(isCurrent ? "Currently applied" : "Apply and pin this wallpaper")
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.headline)

            Toggle("Auto-refresh daily", isOn: $appState.autoRefreshEnabled)

            Toggle("Launch at login", isOn: Binding(
                get: { appState.launchAtLoginEnabled },
                set: { appState.toggleLaunchAtLogin($0) }
            ))
        }
    }
}
