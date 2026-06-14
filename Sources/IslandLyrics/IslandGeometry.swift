import AppKit

/// 收起态歌词岛的几何参数，全部由屏幕实测推导，外接屏有兜底
struct IslandGeometry {
    let islandWidth: CGFloat
    let islandHeight: CGFloat
    /// 中央摄像模组禁区宽度（含两侧安全边距），无刘海屏为 0
    let cameraZoneWidth: CGFloat
    let topRadius: CGFloat = 8
    let bottomRadius: CGFloat = 13

    init(screen: NSScreen, preferredWidth: CGFloat = 590, cameraMargin: CGFloat = 10) {
        let notch = screen.notchSize
        if notch.height > 0 {
            islandHeight = min(max(notch.height, 30), 34)
            cameraZoneWidth = notch.width + cameraMargin * 2
        } else {
            let menuBar = screen.menuBarHeight
            islandHeight = menuBar > 0 ? min(max(menuBar, 24), 34) : 32
            cameraZoneWidth = 0
        }
        islandWidth = min(max(preferredWidth, 560), 620)
    }
}
