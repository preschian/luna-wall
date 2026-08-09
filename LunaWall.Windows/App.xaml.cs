using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media.Imaging;
using LunaWall.Models;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace LunaWall;

public partial class App : System.Windows.Application
{
    [DllImport("kernel32.dll")]
    private static extern bool AllocConsole();

    private AppState? _state;
    private MainWindow? _mainWindow;
    private Forms.NotifyIcon? _tray;
    private Drawing.Icon? _trayIcon;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        if (e.Args.Any(a => string.Equals(a, "--self-check", StringComparison.OrdinalIgnoreCase)))
        {
            AllocConsole();
            try
            {
                BingImage.SelfCheck();
                Console.WriteLine("self-check ok");
                Shutdown(0);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex);
                Shutdown(1);
            }
            return;
        }

        _state = new AppState();
        _state.Start();

        _mainWindow = new MainWindow(_state);
        _mainWindow.Icon = LoadWindowIcon();
        _mainWindow.Closing += (_, args) =>
        {
            // Keep running in the tray, matching macOS menu-bar lifetime.
            args.Cancel = true;
            _mainWindow.Hide();
        };

        _trayIcon = LoadTrayIcon();
        _tray = new Forms.NotifyIcon
        {
            Text = "LunaWall",
            Icon = _trayIcon,
            Visible = true,
            ContextMenuStrip = BuildTrayMenu(),
        };
        _tray.DoubleClick += (_, _) => ShowMainWindow();

        ShowMainWindow();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _state?.Stop();
        if (_tray is not null)
        {
            _tray.Visible = false;
            _tray.Dispose();
            _tray = null;
        }
        _trayIcon?.Dispose();
        _trayIcon = null;
        base.OnExit(e);
    }

    private static Drawing.Icon LoadTrayIcon()
    {
        // WPF resource stream — reliable for NotifyIcon even before shell associates the exe icon.
        try
        {
            var info = GetResourceStream(new Uri("pack://application:,,,/Assets/LunaWall.ico", UriKind.Absolute));
            if (info?.Stream is { } stream)
                return new Drawing.Icon(stream);
        }
        catch
        {
            // fall through
        }

        var exe = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(exe) && File.Exists(exe))
        {
            try
            {
                var fromExe = Drawing.Icon.ExtractAssociatedIcon(exe);
                if (fromExe is not null)
                    return (Drawing.Icon)fromExe.Clone();
            }
            catch
            {
                // fall through
            }
        }

        return (Drawing.Icon)Drawing.SystemIcons.Application.Clone();
    }

    private static BitmapFrame? LoadWindowIcon()
    {
        try
        {
            var uri = new Uri("pack://application:,,,/Assets/LunaWall.ico", UriKind.Absolute);
            return BitmapFrame.Create(uri);
        }
        catch
        {
            return null;
        }
    }

    private Forms.ContextMenuStrip BuildTrayMenu()
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Show LunaWall", null, (_, _) => ShowMainWindow());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Refresh Now", null, (_, _) => _state?.Refresh(force: true));
        menu.Items.Add("Follow Today", null, (_, _) => _state?.FollowToday());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit LunaWall", null, (_, _) =>
        {
            _tray!.Visible = false;
            Shutdown();
        });

        menu.Opening += (_, _) =>
        {
            if (_state is null) return;
            if (menu.Items[3] is Forms.ToolStripMenuItem follow)
                follow.Enabled = _state.IsPinned && !_state.IsRefreshing;
            if (menu.Items[2] is Forms.ToolStripMenuItem refresh)
                refresh.Enabled = !_state.IsRefreshing;
        };

        return menu;
    }

    private void ShowMainWindow()
    {
        if (_mainWindow is null) return;
        if (!_mainWindow.IsVisible) _mainWindow.Show();
        if (_mainWindow.WindowState == WindowState.Minimized)
            _mainWindow.WindowState = WindowState.Normal;
        _mainWindow.Activate();
    }
}
