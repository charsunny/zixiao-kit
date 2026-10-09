import Foundation
import Supabase

/// `ZXAuthBackend` 的 supabase-swift 2.x 实现。整个内核里只有这里 (与离线队列的 transport) 直接调 Auth API。
///
/// 用到的 supabase-swift 方法:
/// - `auth.session` / `auth.currentUser` —— 恢复钥匙串里的 session (默认 `KeychainLocalStorage`, 自动持久化);
/// - `auth.signInAnonymously()`;
/// - `auth.setSession(accessToken:refreshToken:)` —— Apple 登录 (`linkApple` / `signInWithApple`): 不走 GoTrue 的
///   Apple provider (阿里云托管的 GoTrue 没开, 回 `provider_disabled`), 而是把 Apple id token 交给子晓系共用的
///   服务端换 session (`ZXAppleExchange`, 现由微诗 web 提供), 拿回同一 Supabase 项目的 session 再 setSession。
///   换来的是「这个 Apple ID 在子晓系账号体系里的那个人」, 通常**不是**当前匿名用户 —— 即账号切换, 见 `ZXAuth.linkApple`;
/// - `auth.update(user: UserAttributes(phone:))` + `auth.verifyOTP(phone:token:type: .phoneChange)` —— 手机号绑定;
/// - `auth.signInWithOTP(phone:shouldCreateUser: false)` + `auth.verifyOTP(phone:token:type: .sms)` ——
///   仅用于「找回旧账号」, 会换 user id (见 `ZXAuth.signInWithApple` 上方说明);
/// - `auth.update(user: UserAttributes(data:))` —— 昵称 / 头像样式写进 user_metadata (键名见 `ZXUserMetadata`);
/// - `auth.signOut(scope:)`; 默认经 HTTP 删号入口先清私有媒体，再删账号；显式 RPC 注入保留旧兼容路径。
///
/// 失败一律抛 `ZXAuthFailure` (映射后的 `ZXCoreError` + GoTrue 原文), `ZXAuth` 把原文记进 `lastErrorDetail`。
///
/// ### 为什么手机号绑定不用 `signInWithOTP(phone:)` + `verifyOTP(type: .sms)`
/// 查过 supabase-swift 源码 (AuthClient.swift): `signInWithOTP(phone:)` 走 `api.execute` 打 `POST /otp`,
/// **不带当前用户的 Bearer**; GoTrue 据手机号找用户, 找不到就 (shouldCreateUser) 新建一个 ——
/// 于是随后的 `verifyOTP(type: .sms)` 会登进一个**新的 user id**, 匿名账号下的数据全部留在旧 id 上。
/// 这正是 PoetKit/Auth.swift 的做法, 它能接受是因为它有「设备行并入账号」的迁移; 我们的 `zen_*` 表没有。
///
/// 正确路径是 Supabase 文档「把匿名用户转为永久用户」那条:
/// 1. `update(user: UserAttributes(phone:))` 走 `authorizedExecute` 打 `PUT /user`, 带当前匿名用户的 Bearer,
///    GoTrue 把号码记进该用户的 `phone_change` 并发 phone_change 短信 (与登录短信同一个 SMS 通道);
/// 2. `verifyOTP(phone:token:type: .phoneChange)` 打 `POST /verify`, GoTrue 按 `phone_change` 找到的就是
///    **原来那个用户**, 确认号码、清掉 is_anonymous, 并给同一 user id 签发新 session。
/// `ZXAuth` 仍会在第 2 步后核对 user id 未变, 作为双保险。
public struct ZXSupabaseAuthBackend: ZXAuthBackend {
    /// 现行 schema 的删号 RPC (0011_delete_account.sql)。
    /// SECURITY DEFINER 删 auth.users 行, 所有 `zen_*` 表 on delete cascade 跟着走。
    /// 架构决定 7: Sprint 2 沿用 `zen_*`, 矩阵契约 (app_slug) 定下来后由 App 注入新名字。
    public static let defaultDeleteAccountRPC = "zen_delete_account"

    private let clientProvider: @Sendable () throws -> SupabaseClient
    private let deleteAccountRPC: String?
    private let appleExchangeProvider: @Sendable () throws -> ZXAppleExchange
    private let accountDeletionProvider: @Sendable () -> ZXAccountDeletion
    /// Uses the locally persisted user even if the access token has expired.
    /// Token validation/refresh still happens when an authenticated request runs.
    private let preferCachedSession: Bool

