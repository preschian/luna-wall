using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LunaWall.Models;
using LunaWall.Services;

namespace LunaWall;

public partial class MainWindow : Window
{
    private readonly AppState _state;
    private readonly MainWindowModel _model;

    public MainWindow(AppState state)
    {
        InitializeComponent();
        _state = state;
        _model = new MainWindowModel(state);
        DataContext = _model;
        _state.PropertyChanged += (_, e) => Dispatcher.Invoke(() => _model.Sync(e.PropertyName));
        StateChanged += (_, _) => _model.SyncChrome(WindowState);
        _model.Sync(null);
        _model.SyncChrome(WindowState);
    }

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2) ToggleMaximize();
        else if (e.ButtonState == MouseButtonState.Pressed) DragMove();
    }

    private void Minimize_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void Maximize_Click(object sender, RoutedEventArgs e) => ToggleMaximize();

    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    private void ToggleMaximize() =>
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;

    private void GoHome_Click(object sender, RoutedEventArgs e) => _model.View = AppView.Home;

    private void GoLibrary_Click(object sender, RoutedEventArgs e) => _model.View = AppView.Library;

    private void GoSettings_Click(object sender, RoutedEventArgs e) => _model.View = AppView.Settings;

    private void Refresh_Click(object sender, RoutedEventArgs e) => _state.Refresh(force: true);

    private void TogglePin_Click(object sender, RoutedEventArgs e)
    {
        if (_state.IsPinned) _state.FollowToday();
        else _state.PinCurrent();
    }

    private void ViewFull_Click(object sender, RoutedEventArgs e) => _model.OpenDetail(_state.CurrentImage);

    private void Tile_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button { Tag: TileModel tile })
            _model.OpenDetail(tile.Image);
    }

    private void CloseDetail_Click(object sender, RoutedEventArgs e) => _model.CloseDetail();

    private void PrevDetail_Click(object sender, RoutedEventArgs e) => _model.StepDetail(-1);

    private void NextDetail_Click(object sender, RoutedEventArgs e) => _model.StepDetail(+1);

    private void ApplyDetail_Click(object sender, RoutedEventArgs e)
    {
        if (_model.DetailImageModel is not { } image) return;
        _state.ApplyImage(image);
        _model.CloseDetail();
        _model.View = AppView.Home;
    }

    private void PinDetail_Click(object sender, RoutedEventArgs e)
    {
        if (_model.DetailImageModel is not { } image) return;
        if (_state.PinnedHash == image.Hash) _state.FollowToday();
        else _state.ApplyImage(image, pin: true);
        _model.CloseDetail();
        _model.View = AppView.Home;
    }

    private void OpenDetailFolder_Click(object sender, RoutedEventArgs e)
    {
        if (_model.DetailImageModel is { } image) _state.RevealInExplorer(_state.FilePath(image));
    }

    private void OpenStorage_Click(object sender, RoutedEventArgs e) => _state.RevealInExplorer(_state.StorageDirectory);

    private void CleanUp_Click(object sender, RoutedEventArgs e)
    {
        _state.CleanUpCache();
        _model.Sync(null);
    }
}

public enum AppView
{
    Home,
    Library,
    Settings,
}

public sealed class MainWindowModel : INotifyPropertyChanged
{
    private const int HeroDecodeWidth = 1600;

    private readonly AppState _state;

    private AppView _view = AppView.Home;
    private string _query = "";
    private bool _pinnedOnly;
    private bool _syncingLaunch;
    private int _detailIndex = -1;
    private bool _detailOpen;
    private string _maximizeGlyph = "";
    private BitmapImage? _heroImage;
    private BitmapImage? _heroThumbnail;
    private BitmapImage? _detailImage;

    public MainWindowModel(AppState state) => _state = state;

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<TileModel> RecentItems { get; } = [];
    public ObservableCollection<ShelfModel> Shelves { get; } = [];

    // ---- navigation -------------------------------------------------------

    public AppView View
    {
        get => _view;
        set
        {
            if (_view == value) return;
            _view = value;
            _detailOpen = false;
            SyncVisibility();
        }
    }

    public Visibility HomeVisibility => Vis(_view == AppView.Home);
    public Visibility LibraryVisibility => Vis(_view == AppView.Library);
    public Visibility SettingsVisibility => Vis(_view == AppView.Settings);
    public Visibility HeaderVisibility => Vis(_view != AppView.Home);
    public Visibility LibraryNavVisibility => Vis(_view != AppView.Library);
    public Visibility SettingsNavVisibility => Vis(_view != AppView.Settings);

    public string MaximizeGlyph
    {
        get => _maximizeGlyph;
        private set => SetField(ref _maximizeGlyph, value);
    }

