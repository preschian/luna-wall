import AppKit
import Foundation

enum WallpaperServiceError: LocalizedError {
    case noScreens
    case setFailed(String)

    var errorDescription: String? {
        switch self {
        case .noScreens:
            return "No displays are available."
        case .setFailed(let message):
            return message
        }
    }
}

struct WallpaperService {
    var storageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LunaWall", isDirectory: true)
    }

    func localFileURL(for image: BingImage) -> URL {
        storageDirectory.appendingPathComponent("\(image.startdate)-\(image.hsh).jpg")
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
