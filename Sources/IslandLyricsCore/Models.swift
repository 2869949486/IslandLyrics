import Foundation

/// 网易云 id 通常是 Int，但本地歌(local://)可能是 String / 0。
/// 统一收成 String，仅用于切歌检测与缓存 key。
public struct FlexibleID: Codable, Equatable, Hashable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) { self.value = value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = String(i) }
        else if let d = try? c.decode(Double.self) {
            // Int(Double) 对 NaN/Inf/超范围是 trap 转换，try? 抓不住 → 先判有限且在 Int 范围内。
            // 用 < 而非 <=：Double(Int.max) 因精度上舍入到 2^63，相等也会越界。
            if d.isFinite, d > Double(Int.min), d < Double(Int.max) { value = String(Int(d)) }
            else { value = String(d) }
        }
        else if let s = try? c.decode(String.self) { value = s }
        else { value = "" }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }

    public var description: String { value }
    public var isEmpty: Bool { value.isEmpty || value == "0" }
}

public struct Artist: Codable, Equatable {
    public let name: String
    public init(name: String) { self.name = name }
}

public struct Album: Codable, Equatable {
    public let name: String?
    public let picUrl: String?
    public init(name: String?, picUrl: String?) { self.name = name; self.picUrl = picUrl }
}

public struct LyricWord: Codable, Equatable {
    public let text: String
    public let startTime: Int      // ms
    public let duration: Int       // ms
    public let space: Bool?
    public init(text: String, startTime: Int, duration: Int, space: Bool?) {
        self.text = text; self.startTime = startTime; self.duration = duration; self.space = space
    }
}

public struct LyricLine: Codable, Equatable {
    public let text: String
    public let trText: String?
    public let startTime: Int      // ms
    public let duration: Int       // ms
    public let hasWordByWord: Bool?
    public let words: [LyricWord]?
    public init(text: String, trText: String?, startTime: Int, duration: Int,
                hasWordByWord: Bool?, words: [LyricWord]?) {
        self.text = text; self.trText = trText; self.startTime = startTime
        self.duration = duration; self.hasWordByWord = hasWordByWord; self.words = words
    }
}

public struct Lyric: Codable, Equatable {
    public let hasWordByWord: Bool?
    public let lrcTimeArray: [Double]?   // 每行起始秒，与 lrcArray 平行
    public let lrcArray: [LyricLine]?
    public init(hasWordByWord: Bool?, lrcTimeArray: [Double]?, lrcArray: [LyricLine]?) {
        self.hasWordByWord = hasWordByWord; self.lrcTimeArray = lrcTimeArray; self.lrcArray = lrcArray
    }
}

public struct Song: Codable, Equatable {
    public let id: FlexibleID
    public let name: String?
    public let ar: [Artist]?
    public let al: Album?
    public let picUrl: String?
    public let dt: Int?                 // 时长 ms
    public let createdAt: Int64?        // 音频 URL 创建时间 epoch ms ≈ 播放起点
    public let expiredAt: Int64?
    public let primaryColor: String?    // "rgb(r,g,b)"
    public let backgroundColor: String? // "linear-gradient(...)"
    public let lyric: Lyric?

    public init(id: FlexibleID, name: String?, ar: [Artist]?, al: Album?, picUrl: String?,
                dt: Int?, createdAt: Int64?, expiredAt: Int64?,
                primaryColor: String?, backgroundColor: String?, lyric: Lyric?) {
        self.id = id; self.name = name; self.ar = ar; self.al = al; self.picUrl = picUrl
        self.dt = dt; self.createdAt = createdAt; self.expiredAt = expiredAt
        self.primaryColor = primaryColor; self.backgroundColor = backgroundColor; self.lyric = lyric
    }

    /// 返回替换了歌词的副本（用于注入 30488 兜底歌词）
    public func replacingLyric(_ l: Lyric?) -> Song {
        Song(id: id, name: name, ar: ar, al: al, picUrl: picUrl, dt: dt, createdAt: createdAt,
             expiredAt: expiredAt, primaryColor: primaryColor, backgroundColor: backgroundColor, lyric: l)
    }

    /// 歌手名拼接（"周杰伦 / 方文山"）
    public var artistText: String {
        (ar ?? []).map(\.name).filter { !$0.isEmpty }.joined(separator: " / ")
    }
    /// 优先专辑封面，回退 picUrl。网易云图片常是 http:// → 升级为 https://（ATS + 加载更稳）。
    public var coverURL: String? {
        guard let raw = al?.picUrl ?? picUrl, !raw.isEmpty else { return nil }
        return raw.hasPrefix("http://") ? "https://" + raw.dropFirst("http://".count) : raw
    }
    public var durationMs: Int { dt ?? 0 }
}

public struct StatusResponse: Codable, Equatable {
    public let isPlaying: Bool
    public let currentSong: Song?
    public init(isPlaying: Bool, currentSong: Song?) {
        self.isPlaying = isPlaying; self.currentSong = currentSong
    }
}

public extension StatusResponse {
    /// 从 /api/status 原始字节解码（忽略未声明字段）
    static func decode(_ data: Data) -> StatusResponse? {
        try? JSONDecoder().decode(StatusResponse.self, from: data)
    }
}
