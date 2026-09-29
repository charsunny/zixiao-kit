ZixiaoCalendar 随包资源。

- hou72.json / huaxin.json / shichen.json / suishi.json: 从 `qizen/app/assets/culture/` 原样复制, schema 不动。
  为什么不改 schema: Flutter 版 (Android / Web) 仍在读同一套文件, 两端各自改会漂移; 要改先改 qizen 那边, 再复制过来。
- eras.json: 从 PoetKit (`zhi/DongpoZhi/Packages/PoetKit/Sources/PoetKit/Resources/eras.json`) 原样复制, 年号是朝代级公共参照数据。
