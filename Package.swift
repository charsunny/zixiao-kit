// swift-tools-version: 5.9
import PackageDescription

// ZixiaoKit — 子晓纪产品矩阵的共享 Swift 内核 (L1)。
// 消费者: 玄览 (qizen/apple), 后续东坡志 / 诗人志系列 (PoetKit 依赖本包)。
// 纯 iOS 包 (iOS 17 / macCatalyst 17)。验证用 iOS Simulator 目标, 见 README。
let package = Package(
    name: "ZixiaoKit",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17), .macCatalyst(.v17)],
    products: [
        .library(name: "ZixiaoCore", targets: ["ZixiaoCore"]),
        .library(name: "ZixiaoDesign", targets: ["ZixiaoDesign"]),
        .library(name: "ZixiaoCalendar", targets: ["ZixiaoCalendar"]),
        .library(name: "ZixiaoLibrary", targets: ["ZixiaoLibrary"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
        .package(url: "https://github.com/6tail/lunar-swift.git", from: "1.1.8"),
    ],
    targets: [
        // 账号 / 用户数据 / 离线队列 / Supabase 配置。Sprint 1 只放骨架。
        .target(
            name: "ZixiaoCore",
            dependencies: [.product(name: "Supabase", package: "supabase-swift")],
            resources: [.process("Resources")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // 设计 token / 身份 / 字体 / 文化组件 (印章、竖排、线装封面、釉面面板)。
        .target(
            name: "ZixiaoDesign",
            dependencies: [],
            resources: [.process("Resources")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // 岁时: 农历、干支、节气、七十二候、花信、时辰更点、年号纪年、节日。
        .target(
            name: "ZixiaoCalendar",
            dependencies: [.product(name: "LunarSwift", package: "lunar-swift")],
            resources: [.process("Resources")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // 书库: book.json schema、目录、随包/云端加载 (sha256)、阅读状态、线装书阅读器。
        .target(
            name: "ZixiaoLibrary",
            dependencies: ["ZixiaoDesign"],
            resources: [.process("Resources")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(name: "ZixiaoCoreTests", dependencies: ["ZixiaoCore"]),
        .testTarget(name: "ZixiaoDesignTests", dependencies: ["ZixiaoDesign"]),
        // 金标 fixture 在仓库根 Fixtures/, 测试用 #filePath 定位读取 (SPM 不允许 target 外的 resources)。
        .testTarget(name: "ZixiaoCalendarTests", dependencies: ["ZixiaoCalendar"]),
        .testTarget(name: "ZixiaoLibraryTests", dependencies: ["ZixiaoLibrary"], resources: [.process("Resources")]),
    ]
)
