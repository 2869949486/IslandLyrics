import SwiftUI
import AppKit

/// 用户可自定义的外观设置，UserDefaults 持久化，全应用共享一个实例。
/// 收起态视图与设置窗口都观察它 → 改动即时生效。
@MainActor
final class SettingsStore: ObservableObject {
    private let d = UserDefaults.standard

    @Published var songNameColor: Color { didSet { d.set(Self.encode(songNameColor), forKey: K.songName) } }
    @Published var artistColor: Color { didSet { d.set(Self.encode(artistColor), forKey: K.artist) } }
    @Published var lyricColor: Color { didSet { d.set(Self.encode(lyricColor), forKey: K.lyric) } }
    @Published var lyricHighlightColor: Color { didSet { d.set(Self.encode(lyricHighlightColor), forKey: K.lyricHi) } }
    // 字号按 收起态/展开态 分别可调
    @Published var collapsedLyricFontSize: Double { didSet { d.set(collapsedLyricFontSize, forKey: K.cLyricFont) } }
    @Published var expandedLyricFontSize: Double { didSet { d.set(expandedLyricFontSize, forKey: K.eLyricFont) } }
    @Published var collapsedTitleFontSize: Double { didSet { d.set(collapsedTitleFontSize, forKey: K.cTitleFont) } }
    @Published var expandedTitleFontSize: Double { didSet { d.set(expandedTitleFontSize, forKey: K.eTitleFont) } }
    /// 歌词时间偏移(ms)：正=歌词提前显示，负=延后。
    @Published var lyricOffsetMs: Double { didSet { d.set(lyricOffsetMs, forKey: K.offset) } }

    private enum K {
        static let songName = "songNameColor", artist = "artistColor"
        static let lyric = "lyricColor", lyricHi = "lyricHighlightColor"
        static let cLyricFont = "collapsedLyricFontSize", eLyricFont = "expandedLyricFontSize"
        static let cTitleFont = "collapsedTitleFontSize", eTitleFont = "expandedTitleFontSize"
        static let offset = "lyricOffsetMs"
    }

    // 默认：歌名/作者亮白，歌词底色灰、高亮白；字号在 32pt 岛高内偏大但安全
    static let defSongName = Color.white
    static let defArtist = Color.white
    static let defLyric = Color(white: 0.55)
    static let defLyricHi = Color.white
    static let defCLyricFont = 13.0, defELyricFont = 18.0
    static let defCTitleFont = 13.0, defETitleFont = 20.0
    static let defOffset = 0.0
    static let offsetRange: ClosedRange<Double> = -3000...3000   // ±3s

    // 收起态受 ~32pt 岛高限制；展开态空间大、可更大
    static let collapsedLyricRange: ClosedRange<Double> = 10...18
    static let collapsedTitleRange: ClosedRange<Double> = 10...17
    static let expandedLyricRange: ClosedRange<Double> = 12...26
    static let expandedTitleRange: ClosedRange<Double> = 12...28

    init() {
        songNameColor = Self.decode(d.string(forKey: K.songName), Self.defSongName)
        artistColor = Self.decode(d.string(forKey: K.artist), Self.defArtist)
        lyricColor = Self.decode(d.string(forKey: K.lyric), Self.defLyric)
        lyricHighlightColor = Self.decode(d.string(forKey: K.lyricHi), Self.defLyricHi)
        // 夹紧到各滑杆范围：避免跨版本调整 range 后旧持久值越界喂给 Slider。
        collapsedLyricFontSize = Self.clamp(d.object(forKey: K.cLyricFont) as? Double ?? Self.defCLyricFont, Self.collapsedLyricRange)
        expandedLyricFontSize = Self.clamp(d.object(forKey: K.eLyricFont) as? Double ?? Self.defELyricFont, Self.expandedLyricRange)
        collapsedTitleFontSize = Self.clamp(d.object(forKey: K.cTitleFont) as? Double ?? Self.defCTitleFont, Self.collapsedTitleRange)
        expandedTitleFontSize = Self.clamp(d.object(forKey: K.eTitleFont) as? Double ?? Self.defETitleFont, Self.expandedTitleRange)
        lyricOffsetMs = Self.clamp(d.object(forKey: K.offset) as? Double ?? Self.defOffset, Self.offsetRange)
    }

    func resetDefaults() {
        songNameColor = Self.defSongName
        artistColor = Self.defArtist
        lyricColor = Self.defLyric
        lyricHighlightColor = Self.defLyricHi
        collapsedLyricFontSize = Self.defCLyricFont
        expandedLyricFontSize = Self.defELyricFont
        collapsedTitleFontSize = Self.defCTitleFont
        expandedTitleFontSize = Self.defETitleFont
        lyricOffsetMs = Self.defOffset
    }

    /// 菜单快捷调偏移（±ms），夹在范围内
    func nudgeOffset(_ deltaMs: Double) {
        lyricOffsetMs = min(Self.offsetRange.upperBound, max(Self.offsetRange.lowerBound, lyricOffsetMs + deltaMs))
    }

    static func clamp(_ v: Double, _ r: ClosedRange<Double>) -> Double {
        min(r.upperBound, max(r.lowerBound, v))
    }

    // Color ↔ "r,g,b,a" 字符串
    static func encode(_ c: Color) -> String {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .white
        return "\(ns.redComponent),\(ns.greenComponent),\(ns.blueComponent),\(ns.alphaComponent)"
    }
    static func decode(_ s: String?, _ def: Color) -> Color {
        guard let s else { return def }
        let p = s.split(separator: ",").compactMap { Double($0) }
        // 含 NaN/Inf 的篡改值会构造出非法分量 Color；非有限即回退默认，分量夹紧 0...1。
        guard p.count == 4, p.allSatisfy(\.isFinite) else { return def }
        return Color(.sRGB, red: clamp(p[0], 0...1), green: clamp(p[1], 0...1), blue: clamp(p[2], 0...1), opacity: clamp(p[3], 0...1))
    }
}
