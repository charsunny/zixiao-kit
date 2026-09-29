import Foundation

/// 账号上绑定的登录方式。匿名本身不算一种 —— GoTrue 的匿名用户没有 identity。
public enum ZXProvider: String, Sendable, Hashable, Codable, CaseIterable {
    case apple
    case phone
    case email
    /// Android 端 Google 走自家服务端中转, 不是 GoTrue identity, 只在 `app_metadata.google_sub` 留痕。
    /// iOS 不提供 Google 入口, 列在这里只是为了同一账号在 iOS 上能正确显示「已绑定」。
    case google

    public var displayName: String {
        switch self {
        case .apple: return "Apple 账号"
        case .phone: return "手机号"
        case .email: return "邮箱"
        case .google: return "Google 账号"
        }
    }
}

/// 后端返回的用户, 已抹去 supabase-swift 的类型。
public struct ZXAuthUser: Sendable, Hashable, Codable {
    /// 小写 UUID 字符串, 与数据库里 `user_id` 列的写法一致 (Foundation 的 `uuidString` 是大写)。
    public var id: String
    public var isAnonymous: Bool
    public var providers: Set<ZXProvider>
    public var phone: String?
    public var email: String?

    public init(id: String, isAnonymous: Bool, providers: Set<ZXProvider> = [], phone: String? = nil,
                email: String? = nil) {
        self.id = id.lowercased()
        self.isAnonymous = isAnonymous
        self.providers = providers
        self.phone = phone
        self.email = email
    }
}

/// 账号状态机。
///
/// ```
///            bootstrap (无 session → 匿名登录)
/// signedOut ───────────────────────────────▶ anonymous(userId)
///     ▲                                           │ linkApple / verifyPhoneOTP (user id 不变)
///     │ signOut / deleteAccount                   ▼
///     └──────────────────────────────── linked(userId, providers)
/// ```
/// 关键不变量: anonymous → linked 时 userId 不变 —— 所有 `zen_*` 表按 user id 归属, 换了 id 就等于丢了数据。
public enum ZXAuthState: Sendable, Hashable {
    case signedOut
    case anonymous(userId: String)
    case linked(userId: String, providers: Set<ZXProvider>)

    public init(user: ZXAuthUser?) {
        guard let user else { self = .signedOut; return }
        // 以「有没有绑定方式」为准, 而不是只看 is_anonymous: 老版本 GoTrue 在 phone_change 之后
        // 不一定翻 is_anonymous, 但 phone_confirmed_at 一定有了。
        if user.providers.isEmpty && user.isAnonymous {
            self = .anonymous(userId: user.id)
        } else {
            self = .linked(userId: user.id, providers: user.providers)
        }
    }

    public var userId: String? {
        switch self {
        case .signedOut: return nil
        case .anonymous(let id), .linked(let id, _): return id
        }
    }

    public var isAnonymous: Bool {
        if case .anonymous = self { return true }
        return false
    }

    public var isSignedIn: Bool { userId != nil }

    public var providers: Set<ZXProvider> {
        if case .linked(_, let providers) = self { return providers }
        return []
    }
}
