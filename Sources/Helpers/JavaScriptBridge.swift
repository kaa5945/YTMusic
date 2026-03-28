import WebKit
import Foundation

/// Swift ↔ JavaScript 雙向通訊橋接
class JavaScriptBridge: NSObject, WKScriptMessageHandler {
    static let shared = JavaScriptBridge()

    /// 歌曲資訊變更回呼
    var onTrackChanged: ((TrackInfo) -> Void)?
    /// 播放狀態變更回呼
    var onPlaybackStateChanged: ((Bool) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
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

        default:
            break
        }
    }

    // MARK: - Swift → JavaScript 控制

    static func executeCommand(_ command: PlayerCommand) {
        let js: String
        switch command {
        case .playPause:
            js = "document.querySelector('#play-pause-button')?.click();"
        case .next:
            js = "document.querySelector('.next-button')?.click();"
        case .previous:
            js = "document.querySelector('.previous-button')?.click();"
        }
        WebViewManager.shared.webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("[JSBridge] 執行指令失敗: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 注入到網頁的監聽腳本

    /// 監聽 YouTube Music 的歌曲資訊與播放狀態變化
    static let monitorScript = """
    (function() {
        'use strict';

        let lastTitle = '';
        let lastIsPlaying = null;

        function getTrackInfo() {
            // 優先使用 Media Session API（更穩定）
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

            // Fallback: 從 DOM 取得
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

        function checkForChanges() {
            const info = getTrackInfo();
            if (info.title && info.title !== lastTitle) {
                lastTitle = info.title;
                window.webkit.messageHandlers.nowPlaying.postMessage(info);
            }

            const isPlaying = getPlaybackState();
            if (isPlaying !== lastIsPlaying) {
                lastIsPlaying = isPlaying;
                window.webkit.messageHandlers.playbackState.postMessage({ isPlaying });
            }
        }

        // 定期檢查變化（500ms 間隔）
        setInterval(checkForChanges, 500);

        // 同時監聽 video 事件
        function observeVideo() {
            const video = document.querySelector('video');
            if (video) {
                video.addEventListener('play', () => {
                    window.webkit.messageHandlers.playbackState.postMessage({ isPlaying: true });
                });
                video.addEventListener('pause', () => {
                    window.webkit.messageHandlers.playbackState.postMessage({ isPlaying: false });
                });
            } else {
                setTimeout(observeVideo, 1000);
            }
        }
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

enum PlayerCommand {
    case playPause
    case next
    case previous
}
