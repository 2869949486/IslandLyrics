import AppKit
import SwiftUI

/// 承载 SettingsView 的普通窗口。accessory app 打开可交互窗口时临时切 .regular，关闭后切回 .accessory。
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let store: PlayerStore

    init(settings: SettingsStore, store: PlayerStore) { self.settings = settings; self.store = store }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            w.title = "灵动岛歌词 设置"
            w.contentView = NSHostingView(rootView: SettingsView(settings: settings, store: store))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)   // 让窗口可成为 key + 出现在 Dock/Cmd-Tab
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // 关闭设置后回到纯菜单栏后台 app
        NSApp.setActivationPolicy(.accessory)
    }
}
