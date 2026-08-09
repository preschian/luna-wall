using System.Globalization;
using System.Text.Json.Serialization;

namespace LunaWall.Models;

public sealed class BingArchiveResponse
{
    [JsonPropertyName("images")]
    public List<BingImage> Images { get; set; } = [];
}

public sealed class BingImage : IEquatable<BingImage>
{
    [JsonPropertyName("startdate")]
    public string StartDate { get; set; } = "";

    [JsonPropertyName("urlbase")]
    public string UrlBase { get; set; } = "";

    [JsonPropertyName("copyright")]
    public string Copyright { get; set; } = "";

    [JsonPropertyName("copyrightlink")]
    public string CopyrightLink { get; set; } = "";

    [JsonPropertyName("title")]
    public string Title { get; set; } = "";

    [JsonPropertyName("hsh")]
    public string Hash { get; set; } = "";

    public string Id => Hash;

    /// <summary>Highest-resolution wallpaper URL Bing exposes publicly.</summary>
    public Uri? WallpaperUrl
    {
        get
        {
            // Must be a root-relative Bing path such as `/th?id=OHR.…`.
            if (!UrlBase.StartsWith('/') || UrlBase.StartsWith("//") || UrlBase.Contains('@'))
                return null;

            if (!Uri.TryCreate($"https://www.bing.com{UrlBase}_UHD.jpg", UriKind.Absolute, out var url))
                return null;

            if (!string.Equals(url.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
                return null;

            if (url.UserInfo.Length > 0)
                return null;

            var host = url.Host.ToLowerInvariant();
            if (!IsBingHost(host))
                return null;

            return url;
        }
    }

    public Uri? InfoUrl
    {
        get
        {
            if (!Uri.TryCreate(CopyrightLink, UriKind.Absolute, out var url))
                return null;
            if (!string.Equals(url.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
                return null;
            var host = url.Host.ToLowerInvariant();
            return IsBingHost(host) ? url : null;
        }
    }

    public string DisplayDate
    {
        get
        {
            if (!DateTime.TryParseExact(
                    StartDate,
                    "yyyyMMdd",
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.None,
                    out var date))
            {
                return StartDate;
            }

            return date.ToString("d", CultureInfo.CurrentCulture);
        }
    }

    public string DisplayTitle
    {
        get
        {
            var trimmedTitle = Title.Trim();
            if (trimmedTitle.Length > 0 &&
                !string.Equals(trimmedTitle, "Info", StringComparison.OrdinalIgnoreCase))
            {
                return trimmedTitle;
            }

            var paren = Copyright.IndexOf('(');
            var copyrightTitle = (paren > 0 ? Copyright[..paren] : Copyright).Trim();
            return copyrightTitle.Length > 0 ? copyrightTitle : trimmedTitle;
        }
    }

    private static bool IsBingHost(string host) =>
        host == "bing.com" || host.EndsWith(".bing.com", StringComparison.Ordinal);

    public bool Equals(BingImage? other) => other is not null && Hash == other.Hash;

    public override bool Equals(object? obj) => obj is BingImage other && Equals(other);

    public override int GetHashCode() => Hash.GetHashCode(StringComparison.Ordinal);

    /// <summary>ponytail: one runnable check for URL sanitization.</summary>
    public static void SelfCheck()
    {
        var ok = new BingImage { UrlBase = "/th?id=OHR.Test_EN-US", CopyrightLink = "https://www.bing.com/search?q=a" };
        if (ok.WallpaperUrl is null) throw new Exception("expected safe urlbase");
        if (ok.InfoUrl is null) throw new Exception("expected safe copyright link");

        var bad = new BingImage { UrlBase = "@evil.com/x", CopyrightLink = "https://evil.com/x" };
        if (bad.WallpaperUrl is not null) throw new Exception("rejected hostile urlbase");
        if (bad.InfoUrl is not null) throw new Exception("rejected non-bing copyright link");
    }
}
