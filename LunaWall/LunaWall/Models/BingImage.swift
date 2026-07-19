import Foundation

struct BingArchiveResponse: Decodable, Sendable {
    let images: [BingImage]
}

struct BingImage: Decodable, Identifiable, Sendable, Equatable {
    let startdate: String
    let urlbase: String
    let copyright: String
    let copyrightlink: String
    let title: String
    let hsh: String

    var id: String { hsh }

    /// Highest-resolution wallpaper URL Bing exposes publicly.
    var wallpaperURL: URL {
        URL(string: "https://www.bing.com\(urlbase)_UHD.jpg")!
    }

    var infoURL: URL? {
        URL(string: copyrightlink)
    }

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        guard let date = formatter.date(from: startdate) else { return startdate }

        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
