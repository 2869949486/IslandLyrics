import Foundation
import AppKit

public enum AlgerMusicApp {
    public static let bundleID = "com.alger.music"
    public static let appName = "AlgerMusicPlayer"

    /// AlgerMusic 是否在运行（按 bundle id）。
    public static var isRunning: Bool { runningApp != nil }

    public static var runningApp: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }

    /// 本机是否安装了 AlgerMusic（按 bundle id 找到 app 包）。未安装 → 引导用户去下载。
    public static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// AlgerMusic 官方仓库（开源版用户在此下载）。
    public static let downloadURL = URL(string: "https://github.com/algerkong/AlgerMusicPlayer/releases")!

    /// 带调试参数启动 AlgerMusic。若已在运行，须先 terminate 再启（见 relaunchWithDebugFlags）。
    public static func launchWithDebugFlags() {
        let args = ["--remote-debugging-port=9222", "--remote-allow-origins=*"]
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            ?? URL(fileURLWithPath: "/Applications/\(appName).app")
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.arguments = args
        cfg.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
    }

    /// 退出 AlgerMusic（"代启"前先关掉无调试参数的实例）。返回是否发出了退出请求。
    @discardableResult
    public static func terminate() -> Bool {
        guard let app = runningApp else { return false }
        return app.terminate()
    }

    /// 带调试参数（重）启动：在运行就先退出、等旧实例真正退出(最多~3s)再带参启动，避免 open 只激活旧实例而忽略参数。
    public static func relaunchWithDebugFlags() async {
        if runningApp != nil {
            terminate()
            for _ in 0..<30 {                 // 等旧实例退出，最多 3s
                if runningApp == nil { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        launchWithDebugFlags()
    }
}
