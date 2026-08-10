import AppKit
import SwiftUI

struct MainWindowView: View {
    private enum Pane {
        case home, library, settings
    }

    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    @State private var pane: Pane = .home
    @State private var detailIndex: Int?
    @State private var query = ""
    @State private var pinnedOnly = false

    private let gridColumns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 14)]

    var body: some View {
        ZStack {
            Theme.shell
            switch pane {
            case .home: home
            case .library: library
            case .settings: settings
            }
            if let image = detailImage {
                detailOverlay(image)
            }
        }
        .frame(minWidth: 880, minHeight: 640)
        .preferredColorScheme(.dark)
        // Register once at launch so Dock reopen works after the window is closed.
        .onAppear { OpenMainWindow.register(openWindow) }
    }

    // MARK: - Home

    private var home: some View {
        VStack(spacing: 0) {
            hero
            recentStrip
        }
    }

    private var hero: some View {
        ZStack {
            if let image = appState.currentImage {
                LibraryThumbnail(
                    sourceURL: appState.fileURL(for: image),
                    thumbnailURL: appState.thumbnailURL(for: image),
                    fullSize: true
                )
            } else {
                Theme.tile
            }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.32),
                    .init(color: Theme.scrim.opacity(0.45), location: 0.62),
                    .init(color: Theme.scrim.opacity(0.92), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .top) { heroTopBar }
        .overlay(alignment: .bottom) { heroCaption }
    }

    private var heroTopBar: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(statusLabel)
                .font(Theme.mono(11, .medium))
                .kerning(0.4)
                .foregroundStyle(appState.isPinned ? Theme.pinned : Theme.amber)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.14)))

            Spacer(minLength: 12)

            Button("Refresh") { appState.refresh(force: true) }
                .disabled(appState.isRefreshing)
            Button("Library") { pane = .library }
            Button("Settings") { pane = .settings }
        }
        .buttonStyle(GhostButtonStyle(glass: true))
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private var heroCaption: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                if let image = appState.currentImage {
                    Text(image.displayDate.uppercased())
                        .font(Theme.mono(11, .medium))
                        .kerning(1.1)
                        .foregroundStyle(Theme.amber)
                    Text(image.displayTitle)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                    Text(image.copyright)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.62))
                        .textSelection(.enabled)
                } else {
                    Text(appState.isRefreshing ? "Loading today’s wallpaper…" : "No wallpaper loaded yet.")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                if let error = appState.lastError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.pinned)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: 660, alignment: .leading)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                if appState.isPinned {
                    Button("Follow today") { appState.followToday() }
                        .buttonStyle(GhostButtonStyle(size: 13))
                        .disabled(appState.isRefreshing)
                } else {
                    Button("Pin this day") { appState.pinCurrent() }
                        .buttonStyle(AmberButtonStyle())
                        .disabled(appState.currentImage == nil)
                }
                Button("View full") { detailIndex = currentIndex ?? 0 }
                    .buttonStyle(GhostButtonStyle(size: 13))
                    .disabled(appState.recentImages.isEmpty)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
    }

    private var recentStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last \(appState.recentImages.count) days")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Button {
                    pane = .library
                } label: {
                    Text("BING ARCHIVE · \(appState.recentImages.count) IMAGES →")
                        .font(Theme.mono(11))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .buttonStyle(.plain)
            }

            if appState.recentImages.isEmpty {
                Text(appState.isRefreshing ? "Loading…" : "No recent images yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(height: 70)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(appState.recentImages.enumerated()), id: \.element.id) { index, image in
                        tile(image, index: index, style: .compact)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .background(Theme.shell)
    }

    // MARK: - Library

    private var library: some View {
        VStack(spacing: 0) {
            appliedBar(alternate: ("Library", Pane.library))
            librarySearchBar
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ForEach(shelves, id: \.key) { shelf in
                        VStack(alignment: .leading, spacing: 13) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(shelf.month)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Rectangle()
                                    .fill(Theme.hairline)
                                    .frame(height: 1)
                                Text("\(shelf.items.count) DAYS")
                                    .font(Theme.mono(11))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 14) {
                                ForEach(shelf.items, id: \.element.id) { index, image in
                                    tile(image, index: index, style: .full)
                                }
                            }
                        }
                    }
                    if shelves.isEmpty {
                        Text(appState.recentImages.isEmpty ? "Loading catalog…" : "No images match this filter.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
        }
    }

    private var librarySearchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("/")
                    .font(Theme.mono(12))
                    .foregroundStyle(.white.opacity(0.35))
                TextField("Search titles, places, photographers…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.09)))

            HStack(spacing: 0) {
                chip("All \(appState.recentImages.count)", active: !pinnedOnly) { pinnedOnly = false }
                chip("Pinned \(pinnedCount)", active: pinnedOnly) { pinnedOnly = true }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.13)))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Theme.shell)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? .white : .white.opacity(0.5))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(active ? Color.white.opacity(0.12) : .clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Settings

    private var settings: some View {
        VStack(spacing: 0) {
            appliedBar(alternate: ("Settings", Pane.settings))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Auto-checks every 30 minutes and after your Mac wakes.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 4)
                        .padding(.bottom, 26)

                    VStack(spacing: 0) {
                        settingRow(
                            title: "Follow today automatically",
                            subtitle: "Swap the desktop each morning unless a day is pinned."
                        ) {
                            Toggle("", isOn: $appState.autoRefreshEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(Theme.amber)
                        }
                        Divider().overlay(Theme.hairline)
                        settingRow(
                            title: "Launch at login",
                            subtitle: "Start LunaWall in the menu bar when you log in."
                        ) {
                            Toggle("", isOn: Binding(
                                get: { appState.launchAtLoginEnabled },
                                set: { appState.toggleLaunchAtLogin($0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(Theme.amber)
                        }
                        Divider().overlay(Theme.hairline)
                        settingRow(
                            title: "Cache folder",
                            subtitle: appState.cacheDirectory.path,
                            monoSubtitle: true
                        ) {
                            Button("Open") { appState.revealInFinder(nil) }
                                .buttonStyle(GhostButtonStyle())
                        }
                    }
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.07)))

                    Text("Bing serves 8 days; LunaWall caches that window and drops files once they leave it.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        )
                        .padding(.top, 26)
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 30)
            }
        }
    }

    private func settingRow(
        title: String,
        subtitle: String,
        monoSubtitle: Bool = false,
        @ViewBuilder control: () -> some View
    ) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(monoSubtitle ? Theme.mono(12) : .system(size: 12))
                    .foregroundStyle(.white.opacity(0.42))
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    // MARK: - Shared chrome

    /// Compact "what is on the desktop" bar shown above Library and Settings.
    private func appliedBar(alternate: (String, Pane)) -> some View {
        HStack(spacing: 16) {
            Button {
                pane = .home
            } label: {
                Group {
                    if let image = appState.currentImage {
                        LibraryThumbnail(
                            sourceURL: appState.fileURL(for: image),
                            thumbnailURL: appState.thumbnailURL(for: image)
                        )
                    } else {
                        Theme.tile
                    }
                }
                .frame(width: 74, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(appState.currentImage?.displayTitle ?? "Loading…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.isPinned ? Theme.pinned : Theme.amber)
                        .frame(width: 6, height: 6)
                    Text(appState.statusMessage.uppercased())
                        .font(Theme.mono(11))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button("Today") { pane = .home }
                if alternate.1 == .settings {
                    Button("Library") { pane = .library }
                } else {
                    Button("Settings") { pane = .settings }
                }
            }
            .buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Theme.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private enum TileStyle {
        case compact, full
    }

    private func tile(_ image: BingImage, index: Int, style: TileStyle) -> some View {
        let isCurrent = appState.currentImage?.hsh == image.hsh
        return Button {
            detailIndex = index
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                LibraryThumbnail(
                    sourceURL: appState.fileURL(for: image),
                    thumbnailURL: appState.thumbnailURL(for: image)
                )
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: style == .compact ? 6 : 7))
                .overlay {
                    RoundedRectangle(cornerRadius: style == .compact ? 6 : 7)
                        .strokeBorder(isCurrent ? Theme.amber : Color.white.opacity(0.09), lineWidth: isCurrent ? 2 : 1)
                }
                .overlay(alignment: .topLeading) {
                    if style == .full {
                        Text(image.dayLabel)
                            .font(Theme.mono(10, .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if appState.pinnedHash == image.hsh {
                        Text("◆")
                            .font(Theme.mono(10, .medium))
                            .foregroundStyle(Theme.amber)
                            .padding(7)
                    }
                }

                switch style {
                case .compact:
                    Text(image.shortLabel)
                        .font(Theme.mono(10))
                        .foregroundStyle(isCurrent ? Theme.amber : .white.opacity(0.42))
                        .lineLimit(1)
                case .full:
                    Text(image.displayTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCurrent ? "Currently applied" : "Open \(image.displayTitle)")
    }

    // MARK: - Detail

    private func detailOverlay(_ image: BingImage) -> some View {
        ZStack {
            Rectangle()
                .fill(Theme.scrim.opacity(0.72))
                .onTapGesture { detailIndex = nil }

            VStack(spacing: 0) {
                ZStack {
                    LibraryThumbnail(
                        sourceURL: appState.fileURL(for: image),
                        thumbnailURL: appState.thumbnailURL(for: image),
                        fullSize: true
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    circleButton("✕") { detailIndex = nil }
                        .padding(14)
                }
                .overlay(alignment: .leading) {
                    circleButton("‹") { step(-1) }
                        .padding(.leading, 14)
                        .disabled(detailIndex == 0)
                }
                .overlay(alignment: .trailing) {
                    circleButton("›") { step(1) }
                        .padding(.trailing, 14)
                        .disabled(detailIndex == appState.recentImages.count - 1)
                }

                HStack(alignment: .bottom, spacing: 26) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(image.displayDate.uppercased()) · UHD")
                            .font(Theme.mono(11, .medium))
                            .kerning(1.1)
                            .foregroundStyle(Theme.amber)
                        Text(image.displayTitle)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                        Text(image.copyright)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 9) {
                        Button("Set as wallpaper") {
                            appState.applyImage(image)
                            detailIndex = nil
                            pane = .home
                        }
                        .buttonStyle(AmberButtonStyle())
                        .disabled(appState.isRefreshing)

                        Button("Open folder") { appState.revealInFinder(image) }
                            .buttonStyle(GhostButtonStyle(size: 13))
                        if image.infoURL != nil {
                            Button("About") { appState.openCopyrightPage(for: image) }
                                .buttonStyle(GhostButtonStyle(size: 13))
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 20)
                .background(Theme.bar)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
            .padding(.horizontal, 56)
            .padding(.vertical, 44)
        }
    }

    private func circleButton(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func step(_ delta: Int) {
        guard let index = detailIndex else { return }
        detailIndex = min(max(index + delta, 0), appState.recentImages.count - 1)
    }

    // MARK: - Derived state

    private var detailImage: BingImage? {
        guard let index = detailIndex, appState.recentImages.indices.contains(index) else { return nil }
        return appState.recentImages[index]
    }

    private var currentIndex: Int? {
        appState.recentImages.firstIndex { $0.hsh == appState.currentImage?.hsh }
    }

    private var pinnedCount: Int {
        appState.recentImages.filter { $0.hsh == appState.pinnedHash }.count
    }

    private var statusLabel: String {
        if appState.isRefreshing { return "● CHECKING BING…" }
        return appState.isPinned ? "◆ PINNED · AUTO-REFRESH HELD" : "● LIVE · FOLLOWING TODAY"
    }

    /// Library rows grouped by month, keeping each image's index into `recentImages`.
    private var shelves: [(key: String, month: String, items: [(offset: Int, element: BingImage)])] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = appState.recentImages.enumerated().filter { _, image in
            let matchesQuery = needle.isEmpty
                || image.displayTitle.lowercased().contains(needle)
                || image.copyright.lowercased().contains(needle)
            return matchesQuery && (!pinnedOnly || image.hsh == appState.pinnedHash)
        }
        var order: [String] = []
        var groups: [String: [(offset: Int, element: BingImage)]] = [:]
        for match in matches {
            let key = match.element.monthKey
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]?.append(match)
        }
        return order.map { key in
            (key: key, month: groups[key]?.first?.element.monthLabel ?? key, items: groups[key] ?? [])
        }
    }
}
