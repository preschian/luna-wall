import AppKit
import SwiftUI

struct LibraryThumbnail: View {
    let sourceURL: URL
    let thumbnailURL: URL
    var width: CGFloat = 64
    var height: CGFloat = 40

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .cornerRadius(4)
        .task(id: thumbnailURL.path) {
            image = await WallpaperService.loadThumbnailImage(
                source: sourceURL,
                destination: thumbnailURL
            )
        }
    }
}
