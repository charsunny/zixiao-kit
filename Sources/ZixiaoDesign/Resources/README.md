ZixiaoDesign 的随包资源。

- `identities/`: 身份 JSON (颜色、字族、插槽)。内核不写死任何颜色, 全部从这里来。
- `Fonts/`: 思源宋体 SC Regular / Bold (SIL OFL) 与秋鸿楷子集 (免费商用), 复制自 `qizen/app/assets/fonts/`。
  SPM 资源进不了 App 的 `UIAppFonts`, 由 `ZXFonts.registerAll()` 在运行时用 CoreText 注册。
