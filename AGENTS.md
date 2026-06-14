# IslandLyrics — 项目约定（给 AI 助手 / 贡献者）

macOS 刘海「灵动岛歌词」app：贴住 MacBook 刘海的超薄黑色岛，数据来自本机 AlgerMusicPlayer 的 localhost 接口。Swift/SwiftUI/AppKit，SwiftPM 构建（本机无 Xcode）。

## 构建 / 运行（无 Xcode，SwiftPM + 手工组 .app + ad-hoc 签名）

```bash
./build.sh                    # swift build -c release → 组 dist/灵动岛歌词.app → codesign -
open "dist/灵动岛歌词.app"     # 顶部刘海区出现歌词岛
pkill -x IslandLyrics          # 停止
swift run IslandLyricsCoreTests # 跑单测（无 XCTest 的断言式 runner）
```

## 源码结构

- `Sources/IslandLyricsCore/` — 纯逻辑 + 网络层（无 SwiftUI），可单测：PositionEngine(插值)、CDPPositionReader、AlgerMusicClient、NeteaseLyricParser、LyricIndex、PortDiscovery、ProcessDetector、Models、IslandState、ColorComponents。
- `Sources/IslandLyrics/` — AppKit/SwiftUI：IslandView(收起/展开状态机)、ExpandedView(seek/控制)、IslandWindow(覆盖窗)、IslandShape、PlayerStore(协调器)、StatusBarController、Settings*。
- `Tests/IslandLyricsCoreTests/` — 断言式测试 runner。
- 接口事实见 [docs/INTEGRATION.md](docs/INTEGRATION.md)。

## 铁律

- 收起态必须是「从刘海自然长出」的 IslandShape（顶贴边+肩部凹角+底圆角），不是普通圆角浮窗。
- 摄像禁区任何状态不放内容；收起态歌词与频谱分开排布。
- 非激活面板（`NSPanel(.nonactivatingPanel)`）里**自定义鼠标光标(NSCursor)无法生效**，别再加。
- 不 fork AlgerMusic，只调它 localhost 的 HTTP 接口；不用 Rust 语言工具链。
- 本机无 Xcode：SwiftPM build，禁 xcodebuild/storyboard/asset catalog。

## 关键坑（实测）

- `currentSong.dt`/`duration` 是毫秒；`/api/status` 无播放进度，需 CDP 或 createdAt 锚点+本地时钟插值。
- AlgerMusic 远程控制默认关，端口从 `config.json` 读而非硬编码。
- 网易云响应 Content-Type 恒 text/plain、HTTP 恒 200，错误看 JSON 内 `code`；yrc 开头 JSON credits 行要跳过。
- 给 AlgerMusic 的请求用独立 `URLSession` + `connectionProxyDictionary=[:]` 关代理 + 字面 `127.0.0.1`（用户常开 Clash+TUN）。
