import Foundation

public struct AlgerPorts: Equatable {
    public let remoteControlPort: Int
    public let remoteControlEnabled: Bool
    public let musicApiPort: Int
    public init(remoteControlPort: Int, remoteControlEnabled: Bool, musicApiPort: Int) {
        self.remoteControlPort = remoteControlPort
        self.remoteControlEnabled = remoteControlEnabled
        self.musicApiPort = musicApiPort
    }
    public static let defaults = AlgerPorts(remoteControlPort: 31888, remoteControlEnabled: false, musicApiPort: 30488)
}

public enum PortDiscovery {
    public static let configPath = NSString(string:
        "~/Library/Application Support/AlgerMusicPlayer/config.json").expandingTildeInPath

    /// 从磁盘读 config.json；不存在/解析失败 → 全默认。
    public static func discover(path: String = configPath) -> AlgerPorts {
        guard let data = FileManager.default.contents(atPath: path) else { return .defaults }
        return parse(data)
    }

    /// 纯解析（便于单测）。实测 config.json 无 `musicApiPort` 键 → 回退默认 30488。
    public static func parse(_ data: Data) -> AlgerPorts {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .defaults
        }
        let rc = obj["remoteControl"] as? [String: Any]
        let rcPort = (rc?["port"] as? Int) ?? AlgerPorts.defaults.remoteControlPort
        let rcEnabled = (rc?["enabled"] as? Bool) ?? false
        let musicPort = (obj["musicApiPort"] as? Int) ?? AlgerPorts.defaults.musicApiPort
        return AlgerPorts(remoteControlPort: rcPort, remoteControlEnabled: rcEnabled, musicApiPort: musicPort)
    }
}
