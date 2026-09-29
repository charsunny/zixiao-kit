// ZixiaoDesign — 设计 token、身份 JSON、字体注册与文化组件。见仓库 README 的模块契约。
//
// 入口: `ZXIdentity` (身份) → `ZXTheme` (按外观解析, 经 `\.zxTheme` 下发) →
// 组件 (`SealView` `VerticalText` `BookCoverView` `GlazePanel` `SectionLabel` `InkDivider` `EmptyState`)。
// token 分组: `theme.color` / `type` / `space` / `radius` / `motion`; 修饰符 `zxSurface` `zxShadow` `zxGlass`
// 与 `ZXHairline`。屏幕件 (Components/Screens): `ZXTabShell` `ZXFloatingPill` `ZXCodeEntry`
// `ZXGhostState` `ZXBentoGrid`。视图只读 `\.zxTheme`, 不读 colorScheme 选色, 不写死色值与字号。
// 字体: App 启动时调 `ZXFonts.registerAll()`; 忘了也不要紧, `ZXFont` 取字前会自己注册。
public enum ZixiaoDesignModule: Sendable { public static let name = "ZixiaoDesign" }
