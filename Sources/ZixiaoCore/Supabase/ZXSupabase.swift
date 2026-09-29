import Foundation
import os
import Supabase

/// Supabase 客户端的单例配置。由 App 在启动时调用 `configure`, URL 与 anon key 来自 xcconfig → Info.plist。
///
/// 为什么缺配置不崩溃而是「离线模式」:
/// - 开发机 / CI / 截图构建常常不填密钥, 这时 App 仍要能跑今日页、书斋等纯本地功能;
/// - 矩阵各 App 的核心体验本来就不依赖账号, 账号只是「换设备不丢」的保险。
/// 离线时 `client` 为 nil, 所有经 ZixiaoCore 的网络操作抛 `ZXCoreError.offline`。
///
/// 为什么是 enum + 锁而不是 `@MainActor` 单例: 离线队列 (actor) 与认证后端都在非主线程读它,
/// `OSAllocatedUnfairLock` 让读取同步、无需 await, 且 StrictConcurrency 下可证安全。
public enum ZXSupabase {
    private struct Configured: Sendable {
        let client: SupabaseClient
        let url: URL
    }

    private static let state = OSAllocatedUnfairLock<Configured?>(initialState: nil)

    /// 未配置 (或配置无效) 时为 true。
    public static var isOffline: Bool { client == nil }

    /// 已配置的客户端。只给 ZixiaoCore 内部与极少数需要直查的内核模块用 —— UI 不应直接碰它 (见评审清单)。
    public static var client: SupabaseClient? { state.withLock { $0?.client } }

    /// 当前配置的项目 URL (诊断 / 「关于」页用)。离线时为 nil。
    public static var url: URL? { state.withLock { $0?.url } }

    /// 取客户端, 离线时抛 `.offline`。
    public static func requireClient() throws -> SupabaseClient {
        guard let client else { throw ZXCoreError.offline }
        return client
    }

    /// 用 URL + anon key 配置。任一缺失或是占位符时进入离线模式并返回 false。
    ///
    /// - Parameter storageKey: session 在钥匙串里的键。同一台设备上多个 App 的钥匙串本就隔离,
    ///   一般不用传; 只有同一个 App 要连两套后端时才需要区分。
    @discardableResult
    public static func configure(url: URL?, anonKey: String?, storageKey: String? = nil) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false,
              let key = anonKey?.trimmingCharacters(in: .whitespacesAndNewlines), isUsableValue(key)
        else {
            state.withLock { $0 = nil }
            return false
        }
        let options = SupabaseClientOptions(
            auth: .init(
                storageKey: storageKey,
                // 新行为: 冷启动先交出本地 session (哪怕过期), 由我们在 bootstrap 里决定是否刷新。
                // 不设的话 supabase-swift 每次启动都会打一条弃用警告。
                emitLocalSessionAsInitialSession: true
            )
        )
        let client = SupabaseClient(supabaseURL: url, supabaseKey: key, options: options)
        state.withLock { $0 = Configured(client: client, url: url) }
        return true
    }

    /// 从 Info.plist 字符串配置。
    ///
    /// xcconfig 里 `//` 会被当成注释, 所以常见写法是只填主机名 (`data.weshici.com`) 或 `https:/$()/...`;
    /// 这里两种都接: 没有 scheme 时补 `https://`。空串与未展开的 `$(SUPABASE_URL)` 视为缺失。
    @discardableResult
    public static func configure(urlString: String?, anonKey: String?, storageKey: String? = nil) -> Bool {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), isUsableValue(raw) else {
            return configure(url: nil, anonKey: anonKey, storageKey: storageKey)
        }
        let withScheme = raw.contains("://") ? raw : "https://\(raw)"
        return configure(url: URL(string: withScheme), anonKey: anonKey, storageKey: storageKey)
    }

    /// 直接注入一个已建好的客户端 (需要自定义 URLSession / logger 时用)。
    public static func configure(client: SupabaseClient, url: URL) {
        state.withLock { $0 = Configured(client: client, url: url) }
    }

    /// 回到离线模式。测试用, App 一般不需要。
    public static func reset() {
        state.withLock { $0 = nil }
    }

    /// 空串、未展开的构建变量、明显的占位符都不算配置。
    static func isUsableValue(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if value.hasPrefix("$(") { return false }
        let upper = value.uppercased()
        return !(upper.contains("YOUR_") || upper.contains("PLACEHOLDER") || upper == "TODO")
    }
}