    public void SyncChrome(WindowState windowState) =>
        MaximizeGlyph = windowState == WindowState.Maximized ? "" : "";

    // ---- hero -------------------------------------------------------------

    public BitmapImage? HeroImage
    {
        get => _heroImage;
        private set => SetField(ref _heroImage, value);
    }

    public BitmapImage? HeroThumbnail
    {
        get => _heroThumbnail;
        private set => SetField(ref _heroThumbnail, value);
    }

    public string HeroTitle => _state.CurrentImage?.DisplayTitle ?? "Waiting for today's wallpaper…";
    public string HeroCopyright => _state.CurrentImage?.Copyright ?? "";
    public string HeroDate => LongDate(_state.CurrentImage);

    public bool HasCurrent => _state.CurrentImage is not null;
    public bool CanRefresh => !_state.IsRefreshing;

    public string RefreshLabel => _state.IsRefreshing ? "Checking…" : "Refresh";

    public Brush StatusBrush => Resource(_state.IsPinned ? "PinOrange" : "Amber");

    public string StatusLabel => _state.IsRefreshing
        ? "● CHECKING BING…"
        : _state.IsPinned ? "◆ PINNED · AUTO-REFRESH HELD" : "● LIVE · FOLLOWING TODAY";

    public string StatusLine
    {
        get
        {
            if (_state.IsPinned) return "PINNED · AUTO-REFRESH HELD";
            var line = "ON YOUR DESKTOP · FOLLOWING TODAY";
            if (_state.NextCheckAt is { } next)
            {
                var hours = (int)Math.Max(0, Math.Round((next - DateTime.Now).TotalHours));
                line += $" · NEXT CHECK {hours} H";
            }
            return line;
        }
    }

    public string PinLabel => _state.IsPinned ? "Follow today" : "Pin this day";
    public Brush PinBackground => _state.IsPinned ? Brushes.Transparent : Resource("Amber");
    public Brush PinBorder => Resource(_state.IsPinned ? "Edge" : "Amber");
    public Thickness PinBorderThickness => new(_state.IsPinned ? 1 : 0);
    public Brush PinForeground => _state.IsPinned ? Resource("Ink") : Resource("AmberInk");

    public string CatalogSummary => $"LOCAL CATALOG · {_state.RecentImages.Count} IMAGES →";

    // ---- library ----------------------------------------------------------

    public string Query
    {
        get => _query;
        set
        {
            if (!SetField(ref _query, value)) return;
            OnPropertyChanged(nameof(SearchPlaceholderVisibility));
            RebuildLibrary();
        }
    }

    public Visibility SearchPlaceholderVisibility => Vis(_query.Length == 0);

    public bool ShowPinnedOnly
    {
        get => _pinnedOnly;
        set
        {
            if (!SetField(ref _pinnedOnly, value)) return;
            OnPropertyChanged(nameof(ShowAll));
            RebuildLibrary();
        }
    }

    public bool ShowAll
    {
        get => !_pinnedOnly;
        set { if (value) ShowPinnedOnly = false; }
    }

    public string AllChipLabel => $"All {_state.RecentImages.Count}";
    public string PinnedChipLabel => $"Pinned {(_state.IsPinned ? 1 : 0)}";

    public string EmptyNote => _state.RecentImages.Count == 0 ? "Loading catalog…" : "No images match this filter.";
    public Visibility EmptyNoteVisibility => Vis(Shelves.Count == 0);

    // ---- settings ---------------------------------------------------------

    public bool AutoRefreshEnabled
    {
        get => _state.AutoRefreshEnabled;
        set => _state.AutoRefreshEnabled = value;
    }

    public bool LaunchAtLoginEnabled
    {
        get => _state.LaunchAtLoginEnabled;
        set
        {
            if (_syncingLaunch) return;
            _state.ToggleLaunchAtLogin(value);
            OnPropertyChanged();
        }
    }

    public bool RetainNinetyDays
    {
        get => _state.RetentionDays == 90;
        set
        {
            if (!value) return;
            _state.RetentionDays = 90;
            OnPropertyChanged();
            OnPropertyChanged(nameof(RetainForever));
        }
    }

    public bool RetainForever
    {
        get => _state.RetentionDays == 0;
        set
        {
            if (!value) return;
            _state.RetentionDays = 0;
            OnPropertyChanged();
            OnPropertyChanged(nameof(RetainNinetyDays));
        }
    }

    public string StorageDirectory => _state.StorageDirectory;

    public string CacheSummary
    {
        get
        {
            var (files, bytes) = _state.CacheUsage();
            return $"{FormatBytes(bytes)} cached across {files} files. Thumbnails are kept; " +
                   "full-resolution images older than a year can be re-downloaded on demand.";
        }
    }

