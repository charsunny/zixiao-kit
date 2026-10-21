# ZixiaoKit (子晓套件)

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%2B%20%7C%20macOS%2015%2B-blue.svg)](Package.swift)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**ZixiaoKit** 是子晓古典文化与诗词产品矩阵（微诗 Wish、玄览、东坡志 / 诗人志系列）的开源共享 Swift 内核（L1）。涵盖**程序化中国水墨山水与写意花鸟 (`ZixiaoArt`)**、**中国传统色与东方设计系统 (`ZixiaoDesign`)**、**农历节气七十二候历法 (`ZixiaoCalendar`)**、**线装书古籍阅读器 (`ZixiaoLibrary`)** 以及 **诗人编年与多编成书房框架 (`ZixiaoPoet`)**。

---

## 核心模块

| 模块 | 职责 | 依赖 |
| :--- | :--- | :--- |
| **`ZixiaoArt`** | 程序化中国水墨画引擎：山水长卷（`shan-shui-inf` 移植与三代笔法演进）与写意花卉（`nonflowers` 移植），支持 `background.procedural` 配方解码、CoreGraphics 与 SwiftUI Canvas 双后端渲染；`shanshui@1/@2/@3` 的 `Drawing.anchors` 输出山脊、水体、孤舟、行客、林木、屋舍、天际带等语义锚点，供动态画屏与视频工作台驱动自然动效 | `ZixiaoColor` |
| **`ZixiaoDesign`** | 东方美学设计 Token、产品身份（Identity）JSON、传统色配色目录（鸦青、月白、缃叶、苍筤、藕丝、青黛、胭脂）、字体注册与文化组件（朱文/白文印章、竖排排版、线装封面、釉面面板、分节标题） | `ZixiaoColor` |
| **`ZixiaoCalendar`** | 农历、干支、二十四节气、七十二候、二十四番花信风、时辰更点、历史年号纪年与传统节日计算 | `lunar-swift` |
| **`ZixiaoLibraryCore`** | `book.json` 古籍模型、目录索引、随包/云端书库（`sha256` 校验）与本地阅读状态；纯数据层无 UI | 无 |
| **`ZixiaoLibrary`** | iOS / macOS Catalyst 线装书阅读器视图组件；公开 re-export `ZixiaoLibraryCore` | `ZixiaoLibraryCore`, `ZixiaoDesign` |
| **`ZixiaoPoetCore`** | 诗人编成与资源加载、只读文库（`PoetStore`）、用户同步（`PoetUserData`）、多编成共享会话（`PoetSession`）与阅读推导；纯数据层无 UI | `ZixiaoCore`, `ZixiaoCalendar`, `supabase-swift` |
| **`ZixiaoPoet`** | iOS / Catalyst 启动层与能力视图（今日、生平长卷、文集、行迹、检索）；内核零硬编码诗人名（由 `Tools/lint-no-poet-names.sh` 守护） | `ZixiaoPoetCore`, `ZixiaoDesign`, `ZixiaoLibrary`, `ZixiaoArt`, `SwiftPieces` |
| **`ZixiaoCore`** | 离线优先的 Supabase 客户端配置、匿名优先账号体系（支持绑定 Apple / 手机号）、按 `app_slug` 隔离的用户数据同步与幂等离线队列（`ZXOutbox`） | `supabase-swift` |

- `ZixiaoCore`、`ZixiaoCalendar`、`ZixiaoArt`、`ZixiaoLibraryCore`、`ZixiaoPoetCore` 原生支持 **macOS 15+** 与 **iOS 17+**。
- `ZixiaoColor` 是 `ZixiaoDesign` 与 `ZixiaoArt` 共用的轻量纯色值模块，`ZXHex` 经两个模块公开导出。

---

## 快速接入 (Swift Package Manager)

在 `Package.swift` 或 Xcode 的 Package Dependencies 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/charsunny/zixiao-kit.git", branch: "master")
]
```

按需引入目标模块（例如仅使用程序化水墨山水与传统色）：

```swift
import SwiftUI
import ZixiaoArt
import ZixiaoDesign

// 使用种子确定性生成水墨山水与语义锚点
let recipe = ZXArtProcedural(generator: "shanshui@2", seed: "hanlu-dufu", variant: "远山")
```

---

## 架构与工程原则

1. **零产品耦合**：内核中不出现具体产品或单一诗人硬编码，所有产品差异通过 Identity JSON 与资源包注入。
2. **Swift 6 Strict Concurrency**：所有 `public` 模型与服务类型均标注 `Sendable`，开启严格并发检查。
3. **金标基准测试**：历法计算与程序化山水构图均配备 `Fixtures/` 金标回归测试。
4. **传统色与五行四时**：详见 [传统色配色方案](Docs/Design/THEME_PALETTES.md) 与 [Apple 共用组件规范](Docs/Design/README.md)。

---

## 构建与测试

```sh
# 编译 (iOS Simulator)
xcodebuild -scheme ZixiaoKit-Package -destination 'generic/platform=iOS Simulator' build

# 运行全套单元测试与金标回归
xcodebuild -scheme ZixiaoKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

---

## 致谢与开源许可 (License)

本项目基于 [MIT License](LICENSE) 开源。

其中 `ZixiaoArt` 模块的底层山水与花卉几何生成算法移植并演进自 Lingdong Huang 的开源作品，保留完整 MIT 版权声明（详见 [`LICENSES/`](LICENSES/README.md) 及代码内 `ZXArt.acknowledgements`）：
- [`shan-shui-inf`](https://github.com/LingDong-/shan-shui-inf) (Copyright (c) 2018 Lingdong Huang, MIT License)
- [`nonflowers`](https://github.com/LingDong-/nonflowers) (Copyright (c) 2018 Lingdong Huang, MIT License)
