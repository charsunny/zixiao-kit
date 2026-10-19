# 笔触引擎金标

`brush-v1.json` 的生成路径在 `Tests/ZixiaoArtTests/ZXArtBrushTests.swift`，用 `#filePath` 定位到本目录。
它不参与 `procedural-v1.json` / `procedural-v2.json` 的生成，也不需要改 Package.swift。
本 PR 在 Linux VPS 编写，未在本机编译/测试；JSON 由 charsunny 在 Mac 首次运行后生成并提交。
文件缺失时 `testBrushFixture` 会 skip 并提示生成命令，不以空 JSON 充当金标。

在仓库根目录运行（模拟器名称按本机已安装设备调整）：

```sh
# 只生成笔触金标，不运行旧配方的写金标测试。
TEST_RUNNER_ZXART_WRITE_FIXTURES=brush-v1 \
xcodebuild test -scheme ZixiaoKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ZixiaoArtTests/ZXArtBrushTests/testBrushFixture

# 不设置写 fixture 开关，确认比对；同时输出目视样张与 xcresult 附件。
TEST_RUNNER_ZXART_WRITE_SHEETS=/tmp/zxart-brush \
xcodebuild test -scheme ZixiaoKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath /tmp/zxart-brush-review.xcresult \
  -only-testing:ZixiaoArtTests/ZXArtBrushTests \
  -only-testing:ZixiaoArtTests/ZXArtProceduralFixtureTests \
  -only-testing:ZixiaoArtTests/ZXArtParityTests
```

测试进程直接使用 `ZXART_WRITE_FIXTURES` / `ZXART_WRITE_SHEETS`，经 xcodebuild 启动时用
`TEST_RUNNER_` 前缀传入。第二次运行前需为 xcresult 换一个未占用的路径。

金标保存每个用例的输入参数与完整输出（墨体顶点、首尾 alpha、每根笔毫的宽度 / alpha / 各段顶点），
覆盖十种压力曲线、四档 dry、progress 0.5 / 1、宽度 1 / 20 / 130、正反 darkDirection、
开口墨圈、墨点，以及哈希和噪声取数。墨体首尾 alpha 分别存为 `bodyAlphaStart` / `bodyAlphaEnd`。
整数哈希逐位比较；浮点沿用 `ZXArtParityTests` 的 `1e-9` 相对 / 绝对容差。
几何和 alpha 输出是 Float32，后续 JS 移植须在相同位置用 `Math.fround`。
数组长度及对象字段必须一致，不能只比坐标和。

目视检查两张图：`brush-v1-model-sheet-paperink.png`、`brush-v1-model-sheet-night.png`。
行是压力曲线，列是 dry 0 / 0.4 / 0.8 × side 0 / 0.8；接着是三种 seed 的开口墨圈及三档压扁比的墨点，
底部新增宽度 1 / 20 / 130 的笔触和 darkDirection 朝下 / 朝上的对照。
检查起收笔差异、非等距的飞白、含墨侧的连续浓淡、墨圈开口与压扁比，以及是否出现规则平行条纹。
特别检查 130 宽的大笔是否仍有长尺度断墨、1 宽细线是否有变化，以及方向反转后浓侧是否翻转。
图像由现有 `ZXArt.render` 绘制，CoreText 仅添加英文参数标签。

固定 `gapLength` 时保留参考步长 0.5、最多 600 点的网格，调用方应传入不小于动画最大弧长的参考长度；
参考长度偏小会使笔毫采样变稀。噪声输入仍是 `u * reference`，再除以随笔宽变化的尺度。
`darkDirection` 根据整笔按弧长加权的平均法线确定 `side` 正负，y 向下时正 side 为前进方向右侧。
点积为零或方向无效时保留原 side；方向解析不随 progress 截取而改变。
