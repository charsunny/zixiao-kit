# shanshui@5 国画化一轮：模型、元素与构图

2026-10-21 起草（Claude）。目标：**更像传统中国画**。基线是 zixiao-kit PR #9（`feat/shanshui-taste`）。本轮在其上叠加，分支 `feat/shanshui-guohua`。

不考虑兼容：直接改 `shanshui@5`，不开新版本（线上没有用户收藏，只有老版本展示）。

## 1. 已经做过的（不要倒退）

PR #9 和它的追加提交已经解决以下问题，详见 PR 说明。改动时不能把它们改坏：

- 皴笔按受光分布、点苔；坡陀错落；远山分峰、偏向一侧；
- 山脚用 `LayerFade` 入云：墨自己淡去，不盖纸色；
- 竖幅诗句占右上天空，诗下地面铺满整宽（`bandTop` / `lowerBand()`），近岸下沿入雾；横幅退回画栏；
- 一河两岸的中景对岸（`paintingFarShore`）；
- 新画的茅屋（屋脊平、对称、有台基）、栅栏、垂藤、瘦马、芦苇、竹林、点花与横点、个字点叶法、泼墨荷叶、烘云托月、界画粉墙、峰顶古台、大漠、海天；
- 山寺、山居的建筑落在主山山脚（`placeAtFoot`）；树干随机、按树种分枝法，有双干和欹斜。

## 2. 还存在的问题（按影响大小排）

### 构图
1. **骨架千篇一律**：几乎每类都是「远山 + 一道远岸 + 底部一条近岸」。要按诗意和种子在几种传统骨架之间选，并真正改变画面的大结构，不只是挪动框的位置：
   - 高远（郭熙）：主峰高耸，顶天立地，有主峰与宾峰；
   - 深远：层层山峦沿对角线后退，用云和水口隔开；
   - 平远（倪瓒一河两岸）：近岸、大片水面、远岸；
   - 边角（马一角、夏半边）：景物集中在一角，其余大片留白。
   诗句框的避让、整宽地带、推荐页和阅读页的留白规则都不能破坏。
2. **日月永远在同一个位置**（`slot(0.61, 0.06…)`）。要按构图放：落日贴远山或地平线，月在空白处与主体呼应。
3. **墨色整体偏淡、没有醒提**：近景要有焦墨、浓墨（近树、点苔、屋檐暗部、舟、人），远处逐层变淡。可以做一个按景深分层的墨色系数。

### 元素
4. **点景人物不落地**：送别里两个行人挂在柳树树冠上（`traveler` 的 `slot(0.56, 0.72…)` 没有落到坡岸）。人物要落地，大小按「丈山尺树寸马分人」与周围景物相称；人物画法要更像传统点景：几笔衣纹，头部一点，戴笠、持杖、骑驴等按诗意来。
5. **亭子还是旧的西式八角凉亭**（`pavilion` 走 legacy `arch04`）。重画传统的亭：攒尖顶或歇山顶，翼角起翘，四根柱子，低栏，多半藏在树后。
6. **小桥不跨水**：秋行里小桥架在坡顶上，桥下没有水。桥必须跨在溪或河上，桥下有水、两端接岸，石拱桥有倒影或水纹。水乡、秋行都要检查。
7. **藤像绳梯**：垂藤笔直、等距。藤蔓要缠绕、长短参差，叶点集中在上部。
8. **坡石重复**：每个场景都是 `paintingBank` 那一组四块石头。至少按场景给出几种不同的坡石组合与皴法：江南平远用披麻、低平汀渚；山寺、高远用斧劈、有棱角的大石；矾头、卵石滩、石矶等也可以用上。
9. **主山单一**：主山总是 shan-shui-inf 的山体，山顶戴一圈点树。要有矾头、层叠的山头、山脊上疏密有致的树，而不是一顶「帽子」；山形要和所选的骨架（高远、深远）一致。
10. **舟**：船身和篷还是简单的符号。按传统画小舟：船身微翘、篷为弧形竹篷，渔舟有人、钓竿、蓑笠。
11. **水**：河道两岸线和水纹仍偏机械；海天的浪是平行线，可以参考宋人水图（马远《水图》）的节奏线。
12. **大漠沙丘**仍有几何感；孤烟、长河可以再雅一些。
13. 次要：树谱里的松偏瘦高、树冠偏稀；塔和山门（legacy）可以重画；春日的「蹊」（花间小路）不明显。

## 3. 怎么工作

