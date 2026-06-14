import Foundation

/// 0...1 的 RGB 分量。视图层据此构造 SwiftUI.Color（Core 不依赖 SwiftUI）。
public struct RGBComponents: Equatable {
    public let r: Double
    public let g: Double
    public let b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    /// 解析 "rgb(102,87,81)" / "rgba(102,87,81,0.5)" / "rgb(102 87 81)"。失败返回 nil。
    public static func parse(_ string: String?) -> RGBComponents? {
        guard let s = string else { return nil }
        // open < close 必须成立：否则 s[index(after:open)..<close] 在 ")(" 这类畸形串上 lowerBound>upperBound 崩溃。
        guard let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")"), open < close else { return nil }
        let inner = s[s.index(after: open)..<close]
        let parts = inner.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return nil }
        return RGBComponents(r: parts[0] / 255.0, g: parts[1] / 255.0, b: parts[2] / 255.0)
    }

    /// 从 "linear-gradient(to bottom, rgb(a) 0%, rgb(b) 50%, ...)" 取第一个 rgb()。
    public static func firstFromGradient(_ string: String?) -> RGBComponents? {
        guard let s = string, let range = s.range(of: "rgb") else { return parse(string) }
        return parse(String(s[range.lowerBound...]))
    }

    /// 取 linear-gradient 里全部 rgb()/rgba() 色段（按顺序），用于展开态背景渐变。
    public static func allFromGradient(_ string: String?) -> [RGBComponents] {
        guard let s = string else { return [] }
        var result: [RGBComponents] = []
        var idx = s.startIndex
        while let r = s.range(of: "rgb", range: idx..<s.endIndex) {
            // 取这个 rgb( ... ) 片段
            if let close = s.range(of: ")", range: r.lowerBound..<s.endIndex) {
                if let c = parse(String(s[r.lowerBound...close.lowerBound])) { result.append(c) }
                idx = close.upperBound
            } else { break }
        }
        return result
    }
}
