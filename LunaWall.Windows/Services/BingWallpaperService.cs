using System.Globalization;
using System.Net.Http;

namespace LunaWall.Services;

public sealed class BingWallpaperService
{
    private static readonly System.Text.Json.JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly System.Net.Http.HttpClient _http;

    public BingWallpaperService(System.Net.Http.HttpClient? http = null)
    {
        _http = http ?? new System.Net.Http.HttpClient { Timeout = TimeSpan.FromSeconds(60) };
    }

    public async Task<IReadOnlyList<Models.BingImage>> FetchImagesAsync(
        int count = 1,
        int startingAt = 0,
        string? market = null,
        CancellationToken cancellationToken = default)
    {
        var n = Math.Clamp(count, 1, 8);
        var mkt = market ?? PreferredMarket();
        var url =
            $"https://www.bing.com/HPImageArchive.aspx?format=js&idx={startingAt}&n={n}&mkt={Uri.EscapeDataString(mkt)}&uhd=1";

        using var response = await _http.GetAsync(url, cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException("Bing returned an invalid response.");

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        var archive = await System.Text.Json.JsonSerializer
            .DeserializeAsync<Models.BingArchiveResponse>(stream, JsonOptions, cancellationToken)
            .ConfigureAwait(false);

        if (archive is null || archive.Images.Count == 0)
            throw new InvalidOperationException("No Bing wallpaper is available right now.");

        return archive.Images;
    }

    public async Task DownloadAsync(
        Models.BingImage image,
        string destinationPath,
        CancellationToken cancellationToken = default)
    {
        var wallpaperUrl = image.WallpaperUrl
            ?? throw new InvalidOperationException("Bing returned an unsafe or invalid image URL.");

        var directory = Path.GetDirectoryName(destinationPath)
            ?? throw new InvalidOperationException("Invalid destination path.");
        Directory.CreateDirectory(directory);

        var staged = Path.Combine(directory, $"{Guid.NewGuid():N}.download");
        try
        {
            using var response = await _http
                .GetAsync(wallpaperUrl, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
                .ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
                throw new InvalidOperationException("Failed to download the wallpaper image.");

            await using (var input = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false))
            await using (var output = new FileStream(staged, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                await input.CopyToAsync(output, cancellationToken).ConfigureAwait(false);
            }

            if (File.Exists(destinationPath))
                File.Delete(destinationPath);
            File.Move(staged, destinationPath);
        }
        catch
        {
            try { if (File.Exists(staged)) File.Delete(staged); } catch { /* best effort */ }
            throw;
        }
    }

    private static string PreferredMarket()
    {
        var name = CultureInfo.CurrentCulture.Name;
        return string.IsNullOrWhiteSpace(name) ? "en-US" : name;
    }
}
