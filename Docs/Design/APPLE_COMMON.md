# Apple 共用设计基线

2026-10-11 从微诗规范提取。适用微诗、诗人志、玄览、子晓；官方资料核对沿用原记录 2026-09-14，本次是职责重组，未重新审计新版 HIG。数值中的手机阅读起点不直接套用到 macOS。

共用组件与风格契约见 [COMPONENTS.md](COMPONENTS.md)。产品信息架构、导航目的地、内容策略、品牌身份及例外由各 App 规范维护。产品规范可细化平台差异，不能无说明地取消可访问性、状态隔离或原生交互要求。

## 1. 规范的使用方式

- **官方依据**说明 Apple 的设计建议；**系列决策**是我们为诗词阅读选择的产品标准，两者分别标注。
- 平台交互、可访问性和自适应以本文为当前基线；产品分工、编辑主线与跨端品牌见 各 App 自己的设计规范。技术架构仍以 各 App 的技术规范 为准。
- 旧稿中的固定色值、仿系统控件示意与布局草图不能覆盖当前系统行为。遇到新系统差异，先查官方文档，再记录适用版本与实际验证结果。
- 每次界面交付附上：阅读任务、所用系统组件、窄宽窗口方案、无障碍变化、加载与失败状态、验证证据。小改动按影响范围验收，复用有效证据。
- 每次年度系统适配及公开版本发布前复核受影响的官方章节；记录日期。没有运行验证的项目明确写“待验证”。

## 2. 系列身份与原生体验

