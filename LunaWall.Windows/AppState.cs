using System.ComponentModel;
using System.Runtime.CompilerServices;
using LunaWall.Models;
using LunaWall.Services;

namespace LunaWall;

public sealed class AppState : INotifyPropertyChanged
{
    private const string LastAppliedHashKey = "lastAppliedHash";
    private const string LastAppliedDateKey = "lastAppliedDate";
    private const string AutoRefreshEnabledKey = "autoRefreshEnabled";
    private const string PinnedHashKey = "pinnedHash";
    private const string RetentionDaysKey = "retentionDays";

    /// <summary>Minutes between automatic checks.</summary>
    private const int CheckIntervalMinutes = 30;

    /// <summary>Bing HPImageArchive allows at most 8 images per request.</summary>
    public const int HistoryCount = 8;

    private enum TargetPolicy
    {
        FollowPin,
        ForceToday,
        Exact,
    }

    private readonly BingWallpaperService _bing = new();
    private readonly WallpaperService _wallpaper = new();

    private CancellationTokenSource? _operationCts;
    private CancellationTokenSource? _libraryCts;
    private System.Windows.Threading.DispatcherTimer? _timer;
    private bool _didStart;
    private int _consecutiveRefreshFailures;
    private DateTime? _earliestRetryAt;

    private BingImage? _currentImage;
    private IReadOnlyList<BingImage> _recentImages = [];
    private string _statusMessage = "Ready";
    private bool _isRefreshing;
    private bool _isWarmingLibrary;
    private string? _lastError;
    private bool _autoRefreshEnabled;
    private string? _pinnedHash;
    private bool _launchAtLoginEnabled;
    private int _retentionDays;
    private DateTime? _nextCheckAt;

    public event PropertyChangedEventHandler? PropertyChanged;

    public BingImage? CurrentImage
    {
        get => _currentImage;
        private set => SetField(ref _currentImage, value);
    }

    public IReadOnlyList<BingImage> RecentImages
    {
        get => _recentImages;
        private set => SetField(ref _recentImages, value);
    }

    public string StatusMessage
    {
        get => _statusMessage;
        private set => SetField(ref _statusMessage, value);
    }

    public bool IsRefreshing
    {
        get => _isRefreshing;
        private set => SetField(ref _isRefreshing, value);
    }

    public bool IsWarmingLibrary
    {
        get => _isWarmingLibrary;
        private set => SetField(ref _isWarmingLibrary, value);
    }

    public string? LastError
    {
        get => _lastError;
        private set => SetField(ref _lastError, value);
    }

    public bool AutoRefreshEnabled
    {
        get => _autoRefreshEnabled;
        set
        {
            if (!SetField(ref _autoRefreshEnabled, value)) return;
            AppSettings.Set(AutoRefreshEnabledKey, value);
        }
    }

    public string? PinnedHash
    {
        get => _pinnedHash;
        private set
        {
            if (!SetField(ref _pinnedHash, value)) return;
            if (value is null) AppSettings.Remove(PinnedHashKey);
            else AppSettings.Set(PinnedHashKey, value);
            OnPropertyChanged(nameof(IsPinned));
        }
    }

    public bool IsPinned => PinnedHash is not null;

    public bool LaunchAtLoginEnabled
    {
        get => _launchAtLoginEnabled;
        private set => SetField(ref _launchAtLoginEnabled, value);
    }

    /// <summary>Days of catalog history to keep; 0 keeps everything.</summary>
    public int RetentionDays
    {
        get => _retentionDays;
        set
        {
            if (!SetField(ref _retentionDays, value)) return;
            AppSettings.Set(RetentionDaysKey, value.ToString(System.Globalization.CultureInfo.InvariantCulture));
            var trimmed = LibraryStore.Trim(value);
            RecentImages = trimmed;
            _wallpaper.Evict(trimmed);
        }
    }

    /// <summary>Wall-clock time of the next automatic check, or null when the scheduler is idle.</summary>
    public DateTime? NextCheckAt
    {
        get => _nextCheckAt;
        private set => SetField(ref _nextCheckAt, value);
    }

    public string StorageDirectory => _wallpaper.StorageDirectory;

    public AppState()
    {
        if (!AppSettings.Has(AutoRefreshEnabledKey))
            AppSettings.Set(AutoRefreshEnabledKey, true);

        _autoRefreshEnabled = AppSettings.GetBool(AutoRefreshEnabledKey, true);
        _pinnedHash = AppSettings.GetString(PinnedHashKey);
        _launchAtLoginEnabled = LaunchAtLoginService.IsEnabled;
        _retentionDays = int.TryParse(AppSettings.GetString(RetentionDaysKey), out var days) ? days : 0;
        _recentImages = LibraryStore.Load();
        // Show the last applied image immediately instead of an empty hero while Bing is fetched.
        var lastHash = AppSettings.GetString(LastAppliedHashKey);
        _currentImage = _recentImages.FirstOrDefault(i => i.Hash == lastHash);
    }

