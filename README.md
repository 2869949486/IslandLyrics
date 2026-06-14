<div align="center">

<img src="assets/icon.png" width="120" alt="IslandLyrics" />

# IslandLyrics · 灵动岛歌词

**贴住 MacBook 刘海的超薄歌词灵动岛 —— 数据来自本机 [AlgerMusicPlayer](https://github.com/algerkong/AlgerMusicPlayer)**

收起态显示专辑+歌名/逐字高亮歌词+频谱；悬停展开成详情面板，可拖动进度、控制播放、看整页滚动歌词。

[![Platform](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64%20only-black?logo=apple)](https://support.apple.com/116943)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)
[![Build](https://img.shields.io/badge/build-SwiftPM-blue?logo=swift)](https://www.swift.org/package-manager/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

---

## ✨ 截图

**收起态**（贴刘海的薄条：左 专辑+歌名·歌手 ｜ 中 摄像区留空 ｜ 右 当前歌词逐字高亮 + 频谱）

<div align="center"><img src="assets/collapsed.png" width="760" alt="收起态" /></div>

**展开态**（悬停 0.5 秒或点击展开：大封面、可拖动进度条、上一首/播放暂停/下一首、整页滚动歌词）

<div align="center"><img src="assets/expanded.png" width="760" alt="展开态" /></div>

---

## 🎯 特性

- 🎵 **从刘海自然长出的灵动岛**：顶贴边 + 肩部凹角 + 底圆角的 IslandShape，不是普通圆角浮窗；摄像头禁区任何状态都留空。
- 🔤 **逐字 / 逐行高亮**：有逐字（yrc）走逐字渐进高亮，没有就行内线性插值；长歌词横向滚动跟随高亮。
- 🎚️ **精准进度 + 可拖动 seek**：通过 CDP 读 Howler 真实播放位置，拖动进度条即时跳转（毫秒级，不是估算）。
- 🎨 **跟封面主色的频谱** + **可自定义配色字号**：歌名/歌手/歌词/高亮四色、收起/展开各自字号、歌词时间偏移，全部可在设置里调（QQ 音乐式取色器）。
- 🪶 **零侵入**：纯菜单栏后台 app（不进 Dock），只调 AlgerMusic 在本机暴露的 HTTP 接口，**不 fork、不改** AlgerMusic。
- 🚀 **开箱即用**：没装 AlgerMusic 会引导你去下载；装了但没带调试参数启动，会**自动带参重启**启用精准进度。
- 🛠️ **无需 Xcode**：纯 SwiftPM 构建 + 手工组 `.app` + ad-hoc 签名。

---

## 📦 环境要求

| 项 | 要求 |
|---|---|
| 芯片 | **仅 Apple Silicon（M 系列芯片，arm64 架构）**。⚠️ **不支持 Intel 芯片的 Mac** —— 预编译版是 arm64 单架构，Intel Mac 无法运行（且 Intel Mac 也没有刘海） |
| 系统 | macOS 13 (Ventura) 及以上 |
| 屏幕 | MacBook 内建刘海屏最佳（非刘海屏会退化成贴菜单栏的条）。多屏 MVP 仅用内建屏 |
| 依赖 | 本机安装并运行 **[AlgerMusicPlayer](https://github.com/algerkong/AlgerMusicPlayer)**（网易云第三方客户端），且开启**远程控制** |

> IslandLyrics 本身**不播放音乐**，它是 AlgerMusic 的「歌词显示外设」——播放/控制/歌词都来自 AlgerMusic 的本地接口。

---

## 🚀 安装与使用

### 方式一：下载预编译版（Releases）

1. 到 [Releases](../../releases) 下载 `灵动岛歌词.app`，拖进「应用程序」。
2. **首次打开会被 Gatekeeper 拦**（见下方 ⚠️ 绕过说明）。
3. 打开后它会自检 AlgerMusic：
   - **没装** → 岛上提示「点此前往安装」，跳转下载页。
   - **装了但没带调试口启动** → 自动带参重启 AlgerMusic 以启用精准进度（一次性，不打扰）。
4. 在 **AlgerMusic → 设置 → 应用设置 → 远程控制** 里**开启远程控制**（默认是关的，IslandLyrics 取数据必需）。
5. 放首歌，刘海上就出现歌词岛了。

### ⚠️ 绕过 Gatekeeper（重要）

本 app 用 **ad-hoc 签名**（没走 Apple 公证，因为公证需要付费的开发者账号）。所以从网上下载后首次打开，macOS 会弹「**"灵动岛歌词"已损坏 / 无法验证开发者**」。这是正常的，二选一绕过：

**方法 A（推荐，点几下）**：在「应用程序」里**右键**（或 Control+点击）`灵动岛歌词.app` → **打开** → 弹窗里再点一次「**打开**」。之后就正常了，只需做这一次。

**方法 B（命令行，一行搞定）**：

```bash
xattr -dr com.apple.quarantine "/Applications/灵动岛歌词.app"
```

> 直接双击打开如果只显示「无法打开」没有「打开」按钮，用上面任一方法即可。这不是病毒，只是没花钱买苹果公证。

### 方式二：从源码构建

不需要 Xcode，只要装了命令行 Swift 工具链（`xcode-select --install`）：

```bash
git clone https://github.com/2869949486/IslandLyrics.git
cd IslandLyrics
./build.sh                    # swift build -c release → 组 dist/灵动岛歌词.app → ad-hoc 签名
open "dist/灵动岛歌词.app"
pkill -x IslandLyrics          # 停止
```

跑测试：`swift run IslandLyricsCoreTests`（无 XCTest 依赖的断言式 runner）。

---

## ⚙️ 设置

菜单栏图标（`music.note.list`）右键，或**右键刘海条**，弹出菜单：

- 上一首 / 播放暂停 / 下一首
- 歌词偏移（提前/延后 0.5s，全局生效）
- 显示/隐藏歌词岛
- **重启 AlgerMusic（精准进度）**——精准 seek 没生效时一键修
- 外观设置…（自定义四色 + 收起/展开字号 + 开机启动 + 连接状态）

---

## 🧠 工作原理

AlgerMusic 在本机暴露两个 localhost HTTP 口 + 一个可选的调试口，IslandLyrics 全靠它们：

| 来源 | 端口 | 用途 |
|---|---|---|
| 远程控制 API | `31888` | `GET /api/status` 拿当前歌（含已解析的逐字歌词+翻译+封面主色）；`POST /api/{toggle-play,prev,next}` 控制 |
| 网易云歌词 API | `30488` | `currentSong.lyric` 为空时的歌词兜底（`/lyric/new` 逐字、`/lyric` 经典 LRC） |
| CDP 调试口 | `9222` | 读渲染进程里 Howler 的真实 `seek()` → 精准进度 + 完美 seek（不可用时回退 `createdAt` + 本地时钟插值） |

端口都从 `~/Library/Application Support/AlgerMusicPlayer/config.json` 读、不硬编码。详见 [docs/INTEGRATION.md](docs/INTEGRATION.md)。

> 技术栈：Swift / SwiftUI / AppKit，`NSPanel(.nonactivatingPanel)` 覆盖窗 + 自绘 IslandShape；数据/解析/插值在纯逻辑 Core 库里、有单测覆盖。

---

## ⚠️ 已知限制

- **逐字像素对齐**：逐字高亮进度按「字符数」算，渲染按「像素宽」遮罩，中英混排时高亮边界与实际字形有轻微偏差（不影响逐行/纯中文/纯英文）。
- **多屏**：MVP 仅内建刘海屏；合盖外接（clamshell）/Sidecar 等场景下的多屏适配尚未完善。
- **依赖 AlgerMusic 版本**：基于 AlgerMusic 5.1.0 的接口实测；端口/字段随其版本可能变动，启动时会探测而非硬编码。
- **远程控制需手动开**：AlgerMusic 的远程控制默认关闭，需在其设置里开启（IslandLyrics 无法代开，会图文引导）。

---

## 🙏 致谢 / 关系说明

- **[AlgerMusicPlayer](https://github.com/algerkong/AlgerMusicPlayer)** by [@algerkong](https://github.com/algerkong)：本项目的数据源。IslandLyrics 只调用它在 localhost 暴露的 HTTP 接口，**不包含、不修改其任何代码**，二者各自独立、各自授权。
- 歌词数据来自网易云音乐（经 AlgerMusic 代理）。

---

## 📄 许可证

[MIT](LICENSE) © 2026 taoxi_honey

> 本项目与 AlgerMusicPlayer、网易云音乐均无隶属关系，仅为个人兴趣的互操作工具。
