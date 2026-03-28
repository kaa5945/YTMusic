import Cocoa
import UserNotifications

/// 歌曲切換通知服務
/// Now Playing 與媒體鍵由 WebView 內建的 MediaSession API 處理，不需要重複註冊
class NowPlayingService {
    static let shared = NowPlayingService()

    private var lastNotifiedTitle = ""

    private init() {
        requestNotificationPermission()
    }

    // MARK: - 系統通知

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, error in
            if let error = error {
                print("[Notification] 權限請求失敗: \(error.localizedDescription)")
            }
        }
    }

    func showNotification(track: TrackInfo) {
        // 避免重複通知同一首歌
        guard track.title != lastNotifiedTitle else { return }
        lastNotifiedTitle = track.title

        let content = UNMutableNotificationContent()
        content.title = track.title
        content.body = track.artist
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "trackChange-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Notification] 發送失敗: \(error.localizedDescription)")
            }
        }
    }
}
