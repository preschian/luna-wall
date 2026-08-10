using System.Text.Json;
using LunaWall.Models;

namespace LunaWall.Services;

/// <summary>
/// Persists every Bing day LunaWall has seen so Recent can grow beyond the API's 8-image window.
/// </summary>
internal static class LibraryStore
{
    private static readonly object Gate = new();
    private static readonly string Path = System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "LunaWall",
        "library.json");

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };

    public static IReadOnlyList<BingImage> Load()
    {
        lock (Gate) return LoadUnlocked();
    }

    /// <summary>
    /// Upserts <paramref name="incoming"/> by hash, keeps older entries, and returns newest-first.
    /// </summary>
    /// <param name="retentionDays">Drop entries older than this many days; 0 keeps everything.</param>
    public static IReadOnlyList<BingImage> MergeAndSave(IEnumerable<BingImage> incoming, int retentionDays = 0)
    {
        lock (Gate)
        {
            var byHash = new Dictionary<string, BingImage>(StringComparer.Ordinal);
            foreach (var image in LoadUnlocked())
            {
                if (!string.IsNullOrWhiteSpace(image.Hash))
                    byHash[image.Hash] = image;
            }

            foreach (var image in incoming)
            {
                if (string.IsNullOrWhiteSpace(image.Hash)) continue;
                byHash[image.Hash] = image;
            }

            return SaveUnlocked(ApplyRetention(SortNewestFirst(byHash.Values), retentionDays));
        }
    }

    /// <summary>Re-applies a retention window to what is already on disk.</summary>
    public static IReadOnlyList<BingImage> Trim(int retentionDays)
    {
        lock (Gate) return SaveUnlocked(ApplyRetention(LoadUnlocked(), retentionDays));
    }

    private static List<BingImage> ApplyRetention(IReadOnlyList<BingImage> images, int retentionDays)
    {
        if (retentionDays <= 0) return images.ToList();
        var cutoff = DateTime.Today.AddDays(-retentionDays).ToString("yyyyMMdd");
        return images.Where(i => string.CompareOrdinal(i.StartDate, cutoff) >= 0).ToList();
    }

    private static IReadOnlyList<BingImage> SaveUnlocked(List<BingImage> images)
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
            File.WriteAllText(Path, JsonSerializer.Serialize(images, JsonOptions));
        }
        catch
        {
            // best effort — the in-memory list is still returned
        }

        return images;
    }

    private static IReadOnlyList<BingImage> LoadUnlocked()
    {
        try
        {
            if (!File.Exists(Path)) return [];
            var json = File.ReadAllText(Path);
            var images = JsonSerializer.Deserialize<List<BingImage>>(json, JsonOptions);
            return SortNewestFirst(images ?? []);
        }
        catch
        {
            return [];
        }
    }

    private static List<BingImage> SortNewestFirst(IEnumerable<BingImage> images) =>
        images
            .OrderByDescending(i => i.StartDate, StringComparer.Ordinal)
            .ThenBy(i => i.Hash, StringComparer.Ordinal)
            .ToList();
}