    public void Start()
    {
        if (_didStart) return;
        _didStart = true;
        Refresh(force: false);
        StartScheduler();
        Microsoft.Win32.SystemEvents.PowerModeChanged += OnPowerModeChanged;
    }

    public void Stop()
    {
        _timer?.Stop();
        _timer = null;
        NextCheckAt = null;
        CancelOperations();
        IsRefreshing = false;
        IsWarmingLibrary = false;
        Microsoft.Win32.SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        _didStart = false;
    }

    public void Refresh(bool force) =>
        BeginOperation(ct => PerformOperationAsync(force, TargetPolicy.FollowPin, exact: null, forcePin: false, ct));

    /// <param name="pin">Hold this image even when it happens to be today's.</param>
    public void ApplyImage(BingImage image, bool pin = false) =>
        BeginOperation(ct => PerformOperationAsync(force: true, TargetPolicy.Exact, image, pin, ct));

    public void FollowToday() =>
        BeginOperation(ct => PerformOperationAsync(force: true, TargetPolicy.ForceToday, exact: null, forcePin: false, ct));

    /// <summary>Holds the current wallpaper in place so auto-refresh stops following today.</summary>
    public void PinCurrent()
    {
        if (CurrentImage is { } image) PinnedHash = image.Hash;
    }

    public void RevealInExplorer(string path)
    {
        var target = File.Exists(path) ? $"/select,\"{path}\"" : $"\"{StorageDirectory}\"";
        Directory.CreateDirectory(StorageDirectory);
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", target));
    }

    /// <summary>Frees space by deleting full-resolution files over a year old; thumbnails stay.</summary>
    public void CleanUpCache()
    {
        try
        {
            _wallpaper.DeleteFullResolutionOlderThan(DateTime.Today.AddYears(-1), CurrentImage, RecentImages);
            LastError = null;
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
        }
        OnPropertyChanged(nameof(RecentImages));
    }

    public (int Files, long Bytes) CacheUsage() => _wallpaper.CacheUsage();

    public string FilePath(BingImage image) => _wallpaper.LocalFilePath(image);

    public string ThumbnailPath(BingImage image) => _wallpaper.ThumbnailFilePath(image);

    public void ToggleLaunchAtLogin(bool enabled)
    {
        try
        {
            LaunchAtLoginService.SetEnabled(enabled);
            LaunchAtLoginEnabled = LaunchAtLoginService.IsEnabled;
            LastError = null;
        }
        catch (Exception ex)
        {
            LaunchAtLoginEnabled = LaunchAtLoginService.IsEnabled;
            LastError = ex.Message;
            StatusMessage = "Could not update login item";
        }
    }

