import Foundation

/// 解析 30488(网易云代理) 歌词为统一的 `Lyric`。
/// - `/lyric/new` 的 `yrc` = 逐字（部分热门歌有）
/// - `/lyric` 的 `lrc` = 经典 LRC（普遍可用）+ `tlyric` 翻译
public enum NeteaseLyricParser {

    /// 错误体守卫：网易云 HTTP 恒 200，错误看 JSON 内 code（-460 风控/404/未收录）。放过 code:200 的空词体。
    private static func isErrorBody(_ obj: [String: Any]) -> Bool {
        if let code = obj["code"] as? Int, code != 200 { return true }
        return false
    }

    /// 从 /lyric/new 响应提取 yrc 逐字歌词；无 yrc / 错误码 → nil。
    public static func parseYRCFromLyricNew(_ data: Data) -> Lyric? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], !isErrorBody(obj),
              let yrc = (obj["yrc"] as? [String: Any])?["lyric"] as? String, !yrc.isEmpty else { return nil }
        let tlyric = (obj["tlyric"] as? [String: Any])?["lyric"] as? String
        let lines = parseYRC(yrc, translation: tlyric)
        guard !lines.isEmpty else { return nil }
        return Lyric(hasWordByWord: true, lrcTimeArray: lines.map { Double($0.startTime) / 1000 }, lrcArray: lines)
    }

    /// 从 /lyric 响应提取经典 LRC（+翻译）；错误码 → nil。
    public static func parseClassicFromLyric(_ data: Data) -> Lyric? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], !isErrorBody(obj) else { return nil }
        let lrc = ((obj["lrc"] as? [String: Any])?["lyric"] as? String) ?? ""
        let tlyric = (obj["tlyric"] as? [String: Any])?["lyric"] as? String
        let lines = parseLRC(lrc, translation: tlyric)
        guard !lines.isEmpty else { return nil }
        return Lyric(hasWordByWord: false, lrcTimeArray: lines.map { Double($0.startTime) / 1000 }, lrcArray: lines)
    }

    // MARK: - 经典 LRC

    public static func parseLRC(_ lrc: String, translation: String?) -> [LyricLine] {
        let trans = translation.map(parseLRCMap) ?? [:]
        var raw: [(ms: Int, text: String)] = []
        for line in lrc.split(separator: "\n", omittingEmptySubsequences: false) {
            let (stamps, text) = splitStamps(String(line))
            let t = text.trimmingCharacters(in: .whitespaces)
            for ms in stamps { raw.append((ms, t)) }
        }
        raw.sort { $0.ms < $1.ms }
        var result: [LyricLine] = []
        for (i, item) in raw.enumerated() {
            let next = i + 1 < raw.count ? raw[i + 1].ms : item.ms + 4000
            let dur = max(200, next - item.ms)
            result.append(LyricLine(text: item.text, trText: trans[item.ms], startTime: item.ms,
                                    duration: dur, hasWordByWord: false, words: nil))
        }
        return result
    }

    static func parseLRCMap(_ lrc: String) -> [Int: String] {
        var map: [Int: String] = [:]
        for line in lrc.split(separator: "\n") {
            let (stamps, text) = splitStamps(String(line))
            let t = text.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            for ms in stamps { map[ms] = t }
        }
        return map
    }

    /// 取开头连续的 `[...]` 时间戳 + 其后文本
    static func splitStamps(_ line: String) -> (stamps: [Int], text: String) {
        var stamps: [Int] = []
        var rest = line.drop { $0 == " " || $0 == "\t" }   // 容忍行首空白，否则带前导空格的时间戳行被当歌词
        while rest.first == "[" {
            guard let close = rest.firstIndex(of: "]") else { break }
            let inside = rest[rest.index(after: rest.startIndex)..<close]
            if let ms = lrcStampMs(String(inside)) { stamps.append(ms) }
            rest = rest[rest.index(after: close)...]
        }
        return (stamps, String(rest))
    }

    /// "mm:ss.xx" / "mm:ss" → ms。元数据标签(如 "ti:...") 返回 nil。
    public static func lrcStampMs(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        // 分/秒夹在合理范围：畸形大数（如 16 位分钟）会让 (mm*60+ss)*1000 整数溢出陷阱崩溃。
        guard parts.count == 2, let mm = Int(parts[0]), mm >= 0, mm < 6000 else { return nil }
        let secParts = parts[1].split(whereSeparator: { $0 == "." || $0 == ":" })
        guard let first = secParts.first, let ss = Int(first), ss >= 0, ss < 6000 else { return nil }
        var ms = (mm * 60 + ss) * 1000
        if secParts.count > 1 {
            let frac = String(secParts[1])
            if let f = Int(frac) {
                switch frac.count {
                case 1: ms += f * 100
                case 2: ms += f * 10
                default: ms += Int((Double("0." + frac) ?? 0) * 1000)
                }
            }
        }
        return ms
    }

    // MARK: - YRC 逐字

    public static func parseYRC(_ yrc: String, translation: String?) -> [LyricLine] {
        let trans = translation.map(parseLRCMap) ?? [:]
        var result: [LyricLine] = []
        for rawLine in yrc.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[") else { continue }   // 跳过 {credits} JSON 行
            guard let close = line.firstIndex(of: "]") else { continue }
            let header = line[line.index(after: line.startIndex)..<close]
            let hp = header.split(separator: ",")
            guard hp.count >= 2, let start = Int(hp[0]), let dur = Int(hp[1]) else { continue }
            let body = String(line[line.index(after: close)...])
            let words = parseYRCWords(body)
            guard !words.isEmpty else { continue }
            let text = words.map(\.text).joined()
            result.append(LyricLine(text: text, trText: trans[start], startTime: start,
                                    duration: dur, hasWordByWord: true, words: words))
        }
        return result
    }

    /// 解析一行 yrc body：`(ws,wd,0)字(ws,wd,0)字...`
    static func parseYRCWords(_ body: String) -> [LyricWord] {
        var words: [LyricWord] = []
        var s = Substring(body)
        while let open = s.firstIndex(of: "("), let close = s[open...].firstIndex(of: ")"), close > open {
            let inside = s[s.index(after: open)..<close]
            let p = inside.split(separator: ",")
            let afterClose = s.index(after: close)
            let nextOpen = s[afterClose...].firstIndex(of: "(") ?? s.endIndex
            let text = String(s[afterClose..<nextOpen])
            // 时间头畸形也保留文本（回退到上一字结束时间/0），否则该字会从拼接的 line.text 中静默消失。
            let ws = (p.count >= 2 ? Int(p[0]) : nil) ?? (words.last.map { $0.startTime + $0.duration } ?? 0)
            let wd = (p.count >= 2 ? Int(p[1]) : nil) ?? 0
            if !text.isEmpty {
                words.append(LyricWord(text: text, startTime: ws, duration: wd, space: text.hasSuffix(" ")))
            }
            s = s[nextOpen...]
        }
        return words
    }
}
