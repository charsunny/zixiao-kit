# shanshui@5 构图审图记录

基线：master f4f3967 / elements-d14。开发分支：feat/shanshui-composition。
代码修改与审查在 VPS；编译、出图、测试均在 xistudio，未启动其他 agent。

## 迭代

- elements-d14：完整查看总览、三张种子谱、15 场景竖横版。主体低、小，右下坡石脱离主景；庭院是一段大墙；大漠与海上缺少纵深。
- comp-1：主峰比例初始化的 Swift 编译错误，未产生可用样张；修正后进入 comp-2。
- comp-2：抬高主峰和主树、连近岸、疏短蟹爪。总览、三张种子谱、受影响场景横竖版及深色抽查；另看树木图谱。主峰尺度改善，但秋屋比例仍需调整、飞鸦偏大、泊舟压岸、日月与树重叠。
- comp-3：庭院前墙—后楼—柳、地面台阶；大漠沙脊—烽燧—长河—落日；海平面—月—碎光—近浪—礁石。查看总览、三张种子谱和相关横竖版、深色版。发现河道过宽似道路、塔脚悬空、月光横笔侵入月面、秋屋仍大。Kit 回归暴露桥与人马尺度、海水 anchor、推荐页上沿问题。
- comp-4：限制人高跟随桥跨度；大树保留前景分量，房屋回到中景；保护阅读上下留白；增加中段沙丘并把塔脚落到沙脊；月面抬离碎光；深远宾峰沿对角线后退。查看总览、三张种子谱、全部15场景竖横版、庭院和大漠深色。Kit 原有比例和海水测试通过，剩余上沿与新增构图断言继续修正。长河仍需更明确曲折，水乡种子谱仍过于成对重复。
- comp-5：水景加入深远候选；主树大小、偏向进一步拉开；秋屋限制一至两间；沿用河道画法，单独调整大漠河道开口和曲率；庭院后屋限制在画栏内，飞鸦保护推荐页上沿，边角远山上提。查看总览、三张种子谱、全部15场景横竖版、组合谱与树木/人物图谱，抽查大漠和海上深色。原有回归已通过，新增检查继续推动宾峰与月面尺度修正。
- comp-6：深远宾峰继续上移，前后层次更清楚；庭院单柳/双柳及大小变化；烽燧根据真实河湾两岸找沙脊落脚。查看总览、三张种子谱、六类改动场景全部横竖版，四类深色抽查，并裁切大漠横幅检查塔脚。上部景势测试已通过；一个横幅的月云过高，使碎光不足页面20%。
- comp-7：给横幅月云增加按画高计算的上限，留出月下水面。查看总览、种子谱、海上竖横版及横幅深色。
- comp-8：把较小柳树的庭院改为画栏中段的远院；加大上部景势测试覆盖，纳入庭院。查看总览、种子谱、庭院横竖明暗、带亭庭院和海上横幅。全部原有测试及月面/碎光检查通过；新检查发现最后一个近院种子的树冠仍低于35%。
- comp-9：将该种子也归入远院，保留一类近院与三类远院（单柳、双柳、不同主树尺度）。已查看总览、三张种子谱、庭院横竖明暗；本轮 Kit 全部通过。

## 设计取舍

- 保持既有山、树、坡、屋、舟、人马的勾皴画法；只增加烽燧，并为山形比例、河道曲率/宽窄、屋间数提供可选参数。默认参数保留原画法。
- 秋思原来的“树高不超过8个人高”与本轮前景高大老树冲突。允许前景树/中景行人为3–18倍；门/人、檐/人、桥/人、马/人仍按原测试验收。
- 日月避让树冠与山体；远山淡、中景次之、近岸及树屋用浓墨，未全局加灰。

## 最终样张与验证

- 最终轮次：`comp-9`，出图代码 `1d1fe0c95d36ade0c1d7de2d0dc7a7ea457a4c59`。
- 基线：`xistudio:/Volumes/XiPass/literature/taste/reviews/elements-d14/`。
- 最终出图：`xistudio:/Volumes/XiPass/literature/taste/reviews/comp-9/`。
- 归档：`xistudio:/Volumes/XiPass/literature/qa-taste-2026-10-21/composition/`。
- 106 张原图、106 张900px小样；包括15类竖横明暗、总览、种子谱、景物图谱和组合谱。归档附 PNG 校验和、测试命令与日志。

| 验证 | 结果 |
| --- | --- |
| SceneReview 出图 | 8 项 XCTest 通过，106 张 PNG，`TEST SUCCEEDED` |
| Kit 定向回归 | 30 项 XCTest + 32 项 Swift Testing 通过，0失败，`TEST SUCCEEDED`，退出码0 |
| App 验收 | HuapingEditingTests 55项 + HuapingArtTests 26项，共81项通过，0失败，`TEST SUCCEEDED`，退出码0 |
| VPS 代码检查 | `git diff master --check` 通过；全部代码在 VPS 编写及审查 |

Kit 覆盖：`ZXArtPaintingSceneTests`、`ZXArtPoetrySceneTests`、`ZXArtProceduralFixtureTests`、`ZXArtBrushTests`、`ZXArtParityTests`、`ZXArtGuohuaTests`、`ZXArtElementsCompletionTests`、`ZXArtCompositionTests`。
其中包括同种子确定性、选中必画、诗句框与阅读/推荐页留白、房屋落地、人马桥屋比例、日月避山与本轮新增的主体高度/庭院纵深/烟台相接/月面碎光关系。

App 使用 wish main 提交 `2f72153db6b0587ed9c761d1827b6ce6f5fa7cbd`（PR #89 已合并），本地依赖指向相邻的最终 kit。main 被另一个 worktree 使用，因此验收 worktree detached 在该 main 提交上；验收表无修改。场景验收包含15类 × 明暗 × 竖幅/方幅/横幅，共90种实际页面绘制。

两组验收均在 iPhone 17 模拟器 `42D624E8-787E-412C-BAC6-AD74AFC35FA1` 上执行。Kit 使用 Release、`ENABLE_TESTABILITY=YES`，App 使用 Debug，分别使用 `taste/DerivedData` 和 `taste/DerivedData-app`。完整执行命令随归档保存为 `kit-command.sh` 与 `app-command.sh`。

早期失败轮次的日志仍保留在各 `reviews/comp-*` 目录。部分失败运行在报告 Swift Testing 结果后停留于 Xcode SDK 记录阶段；确认结果已落盘后，只终止了对应的遗留 xcodebuild 进程。最终成功轮次以完整 `TEST SUCCEEDED` 和退出码为准。

## 仍可打磨

月夜、荷塘的种子差异比山寺、大漠更克制；沙丘、河湾和海浪仍有程序化的线条节奏。当前样张和有限种子回归不代表穷举了所有诗句、字号和比例组合。

本轮执行计划指定的定向回归，没有运行包含已知 Rim、V3 墨量/分块、Wash 分块失败的全量 Kit，以及 App 的旧雪边缘失败项。它们的状态仍以此前记录为准。
