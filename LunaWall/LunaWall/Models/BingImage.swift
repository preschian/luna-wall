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
    /// Rejects `urlbase` values that could redirect the request off bing.com (e.g. `@evil.com`).
    var wallpaperURL: URL? {
        // Must be a root-relative Bing path such as `/th?id=OHR.…`.
        guard urlbase.hasPrefix("/"), !urlbase.hasPrefix("//"), !urlbase.contains("@") else {
            return nil
        }

        guard var components = URLComponents(string: "https://www.bing.com\(urlbase)_UHD.jpg") else {
            return nil
        }
        components.user = nil
        components.password = nil

        guard components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              Self.isBingHost(host),
              let url = components.url
        else {
            return nil
        }
        return url
    }

    /// Copyright / “about this image” link — https Bing hosts only.
    var infoURL: URL? {
        guard let url = URL(string: copyrightlink),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              Self.isBingHost(host)
        else {
            return nil
        }
        return url
    }

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        guard let date = formatter.date(from: startdate) else { return startdate }

        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = .current
        return formatter.string(from: date)
    }

    /// Some markets return a generic `title` like "Info"; prefer a useful caption for the UI.
    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty, trimmedTitle.caseInsensitiveCompare("Info") != .orderedSame {
            return trimmedTitle
        }
        let copyrightTitle = copyright.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (copyrightTitle?.isEmpty == false) ? copyrightTitle! : trimmedTitle
    }

    private static func isBingHost(_ host: String) -> Bool {
        host == "bing.com" || host.hasSuffix(".bing.com")
    }
}
