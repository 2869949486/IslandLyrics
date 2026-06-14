import AppKit

/// accessory app 入口（@main + @MainActor，避免 main.swift 顶层代码构造 @MainActor 类型的隔离冲突）。
@main
enum NotchLyricsApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
