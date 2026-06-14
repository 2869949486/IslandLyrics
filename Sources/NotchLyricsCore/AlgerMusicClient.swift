import Foundation

public enum ControlAction: String {
    case togglePlay = "toggle-play"
    case prev
    case next
    case volumeUp = "volume-up"
    case volumeDown = "volume-down"
    case toggleFavorite = "toggle-favorite"
}

/// 远程控制(31888) HTTP 客户端。双保险：独立 ephemeral session + 显式关代理 + 字面 127.0.0.1。
public final class AlgerMusicClient: @unchecked Sendable {
    public var remotePort: Int
    public var musicApiPort: Int
    private let session: URLSession

    public init(remotePort: Int = 31888, musicApiPort: Int = 30488) {
        self.remotePort = remotePort
        self.musicApiPort = musicApiPort
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]            // 显式关系统代理
        cfg.timeoutIntervalForRequest = 3
        cfg.timeoutIntervalForResource = 5
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    private func remoteURL(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(remotePort)\(path)")!
    }

    /// GET /api/status。连接失败（远控未开/未运行）→ nil（区分于"连上但无歌"）。
    public func status() async -> StatusResponse? {
        var req = URLRequest(url: remoteURL("/api/status"))
        req.httpMethod = "GET"
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return StatusResponse.decode(data)
    }

    /// 仅探测 31888 是否可达（用于待机状态机的 remoteReachable）。
    public func reachable() async -> Bool {
        var req = URLRequest(url: remoteURL("/api/status"))
        req.httpMethod = "GET"
        guard let (_, resp) = try? await session.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    /// POST /api/{action}
    @discardableResult
    public func control(_ action: ControlAction) async -> Bool {
        var req = URLRequest(url: remoteURL("/api/\(action.rawValue)"))
        req.httpMethod = "POST"
        guard let (_, resp) = try? await session.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - 歌词兜底（30488，仅当 currentSong.lyric 空/无逐字时用）
    /// id 百分号编码 + guard let 取代强解包：本地歌 id 可能含 URL 非法字符（`local://…`），`URL(string:)!` 会崩。
    private func lyricURL(path: String, id: String) -> URL? {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        return URL(string: "http://127.0.0.1:\(musicApiPort)\(path)?id=\(enc)")
    }
    public func rawLyricNew(id: String) async -> Data? {
        guard let url = lyricURL(path: "/lyric/new", id: id) else { return nil }
        return try? await session.data(from: url).0
    }
    public func rawLyric(id: String) async -> Data? {
        guard let url = lyricURL(path: "/lyric", id: id) else { return nil }
        return try? await session.data(from: url).0
    }
}