    public void OpenCopyrightPage()
    {
        if (CurrentImage?.InfoUrl is not { } url) return;
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url.AbsoluteUri)
        {
            UseShellExecute = true,
        });
    }

    private void BeginOperation(Func<CancellationToken, Task> work)
    {
        CancelOperations();
        var cts = new CancellationTokenSource();
        _operationCts = cts;
        IsRefreshing = true;
        IsWarmingLibrary = false;
        LastError = null;

        _ = Task.Run(async () =>
        {
            try
            {
                await work(cts.Token).ConfigureAwait(false);
            }
            finally
            {
                RunOnUi(() =>
                {
                    if (ReferenceEquals(_operationCts, cts))
                        IsRefreshing = false;
                });
            }
        }, CancellationToken.None);
    }

    private void CancelOperations()
    {
        try { _operationCts?.Cancel(); } catch { /* ignore */ }
        try { _libraryCts?.Cancel(); } catch { /* ignore */ }
        _operationCts?.Dispose();
        _libraryCts?.Dispose();
        _operationCts = null;
        _libraryCts = null;
    }

    private async Task PerformOperationAsync(
        bool force,
        TargetPolicy policy,
        BingImage? exact,
        bool forcePin,
        CancellationToken cancellationToken)
    {
        if (!force && _earliestRetryAt is { } earliest && DateTime.UtcNow < earliest)
        {
            RunOnUi(() => StatusMessage = "Waiting to retry…");
            return;
        }

        RunOnUi(() => StatusMessage = "Fetching Bing wallpaper…");

        try
        {
            var images = await _bing.FetchImagesAsync(HistoryCount, cancellationToken: cancellationToken)
                .ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();

            _consecutiveRefreshFailures = 0;
            _earliestRetryAt = null;

            var today = images[0];
            // Grow Recent beyond Bing's 8-day window by keeping every day we've fetched.
            var library = LibraryStore.MergeAndSave(images, RetentionDays);
            var pinned = PinnedHash;
            var target = ResolveTarget(library, today, pinned, policy, exact);
            var lastHash = AppSettings.GetString(LastAppliedHashKey);
            var filePath = _wallpaper.LocalFilePath(target);
            var cachePresent = File.Exists(filePath);

            RunOnUi(() => RecentImages = library);

            if (!force && lastHash == target.Hash && cachePresent)
            {
                RunOnUi(() =>
                {
                    CurrentImage = target;
                    ApplyPinPolicy(target, today, forcePin);
                    StatusMessage = PinnedHash is null
                        ? "Already up to date"
                        : $"Pinned · {target.DisplayDate}";
                });
            }
            else
            {
                await ApplyWallpaperAsync(target, today, forcePin, cancellationToken).ConfigureAwait(false);
            }

            cancellationToken.ThrowIfCancellationRequested();
            // Download only the fresh Bing window; retain the full library on disk.
            ScheduleLibraryWarmup(images, library);
        }
        catch (OperationCanceledException)
        {
            // superseded
        }
        catch (Exception ex)
        {
            if (cancellationToken.IsCancellationRequested) return;
            _consecutiveRefreshFailures++;
            var delay = Math.Min(Math.Pow(2, Math.Min(_consecutiveRefreshFailures, 5)), 60);
            _earliestRetryAt = DateTime.UtcNow.AddSeconds(delay);
            RunOnUi(() =>
            {
                LastError = ex.Message;
                StatusMessage = "Update failed";
            });
        }
    }

    private static BingImage ResolveTarget(
        IReadOnlyList<BingImage> images,
        BingImage today,
        string? pinnedHash,
        TargetPolicy policy,
        BingImage? exact)
    {
        return policy switch
        {
            TargetPolicy.ForceToday => today,
            TargetPolicy.Exact => images.FirstOrDefault(i => i.Hash == exact!.Hash) ?? exact!,
            _ => pinnedHash is not null
                ? images.FirstOrDefault(i => i.Hash == pinnedHash) ?? today
                : today,
        };
    }

    private void ApplyPinPolicy(BingImage applied, BingImage today, bool forcePin) =>
        PinnedHash = forcePin || applied.Hash != today.Hash ? applied.Hash : null;

    private async Task ApplyWallpaperAsync(
        BingImage image,
        BingImage today,
        bool forcePin,
        CancellationToken cancellationToken)
    {
        var filePath = _wallpaper.LocalFilePath(image);
        if (!File.Exists(filePath))
        {
            RunOnUi(() => StatusMessage = "Downloading…");
            await _bing.DownloadAsync(image, filePath, cancellationToken).ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();
        }

        RunOnUi(() => StatusMessage = "Setting wallpaper…");
        _wallpaper.SetDesktopImage(filePath);
        cancellationToken.ThrowIfCancellationRequested();

        AppSettings.Set(LastAppliedHashKey, image.Hash);
        AppSettings.Set(LastAppliedDateKey, image.StartDate);

        RunOnUi(() =>
        {
            CurrentImage = image;
            ApplyPinPolicy(image, today, forcePin);
            StatusMessage = PinnedHash is null
                ? $"Updated · {image.DisplayDate}"
                : $"Pinned · {image.DisplayDate}";
        });
    }

    private void ScheduleLibraryWarmup(IReadOnlyList<BingImage> toDownload, IReadOnlyList<BingImage> retain)
    {
        try { _libraryCts?.Cancel(); } catch { /* ignore */ }
        _libraryCts?.Dispose();
        var cts = new CancellationTokenSource();
        _libraryCts = cts;

        _ = Task.Run(async () =>
        {
            try
            {
                await WarmupLibraryAsync(toDownload, retain, cts.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                // superseded
            }
        }, CancellationToken.None);
    }

    private async Task WarmupLibraryAsync(
        IReadOnlyList<BingImage> toDownload,
        IReadOnlyList<BingImage> retain,
        CancellationToken cancellationToken)
    {
        RunOnUi(() => IsWarmingLibrary = true);
        try
        {
            var pending = toDownload.Where(i => !File.Exists(_wallpaper.LocalFilePath(i))).ToList();
            if (pending.Count > 0)
            {
                RunOnUi(() => StatusMessage = $"Downloading library 0/{pending.Count}…");
                var finished = 0;
                var failures = 0;

                var tasks = pending.Select(async image =>
                {
                    try
                    {
                        await _bing.DownloadAsync(image, _wallpaper.LocalFilePath(image), cancellationToken)
                            .ConfigureAwait(false);
                        return true;
                    }
                    catch
                    {
                        return false;
                    }
                }).ToList();

                while (tasks.Count > 0)
                {
                    var done = await Task.WhenAny(tasks).ConfigureAwait(false);
                    tasks.Remove(done);
                    cancellationToken.ThrowIfCancellationRequested();
                    if (await done.ConfigureAwait(false)) finished++;
                    else failures++;
                    RunOnUi(() => StatusMessage = $"Downloading library {finished}/{pending.Count}…");
                }

                if (failures > 0 && finished == 0)
                    RunOnUi(() => LastError = "Could not download the wallpaper library.");
                else if (failures > 0)
                    RunOnUi(() => LastError = $"Some library downloads failed ({failures}).");
            }

            cancellationToken.ThrowIfCancellationRequested();

            await Task.Run(() =>
            {
                foreach (var image in toDownload)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    WallpaperService.LoadThumbnailImage(
                        _wallpaper.LocalFilePath(image),
                        _wallpaper.ThumbnailFilePath(image));
                }
            }, cancellationToken).ConfigureAwait(false);

            cancellationToken.ThrowIfCancellationRequested();
            // Keep every library day; only delete orphan files not in the catalog.
            _wallpaper.Evict(retain);

            RunOnUi(() =>
            {
                if (PinnedHash is null)
                    StatusMessage = CurrentImage is { } img ? $"Updated · {img.DisplayDate}" : "Ready";
                else if (CurrentImage is { } current)
                    StatusMessage = $"Pinned · {current.DisplayDate}";
            });
        }
        finally
        {
            RunOnUi(() =>
            {
                if (!cancellationToken.IsCancellationRequested)
                    IsWarmingLibrary = false;
            });
        }
    }

    private void StartScheduler()
    {
        _timer?.Stop();
        _timer = new System.Windows.Threading.DispatcherTimer
        {
            Interval = TimeSpan.FromMinutes(CheckIntervalMinutes),
        };
        _timer.Tick += (_, _) =>
        {
            NextCheckAt = DateTime.Now.AddMinutes(CheckIntervalMinutes);
            if (AutoRefreshEnabled) Refresh(force: false);
        };
        _timer.Start();
        NextCheckAt = DateTime.Now.AddMinutes(CheckIntervalMinutes);
    }

    private void OnPowerModeChanged(object sender, Microsoft.Win32.PowerModeChangedEventArgs e)
    {
        if (e.Mode == Microsoft.Win32.PowerModes.Resume && AutoRefreshEnabled)
            Refresh(force: false);
    }

    private static void RunOnUi(Action action)
    {
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher is null || dispatcher.CheckAccess())
            action();
        else
            dispatcher.Invoke(action);
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(name);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

