ZixiaoDesign 的随包资源。

- `identities/`: 身份 JSON (颜色、字族、插槽)。内核不写死任何颜色, 全部从这里来。
- `Fonts/`: 思源宋体 SC Regular / Bold (SIL OFL) 与秋鸿楷子集 (免费商用), 复制自 `qizen/app/assets/fonts/`。
  SPM 资源进不了 App 的 `UIAppFonts`, 由 `ZXFonts.registerAll()` 在运行时用 CoreText 注册。

传统色身份：`moon-white` 月白、`xiang-leaf` 缃叶、`canglang` 苍筤、`ouhe` 藕荷、
`dai-blue` 黛蓝、`rouge` 胭脂。色值来自本仓库设计方案，派生值已写死，不引入第三方色库。
`rationale` 保存微诗诗库原句、作者、篇名和核对限制；藕荷、黛蓝暂保留方案名，建议换名后发布。
`palette.highContrastLight` / `highContrastDark` 可选，缺席时沿用普通色板。
