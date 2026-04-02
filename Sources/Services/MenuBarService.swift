import Cocoa
import SwiftUI

/// Menu Bar 常駐圖示服務
class MenuBarService: NSObject, NSMenuDelegate {
    static let shared = MenuBarService()

    private var statusItem: NSStatusItem?
    private var isPlaying = false
    private var currentTrack: TrackInfo?
    private var currentArtwork: NSImage?
    private var volume: Float = 1.0
    private var repeatState: String = "none"
    private var shuffleEnabled: Bool = false
    private var queueItems: [QueueItem] = []
    private var currentTime: Double = 0
    private var duration: Double = 0
    private var queueThumbnails: [String: NSImage] = [:]
    private var artworkRequestTracker = ArtworkRequestTracker()

    // 即時更新的 UI 元素引用
    private weak var playButton: NSButton?
    private weak var progressSlider: NSSlider?
    private weak var elapsedLabel: NSTextField?
    private weak var remainLabel: NSTextField?
    private weak var artworkView: NSImageView?
    private weak var titleLabel: NSTextField?
    private weak var artistLabel: NSTextField?

    // 播放清單滾動位置追蹤
    private weak var queueScrollView: NSScrollView?
    private weak var topIndicator: NSView?
    private weak var bottomIndicator: NSView?
    private var lastQueueScrollOffset: CGFloat = 0

