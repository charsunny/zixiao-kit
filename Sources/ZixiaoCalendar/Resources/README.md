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

## T57 节气详情 (只在本包加, 尚未回写 qizen)

suishi.json 的 `terms` 同样**只增不改**地加了 `source` `sourceBook` `explain` `life` (全部可选, Swift 侧 `ZXTermVerse` 对应同名可选属性; `festivals` 未动):

- `source` / `sourceBook`: 节气名释义原句与书名。21 条出自《月令七十二候集解》; 大暑 / 秋分 / 大寒三条集解只写「解见小暑 / 春分 / 前」, 改用《淮南子·天文训》斗建句。
- `explain`: 140–200 字, 写太阳黄经 (立春 315° 起每气 +15°)、公历日期区间、气候物候、三候名 (与 hou72 一致) 与串讲。
- `life`: 80–140 字, 民俗 / 饮食 / 养生, 养生只写「传统上 / 古人认为」。

另外按维基文库核对了现有诗句, 改了 8 条 `line` / `author` / `title` 的值 (键名不变): 春分 (欧阳修《阮郎归》又见冯延巳集, 且有「柳如眉 / 柳如丝」异文) → 徐铉《春分日》; 清明 (杜牧《清明》不见于《樊川文集》, 作者存疑) → 程颢《郊行即事》; 谷雨 / 小满 / 小暑 / 小寒 (元稹《咏廿四气诗》作者存疑, 维基文库无本) → 林逋《尝茶次寄越僧灵皎》、欧阳修《归田四时乐春夏二首·其二》、杨万里《夏夜追凉》、王安石《梅花》; 立冬篇名订正为「立冬即事二首·其一」; 小雪「能饮一杯无」句末改为问号。回写 qizen 时这 8 条一并合过去。
