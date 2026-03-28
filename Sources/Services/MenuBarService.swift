import Cocoa
import SwiftUI

/// Menu Bar 常駐圖示服務
class MenuBarService {
    static let shared = MenuBarService()

    private var statusItem: NSStatusItem?
    private var isPlaying = false
    private var currentTrack: TrackInfo?
    private var currentArtwork: NSImage?

    private init() {
        setupStatusItem()
        setupCallbacks()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "YTMusic")
        }

        updateMenu()
    }

    private func setupCallbacks() {
        JavaScriptBridge.shared.onPlaybackStateChanged = { [weak self] playing in
            DispatchQueue.main.async {
                self?.isPlaying = playing
                self?.updateMenu()
            }
        }

        JavaScriptBridge.shared.onTrackChanged = { [weak self] track in
            DispatchQueue.main.async {
                self?.currentTrack = track
                self?.currentArtwork = nil
                self?.updateMenu()
                NowPlayingService.shared.showNotification(track: track)

                // 非同步載入封面圖
                if let urlString = track.artworkURL, let url = URL(string: urlString) {
                    URLSession.shared.dataTask(with: url) { data, _, _ in
                        guard let data = data, let image = NSImage(data: data) else { return }
                        DispatchQueue.main.async {
                            self?.currentArtwork = image
                            self?.updateMenu()
                        }
                    }.resume()
                }
            }
        }
    }

    private func updateMenu() {
        let menu = NSMenu()

        // 顯示目前歌曲（含封面圖）
        if let track = currentTrack, !track.title.isEmpty {
            let trackView = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 60))

            // 封面圖
            let imageView = NSImageView(frame: NSRect(x: 16, y: 8, width: 44, height: 44))
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 6
            imageView.layer?.masksToBounds = true
            if let artwork = currentArtwork {
                imageView.image = artwork
            } else {
                imageView.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
            }
            trackView.addSubview(imageView)

            // 歌名
            let titleLabel = NSTextField(labelWithString: track.title)
            titleLabel.frame = NSRect(x: 68, y: 30, width: 170, height: 18)
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            titleLabel.lineBreakMode = .byTruncatingTail
            trackView.addSubview(titleLabel)

            // 歌手
            if !track.artist.isEmpty {
                let artistLabel = NSTextField(labelWithString: track.artist)
                artistLabel.frame = NSRect(x: 68, y: 12, width: 170, height: 16)
                artistLabel.font = NSFont.systemFont(ofSize: 11)
                artistLabel.textColor = .secondaryLabelColor
                artistLabel.lineBreakMode = .byTruncatingTail
                trackView.addSubview(artistLabel)
            }

            let trackItem = NSMenuItem()
            trackItem.view = trackView
            menu.addItem(trackItem)
            menu.addItem(NSMenuItem.separator())
        }

        // 播放控制
        let playPauseTitle = isPlaying ? "⏸ 暫停" : "▶ 播放"
        let playPauseItem = NSMenuItem(title: playPauseTitle, action: #selector(playPauseClicked), keyEquivalent: "")
        playPauseItem.target = self
        menu.addItem(playPauseItem)

        let nextItem = NSMenuItem(title: "⏭ 下一首", action: #selector(nextClicked), keyEquivalent: "")
        nextItem.target = self
        menu.addItem(nextItem)

        let prevItem = NSMenuItem(title: "⏮ 上一首", action: #selector(previousClicked), keyEquivalent: "")
        prevItem.target = self
        menu.addItem(prevItem)

        menu.addItem(NSMenuItem.separator())

        // 視窗控制
        let showItem = NSMenuItem(title: "顯示視窗", action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        // 結束
        let quitItem = NSMenuItem(title: "結束 YTMusic", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
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

    @objc private func showWindow() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showWindow()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
