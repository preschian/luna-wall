# Contributing

## Requirements

### macOS

- macOS 14 or later
- Xcode 15+ (or newer)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Windows

- Windows 10 or later
- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) to build (current LTS)
- [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/10.0) to run a published exe

## Build & run

### macOS

```bash
cd LunaWall
xcodegen generate
open LunaWall.xcodeproj
```

In Xcode, select the **LunaWall** scheme and press **Run** (`⌘R`).

The app opens a main window (history grid, pin/apply, settings). A menu bar icon stays available for quick refresh, follow-today, and reopening the window. Closing the window does not quit the app; use **Quit LunaWall** from the menu bar or the app menu.

#### Command-line build

```bash
cd LunaWall
xcodegen generate
xcodebuild -scheme LunaWall -configuration Release -derivedDataPath build
open build/Build/Products/Release/LunaWall.app
```

### Windows

```powershell
cd LunaWall.Windows
dotnet run -c Release
```

Closing the main window hides it to the system tray. Quit from the tray menu.

#### Self-check

```powershell
dotnet run -c Release -- --self-check
```

#### Publish (framework-dependent)

Requires [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/10.0) on the target machine:

```powershell
cd LunaWall.Windows
dotnet publish -c Release -r win-x64 --self-contained false `
  -p:PublishSingleFile=true `
  -o publish
.\publish\LunaWall.exe
```

#### Release (Windows)

Push a version tag; GitHub Actions builds `LunaWall-windows-x64.exe` and attaches it to the release:

```powershell
git tag v0.1.0
git push origin v0.1.0
```

Unsigned downloads may trip SmartScreen; users can choose **More info → Run anyway**.

## How it works

1. Calls Bing’s public archive API:  
   `https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&uhd=1`
2. Downloads the UHD JPEG into `Downloads/luna-wall`, reusing a file if it is already cached
3. Sets it as the desktop image (`NSWorkspace.setDesktopImageURL` on macOS, `SystemParametersInfo` on Windows)
4. Applying a past day pins that hash so scheduled refresh won’t replace it until you choose **Follow Today** or apply today’s image
5. On Windows, merges each fetch into `%LOCALAPPDATA%\LunaWall\library.json` and retains those files so Recent grows day by day beyond Bing’s 8-image window