    private let menuWidth: CGFloat = 300
    private var isMenuOpen = false
    private var queueRefreshWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
        setupStatusItem()
        setupCallbacks()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "YTMusic")
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    // MARK: - NSMenuDelegate — 每次開啟時重建 menu 內容

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let contentView = queueScrollView?.contentView {
            lastQueueScrollOffset = contentView.bounds.origin.y
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: contentView
            )
        }

        playButton = nil
        progressSlider = nil
        elapsedLabel = nil
        remainLabel = nil
        artworkView = nil
        titleLabel = nil
        artistLabel = nil
        queueScrollView = nil
        topIndicator = nil
        bottomIndicator = nil

        menu.removeAllItems()
        menu.minimumWidth = menuWidth

        // Now Playing 區
        if let track = currentTrack, !track.title.isEmpty {
            let nowPlayingItem = NSMenuItem()
            nowPlayingItem.view = createNowPlayingView(track: track)
            menu.addItem(nowPlayingItem)
            menu.addItem(NSMenuItem.separator())
        }

        // 音量 + 功能鍵區
        let volumeItem = NSMenuItem()
        volumeItem.view = createVolumeView()
        menu.addItem(volumeItem)

        let toggleItem = NSMenuItem()
        toggleItem.view = createToggleButtonsView()
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem.separator())

        // 待播清單區
        let queueHeaderItem = NSMenuItem()
        queueHeaderItem.view = createQueueHeaderView()
        menu.addItem(queueHeaderItem)

        if queueItems.isEmpty {
            JavaScriptBridge.executeCommand(.fetchQueue)
        } else {
            let queueViewItem = NSMenuItem()
            queueViewItem.view = createQueueView()
            menu.addItem(queueViewItem)
        }

        menu.addItem(NSMenuItem.separator())

        let showItem = NSMenuItem(title: "顯示視窗", action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "結束 YTMusic", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        debugConsole("[MenuBar] menuWillOpen")
        scheduleQueueRefresh(delay: 0)
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        debugConsole("[MenuBar] menuDidClose")
    }

    private func setupCallbacks() {
        JavaScriptBridge.shared.onPlaybackStateChanged = { [weak self] playing in
            DispatchQueue.main.async {
                self?.isPlaying = playing
                self?.updatePlayButtonIcon()
                if playing {
                    self?.scheduleQueueRefresh()
                }
                self?.refreshMenuContentsIfVisible()
            }
        }

        JavaScriptBridge.shared.onTrackChanged = { [weak self] track in
            DispatchQueue.main.async {
                debugConsole("[MenuBar] onTrackChanged title=\(track.title) artist=\(track.artist)")
                self?.currentTrack = track
                self?.currentArtwork = nil
                self?.artworkView?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
                self?.titleLabel?.stringValue = track.title
                self?.artistLabel?.stringValue = track.artist
                NowPlayingService.shared.showNotification(track: track)
                self?.scheduleQueueRefresh()

                if let urlString = track.artworkURL {
                    self?.loadArtwork(urlString: urlString)
                } else {
                    self?.artworkRequestTracker.clear()
                }
                self?.refreshMenuContentsIfVisible()
            }
        }

        JavaScriptBridge.shared.onVolumeChanged = { [weak self] vol in
            DispatchQueue.main.async {
                self?.volume = vol
            }
        }

        JavaScriptBridge.shared.onRepeatStateChanged = { [weak self] state in
            DispatchQueue.main.async {
                self?.repeatState = state
                self?.refreshMenuContentsIfVisible()
            }
        }

        JavaScriptBridge.shared.onShuffleStateChanged = { [weak self] enabled in
            DispatchQueue.main.async {
                self?.shuffleEnabled = enabled
                self?.refreshMenuContentsIfVisible()
            }
        }

        JavaScriptBridge.shared.onQueueUpdated = { [weak self] items in
            DispatchQueue.main.async {
                let summary = items.prefix(5).map { "\($0.title) | \($0.artist) | playing=\($0.isPlaying)" }.joined(separator: " || ")
                debugConsole("[MenuBar] onQueueUpdated count=\(items.count) \(summary)")
                self?.queueItems = items
                self?.loadQueueThumbnails(items)
                self?.refreshMenuContentsIfVisible()
            }
        }

        JavaScriptBridge.shared.onTimeUpdated = { [weak self] current, total in
            DispatchQueue.main.async {
                self?.currentTime = current
                self?.duration = total
                self?.updateProgressUI()
            }
        }
    }

    // MARK: - 即時 UI 更新（不重建 menu）

    private func updatePlayButtonIcon() {
        guard let button = playButton else { return }
        let symbolName = isPlaying ? "pause.fill" : "play.fill"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        }
    }

    private func updateProgressUI() {
        progressSlider?.maxValue = max(duration, 1)
        progressSlider?.doubleValue = currentTime
        elapsedLabel?.stringValue = formatTime(currentTime)
        let remaining = max(0, duration - currentTime)
        remainLabel?.stringValue = "-\(formatTime(remaining))"
    }

    private func refreshMenuContentsIfVisible() {
        guard isMenuOpen,
              let menu = statusItem?.menu else { return }
        menuNeedsUpdate(menu)
        menu.update()
    }

    private func scheduleQueueRefresh(delay: TimeInterval = 0.35) {
        queueRefreshWorkItem?.cancel()
        debugConsole("[MenuBar] scheduleQueueRefresh delay=\(delay)")

        let workItem = DispatchWorkItem {
            debugConsole("[MenuBar] execute fetchQueue")
            JavaScriptBridge.executeCommand(.fetchQueue)
        }
        queueRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func loadArtwork(urlString: String) {
        let requestID = artworkRequestTracker.start()

        // 嘗試取得較大尺寸的封面圖
        let highResURL = urlString
            .replacingOccurrences(of: "w60-h60", with: "w300-h300")
            .replacingOccurrences(of: "w120-h120", with: "w300-h300")
            .replacingOccurrences(of: "=w60", with: "=w300")
            .replacingOccurrences(of: "=w120", with: "=w300")

        let urls = [highResURL, urlString].compactMap { URL(string: $0) }
        loadArtworkFromURLs(urls, requestID: requestID)
    }

    private func loadArtworkFromURLs(_ urls: [URL], requestID: UUID) {
        guard let url = urls.first else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            if let data = data, let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    guard self?.artworkRequestTracker.accepts(requestID) == true else { return }
                    self?.currentArtwork = image
                    self?.artworkView?.image = image
                }
            } else {
                // fallback 到下一個 URL
                let remaining = Array(urls.dropFirst())
                if !remaining.isEmpty {
                    self?.loadArtworkFromURLs(remaining, requestID: requestID)
                }
            }
        }.resume()
    }

    // MARK: - Now Playing 區

    private func createNowPlayingView(track: TrackInfo) -> NSView {
        let padding: CGFloat = 12
        let artSize: CGFloat = 100
        let viewHeight: CGFloat = artSize + padding * 2
        let view = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: viewHeight))

        let rightX = padding + artSize + 12
        let rightWidth = menuWidth - rightX - padding

        // 封面圖 100x100 左側
        let imageView = NSImageView(frame: NSRect(x: padding, y: padding, width: artSize, height: artSize))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        imageView.image = currentArtwork ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        view.addSubview(imageView)
        self.artworkView = imageView

        // 歌名
        let titleY = padding + artSize - 18
        let titleLabel = NSTextField(labelWithString: track.title)
        titleLabel.frame = NSRect(x: rightX, y: titleY, width: rightWidth, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        view.addSubview(titleLabel)
        self.titleLabel = titleLabel

        // 歌手
        let artistY = titleY - 16
        let artistLabel = NSTextField(labelWithString: track.artist)
        artistLabel.frame = NSRect(x: rightX, y: artistY, width: rightWidth, height: 14)
        artistLabel.font = NSFont.systemFont(ofSize: 11)
        artistLabel.textColor = .secondaryLabelColor
        artistLabel.lineBreakMode = .byTruncatingTail
        view.addSubview(artistLabel)
        self.artistLabel = artistLabel

        // 播放控制按鈕
        let btnSize: CGFloat = 32
        let btnSpacing: CGFloat = 12
        let totalBtnWidth = btnSize * 3 + btnSpacing * 2
        let btnStartX = rightX + (rightWidth - totalBtnWidth) / 2
        let btnY = artistY - btnSize - 4

        let prevButton = createSymbolButton(
            symbolName: "backward.fill",
            frame: NSRect(x: btnStartX, y: btnY, width: btnSize, height: btnSize),
            action: #selector(previousClicked),
            fontSize: 13
        )
        view.addSubview(prevButton)

        let playSymbol = isPlaying ? "pause.fill" : "play.fill"
        let playBtn = createSymbolButton(
            symbolName: playSymbol,
            frame: NSRect(x: btnStartX + btnSize + btnSpacing, y: btnY, width: btnSize, height: btnSize),
            action: #selector(playPauseClicked),
            fontSize: 18
        )
        view.addSubview(playBtn)
        self.playButton = playBtn

        let nextButton = createSymbolButton(
            symbolName: "forward.fill",
            frame: NSRect(x: btnStartX + (btnSize + btnSpacing) * 2, y: btnY, width: btnSize, height: btnSize),
            action: #selector(nextClicked),
            fontSize: 13
        )
        view.addSubview(nextButton)

        // 進度條 + 時間
        let timeWidth: CGFloat = 38
        let progressY = padding

        let elapsed = NSTextField(labelWithString: formatTime(currentTime))
        elapsed.frame = NSRect(x: rightX, y: progressY, width: timeWidth, height: 12)
        elapsed.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        elapsed.textColor = .secondaryLabelColor
        elapsed.alignment = .left
        view.addSubview(elapsed)
        self.elapsedLabel = elapsed

        let sliderX = rightX + timeWidth + 2
        let sliderWidth = rightWidth - timeWidth * 2 - 4
        let slider = NSSlider(frame: NSRect(x: sliderX, y: progressY - 2, width: sliderWidth, height: 16))
        slider.minValue = 0
        slider.maxValue = max(duration, 1)
        slider.doubleValue = currentTime
        slider.target = self
        slider.action = #selector(progressSliderChanged(_:))
        slider.isContinuous = true
        view.addSubview(slider)
        self.progressSlider = slider

        let remaining = max(0, duration - currentTime)
        let remain = NSTextField(labelWithString: "-\(formatTime(remaining))")
        remain.frame = NSRect(x: rightX + rightWidth - timeWidth, y: progressY, width: timeWidth, height: 12)
        remain.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        remain.textColor = .secondaryLabelColor
        remain.alignment = .right
        view.addSubview(remain)
        self.remainLabel = remain

        return view
    }

    // MARK: - 音量 + Toggle 區

    private func createVolumeView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 30))
        let padding: CGFloat = 16
        let iconSize: CGFloat = 16

        let smallIcon = NSImageView(frame: NSRect(x: padding, y: 7, width: iconSize, height: iconSize))
        smallIcon.image = NSImage(systemSymbolName: "speaker.wave.1.fill", accessibilityDescription: "音量小")
        smallIcon.contentTintColor = .secondaryLabelColor
        view.addSubview(smallIcon)

        let sliderX = padding + iconSize + 8
        let sliderWidth = menuWidth - sliderX - padding - iconSize - 8
        let slider = NSSlider(frame: NSRect(x: sliderX, y: 5, width: sliderWidth, height: 20))
        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = Double(volume)
        slider.target = self
        slider.action = #selector(volumeSliderChanged(_:))
        slider.isContinuous = true
        view.addSubview(slider)

        let largeIcon = NSImageView(frame: NSRect(x: menuWidth - padding - iconSize, y: 7, width: iconSize, height: iconSize))
        largeIcon.image = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: "音量大")
        largeIcon.contentTintColor = .secondaryLabelColor
        view.addSubview(largeIcon)

        return view
    }

    private func createToggleButtonsView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 44))

        let buttonSize: CGFloat = 44
        let spacing: CGFloat = 32
        let totalWidth = buttonSize * 2 + spacing
        let startX = (menuWidth - totalWidth) / 2

        let repeatSymbol = repeatState == "one" ? "repeat.1" : "repeat"
        let repeatButton = createSymbolButton(
            symbolName: repeatSymbol,
            frame: NSRect(x: startX, y: 0, width: buttonSize, height: buttonSize),
            action: #selector(repeatClicked),
            fontSize: 14
        )
        if repeatState != "none" {
            repeatButton.contentTintColor = .controlAccentColor
        }
        view.addSubview(repeatButton)

        let shuffleButton = createSymbolButton(
            symbolName: "shuffle",
            frame: NSRect(x: startX + buttonSize + spacing, y: 0, width: buttonSize, height: buttonSize),
            action: #selector(shuffleClicked),
            fontSize: 14
        )
        if shuffleEnabled {
            shuffleButton.contentTintColor = .controlAccentColor
        }
        view.addSubview(shuffleButton)

        return view
    }

    // MARK: - 待播清單區

    private func createQueueHeaderView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 24))

        let label = NSTextField(labelWithString: "待播清單")
        label.frame = NSRect(x: 16, y: 3, width: 200, height: 18)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        view.addSubview(label)

        return view
    }

    private func createQueueView() -> NSView {
        let rowHeight: CGFloat = 52
        let maxVisible = 5
        let visibleHeight = min(CGFloat(queueItems.count), CGFloat(maxVisible)) * rowHeight
        let indicatorHeight: CGFloat = 16

        let containerHeight = visibleHeight
        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: containerHeight))

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: containerHeight))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false

        let totalHeight = CGFloat(queueItems.count) * rowHeight
        let documentView = FlippedView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: totalHeight))

        for (index, item) in queueItems.enumerated() {
            let rowView = createQueueRow(item: item, index: index, rowHeight: rowHeight)
            rowView.frame = NSRect(x: 0, y: CGFloat(index) * rowHeight, width: menuWidth, height: rowHeight)
            documentView.addSubview(rowView)
        }

        scrollView.documentView = documentView
        container.addSubview(scrollView)

        // ▲▼ 指示器（無半透明圖層，只有 chevron 圖示）
        if queueItems.count > maxVisible {
            let topInd = createScrollIndicator(
                frame: NSRect(x: 0, y: containerHeight - indicatorHeight, width: menuWidth, height: indicatorHeight),
                chevronName: "chevron.up"
            )
            container.addSubview(topInd)
            topInd.isHidden = true
            self.topIndicator = topInd

            let bottomInd = createScrollIndicator(
                frame: NSRect(x: 0, y: 0, width: menuWidth, height: indicatorHeight),
                chevronName: "chevron.down"
            )
            container.addSubview(bottomInd)
            self.bottomIndicator = bottomInd

            self.queueScrollView = scrollView
            if let documentView = scrollView.documentView {
                let maxOffset = max(0, documentView.frame.height - scrollView.frame.height)
                let restoredOffset = min(lastQueueScrollOffset, maxOffset)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: restoredOffset))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(queueDidScroll(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            scrollView.contentView.postsBoundsChangedNotifications = true
        }

        return container
    }

    private func createQueueRow(item: QueueItem, index: Int, rowHeight: CGFloat) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: rowHeight))
        let padding: CGFloat = 16
        let thumbSize: CGFloat = 32
        let timeWidth: CGFloat = 36

        // 縮圖
        let artworkFrame = NSRect(x: padding, y: (rowHeight - thumbSize) / 2, width: thumbSize, height: thumbSize)
        let artworkView = QueueArtworkHoverView(frame: artworkFrame)
        artworkView.configure(
            image: queueArtworkImage(for: item),
            isCurrentlyPlaying: item.isPlaying && isPlaying
        )
        artworkView.onActivate = { [weak self] in
            self?.playQueueItem(at: index)
        }
        row.addSubview(artworkView)

        let textX = padding + thumbSize + 8
        let textWidth = menuWidth - textX - padding - timeWidth - 4

        // 歌名
        let titleLabel = NSTextField(labelWithString: item.title)
        titleLabel.frame = NSRect(x: textX, y: rowHeight / 2 + 1, width: textWidth, height: 16)
        titleLabel.font = item.isPlaying
            ? NSFont.systemFont(ofSize: 12, weight: .semibold)
            : NSFont.systemFont(ofSize: 12)
        titleLabel.lineBreakMode = .byTruncatingTail
        row.addSubview(titleLabel)

        // 歌手
        let artistLabel = NSTextField(labelWithString: item.artist)
        artistLabel.frame = NSRect(x: textX, y: rowHeight / 2 - 15, width: textWidth, height: 14)
        artistLabel.font = NSFont.systemFont(ofSize: 10)
        artistLabel.textColor = .secondaryLabelColor
        artistLabel.lineBreakMode = .byTruncatingTail
        row.addSubview(artistLabel)

        // 時長
        if !item.duration.isEmpty {
            let timeLabel = NSTextField(labelWithString: item.duration)
            timeLabel.frame = NSRect(x: menuWidth - padding - timeWidth, y: (rowHeight - 14) / 2, width: timeWidth, height: 14)
            timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            timeLabel.textColor = .secondaryLabelColor
            timeLabel.alignment = .right
            row.addSubview(timeLabel)
        }

        // 分隔線
        let separator = NSView(frame: NSRect(x: textX, y: 0, width: menuWidth - textX - padding, height: 0.5))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        row.addSubview(separator)

        return row
    }

    // MARK: - ▲▼ 指示器（純圖示，無漸層）

    private func createScrollIndicator(frame: NSRect, chevronName: String) -> NSView {
        let view = NSView(frame: frame)

        let iconSize: CGFloat = 10
        let iconView = NSImageView(frame: NSRect(
            x: (frame.width - iconSize) / 2,
            y: (frame.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        ))
        if let img = NSImage(systemSymbolName: chevronName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .medium)
            iconView.image = img.withSymbolConfiguration(config)
        }
        iconView.contentTintColor = .tertiaryLabelColor
        view.addSubview(iconView)

        return view
    }

    @objc private func queueDidScroll(_ notification: Notification) {
        guard let scrollView = queueScrollView,
              let documentView = scrollView.documentView else { return }

        let clipBounds = scrollView.contentView.bounds
        lastQueueScrollOffset = clipBounds.origin.y
        let contentHeight = documentView.frame.height
        let viewHeight = scrollView.frame.height

        let atTop = clipBounds.origin.y <= 0
        let atBottom = clipBounds.origin.y + viewHeight >= contentHeight - 1

        topIndicator?.isHidden = atTop
        bottomIndicator?.isHidden = atBottom
    }

    // MARK: - 輔助方法

    private func createSymbolButton(symbolName: String, frame: NSRect, action: Selector, fontSize: CGFloat) -> NSButton {
        let button = NSButton(frame: frame)
        button.bezelStyle = .inline
        button.isBordered = false
        button.target = self
        button.action = action

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: fontSize, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        }

        button.imagePosition = .imageOnly
        button.contentTintColor = .labelColor

        return button
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }

    private func queueArtworkImage(for item: QueueItem) -> NSImage? {
        if item.isPlaying && isPlaying {
            return NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "正在播放")
        }

        if let urlStr = item.thumbnailURL, let cached = queueThumbnails[urlStr] {
            return cached
        }

        return NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
    }

    private func loadQueueThumbnails(_ items: [QueueItem]) {
        for item in items {
            guard let urlStr = item.thumbnailURL,
                  queueThumbnails[urlStr] == nil,
                  let url = URL(string: urlStr) else { continue }

            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    self?.queueThumbnails[urlStr] = image
                    self?.refreshMenuContentsIfVisible()
                }
            }.resume()
        }
    }

    // MARK: - 選單動作

    @objc private func playPauseClicked() {
        JavaScriptBridge.executeCommand(.playPause)
    }

    @objc private func nextClicked() {
        JavaScriptBridge.executeCommand(.next)
    }

    @objc private func previousClicked() {
        JavaScriptBridge.executeCommand(.previous)
    }

    @objc private func volumeSliderChanged(_ sender: NSSlider) {
        let value = Float(sender.doubleValue)
        volume = value
        JavaScriptBridge.executeCommand(.setVolume(value))
    }

    @objc private func progressSliderChanged(_ sender: NSSlider) {
        let time = sender.doubleValue
        currentTime = time
        JavaScriptBridge.executeCommand(.seekTo(time))
    }

    @objc private func repeatClicked() {
        JavaScriptBridge.executeCommand(.toggleRepeat)
    }

    @objc private func shuffleClicked() {
        JavaScriptBridge.executeCommand(.toggleShuffle)
    }

    @objc private func queueItemClicked(_ sender: NSButton) {
        let index = sender.tag
        playQueueItem(at: index)
    }

    private func playQueueItem(at index: Int) {
        JavaScriptBridge.executeCommand(.playQueueItem(index))
    }

    @objc private func showWindow() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showWindow()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - 翻轉座標 NSView（從上往下排列）

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class QueueArtworkHoverView: NSView {
    private let imageView = NSImageView()
    private let overlayButtonView = NSView()
    private let iconView = NSImageView()
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false
    private var isCurrentlyPlaying = false
    var onActivate: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(image: NSImage?, isCurrentlyPlaying: Bool) {
        self.isCurrentlyPlaying = isCurrentlyPlaying
        imageView.image = image
        imageView.contentTintColor = isCurrentlyPlaying ? .controlAccentColor : .tertiaryLabelColor
        refreshOverlay()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .inVisibleRect]
        let trackingAreaRef = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingAreaRef)
        self.trackingAreaRef = trackingAreaRef
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        refreshOverlay()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        refreshOverlay()
    }

    override func mouseUp(with event: NSEvent) {
        guard event.type == .leftMouseUp else { return }
        onActivate?()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true

        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)

        let buttonSize: CGFloat = 24
        overlayButtonView.frame = NSRect(
            x: (bounds.width - buttonSize) / 2,
            y: (bounds.height - buttonSize) / 2,
            width: buttonSize,
            height: buttonSize
        )
        overlayButtonView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        overlayButtonView.wantsLayer = true
        overlayButtonView.layer?.cornerRadius = buttonSize / 2
        overlayButtonView.layer?.masksToBounds = true
        overlayButtonView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        overlayButtonView.layer?.borderWidth = 0.5
        overlayButtonView.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        overlayButtonView.isHidden = true
        addSubview(overlayButtonView)

        let iconSize: CGFloat = 12
        iconView.frame = NSRect(
            x: (buttonSize - iconSize) / 2,
            y: (buttonSize - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        iconView.contentTintColor = .white
        overlayButtonView.addSubview(iconView)
    }

    private func refreshOverlay() {
        overlayButtonView.isHidden = !isHovering

        let symbolName: String
        if isCurrentlyPlaying {
            symbolName = "pause.fill"
        } else {
            symbolName = "play.fill"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            iconView.image = image.withSymbolConfiguration(config)
        }
    }
}

public struct ArtworkRequestTracker {
    private var currentRequestID: UUID?

    public init() {}

    public mutating func start() -> UUID {
        let requestID = UUID()
        currentRequestID = requestID
        return requestID
    }

    public mutating func clear() {
        currentRequestID = nil
    }

    public func accepts(_ requestID: UUID) -> Bool {
        currentRequestID == requestID
    }
}
