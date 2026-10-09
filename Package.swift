// swift-tools-version: 5.9
import PackageDescription

// ZixiaoKit — 子晓纪产品矩阵的共享 Swift 内核 (L1)。
// 消费者: 玄览 (qizen/apple), 后续东坡志 / 诗人志系列 (PoetKit 依赖本包)。
// 数据与服务支持原生 macOS 15; ZixiaoPoet / ZixiaoLibrary 的现有 UI 仍面向 iOS / Catalyst。
let package = Package(
    name: "ZixiaoKit",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17), .macCatalyst(.v17), .macOS("15.0")],
    products: [
        .library(name: "ZixiaoCore", targets: ["ZixiaoCore"]),
        .library(name: "ZixiaoDesign", targets: ["ZixiaoDesign"]),
        .library(name: "ZixiaoCalendar", targets: ["ZixiaoCalendar"]),
        .library(name: "ZixiaoLibrary", targets: ["ZixiaoLibrary"]),
        .library(name: "ZixiaoLibraryCore", targets: ["ZixiaoLibraryCore"]),
        .library(name: "ZixiaoArt", targets: ["ZixiaoArt"]),
        .library(name: "SwiftPieces", targets: ["SwiftPieces"]),
        .library(name: "ZixiaoPoet", targets: ["ZixiaoPoet"]),
        .library(name: "ZixiaoPoetCore", targets: ["ZixiaoPoetCore"]),
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
        // 色值与混色纯计算; Design 与 Art 共用同一份类型, 渲染器不引入 UIKit 组件。
        .target(name: "ZixiaoColor", dependencies: [],
                swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
        // 设计系统: token 分组 (color / type / space / radius / motion)、身份、字体、修饰符、文化组件与屏幕件。
        .target(
            name: "ZixiaoDesign",
            dependencies: ["ZixiaoColor"],
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
        // 无 UI 的书库: book.json、目录、随包/云端加载 (sha256)、阅读状态。
        .target(
            name: "ZixiaoLibraryCore",
            dependencies: [],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // iOS 阅读器; re-export Core, 既有客户端继续 import ZixiaoLibrary。
        .target(
            name: "ZixiaoLibrary",
            dependencies: ["ZixiaoDesign", "ZixiaoLibraryCore"],
            resources: [.process("Resources")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // 程序化国画 (画屏背景): 山水 (shan-shui-inf) 与花卉 (nonflowers) 的 Swift 移植 (MIT, 许可全文在
        // ZXArtLicenses.swift, 以 ZXArt.acknowledgements 暴露)。只依赖 ZixiaoColor 的色值 (ZXHex);
        // 纯 CoreGraphics 渲染, 可在小组件扩展 / 后台线程里调用。
        .target(
            name: "ZixiaoArt",
            dependencies: ["ZixiaoColor"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // 诗人领域内核: 编成、资源、只读数据、用户同步与阅读推导; 不依赖 SwiftUI/UIKit。
        .target(
            name: "ZixiaoPoetCore",
            dependencies: ["ZixiaoCore", "ZixiaoCalendar",
                           .product(name: "Supabase", package: "supabase-swift")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // 诗人 iOS UI (原 PoetKit); re-export Core 保持既有导入兼容。
        // 不含任何诗人的资源 —— 编成 / 导读 / 书画随各产品 App 包发, 经 PoetComposition.load(from:) / PoetResources 注入。
        // 直接依赖 Supabase: PoetStore 的只读查询用 ZXSupabase.client (同一份 session)。
        .target(
            name: "ZixiaoPoet",
            dependencies: [
                "ZixiaoPoetCore", "ZixiaoCore", "ZixiaoDesign", "ZixiaoCalendar", "ZixiaoLibrary", "ZixiaoArt", "SwiftPieces",
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(name: "ZixiaoCoreTests", dependencies: ["ZixiaoCore"]),
        .testTarget(name: "ZixiaoDesignTests", dependencies: ["ZixiaoDesign"]),
        // 金标 fixture 在仓库根 Fixtures/, 测试用 #filePath 定位读取 (SPM 不允许 target 外的 resources)。
        .testTarget(name: "ZixiaoCalendarTests", dependencies: ["ZixiaoCalendar"]),
        .testTarget(name: "ZixiaoLibraryCoreTests", dependencies: ["ZixiaoLibraryCore"]),
        .testTarget(name: "ZixiaoLibraryTests", dependencies: ["ZixiaoLibrary", "ZixiaoLibraryCore"], resources: [.process("Resources")]),
        // 对拍金标 (原作 JS 跑出, Tools/zxart-fixtures/generate.cjs) 随测试包拷贝, 用 Bundle.module 读取。
        .testTarget(name: "ZixiaoArtTests", dependencies: ["ZixiaoArt"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ZixiaoPoetCoreTests", dependencies: ["ZixiaoPoetCore", "ZixiaoCore"]),
        .testTarget(name: "ZixiaoPoetTests", dependencies: ["ZixiaoPoet", "ZixiaoPoetCore", "ZixiaoCore", "ZixiaoDesign", "ZixiaoCalendar"]),
    ]
)
