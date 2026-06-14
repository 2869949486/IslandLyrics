import AppKit
import NotchLyricsCore

/// 菜单栏状态项（中文菜单）。当前为可用子集：当前歌曲(只读)/上一首/播放暂停/下一首/显示隐藏/退出。
/// 其余项（打开主界面、展开收起、重载歌词、歌词偏移、开机启动）随对应功能在 phase4 补全。
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let store: PlayerStore
    private let settings: SettingsStore
    private let onOpenSettings: () -> Void

    init(store: PlayerStore, settings: SettingsStore, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            // 与 app 图标一致的品牌标记：music.note.list（用户选定）
            if let sym = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "灵动岛歌词") {
                sym.isTemplate = true
                button.image = sym
            } else {
                button.title = "♪"
            }
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // 打开前重建，反映当前歌曲与播放态；每项都有一致的 SF Symbol 图标
    func menuNeedsUpdate(_ menu: NSMenu) { populate(menu) }

    /// 供刘海歌词条右键复用：每次新建并填充，与菜单栏菜单完全一致、且反映当前歌曲/播放态。
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu)
        return menu
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        // 关掉自动启用，否则 AppKit 按 target 是否响应 action 决定 enabled，会覆盖我们手设的
        // enabled: canControl，导致无歌时「上一首/下一首」仍可点。
        menu.autoenablesItems = false

        let title: String, symbol: String
        switch store.island {
        case .notInstalled: title = "未安装 AlgerMusic"; symbol = "arrow.down.circle"
        case .hidden:  title = "AlgerMusic 未运行"; symbol = "music.note.house"
        case .guide:   title = "远程控制未开启";   symbol = "exclamationmark.triangle"
        case .idle:    title = "未在播放";          symbol = "pause.circle"
        case .active(let song, _):
            let artist = song.artistText
            title = artist.isEmpty ? (song.name ?? "未知") : "\(song.name ?? "未知") — \(artist)"
            symbol = "music.note"
        }
        addItem(menu, title, symbol: symbol, action: nil, enabled: false)
        menu.addItem(.separator())

        let canControl: Bool = { if case .active = store.island { return true }; return false }()
        // 统一线性(outline)风格；上一首/下一首用窄的「跳曲」图标(单三角+竖线)，不用双三角
        addItem(menu, "上一首", symbol: "backward.end", action: #selector(prev), enabled: canControl)
        addItem(menu, store.isPlaying ? "暂停" : "播放",
                symbol: store.isPlaying ? "pause" : "play", action: #selector(togglePlay), enabled: canControl)
        addItem(menu, "下一首", symbol: "forward.end", action: #selector(next), enabled: canControl)
        menu.addItem(.separator())

        // AlgerMusic 集成：未装→引导安装；已装→可一键带调试参数重启（精准进度没生效时用）。
        if case .notInstalled = store.island {
            addItem(menu, "前往安装 AlgerMusic…", symbol: "arrow.down.circle", action: #selector(installAlger), enabled: true)
        } else {
            addItem(menu, "重启 AlgerMusic（精准进度）", symbol: "arrow.clockwise", action: #selector(relaunchAlger), enabled: true)
        }
        menu.addItem(.separator())

        // 歌词偏移（全局，对所有歌曲生效）
        addItem(menu, String(format: "歌词偏移(全局) %+.1fs", settings.lyricOffsetMs / 1000),
                symbol: "clock", action: nil, enabled: false)
        addItem(menu, "歌词提前 0.5s", symbol: "goforward", action: #selector(offsetEarlier), enabled: true)
        addItem(menu, "歌词延后 0.5s", symbol: "gobackward", action: #selector(offsetLater), enabled: true)
        menu.addItem(.separator())

        addItem(menu, store.userHidden ? "显示歌词岛" : "隐藏歌词岛",
                symbol: store.userHidden ? "eye" : "eye.slash", action: #selector(toggleHidden), enabled: true)
        addItem(menu, "外观设置…", symbol: "gearshape", action: #selector(openSettings), enabled: true)
        menu.addItem(.separator())
        addItem(menu, "退出灵动岛歌词", symbol: "power", action: #selector(quit), enabled: true)
    }

    private func addItem(_ menu: NSMenu, _ title: String, symbol: String, action: Selector?, enabled: Bool) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = (action == nil) ? nil : self
        item.isEnabled = enabled
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            img.isTemplate = true
            item.image = img
        }
        menu.addItem(item)
    }

    @objc private func prev() { store.prev() }
    @objc private func togglePlay() { store.togglePlay() }
    @objc private func next() { store.next() }
    @objc private func installAlger() { store.openInstallPage() }
    @objc private func relaunchAlger() { store.relaunchAlgerForDebug() }
    @objc private func toggleHidden() { store.userHidden.toggle() }
    @objc private func offsetEarlier() { settings.nudgeOffset(500) }
    @objc private func offsetLater() { settings.nudgeOffset(-500) }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
