import AppKit
import Foundation
import ObjectiveC
import WebKit
import YTMusicCore

@MainActor
@main
struct SmokeTestsRunner {
    static func main() {
        _ = NSApplication.shared

        do {
            try testNowPlayingUsesFullTrackFingerprint()
            try testQueueFetchAndPlayUseSameIndexMapping()
            try testQueueFetchExtractsThumbnailFromLazyImageAttributes()
            try testReplacingVideoElementRebindsTimeupdateListener()
            try testArtworkRequestTrackerAcceptsOnlyLatestRequest()
            print("Smoke tests passed")
        } catch {
            fputs("Smoke tests failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func testNowPlayingUsesFullTrackFingerprint() throws {
        let recorder = ScriptMessageRecorder()
        let webView = makeWebView(recorder: recorder)

        try loadHTML(
            """
            <html>
            <body>
                <script>
                    Object.defineProperty(navigator, 'mediaSession', {
                        configurable: true,
                        value: {
                            metadata: {
                                title: 'Same Title',
                                artist: 'Artist A',
                                album: 'Album',
                                artwork: [{ src: 'https://example.com/a.png' }]
                            }
                        }
                    });
                    setTimeout(() => {
                        navigator.mediaSession.metadata = {
                            title: 'Same Title',
                            artist: 'Artist B',
                            album: 'Album',
                            artwork: [{ src: 'https://example.com/b.png' }]
                        };
                    }, 700);
                </script>
            </body>
            </html>
            """,
            in: webView
        )

        let messages = try recorder.waitForMessages(named: "nowPlaying", count: 2, timeout: 3)
        let artists = messages.compactMap { ($0 as? [String: Any])?["artist"] as? String }
        try expect(artists == ["Artist A", "Artist B"], "預期同標題不同歌手要送出兩次 nowPlaying")
    }

    private static func testQueueFetchAndPlayUseSameIndexMapping() throws {
        let recorder = ScriptMessageRecorder()
        let webView = makeWebView(recorder: recorder)

        try loadHTML(
            """
            <html>
            <body>
                <ytmusic-player-queue-item selected>
                    <div class="song-title">Song A</div>
                    <div class="byline">Artist A</div>
                    <div class="duration">3:00</div>
                </ytmusic-player-queue-item>
                <ytmusic-player-queue-item>
                    <div class="song-title">Song B</div>
                    <div class="byline">Artist B</div>
                    <div class="duration">4:00</div>
                </ytmusic-player-queue-item>
                <ytmusic-player-queue-item>
                    <div class="song-title">Song A</div>
                    <div class="byline">Artist A</div>
                    <div class="duration">3:00</div>
                </ytmusic-player-queue-item>
                <script>
                    document.querySelectorAll('ytmusic-player-queue-item').forEach((row) => {
                        row.addEventListener('dblclick', () => {
                            window.clickedKey = [
                                row.querySelector('.song-title').textContent.trim(),
                                row.querySelector('.byline').textContent.trim()
                            ].join('|');
                        });
                    });
                </script>
            </body>
            </html>
            """,
            in: webView
        )

        _ = try evaluate(JavaScriptBridge.script(for: .fetchQueue), in: webView)
        let queueMessages = try recorder.waitForMessages(named: "queueUpdate", count: 1, timeout: 2)
        let items = ((queueMessages[0] as? [String: Any])?["items"] as? [[String: Any]]) ?? []
        try expect(items.count == 3, "預期 queue 要保留完整順序，包含重複歌曲")
        try expect(items[safe: 1]?["title"] as? String == "Song B", "預期索引 1 對應 Song B")
        try expect(items[safe: 2]?["title"] as? String == "Song A", "預期重複歌曲仍保留在原始索引")

        _ = try evaluate(JavaScriptBridge.script(for: .playQueueItem(1)), in: webView)
        let clicked = try evaluate("window.clickedKey", in: webView) as? String
        try expect(clicked == "Song B|Artist B", "預期點擊索引 1 播放 Song B")
    }

    private static func testReplacingVideoElementRebindsTimeupdateListener() throws {
        let recorder = ScriptMessageRecorder()
        let webView = makeWebView(recorder: recorder)

        try loadHTML(
            """
            <html>
            <body>
                <video id="player"></video>
                <script>
                    function configureVideo(video, currentTime, duration) {
                        Object.defineProperty(video, 'duration', {
                            configurable: true,
                            value: duration
                        });
                        video.currentTime = currentTime;
                    }

                    configureVideo(document.getElementById('player'), 10, 180);

                    window.replaceVideo = function() {
                        const next = document.createElement('video');
                        next.id = 'player-2';
                        configureVideo(next, 42, 240);
                        document.body.replaceChild(next, document.getElementById('player'));
                        [1300, 2200, 3100].forEach((delay) => {
                            setTimeout(() => next.dispatchEvent(new Event('timeupdate')), delay);
                        });
                    };
                </script>
            </body>
            </html>
            """,
            in: webView
        )

        _ = try evaluate(
            """
            window.replaceVideo();
            if (window.__ytmusicCodexBindVideoEvents) {
                window.__ytmusicCodexBindVideoEvents(document.getElementById('player-2'));
            } else if (window.__ytmusicCodexObserveVideo) {
                window.__ytmusicCodexObserveVideo();
            }
            """,
            in: webView
        )
        let payload = try recorder.waitForMessage(named: "timeUpdate", timeout: 5) { message in
            let body = message as? [String: Any]
            return body?["currentTime"] as? Double == 42 && body?["duration"] as? Double == 240
        } as? [String: Any]
        try expect(payload?["currentTime"] as? Double == 42, "預期新 video 的 currentTime 要送到 Swift")
        try expect(payload?["duration"] as? Double == 240, "預期新 video 的 duration 要送到 Swift")
    }

    private static func testQueueFetchExtractsThumbnailFromLazyImageAttributes() throws {
        let recorder = ScriptMessageRecorder()
        let webView = makeWebView(recorder: recorder)

        try loadHTML(
            """
            <html>
            <body>
                <ytmusic-player-queue-item selected>
                    <img src="https://example.com/cover-a.jpg">
                    <div class="song-title">Song A</div>
                    <div class="byline">Artist A</div>
                    <div class="duration">3:00</div>
                </ytmusic-player-queue-item>
                <ytmusic-player-queue-item>
                    <img src="" srcset="https://example.com/cover-b.jpg 1x, https://example.com/cover-b@2x.jpg 2x">
                    <div class="song-title">Song B</div>
                    <div class="byline">Artist B</div>
                    <div class="duration">4:00</div>
                </ytmusic-player-queue-item>
            </body>
            </html>
            """,
            in: webView
        )

        _ = try evaluate(JavaScriptBridge.script(for: .fetchQueue), in: webView)
        let queueMessages = try recorder.waitForMessages(named: "queueUpdate", count: 1, timeout: 2)
        let items = ((queueMessages[0] as? [String: Any])?["items"] as? [[String: Any]]) ?? []

        try expect(items.count == 2, "預期 queue 要抓到兩首歌")
        try expect(items[safe: 1]?["thumbnailURL"] as? String == "https://example.com/cover-b.jpg", "預期 lazy-load row 也要解析出縮圖 URL")
    }

    private static func testArtworkRequestTrackerAcceptsOnlyLatestRequest() throws {
        var tracker = ArtworkRequestTracker()
        let first = tracker.start()
        let second = tracker.start()

        try expect(!tracker.accepts(first), "舊封面 request 不應被接受")
        try expect(tracker.accepts(second), "最新封面 request 應被接受")

        tracker.clear()
        try expect(!tracker.accepts(second), "清除後不應再接受舊 request")
    }

    private static func makeWebView(recorder: ScriptMessageRecorder) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        configuration.userContentController = controller

        for name in ["nowPlaying", "playbackState", "volumeChanged", "repeatState", "shuffleState", "queueUpdate", "timeUpdate", "debugLog"] {
            controller.add(recorder, name: name)
        }

        controller.addUserScript(
            WKUserScript(
                source: JavaScriptBridge.monitorScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        return WKWebView(frame: .zero, configuration: configuration)
    }

    private static func loadHTML(_ html: String, in webView: WKWebView) throws {
        let delegate = NavigationDelegate()
        let key = UnsafeRawPointer(Unmanaged.passUnretained(webView).toOpaque())
        objc_setAssociatedObject(webView, key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: URL(string: "https://example.com"))

        try waitUntil(timeout: 3, failureMessage: "WKWebView 載入 HTML 逾時") {
            delegate.didFinish || delegate.error != nil
        }

        if let error = delegate.error {
            throw error
        }
    }

    private static func evaluate(_ script: String, in webView: WKWebView) throws -> Any? {
        let box = CallbackBox<Any?>()
        webView.evaluateJavaScript(script) { result, error in
            box.result = result
            box.error = error
            box.isResolved = true
        }

        try waitUntil(timeout: 2, failureMessage: "evaluateJavaScript 逾時") {
            box.isResolved
        }

        if let error = box.error {
            throw error
        }

        return box.result
    }

    fileprivate static func waitUntil(timeout: TimeInterval, failureMessage: String, condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        throw SmokeTestError.timeout(failureMessage)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw SmokeTestError.assertionFailed(message)
        }
    }
}

@MainActor
private final class ScriptMessageRecorder: NSObject, WKScriptMessageHandler {
    private var messagesByName: [String: [Any]] = [:]

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        messagesByName[message.name, default: []].append(message.body)
    }

    func waitForMessages(named name: String, count: Int, timeout: TimeInterval) throws -> [Any] {
        try SmokeTestsRunner.waitUntil(timeout: timeout, failureMessage: "等待訊息逾時: \(name)") {
            (self.messagesByName[name]?.count ?? 0) >= count
        }

        return Array((messagesByName[name] ?? []).prefix(count))
    }

    func waitForMessage(named name: String, timeout: TimeInterval, where predicate: (Any) -> Bool) throws -> Any {
        try SmokeTestsRunner.waitUntil(timeout: timeout, failureMessage: "等待訊息逾時: \(name)") {
            (self.messagesByName[name] ?? []).contains(where: predicate)
        }

        guard let match = (messagesByName[name] ?? []).first(where: predicate) else {
            throw SmokeTestError.assertionFailed("找不到符合條件的訊息: \(name)")
        }

        return match
    }
}

private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    var didFinish = false
    var error: Error?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.error = error
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.error = error
    }
}

private final class CallbackBox<T> {
    var result: T?
    var error: Error?
    var isResolved = false
}

private enum SmokeTestError: LocalizedError {
    case assertionFailed(String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .assertionFailed(let message):
            return message
        case .timeout(let message):
            return message
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