    public init(deleteAccountRPC: String? = nil,
                appleExchange: @escaping @Sendable () throws -> ZXAppleExchange = { try ZXAppleExchange.current() },
                accountDeletion: @escaping @Sendable () -> ZXAccountDeletion = { ZXAccountDeletion.current() },
                preferCachedSession: Bool = false) {
        self.init(deleteAccountRPC: deleteAccountRPC, client: { try ZXSupabase.requireClient() },
                  appleExchange: appleExchange, accountDeletion: accountDeletion, preferCachedSession: preferCachedSession)
    }

    /// 注入客户端来源。默认每次调用都去读 `ZXSupabase` / `ZXAppleExchange` 的全局配置,
    /// 所以 App 晚于 `ZXAuth` 初始化配置也没关系。
    public init(deleteAccountRPC: String? = nil,
                client: @escaping @Sendable () throws -> SupabaseClient,
                appleExchange: @escaping @Sendable () throws -> ZXAppleExchange = { try ZXAppleExchange.current() },
                accountDeletion: @escaping @Sendable () -> ZXAccountDeletion = { ZXAccountDeletion.current() },
                preferCachedSession: Bool = false) {
        self.clientProvider = client
        self.deleteAccountRPC = deleteAccountRPC
        self.appleExchangeProvider = appleExchange
        self.accountDeletionProvider = accountDeletion
        self.preferCachedSession = preferCachedSession
    }

    public var isConfigured: Bool { (try? clientProvider()) != nil }

    public func restoreSession() async throws -> ZXAuthUser? {
        let client = try clientProvider()
        // AuthClient.currentUser reads SessionStorage synchronously, whereas
        // auth.session refreshes an expired token over the network.
        if preferCachedSession { return client.auth.currentUser.map(ZXAuthUser.init) }
        do {
            // 未过期直接返回本地的; 过期则用 refresh token 换新的。
            return ZXAuthUser(try await client.auth.session.user)
        } catch AuthError.sessionMissing {
            return nil
        } catch let error as AuthError where Self.isDeadSession(error) {
            // refresh token 被撤销 / 账号在别处删了: 这份 session 永远救不回来。
            // supabase-swift 刷新失败时不会自己删本地 session, 这里清掉, 让 bootstrap 重新匿名登录。
            try? await client.auth.signOut(scope: .local)
            return nil
        } catch {
            // 网络问题: 本地还有 session 就先认这个人, 等联网后 SDK 的自动刷新会接上。
            if let user = client.auth.currentUser { return ZXAuthUser(user) }
            throw Self.failure(error)
        }
    }

    public func signInAnonymously() async throws -> ZXAuthUser {
        let client = try clientProvider()
        do {
            return ZXAuthUser(try await client.auth.signInAnonymously().user)
        } catch {
            throw Self.failure(error)
        }
    }

    /// 子晓系账号统一后, Apple「绑定」与「登录」是同一件事: 换到这个 Apple ID 所属的账号 (服务端没有就新建)。
    /// 返回的用户一般与当前匿名用户不同 —— `ZXAuth.linkApple` 按账号切换收尾。
    public func linkApple(idToken: String, nonce: String) async throws -> ZXAuthUser {
        try await exchangeApple(idToken: idToken, nonce: nonce)
    }

    public func requestPhoneLink(phone: String) async throws {
        let client = try clientProvider()
        do {
            try await client.auth.update(user: UserAttributes(phone: phone))
        } catch {
            throw Self.failure(error, provider: .phone)
        }
    }

    public func verifyPhoneLink(phone: String, code: String) async throws -> ZXAuthUser {
        let client = try clientProvider()
        do {
            // GoTrue 对 phone_change 的 /verify 会给同一用户签发 session (AuthResponse.session),
            // SDK 已把它存进钥匙串; `response.user` 两种分支都有, 就是确认后的用户。
            let response = try await client.auth.verifyOTP(phone: phone, token: code, type: .phoneChange)
            return ZXAuthUser(response.user)
        } catch {
            throw Self.failure(error, provider: .phone)
        }
    }

