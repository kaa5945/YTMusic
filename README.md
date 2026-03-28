![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)
[![繁體中文](https://img.shields.io/badge/lang-繁體中文-red)](README.zh-TW.md)
[![Changelog](https://img.shields.io/badge/changelog-CHANGELOG.md-yellow)](CHANGELOG.md)

# YTMusic

A lightweight native macOS app that wraps YouTube Music with background playback support. Built with Swift + WKWebView — no Electron, no Chromium, minimal resource usage.

## Features

- **Background Playback** — closing the window doesn't stop the music
- **Google Sign-in** — login within the app, session persists across launches
- **Menu Bar Controls** — album art, track info, play/pause/next/previous
- **System Notifications** — song change notifications via macOS
- **Media Keys** — keyboard media keys work via WebView MediaSession
- **Dock Integration** — click Dock icon to restore window

## Requirements

- macOS 13 (Ventura) or later

## Install

Download the latest DMG from [Releases](https://github.com/kaa5945/YTMusic/releases), open it, and drag YTMusic to Applications.

## Uninstall

```bash
bash scripts/uninstall.sh
```

Or manually remove:

```bash
rm -rf /Applications/YTMusic.app
rm -rf ~/Library/WebKit/com.kaa5945.ytmusic
rm -rf ~/Library/Caches/com.kaa5945.ytmusic
rm -rf ~/Library/Preferences/com.kaa5945.ytmusic.plist
```

## Build from Source

Requires Swift 5.9+ (Command Line Tools).

```bash
# Build and create .app bundle
bash scripts/bundle.sh

# Copy to Applications
cp -R build/YTMusic.app /Applications/
```

## Project Structure

```
Sources/
├── App/
│   ├── main.swift              # Entry point (NSApplication)
│   └── AppDelegate.swift       # Window lifecycle, background playback
├── Views/
│   ├── ContentView.swift       # Main SwiftUI view
│   └── WebView.swift           # WKWebView wrapper + Google login
├── Services/
│   ├── MenuBarService.swift    # Menu bar icon + controls
│   ├── NowPlayingService.swift # Song change notifications
│   └── MediaKeyService.swift   # Media key placeholder
└── Helpers/
    └── JavaScriptBridge.swift  # JS ↔ Swift communication
```

## License

MIT
