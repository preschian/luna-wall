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
    public static IReadOnlyList<BingImage> MergeAndSave(IEnumerable<BingImage> incoming)
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

            var merged = SortNewestFirst(byHash.Values);
            try
            {
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
                File.WriteAllText(Path, JsonSerializer.Serialize(merged, JsonOptions));
            }
            catch
            {
                // best effort — in-memory merge still returned
            }

            return merged;
        }
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
