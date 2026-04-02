import Cocoa
import SwiftUI
import YTMusicCore

// SPM 進入點：用 NSApplication 啟動，不依賴 Xcode 的 @main + WindowGroup
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
