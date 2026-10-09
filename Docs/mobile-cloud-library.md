# 统一书房移动端接入（2026-10-07）

代码与接口已接入。本文件描述实现范围；编译、端到端结果由 workspace 主任务的串行验收记录补充。
后端协议见 `poetry/code/poetryhub/web/docs/zixiao-library-sync.md`。后台迁移和 Web 部署由主任务隔离执行，移动文件不会触发部署。

## 同步范围

| 产品 | 原生 iOS | 原生 Android | 数据源 |
| --- | --- | --- | --- |
| 微诗 | 最近阅读、歌曲收藏、画屏草稿和照片 | 同左，国内/Play 共用仓库 | 新 `zx_library_*` |
| 玄览 | 书籍收藏 | 书籍收藏 | 新 `zx_library_*` |
| 诗人志 | 各 app_slug 的经典阅读位置和摘抄 | 现有作品收藏、阅读记录与进度 | iOS 经典用新协议；Android 作品直连原 `poetkit_*` |
| 既有云资料 | 诗作收藏/诗集、诗人作品笔记、玄览阅读/摘抄/日课保留原同步 | 已有玄览日课/阅读/摘抄保留原同步 | 原表保持权威，Mac 通过适配器聚合 |

Android 诗人志目前没有经典书库和笔记编辑器，不伪造不存在的入口。其作品收藏和阅读直接使用 iOS 原来的 owner_key/app 表和规则，不同时投影到新表。Mac 的 LegacyPoetryLibraryAdapter 同源读取；旧表阅读仅有比例/完成度，没有跨设备像素偏移。

## 实际入口

- 微诗：诗斋设置区 →「同步书房」。iOS 在 App 启动、账号变化、前台恢复和本机资料变化时触发；Android 在账号恢复/变化、相关本机 Flow 变化时触发，也可从此入口手动重试。
- 玄览：设置 →「同步书房」。书架/阅读器收藏按钮仍修改同一个 BookFavorites；仅绑定账号自动同步。
- 诗人志 iOS：设置 →「同步书房」。经典书架注入账号与诗人分别持久化的 ReadingStateStore；真正翻页/完成记录触发同步。
- 诗人志 Android：书房设置 →「登录账号」和「同步书房」。短信走现有手机号 broker、图形验证码，令牌由 Android Keystore 加密；诗人 flavor 保留独立 app 字段。

「导入本机资料」总是先展示预览，可取消。无归属的旧 UserDefaults/Preferences/文件不会自动上传给第一次登录者，原件不会在导入后删除。账号退出时切回游客空间；重新登录只恢复该账号空间。已有云端明确归属的记录直接拉取，不要求重复导入。

## 协议与隔离

- Swift：`Sources/ZixiaoCore/CloudLibrary/` 的 client、JSON model 和 UI-neutral driver。
- Kotlin：三仓库 `android/app/src/main/java/com/zixiao/cloud/` 同协议；PoetLegacyCloud 实现同一个 transport，接旧 poetkit 表。
- 队列/cursor/remote records/tombstones 在同一账号文件原子保存。首次发送前固化 revision、mutation UUID 和 body，失败/重启复用同一 UUID。
- 调用传入 captured expectedOwner；等待文件锁、网络和素材上传时发生换号会停止旧任务，不把旧快照写入新账号。
- 快照只比较本产品管理的子集，不因其他产品条目未出现在本地 store 就删除。取消收藏保存 tombstone。
- 未知 payload/嵌套 recipe 字段合并保留。字段确需清空时使用 JSON null，省略不代表删除。
- 草稿分叉保存服务端原样 record.key，同时分配独立的本地 recipe ID，后续编辑不能回写原稿。保留原 contentRef，不因平台更换改变来源。
- 画屏照片走私有 bucket；JSON 存 asset ID/`zx-asset://`，不保存签名 URL。素材下载失败保留现有本机内容和待处理记录。
- 注销走原有 HTTP 删除账号流程，先清理新增私有媒体及同步表，再删除 profile 和 Auth 用户。任一新增素材清理失败、Auth 用户删除失败都不报告成功；仍有效的 GoTrue session 可重试（此端点鉴权不依赖 profile 存在）。GoTrue/旧 RPC 直接删除无法清理 Storage 对象，不作为这些客户端的删除入口。各设备的离线文件按账号隔离，云端注销不意味着可远程擦除其他离线设备上的本机副本。

## 源码接线

- 微诗 Swift：`ios/PoetryHub/Services/PoetryCloudLibrary.swift`；LibraryStore、RealmSongFavorites、HuapingSharedStore 分别切换实际账号存储；App 与设置入口已接。`fetchPoems(ids:)` 批量补齐外来阅读记录的可点击原诗。
- 玄览 Swift：`apple/Sources/Features/Library/XuanlanBooksCloud.swift` 和 BookFavorites；RootView 与 SettingsScreen 已接，XcodeGen 生成工程时自动包含。
- 诗人志 Swift：`Sources/ZixiaoPoet/Capabilities/PoetBooksCloud.swift`；LibraryShelfView 的阅读 store 注入、完成/落盘回调、Profile 设置已接。
- 微诗 Kotlin：`data/repository/CloudLibraryRepository.kt`；MainActivity 注入、Profile、LibraryStore/SongFavoritesStore/HuapingMineStore 已接。
- 玄览 Kotlin：AppModel、LocalStore 的账号收藏键、Profile 设置入口；HttpAuthBackend 删除端点改 HTTP。
- 诗人志 Kotlin：PoetCloudAccount、PoetCloudAccountPanel、PoetLegacyCloud、PoetViewModel 与 ReaderScreen/SettingsScreen。

## 验证

新增 Core CloudLibraryTests 模拟 HTTP transport，覆盖：回包失败后的精确重试、待确认编辑撤销、未知字段/墓碑保留、跨账号响应隔离、冲突选云端后不反复上传、阅读时间含时区/小数秒的新者胜。三套 Kotlin CloudLibraryContractTest 核对阅读冲突条件及未知字段合并；JVM 测试使用 org.json 实现，而不是 android.jar 的占位方法。
玄览 AuthBackendTest 核对注销 HTTP 路径及令牌仅通过 Authorization 发送，不把 Supabase apikey 发给 Web。

服务端 `delete-account.test.ts` 覆盖 profile 已删除但 Auth 删除失败时拒绝报告成功，以及同账号再次请求可完成清理；`library-sync-server.test.ts` 覆盖私有素材清理先于数据库记录删除。测试使用模拟服务，真实注销与 Storage 联调应使用独立测试账号。

仍需真人设备/线上联调确认：同账号两设备续读、短信验证码、退出再登录、断网再恢复、两个设备同时编辑画屏及照片；App Store/Play 发布不包含在这次代码提交动作中。未声称这些已通过单元测试验证。
