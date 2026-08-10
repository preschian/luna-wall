# LunaWall

Simple native desktop app that sets your wallpaper to Bing’s photo of the day — similar to [Bing Wallpaper](https://bingwallpaper.microsoft.com/).

| Platform | Project | Stack |
| --- | --- | --- |
| macOS | [`LunaWall/`](LunaWall/) | SwiftUI / AppKit |
| Windows | [`LunaWall.Windows/`](LunaWall.Windows/) | WPF / .NET 10 |

## UI decision (hybrid)

LunaWall is a **hybrid** app on both platforms:

- **Primary UI:** a standard window for browsing history, larger previews, pinning, and settings
- **Secondary entry:** a menu bar extra (macOS) or system tray icon (Windows) for quick refresh / follow-today / reopen the window

A menu-bar-only panel was too constrained for reliable observation, scrolling, and a richer history browser (see [#6](https://github.com/preschian/luna-wall/issues/6)).

## Features

- Fetches today’s Bing wallpaper in UHD
- Browse and apply Bing wallpapers in the main window, with a growing local catalog on both platforms
- Each refresh merges Bing’s 8-day API window into that catalog, so history is not capped at 8 days
- Optional 90-day retention, cache usage summary, and a clean-up that keeps thumbnails
- Applies it as the desktop wallpaper
- Auto-checks on launch, every 8 hours, and after wake / resume
- Pin a day (past or today) to keep it; otherwise auto-refresh follows today
- Launch at login, enabled on first run
- Menu bar / tray shortcuts for refresh, follow-today, and opening the window
- Caches downloaded images in `~/Downloads/luna-wall` (macOS) or `%USERPROFILE%\Downloads\luna-wall` (Windows)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for requirements, build instructions, and how the app works under the hood.

## License

MIT — see [LICENSE](LICENSE).

Images are provided by Bing for wallpaper use. This project is not affiliated with Microsoft.
