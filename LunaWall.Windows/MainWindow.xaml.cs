using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
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
        _model.Sync(null);
    }

    private void Refresh_Click(object sender, RoutedEventArgs e) => _state.Refresh(force: true);

    private void FollowToday_Click(object sender, RoutedEventArgs e) => _state.FollowToday();

    private void About_Click(object sender, RoutedEventArgs e) => _state.OpenCopyrightPage();

    private void HistoryItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button { Tag: HistoryItemModel item })
            _state.ApplyImage(item.Image);
    }
}

public sealed class MainWindowModel : INotifyPropertyChanged
{
    private readonly AppState _state;
    private BitmapImage? _currentThumbnail;
    private string _currentTitle = "";
    private string _currentCopyright = "";
    private string _currentDate = "";
    private bool _hasInfoUrl;
    private bool _syncingLaunch;

    public MainWindowModel(AppState state) => _state = state;

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<HistoryItemModel> HistoryItems { get; } = [];

    public string StatusMessage => _state.StatusMessage;
    public bool IsBusy => _state.IsRefreshing || _state.IsWarmingLibrary;
    public bool CanRefresh => !_state.IsRefreshing;
    public bool HasCurrent => _state.CurrentImage is not null;
    public bool HasError => !string.IsNullOrEmpty(_state.LastError);
    public string? LastError => _state.LastError;
    public bool IsPinned => _state.IsPinned;
    public bool HasHistory => HistoryItems.Count > 0;
    public bool HasInfoUrl => _hasInfoUrl;

    public BitmapImage? CurrentThumbnail
    {
        get => _currentThumbnail;
        private set => SetField(ref _currentThumbnail, value);
    }

    public string CurrentTitle
    {
        get => _currentTitle;
        private set => SetField(ref _currentTitle, value);
    }

    public string CurrentCopyright
    {
        get => _currentCopyright;
        private set => SetField(ref _currentCopyright, value);
    }

    public string CurrentDate
    {
        get => _currentDate;
        private set => SetField(ref _currentDate, value);
    }

    public string EmptyCurrentMessage =>
        _state.IsRefreshing ? "Loading wallpaper…" : "No wallpaper loaded yet.";

    public string EmptyHistoryMessage =>
        _state.IsRefreshing ? "Loading…" : "No recent images yet.";

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

    public void Sync(string? propertyName)
    {
        OnPropertyChanged(nameof(StatusMessage));
        OnPropertyChanged(nameof(IsBusy));
        OnPropertyChanged(nameof(CanRefresh));
        OnPropertyChanged(nameof(HasCurrent));
        OnPropertyChanged(nameof(HasError));
        OnPropertyChanged(nameof(LastError));
        OnPropertyChanged(nameof(IsPinned));
        OnPropertyChanged(nameof(EmptyCurrentMessage));
        OnPropertyChanged(nameof(EmptyHistoryMessage));
        OnPropertyChanged(nameof(AutoRefreshEnabled));

        _syncingLaunch = true;
        OnPropertyChanged(nameof(LaunchAtLoginEnabled));
        _syncingLaunch = false;

        if (propertyName is null or nameof(AppState.CurrentImage) or nameof(AppState.IsWarmingLibrary)
            or nameof(AppState.RecentImages) or nameof(AppState.IsRefreshing))
        {
            RefreshCurrent();
            RefreshHistory();
        }
    }

    private void RefreshCurrent()
    {
        var image = _state.CurrentImage;
        if (image is null)
        {
            CurrentThumbnail = null;
            CurrentTitle = "";
            CurrentCopyright = "";
            CurrentDate = "";
            _hasInfoUrl = false;
            OnPropertyChanged(nameof(HasInfoUrl));
            return;
        }

        CurrentTitle = image.DisplayTitle;
        CurrentCopyright = image.Copyright;
        CurrentDate = image.DisplayDate;
        _hasInfoUrl = image.InfoUrl is not null;
        OnPropertyChanged(nameof(HasInfoUrl));
        CurrentThumbnail = WallpaperService.LoadThumbnailImage(
            _state.FilePath(image),
            _state.ThumbnailPath(image));
    }

    private void RefreshHistory()
    {
        HistoryItems.Clear();
        foreach (var image in _state.RecentImages)
        {
            var isCurrent = _state.CurrentImage?.Hash == image.Hash;
            HistoryItems.Add(new HistoryItemModel
            {
                Image = image,
                Title = image.DisplayTitle,
                Date = image.DisplayDate,
                Thumbnail = WallpaperService.LoadThumbnailImage(
                    _state.FilePath(image),
                    _state.ThumbnailPath(image)),
                CanApply = !_state.IsRefreshing && !isCurrent,
                IsCurrent = isCurrent,
            });
        }
        OnPropertyChanged(nameof(HasHistory));
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

public sealed class HistoryItemModel
{
    public required BingImage Image { get; init; }
    public required string Title { get; init; }
    public required string Date { get; init; }
    public BitmapImage? Thumbnail { get; init; }
    public bool CanApply { get; init; }
    public bool IsCurrent { get; init; }

    public FontWeight TitleWeight => IsCurrent ? FontWeights.SemiBold : FontWeights.Normal;
    public System.Windows.Media.Brush BorderBrush => IsCurrent
        ? System.Windows.SystemColors.HighlightBrush
        : new SolidColorBrush(System.Windows.Media.Color.FromArgb(0x33, 0, 0, 0));
    public Thickness BorderThickness => new(IsCurrent ? 2 : 1);
    public Visibility CurrentMarkVisibility => IsCurrent ? Visibility.Visible : Visibility.Collapsed;
}
