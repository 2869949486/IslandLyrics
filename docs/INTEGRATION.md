# AlgerMusic 集成技术说明

> NotchLyrics 如何从本机 AlgerMusicPlayer 取数据。基于 AlgerMusic 5.1.0（bundle id `com.alger.music`）实测。
> 端口与是否需手动开启依赖 AlgerMusic 版本，启动时探测、不硬编码。

## 三个本地口

| 口 | 端口（默认） | 模块 | 说明 |
|---|---|---|---|
| 远程控制 API | `31888` | Express，**默认关，用户需手动开** | 正在播放 + 播放控制 |
| 网易云歌词 API | `30488` | 内置 `netease-cloud-music-api` 分支 | 歌词兜底（App 注入登录 Cookie，下架歌也能出词） |
| CDP 调试口 | `9222` | Electron `--remote-debugging-port` | 读 Howler 真实播放位置（需带参启动） |

端口从 `~/Library/Application Support/AlgerMusicPlayer/config.json` 读：`remoteControl.port`、`musicApiPort`（实测常无此键 → 回退 30488）。

## 远程控制 API（31888）

- `GET /api/status` → `{ isPlaying: Bool, currentSong: SongResult }`
- `POST /api/{toggle-play, prev, next, volume-up, volume-down, toggle-favorite}` → `{success}`
- CORS 全开；IP 白名单留空 = 放行全部，`127.0.0.1` 直连即可。
- **开启路径**：AlgerMusic → 设置 → **应用设置**（不是「网络设置」）→ 远程控制 → 开启。

### currentSong 关键字段（实测）

- `id`：网易云歌曲 id（**即便音频经 UnblockNeteaseMusic 从别的平台解锁，id 永远是网易云 id**，取词永远对得上）。
- `name` / `ar[].name`(歌手) / `al.{name,picUrl}` / `picUrl`
- `dt`：时长**毫秒**
- `primaryColor`：封面主色 `"rgb(r,g,b)"`（直接做频谱/高亮配色）
- `backgroundColor`：`"linear-gradient(...)"`（展开态背景）
- `createdAt` / `expiredAt`：音频 URL 创建/过期时间戳（epoch ms）；`createdAt ≈ 播放起点`，`expiredAt = createdAt + 1800s`，**单曲内不刷新**。
- **`lyric`：已解析好的逐字歌词对象**（重大简化，歌词不必再调 30488）：

```jsonc
lyric = {
  hasWordByWord: bool,
  lrcTimeArray: [秒, ...],          // 每行起始时间，与 lrcArray 平行
  lrcArray: [{
    text, trText,                   // 原文 + 翻译
    startTime, duration,            // ms
    hasWordByWord,
    words: [{ text, startTime, duration, space }, ...]   // 逐字，含 ms 时间
  }, ...]
}
```

## 播放进度：CDP 主 + 插值兜底

`/api/status` **不直接给 position**，需要两条路：

1. **CDP 读 Howler（首选，真实位置）**：AlgerMusic 带 `--remote-debugging-port=9222 --remote-allow-origins='*'` 启动后（NotchLyrics 会代启），经 `GET /json/list` 取 `type==='page'` target 的 `webSocketDebuggerUrl`，WS 连上 `Runtime.evaluate` 读 `window.Howler._howls` 里 `playing()===true` 实例的 `seek()`。seek/快退/暂停**即时反映、零延迟**。每次采样短连重连最稳。
2. **createdAt 插值（兜底）**：CDP 不可用时 `position ≈ now - createdAt - 累计暂停墙钟`。正常听够用；**纯插值下手动 seek 会错**（createdAt/LS progress 都感知不到 seek）——这正是要 CDP 的原因。

> 播放器是 **Howler.js**，不是 `<audio>` 元素；多 `_howls` 实例（预加载下一首）用 `playing()===true` 选当前那个；暂停态 seek 按 `duration()≈dt` 匹配实例。

## 代理 / TUN 兼容

用户常开 Clash + 系统代理 + TUN。实测 `URLSession` 直打 `127.0.0.1` 本地口正常（系统代理 ExceptionsList 默认含 127.0.0.1；TUN 不接管 `lo0`；字面 IP 不查 DNS）。代码层双保险：

1. 独立 `URLSession` 且 `configuration.connectionProxyDictionary = [:]` 显式关代理；
2. 一律用字面 `127.0.0.1`，不用 `localhost`。

## 法务边界

不 fork、不改 AlgerMusic 源码，只调它在 localhost 暴露的 HTTP 接口 + 自带网易云 API → 许可证耦合极小，属正常互操作。
