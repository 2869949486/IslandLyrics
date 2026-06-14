// swift-tools-version: 5.9
import PackageDescription

// 本机仅 Command Line Tools（无 Xcode）→ XCTest 不可用。
// 测试用独立可执行 runner（无 XCTest 依赖），`swift run NotchLyricsCoreTests` 跑。
let package = Package(
    name: "NotchLyrics",
    platforms: [.macOS(.v13)],
    targets: [
        // 纯逻辑 + 网络层（Foundation/AppKit，无 SwiftUI 视图），可测
        .target(name: "NotchLyricsCore", path: "Sources/NotchLyricsCore"),
        // AppKit/SwiftUI 入口 + 视图 + 窗口
        .executableTarget(
            name: "NotchLyrics",
            dependencies: ["NotchLyricsCore"],
            path: "Sources/NotchLyrics"
        ),
        // 无 XCTest 的断言式测试 runner
        .executableTarget(
            name: "NotchLyricsCoreTests",
            dependencies: ["NotchLyricsCore"],
            path: "Tests/NotchLyricsCoreTests"
        ),
    ]
)
