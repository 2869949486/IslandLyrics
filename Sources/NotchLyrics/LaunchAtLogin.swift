import Foundation
import ServiceManagement

/// 开机启动（macOS 13+ SMAppService）。ad-hoc 签名/非 /Applications 的 app 可能注册受限，
/// 失败不抛错，仅以 isEnabled 反映真实状态。
enum LaunchAtLogin {
    /// .requiresApproval（ad-hoc 签名/非 /Applications 常见：已注册成功、待用户在系统设置→登录项批准）
    /// 也算「已请求」，否则 Toggle 注册成功后会因状态非 .enabled 静默弹回 off，误导用户。
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            let s = SMAppService.mainApp.status
            return s == .enabled || s == .requiresApproval
        }
        return false
    }

    /// 已注册但待用户在「系统设置→通用→登录项」批准（ad-hoc 签名常见）。UI 据此提示用户去批准。
    static var needsApproval: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .requiresApproval }
        return false
    }

    @discardableResult
    static func set(_ on: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            return false
        }
    }
}