    public string? LastError => _state.LastError;
    public Visibility ErrorVisibility => Vis(!string.IsNullOrEmpty(_state.LastError));

    // ---- detail -----------------------------------------------------------

    public BingImage? DetailImageModel =>
        _detailIndex >= 0 && _detailIndex < _state.RecentImages.Count ? _state.RecentImages[_detailIndex] : null;

    public Visibility DetailVisibility => Vis(_detailOpen && DetailImageModel is not null);

    public BitmapImage? DetailImage
    {
        get => _detailImage;
        private set => SetField(ref _detailImage, value);
    }

    public string DetailTitle => DetailImageModel?.DisplayTitle ?? "";
    public string DetailCopyright => DetailImageModel?.Copyright ?? "";

    public string DetailMeta
    {
        get
        {
            if (DetailImageModel is not { } image) return "";
            var path = _state.FilePath(image);
            var size = File.Exists(path) ? $" · {FormatBytes(new FileInfo(path).Length)}" : " · NOT CACHED";
            return $"{LongDate(image)} · UHD{size}";
        }
    }

    public string DetailPinLabel => DetailImageModel is { } image && _state.PinnedHash == image.Hash ? "Unpin" : "Pin";

    public void OpenDetail(BingImage? image)
    {
        if (image is null) return;
        var index = IndexOf(image);
        if (index < 0) return;
        _detailIndex = index;
        _detailOpen = true;
        SyncDetail();
    }

    public void CloseDetail()
    {
        _detailOpen = false;
        SyncDetail();
    }

    public void StepDetail(int delta)
    {
        var next = _detailIndex + delta;
        if (next < 0 || next >= _state.RecentImages.Count) return;
        _detailIndex = next;
        SyncDetail();
    }

    // ---- sync -------------------------------------------------------------

    public void Sync(string? propertyName)
    {
        foreach (var name in new[]
                 {
                     nameof(CanRefresh), nameof(HasCurrent), nameof(RefreshLabel), nameof(StatusBrush),
                     nameof(StatusLabel), nameof(StatusLine), nameof(PinLabel), nameof(PinBackground),
                     nameof(PinBorder), nameof(PinBorderThickness), nameof(PinForeground), nameof(HeroTitle), nameof(HeroCopyright),
                     nameof(HeroDate), nameof(CatalogSummary), nameof(AllChipLabel), nameof(PinnedChipLabel),
                     nameof(AutoRefreshEnabled), nameof(LastError), nameof(ErrorVisibility), nameof(CacheSummary),
                     nameof(EmptyNote), nameof(RetainForever), nameof(RetainNinetyDays), nameof(DetailPinLabel),
                 })
        {
            OnPropertyChanged(name);
        }

        _syncingLaunch = true;
        OnPropertyChanged(nameof(LaunchAtLoginEnabled));
        _syncingLaunch = false;

        if (propertyName is null or nameof(AppState.CurrentImage) or nameof(AppState.IsWarmingLibrary)
            or nameof(AppState.RecentImages) or nameof(AppState.IsRefreshing)
            or nameof(AppState.PinnedHash) or nameof(AppState.IsPinned))
        {
            RefreshHero();
            RebuildLibrary();
            SyncDetail();
        }
    }

    private void SyncVisibility()
    {
        OnPropertyChanged(nameof(HomeVisibility));
        OnPropertyChanged(nameof(LibraryVisibility));
        OnPropertyChanged(nameof(SettingsVisibility));
        OnPropertyChanged(nameof(HeaderVisibility));
        OnPropertyChanged(nameof(LibraryNavVisibility));
        OnPropertyChanged(nameof(SettingsNavVisibility));
        OnPropertyChanged(nameof(DetailVisibility));
        OnPropertyChanged(nameof(CacheSummary));
    }

    private void SyncDetail()
    {
        DetailImage = DetailImageModel is { } image
            ? WallpaperService.LoadPreviewImage(_state.FilePath(image), HeroDecodeWidth)
              ?? WallpaperService.LoadThumbnailImage(_state.FilePath(image), _state.ThumbnailPath(image))
            : null;

        OnPropertyChanged(nameof(DetailVisibility));
        OnPropertyChanged(nameof(DetailTitle));
        OnPropertyChanged(nameof(DetailCopyright));
        OnPropertyChanged(nameof(DetailMeta));
        OnPropertyChanged(nameof(DetailPinLabel));
    }

    private void RefreshHero()
    {
        if (_state.CurrentImage is not { } image)
        {
            HeroImage = null;
            HeroThumbnail = null;
            return;
        }

        var path = _state.FilePath(image);
        HeroThumbnail = WallpaperService.LoadThumbnailImage(path, _state.ThumbnailPath(image));
        HeroImage = WallpaperService.LoadPreviewImage(path, HeroDecodeWidth) ?? HeroThumbnail;
    }

