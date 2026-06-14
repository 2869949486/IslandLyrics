import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: IslandWindowController?
    private var statusBar: StatusBarController?
    private var settingsWC: SettingsWindowController?
    private let store = PlayerStore()
    private let settings = SettingsStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.start()
        settingsWC = SettingsWindowController(settings: settings, store: store)
        statusBar = StatusBarController(store: store, settings: settings,
                                        onOpenSettings: { [weak self] in self?.settingsWC?.show() })
        rebuildWindow()
        if CommandLine.arguments.contains("--open-settings") { settingsWC?.show() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildWindow() }
        }
    }

    private func rebuildWindow() {
        windowController?.close()
        windowController = nil
        // MVP：仅内建刘海屏（无内建屏时回退主屏）
        guard let screen = NSScreen.builtIn ?? NSScreen.main else { return }
        windowController = IslandWindowController(
            screen: screen, store: store, settings: settings,
            startExpanded: CommandLine.arguments.contains("--show-expanded"),
            menuProvider: { [weak self] in self?.statusBar?.makeMenu() }   // 右键刘海条弹同一套菜单
        )
    }
}
