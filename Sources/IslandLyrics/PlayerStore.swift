import Foundation
import AppKit
import IslandLyricsCore

/// 协调器：轮询 /api/status + CDP seek 喂给 PositionEngine，推导待机状态，发布给 SwiftUI。
/// 视图每帧调 `currentPositionMs()` 取插值位置驱动逐字高亮（位置精度由引擎负责）。
@MainActor
final class PlayerStore: ObservableObject {
    @Published private(set) var island: IslandState = .hidden
    @Published private(set) var cdpAvailable = false
    @Published var userHidden = false   // 菜单栏「隐藏歌词岛」手动开关
    @Published private(set) var fallbackLyrics: [String: Lyric] = [:]   // id → 30488 兜底歌词
    @Published private(set) var algerInstalled = true   // 本机是否装了 AlgerMusic（false → 引导安装）
    @Published private(set) var likedThisSession: Set<String> = []   // 本会话点过「喜欢」的歌 id（乐观显示红心；API 不暴露真实红心态）
    private var fetchingLyric: Set<String> = []
    private var debugLaunchAttempted = false   // 本会话是否已尝试过带调试参数(重)启（一次性，避免循环重启）

    private let engine = PositionEngine()
    private let cdp = CDPPositionReader()
    private var client: AlgerMusicClient
    private var ports: AlgerPorts
    private var started = false
    private var statusTask: Task<Void, Never>?
    private var cdpTask: Task<Void, Never>?
    /// 刚提交的 seek 目标（秒）+ 墙钟。CDP 回采靠拢目标或窗口超时前，忽略回采避免读到 seek 生效前的旧值。
    private var pendingSeek: (target: Double, wall: Int64)?
    /// 刚乐观翻转的播放态 + 确认截止墙钟 + 当时歌曲身份。窗口内 status 未反映 toggle 时沿用乐观值，避免按钮闪回；
    /// 换歌则立即放弃（否则暂停后立刻 next/prev，新歌被旧暂停目标强制渲染成暂停）。
    private var pendingPlay: (value: Bool, until: Int64, songKey: String?)?
    private var wakeObserver: NSObjectProtocol?

    init() {
        ports = PortDiscovery.discover()
        client = AlgerMusicClient(remotePort: ports.remoteControlPort, musicApiPort: ports.musicApiPort)
    }

