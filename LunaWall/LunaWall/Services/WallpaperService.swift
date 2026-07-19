import AppKit
import Foundation
import ImageIO

enum WallpaperServiceError: LocalizedError {
    case noScreens
    case setFailed(String)
    case thumbnailFailed

    var errorDescription: String? {
        switch self {
        case .noScreens:
            return "No displays are available."
        case .setFailed(let message):
            return message
        case .thumbnailFailed:
            return "Could not create a wallpaper thumbnail."
        }
    }
}

struct WallpaperService: Sendable {
    var storageDirectory: URL {
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        return base.appendingPathComponent("luna-wall", isDirectory: true)
    }

    var thumbnailDirectory: URL {
        storageDirectory.appendingPathComponent("thumbs", isDirectory: true)
    }

    func localFileURL(for image: BingImage) -> URL {
        let startdate = Self.sanitizePathComponent(image.startdate)
        let hash = Self.sanitizePathComponent(image.hsh)
        return storageDirectory.appendingPathComponent("\(startdate)-\(hash).jpg")
    }

    func thumbnailFileURL(for image: BingImage) -> URL {
        let startdate = Self.sanitizePathComponent(image.startdate)
        let hash = Self.sanitizePathComponent(image.hsh)
        return thumbnailDirectory.appendingPathComponent("\(startdate)-\(hash).jpg")
    }

    /// Keep wallpaper filenames inside `storageDirectory` even if archive fields are hostile.
    private static func sanitizePathComponent(_ value: String) -> String {
        let filtered = String(value.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return "_"
        })
        return filtered.isEmpty ? "unknown" : filtered
    }

    /// Removes cached wallpapers/thumbnails that are not part of the current archive window.
    func evict(except images: [BingImage]) {
        let keepWallpapers = Set(images.map { localFileURL(for: $0).lastPathComponent })
        let keepThumbs = Set(images.map { thumbnailFileURL(for: $0).lastPathComponent })
        Self.evictDirectory(storageDirectory, keeping: keepWallpapers, pathExtension: "jpg")
        Self.evictDirectory(thumbnailDirectory, keeping: keepThumbs, pathExtension: "jpg")
    }

    private static func evictDirectory(_ directory: URL, keeping: Set<String>, pathExtension: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for file in files where file.pathExtension.lowercased() == pathExtension {
            if !keeping.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Builds a small on-disk thumbnail for menu UI (off the caller’s actor).
    nonisolated static func ensureThumbnail(
        source: URL,
        destination: URL,
        maxPixelSize: CGFloat = 160
    ) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            return
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw WallpaperServiceError.thumbnailFailed
        }

        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let sourceImage = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw WallpaperServiceError.thumbnailFailed
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(sourceImage, 0, options as CFDictionary) else {
            throw WallpaperServiceError.thumbnailFailed
        }

        let tempURL = directory.appendingPathComponent(UUID().uuidString + ".thumb")
        guard let destinationImage = CGImageDestinationCreateWithURL(
            tempURL as CFURL,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            throw WallpaperServiceError.thumbnailFailed
        }
        CGImageDestinationAddImage(destinationImage, thumbnail, nil)
        guard CGImageDestinationFinalize(destinationImage) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw WallpaperServiceError.thumbnailFailed
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: destination)
        }
    }

    nonisolated static func loadThumbnailImage(source: URL, destination: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            do {
                try ensureThumbnail(source: source, destination: destination)
                return NSImage(contentsOf: destination)
            } catch {
                return nil
            }
        }.value
    }

    @MainActor
    func setDesktopImage(at fileURL: URL) throws {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw WallpaperServiceError.noScreens
        }

        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
            .allowClipping: true,
        ]

        for screen in screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(fileURL, for: screen, options: options)
            } catch {
                throw WallpaperServiceError.setFailed(error.localizedDescription)
            }
        }
    }
}
