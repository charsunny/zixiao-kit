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
        .library(name: "ZixiaoArt", targets: ["ZixiaoArt"]),
        .library(name: "SwiftPieces", targets: ["SwiftPieces"]),
        .library(name: "ZixiaoPoet", targets: ["ZixiaoPoet"]),
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
        // Swift Pieces (swiftpieces.com) 的免费件 (MIT + Commons Clause), 由 `npx swiftpieces add` 写入,
        // 配置在仓库根 swiftpieces.json。规则: 不手改这里的文件 (升级会被 --overwrite 覆盖)。
        // 没有 Pro: 设计系统与屏幕件按同样契约在 ZixiaoDesign 里自己实现。
        .target(
            name: "SwiftPieces",
            dependencies: [],
            path: "Sources/SwiftPieces",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // 设计系统: token 分组 (color / type / space / radius / motion)、身份、字体、修饰符、文化组件与屏幕件。
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
        // 程序化国画 (画屏背景): 山水 (shan-shui-inf) 与花卉 (nonflowers) 的 Swift 移植 (MIT, 许可全文在
        // ZXArtLicenses.swift, 以 ZXArt.acknowledgements 暴露)。只依赖 ZixiaoDesign 的色值 (ZXHex);
        // 纯 CoreGraphics 渲染, 可在小组件扩展 / 后台线程里调用。
        .target(
            name: "ZixiaoArt",
            dependencies: ["ZixiaoDesign"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // 诗人志内核 (原 PoetKit, 2026-10-01 charsunny 决定并入): 编成、只读数据、用户数据同步、启动层与能力视图。
        // 不含任何诗人的资源 —— 编成 / 导读 / 书画随各产品 App 包发, 经 PoetComposition.load(from:) / PoetResources 注入。
        // 直接依赖 Supabase: PoetStore 的只读查询用 ZXSupabase.client (同一份 session)。
        .target(
            name: "ZixiaoPoet",
            dependencies: [
                "ZixiaoCore", "ZixiaoDesign", "ZixiaoCalendar", "ZixiaoLibrary", "SwiftPieces",
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(name: "ZixiaoCoreTests", dependencies: ["ZixiaoCore"]),
        .testTarget(name: "ZixiaoDesignTests", dependencies: ["ZixiaoDesign"]),
        // 金标 fixture 在仓库根 Fixtures/, 测试用 #filePath 定位读取 (SPM 不允许 target 外的 resources)。
        .testTarget(name: "ZixiaoCalendarTests", dependencies: ["ZixiaoCalendar"]),
        .testTarget(name: "ZixiaoLibraryTests", dependencies: ["ZixiaoLibrary"], resources: [.process("Resources")]),
        // 对拍金标 (原作 JS 跑出, Tools/zxart-fixtures/generate.cjs) 随测试包拷贝, 用 Bundle.module 读取。
        .testTarget(name: "ZixiaoArtTests", dependencies: ["ZixiaoArt"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ZixiaoPoetTests", dependencies: ["ZixiaoPoet", "ZixiaoCore", "ZixiaoDesign", "ZixiaoCalendar"]),
    ]
)
