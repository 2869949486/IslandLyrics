import SwiftUI
import AppKit
import IslandLyricsCore

/// 统一灵动岛：收起态是贴刘海的薄条；悬停/点击时**同一形状直接向下延展**成详情面板
/// （非另开一个胶囊）。隐藏=透明；引导/就绪=最小条；放歌收起=薄条；放歌展开=延展面板。
struct IslandView: View {
    let geometry: IslandGeometry
    @ObservedObject var store: PlayerStore
    @ObservedObject var settings: SettingsStore
    /// 展开状态变化回调（窗口据此调整命中区域，让收起时下方透明区点击穿透）
    var onExpandedChange: (Bool) -> Void = { _ in }
    /// 隐藏态变化回调（窗口据此让隐藏时全窗点击穿透，避免顶部薄条命中区吞点击）
    var onClickThroughChange: (Bool) -> Void = { _ in }
    var startExpanded = false
    /// 岛在屏幕坐标系下的矩形（= 覆盖窗 frame；展开态整窗即岛）。悬停轮询据此几何判定指针进/出。
    var islandRect: CGRect = .zero
    /// 菜单弹出闸：弹右键菜单期间冻结悬停轮询，避免把展开的岛收回致菜单悬空。
    var menuGate: MenuGate?

    @State private var expanded = false
    @State private var pinned = false   // 仅调试 --show-expanded 用：固定展开、轮询不收
    @State private var hoverPoll: Timer?   // 统一悬停轮询：几何命中真实鼠标坐标，绕开 .onHover 在屏幕边缘丢进/出事件
    @State private var inTicks = 0         // 连续命中收起态薄条的 tick 数（→ 展开）
    @State private var outTicks = 0        // 连续离开展开态整窗的 tick 数（→ 收起）
    @State private var suppressExpand = false   // 点击收起后抑制重展开，直到鼠标离开薄条

    /// 悬停多久后才展开（秒）
    private let hoverExpandDelay: TimeInterval = 0.5

    private let expandedHeight: CGFloat = 330

