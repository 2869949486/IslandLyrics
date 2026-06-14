import Foundation
import IslandLyricsCore

// 极简断言 runner（CLT 无 XCTest）。所有 check 累计失败，末尾汇总并以非零码退出。
var failures = 0
var passes = 0
func check(_ cond: Bool, _ msg: String, line: UInt = #line) {
    if cond { passes += 1 } else { failures += 1; print("  ✗ FAIL [\(line)] \(msg)") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ msg: String, line: UInt = #line) {
    if a == b { passes += 1 } else { failures += 1; print("  ✗ FAIL [\(line)] \(msg): \(a) != \(b)") }
}
func approx(_ a: Double, _ b: Double, _ msg: String, eps: Double = 1e-6, line: UInt = #line) {
    if abs(a - b) <= eps { passes += 1 } else { failures += 1; print("  ✗ FAIL [\(line)] \(msg): \(a) !~ \(b)") }
}
func group(_ name: String, _ body: () -> Void) { print("• \(name)"); body() }

// MARK: Models
group("Models decode") {
    let sample = """
    {"isPlaying":true,"currentSong":{
      "name":"把回忆拼好给你","id":1403318151,"unknownA":123,"alia":[],
      "ar":[{"id":1,"name":"王贰浪","tns":[]}],
      "al":{"id":83305009,"name":"把回忆拼好给你","picUrl":"http://x/cover.jpg"},
      "dt":381000,"createdAt":1781337599199,"expiredAt":1781339399199,
      "primaryColor":"rgb(171,169,176)",
      "backgroundColor":"linear-gradient(to bottom, rgb(223, 222, 225) 0%, rgb(171, 169, 176) 50%, rgb(94, 90, 99) 100%)",
      "lyric":{"hasWordByWord":false,"lrcTimeArray":[2.12,12.15],
        "lrcArray":[
          {"text":"采样曲：願い","trText":"","startTime":2120,"duration":10030,"hasWordByWord":false,"words":[]},
          {"text":"Oh whoa","trText":"哦","startTime":17370,"duration":740,"hasWordByWord":true,
            "words":[{"text":"Oh","startTime":17370,"duration":370,"space":true},
                     {"text":"whoa","startTime":17740,"duration":370,"space":false}]}
        ]}
    }}
    """.data(using: .utf8)!
    let s = StatusResponse.decode(sample)
    check(s != nil, "decode succeeds")
    check(s?.isPlaying == true, "isPlaying")
    let song = s?.currentSong
    eq(song?.id.value, "1403318151", "id int->string")
    eq(song?.artistText, "王贰浪", "artistText")
    eq(song?.coverURL, "https://x/cover.jpg", "coverURL (http→https 升级)")
    eq(song?.durationMs, 381000, "durationMs")
    eq(song?.createdAt, 1781337599199, "createdAt")
    eq(song?.lyric?.lrcArray?.count, 2, "lrcArray count")

    let strID = StatusResponse.decode(#"{"isPlaying":false,"currentSong":{"id":"local-abc","name":"x"}}"#.data(using: .utf8)!)
    eq(strID?.currentSong?.id.value, "local-abc", "FlexibleID from string")

    let nullSong = StatusResponse.decode(#"{"isPlaying":false,"currentSong":null}"#.data(using: .utf8)!)
    check(nullSong != nil && nullSong?.currentSong == nil, "null currentSong")

    // A1 回归：id 解析成超出 Int 范围的浮点不得让 Int(d) trap 崩进程（若崩，runner 直接挂）。
    let hugeID = StatusResponse.decode(#"{"isPlaying":true,"currentSong":{"id":1e30}}"#.data(using: .utf8)!)
    check(hugeID?.currentSong != nil, "huge-double id decodes without crash")
    check(!(hugeID?.currentSong?.id.isEmpty ?? true), "huge-double id non-empty")
}

// MARK: Color
group("Color parse") {
    let c = RGBComponents.parse("rgb(171,169,176)")
    approx(c?.r ?? -1, 171/255.0, "rgb r")
    approx(c?.g ?? -1, 169/255.0, "rgb g")
    approx(c?.b ?? -1, 176/255.0, "rgb b")
    approx(RGBComponents.parse("rgba(10, 20, 30, 0.5)")?.r ?? -1, 10/255.0, "rgba r")
    approx(RGBComponents.firstFromGradient("linear-gradient(to bottom, rgb(223, 222, 225) 0%, rgb(171,169,176) 50%)")?.r ?? -1, 223/255.0, "gradient first")
    check(RGBComponents.parse("transparent") == nil, "garbage nil")
    check(RGBComponents.parse(nil) == nil, "nil nil")
    // A-1 回归：")" 在 "(" 之前的畸形串不得触发 Range lowerBound>upperBound 崩溃（若崩，runner 直接挂）。
    check(RGBComponents.parse(")(") == nil, "malformed ')(' no crash")
    check(RGBComponents.parse("x)y(z") == nil, "malformed 'x)y(z' no crash")
    check(RGBComponents.parse("rgb)(") == nil, "malformed 'rgb)(' no crash")
}

// MARK: LyricParser 健壮性
group("LyricParser robustness") {
    // 正常戳仍对
    eq(NeteaseLyricParser.lrcStampMs("01:23.45"), 83450, "lrcStamp normal")
    eq(NeteaseLyricParser.lrcStampMs("00:05"), 5000, "lrcStamp no frac")
    check(NeteaseLyricParser.lrcStampMs("ti:标题") == nil, "lrcStamp metadata nil")
    // A-2 回归：≥15 位分钟数（能进 Int64 但乘法溢出）不得 SIGTRAP 崩溃。
    check(NeteaseLyricParser.lrcStampMs("1000000000000000:00.00") == nil, "lrcStamp 16-digit minute no crash")
    check(NeteaseLyricParser.lrcStampMs("99999999999999999:00") == nil, "lrcStamp huge minute no crash")

    // C-12 接线后解析器上线：补 yrc/LRC 解析 + D-3 错误码守卫覆盖。
    let lrcBody = #"{"code":200,"lrc":{"lyric":"[00:01.00]第一行\n[00:03.50]第二行"},"tlyric":{"lyric":"[00:01.00]line1"}}"#.data(using: .utf8)!
    let lrc = NeteaseLyricParser.parseClassicFromLyric(lrcBody)
    eq(lrc?.lrcArray?.count, 2, "LRC parse 2 lines")
    eq(lrc?.lrcArray?.first?.startTime, 1000, "LRC first startTime")
    eq(lrc?.lrcArray?.first?.trText, "line1", "LRC translation merged")
    let yrcBody = #"{"code":200,"yrc":{"lyric":"[1000,500](1000,250,0)Hel(1250,250,0)lo"}}"#.data(using: .utf8)!
    let yrc = NeteaseLyricParser.parseYRCFromLyricNew(yrcBody)
    eq(yrc?.lrcArray?.first?.text, "Hello", "YRC word join")
    eq(yrc?.lrcArray?.first?.words?.count, 2, "YRC 2 words")
    check(yrc?.hasWordByWord == true, "YRC hasWordByWord")
    // D-3：错误体（code != 200）一律 nil，不当成空词。
    let errBody = #"{"code":-460,"lrc":{"lyric":"[00:01.00]should be ignored"}}"#.data(using: .utf8)!
    check(NeteaseLyricParser.parseClassicFromLyric(errBody) == nil, "error code -460 → nil")
    check(NeteaseLyricParser.parseYRCFromLyricNew(#"{"code":404}"#.data(using: .utf8)!) == nil, "error code 404 → nil")
}

// MARK: LyricIndex
group("LyricIndex") {
    let lines: [LyricLine] = [
        .init(text: "l0", trText: nil, startTime: 1000, duration: 2000, hasWordByWord: false, words: nil),
        .init(text: "l1", trText: nil, startTime: 3000, duration: 2000, hasWordByWord: false, words: nil),
        .init(text: "l2", trText: nil, startTime: 5000, duration: 2000, hasWordByWord: false, words: nil),
    ]
    check(LyricIndex.currentLineIndex(lines, positionMs: 500) == nil, "before first → nil")
    eq(LyricIndex.currentLineIndex(lines, positionMs: 1000), 0, "at line0")
    eq(LyricIndex.currentLineIndex(lines, positionMs: 2999), 0, "still line0")
    eq(LyricIndex.currentLineIndex(lines, positionMs: 3000), 1, "line1")
    eq(LyricIndex.currentLineIndex(lines, positionMs: 9999), 2, "line2 clamp")
    check(LyricIndex.currentLineIndex([], positionMs: 100) == nil, "empty → nil")

    approx(LyricIndex.revealFraction(lines[0], positionMs: 1000), 0, "linear 0")
    approx(LyricIndex.revealFraction(lines[0], positionMs: 2000), 0.5, "linear mid")
    approx(LyricIndex.revealFraction(lines[0], positionMs: 3000), 1, "linear end")
    approx(LyricIndex.revealFraction(lines[0], positionMs: 5000), 1, "linear clamp")

    let w = LyricLine(text: "Ohwhoa", trText: nil, startTime: 17370, duration: 740, hasWordByWord: true,
        words: [.init(text: "Oh", startTime: 17370, duration: 370, space: false),
                .init(text: "whoa", startTime: 17740, duration: 370, space: false)])
    approx(LyricIndex.revealFraction(w, positionMs: 17000), 0, "word before")
    approx(LyricIndex.revealFraction(w, positionMs: 17555), 1.0/6.0, "word mid Oh")
    approx(LyricIndex.revealFraction(w, positionMs: 17740), 2.0/6.0, "word Oh done")
    approx(LyricIndex.revealFraction(w, positionMs: 18110), 1.0, "word all done")
}

// MARK: PositionEngine
group("PositionEngine") {
    do {
        let e = PositionEngine()
        e.ingestStatus(songKey: "a", isPlaying: true, createdAt: nil, nowWall: 1000)
        e.ingestCDP(seekSeconds: 100, nowWall: 1000)
        eq(e.current(nowWall: 1000), 100_000, "cdp anchor")
        eq(e.current(nowWall: 1500), 100_500, "cdp interp 0.5s")
        eq(e.current(nowWall: 2000), 101_000, "cdp interp 1s")
    }
    do {
        let e = PositionEngine()
        e.ingestStatus(songKey: "a", isPlaying: true, createdAt: nil, nowWall: 1000)
        e.ingestCDP(seekSeconds: 100, nowWall: 1000)
        e.ingestStatus(songKey: "a", isPlaying: false, createdAt: nil, nowWall: 2000)
        // C-2：暂停冻结到「暂停那刻外推值」= 100s + (2000-1000=1s) = 101s（更准，非回退到上次 CDP 锚 100s）。
        eq(e.current(nowWall: 2500), 101_000, "pause freeze (extrapolated to pause instant)")
        eq(e.current(nowWall: 9999), 101_000, "pause stays frozen")
    }
    do {
        let e = PositionEngine()
        e.ingestStatus(songKey: "a", isPlaying: true, createdAt: nil, nowWall: 1000)
        e.ingestCDP(seekSeconds: 100, nowWall: 1000)
        e.ingestStatus(songKey: "b", isPlaying: true, createdAt: 500, nowWall: 3000)
        eq(e.current(nowWall: 3000), 2500, "song change fallback anchor")
        eq(e.current(nowWall: 3500), 3000, "fallback interp")
    }
    do {
        let e = PositionEngine()
        e.ingestStatus(songKey: "b", isPlaying: true, createdAt: 500, nowWall: 3000)
        e.ingestStatus(songKey: "b", isPlaying: false, createdAt: 500, nowWall: 4000)
        e.ingestStatus(songKey: "b", isPlaying: false, createdAt: 500, nowWall: 5000)
        e.ingestStatus(songKey: "b", isPlaying: true, createdAt: 500, nowWall: 6000)
        eq(e.current(nowWall: 6000), 3500, "fallback pause accumulation (2000ms paused)")
    }
    do {
        let e = PositionEngine(cdpFreshnessMs: 2000)
        e.ingestCDP(seekSeconds: 50, nowWall: 1000)
        e.ingestStatus(songKey: "a", isPlaying: true, createdAt: 0, nowWall: 1500)
        eq(e.current(nowWall: 1500), 50_500, "fresh CDP not overridden by fallback")
    }
    do {
        // B2/B3 回归：seek 使 CDP 真值偏离 createdAt 线性预测 +90s；CDP 失联回退后位置必须连续，
        // 不得跳回 createdAt 线。createdAt=0：无 seek 时 t=13000 预测 13s；seek 到 100s 后应为 103s。
        let e = PositionEngine(cdpFreshnessMs: 2000)
        e.ingestStatus(songKey: "s", isPlaying: true, createdAt: 0, nowWall: 10_000)
        e.ingestCDP(seekSeconds: 100, nowWall: 10_000)        // 用户 seek 到 100s
        eq(e.current(nowWall: 10_000), 100_000, "post-seek CDP anchor")
        eq(e.current(nowWall: 12_999), 102_999, "post-seek CDP interp")
        // 3s 后 CDP 已过期(>2000)，status 走 createdAt 回退：应 ~103s 而非跳回 13s
        e.ingestStatus(songKey: "s", isPlaying: true, createdAt: 0, nowWall: 13_000)
        eq(e.current(nowWall: 13_000), 103_000, "fallback continuous after seek (drift preserved, no jump)")
    }
    do {
        // B-1 回归：CDP 主路径「暂停→2s 内恢复」不得把暂停墙钟当播放外推致前跳（修前会跳到 101_800）。
        let e = PositionEngine(cdpFreshnessMs: 2000)
        e.ingestStatus(songKey: "p", isPlaying: true, createdAt: 0, nowWall: 10_000)
        e.ingestCDP(seekSeconds: 100, nowWall: 10_000)
        eq(e.current(nowWall: 10_500), 100_500, "B1 playing interp")
        e.ingestStatus(songKey: "p", isPlaying: false, createdAt: 0, nowWall: 11_000)   // 暂停
        eq(e.current(nowWall: 11_500), 101_000, "B1 paused freeze (extrapolated: 100s+1s)")
        e.ingestStatus(songKey: "p", isPlaying: true, createdAt: 0, nowWall: 11_800)    // 0.8s 后恢复(CDP 仍新鲜)
        eq(e.current(nowWall: 11_800), 101_000, "B1 resume no jump (not 101_800)")
        eq(e.current(nowWall: 12_000), 101_200, "B1 resume continues from freeze")
    }
    do {
        // B-4 回归：同 id 本地连切（songKey 同但 createdAt 变）必须当换歌复位，新歌不沿用上一首插值。
        let e = PositionEngine(cdpFreshnessMs: 2000)
        e.ingestStatus(songKey: "0", isPlaying: true, createdAt: 1000, nowWall: 5000)   // 歌A id=0 createdAt=1000
        eq(e.current(nowWall: 5000), 4000, "B4 song A pos (5000-1000)")
        e.ingestStatus(songKey: "0", isPlaying: true, createdAt: 8000, nowWall: 9000)   // 歌B 同 id createdAt 变=8000
        eq(e.current(nowWall: 9000), 1000, "B4 same-id new createdAt resets (9000-8000, not 8000)")
    }
    do {
        // B-4b 回归：同 id、createdAt 值→nil 也复位（修前漏判，会沿用 A 的锚外推到 8000）。
        let e = PositionEngine(cdpFreshnessMs: 2000)
        e.ingestStatus(songKey: "0", isPlaying: true, createdAt: 1000, nowWall: 5000)
        eq(e.current(nowWall: 5000), 4000, "B4b song A")
        e.ingestStatus(songKey: "0", isPlaying: true, createdAt: nil, nowWall: 9000)
        eq(e.current(nowWall: 9000), 0, "B4b value→nil resets (no stale anchor, not 8000)")
    }
    do {
        // B-4c 回归：同 id、createdAt nil→值 也复位、丢弃旧 CDP 锚（修前会沿用 A 的 CDP 锚到 204000）。
        let e = PositionEngine(cdpFreshnessMs: 2000)
        e.ingestStatus(songKey: "0", isPlaying: true, createdAt: nil, nowWall: 5000)
        e.ingestCDP(seekSeconds: 200, nowWall: 5000)
        eq(e.current(nowWall: 5000), 200_000, "B4c song A cdp anchor")
        e.ingestStatus(songKey: "0", isPlaying: true, createdAt: 8000, nowWall: 9000)
        eq(e.current(nowWall: 9000), 1000, "B4c nil→value resets (drops A cdp anchor, not 204000)")
    }
}

// MARK: IslandStateMachine
group("IslandStateMachine") {
    eq(IslandStateMachine.derive(processRunning: false, remoteReachable: false, status: nil), .hidden, "hidden")
    eq(IslandStateMachine.derive(processRunning: true, remoteReachable: false, status: nil), .guide, "guide")
    eq(IslandStateMachine.derive(processRunning: true, remoteReachable: true, status: StatusResponse(isPlaying: false, currentSong: nil)), .idle, "idle")
    let active = IslandStateMachine.derive(processRunning: true, remoteReachable: true,
        status: StatusResponse(isPlaying: true, currentSong: Song(id: .init("1"), name: "n", ar: nil, al: nil, picUrl: nil, dt: 1000, createdAt: nil, expiredAt: nil, primaryColor: nil, backgroundColor: nil, lyric: nil)))
    if case .active(_, let playing) = active { check(playing, "active playing") } else { check(false, "active case") }

    func mk(_ lines: [LyricLine]?) -> Song {
        Song(id: .init("1"), name: nil, ar: nil, al: nil, picUrl: nil, dt: 0, createdAt: nil, expiredAt: nil,
             primaryColor: nil, backgroundColor: nil,
             lyric: lines == nil ? nil : Lyric(hasWordByWord: nil, lrcTimeArray: nil, lrcArray: lines))
    }
    eq(IslandStateMachine.lyricMode(mk(nil)), .none, "mode none (nil)")
    eq(IslandStateMachine.lyricMode(mk([])), .none, "mode none (empty)")
    eq(IslandStateMachine.lyricMode(mk([.init(text: "纯音乐，请欣赏", trText: nil, startTime: 0, duration: 0, hasWordByWord: false, words: nil)])), .instrumental, "mode instrumental")
    eq(IslandStateMachine.lyricMode(mk([.init(text: "hi", trText: nil, startTime: 0, duration: 100, hasWordByWord: false, words: nil)])), .lineByLine, "mode lineByLine")
    eq(IslandStateMachine.lyricMode(mk([.init(text: "hi", trText: nil, startTime: 0, duration: 100, hasWordByWord: true, words: [.init(text: "hi", startTime: 0, duration: 100, space: nil)])])), .wordByWord, "mode wordByWord")
}

// MARK: PortDiscovery
group("PortDiscovery") {
    let p1 = PortDiscovery.parse(#"{"remoteControl":{"enabled":true,"port":31888,"allowedIps":[]}}"#.data(using: .utf8)!)
    eq(p1.remoteControlPort, 31888, "rc port")
    check(p1.remoteControlEnabled, "rc enabled")
    eq(p1.musicApiPort, 30488, "musicApiPort default (no key)")
    let p2 = PortDiscovery.parse(#"{"musicApiPort":40000,"remoteControl":{"enabled":false,"port":31999}}"#.data(using: .utf8)!)
    eq(p2.musicApiPort, 40000, "musicApiPort explicit")
    eq(p2.remoteControlPort, 31999, "rc port explicit")
    check(!p2.remoteControlEnabled, "rc disabled")
    eq(PortDiscovery.parse(Data("nonsense".utf8)), AlgerPorts.defaults, "garbage → defaults")
}

print("\n=== \(passes) passed, \(failures) failed ===")
exit(failures == 0 ? 0 : 1)
