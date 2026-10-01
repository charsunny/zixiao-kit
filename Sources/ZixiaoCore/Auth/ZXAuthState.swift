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
    /// 昵称 (user_metadata 的 `display_name`, 缺省回落 `full_name` / `name`), 已去首尾空白; 没填为 nil。
    /// 见 `ZXUserMetadata`。
    public var displayName: String?
    /// 程序化头像的样式序号 (user_metadata 的 `avatar_style`); 没选过为 nil。序号由 App 解释。
    public var avatarStyle: Int?

    public init(id: String, isAnonymous: Bool, providers: Set<ZXProvider> = [], phone: String? = nil,
                email: String? = nil, displayName: String? = nil, avatarStyle: Int? = nil) {
        self.id = id.lowercased()
        self.isAnonymous = isAnonymous
        self.providers = providers
        self.phone = phone
        self.email = email
        self.displayName = ZXUserMetadata.normalizedName(displayName)
        self.avatarStyle = avatarStyle.flatMap { $0 >= 0 ? $0 : nil }
    }

    /// 从 user_metadata 取资料字段的便捷构造 (后端实现与测试用)。
    public init(id: String, isAnonymous: Bool, providers: Set<ZXProvider> = [], phone: String? = nil,
                email: String? = nil, metadata: [String: ZXJSONValue]) {
        self.init(id: id, isAnonymous: isAnonymous, providers: providers, phone: phone, email: email,
                  displayName: ZXUserMetadata.displayName(in: metadata),
                  avatarStyle: ZXUserMetadata.avatarStyle(in: metadata))
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

extension ZXAuthUser {
    /// 子晓系服务端代理登录 (微诗 `createMobileSession`) 给 GoTrue 用户配的合成邮箱域名
    /// (`profile-<hash>@auth.weshici.local`)。它不是用户的邮箱, 不算「已绑定邮箱」, 也不显示。
    public static let brokerEmailDomain = "auth.weshici.local"

    /// 从 GoTrue 用户的各字段推出我们的用户 (与 supabase-swift 类型无关, 便于单测)。
    ///
    /// - identity 列表里认得的 provider 直接算;
    /// - 手机号 / 邮箱以确认时间兜底 (老 GoTrue 的 phone_change 不建 phone identity); 合成邮箱除外;
    /// - `app_metadata.google_sub` → Google (Android 端自家中转);
    /// - `user_metadata.zx_apple_linked == true` → Apple (经 `ZXAppleExchange` 登录过)。
    public static func fromGoTrue(id: String, isAnonymous: Bool, identityProviders: [String],
                                  phone: String?, phoneConfirmed: Bool,
                                  email: String?, emailConfirmed: Bool,
                                  appMetadata: [String: ZXJSONValue],
                                  userMetadata: [String: ZXJSONValue]) -> ZXAuthUser {
        let phone = phone.flatMap { $0.isEmpty ? nil : $0 }
        let email = email.flatMap { $0.isEmpty || isBrokerEmail($0) ? nil : $0 }
        var providers = Set(identityProviders.compactMap { ZXProvider(rawValue: $0) })
        if email == nil { providers.remove(.email) }
        if phoneConfirmed, phone != nil { providers.insert(.phone) }
        if emailConfirmed, email != nil { providers.insert(.email) }
        if case .string? = appMetadata["google_sub"] { providers.insert(.google) }
        if case .bool(true)? = userMetadata[ZXUserMetadata.appleLinkedKey] { providers.insert(.apple) }
        return ZXAuthUser(id: id, isAnonymous: isAnonymous, providers: providers, phone: phone, email: email,
                          metadata: userMetadata)
    }

    /// 是否为服务端代理登录的合成邮箱。
    public static func isBrokerEmail(_ email: String) -> Bool {
        email.lowercased().hasSuffix("@" + brokerEmailDomain)
    }
}