/// <summary>Tiny JSON settings file — avoids an app.config dependency.</summary>
internal static class AppSettings
{
    private static readonly object Gate = new();
    private static readonly string Path = System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "LunaWall",
        "settings.json");

    private static Dictionary<string, string> Load()
    {
        try
        {
            if (!File.Exists(Path)) return new Dictionary<string, string>(StringComparer.Ordinal);
            var json = File.ReadAllText(Path);
            return System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, string>>(json)
                   ?? new Dictionary<string, string>(StringComparer.Ordinal);
        }
        catch
        {
            return new Dictionary<string, string>(StringComparer.Ordinal);
        }
    }

    private static void Save(Dictionary<string, string> data)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
        var json = System.Text.Json.JsonSerializer.Serialize(data);
        File.WriteAllText(Path, json);
    }

    public static bool Has(string key)
    {
        lock (Gate) return Load().ContainsKey(key);
    }

    public static string? GetString(string key)
    {
        lock (Gate) return Load().TryGetValue(key, out var value) ? value : null;
    }

    public static bool GetBool(string key, bool fallback)
    {
        var raw = GetString(key);
        return raw is null ? fallback : string.Equals(raw, "true", StringComparison.OrdinalIgnoreCase);
    }

    public static void Set(string key, string value)
    {
        lock (Gate)
        {
            var data = Load();
            data[key] = value;
            Save(data);
        }
    }

    public static void Set(string key, bool value) => Set(key, value ? "true" : "false");

    public static void Remove(string key)
    {
        lock (Gate)
        {
            var data = Load();
            if (data.Remove(key)) Save(data);
        }
    }
}
