# Contributing

## Requirements

- macOS 14 or later
- Xcode 15+ (or newer)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

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
2. Downloads the UHD JPEG into Application Support (`LunaWall/` inside the app container when sandboxed)
3. Sets it as the desktop image via `NSWorkspace.setDesktopImageURL`
