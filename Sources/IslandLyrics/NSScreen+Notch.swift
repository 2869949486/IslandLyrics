import AppKit

extension NSScreen {
    var isBuiltIn: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(number.uint32Value) == 1
    }

    static var builtIn: NSScreen? {
        screens.first { $0.isBuiltIn }
    }

    /// 物理刘海尺寸；无刘海屏返回 .zero
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea?.width,
              let right = auxiliaryTopRightArea?.width,
              left > 0, right > 0 else { return .zero }
        return CGSize(width: ceil(frame.width - left - right), height: safeAreaInsets.top)
    }

    var menuBarHeight: CGFloat {
        frame.maxY - visibleFrame.maxY
    }
}
