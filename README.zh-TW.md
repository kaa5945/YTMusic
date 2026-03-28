![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)
[![English](https://img.shields.io/badge/lang-English-red)](README.md)
[![Changelog](https://img.shields.io/badge/changelog-CHANGELOG.md-yellow)](CHANGELOG.md)

# YTMusic

輕量的 macOS 原生 YouTube Music 桌面 App，支援背景播放。使用 Swift + WKWebView 打造，不依賴 Electron/Chromium，資源佔用極低。

## 功能

- **背景播放** — 關閉視窗不會中斷音樂
- **Google 登入** — 在 App 內登入，session 跨次啟動保持
- **Menu Bar 控制** — 封面圖、歌曲資訊、播放/暫停/上下首
- **系統通知** — 切歌時顯示 macOS 通知
- **媒體鍵** — 鍵盤媒體鍵透過 WebView MediaSession 控制
- **Dock 整合** — 點擊 Dock 圖示重新開啟視窗

## 系統需求

- macOS 13 (Ventura) 或更新版本

## 安裝

從 [Releases](https://github.com/kaa5945/YTMusic/releases) 下載最新的 DMG，打開後將 YTMusic 拖到 Applications。

## 解除安裝

```bash
bash scripts/uninstall.sh
```

或手動移除：

```bash
rm -rf /Applications/YTMusic.app
rm -rf ~/Library/WebKit/com.kaa5945.ytmusic
rm -rf ~/Library/Caches/com.kaa5945.ytmusic
rm -rf ~/Library/Preferences/com.kaa5945.ytmusic.plist
```

## 從原始碼建置

需要 Swift 5.9+（Command Line Tools）。

```bash
# 建置並打包成 .app bundle
bash scripts/bundle.sh

# 複製到應用程式
cp -R build/YTMusic.app /Applications/
```

## 專案結構

```
Sources/
├── App/
│   ├── main.swift              # 進入點（NSApplication）
│   └── AppDelegate.swift       # 視窗生命週期、背景播放
├── Views/
│   ├── ContentView.swift       # 主 SwiftUI 畫面
│   └── WebView.swift           # WKWebView 封裝 + Google 登入
├── Services/
│   ├── MenuBarService.swift    # Menu Bar 圖示 + 控制
│   ├── NowPlayingService.swift # 歌曲切換通知
│   └── MediaKeyService.swift   # 媒體鍵佔位
└── Helpers/
    └── JavaScriptBridge.swift  # JS ↔ Swift 通訊橋接
```

## 授權

MIT
