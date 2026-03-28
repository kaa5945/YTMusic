import Foundation

/// 媒體鍵由 WKWebView 內建的 MediaSession API 自動處理
class MediaKeyService {
    static let shared = MediaKeyService()
    private init() {}
}