### 看图（必须看图，不要只读代码）
VPS 不能渲染（Linux 没有 CoreGraphics），出图在 charsunny 的 Mac「xistudio」上，SSH 已经配好：
- `ssh xistudio` 通过 VPS 上的用户态 Tailscale。连不上时，用 `crontab -l` 里 `@reboot` 那条命令重启 `tailscaled`，再用 `~/.local/bin/ts status` 检查。
- 一轮出图：在 `/home/paseo/workspace/literature/zixiao-kit`（当前分支）提交后，执行 `~/review/round.sh <轮次名>`。它推送 HEAD 到 Mac 的 `incoming`，在 iPhone 17 模拟器上跑 `ZXArtSceneReviewTests`，导出 15 类 × 竖横 × 明暗的样张、总览 `overview-portrait-light.png` 和树谱 `trees.png`。**出图结果留在 Mac**：原图在 `/Volumes/XiPass/literature/taste/reviews/<轮次名>/`，900px 小样在其下的 `small/`。一轮大约 5–10 分钟。
- 看图：VPS 不再整批保存样张。`~/review/view.sh <轮次名>` 列出文件；`~/review/view.sh <轮次名> <文件名...>` 把指定小样取到 `/tmp/review-view/<轮次名>/` 查看；局部放大用 `~/review/crop.sh <轮次名> <文件名> <高> <宽> <y> <x>`（在 Mac 上裁原图再取回）。看完执行 `~/review/view.sh --clean`。
- 基线：Mac 上 `reviews/r18/`（PR #9 的最终状态）、`reviews/guohua-r15/`（PR #10 当前状态）、`reviews/base/`（改造前）。

### 测试
- 在 Mac 上跑（通过 ssh），不要在 VPS 上编译：
  ```
  cd /Volumes/XiPass/literature/taste/zixiao-kit && git reset -q --hard incoming && \
  xcodebuild test -scheme ZixiaoKit-Package -configuration Release ENABLE_TESTABILITY=YES \
    -destination "platform=iOS Simulator,id=42D624E8-787E-412C-BAC6-AD74AFC35FA1" \
    -derivedDataPath /Volumes/XiPass/literature/taste/DerivedData \
    -only-testing:ZixiaoArtTests/ZXArtPaintingSceneTests -only-testing:ZixiaoArtTests/ZXArtPoetrySceneTests \
    -only-testing:ZixiaoArtTests/ZXArtProceduralFixtureTests -only-testing:ZixiaoArtTests/ZXArtBrushTests \
    -only-testing:ZixiaoArtTests/ZXArtParityTests
  ```
- App 验收：Mac 上 `/Volumes/XiPass/literature/taste/wish` 是和 kit 并排的 wish worktree（分支 `taste-incoming`，即 wish PR #89）。跑 `PoetryHubTests/HuapingEditingTests` 和 `PoetryHubTests/HuapingArtTests`，命令参考 wish PR #89。`HuapingEditingTests` 会检查每类场景必须出现的景物（`ios/PoetryHubTests/Fixtures/huaping-scene-acceptance.json`）。如果按画理确实要改这张表，在 wish 的 `feat/shanshui-taste` 分支上改，并在 PR 里写明理由。
- 已知的旧失败，不必处理：全量 `ZixiaoArtTests` 里的 4 项（Rim、V3 墨量、V3 分块、Wash 分块），以及 App 的 `HuapingWeatherTests.testSnowEdgesFollowTheRidgeFromBelow`。
- 场景测试里的比例上限，可以随画理有意调整，但要在 PR 里说明为什么。

### 约束
- VPS 只有 1G 内存：不要在 VPS 上跑 `swift build` 或 `xcodebuild`，不要装依赖，也不要再起其他 agent。
- 只用墨色，加一个点缀色（朱砂）；不发光，不铺大色块。
- 不改 @1、@2、@3 的出图和金标；不改 `Package.swift` 的 target 结构。
- Mac 上只动 `/Volumes/XiPass/literature/taste/` 下的东西，以及 `/tmp` 里的输出，不碰其他目录。不要在 Mac 的 App 编译还没结束时往 `incoming` 推送。
- 小步提交，提交说明用中文。

## 4. 交付

1. 至少迭代到总览和每类单张都明显更像传统中国画。每轮看图后记下改了什么、还差什么。
2. 推送 `feat/shanshui-guohua`，开 PR 到 master，说明 base 是 PR #9 的分支。PR 里写：
   - 每一项问题怎么改的；
   - 前后对比，指出样张路径；
   - 测试结果；
   - 还没解决的问题。
3. 把最终样张复制到 Mac 的 `/Volumes/XiPass/literature/qa-taste-2026-10-21/guohua/`。
