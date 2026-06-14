import SwiftUI

/// 外观设置：顶部实时预览 + 颜色卡片 + 字号卡片。改动即时反映到刘海歌词岛与预览。
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var store: PlayerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                preview
                colorCard
                fontCard
                timeCard
                statusCard
                footer
            }
            .padding(22)
        }
        .frame(width: 440, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.43, green: 0.36, blue: 1), Color(red: 1, green: 0.3, blue: 0.66)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 1) {
                Text("外观设置").font(.system(size: 15, weight: .semibold))
                Text("自定义歌词岛的配色与字号，改动即时生效").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // 实时预览：真实复用 SongInfoLabel + KaraokeLine，所见即所得
    private var preview: some View {
        HStack(spacing: 10) {
            Group {
                if let img = bundleImage("sample-cover") {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(white: 0.9), Color(white: 0.55)], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            SongInfoLabel(name: "示例歌曲", artist: "演示歌手",
                          nameColor: settings.songNameColor, artistColor: settings.artistColor,
                          fontSize: settings.collapsedTitleFontSize)
            Spacer(minLength: 14)
            KaraokeLine(text: "这是一句示例歌词",
                        font: .system(size: settings.collapsedLyricFontSize, weight: .medium),
                        baseColor: settings.lyricColor, highlightColor: settings.lyricHighlightColor,
                        progress: 0.55)
                .fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }

    private var colorCard: some View {
        card("颜色") {
            colorRow("歌曲名", $settings.songNameColor)
            Divider()
            colorRow("作者名", $settings.artistColor)
            Divider()
            colorRow("歌词", $settings.lyricColor)
            Divider()
            colorRow("高亮歌词", $settings.lyricHighlightColor)
        }
    }

    private var fontCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            card("收起态字号") {
                sizeRow("歌词", $settings.collapsedLyricFontSize, SettingsStore.collapsedLyricRange)
                Divider()
                sizeRow("歌名 / 作者", $settings.collapsedTitleFontSize, SettingsStore.collapsedTitleRange)
            }
            card("展开态字号") {
                sizeRow("歌词", $settings.expandedLyricFontSize, SettingsStore.expandedLyricRange)
                Divider()
                sizeRow("歌名 / 作者", $settings.expandedTitleFontSize, SettingsStore.expandedTitleRange)
            }
        }
    }

    private var timeCard: some View {
        card("歌词时间轴 · 全局偏移（对所有歌曲生效）") {
            HStack(spacing: 12) {
                Text("偏移").font(.system(size: 13)).frame(width: 76, alignment: .leading)
                Slider(value: $settings.lyricOffsetMs, in: SettingsStore.offsetRange, step: 100)
                Text(String(format: "%+.1fs", settings.lyricOffsetMs / 1000))
                    .font(.system(size: 12)).monospacedDigit().foregroundColor(.secondary)
                    .frame(width: 46, alignment: .trailing)
            }
            .frame(height: 40)
        }
    }

    private var statusCard: some View {
        card("状态") {
            statusRow("AlgerMusic", store.processRunning ? "运行中" : "未运行",
                      ok: store.processRunning)
            Divider()
            statusRow("远程控制 · 端口 \(store.remotePort)", store.remoteReachable ? "已连接" : "未开启",
                      ok: store.remoteReachable)
            Divider()
            statusRow("精准进度", store.cdpAvailable ? "CDP 实时" : "插值模式（够用）",
                      ok: store.cdpAvailable)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("开机启动").font(.system(size: 13))
                    Spacer()
                    // 实时绑定：每次重渲染直接读真实状态，避免窗口复用导致 @State 缓存陈旧；
                    // set 后下次渲染回读，requiresApproval 也算已启用故不弹回。
                    Toggle("", isOn: Binding(
                        get: { LaunchAtLogin.isEnabled },
                        set: { LaunchAtLogin.set($0) }
                    )).labelsHidden()
                }
                // ad-hoc 签名常落到 requiresApproval：已注册但需用户手动批准，给出引导（C-11）。
                if LaunchAtLogin.needsApproval {
                    Text("需在「系统设置 → 通用 → 登录项」中批准本 App")
                        .font(.system(size: 11)).foregroundColor(.orange)
                }
            }
            .frame(minHeight: 38)
        }
    }

    private func statusRow(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(ok ? Color.green : Color.orange).frame(width: 7, height: 7)
                Text(value).font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
        .frame(height: 36)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(role: .none) { settings.resetDefaults() } label: {
                Label("恢复默认", systemImage: "arrow.counterclockwise")
            }
        }
    }

    // MARK: 组件

    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                .textCase(.uppercase).kerning(0.5)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
    }

    private func colorRow(_ label: String, _ binding: Binding<Color>) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            ColorField(color: binding)
        }
        .frame(height: 38)
    }

    private func sizeRow(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 13)).frame(width: 76, alignment: .leading)
            Slider(value: value, in: range, step: 0.5)
            Text(String(format: "%.0f", value.wrappedValue)).font(.system(size: 12)).monospacedDigit()
                .foregroundColor(.secondary).frame(width: 26, alignment: .trailing)
        }
        .frame(height: 40)
    }
}
