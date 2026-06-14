import AppKit
import SwiftUI

/// 覆盖窗：贴顶、置于菜单栏之上、全屏可见、透明无阴影。窗口高度按展开态预留，
/// 收起态时下方透明，命中区域交给 IslandContainerView 控制（点击穿透）。
final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    // 允许点击控件/拖动进度时成为 key（nonactivating，不会把 app 拉到前台）
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 菜单弹出闸：menu.popUp 是同步阻塞，期间 hover 轮询若继续运行会把展开的岛收回、菜单悬空。
/// 弹出前后置 isOpen，轮询读它在菜单期间冻结状态机。引用类型，IslandView 与 FirstMouseHostingView 共享同一实例。
final class MenuGate { var isOpen = false }

/// 只在岛的当前可见区域（顶部 islandHeight 高）命中；其余透明区/隐藏态返回 nil → 点击穿透到下层 app。
final class IslandContainerView: NSView {
    var islandHeight: CGFloat = 0
    var clickThrough = false    // 隐藏态：所有点击穿透（否则顶部薄条命中区持续吞点击）
    var wantExpanded = false    // 最新意图：折叠延后缩命中区时据此判断是否已被重新展开
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !clickThrough, point.y >= bounds.maxY - islandHeight - 1 else { return nil }
        return super.hitTest(point)
    }
}

/// 让 SwiftUI 控件在 nonactivating 面板里首点即响应；并把右键/Control+点击转成弹出菜单
/// （菜单栏图标若被刘海吞掉，刘海条本身仍是永不丢失的入口）。
final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    var menuProvider: (() -> NSMenu?)?
    var menuGate: MenuGate?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func popUpContextMenu(_ event: NSEvent) -> Bool {
        guard let menu = menuProvider?() else { return false }
        menuGate?.isOpen = true                    // popUp 同步阻塞期间冻结 hover 轮询，免菜单悬空
        defer { menuGate?.isOpen = false }
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
        return true
    }

    override func rightMouseDown(with event: NSEvent) {
        if popUpContextMenu(event) { return }
        super.rightMouseDown(with: event)
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), popUpContextMenu(event) { return }
        super.mouseDown(with: event)   // 普通左键交给 SwiftUI（悬停展开/点击固定/拖动 seek）
    }
}

final class IslandWindowController: NSWindowController {
    init(screen: NSScreen, store: PlayerStore, settings: SettingsStore, startExpanded: Bool = false,
         menuProvider: (() -> NSMenu?)? = nil) {
        let geometry = IslandGeometry(screen: screen)
        let expandedHeight: CGFloat = 330
        let w = geometry.islandWidth
        let rect = NSRect(
            x: screen.frame.origin.x + (screen.frame.width - w) / 2,
            y: screen.frame.maxY - expandedHeight,   // 顶贴屏幕顶
            width: w, height: expandedHeight
        )

        let container = IslandContainerView(frame: NSRect(origin: .zero, size: rect.size))
        container.islandHeight = startExpanded ? expandedHeight : geometry.islandHeight
        let gate = MenuGate()

        let root = IslandView(
            geometry: geometry, store: store, settings: settings,
            onExpandedChange: { [weak container] expanded in
                guard let container else { return }
                container.wantExpanded = expanded
                if expanded {
                    container.islandHeight = expandedHeight   // 展开：立即扩大命中区
                } else {
                    // 折叠：延后 ~0.34s（与形变弹簧动画同长）再缩命中区，避免动画期间岛仍可见却点击穿透；
                    // 若期间又被展开(wantExpanded=true)则跳过本次缩小。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { [weak container] in
                        guard let container, !container.wantExpanded else { return }
                        container.islandHeight = geometry.islandHeight
                    }
                }
            },
            onClickThroughChange: { [weak container] hidden in container?.clickThrough = hidden },
            startExpanded: startExpanded,
            islandRect: rect,   // 屏幕坐标系下的覆盖窗 frame，悬停轮询据此判定指针进/出
            menuGate: gate
        )
        let host = FirstMouseHostingView(rootView: root.ignoresSafeArea())
        host.menuProvider = menuProvider
        host.menuGate = gate
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        let panel = IslandPanel(contentRect: rect)
        panel.contentView = container

        super.init(window: panel)
        panel.setFrame(rect, display: true)
        panel.orderFrontRegardless()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }
}
