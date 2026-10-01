ZixiaoCalendar 随包资源。

- hou72.json / huaxin.json / shichen.json / suishi.json: 从 `qizen/app/assets/culture/` 原样复制, schema 不动。
  为什么不改 schema: Flutter 版 (Android / Web) 仍在读同一套文件, 两端各自改会漂移; 要改先改 qizen 那边, 再复制过来。
- eras.json: 从 PoetKit (`zhi/DongpoZhi/Packages/PoetKit/Sources/PoetKit/Resources/eras.json`) 原样复制, 年号是朝代级公共参照数据。

## T54 详情字段 (只在本包加, 尚未回写 qizen)

hou72 / huaxin / shichen 三个文件在原 schema 上**只增不改**地加了图鉴详情字段 (旧字段一个没动, Flutter 版解码时忽略未知键, 不受影响):

- hou72: `source` `sourceBook` `explain` `life` `poem`
- huaxin: `intro` `source` (未能逐花考定的省略) `life` `poem`
- shichen: `explain` `health` `poem`

`poem` 为 `{text, author, title}`, 对应 Swift 的 `ZXPoemQuote`; 全部可选。下次从 qizen 重新复制前, 先把这些字段合并回 qizen, 否则会被覆盖。
