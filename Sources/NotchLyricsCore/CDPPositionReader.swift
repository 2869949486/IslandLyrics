import Foundation

public struct CDPSample: Equatable {
    public let seekMs: Int
    public let durationMs: Int
    public let instances: Int
    public init(seekMs: Int, durationMs: Int, instances: Int) {
        self.seekMs = seekMs; self.durationMs = durationMs; self.instances = instances
    }
}

/// 通过 Chrome DevTools Protocol 读 AlgerMusic 渲染进程里的 Howler 真实播放位置。
/// 每次采样短连重连（connect→evaluate→close）最稳，对应 findings 的实测结论。
public final class CDPPositionReader: @unchecked Sendable {
    public let port: Int
    private let session: URLSession

    /// 取当前正在播放的 Howl 实例的 seek()/duration()。多实例(预加载)时选 playing()===true。
    static let howlerExpr = """
    (()=>{const hs=(window.Howler&&window.Howler._howls)||[];\
    const h=hs.find(x=>{try{return x.playing&&x.playing()}catch(e){return false}});\
    return h?JSON.stringify({seek:h.seek(),duration:h.duration(),n:hs.length}):JSON.stringify({playing:false,n:hs.length});})()
    """

    public init(port: Int = 9222) {
        self.port = port
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        cfg.timeoutIntervalForRequest = 3
        self.session = URLSession(configuration: cfg)
    }

    /// 9222 是否可达（AlgerMusic 是否带调试参数启动）。
    public func available() async -> Bool { await pageWebSocketURL() != nil }

    /// /json/list 里 type=='page' 的 webSocketDebuggerUrl。
    private func pageWebSocketURL() async -> URL? {
        let url = URL(string: "http://127.0.0.1:\(port)/json/list")!
        guard let (data, _) = try? await session.data(from: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        // 只认 type=='page' 的渲染进程靶；不回退 arr.first（那可能是 worker/iframe 靶，Howler 不在其上）。
        let page = arr.first { ($0["type"] as? String) == "page" }
        guard let ws = page?["webSocketDebuggerUrl"] as? String else { return nil }
        return URL(string: ws)
    }

    /// 读一次位置。失败/暂停(无 playing 实例)→ nil。整个 body(含 /json/list 取靶)纳入 timeout 预算。
    public func readPosition(timeout: Double = 2.0) async -> CDPSample? {
        return await withTimeout(timeout) { [weak self] () -> CDPSample? in
            guard let self, let wsURL = await self.pageWebSocketURL() else { return nil }
            guard let value = await self.evaluateRaw(wsURL: wsURL, expression: Self.howlerExpr),
                  let vdata = value.data(using: .utf8),
                  let v = try? JSONSerialization.jsonObject(with: vdata) as? [String: Any],
                  let seek = v["seek"] as? Double else { return nil }  // playing:false 时无 seek
            let dur = (v["duration"] as? Double) ?? 0
            // isFinite + 范围守卫：NaN/Inf/超范围 Double 直转 Int 会 trap 崩溃（比照 FlexibleID）。
            guard seek.isFinite, abs(seek) < Double(Int.max) / 1000 else { return nil }
            let durMs = (dur.isFinite && abs(dur) < Double(Int.max) / 1000) ? Int(dur * 1000) : 0
            let n = (v["n"] as? Int) ?? 0
            return CDPSample(seekMs: Int(seek * 1000), durationMs: durMs, instances: n)
        }
    }

    /// 设置播放位置：CDP 调当前 playing 的 Howl 实例 `seek(sec)`。远控 API 无 seek，故走 CDP。
    /// 暂停时没有 playing 实例 → 按 `duration()≈durationSec` 匹配当前曲实例（避免误中预载的下一首）；
    /// 匹配不到（无 durationSec 或差距过大）就不 seek。返回是否真的对某实例下了 seek（供调用方在失败时撤销乐观重锚）。
    @discardableResult
    public func seek(toSeconds sec: Double, durationSec: Double = 0, timeout: Double = 2.0) async -> Bool {
        let expr = "(()=>{const hs=(window.Howler&&window.Howler._howls)||[];" +
            "let h=hs.find(x=>{try{return x.playing&&x.playing()}catch(e){return false}});" +
            "if(!h){const D=\(durationSec);let best=null,bd=1e9;" +
            "for(const x of hs){try{const d=x.duration();const diff=Math.abs(d-D);if(d>0&&diff<bd){bd=diff;best=x;}}catch(e){}}" +
            "if(best&&D>0&&bd<2)h=best;}" +
            "if(h){try{h.seek(\(sec));return 'ok'}catch(e){return 'err'}}return 'noinst';})()"
        // 整个 body 纳入 timeout 预算（含 /json/list 取靶）。
        let value = await withTimeout(timeout) { [weak self] () -> String? in
            guard let self, let wsURL = await self.pageWebSocketURL() else { return nil }
            return await self.evaluateRaw(wsURL: wsURL, expression: expr)
        }
        return value == "ok"
    }

    /// 连接 WS、Runtime.evaluate(expression, returnByValue)，返回结果 value 字符串。
    private func evaluateRaw(wsURL: URL, expression: String) async -> String? {
        let task = session.webSocketTask(with: wsURL)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        // withTimeout 的取消只有在 receive() 能被打断时才有效。把 send+receive 包进取消处理器：
        // 上层超时 → onCancel 主动关 WS → 卡住的 receive() 立即抛错返回，超时才能准时生效。
        return await withTaskCancellationHandler {
            let msg: [String: Any] = [
                "id": 1,
                "method": "Runtime.evaluate",
                "params": ["expression": expression, "returnByValue": true],
            ]
            guard let body = try? JSONSerialization.data(withJSONObject: msg),
                  let text = String(data: body, encoding: .utf8) else { return nil }
            do { try await task.send(.string(text)) } catch { return nil }

            for _ in 0..<5 {
                guard let frame = try? await task.receive() else { return nil }
                guard case let .string(s) = frame, let data = s.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                guard (obj["id"] as? Int) == 1 else { continue }
                guard let result = obj["result"] as? [String: Any],
                      let inner = result["result"] as? [String: Any] else { return nil }
                return inner["value"] as? String
            }
            return nil
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }
    }
}

/// 给异步操作加超时（CDP 长连偶发卡住时不挂死）。
func withTimeout<T>(_ seconds: Double, _ operation: @escaping () async -> T?) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
