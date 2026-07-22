# LunaWall

Simple native macOS app that sets your desktop wallpaper to Bing’s photo of the day — similar to [Bing Wallpaper for Mac](https://bingwallpaper.microsoft.com/mac/en/bing/bing-wallpaper/).

## UI decision (hybrid)

LunaWall is a **hybrid** app:

- **Primary UI:** a standard macOS window for browsing history, larger previews, pinning, and settings
- **Secondary entry:** a menu bar extra for quick refresh / follow-today / reopen the window

A menu-bar-only `MenuBarExtra` panel was too constrained for reliable observation, scrolling, and a richer history browser (see [#6](https://github.com/preschian/luna-wall/issues/6)).

## Features

- Fetches today’s Bing wallpaper in UHD
- Browse and apply recent Bing wallpapers (last 8 days) in the main window
- Applies it automatically to every connected display
- Auto-checks every 30 minutes (and after wake from sleep)
- Pin a past day to keep it; otherwise auto-refresh follows today
- Optional launch at login
- Menu bar shortcuts for refresh, follow-today, and opening the window
- Caches downloaded images in `~/Downloads/luna-wall`

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for requirements, build instructions, and how the app works under the hood.

## License

MIT — see [LICENSE](LICENSE).

Images are provided by Bing for wallpaper use. This project is not affiliated with Microsoft.