    public func signInWithApple(idToken: String, nonce: String) async throws -> ZXAuthUser {
        try await exchangeApple(idToken: idToken, nonce: nonce)
    }

    /// Apple id token → 服务端换 session → `setSession`。
    ///
    /// 1. `ZXAppleExchange` 把 token 交给服务端 (失败抛 `ZXAuthFailure`, detail 是服务端 JSON 的 `error` 原文);
    /// 2. `setSession`: token 未过期时 SDK 用它 `GET /user` 取用户, 并把 session 存进钥匙串 (之后自动刷新照常);
    /// 3. 服务端签的是「代理登录」用户 (合成邮箱、无 Apple identity), GoTrue 看不出它是 Apple 登录的,
    ///    所以第一次换进来时在 user_metadata 记一笔 `zx_apple_linked` (见 `ZXUserMetadata.appleLinkedKey`),
    ///    冷启动恢复 session 时「绑定方式」才认得出 Apple。记不上 (断网等) 不算失败, 本次结果照样带 `.apple`。
    func exchangeApple(idToken: String, nonce: String, fullName: String? = nil) async throws -> ZXAuthUser {
        let client = try clientProvider()
        let exchange = try appleExchangeProvider()
        let tokens = try await exchange.exchange(idToken: idToken, nonce: nonce, fullName: fullName)
        var user: User
        do {
            user = try await client.auth.setSession(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken)
                .user
        } catch {
            throw Self.failure(error, provider: .apple)
        }
        if user.userMetadata[ZXUserMetadata.appleLinkedKey] != .bool(true),
           let marked = try? await client.auth.update(
               user: UserAttributes(data: [ZXUserMetadata.appleLinkedKey: .bool(true)])
           ) {
            user = marked
        }
        var result = ZXAuthUser(user)
        result.providers.insert(.apple)
        return result
    }

    public func requestPhoneSignIn(phone: String) async throws {
        let client = try clientProvider()
        do {
            // shouldCreateUser: false —— 找回路径只该登进已有账号。号码下没有账号时若顺手新建,
            // 用户会以为「找回来了」却面对一个空账号, 还白白丢了当前匿名数据。
            try await client.auth.signInWithOTP(phone: phone, shouldCreateUser: false)
        } catch let AuthError.api(_, code, _, _) where code == .otpDisabled || code == .userNotFound {
            // GoTrue 对「不许新建且用户不存在」回 otp_disabled (Signups not allowed for otp)。
            throw ZXCoreError.accountNotFound
        } catch {
            throw Self.failure(error, provider: .phone)
        }
    }

    public func verifyPhoneSignIn(phone: String, code: String) async throws -> ZXAuthUser {
        let client = try clientProvider()
        do {
            let response = try await client.auth.verifyOTP(phone: phone, token: code, type: .sms)
            return ZXAuthUser(response.user)
        } catch {
            throw Self.failure(error, provider: .phone)
        }
    }

    public func signOut() async throws {
        let client = try clientProvider()
        do {
            // supabase-swift 先删本地 session 再调 /logout, 所以就算这里抛了, 本地也已经退出了。
            try await client.auth.signOut()
        } catch {
            throw Self.failure(error)
        }
    }

    public func deleteAccount() async throws {
        let client = try clientProvider()
        do {
            if let deleteAccountRPC {
                try await client.rpc(deleteAccountRPC).execute()
            } else {
                let token = try await client.auth.session.accessToken
                try await accountDeletionProvider().delete(accessToken: token)
            }
        } catch {
            if let failure = error as? ZXAuthFailure { throw failure }
            throw Self.failure(error)
        }
        // auth.users 行已删, 服务端 /logout 会回 401/404 (SDK 会吞掉); 只需清本地。
        try? await client.auth.signOut(scope: .local)
    }

    public func updateUserMetadata(_ data: [String: ZXJSONValue]) async throws -> ZXAuthUser {
        let client = try clientProvider()
        do {
            // PUT /user 带当前 Bearer; GoTrue 把 data 的顶层键并进 user_metadata (null 删键), 返回整个用户,
            // SDK 同时把它写回本地 session —— 离线重启后 restoreSession 拿到的也是新资料。
            let user = try await client.auth.update(user: UserAttributes(data: data.mapValues { AnyJSON(zx: $0) }))
            return ZXAuthUser(user)
        } catch {
            throw Self.failure(error)
        }
    }

