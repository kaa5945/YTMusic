# Changelog

## [1.1.0] - 2026-04-02

### Added
- Richer menu bar now playing panel with playback progress, volume slider, repeat, and shuffle controls
- Up next playlist inside the menu bar with thumbnail hover play affordance and preserved scroll position
- Queue thumbnail fallback parsing for lazy-loaded YouTube Music artwork sources
- Smoke test target for JavaScript bridge regressions and playlist behavior

### Changed
- Split the Swift package into a reusable `YTMusicCore` target plus dedicated app and smoke test executables
- Menu bar queue rendering now stays aligned with the visible YouTube Music queue ordering instead of deduping rows
- Queue item interactions are limited to the artwork play affordance to reduce accidental song switches

### Fixed
- Track changes are now detected with a full fingerprint instead of title only, so same-name songs still update correctly
- Queue playback targeting now uses the same row mapping as queue fetch, fixing mismatched playback selection
- Video event listeners are rebound after player element replacement so progress and playback state keep updating
- Artwork requests now ignore stale responses, preventing old covers from overwriting the current track
- Menu bar queue thumbnails now continue loading for later playlist rows instead of stopping after the first few items

### 新增
- Menu Bar 新增更完整的播放中區塊，包含進度列、音量滑桿、重複與隨機播放控制
- Menu Bar 內建待播清單，支援封面 hover 播放按鈕與保留捲動位置
- 補上 YouTube Music lazy-load 封面圖來源 fallback，後段清單也能解析縮圖
- 新增 JavaScript bridge 與播放清單行為的 smoke test target

### 變更
- Swift Package 拆分為可重用的 `YTMusicCore` target，以及獨立的 app 與 smoke test executable
- Menu Bar 待播清單改為跟隨 YouTube Music 畫面上的實際 queue 順序，不再自行去重
- 待播清單互動改成只有封面播放 affordance 可切歌，降低誤觸

### 修正
- 切歌判斷改用完整 track fingerprint，不再因同名歌曲而漏更新
- 待播清單播放索引與抓取索引統一，修正點選歌曲卻播放錯列的問題
- 播放器 video 元素被重建後會重新綁定事件，避免進度與播放狀態失聯
- 封面下載加入過期請求保護，避免舊歌曲封面覆蓋目前播放中的歌曲
- 修正待播清單縮圖只顯示前幾首、後面列缺圖的問題

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