    func start() {
        guard !started else { return }
        started = true
        statusTask = Task { await statusLoop() }
        cdpTask = Task { await cdpLoop() }
        // 休眠唤醒后墙钟跳变会让插值外推一段；立即补一次 CDP 重锚把位置纠到真实处（不等下一轮 ~0.8s）。
        // 存 token 以便 stop() 移除，避免重复 start 累积观察者。
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resyncAfterWake() }
        }
    }

    /// 停止协调器（取消两个轮询 Task + 移除唤醒观察者）。单例随进程终生时无需调用；为可重建/测试预留。
    func stop() {
        statusTask?.cancel(); statusTask = nil
        cdpTask?.cancel(); cdpTask = nil
        if let t = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(t); wakeObserver = nil }
        started = false
    }

    private func resyncAfterWake() {
        guard isPlaying else { return }
        let songAtWake = activeSong?.id.value
        Task {
            if let sample = await cdp.readPosition() {
                // await 期间可能换歌：身份变了就别把旧曲位置锚到新曲引擎。
                guard activeSong?.id.value == songAtWake else { return }
                engine.ingestCDP(seekSeconds: Double(sample.seekMs) / 1000.0, nowWall: nowMs())
            }
        }
    }

    // MARK: - AlgerMusic 代启（待启动）
    /// 本会话首次：若 9222 调试口没起，就带参(重)启 AlgerMusic 启用精准进度。一次性，避免反复重启。
    private func ensureDebugLaunchIfNeeded() async {
        guard !debugLaunchAttempted else { return }
        let debugUp = await cdp.available()   // 9222 /json/list 是否在听（与运行/播放态无关）
        debugLaunchAttempted = true
        guard !debugUp else { return }        // 已带调试参数启动 → 无需动
        await AlgerMusicApp.relaunchWithDebugFlags()   // 未运行→直接带参启；运行但无调试口→退出再带参启
    }

    /// 打开 AlgerMusic 下载页（未安装时引导用户）。
    func openInstallPage() { NSWorkspace.shared.open(AlgerMusicApp.downloadURL) }

    /// 手动：带调试参数重启 AlgerMusic（菜单项用，便于精准进度没生效时一键修）。
    func relaunchAlgerForDebug() {
        debugLaunchAttempted = true
        Task { await AlgerMusicApp.relaunchWithDebugFlags() }
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// 当前插值播放位置（ms），供视图每帧取用。
    func currentPositionMs() -> Int { engine.current(nowWall: nowMs()) }

    var activeSong: Song? { if case .active(let s, _) = island { return s }; return nil }
    var isPlaying: Bool { if case .active(_, let p) = island { return p }; return false }

    // 连接状态（供设置面板显示）
    var processRunning: Bool { switch island { case .hidden, .notInstalled: return false; default: return true } }
    var remoteReachable: Bool { switch island { case .idle, .active: return true; default: return false } }
    var remotePort: Int { ports.remoteControlPort }
    var musicApiPort: Int { ports.musicApiPort }

    // MARK: - 轮询循环

    private func statusLoop() async {
        while !Task.isCancelled {
            // 未安装 AlgerMusic → 引导去下载（开源用户首次可能没装）。
            if !AlgerMusicApp.isInstalled {
                if algerInstalled { algerInstalled = false }
                if island != .notInstalled { island = .notInstalled }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }
            if !algerInstalled { algerInstalled = true }
            // 已装但 CDP 调试口(9222)没起 → 本会话首次自动带参(重)启，启用精准进度（一次性，不循环）。
            await ensureDebugLaunchIfNeeded()
            let running = AlgerMusicApp.isRunning
            if !running {
                if island != .hidden { island = .hidden }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                continue
            }
            let status = await client.status()
            let reachable = (status != nil)
            // 乐观播放态：确认窗口内 status 还没反映 toggle 时沿用乐观值（按钮/歌词即时、不闪回）。
            var effStatus = status
            if let s = status, let pend = pendingPlay {
                // 换歌 / 超时 / status 已反映 → 放弃乐观值，按真实 status。
                if pend.songKey != s.currentSong?.id.value || nowMs() > pend.until || s.isPlaying == pend.value {
                    pendingPlay = nil
                } else {
                    effStatus = StatusResponse(isPlaying: pend.value, currentSong: s.currentSong)
                }
            }
            if let st = effStatus, let song = st.currentSong {
                engine.ingestStatus(songKey: song.id.value, isPlaying: st.isPlaying,
                                    createdAt: song.createdAt, nowWall: nowMs())
            }
            var newIsland = IslandStateMachine.derive(processRunning: running, remoteReachable: reachable, status: effStatus)
            // 内嵌 lyric 为空的歌 → 注入已缓存的 30488 兜底词，或触发拉取（C-12）。
            if case .active(let s, let p) = newIsland {
                newIsland = .active(withFallbackLyric(s), playing: p)
            }
            if newIsland != island { island = newIsland }
            let playing = effStatus?.isPlaying ?? false
            try? await Task.sleep(nanoseconds: playing ? 700_000_000 : 1_500_000_000)
        }
    }

    private func cdpLoop() async {
        while !Task.isCancelled {
            guard AlgerMusicApp.isRunning, isPlaying else {
                try? await Task.sleep(nanoseconds: 1_000_000_000); continue
            }
            let readStart = nowMs()
            if let sample = await cdp.readPosition() {
                if !cdpAvailable { cdpAvailable = true }
                let sampleSec = Double(sample.seekMs) / 1000.0
                let now = nowMs()
                if let ps = pendingSeek {
                    if readStart < ps.wall {
                        // 这次读在 seek 之前就发起了 → 携 seek 前旧位置，丢弃不 ingest、不清 pendingSeek（C-5）。
                    } else if abs(sampleSec - ps.target) <= 1.5 || (now - ps.wall) > 2000 {
                        // 真值靠拢 seek 目标(±1.5s)或窗口超时(>2s)后才恢复回采，期间保持本地重锚不被旧值覆盖。
                        pendingSeek = nil
                        engine.ingestCDP(seekSeconds: sampleSec, nowWall: now)
                    }
                } else {
                    engine.ingestCDP(seekSeconds: sampleSec, nowWall: now)
                }
            } else {
                if cdpAvailable { cdpAvailable = false }
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
    }

    var durationMs: Int { activeSong?.durationMs ?? 0 }

    // MARK: - 30488 歌词兜底（C-12）
    /// 内嵌 lyric 为空的歌：有缓存就注入兜底词，否则触发异步拉取。仅网易云数字 id 兜底（local:// 等跳过）。
    private func withFallbackLyric(_ song: Song) -> Song {
        guard IslandStateMachine.lyricMode(song) == .none, Int(song.id.value) != nil else { return song }
        let id = song.id.value
        if let fb = fallbackLyrics[id] {
            // 命中缓存：有词注入；空词=负缓存(已查无)，保持原样、不再重拉。
            return (fb.lrcArray?.isEmpty == false) ? song.replacingLyric(fb) : song
        }
        fetchFallbackLyric(id: id)
        return song
    }

    /// 拉 30488：先 /lyric/new(yrc 逐字)，回落 /lyric(LRC)；解析后缓存，并即时注入当前曲。fetchingLyric 去重。
    private func fetchFallbackLyric(id: String) {
        guard fallbackLyrics[id] == nil, !fetchingLyric.contains(id) else { return }
        fetchingLyric.insert(id)
        Task {
            var lyric: Lyric?
            if let data = await client.rawLyricNew(id: id) { lyric = NeteaseLyricParser.parseYRCFromLyricNew(data) }
            if lyric == nil, let data = await client.rawLyric(id: id) { lyric = NeteaseLyricParser.parseClassicFromLyric(data) }
            fetchingLyric.remove(id)
            guard let lyric else {
                fallbackLyrics[id] = Lyric(hasWordByWord: false, lrcTimeArray: [], lrcArray: [])   // 负缓存：30488 也查无，停止重试
                return
            }
            fallbackLyrics[id] = lyric
            // 当前正显示该曲 → 立即注入，不等下一轮 status。
            if case .active(let s, let p) = island, s.id.value == id {
                island = .active(s.replacingLyric(lyric), playing: p)
            }
        }
    }

    // MARK: - 控制
    func togglePlay() {
        // 乐观即时翻转：按钮立刻切换形态，不等下一次 status 轮询(最多 ~0.7s 滞后)。
        if case .active(let song, let p) = island {
            island = .active(song, playing: !p)
            pendingPlay = (value: !p, until: nowMs() + 1500, songKey: song.id.value)
        }
        Task { await client.control(.togglePlay) }
    }
    // 切歌：放弃旧的乐观播放态，否则新歌会被旧暂停/播放目标污染。
    func next() { pendingPlay = nil; Task { await client.control(.next) } }
    func prev() { pendingPlay = nil; Task { await client.control(.prev) } }

    /// 当前歌是否被「喜欢」（乐观：仅反映本会话点击；AlgerMusic /api/status 不暴露真实红心态）。
    var currentLiked: Bool { guard let id = activeSong?.id.value else { return false }; return likedThisSession.contains(id) }

    /// 喜欢/取消喜欢当前歌（等同网易云红心 = Apple Music 式喜欢）。POST /api/toggle-favorite + 乐观切换红心显示。
    func toggleFavorite() {
        guard let id = activeSong?.id.value, !id.isEmpty else { return }
        if likedThisSession.contains(id) { likedThisSession.remove(id) } else { likedThisSession.insert(id) }
        Task { await client.control(.toggleFavorite) }
    }

    /// 拖动进度：先本地立即重锚（UI 即时反映），再发 CDP seek 命令到 AlgerMusic。
    func seek(toMs ms: Int) {
        let sec = Double(max(0, ms)) / 1000.0
        let now = nowMs()
        pendingSeek = (target: sec, wall: now)
        // 乐观重锚不更新 drift（seek 未确认）；若 seek 实际失败，清 pendingSeek 让回退/下次采样把位置纠回真实处，
        // 而非把假目标固化（C-1）。
        engine.ingestCDP(seekSeconds: sec, nowWall: now, updateDrift: false)
        let durSec = Double(durationMs) / 1000.0   // 暂停时 CDP 按曲长匹配正确 Howl 实例
        Task {
            let ok = await cdp.seek(toSeconds: sec, durationSec: durSec)
            if !ok, pendingSeek?.wall == now { pendingSeek = nil }
        }
    }
}
