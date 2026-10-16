ZixiaoDesign 的随包资源。

- `identities/`: 身份 JSON (颜色、字族、插槽)。内核不写死任何颜色, 全部从这里来。
- `Fonts/`: 思源宋体 SC Regular / Bold (SIL OFL) 与秋鸿楷子集 (免费商用), 复制自 `qizen/app/assets/fonts/`。
  SPM 资源进不了 App 的 `UIAppFonts`, 由 `ZXFonts.registerAll()` 在运行时用 CoreText 注册。

第四稿传统色身份：`yaqing` 鸦青、`moon-white` 月白、`xiang-leaf` 缃叶、`canglang` 苍筤、`ousi` 藕丝、
`qingdai` 青黛、`rouge` 胭脂。色值来自本仓库设计方案，派生值已写死，不引入第三方色库。
`rationale` 保存微诗诗库原句、作者、篇名与诗的 ID；藕丝取李贺《天上谣》“粉霞红绶藕丝裙”，
青黛取雍陶《题君山》“一螺青黛镜中心”。色值全部按第四稿第 2 节替换，未引入第三方色库。
`palette.highContrastLight` / `highContrastDark` 可选，缺席时沿用普通色板。

鸦青取张矩《虞美人》“粉褪香腮零乱、鬓鸦青”，诗 ID `4a0d028f-eb81-5af6-b2a5-8af79cc3ff83`。
色板取自微诗图标：#121E21、#AEC5C0 / #72968F、#F2F2E8。旧两套身份文件保留且参与对比度测试。
