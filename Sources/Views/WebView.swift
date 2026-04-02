import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = WebViewManager.shared.webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// 管理單一 WKWebView 實例，確保跨視窗生命週期保持 session
class WebViewManager: NSObject, ObservableObject {
    static let shared = WebViewManager()

    let webView: WKWebView

    private override init() {
        let config = WKWebViewConfiguration()

        // 使用預設 data store 持久化 cookie（Google 登入 session）
        config.websiteDataStore = .default()

        // 允許自動播放媒體
        config.mediaTypesRequiringUserActionForPlayback = []

        // 啟用 JavaScript
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences

        // 註冊 JS → Swift message handler
        let userContentController = WKUserContentController()
        config.userContentController = userContentController

        webView = WKWebView(frame: .zero, configuration: config)

        super.init()

        // 使用 Safari UA（WKWebView 本身就是 WebKit，用 Chrome UA 會被 Google 偵測不一致）
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"

        // 設定 navigation delegate 處理彈出式視窗
        webView.navigationDelegate = self
        webView.uiDelegate = self

        // 允許返回/前進手勢
        webView.allowsBackForwardNavigationGestures = true

        // 註冊 JS Bridge message handlers
        let bridge = JavaScriptBridge.shared
        userContentController.add(bridge, name: "nowPlaying")
        userContentController.add(bridge, name: "playbackState")
        userContentController.add(bridge, name: "volumeChanged")
        userContentController.add(bridge, name: "repeatState")
        userContentController.add(bridge, name: "shuffleState")
        userContentController.add(bridge, name: "queueUpdate")
        userContentController.add(bridge, name: "timeUpdate")
        userContentController.add(bridge, name: "debugLog")

        // 在 Google 登入頁面隱藏 WebView 特徵（messageHandlers）
        let hideWebViewScript = WKUserScript(
            source: """
            (function() {
                // 備份 messageHandlers 引用，Google 登入偵測用
                const realHandlers = window.webkit?.messageHandlers;
                Object.defineProperty(window, 'webkit', {
                    get: function() {
                        // 對 Google 登入頁面隱藏 messageHandlers
                        if (document.location.hostname.includes('accounts.google.com')) {
                            return undefined;
                        }
                        return { messageHandlers: realHandlers };
                    },
                    configurable: true
                });
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(hideWebViewScript)

        // 隱藏捲軸（保留捲動功能）
        let hideScrollbarScript = WKUserScript(
            source: """
            (function() {
                var s = document.createElement('style');
                s.textContent = `
                    ::-webkit-scrollbar { display: none !important; width: 0 !important; height: 0 !important; }
                    * { scrollbar-width: none !important; -ms-overflow-style: none !important; }
                `;
                document.head.appendChild(s);
                // YouTube Music 動態載入內容，用 MutationObserver 持續注入
                new MutationObserver(function() {
                    if (!document.head.contains(s)) { document.head.appendChild(s); }
                }).observe(document.documentElement, { childList: true, subtree: true });
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(hideScrollbarScript)

        // 注入歌曲監聯 JS
        let monitorScript = WKUserScript(
            source: JavaScriptBridge.monitorScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(monitorScript)

        loadYouTubeMusic()
    }

    func loadYouTubeMusic() {
        guard let url = URL(string: "https://music.youtube.com") else { return }
        let request = URLRequest(url: url)
        webView.load(request)
    }
}

// MARK: - WKNavigationDelegate
extension WebViewManager: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // 允許所有導航（包含 Google OAuth 流程）
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate
extension WebViewManager: WKUIDelegate {
    /// 處理 JavaScript window.open()（Google 登入彈出視窗）
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // 在同一個 WebView 中打開彈出連結
        if navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
