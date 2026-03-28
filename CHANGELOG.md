# Changelog

## [1.0.0] - 2026-03-28

### Added
- YouTube Music web player via WKWebView
- Google account sign-in (Safari UA + persistent session)
- Background playback (closing window doesn't stop music)
- Menu Bar controls with album art, track info, play/pause/next/previous
- Song change macOS system notifications
- Media key support via WebView MediaSession
- Dock icon to restore window
- Keyboard shortcuts ⌘C/V/X/A support
- `scripts/bundle.sh` to build .app bundle
- `scripts/generate_icon.py` to generate App Icon
- `scripts/create_dmg.sh` to create DMG installer
- `scripts/uninstall.sh` for clean removal

### 新增
- WKWebView 載入 YouTube Music 網頁版
- Google 帳號登入（Safari UA + session 持久化）
- 背景播放（關閉視窗不退出 App）
- Menu Bar 常駐圖示（含封面圖、歌名、歌手、播放控制）
- 歌曲切換 macOS 系統通知
- 媒體鍵控制（透過 WebView 內建 MediaSession）
- Dock 圖示重開視窗
- 主選單支援 ⌘C/V/X/A 快捷鍵
- `scripts/bundle.sh` 打包成 .app bundle
- `scripts/generate_icon.py` 生成 App Icon
- `scripts/create_dmg.sh` 建立 DMG 安裝映像
- `scripts/uninstall.sh` 完整移除 App 及資料
