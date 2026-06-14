import Foundation

@inline(__always) func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

public enum LyricIndex {
    /// 二分定位当前行：返回 startTime <= positionMs 的最后一行下标。
    /// positionMs 早于第一行 → nil。空数组 → nil。
    public static func currentLineIndex(_ lines: [LyricLine], positionMs: Int) -> Int? {
        guard !lines.isEmpty else { return nil }
        if positionMs < lines[0].startTime { return nil }
        var lo = 0, hi = lines.count - 1, ans = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].startTime <= positionMs { ans = mid; lo = mid + 1 }
            else { hi = mid - 1 }
        }
        return ans
    }

    /// 行内渐进高亮的 0...1 进度。
    /// - 有逐字 words：按「已揭示字符数 / 总字符数」（完成的词全计，当前词按其时长内插值）。
    /// - 无逐字：按行时长线性插值 (positionMs - startTime)/duration。
    public static func revealFraction(_ line: LyricLine, positionMs: Int) -> Double {
        if let words = line.words, !words.isEmpty {
            let totalChars = words.reduce(0) { $0 + $1.text.count }
            guard totalChars > 0 else { return 0 }
            var revealed = 0.0
            for w in words {
                let end = w.startTime + w.duration
                if positionMs >= end {
                    revealed += Double(w.text.count)
                } else if positionMs <= w.startTime {
                    break
                } else {
                    let frac = w.duration > 0 ? Double(positionMs - w.startTime) / Double(w.duration) : 1
                    revealed += Double(w.text.count) * clamp01(frac)
                    break
                }
            }
            return clamp01(revealed / Double(totalChars))
        } else {
            guard line.duration > 0 else { return positionMs >= line.startTime ? 1 : 0 }
            return clamp01(Double(positionMs - line.startTime) / Double(line.duration))
        }
    }
}
