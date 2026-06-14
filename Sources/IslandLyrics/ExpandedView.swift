import SwiftUI
import AppKit
import IslandLyricsCore

/// 展开态内容（嵌在灵动岛延展出的形状里，非独立窗口）：
/// 左 大封面+歌名歌手+进度条(可拖动 seek)+上一首/播放暂停/下一首；右 可滚动整页歌词。
/// topInset 让内容避开顶部摄像区。
struct ExpandedContent: View {
    let song: Song
    let playing: Bool
    @ObservedObject var store: PlayerStore
    @ObservedObject var settings: SettingsStore
    var topInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)   // 让开摄像区
            HStack(alignment: .center, spacing: 24) {        // 左右两等分：播放器/歌词各占半区并各自居中，左右对称
                VStack(alignment: .center, spacing: 12) {    // 左侧整体水平居中（含专辑图）
                    AlbumThumb(coverURL: song.coverURL, tint: Color.alger(song.primaryColor, fallback: Color(white: 0.3)))
                        .frame(width: 116, height: 116)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                    VStack(spacing: 2) {
                        Text(song.name ?? "未知歌曲")
                            .font(.system(size: settings.expandedTitleFontSize, weight: .bold))
                            .foregroundColor(settings.songNameColor).lineLimit(1)
                        Text(song.artistText)
                            .font(.system(size: max(11, settings.expandedTitleFontSize - 4)))
                            .foregroundColor(settings.artistColor.opacity(0.85)).lineLimit(1)
                    }
                    .multilineTextAlignment(.center)
                    SeekableProgressBar(store: store, durationMs: song.durationMs, playing: playing)
                    ControlsRow(store: store, playing: playing)
                }
                .frame(width: 200)
                .frame(maxWidth: .infinity)   // 200pt 播放器块在左半区水平居中

                LyricScroll(song: song, store: store,
                            baseColor: settings.lyricColor, highlightColor: settings.lyricHighlightColor,
                            fontSize: settings.expandedLyricFontSize, offsetMs: Int(settings.lyricOffsetMs))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)   // 吃满右侧到边
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 26)  // 左右等距留白
            .padding(.top, 8)
            .padding(.bottom, 26)      // 底留白（与左右一致）
        }
    }
}

/// 可拖动 / 点按 seek 的进度条；显示当前/总时长。
private struct SeekableProgressBar: View {
    @ObservedObject var store: PlayerStore
    let durationMs: Int
    var playing: Bool = true
    @State private var scrub: Double? = nil   // 拖动中的预览 0...1

    private func liveFrac() -> Double {
        durationMs > 0 ? min(1, max(0, Double(store.currentPositionMs()) / Double(durationMs))) : 0
    }

    // 填充 + 滑块。仅在播放时按 30fps 重绘；暂停/拖动时位置由 scrub 或冻结值驱动，无需 TimelineView 空烧。
    @ViewBuilder private func fill(width: CGFloat) -> some View {
        if playing && scrub == nil {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in fillBars(width: width, frac: liveFrac()) }
        } else {
            fillBars(width: width, frac: scrub ?? liveFrac())
        }
    }

    private func fillBars(width: CGFloat, frac: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.92)).frame(width: width * frac, height: 4)
            Circle().fill(.white).frame(width: 11, height: 11).offset(x: width * frac - 5.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 已播/总时长文本，整秒粒度。仅播放时低频(2fps)刷新，暂停/拖动靠状态变化驱动。
    @ViewBuilder private func timeLabels() -> some View {
        if playing && scrub == nil {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in timeRow(frac: liveFrac()) }
        } else {
            timeRow(frac: scrub ?? liveFrac())
        }
    }

    private func timeRow(frac: Double) -> some View {
        HStack {
            Text(Self.mmss(Int(frac * Double(durationMs)))).foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(Self.mmss(durationMs)).foregroundColor(.white.opacity(0.6))
        }.font(.system(size: 10).monospacedDigit())
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22)).frame(height: 4)
                    fill(width: geo.size.width)
                    // 交互层：AppKit NSView 处理「拖动 / 点按 seek」（在 nonactivating 面板里比 SwiftUI 手势更可靠）
                    SeekTrack(
                        onScrub: { f in if durationMs > 0 { scrub = f } },
                        // 时长未知(本地歌/缺 dt)时不响应 seek，避免把进度/歌词重锚到 0。
                        onCommit: { f in if durationMs > 0 { store.seek(toMs: Int(f * Double(durationMs))) }; scrub = nil }
                    )
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            // 吃掉进度条区域的 tap，避免冒泡到岛的 .onTapGesture 把展开的岛收起（seek 仍由 AppKit SeekTrack 处理）。
            .contentShape(Rectangle())
            .onTapGesture { }
            timeLabels()
        }
    }

    static func mmss(_ ms: Int) -> String {
        let s = max(0, ms / 1000); return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 进度条交互层（AppKit）：用 mouseDown/Dragged/Up 处理拖动 / 点按 seek
/// （在 nonactivating 面板里比 SwiftUI 手势更可靠）。
private struct SeekTrack: NSViewRepresentable {
    let onScrub: (Double) -> Void
    let onCommit: (Double) -> Void
    func makeNSView(context: Context) -> SeekTrackView {
        let v = SeekTrackView(); v.onScrub = onScrub; v.onCommit = onCommit; return v
    }
    func updateNSView(_ v: SeekTrackView, context: Context) {
        v.onScrub = onScrub; v.onCommit = onCommit
    }
}

final class SeekTrackView: NSView {
    var onScrub: ((Double) -> Void)?
    var onCommit: ((Double) -> Void)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func frac(_ event: NSEvent) -> Double {
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0 else { return 0 }
        return min(1, max(0, p.x / bounds.width))
    }

    // Control+左键是右键菜单的替代手段：让它冒泡回 FirstMouseHostingView 弹菜单，而非误触发 seek。
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { super.mouseDown(with: event); return }
        onScrub?(frac(event))
    }
    override func mouseDragged(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { super.mouseDragged(with: event); return }
        onScrub?(frac(event))
    }
    override func mouseUp(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { super.mouseUp(with: event); return }
        onCommit?(frac(event))
    }
}

