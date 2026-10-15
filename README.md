# ZixiaoKit

子晓纪产品矩阵的共享 Swift 内核 (L1)。消费者: 玄览 (`../xuan/apple`), 东坡志 / 诗人志系列 (`../zhi/apple`, 三个 target 经 `ZixiaoPoet` 模块接入, 2026-10-01 起)。

规划: `../.claude/plans/product-matrix-2026.md` 第 4 章; 当前冲刺: `../.claude/plans/xuanlan-swift-sprint-01.md`。

## 模块

| 模块 | 职责 | 依赖 |
|---|---|---|
| ZixiaoCore | Supabase 配置、账号 (匿名优先 → 绑定 Apple / 手机号)、用户数据 (app_slug 隔离)、离线队列 | supabase-swift |
| ZixiaoDesign | 设计 token、身份 (Identity) JSON、字体注册、文化组件 (印章、竖排、线装封面、釉面面板、分节标题) | ZixiaoColor |
| ZixiaoCalendar | 农历、干支、节气、七十二候、花信、时辰更点、年号纪年、节日 | lunar-swift |
| ZixiaoLibraryCore | book.json 模型、目录、随包 / 云端书库 (sha256)、本地阅读状态；无 UI | 无 |
| ZixiaoLibrary | iOS / Catalyst 线装书阅读器；公开 re-export ZixiaoLibraryCore | ZixiaoLibraryCore, ZixiaoDesign |
| ZixiaoPoetCore | 编成与资源、只读数据 (PoetStore)、用户同步 (PoetUserData)、多编成共享会话 (PoetSession)、阅读推导；无 UI | ZixiaoCore, ZixiaoCalendar, supabase-swift |
| ZixiaoPoet | iOS / Catalyst 启动层与能力视图；公开 re-export ZixiaoPoetCore。诗人资源随各 App 包发，内核零诗人名 (`Tools/lint-no-poet-names.sh`) | ZixiaoPoetCore, ZixiaoDesign, ZixiaoLibrary, ZixiaoArt, SwiftPieces |
| ZixiaoArt | 程序化国画 (画屏背景): 山水 (shan-shui-inf 移植) 与花卉 (nonflowers 移植), 配方 `background.procedural` 的解码与渲染 (CoreGraphics 与 SwiftUI Canvas); shanshui@1 / @2 的 `Drawing.anchors` 记录山脊 / 水 / 船 / 人 / 树 / 屋 / 天空带的位置 (只记录, 不影响出图); MIT 致谢 `ZXArt.acknowledgements` | ZixiaoColor |

`ZixiaoCore`、`ZixiaoCalendar`、`ZixiaoArt`、`ZixiaoLibraryCore`、`ZixiaoPoetCore` 支持原生 macOS 15。
现有 iOS 客户端可继续导入 `ZixiaoLibrary` / `ZixiaoPoet`，数据类型只在对应 Core 模块定义一份。
`ZixiaoColor` 是 Design 与 Art 共用的纯色值目标，`ZXHex` 经两个模块公开导出。

多编成客户端由应用持有一份 `PoetSession`，通过 `CompositionContext(..., session: session)` 注入各编成。
同一编成的多个窗口共享 `userData`；不同编成沿用各自原有 `appSlug`，导航状态和资源独立。
资源可用 `PoetResources(bundleURL:slug:productName:)` 从各自的平铺目录载入，画作缓存以完整资源 URL 分键。
本机验证用 `await session.start(localOnly: true)`；它不启动认证或上传。网络同步显式调用 `start()`。
`ZXAppleExchange.Configuration.platform` 默认取当前平台 (`ios` / `macos`)，Mac Apple 登录可传发起窗口：
`try await ZXAppleSignIn().request(presentationAnchor: window)`。

## 规则

- 内核里不出现任何产品专属逻辑 (不写「玄览」「苏轼」)。产品差异靠 Identity JSON 与资源注入。
- 所有 public 模型与服务类型标 `Sendable`, 开 StrictConcurrency。SwiftUI View 本身不要求 Sendable, 但它交出去的数据必须是。
- 每个模块有测试; 历法类必须对齐 `Fixtures/` 里的金标。
- 不擅自改 `Package.swift` 的 target 结构; 加模块 / 依赖 / 资源须先经 charsunny 同意并在 PR 说明里写明
  (ZixiaoArt 独立成模块已获批, 2026-09-30; ZixiaoPoet 并入已获批, charsunny 2026-10-01；
  原生 macOS 数据层拆分与共享色值目标已随统一书房实施获批, 2026-10-07)。
- 第三方移植代码 (目前只有 ZixiaoArt) 的许可全文随模块走 (`ZXArtLicenses.swift`), 仓库根 `LICENSES/` 列出处与上游 commit。

## 验证

```sh
# 编译 (iOS Simulator)
xcodebuild -scheme ZixiaoKit-Package -destination 'generic/platform=iOS Simulator' build
# 测试
xcodebuild -scheme ZixiaoKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Apple 共用组件、风格及产品规范索引见 [设计规范](Docs/Design/README.md)。