    // MARK: - 映射

    /// refresh 失败且是服务端明确拒绝 (4xx, 限流除外): session 已作废。
    static func isDeadSession(_ error: AuthError) -> Bool {
        guard case let .api(_, _, _, response) = error else { return false }
        return (400..<500).contains(response.statusCode) && response.statusCode != 429
    }

    /// 映射 + 保留底层原文 (`ZXAuthFailure`)。我们自己的 `ZXCoreError` (如 `.accountNotFound`) 原样抛。
    static func failure(_ error: any Error, provider: ZXProvider? = nil) -> any Error {
        if let own = error as? ZXCoreError { return own }
        return ZXAuthFailure(map(error, provider: provider), detail: detail(of: error))
    }

    /// 底层原文。GoTrue 的 API 错误带上 error_code 与 HTTP 状态, 如
    /// `Unsupported provider: provider is not enabled (validation_failed · HTTP 400)`。
    static func detail(of error: any Error) -> String {
        guard let auth = error as? AuthError else {
            let text = (error as NSError).localizedDescription
            return text.isEmpty ? String(describing: error) : text
        }
        if case let .api(message, code, _, response) = auth {
            var tags: [String] = []
            if !code.rawValue.isEmpty, code != .unknown { tags.append(code.rawValue) }
            tags.append("HTTP \(response.statusCode)")
            return "\(message) (\(tags.joined(separator: " · ")))"
        }
        return auth.message
    }

    /// GoTrue 错误码 → 界面能说的话。
    static func map(_ error: any Error, provider: ZXProvider? = nil) -> ZXCoreError {
        if let own = error as? ZXCoreError { return own }
        guard let auth = error as? AuthError else { return ZXCoreError(error) }
        switch auth {
        case .sessionMissing:
            return .notSignedIn
        case let .api(message, code, _, _):
            switch code {
            case .identityAlreadyExists, .phoneExists, .emailExists:
                return .identityInUse(provider ?? .phone)
            case .otpExpired:
                return .invalidCode
            case .overSMSSendRateLimit, .overRequestRateLimit:
                return .rateLimited
            case .anonymousProviderDisabled, .phoneProviderDisabled, .manualLinkingDisabled:
                return .providerDisabled
            default:
                return .backend(message)
            }
        default:
            return .backend(auth.localizedDescription)
        }
    }
}

extension ZXAuthUser {
    /// 从 GoTrue 用户抽出我们关心的部分。
    init(_ user: User) {
        self = ZXAuthUser.fromGoTrue(
            id: user.id.uuidString, isAnonymous: user.isAnonymous,
            identityProviders: (user.identities ?? []).map(\.provider),
            phone: user.phone, phoneConfirmed: user.phoneConfirmedAt != nil,
            email: user.email, emailConfirmed: user.emailConfirmedAt != nil,
            appMetadata: user.appMetadata.mapValues { ZXJSONValue(supabase: $0) },
            userMetadata: user.userMetadata.mapValues { ZXJSONValue(supabase: $0) }
        )
    }
}

// MARK: - ZXJSONValue ⇄ AnyJSON

extension ZXJSONValue {
    init(supabase json: AnyJSON) {
        switch json {
        case .null: self = .null
        case .bool(let v): self = .bool(v)
        case .integer(let v): self = .int(v)
        case .double(let v): self = .double(v)
        case .string(let v): self = .string(v)
        case .array(let v): self = .array(v.map { ZXJSONValue(supabase: $0) })
        case .object(let v): self = .object(v.mapValues { ZXJSONValue(supabase: $0) })
        }
    }
}

extension AnyJSON {
    init(zx value: ZXJSONValue) {
        switch value {
        case .null: self = .null
        case .bool(let v): self = .bool(v)
        case .int(let v): self = .integer(v)
        case .double(let v): self = .double(v)
        case .string(let v): self = .string(v)
        case .array(let v): self = .array(v.map { AnyJSON(zx: $0) })
        case .object(let v): self = .object(v.mapValues { AnyJSON(zx: $0) })
        }
    }
}
