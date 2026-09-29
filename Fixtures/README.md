金标 fixture (JSON), 由 qizen 的 Dart 引擎导出, Swift 测试逐条对齐。见 README。

- calendar-2025-2027.json: 2025-01-01 ~ 2027-12-31 每天 (Asia/Shanghai 正午) 的农历 / 干支 / 节气 / 候 / 花信 / 七日内节日, 1095 条。
- shichen.json: 十二时辰起止前后一分钟共 48 个时刻的时辰 / 古名 / 更点。

重新生成 (lunar 包升级或 qizen 的 hou_calendar.dart / culture JSON 有改动时):

    cd ../qizen/app && dart run tool/export_calendar_fixtures.dart

脚本会自行以 TZ=Asia/Shanghai 重跑 (Flutter 版逐日前进用本地 DateTime, 有夏令时的时区会算错)。
Swift 测试经 `#filePath` 直接读本目录, 不经测试包资源。
