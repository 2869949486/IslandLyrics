import Foundation

/// 播放位置引擎：CDP 读到的 Howler.seek() 为真相锚点；CDP 不可用/过期时回退
/// `position = now - createdAt - 累计暂停`。所有时间以墙钟 ms 显式传入，便于确定性单测。
///
/// 用法（协调器驱动）：
///   - 每次读到 /api/status → `ingestStatus(...)`
///   - 每次读到 CDP seek → `ingestCDP(...)`
///   - 渲染 tick（30fps）→ `current(nowWall:)`
public final class PositionEngine {
    /// CDP 样本在此时间窗内视为新鲜（ms）。超过则回退插值。
    public var cdpFreshnessMs: Int64

    private var anchorPosMs: Double = 0      // 锚点位置
    private var anchorWall: Int64 = 0        // 锚点墙钟
    private var anchored = false             // 是否已建立有效锚点（避免无锚时按墙钟外推出巨值）
    private var playing = false
    private var lastCDPWall: Int64 = .min / 2
    private var songKey: String?
    private var createdAt: Int64?
    private var accumulatedPauseMs: Double = 0
    private var lastStatusWall: Int64?
    /// CDP 真值与 createdAt 线性预测之差（含 seek 偏移 + 暂停记账误差）。
    /// 回退公式加回它，使 CDP 失联→createdAt 回退时位置连续、不跳变。
    private var driftMs: Double = 0

    public init(cdpFreshnessMs: Int64 = 2000) { self.cdpFreshnessMs = cdpFreshnessMs }

    public var isPlaying: Bool { playing }

    /// 收到 CDP 位置（真相）。秒 → ms 锚点，并校正 createdAt 回退偏移。
    /// updateDrift=false 用于「乐观 seek 重锚」：seek 尚未经 CDP 确认，不更新 drift——否则若 seek 实际失败
    /// （CDP 不可用/无实例），假目标会被烘进 driftMs、污染后续 createdAt 回退锚（C-1）。真实采样才 updateDrift=true。
    public func ingestCDP(seekSeconds: Double, nowWall: Int64, updateDrift: Bool = true) {
        anchorPosMs = max(0, seekSeconds * 1000)
        anchorWall = nowWall
        lastCDPWall = nowWall
        anchored = true
        if updateDrift, let c = createdAt {
            driftMs = anchorPosMs - (Double(nowWall - c) - accumulatedPauseMs)
        }
    }

    /// 收到 /api/status。负责切歌重置、暂停累计、CDP 过期时从 createdAt 回退锚定。
    public func ingestStatus(songKey: String, isPlaying nowPlaying: Bool, createdAt newCreatedAt: Int64?, nowWall: Int64) {
        // createdAt 变化也视作换歌：本地歌 id 常坍缩为同值("0"/"")，仅靠 songKey 无法区分；
        // createdAt(音频起点) 单曲内不刷新，变了即换歌/重播 → 必须复位，否则旧 createdAt 污染回退锚。
        // 用 Optional 整体比较 `newCreatedAt != self.createdAt` 覆盖 nil↔值/值↔值；songKey 相等前提排除首播。
        let songChanged = songKey != self.songKey
            || (self.songKey == songKey && newCreatedAt != self.createdAt)
        if songChanged {
            let isFirst = (self.songKey == nil)
            self.songKey = songKey
            self.createdAt = newCreatedAt
            accumulatedPauseMs = 0
            lastStatusWall = nil
            if !isFirst {
                // 真正切歌 → 丢弃旧歌锚点（含可能已陈旧的 CDP）与 drift
                anchorPosMs = 0
                anchorWall = nowWall
                anchored = false
                lastCDPWall = .min / 2
                driftMs = 0
            }
            // isFirst：保留可能先到的新鲜 CDP 锚点，不清
        } else if self.createdAt == nil, newCreatedAt != nil {
            self.createdAt = newCreatedAt
        }

        // 暂停累计：上一轮到本轮这段墙钟，若当时是暂停态，计入累计暂停（createdAt 不随暂停停）。
        if let last = lastStatusWall, !playing {
            accumulatedPauseMs += Double(nowWall - last)
        }
        let hadPriorStatus = lastStatusWall != nil
        lastStatusWall = nowWall
        let wasPlaying = playing
        playing = nowPlaying

        // 暂停边沿（播放→暂停）：把锚冻结到「暂停那刻的外推值」。否则暂停时 current() 返回上次 CDP 锚值，
        // 比真实暂停位置后退最多一个 CDP 轮询间隔(~0.8s)，暂停瞬间会看到位置回跳。
        if wasPlaying, !nowPlaying, anchored {
            anchorPosMs += Double(nowWall - anchorWall)
            anchorWall = nowWall
        }
        // 恢复边沿（暂停→播放）：把锚跨过这段暂停（保留冻结位置、anchorWall 推进到现在），否则 current()
        // 会把整段暂停墙钟当播放外推、恢复瞬间位置前跳一个暂停时长（CDP 仍新鲜、跳过下方 createdAt 回退时尤甚）。
        // hadPriorStatus 排除「初始 playing=false → 首次开播」这种非真实暂停的转变（首播应继续从 CDP 锚外推）。
        if hadPriorStatus, nowPlaying, !wasPlaying, anchored {
            anchorWall = nowWall
        }

        // CDP 过期且在播放 → 用 createdAt 回退重锚（暂停时不动，冻结在上次锚点避免跳变）。
        let cdpFresh = (nowWall - lastCDPWall) <= cdpFreshnessMs
        if playing, !cdpFresh, let c = createdAt {
            // 加回 driftMs，使回退锚点与最近一次 CDP 真值连续（保留 seek 偏移、吸收暂停记账边界误差）。
            anchorPosMs = max(0, Double(nowWall - c) - accumulatedPauseMs + driftMs)
            anchorWall = nowWall
            anchored = true
        }
    }

    /// 当前插值位置（ms）。播放中且已锚定 → 从锚点按墙钟线性外推；否则冻结/0。
    public func current(nowWall: Int64) -> Int {
        let base = (playing && anchored) ? anchorPosMs + Double(nowWall - anchorWall) : anchorPosMs
        return Int(max(0, base))
    }

    /// 调试：CDP 是否新鲜。
    public func cdpFresh(nowWall: Int64) -> Bool { (nowWall - lastCDPWall) <= cdpFreshnessMs }
}
