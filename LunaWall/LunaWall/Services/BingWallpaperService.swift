import Foundation

enum BingWallpaperError: LocalizedError {
    case invalidResponse
    case emptyArchive
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Bing returned an invalid response."
        case .emptyArchive:
            return "No Bing wallpaper is available right now."
        case .downloadFailed:
            return "Failed to download the wallpaper image."
        }
    }
}

struct BingWallpaperService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches Bing homepage images. `idx` 0 is today; higher values go further back.
    func fetchImages(count: Int = 1, startingAt idx: Int = 0, market: String? = nil) async throws -> [BingImage] {
        var components = URLComponents(string: "https://www.bing.com/HPImageArchive.aspx")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "js"),
            URLQueryItem(name: "idx", value: String(idx)),
            URLQueryItem(name: "n", value: String(max(1, min(count, 8)))),
            URLQueryItem(name: "mkt", value: market ?? preferredMarket),
            URLQueryItem(name: "uhd", value: "1"),
        ]

        guard let url = components.url else {
            throw BingWallpaperError.invalidResponse
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BingWallpaperError.invalidResponse
        }

        let archive = try JSONDecoder().decode(BingArchiveResponse.self, from: data)
        guard !archive.images.isEmpty else {
            throw BingWallpaperError.emptyArchive
        }
        return archive.images
    }

    func fetchToday(market: String? = nil) async throws -> BingImage {
        let images = try await fetchImages(count: 1, startingAt: 0, market: market)
        guard let today = images.first else {
            throw BingWallpaperError.emptyArchive
        }
        return today
    }

    func download(_ image: BingImage, to destination: URL) async throws {
        let (tempURL, response) = try await session.download(from: image.wallpaperURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BingWallpaperError.downloadFailed
        }

        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    private var preferredMarket: String {
        Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    }
}
