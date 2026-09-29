# ZixiaoKit

子晓纪产品矩阵的共享 Swift 内核 (L1)。消费者: 玄览 (`../qizen/apple`), 后续东坡志 / 诗人志系列 (`../zhi/DongpoZhi/Packages/PoetKit` 将依赖本包)。

规划: `../.claude/plans/product-matrix-2026.md` 第 4 章; 当前冲刺: `../.claude/plans/xuanlan-swift-sprint-01.md`。

## 模块

| 模块 | 职责 | 依赖 |
|---|---|---|
| ZixiaoCore | Supabase 配置、账号 (匿名优先 → 绑定 Apple / 手机号)、用户数据 (app_slug 隔离)、离线队列 | supabase-swift |
| ZixiaoDesign | 设计 token、身份 (Identity) JSON、字体注册、文化组件 (印章、竖排、线装封面、釉面面板、分节标题) | 无 |
| ZixiaoCalendar | 农历、干支、节气、七十二候、花信、时辰更点、年号纪年、节日 | lunar-swift |
| ZixiaoLibrary | book.json 模型、目录、随包 / 云端书库 (sha256)、阅读状态、线装书阅读器 | ZixiaoDesign |

## 规则

- 内核里不出现任何产品专属逻辑 (不写「玄览」「苏轼」)。产品差异靠 Identity JSON 与资源注入。
- 所有 public 模型与服务类型标 `Sendable`, 开 StrictConcurrency。SwiftUI View 本身不要求 Sendable, 但它交出去的数据必须是。
- 每个模块有测试; 历法类必须对齐 `Fixtures/` 里的金标。
- 不改 `Package.swift` 的 target 结构; 需要加依赖或资源, 在 PR 说明里提出。

## 验证

```sh
# 编译 (iOS Simulator)
xcodebuild -scheme ZixiaoKit-Package -destination 'generic/platform=iOS Simulator' build
# 测试
xcodebuild -scheme ZixiaoKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```
