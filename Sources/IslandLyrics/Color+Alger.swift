import SwiftUI
import AppKit
import IslandLyricsCore

extension Color {
    init(_ c: RGBComponents) { self.init(red: c.r, green: c.g, blue: c.b) }

    /// 从 AlgerMusic 的 "rgb(...)" 主色串构造；失败回退给定默认色。
    static func alger(_ string: String?, fallback: Color) -> Color {
        RGBComponents.parse(string).map(Color.init) ?? fallback
    }

    /// sRGB 分量 0...1
    func rgba() -> (r: Double, g: Double, b: Double, a: Double) {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent), Double(ns.alphaComponent))
    }

    /// "#RRGGBB"
    func hexString() -> String {
        let c = rgba()
        return String(format: "#%02X%02X%02X",
                      Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
    }

    /// 解析 "#RRGGBB" / "RRGGBB"（保持当前不透明度由调用方处理，这里默认 1）
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}

/// 从 app bundle 的 Resources 读 PNG（手工组装的 .app，资源在 Contents/Resources）。
func bundleImage(_ name: String, ext: String = "png") -> NSImage? {
    guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
    return NSImage(contentsOf: url)
}