    private void RebuildLibrary()
    {
        var images = _state.RecentImages;
        var currentHash = _state.CurrentImage?.Hash;
        var pinnedHash = _state.PinnedHash;

        RecentItems.Clear();
        foreach (var image in images.Take(AppState.HistoryCount))
            RecentItems.Add(Tile(image, currentHash, pinnedHash));

        var needle = _query.Trim();
        var matches = images.Where(i =>
            (needle.Length == 0
             || i.DisplayTitle.Contains(needle, StringComparison.OrdinalIgnoreCase)
             || i.Copyright.Contains(needle, StringComparison.OrdinalIgnoreCase))
            && (!_pinnedOnly || i.Hash == pinnedHash));

        Shelves.Clear();
        // RecentImages is already newest-first, so GroupBy keeps the months in order.
        foreach (var group in matches.GroupBy(MonthLabel))
        {
            Shelves.Add(new ShelfModel
            {
                Month = group.Key,
                Items = [.. group.Select(i => Tile(i, currentHash, pinnedHash))],
            });
        }

        OnPropertyChanged(nameof(EmptyNoteVisibility));
        OnPropertyChanged(nameof(CatalogSummary));
        OnPropertyChanged(nameof(AllChipLabel));
        OnPropertyChanged(nameof(PinnedChipLabel));
    }

    private TileModel Tile(BingImage image, string? currentHash, string? pinnedHash)
    {
        var date = ParseDate(image);
        return new TileModel
        {
            Image = image,
            Title = image.DisplayTitle,
            ShortDate = date?.ToString("MMM d", CultureInfo.CurrentCulture) ?? image.DisplayDate,
            DayNumber = date?.Day.ToString(CultureInfo.InvariantCulture) ?? "",
            IsCurrent = image.Hash == currentHash,
            IsPinned = image.Hash == pinnedHash,
            Thumbnail = WallpaperService.LoadThumbnailImage(_state.FilePath(image), _state.ThumbnailPath(image)),
        };
    }

    private int IndexOf(BingImage image)
    {
        for (var i = 0; i < _state.RecentImages.Count; i++)
            if (_state.RecentImages[i].Hash == image.Hash) return i;
        return -1;
    }

    private static string LongDate(BingImage? image) =>
        image is null ? "" : (ParseDate(image)?.ToString("MMMM d, yyyy", CultureInfo.CurrentCulture)
                              ?? image.DisplayDate).ToUpperInvariant();

    private static string MonthLabel(BingImage image) =>
        ParseDate(image)?.ToString("MMMM yyyy", CultureInfo.CurrentCulture) ?? "Undated";

    private static DateTime? ParseDate(BingImage image) =>
        DateTime.TryParseExact(image.StartDate, "yyyyMMdd", CultureInfo.InvariantCulture,
            DateTimeStyles.None, out var date)
            ? date
            : null;

    private static string FormatBytes(long bytes) => bytes switch
    {
        >= 1L << 30 => $"{bytes / (double)(1L << 30):0.#} GB",
        >= 1L << 20 => $"{bytes / (double)(1L << 20):0.#} MB",
        _ => $"{bytes / 1024.0:0.#} KB",
    };

    private static Visibility Vis(bool visible) => visible ? Visibility.Visible : Visibility.Collapsed;

    private static Brush Resource(string key) =>
        (Brush)System.Windows.Application.Current.Resources[key];

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

public sealed class ShelfModel
{
    public required string Month { get; init; }
    public required IReadOnlyList<TileModel> Items { get; init; }

    public string Count => $"{Items.Count} DAYS";
}

public sealed class TileModel
{
    private static readonly Brush PlainEdge = new SolidColorBrush(Color.FromArgb(0x18, 0xFF, 0xFF, 0xFF));

    public required BingImage Image { get; init; }
    public required string Title { get; init; }
    public required string ShortDate { get; init; }
    public required string DayNumber { get; init; }
    public BitmapImage? Thumbnail { get; init; }
    public bool IsCurrent { get; init; }
    public bool IsPinned { get; init; }

    public string PinMark => IsPinned ? "◆" : "";
    public Brush BorderBrush => IsCurrent ? Amber : PlainEdge;
    public Thickness BorderThickness => new(IsCurrent ? 2 : 1);
    public Brush DateBrush => IsCurrent ? Amber : new SolidColorBrush(Color.FromArgb(0x6B, 0xFF, 0xFF, 0xFF));

    private static Brush Amber => (Brush)System.Windows.Application.Current.Resources["Amber"];
}
