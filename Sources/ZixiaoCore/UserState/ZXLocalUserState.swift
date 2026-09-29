import Foundation

/// 账号级本地态的存取 (JSON 文件, 一个用户一份)。
///
/// 为什么键带 userId、一人一个文件:
/// - 同一台设备可能先后是两个人 (退出再建匿名号、或删号重来), 本地态不能串 —— PoetKit 的
///   `ReadingHistoryCache` 按 owner 分键也是为此;
/// - 删号时 `remove(for:)` 删一个文件即可, 不用读改写一份大字典;
/// - 没有用户时 (首启离线) 记在 `device` 名下, 有了账号后 `adoptDeviceState(into:)` 并过去。
/// - 设备级偏好 (`ZXPreferenceKey.Scope.device`, 如「历注」、阅读器排版、晚省提醒时刻) 永远存在 `device`
///   文件的 `deviceFlags` / `deviceSettings` 里, 与 userId 无关; `flag` / `setFlag` / `setting` / `setSetting`
///   按键的作用域自动路由, 调用方照常传当前 userId 即可。
///   `adoptDeviceState` 与 `remove` 都不碰它 —— 退出、删号、找回旧账号后「历注」开关保持原样。
///
/// 为什么是 actor 而不是 @MainActor: 启动时记「今天打开」发生在 bootstrap 的后台步骤里, 不该占主线程;
/// actor 也串行化同一文件的读改写。与 `ReadingStateStore` 同一套路: 内存缓存 + `.atomic` 写盘 + 坏文件留证。
public actor ZXLocalUserState {
    /// 没有用户时使用的键。
    public static let deviceKey = "device"

    public nonisolated let directory: URL
    private var cache: [String: ZXLocalUserSnapshot] = [:]

    /// - Parameter directory: 默认 `Application Support/ZixiaoCore/users/`。
    public init(directory: URL? = nil) {
        self.directory = directory ?? ZXCorePaths.root.appendingPathComponent("users", isDirectory: true)
    }

    /// 读某个用户的本地态; nil 表示设备 (未登录)。
    public func snapshot(for userId: String?) -> ZXLocalUserSnapshot {
        let key = Self.key(for: userId)
        if let cached = cache[key] { return cached }
        let url = fileURL(forKey: key)
        var snapshot = ZXLocalUserSnapshot.empty
        if let data = try? Data(contentsOf: url) {
            if let decoded = try? Self.decoder.decode(ZXLocalUserSnapshot.self, from: data) {
                snapshot = decoded
            } else {
                let backup = url.appendingPathExtension("corrupt")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.moveItem(at: url, to: backup)
            }
        }
        cache[key] = snapshot
        return snapshot
    }

    /// 改一次并落盘, 返回闭包的结果。
    @discardableResult
    public func update<T: Sendable>(for userId: String?,
                                    _ change: @Sendable (inout ZXLocalUserSnapshot) -> T) throws -> T {
        var snapshot = snapshot(for: userId)
        let result = change(&snapshot)
        try save(snapshot, for: userId)
        return result
    }

    /// 覆盖写入。
    public func save(_ snapshot: ZXLocalUserSnapshot, for userId: String?) throws {
        let key = Self.key(for: userId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: fileURL(forKey: key), options: .atomic)
        // 缓存存「从盘上读回来会得到的」那份, 避免日期精度在重启前后不一致 (同 ReadingStateStore 的教训)。
        cache[key] = (try? Self.decoder.decode(ZXLocalUserSnapshot.self, from: data)) ?? snapshot
    }

    // MARK: - 便捷方法

    /// 记一次打开, 返回更新后的本地态。
    @discardableResult
    public func recordOpen(for userId: String?, at date: Date = Date(),
                           timeZone: TimeZone = ZXLocalUserSnapshot.defaultTimeZone) throws -> ZXLocalUserSnapshot {
        try update(for: userId) { snapshot in
            snapshot.recordOpen(at: date, timeZone: timeZone)
            return snapshot
        }
    }

    public func noteOpened(_ item: ZXRecentItem, for userId: String?) throws {
        try update(for: userId) { $0.noteOpened(item) }
    }

    /// 读开关。`.device` 作用域的键忽略 `userId`, 读设备文件。
    public func flag(_ key: ZXPreferenceKey, for userId: String?, default defaultValue: Bool = false) -> Bool {
        snapshot(for: Self.owner(of: key, userId: userId)).flag(key, default: defaultValue)
    }

    /// 写开关。`.device` 作用域的键忽略 `userId`, 写设备文件。
    public func setFlag(_ key: ZXPreferenceKey, _ value: Bool, for userId: String?) throws {
        try update(for: Self.owner(of: key, userId: userId)) { $0.setFlag(key, value) }
    }

    /// 读小设置。`.device` 作用域的键忽略 `userId`, 读设备文件的 `deviceSettings`;
    /// `.user` 作用域读该用户文件的 `settings`。
    public func setting(_ key: ZXPreferenceKey, for userId: String?) -> String? {
        snapshot(for: Self.owner(of: key, userId: userId)).setting(key)
    }

    /// 写小设置, 路由同 `setting(_:for:)`。`nil` 删除该项。
    public func setSetting(_ key: ZXPreferenceKey, _ value: String?, for userId: String?) throws {
        try update(for: Self.owner(of: key, userId: userId)) { $0.setSetting(key, value) }
    }

    /// 只读设备级设置的便捷入口。
    public func deviceSetting(_ key: ZXPreferenceKey) -> String? {
        precondition(key.scope == .device, "\(key.rawValue) 不是设备级的键")
        return snapshot(for: nil).setting(key)
    }

    /// 只写设备级设置的便捷入口。`nil` 删除该项。
    public func setDeviceSetting(_ key: ZXPreferenceKey, _ value: String?) throws {
        precondition(key.scope == .device, "\(key.rawValue) 不是设备级的键")
        try update(for: nil) { $0.setSetting(key, value) }
    }

    /// 只读设备级开关的便捷入口。
    public func deviceFlag(_ key: ZXPreferenceKey, default defaultValue: Bool = false) -> Bool {
        precondition(key.scope == .device, "\(key.rawValue) 不是设备级的键")
        return snapshot(for: nil).flag(key, default: defaultValue)
    }

    /// 把设备名下的账号级本地态并进某个账号, 然后把设备那份的账号级部分清空
    /// (免得之后另一个人登录又并一次); 设备级偏好原地保留。
    public func adoptDeviceState(into userId: String) throws {
        let device = snapshot(for: nil)
        guard device != device.devicePortion else { return }   // 设备名下没有账号级内容
        let mine = snapshot(for: userId)
        try save(mine.merged(with: device), for: userId)
        try remove(for: nil)
    }

    /// 删掉某个用户的本地态 (删号、退出后的匿名号、找回旧账号时被放弃的匿名号)。
    /// `userId == nil` 清的是设备名下的账号级部分; 设备级偏好任何情况下都保留。
    public func remove(for userId: String?) throws {
        let key = Self.key(for: userId)
        if userId == nil || key == Self.deviceKey {
            let kept = snapshot(for: nil).devicePortion
            if kept == .empty {
                try deleteFile(forKey: key)
            } else {
                try save(kept, for: nil)
            }
            return
        }
        try deleteFile(forKey: key)
    }

    private func deleteFile(forKey key: String) throws {
        cache[key] = nil
        let url = fileURL(forKey: key)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// 设备级的键一律落到设备文件。
    private static func owner(of key: ZXPreferenceKey, userId: String?) -> String? {
        key.scope == .device ? nil : userId
    }

    // MARK: - 内部

    /// userId 做文件名前先消毒: 正常是 UUID, 但别让一个意外的 `/` 或 `..` 写出目录。
    static func key(for userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return deviceKey }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let cleaned = String(userId.lowercased().map { allowed.contains($0) ? $0 : "_" })
        return "u-" + cleaned
    }

    private func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }
}