    var body: some View {
        let state = store.userHidden ? IslandState.hidden : store.island
        let active: Bool = { if case .active = state { return true } else { return false } }()
        let isExpanded = expanded && active
        let h: CGFloat = (state == .hidden) ? 0 : (isExpanded ? expandedHeight : geometry.islandHeight)

        let shape = IslandShape(topRadius: geometry.topRadius, bottomRadius: isExpanded ? 24 : geometry.bottomRadius)
        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if state != .hidden {
                    shape.fill(Color.black).frame(width: geometry.islandWidth, height: h)
                }
                content(state: state, isExpanded: isExpanded)
                    .frame(width: geometry.islandWidth, height: h, alignment: .top)
            }
            .frame(width: geometry.islandWidth, height: h)
            // 用岛形状罩住整个内容：过渡淡出/形变动画期间溢出岛形之外的内容（残影源头）一律裁掉。
            .mask(shape.frame(width: geometry.islandWidth, height: h))
            .contentShape(Rectangle())
            .onTapGesture { if active { toggle() } }
            Spacer(minLength: 0)
        }
        .frame(width: geometry.islandWidth, height: expandedHeight, alignment: .top)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: state)
        .onChange(of: isExpanded) { exp in onExpandedChange(exp) }
        .onChange(of: state) { s in onClickThroughChange(s == .hidden) }   // 隐藏态全窗穿透
        .onChange(of: active) { a in
            // 进 active 才开轮询；离开 active 收起并复位，避免跨歌残留展开态。
            if a { startHoverPoll() } else { stopHoverPoll(); expanded = false; pinned = false; suppressExpand = false }
        }
        .onAppear {
            if startExpanded { expanded = true; pinned = true }
            onClickThroughChange(state == .hidden)
            if active { startHoverPoll() }
        }
        .onDisappear { stopHoverPoll() }
    }

    /// 统一悬停轮询（active 期间常驻）：每 0.1s 用真实鼠标坐标做几何命中——
    /// 收起态判「顶部薄条」连续命中 hoverExpandDelay 秒 → 展开；展开态判「整窗」连续离开 0.3s → 收起。
    /// 几何判定绕开 .onHover 在屏幕边缘丢进/出事件的毛病（快速移到顶部停住也能精准识别）。
    private func startHoverPoll() {
        guard hoverPoll == nil, islandRect.width > 0 else { return }
        inTicks = 0; outTicks = 0
        let interval = 0.1
        let expandTicks = max(1, Int((hoverExpandDelay / interval).rounded()))   // 0.5s → 5
        let collapseTicks = 3                                                     // 0.3s
        // 收起态命中薄条 + 展开态命中整窗：两者上边界都向屏顶外多延 topPad。
        // 否则鼠标顶到最顶时 mouse.y==屏顶==maxY，CGRect.contains 不含上边界会漏判——
        // 收起态漏判→死活不展开；展开态漏判→误判离开→收起→薄条又命中→展开，无限闪烁(残影源头)。
        let topPad: CGFloat = 8
        let strip = CGRect(x: islandRect.minX, y: islandRect.maxY - geometry.islandHeight,
                           width: islandRect.width, height: geometry.islandHeight + topPad)
        let fullRect = CGRect(x: islandRect.minX, y: islandRect.minY,
                              width: islandRect.width, height: islandRect.height + topPad)
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            if menuGate?.isOpen == true { return }   // 右键菜单弹出期间冻结，免把展开的岛收回致菜单悬空
            let mouse = NSEvent.mouseLocation
            if expanded {
                inTicks = 0
                guard !pinned else { return }
                if fullRect.contains(mouse) { outTicks = 0 }
                else { outTicks += 1; if outTicks >= collapseTicks { expanded = false } }
            } else {
                outTicks = 0
                if strip.contains(mouse) {
                    if suppressExpand { inTicks = 0 }
                    else { inTicks += 1; if inTicks >= expandTicks { expanded = true } }
                } else {
                    inTicks = 0
                    suppressExpand = false   // 离开薄条 → 解除「点击收起」的抑制
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        hoverPoll = t
    }

    private func stopHoverPoll() {
        hoverPoll?.invalidate(); hoverPoll = nil; inTicks = 0; outTicks = 0
    }

    @ViewBuilder
    private func content(state: IslandState, isExpanded: Bool) -> some View {
        switch state {
        case .hidden:
            EmptyView()
        case .notInstalled:
            NotInstalledContent { store.openInstallPage() }
                .padding(.horizontal, geometry.topRadius + 6)
        case .guide:
            GuideContent().padding(.horizontal, geometry.topRadius + 6)
        case .idle:
            IdleContent().padding(.horizontal, geometry.topRadius + 6)
        case .active(let song, let playing):
            if isExpanded {
                ExpandedContent(song: song, playing: playing, store: store, settings: settings,
                                topInset: geometry.islandHeight + 4)
                    .id(song.id.value)   // 换歌即重建，复位子视图 @State(scrub/current)，免跨歌残留致跳错 seek/歌词停留上一首
                    .transition(.opacity)
            } else {
                collapsedActive(song, playing: playing)
                    .padding(.horizontal, geometry.topRadius + 6)
                    .transition(.opacity)
            }
        }
    }

    // 收起态放歌：左 专辑图+「歌名·歌手」marquee | 中 摄像禁区 | 右 当前歌词逐字高亮+频谱
    private func collapsedActive(_ song: Song, playing: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                AlbumThumb(coverURL: song.coverURL, tint: Color.alger(song.primaryColor, fallback: Color(white: 0.3)))
                    .frame(width: 22, height: 22)
                Marquee {
                    SongInfoLabel(name: song.name ?? "未知歌曲", artist: song.artistText,
                                  nameColor: settings.songNameColor, artistColor: settings.artistColor,
                                  fontSize: settings.collapsedTitleFontSize)
                }
                .frame(height: settings.collapsedTitleFontSize + 5)
            }
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: geometry.cameraZoneWidth)

            HStack(spacing: 12) {
                LyricStrip(song: song, store: store, playing: playing,
                           baseColor: settings.lyricColor, highlightColor: settings.lyricHighlightColor,
                           fontSize: settings.collapsedLyricFontSize, offsetMs: Int(settings.lyricOffsetMs))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                SpectrumView(color: Color.alger(song.primaryColor, fallback: settings.lyricHighlightColor),
                             animating: playing)
                    .frame(width: 20, height: 16)
            }
            .padding(.trailing, 4)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: geometry.islandHeight)
    }

    /// 点击：立即切换展开/收起。展开后不固定——鼠标移开由轮询自动收起（与悬停一致，只是立即展开）。
    /// 收起时置 suppressExpand，避免鼠标仍停在薄条上时被轮询立刻重新展开（须先离开薄条）。
    private func toggle() {
        expanded.toggle()
        pinned = false
        inTicks = 0; outTicks = 0
        if !expanded { suppressExpand = true }
    }
}

