# 共用组件与风格契约

本文件维护跨 App 可复用的设计能力，不定义某个产品的页面布局。公共平台基线见 [APPLE_COMMON.md](APPLE_COMMON.md)。

| 层 | 现有实现 | 责任 |
| --- | --- | --- |
| 身份 | `ZXIdentity`、`Resources/identities` | 身份数据驱动字体与色彩；产品名、印文、诗人身份由 App 注入 |
| 主题 | `ZXTheme`、`ZXColorTokens`、`ZXTypeTokens`、`ZXSpaceTokens`、`ZXMotionTokens` | 语义 token、浅深色、字号层次、间距、减少动态效果 |
| 表面 | `ZXSurface`、`ZXGlass` | 内容表面与操作材质；系统导航优先原生组件，不把全部卡片玻璃化 |
| 内容组件 | `BookCoverView`、`SealView`、`VerticalText`、`EmptyState` | 书封、印章、竖排、状态呈现；不内置产品路由与服务 |
| 平台组合 | `ZXTabShell`、导航标题、浮动工具条等 | 按 target/API 可用性使用；不能假定所有 UIKit 组件在 macOS 可编译 |

源码位于 `Sources/ZixiaoDesign/`。这些名称描述现有实现，不代表所有 App 已完成统一接入。Mac 采用原生 AppKit / SwiftUI 交互，可共享 token 语义和内容模型，不为复用 iOS 壳引入 UIKit。

## 组件进入共享库的条件

至少两个真实使用场景，或已有明确跨产品契约；输入是内容、状态和回调，不依赖具体 App 的单例、路由或后端。先保留既有公开接口，再增加可选能力。字体许可、缺字回退和可访问性标签随组件维护。

App 定义身份组合、页面布局和文案；共用库定义 token 语义和组件行为。不得把某个 App 的固定颜色、诗人名或品牌图标硬编码到通用组件。已有 App 的局部 DesignSystem 可逐步适配，本次不强制替换运行时代码。

## 变更与验收

公共组件改动列出受影响消费者，按平台串行构建；交互变化补真实窗口、辅助设置和状态验收。产品例外写明原因、平台和证据。共用能力变更更新本文件，产品需求变更只改对应 App 文档，避免复制整套公共规范。

传统色配色目录由 `ZXPaletteCatalog` 提供，`ZXPalettePicker` 用色样卡片选色并转交上锁点击。
`ZXIdentity.applyingPalette` 只替换配色，保留产品字族与插槽。配色按五行季节映射后，不叠加季节偏色。
`ZXPalettePicker` 接受可选 `localize` 文本转换回调（默认原样返回），用于产品的繁简转换；同时转换卡片标签、意象、季节名称和无障碍描述。共享库不读取产品语言单例。
