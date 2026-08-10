import AppKit
import SwiftUI

/// Fills whatever frame the caller gives it; caller owns aspect ratio and clipping.
struct LibraryThumbnail: View {
    let sourceURL: URL
    let thumbnailURL: URL
    /// Loads the original file after the thumbnail, for the hero and the detail view.
    var fullSize = false

    @State private var image: NSImage?

    var body: some View {
        Rectangle()
            .fill(Theme.tile)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: thumbnailURL.path) {
                image = await WallpaperService.loadThumbnailImage(
                    source: sourceURL,
                    destination: thumbnailURL
                )
                guard fullSize, !Task.isCancelled else { return }
                // ponytail: decodes the whole UHD file; downsample if several full-size views coexist.
                if let full = await Self.loadFull(sourceURL) {
                    image = full
                }
            }
    }

    private static func loadFull(_ url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
    }
}