/// 当前歌词单行，每帧按真实插值位置定位行 + 渐进高亮。暂停时停帧（位置冻结，无需 30fps 空转）。
struct LyricStrip: View {
    let song: Song
    @ObservedObject var store: PlayerStore
    var playing: Bool = true
    let baseColor: Color
    let highlightColor: Color
    let fontSize: Double
    var offsetMs: Int = 0

    @ViewBuilder private func line(pos: Int) -> some View {
        let info = lineInfo(pos: pos)
        ScrollingKaraokeLine(text: info.text,
                             font: .system(size: fontSize, weight: .medium),
                             baseColor: baseColor,
                             highlightColor: highlightColor,
                             progress: info.karaoke ? info.fraction : 0)
    }

    var body: some View {
        if playing {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
                line(pos: store.currentPositionMs() + offsetMs)
            }
        } else {
            line(pos: store.currentPositionMs() + offsetMs)   // 暂停：位置冻结，静态渲染一次
        }
    }

    private func lineInfo(pos: Int) -> (text: String, fraction: Double, karaoke: Bool) {
        switch IslandStateMachine.lyricMode(song) {
        case .none: return ("暂无歌词", 0, false)
        case .instrumental: return ("纯音乐，无歌词", 0, false)
        case .lineByLine, .wordByWord:
            guard let lines = song.lyric?.lrcArray, !lines.isEmpty else { return ("暂无歌词", 0, false) }
            if let idx = LyricIndex.currentLineIndex(lines, positionMs: pos) {
                let line = lines[idx]
                return (line.text, LyricIndex.revealFraction(line, positionMs: pos), true)
            }
            return (lines[0].text, 0, true) // 早于首行：显示首行不高亮
        }
    }
}

/// 未安装态：本机没装 AlgerMusic → 点此打开下载页。
struct NotInstalledContent: View {
    var onInstall: () -> Void
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.down.circle").font(.system(size: 12)).foregroundColor(.orange)
            Text("未检测到 AlgerMusic，点此前往安装")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onInstall() }
    }
}

/// 引导态：远控未开。
struct GuideContent: View {
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color.orange).frame(width: 7, height: 7)
            Text("点此在 AlgerMusic 开启远程控制")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 就绪态：在运行、无歌。
struct IdleContent: View {
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(white: 0.22)).frame(width: 22, height: 22)
            Text("未在播放")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 专辑缩略图：网络封面，失败/加载中回退主色占位。
struct AlbumThumb: View {
    let coverURL: String?
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint)
            if let s = coverURL, let url = URL(string: s) {
                CachedCover(url: url)   // 缓存版：视图反复增删时不重载，消除专辑图残影
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// 封面图按 URL 缓存（NSCache）。AsyncImage 每次创建都重新拉取，展开/收起反复增删时
/// 重载+重绘会糊成残影；这里命中缓存即同步显示已加载图，彻底避免重载闪烁。
final class CoverCache {
    static let shared = CoverCache()
    private let cache = NSCache<NSString, NSImage>()
    func image(for url: URL) -> NSImage? { cache.object(forKey: url.absoluteString as NSString) }
    func store(_ img: NSImage, for url: URL) { cache.setObject(img, forKey: url.absoluteString as NSString) }
}

struct CachedCover: View {
    let url: URL
    @State private var loaded: NSImage?

    var body: some View {
        let img = loaded ?? CoverCache.shared.image(for: url)   // 命中缓存 → 同步显示，无加载态闪烁
        return Group {
            if let img { Image(nsImage: img).resizable().scaledToFill() }
            else { Color.clear }
        }
        .onAppear {
            guard CoverCache.shared.image(for: url) == nil else { return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let im = NSImage(data: data) else { return }
                CoverCache.shared.store(im, for: url)
                DispatchQueue.main.async { loaded = im }
            }.resume()
        }
    }
}

/// 行内渐进高亮：底色文本上叠高亮文本，用进度遮罩裁切。
struct KaraokeLine: View {
    let text: String
    let font: Font
    let baseColor: Color
    let highlightColor: Color
    let progress: Double

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .foregroundColor(baseColor)
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundColor(highlightColor)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle().frame(width: geo.size.width * progress)
                        }
                    }
            }
    }
}

