import Foundation

/// Persists every Bing day LunaWall has seen so the library can grow beyond the API's 8-image window.
/// Mirrors `LunaWall.Windows/Services/LibraryStore.cs`.
enum LibraryStore {
    // ponytail: called from the main actor only; add a queue if a background writer shows up.
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("LunaWall", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    static func load() -> [BingImage] {
        guard let data = try? Data(contentsOf: fileURL),
              let images = try? JSONDecoder().decode([BingImage].self, from: data)
        else {
            return []
        }
        return sortNewestFirst(images)
    }

    /// Upserts `incoming` by hash, keeps older entries, and returns the catalog newest-first.
    /// `retentionDays` of 0 keeps everything.
    @discardableResult
    static func mergeAndSave(_ incoming: [BingImage], retentionDays: Int) -> [BingImage] {
        save(merge(existing: load(), incoming: incoming, retentionDays: retentionDays))
    }

    static func merge(existing: [BingImage], incoming: [BingImage], retentionDays: Int) -> [BingImage] {
        var byHash = Dictionary(existing.map { ($0.hsh, $0) }, uniquingKeysWith: { _, new in new })
        for image in incoming where !image.hsh.isEmpty {
            byHash[image.hsh] = image
        }
        return applyRetention(sortNewestFirst(Array(byHash.values)), retentionDays: retentionDays)
    }

    /// Re-applies a retention window to what is already on disk.
    @discardableResult
    static func trim(retentionDays: Int) -> [BingImage] {
        save(applyRetention(load(), retentionDays: retentionDays))
    }

    private static func applyRetention(_ images: [BingImage], retentionDays: Int) -> [BingImage] {
        guard retentionDays > 0 else { return images }
        let cutoff = Self.dateKey(daysAgo: retentionDays)
        return images.filter { $0.startdate >= cutoff }
    }

    /// `yyyyMMdd` key for "today minus `daysAgo`", matching Bing's `startdate` format.
    static func dateKey(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func save(_ images: [BingImage]) -> [BingImage] {
        let url = fileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(images).write(to: url, options: .atomic)
        } catch {
            // best effort — the in-memory list is still returned
        }
        return images
    }

    private static func sortNewestFirst(_ images: [BingImage]) -> [BingImage] {
        images.sorted {
            $0.startdate == $1.startdate ? $0.hsh < $1.hsh : $0.startdate > $1.startdate
        }
    }

    #if DEBUG
    /// Runs at debug launch; the merge/retention rules are the only non-obvious logic here.
    static func selfCheck() {
        func image(_ date: String, _ hash: String) -> BingImage {
            BingImage(startdate: date, urlbase: "/th?id=\(hash)", copyright: "c", copyrightlink: "l", title: hash, hsh: hash)
        }

        let old = image("20250101", "a")
        let merged = merge(existing: [old, image("20260810", "b")], incoming: [image("20260810", "b"), image("20260811", "c")], retentionDays: 0)
        assert(merged.map(\.hsh) == ["c", "b", "a"], "merge must dedupe by hash and sort newest-first")

        let trimmed = merge(existing: [old], incoming: [image(dateKey(daysAgo: 1), "d")], retentionDays: 90)
        assert(trimmed.map(\.hsh) == ["d"], "retention must drop days outside the window")

        assert(merge(existing: [], incoming: [old], retentionDays: 0).count == 1, "retentionDays 0 keeps everything")
    }
    #endif
}
