import Foundation

/// 灵动岛待机状态机（决策：未运行隐藏 / 远控未开引导 / 在运行就绪或暂停或放歌）。
public enum IslandState: Equatable {
    case notInstalled                 // 本机未安装 AlgerMusic → 引导去下载
    case hidden                       // AlgerMusic 未运行 → 整个岛隐藏
    case guide                        // 在运行但 31888 远控不可达 → 图文引导态
    case idle                         // 在运行、远控通、但无当前歌 → 最小就绪条
    case active(Song, playing: Bool)  // 有当前歌（playing=正常岛，false=暂停冻结态）

    public var isVisible: Bool { self != .hidden }
}

/// 歌词可用性（驱动视图选高亮路径/占位文案）。
public enum LyricMode: Equatable {
    case wordByWord    // 有逐字 words
    case lineByLine    // 有逐行 LRC、无逐字 → 行内线性插值
    case instrumental  // 纯音乐 → 「纯音乐，无歌词」
    case none          // 暂无歌词（本地音乐等）→ 「暂无歌词」
}

public enum IslandStateMachine {
    /// 三态推导。remoteReachable=能否连上 31888；status=最近一次 /api/status。
    public static func derive(processRunning: Bool, remoteReachable: Bool, status: StatusResponse?) -> IslandState {
        guard processRunning else { return .hidden }
        guard remoteReachable else { return .guide }
        guard let status, let song = status.currentSong else { return .idle }
        return .active(song, playing: status.isPlaying)
    }

    /// 歌词模式判定（启发式，phase3 真机校准）：
    /// - 文本含「纯音乐」→ instrumental
    /// - 有非空 words → wordByWord
    /// - 有行无逐字 → lineByLine
    /// - 无行 → none
    public static func lyricMode(_ song: Song) -> LyricMode {
        guard let lines = song.lyric?.lrcArray, !lines.isEmpty else { return .none }
        if lines.contains(where: { $0.text.contains("纯音乐") }) { return .instrumental }
        if lines.contains(where: { ($0.words?.isEmpty == false) }) { return .wordByWord }
        return .lineByLine
    }
}