/// 频谱动画，颜色由封面主色调传入；暂停时静止。
struct SpectrumView: View {
    let color: Color
    var animating: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: animating ? 1.0 / 30.0 : nil)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<4, id: \.self) { index in
                    let phase = Double(index) * 0.9
                    let speed = 1.7 + Double(index) * 0.4
                    let h = animating ? 5 + 9 * abs(sin(t * speed + phase)) : 4
                    RoundedRectangle(cornerRadius: 1.25)
                        .fill(color)
                        .frame(width: 2.5, height: h)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// 「歌名 · 歌手」标签：歌名亮、歌手稍暗，单行。
struct SongInfoLabel: View {
    let name: String
    let artist: String
    let nameColor: Color
    let artistColor: Color
    let fontSize: Double
    var body: some View {
        HStack(spacing: 5) {
            Text(name).foregroundColor(nameColor)
            if !artist.isEmpty {
                Text("·").foregroundColor(artistColor)
                Text(artist).foregroundColor(artistColor)
            }
        }
        .font(.system(size: fontSize, weight: .medium))
        .lineLimit(1)
        .fixedSize()
    }
}

/// 通用循环跑马灯：内容宽于可用宽度时两份拼接横向循环滚动；否则静止。
struct Marquee<Content: View>: View {
    var speed: CGFloat = 26
    var gap: CGFloat = 26
    let content: Content
    @State private var contentWidth: CGFloat = 0

    init(speed: CGFloat = 26, gap: CGFloat = 26, @ViewBuilder content: () -> Content) {
        self.speed = speed; self.gap = gap; self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.width
            ZStack(alignment: .leading) {
                if contentWidth > available + 1 {
                    TimelineView(.animation) { ctx in
                        let cycle = contentWidth + gap
                        let off = CGFloat(ctx.date.timeIntervalSinceReferenceDate * Double(speed))
                            .truncatingRemainder(dividingBy: cycle)
                        HStack(spacing: gap) { content; content }.offset(x: -off)
                    }
                } else {
                    content
                }
            }
            .frame(width: available, height: geo.size.height, alignment: .leading)
            .clipped()
        }
        .overlay(content.fixedSize().hidden().background(GeometryReader { p in
            Color.clear.preference(key: MarqueeWidthKey.self, value: p.size.width)
        }))
        .onPreferenceChange(MarqueeWidthKey.self) { contentWidth = $0 }
    }
}

/// 逐字高亮 + 横向滚动：长句歌词随高亮推进自动横向滚动（让正唱的字停在视图中部），
/// 整段（底色 + 高亮遮罩）一起位移，所以颜色流动渐变效果在滚动中不丢失。短句静止。
struct ScrollingKaraokeLine: View {
    let text: String
    let font: Font
    let baseColor: Color
    let highlightColor: Color
    let progress: Double
    @State private var textWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.width
            let overflow = max(0, textWidth - available)
            // 跟随高亮：高亮边界 x = textWidth*progress，使其停在视图 ~中部
            let target = textWidth * progress - available * 0.5
            let offset = min(max(0, target), overflow)
            KaraokeLine(text: text, font: font, baseColor: baseColor,
                        highlightColor: highlightColor, progress: progress)
                .fixedSize()
                .offset(x: -offset)
                .frame(width: available, height: geo.size.height, alignment: .leading) // .leading=水平靠左+垂直居中
                .clipped()
        }
        .overlay(Text(text).font(font).fixedSize().hidden().background(GeometryReader { p in
            Color.clear.preference(key: MarqueeWidthKey.self, value: p.size.width)
        }))
        .onPreferenceChange(MarqueeWidthKey.self) { textWidth = $0 }
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