private struct ControlsRow: View {
    @ObservedObject var store: PlayerStore
    let playing: Bool

    var body: some View {
        HStack(spacing: 22) {
            ControlButton(symbol: "backward.fill", size: 15) { store.prev() }
            ControlButton(symbol: playing ? "pause.fill" : "play.fill", size: 20) { store.togglePlay() }
            ControlButton(symbol: "forward.fill", size: 15) { store.next() }
        }
        .frame(maxWidth: .infinity)
    }
}

/// 控制按钮：悬停放大 + 圆形高亮背景。（非激活面板里自定义 NSCursor 无效，不设手型光标。）
private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white)
                .frame(width: size + 20, height: size + 20)
                .background(Circle().fill(Color.white.opacity(hover ? 0.16 : 0)))
                .scaleEffect(hover ? 1.14 : 1.0)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hover = h }
        }
    }
}


/// 可滚动整页歌词，当前行高亮(用设置色/字号) + 自动滚到中部
private struct LyricScroll: View {
    let song: Song
    @ObservedObject var store: PlayerStore
    let baseColor: Color
    let highlightColor: Color
    let fontSize: Double
    var offsetMs: Int = 0
    @State private var current = -1
    private let tick = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        let lines = song.lyric?.lrcArray ?? []
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                if lines.isEmpty {
                    Text(IslandStateMachine.lyricMode(song) == .instrumental ? "纯音乐，无歌词" : "暂无歌词")
                        .font(.system(size: fontSize)).foregroundColor(baseColor.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVStack(alignment: .center, spacing: 9) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            VStack(alignment: .center, spacing: 1) {
                                Text(line.text.isEmpty ? " " : line.text)
                                    .font(.system(size: fontSize, weight: i == current ? .semibold : .regular))
                                    .foregroundColor(i == current ? highlightColor : baseColor.opacity(0.5))
                                if let tr = line.trText, !tr.isEmpty {
                                    Text(tr).font(.system(size: max(10, fontSize - 2)))
                                        .foregroundColor((i == current ? highlightColor : baseColor).opacity(0.4))
                                }
                            }
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)   // 行居中：短歌词空白匀到两侧，不再全堆右边
                            .id(i)
                        }
                    }
                    .padding(.vertical, 120)
                }
            }
            .mask(   // 顶/底渐隐：营造留白 + 暗示可滚动
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.13),
                    .init(color: .black, location: 0.87),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .onReceive(tick) { _ in
                let idx = LyricIndex.currentLineIndex(lines, positionMs: store.currentPositionMs() + offsetMs) ?? -1
                if idx != current {
                    current = idx
                    if idx >= 0 { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(idx, anchor: .center) } }
                }
            }
        }
    }
}
