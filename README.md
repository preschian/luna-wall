# LunaWall

Simple native macOS menu bar app that sets your desktop wallpaper to Bing’s photo of the day — similar to [Bing Wallpaper for Mac](https://bingwallpaper.microsoft.com/mac/en/bing/bing-wallpaper/).

## Features

- Fetches today’s Bing wallpaper in UHD
- Applies it automatically to every connected display
- Auto-checks every 30 minutes (and after wake from sleep)
- Optional launch at login
- Menu bar UI with title, copyright, and manual refresh

## Requirements

- macOS 14 or later
- Xcode 15+ (or newer)

## Build & run

```bash
cd LunaWall
xcodegen generate
open LunaWall.xcodeproj
```

In Xcode, select the **LunaWall** scheme and press **Run** (`⌘R`).

The app lives in the menu bar (photo icon). Click it to refresh, toggle auto-refresh, or enable launch at login.

### Command-line build

```bash
cd LunaWall
xcodegen generate
xcodebuild -scheme LunaWall -configuration Release -derivedDataPath build
open build/Build/Products/Release/LunaWall.app
```

## How it works

1. Calls Bing’s public archive API:  
   `https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&uhd=1`
2. Downloads the UHD JPEG into `~/Library/Application Support/LunaWall/`
3. Sets it as the desktop image via `NSWorkspace.setDesktopImageURL`

Images are provided by Bing for wallpaper use. This project is not affiliated with Microsoft.

## License

MIT — see [LICENSE](LICENSE).
