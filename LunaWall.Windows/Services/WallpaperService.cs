using System.Runtime.InteropServices;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using LunaWall.Models;

namespace LunaWall.Services;

public sealed class WallpaperService
{
    public const int ThumbnailMaxPixelSize = 320;

    private const int SpiSetDeskWallpaper = 20;
    private const int SpifUpdateIniFile = 0x01;
    private const int SpifSendWinIniChange = 0x02;

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);

    public string StorageDirectory
    {
        get
        {
            var downloads = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                "Downloads",
                "luna-wall");
            return downloads;
        }
    }

    public string ThumbnailDirectory => Path.Combine(StorageDirectory, "thumbs");

    public string LocalFilePath(BingImage image)
    {
        var startdate = SanitizePathComponent(image.StartDate);
        var hash = SanitizePathComponent(image.Hash);
        return Path.Combine(StorageDirectory, $"{startdate}-{hash}.jpg");
    }

    public string ThumbnailFilePath(BingImage image)
    {
        var startdate = SanitizePathComponent(image.StartDate);
        var hash = SanitizePathComponent(image.Hash);
        return Path.Combine(ThumbnailDirectory, $"{startdate}-{hash}-p{ThumbnailMaxPixelSize}.jpg");
    }

    private static string SanitizePathComponent(string value)
    {
        var filtered = new string(value.Select(ch =>
            char.IsLetterOrDigit(ch) || ch is '-' or '_' ? ch : '_').ToArray());
        return filtered.Length == 0 ? "unknown" : filtered;
    }

    public void Evict(IEnumerable<BingImage> images)
    {
        var keepWallpapers = images.Select(LocalFilePath).Select(Path.GetFileName).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var keepThumbs = images.Select(ThumbnailFilePath).Select(Path.GetFileName).ToHashSet(StringComparer.OrdinalIgnoreCase);
        EvictDirectory(StorageDirectory, keepWallpapers, ".jpg");
        EvictDirectory(ThumbnailDirectory, keepThumbs, ".jpg");
    }

    private static void EvictDirectory(string directory, HashSet<string?> keeping, string extension)
    {
        if (!Directory.Exists(directory)) return;
        foreach (var file in Directory.EnumerateFiles(directory, $"*{extension}"))
        {
            var name = Path.GetFileName(file);
            if (!keeping.Contains(name))
            {
                try { File.Delete(file); } catch { /* best effort */ }
            }
        }
    }

    public static void EnsureThumbnail(string source, string destination)
    {
        if (File.Exists(destination)) return;
        if (!File.Exists(source)) throw new InvalidOperationException("Could not create a wallpaper thumbnail.");

        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);

        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.UriSource = new Uri(source, UriKind.Absolute);
        bitmap.DecodePixelWidth = ThumbnailMaxPixelSize;
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.EndInit();
        bitmap.Freeze();

        var encoder = new JpegBitmapEncoder { QualityLevel = 85 };
        encoder.Frames.Add(BitmapFrame.Create(bitmap));

        var temp = Path.Combine(Path.GetDirectoryName(destination)!, $"{Guid.NewGuid():N}.thumb");
        try
        {
            using (var stream = File.Create(temp))
                encoder.Save(stream);

            if (File.Exists(destination)) File.Delete(destination);
            File.Move(temp, destination);
        }
        catch
        {
            try { if (File.Exists(temp)) File.Delete(temp); } catch { /* best effort */ }
            throw;
        }
    }

    public static BitmapImage? LoadThumbnailImage(string source, string destination)
    {
        try
        {
            EnsureThumbnail(source, destination);
            var image = new BitmapImage();
            image.BeginInit();
            image.UriSource = new Uri(destination, UriKind.Absolute);
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch
        {
            return null;
        }
    }

    public void SetDesktopImage(string filePath)
    {
        if (!File.Exists(filePath))
            throw new InvalidOperationException("Wallpaper file was not found.");

        // Fill style matches macOS scaleProportionallyUpOrDown + allowClipping.
        using (var key = Registry.CurrentUser.OpenSubKey(@"Control Panel\Desktop", writable: true))
        {
            key?.SetValue("WallpaperStyle", "10");
            key?.SetValue("TileWallpaper", "0");
        }

        if (!SystemParametersInfo(SpiSetDeskWallpaper, 0, filePath, SpifUpdateIniFile | SpifSendWinIniChange))
            throw new InvalidOperationException("Could not set the desktop wallpaper.");
    }
}