**官方依据：**品牌可通过内容、用语与可读的定制字体表达，同时保留熟悉的系统交互；避免让重复品牌展示妨碍任务。[Branding](https://developer.apple.com/design/human-interface-guidelines/branding)

**系列决策：**“遇见一篇 → 读原文 → 理解处境 → 继续读”是共同主线。原文优先，工具退居辅助层。

身份色从产品资源或编成读取。正文中的章法、留白、字体和编辑内容承担主要特色；导航栏、标签栏与系统控件使用系统形态。网站保留宽屏侧边栏、链接、浏览器历史等桌面交互，共享视觉语义；网页布局尺寸不直接作为原生点数规范。

## 3. 排版与阅读

**官方依据：**文字须清楚、层级明确，定制字体同样需要响应可访问性设置。HIG 的 iOS / iPadOS 表列出默认 17pt、最低 11pt；最低值不是长篇阅读的目标字号。[Typography](https://developer.apple.com/design/human-interface-guidelines/typography)

**系列决策：**

| 层次 | 字体与语义 | 布局约束 |
| --- | --- | --- |
| 导航、按钮、筛选、提示 | 系统语义样式，如 headline / body / footnote | 跟随系统字号与字重，避免散落固定字号 |
| 诗题、原文、编辑导读 | 随包的思源宋体 Source Han Serif CN；按标题 / 正文 / 注释分配缩放语义 | 诗题直接展示；额外装饰性引号不进入题名 |
| 原文 | 正常字号下以 20–24pt 为起点，按诗、词、长文实测 | 自然换行、可选择复制；长文限制阅读栏宽度 |
| 来源、年代、注释 | 正常字号下通常 13–17pt，内容重要性决定层次 | 核心说明能放大、换行，不能靠淡灰小字隐藏 |

上述数值是系列设计起点，不限制 Dynamic Type。用户字号偏好与系统缩放组合后仍要保有标题、正文、注释层级；不通过缩小字号抵消用户的放大设置。缺字时保持可读的系统回退，异体字说明保留。

SwiftUI 的 `Font.custom(_:size:)` **已默认随 body 缩放**，不能把没有 `relativeTo` 误报成完全不支持 Dynamic Type；`relativeTo` 用来指定正确的层级。UIKit 字体可用 `UIFontMetrics`。每条字体路径只安排一次系统缩放，避免重复放大。固定 `.system(size:)` 分支须单独核对。[custom(_:size:)](https://developer.apple.com/documentation/swiftui/font/custom(_:size:)), [custom(_:size:relativeTo:)](https://developer.apple.com/documentation/swiftui/font/custom(_:size:relativeto:))

正常字号下目录可用有限行数保持扫描效率；辅助大字号下，诗题、同题首句、章节标题及主要操作必须有足够空间。长诗不固定高度，不截断正文。正文栏宽度按字体和窗口校准，不把微诗现有 720pt 与 PoetKit 的 760pt 强行合并成一个数字。

## 4. 颜色、材质与动态效果

**官方依据：**采用适应环境的颜色，检查浅深色和增强对比度；状态不能只靠颜色传达。深色环境下的背景层次和内容对比需要分别检查。[Color](https://developer.apple.com/design/human-interface-guidelines/color), [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)

**系列决策：**系统操作层使用语义颜色。纸面主题可作用于阅读内容；系统外观默认跟随设备。身份色提供浅色、深色及必要的增强对比度处理，用实测后的显示颜色定稿，设计稿 HEX 不等于运行时结果。重要文字与信息图形以 4.5:1 为团队检查基线，小字与长篇正文争取 7:1；装饰线条另按用途判断。这是团队目标，不能冒称 Apple 对所有元素都要求同一比值。

**官方依据：**Liquid Glass 主要服务导航和控制层，标准材质可用于内容。系统组件自动获得对应外观；自定义使用应克制，避免玻璃层叠。[Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)

**系列决策：**诗文阅读面保持稳定。优先采用原生 TabView、toolbar、Menu、sheet；新增自定义玻璃只用于确有必要的浮动操作，并按系统版本提供回退。通常选 regular；clear 需有合适媒体背景和单独的可读性验证。减少透明度、增强对比度与系统可用的玻璃外观设置都进入验收。

**官方依据：**动画应说明状态和关系，并尊重 Reduce Motion。[Motion](https://developer.apple.com/design/human-interface-guidelines/motion)

**系列决策：**保留有助定位的导航过渡；减少动态效果开启时移除自定义缩放、视差、弹跳和循环装饰。阅读中不自动移动正文或持续吸引注意力。操作反馈不能只通过动画、声音或触觉表达。

## 5. 导航与窗口自适应

**官方依据：**布局根据实际可用空间调整；iPad 优先考虑标签栏，需要更深层内容组织时使用可适配侧边栏或分栏；调整窗口时保持任务上下文。[Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios), [Designing for iPadOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados)

**系列决策：**

- iPhone 紧凑宽度：系统标签栏承载主要目的地，每个目的地保持自己的阅读路径，详情用 NavigationStack。
- iPad 宽窗口：目录、章节、作品列表与阅读区可并列。先评估系统可适配标签栏；需要持续目录和选择上下文时采用 NavigationSplitView。侧边栏可收合，当前作品和阅读位置在调整宽度后保持。
- iPad 窄窗口：分栏自然折叠；返回目录、当前选中项、搜索条件仍可恢复。不能只凭“这是 iPad”固定三栏。
- 微诗 Mac Catalyst：保留桌面菜单、键盘焦点与窗口行为。平台能力判断与窗口布局判断分开；本轮未审计的 Mac 专项不能视为通过。
- 单一可用 pane 直接显示内容；分段选择器仅切换同一目的地下的相关视图。

**官方依据：**标签对应目的地，保持稳定和可理解；即使内容暂缺，也不应随时禁用或隐藏已有标签。[Tab Bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)

**系列决策：**每款 App 的主目的地由编成确定，通常 3–5 个，这是我们的信息架构选择。未实现的能力可在该产品编成中缺席；已经提供的标签不能因断网或空数据消失，须提供有意义的空态和恢复入口。模块可以根据真实数据隐藏，不能把“允许缺席”用于掩盖坏掉的主导航。

## 6. 搜索、操作与临时任务

| 组件 | 官方依据 | 系列执行规则 |
| --- | --- | --- |
| 搜索 | [Search Fields](https://developer.apple.com/design/human-interface-guidelines/search-fields) | 使用 searchable 和系统搜索角色；发现型搜索先呈现线索，直接检索入口才立即聚焦。保留查询、筛选与返回位置；区分初始态、搜索中、无结果、失败。搜索角色始终执行搜索。 |
| 按钮 | [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) | 文案明确动作和对象；常用触控命中区域按 44×44pt 实施，图标可以较小。在 label 内扩展有效区域并检查相邻命中边界，不能只加控件外层 frame。 |
| 菜单 | [Menus](https://developer.apple.com/design/human-interface-guidelines/menus) | 次要动作收进原生 Menu；同一动作位置、名称和符号一致。普通菜单中暂不可用项通常保留并变灰，避免位置漂移。 |
| 上下文菜单 | [Context Menus](https://developer.apple.com/design/human-interface-guidelines/context-menus) | 长按 / 右键提供快捷路径，隐藏当前不适用项；重要动作还须有可发现入口。避免深层嵌套。 |
| sheet | [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets) | 用于阅读设置、分享前配置等集中任务，避免连续叠多层。返回处理层级，关闭结束临时任务。延后保存的编辑用取消 / 保存；即时生效设置用关闭等明确语义，不暗示关闭会撤销。 |
| alert | [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) | 只在需要立刻理解或决策时使用。可恢复网络错误优先原位提示与重试；不可逆内容损失说明后果并提供安全退出。普通可撤销操作优先撤销反馈。 |

Apple 当前 Accessibility 表列出 iOS / iPadOS 默认控件尺寸 44×44pt、最低控件尺寸 28×28pt；Buttons 给出的通常命中区域规则是至少 44×44pt。系列常用操作采用至少 44×44pt，并检查间距；不据此缩小现有系统命中区域，也不把团队标准误写成所有 Apple 平台统一的官方绝对下限。[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

键盘和指针是完整输入方式：焦点可见、顺序合理，搜索支持适当快捷键，Esc 关闭可取消的临时界面，常见操作可从菜单到达。避免抢占系统快捷键；触控、键盘与指针共用动作逻辑。[Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)

多窗口按内容任务决定是否提供。若提供，同一首诗可独立阅读，各窗口保留自己的导航和临时状态；登录与共享收藏状态需要正确同步。调整尺寸、进入后台再返回不应丢失阅读位置。[Multitasking](https://developer.apple.com/design/human-interface-guidelines/multitasking), [Elevate the Design of Your iPad App](https://developer.apple.com/videos/play/wwdc2025/208/)

## 7. 可访问性是一条完整阅读路径

**官方依据：**VoiceOver 需要正确描述、阅读顺序、可理解的分组和及时的必要反馈；有意义的图像要描述，装饰内容不应干扰朗读。[VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)

**系列验收要求：**

1. 只用 VoiceOver 能完成“今日 → 原文 → 背景 → 下一篇 → 最近阅读”。诗题、作者、正文、注释和来源朗读顺序自然。
2. 章节与主要区块有 heading trait；标题转子能定位内容。按钮标签包含具体动作、作品或对象，收藏等状态可获知。
3. 字印、边框与纯装饰插图不重复朗读；地图、关系图有信息等价的列表入口。把图变成可点节点不等于已经完成无障碍。
4. 异步搜索结果、保存失败、登录状态等重要变化能被获知，焦点不意外跳走；先验证系统反馈，再补必要的公告，避免重复朗读。
5. 最大辅助字号、粗体文字、增强对比度、减少动态效果、减少透明度分别检查，并抽查关键组合。可交互文字保持可见与可操作。
6. Accessibility Inspector 的标签、命中区域、对比度检查与人工朗读互相补充。编译成功、一个大字号截图都不能替代这些验收。

## 8. 加载、空态、反馈与内容可信度

**官方依据：**尽早提供可用内容，诚实呈现加载进度；反馈需要让人理解结果和下一步。[Loading](https://developer.apple.com/design/human-interface-guidelines/loading), [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)

**系列决策：**先展示已打包导读或缓存；刷新保留旧内容。没有可用缓存时给出清楚的状态和重试。加载中、确无内容、无搜索结果、请求失败分别处理。未知进度使用不定进度，禁止模拟完成百分比。写入失败不得宣称已同步；本地保存与远端同步状态区分。

空书房提供可读篇目；无日级史料时不展示虚构“历史上的今天”。原文、底本、编辑说明、AI 生成解读分层标识；作品 UUID 与篇目对应关系可追溯。异说在相关位置说明，避免在同一路径反复加入泛化免责。

**官方依据：**生成式 AI 体验需要合理预期、用户控制和清楚反馈。[Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai)

**系列决策：**AI 解读标识来源性质，不能冒充原文、确证史料或真人评论。生成中可取消，失败可重试；核心原文阅读不依赖生成。地图坐标、交游与作品系年按资料精度表达，不由模型补造；提供纠错入口。既有模型、审核和数据架构由相应技术规范管理。

## 9. 首次使用、设置与隐私

| 官方章节 | 系列执行规则 |
| --- | --- |
| [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) | 先让人读到一篇；可选提示按需出现、可跳过。功能不依赖账号或权限时，不把登录和授权放在阅读前。 |
| [Settings](https://developer.apple.com/design/human-interface-guidelines/settings) | 尊重设备外观与辅助设置；阅读字号、行距、纸面偏好集中且可恢复默认。明确即时生效与保存后生效，避免重复系统设置。 |
| [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy) | 在使用相关功能时说明原因并申请必要权限；优先系统选择器，拒绝后有适当替代路径。权限与账号方案的具体实现另行按技术和发布要求验收。 |
| [Writing](https://developer.apple.com/design/human-interface-guidelines/writing) | 用读者理解的短句说明动作、结果和恢复办法；界面不展示内部编成、UUID 或工程状态。筹备中的产品明确写“筹备中”，下载按钮只连接真实商店条目。 |

## 10. 图标与资源

**官方依据：**App 图标应有简单可识别的核心，分层资源适配系统表现，系统负责蒙版与相关效果；SF Symbols 用于界面符号，不能作为 App 图标、徽标或商标。[App Icons](https://developer.apple.com/design/human-interface-guidelines/app-icons), [SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)

**系列决策：**以同一家族的原创字印 / 图形建立识别，由各 App 定义自己的核心符号。小尺寸下首先辨认主体，不堆四字小印和细密纹理。通过 Icon Composer 和当前官方模板检查支持系统中的默认、深色、清透与着色外观；系统自动生成的变体也要检查。交付含原始分层文件与实际设备截图，不自行烘焙系统圆角、玻璃高光与投影。

字体资源保留许可与来源；系统字体通过系统 API 使用。图标、插图与诗文内容资源分别管理，避免用带诗人身份的资源硬编码共享内核。模板和工具以 [Apple Design Resources](https://developer.apple.com/design/resources/) 为准。

## 11. 每批交付的验收口径

| 阶段 | 交付物 | 完成判断 |
| --- | --- | --- |
| PM / 设计 | 一条真实任务路径、信息架构、关键状态和窄宽布局 | 说明所遵循章节与系列自己的选择；有真实内容，不用空模块凑页面 |
| 实现 | 原生组件、语义资源、状态和可访问性 | 所有受影响 target 构建；新 API 有兼容路径；变更范围可复核 |
| 体验评审 | 真正操作路径与视觉 / 辅助模式证据 | 按 QA 矩阵记录设备、OS、字号和开关；待测项保留待测 |
| 发布收口 | 已解决问题、剩余限制、内容和图标资源 | 阅读阻断、核心不可达、正文截断等问题修复；商店状态与实际可用性一致 |

系统支持矩阵至少覆盖当前部署下限与本次采用新行为的系统版本。不能用最新 SDK 的一次构建推断旧系统已经运行通过。每个系列 App 都要走路径；共享实现的细项可复用证据，诗人编成、字体和内容差异仍须抽查。

历史来源核对覆盖 HIG 中与系列直接相关的 **30 个正文专题**（以上各节已链接），另查阅官方设计资源、两场 WWDC 设计讲解和字体 API。覆盖通用及 iOS / iPadOS 部分；没有声称读完 Apple 全站或完成所有平台审计。离线核对工件保存在本机 `/Volumes/XiPass/literature/zhi/.codex-artifacts/apple-design-20260914/`，包含官方 DocC 原始响应、摘要文本及来源 URL / SHA-256；工件用于追溯，不作为产品内容发布。
