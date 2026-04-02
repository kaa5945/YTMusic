import WebKit
import Foundation

func debugConsole(_ message: String) {
    guard let data = "\(message)\n".data(using: .utf8) else { return }
    FileHandle.standardError.write(data)
    fflush(stderr)

    let logURL = URL(fileURLWithPath: "/tmp/ytmusic-inapp.log")
    if !FileManager.default.fileExists(atPath: logURL.path) {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
    }

    do {
        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    } catch {
        FileHandle.standardError.write("debugConsole file write failed: \(error)\n".data(using: .utf8)!)
        fflush(stderr)
    }
}

/// Swift ↔ JavaScript 雙向通訊橋接
public final class JavaScriptBridge: NSObject, WKScriptMessageHandler {
    static let shared = JavaScriptBridge()

    /// 歌曲資訊變更回呼
    var onTrackChanged: ((TrackInfo) -> Void)?
    /// 播放狀態變更回呼
    var onPlaybackStateChanged: ((Bool) -> Void)?
    /// 音量變更回呼
    var onVolumeChanged: ((Float) -> Void)?
    /// 循環狀態變更回呼
    var onRepeatStateChanged: ((String) -> Void)?
    /// 隨機播放狀態變更回呼
    var onShuffleStateChanged: ((Bool) -> Void)?
    /// 播放清單變更回呼
    var onQueueUpdated: (([QueueItem]) -> Void)?
    /// 播放時間變更回呼 (currentTime, duration)
    var onTimeUpdated: ((Double, Double) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - WKScriptMessageHandler

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "nowPlaying":
            guard let body = message.body as? [String: Any] else { return }
            let track = TrackInfo(
                title: body["title"] as? String ?? "",
                artist: body["artist"] as? String ?? "",
                album: body["album"] as? String ?? "",
                artworkURL: body["artworkURL"] as? String
            )
            if !track.title.isEmpty {
                onTrackChanged?(track)
            }

        case "playbackState":
            guard let body = message.body as? [String: Any],
                  let isPlaying = body["isPlaying"] as? Bool else { return }
            onPlaybackStateChanged?(isPlaying)

        case "volumeChanged":
            guard let body = message.body as? [String: Any],
                  let volume = body["volume"] as? Double else { return }
            onVolumeChanged?(Float(volume))

        case "repeatState":
            guard let body = message.body as? [String: Any],
                  let state = body["state"] as? String else { return }
            onRepeatStateChanged?(state)

        case "shuffleState":
            guard let body = message.body as? [String: Any],
                  let enabled = body["enabled"] as? Bool else { return }
            onShuffleStateChanged?(enabled)

        case "queueUpdate":
            guard let body = message.body as? [String: Any],
                  let items = body["items"] as? [[String: Any]] else { return }
            let queue = items.map { item in
                QueueItem(
                    title: item["title"] as? String ?? "",
                    artist: item["artist"] as? String ?? "",
                    isPlaying: item["isPlaying"] as? Bool ?? false,
                    duration: item["duration"] as? String ?? "",
                    thumbnailURL: item["thumbnailURL"] as? String
                )
            }
            onQueueUpdated?(queue)

        case "timeUpdate":
            guard let body = message.body as? [String: Any],
                  let currentTime = body["currentTime"] as? Double,
                  let duration = body["duration"] as? Double else { return }
            onTimeUpdated?(currentTime, duration)

        case "debugLog":
            if let body = message.body as? String {
                debugConsole("[JSDebug] \(body)")
            } else {
                debugConsole("[JSDebug] \(message.body)")
            }

        default:
            break
        }
    }

    // MARK: - Swift → JavaScript 控制

    static func executeCommand(_ command: PlayerCommand) {
        let js = script(for: command)
        WebViewManager.shared.webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                debugConsole("[JSBridge] 執行指令失敗: \(error.localizedDescription)")
            }
        }
    }

    public static func script(for command: PlayerCommand) -> String {
        switch command {
        case .playPause:
            return "document.querySelector('#play-pause-button')?.click();"
        case .next:
            return "document.querySelector('.next-button')?.click();"
        case .previous:
            return "document.querySelector('.previous-button')?.click();"
        case .setVolume(let value):
            let clamped = max(0, min(1, value))
            return """
            (function() {
                var v = document.querySelector('video');
                if (v) { v.volume = \(clamped); }
                var slider = document.querySelector('#volume-slider');
                if (slider) { slider.value = \(Int(clamped * 100)); slider.dispatchEvent(new Event('input')); }
            })();
            """
        case .seekTo(let time):
            return """
            (function() {
                var v = document.querySelector('video');
                if (v) { v.currentTime = \(time); }
            })();
            """
        case .toggleRepeat:
            return "document.querySelector('.repeat.ytmusic-player-bar')?.click();"
        case .toggleShuffle:
            return "document.querySelector('.shuffle.ytmusic-player-bar')?.click();"
        case .fetchQueue:
            return """
            (function() {
                var entries = window.__ytmusicCodexGetQueueRows ? window.__ytmusicCodexGetQueueRows() : [];
                window.webkit.messageHandlers.debugLog.postMessage('fetchQueue entries=' + entries.length);
                var items = entries
                    .map(function(entry) { return entry.item; });
                window.webkit.messageHandlers.queueUpdate.postMessage({ items: items });
            })();
            """
        case .playQueueItem(let index):
            return """
            (function() {
                var entries = window.__ytmusicCodexGetQueueRows ? window.__ytmusicCodexGetQueueRows() : [];
                var row = entries[\(index)]?.row;
                window.webkit.messageHandlers.debugLog.postMessage('playQueueItem index=\(index) entries=' + entries.length + ' hasRow=' + !!row);
                if (row) {
                    var playButton =
                        row.querySelector('ytmusic-play-button-renderer button') ||
                        row.querySelector('ytmusic-play-button-renderer tp-yt-paper-icon-button') ||
                        row.querySelector('ytmusic-play-button-renderer .content-wrapper') ||
                        row.querySelector('[id=\"play-button\"]') ||
                        row.querySelector('[aria-label*=\"Play\"]') ||
                        row.querySelector('[aria-label*=\"播放\"]');
                    var songLink = row.querySelector('a[href*=\"/watch\"]');
                    var primaryTarget = playButton || songLink || row;
                    var title = row.querySelector('.song-title')?.textContent?.trim() || '';
                    var artist = row.querySelector('.byline')?.textContent?.trim() || '';
                    window.webkit.messageHandlers.debugLog.postMessage(
                        'playQueueItem target title=' + title +
                        ' artist=' + artist +
                        ' hasPlayButton=' + !!playButton +
                        ' hasSongLink=' + !!songLink +
                        ' link=' + (songLink ? songLink.href : 'none')
                    );

                    if (songLink && songLink.href) {
                        window.webkit.messageHandlers.debugLog.postMessage('playQueueItem using location.assign');
                        window.location.assign(songLink.href);
                        return;
                    }

                    function fireMouseSequence(element) {
                        if (!element) return;
                        var events = [
                            { type: 'mousedown', detail: 1 },
                            { type: 'mouseup', detail: 1 },
                            { type: 'click', detail: 1 },
                            { type: 'mousedown', detail: 2 },
                            { type: 'mouseup', detail: 2 },
                            { type: 'click', detail: 2 },
                            { type: 'dblclick', detail: 2 }
                        ];

                        events.forEach(function(eventInfo) {
                            element.dispatchEvent(new MouseEvent(eventInfo.type, {
                                bubbles: true,
                                cancelable: true,
                                composed: true,
                                button: 0,
                                buttons: 1,
                                detail: eventInfo.detail
                            }));
                        });
                    }

                    if (primaryTarget.click) {
                        window.webkit.messageHandlers.debugLog.postMessage('playQueueItem invoking click on primary target');
                        primaryTarget.click();
                    }
                    fireMouseSequence(primaryTarget);

                    if (primaryTarget !== row) {
                        window.webkit.messageHandlers.debugLog.postMessage('playQueueItem firing fallback row sequence');
                        fireMouseSequence(row);
                    }
                }
            })();
            """
        }
    }

    // MARK: - 注入到網頁的監聽腳本

    /// 監聽 YouTube Music 的歌曲資訊、播放狀態、音量、循環、隨機、時間變化
    public static let monitorScript = """
    (function() {
        'use strict';

        let lastTrackKey = '';
        let lastIsPlaying = null;
        let lastVolume = null;
        let lastRepeat = null;
        let lastShuffle = null;
        let lastTimeReport = 0;
        let observedVideo = null;

        function buildTrackKey(info) {
            return [info.title || '', info.artist || '', info.album || '', info.artworkURL || ''].join('|');
        }

        function isElementVisible(element) {
            if (!element) return false;
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            if (style.display === 'none' || style.visibility === 'hidden') return false;
            if (element.hidden || element.closest('[hidden], [aria-hidden="true"]')) return false;
            return rect.width > 0 && rect.height > 0;
        }

        function normalizeImageURL(value) {
            if (!value || typeof value !== 'string') return null;
            const trimmed = value.trim();
            if (!trimmed || trimmed === 'about:blank') return null;
            if (trimmed.startsWith('data:image/gif')) return null;
            if (trimmed === window.location.href || trimmed === document.baseURI) return null;
            return trimmed;
        }

        function parseSrcset(value) {
            const srcset = normalizeImageURL(value);
            if (!srcset) return null;
            const firstCandidate = srcset.split(',')[0]?.trim() || '';
            const url = firstCandidate.split(/\\s+/)[0];
            return normalizeImageURL(url);
        }

        function extractBackgroundImageURL(element) {
            if (!element) return null;
            const style = window.getComputedStyle(element);
            const backgroundImage = style.backgroundImage || '';
            const match = backgroundImage.match(/url\\(["']?(.*?)["']?\\)/);
            return normalizeImageURL(match && match[1]);
        }

        function getImageURL(row) {
            const img = row.querySelector('img');
            const thumbnailElement =
                img ||
                row.querySelector('[style*="background-image"]') ||
                row.querySelector('.thumbnail-image-wrapper') ||
                row.querySelector('.thumbnail');

            if (img) {
                const candidate = [
                    normalizeImageURL(img.dataset?.src),
                    normalizeImageURL(img.dataset?.thumbnailUrl),
                    normalizeImageURL(img.dataset?.thumb),
                    parseSrcset(img.getAttribute('srcset')),
                    normalizeImageURL(img.currentSrc),
                    normalizeImageURL(img.getAttribute('src'))
                ].find(Boolean);

                if (candidate) return candidate;
            }

            if (thumbnailElement) {
                const candidate = [
                    normalizeImageURL(thumbnailElement.getAttribute && thumbnailElement.getAttribute('src')),
                    normalizeImageURL(thumbnailElement.dataset?.src),
                    normalizeImageURL(thumbnailElement.dataset?.thumbnailUrl),
                    normalizeImageURL(thumbnailElement.dataset?.thumb),
                    parseSrcset(thumbnailElement.getAttribute && thumbnailElement.getAttribute('srcset')),
                    extractBackgroundImageURL(thumbnailElement)
                ].find(Boolean);

                if (candidate) return candidate;
            }

            return null;
        }

        function getQueueRows() {
            const allRows = Array.from(document.querySelectorAll('ytmusic-player-queue-item'));
            const visibleRows = allRows.filter(isElementVisible);
            const selectedRow =
                visibleRows.find(function(row) { return row.hasAttribute('selected'); }) ||
                allRows.find(function(row) { return row.hasAttribute('selected'); });

            let scopedRows = visibleRows.length > 0 ? visibleRows : allRows;

            if (selectedRow) {
                let container = selectedRow.parentElement;
                while (container && container !== document.body) {
                    const directRows = Array.from(container.children)
                        .filter(function(child) { return child.matches && child.matches('ytmusic-player-queue-item'); })
                        .filter(isElementVisible);

                    if (directRows.length > 1) {
                        scopedRows = directRows;
                        break;
                    }

                    container = container.parentElement;
                }
            }

            const items = [];
            let foundSelected = false;

            scopedRows.forEach(function(row) {
                const title = row.querySelector('.song-title')?.textContent?.trim() || '';
                const artist = row.querySelector('.byline')?.textContent?.trim() || '';
                if (!title) return;

                const selected = row.hasAttribute('selected') && !foundSelected;
                if (selected) foundSelected = true;

                const durationEl = row.querySelector('.duration');

                items.push({
                    row: row,
                    item: {
                        title: title,
                        artist: artist,
                        isPlaying: selected,
                        duration: durationEl ? durationEl.textContent.trim() : '',
                        thumbnailURL: getImageURL(row)
                    }
                });
            });

            return items;
        }

        function getTrackInfo() {
            if (navigator.mediaSession && navigator.mediaSession.metadata) {
                const meta = navigator.mediaSession.metadata;
                const artwork = meta.artwork && meta.artwork.length > 0 ? meta.artwork[meta.artwork.length - 1].src : null;
                return {
                    title: meta.title || '',
                    artist: meta.artist || '',
                    album: meta.album || '',
                    artworkURL: artwork
                };
            }

            const title = document.querySelector('.title.ytmusic-player-bar')?.textContent?.trim() || '';
            const artist = document.querySelector('.byline.ytmusic-player-bar a')?.textContent?.trim() || '';
            const img = document.querySelector('.image.ytmusic-player-bar img');
            const artworkURL = img ? img.src : null;

            return { title, artist, album: '', artworkURL };
        }

        function getPlaybackState() {
            const video = document.querySelector('video');
            return video ? !video.paused : false;
        }

        function getRepeatState() {
            const btn = document.querySelector('.repeat.ytmusic-player-bar');
            if (!btn) return 'none';
            const ariaLabel = btn.getAttribute('aria-label') || btn.getAttribute('title') || '';
            if (ariaLabel.includes('one') || ariaLabel.includes('單曲')) return 'one';
            if (ariaLabel.includes('off') || ariaLabel.includes('關閉') || ariaLabel.includes('不重複')) return 'all';
            return 'none';
        }

        function getShuffleState() {
            const btn = document.querySelector('.shuffle.ytmusic-player-bar');
            if (!btn) return false;
            const ariaLabel = btn.getAttribute('aria-label') || btn.getAttribute('title') || '';
            return ariaLabel.includes('on') || ariaLabel.includes('開啟') || btn.getAttribute('aria-pressed') === 'true';
        }

        function checkForChanges() {
            const info = getTrackInfo();
            const trackKey = buildTrackKey(info);
            if (info.title && trackKey !== lastTrackKey) {
                lastTrackKey = trackKey;
                window.webkit.messageHandlers.nowPlaying.postMessage(info);
            }

            const isPlaying = getPlaybackState();
            if (isPlaying !== lastIsPlaying) {
                lastIsPlaying = isPlaying;
                window.webkit.messageHandlers.playbackState.postMessage({ isPlaying });
            }

            const video = document.querySelector('video');
            if (video) {
                const vol = video.volume;
                if (vol !== lastVolume) {
                    lastVolume = vol;
                    window.webkit.messageHandlers.volumeChanged.postMessage({ volume: vol });
                }
            }

            const repeatState = getRepeatState();
            if (repeatState !== lastRepeat) {
                lastRepeat = repeatState;
                window.webkit.messageHandlers.repeatState.postMessage({ state: repeatState });
            }

            const shuffleState = getShuffleState();
            if (shuffleState !== lastShuffle) {
                lastShuffle = shuffleState;
                window.webkit.messageHandlers.shuffleState.postMessage({ enabled: shuffleState });
            }
        }

        setInterval(function() {
            checkForChanges();
            observeVideo();
        }, 500);

        function bindVideoEvents(video) {
            if (!video || video === observedVideo) return;
            observedVideo = video;

            video.addEventListener('play', () => {
                window.webkit.messageHandlers.playbackState.postMessage({ isPlaying: true });
            });
            video.addEventListener('pause', () => {
                window.webkit.messageHandlers.playbackState.postMessage({ isPlaying: false });
            });
            video.addEventListener('volumechange', () => {
                window.webkit.messageHandlers.volumeChanged.postMessage({ volume: video.volume });
            });
            video.addEventListener('timeupdate', () => {
                const now = Date.now();
                if (now - lastTimeReport >= 1000) {
                    lastTimeReport = now;
                    window.webkit.messageHandlers.timeUpdate.postMessage({
                        currentTime: video.currentTime,
                        duration: video.duration || 0
                    });
                }
            });
        }

        function observeVideo() {
            const video = document.querySelector('video');
            if (video) {
                bindVideoEvents(video);
            } else {
                setTimeout(observeVideo, 1000);
            }
        }
        window.__ytmusicCodexGetQueueRows = getQueueRows;
        window.__ytmusicCodexObserveVideo = observeVideo;
        window.__ytmusicCodexBindVideoEvents = bindVideoEvents;
        new MutationObserver(observeVideo).observe(document.documentElement, { childList: true, subtree: true });
        observeVideo();
    })();
    """
}

// MARK: - 資料模型

struct TrackInfo {
    let title: String
    let artist: String
    let album: String
    let artworkURL: String?
}

struct QueueItem {
    let title: String
    let artist: String
    let isPlaying: Bool
    let duration: String
    let thumbnailURL: String?
}

public enum PlayerCommand {
    case playPause
    case next
    case previous
    case setVolume(Float)
    case seekTo(Double)
    case toggleRepeat
    case toggleShuffle
    case fetchQueue
    case playQueueItem(Int)
}
