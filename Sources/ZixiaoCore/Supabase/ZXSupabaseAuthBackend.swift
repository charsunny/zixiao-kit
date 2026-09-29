import Foundation
import Supabase

/// `ZXAuthBackend` 的 supabase-swift 2.x 实现。整个内核里只有这里 (与离线队列的 transport) 直接调 Auth API。
///
/// 用到的 supabase-swift 方法:
/// - `auth.session` / `auth.currentUser` —— 恢复钥匙串里的 session (默认 `KeychainLocalStorage`, 自动持久化);
/// - `auth.signInAnonymously()`;
/// - `auth.linkIdentityWithIdToken(credentials:)` —— Apple 原生面板拿到的 id token 绑到当前用户;
/// - `auth.update(user: UserAttributes(phone:))` + `auth.verifyOTP(phone:token:type: .phoneChange)` —— 手机号绑定;
/// - `auth.signInWithIdToken(credentials:)`、`auth.signInWithOTP(phone:shouldCreateUser: false)` +
///   `auth.verifyOTP(phone:token:type: .sms)` —— 仅用于「找回旧账号」, 会换 user id (见 `ZXAuth.signInWithApple`);
/// - `auth.signOut(scope:)`; `rpc("zen_delete_account")`。
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
    private let deleteAccountRPC: String

    public init(deleteAccountRPC: String = ZXSupabaseAuthBackend.defaultDeleteAccountRPC) {
        self.init(deleteAccountRPC: deleteAccountRPC, client: { try ZXSupabase.requireClient() })
    }

    /// 注入客户端来源。默认每次调用都去读 `ZXSupabase`, 所以 App 晚于 `ZXAuth` 初始化配置也没关系。
    public init(deleteAccountRPC: String = ZXSupabaseAuthBackend.defaultDeleteAccountRPC,
                client: @escaping @Sendable () throws -> SupabaseClient) {
        self.clientProvider = client
        self.deleteAccountRPC = deleteAccountRPC
    }

    public var isConfigured: Bool { (try? clientProvider()) != nil }

    public func restoreSession() async throws -> ZXAuthUser? {
        let client = try clientProvider()
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
            throw Self.map(error)
        }
    }

    public func signInAnonymously() async throws -> ZXAuthUser {
        let client = try clientProvider()
        do {
            return ZXAuthUser(try await client.auth.signInAnonymously().user)
        } catch {
            throw Self.map(error)
        }
    }

    public func linkApple(idToken: String, nonce: String) async throws -> ZXAuthUser {
        let client = try clientProvider()
        do {
            // linkIdentityWithIdToken 会带上当前 session 的 Bearer 并置 link_identity=true,
            // GoTrue 因而把 Apple identity 挂到当前用户, 而不是按 Apple 邮箱另找 / 另建用户。
            // 需要服务端开 GOTRUE_SECURITY_MANUAL_LINKING_ENABLED (现行后端的 Apple 绑定已在用)。
            let session = try await client.auth.linkIdentityWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
            return ZXAuthUser(session.user)
        } catch {
            throw Self.map(error, provider: .apple)
        }
    }

    public func requestPhoneLink(phone: String) async throws {
        let client = try clientProvider()
        do {
            try await client.auth.update(user: UserAttributes(phone: phone))
        } catch {
            throw Self.map(error, provider: .phone)
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
            throw Self.map(error, provider: .phone)
        }
    }

    public func signInWithApple(idToken: String, nonce: String) async throws -> ZXAuthUser {
        let client = try clientProvider()
        do {
            // 与 linkIdentityWithIdToken 同一个 /token?grant_type=id_token, 只是不带 link_identity 与当前 Bearer:
            // GoTrue 据 Apple 的 sub 找到它所属的账号并签发那个账号的 session。
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
            return ZXAuthUser(session.user)
        } catch {
            throw Self.map(error, provider: .apple)
        }
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
            throw Self.map(error, provider: .phone)
        }
    }

    public func verifyPhoneSignIn(phone: String, code: String) async throws -> ZXAuthUser {
        let client = try clientProvider()
        do {
            let response = try await client.auth.verifyOTP(phone: phone, token: code, type: .sms)
            return ZXAuthUser(response.user)
        } catch {
            throw Self.map(error, provider: .phone)
        }
    }

    public func signOut() async throws {
        let client = try clientProvider()
        do {
            // supabase-swift 先删本地 session 再调 /logout, 所以就算这里抛了, 本地也已经退出了。
            try await client.auth.signOut()
        } catch {
            throw Self.map(error)
        }
    }

    public func deleteAccount() async throws {
        let client = try clientProvider()
        do {
            try await client.rpc(deleteAccountRPC).execute()
        } catch {
            throw Self.map(error)
        }
        // auth.users 行已删, 服务端 /logout 会回 401/404 (SDK 会吞掉); 只需清本地。
        try? await client.auth.signOut(scope: .local)
    }

    // MARK: - 映射

    /// refresh 失败且是服务端明确拒绝 (4xx, 限流除外): session 已作废。
    static func isDeadSession(_ error: AuthError) -> Bool {
        guard case let .api(_, _, _, response) = error else { return false }
        return (400..<500).contains(response.statusCode) && response.statusCode != 429
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
        var providers = Set((user.identities ?? []).compactMap { ZXProvider(rawValue: $0.provider) })
        // identity 列表不一定可靠 (老 GoTrue 的 phone_change 不建 phone identity), 以确认时间兜底。
        if user.phoneConfirmedAt != nil, let phone = user.phone, !phone.isEmpty { providers.insert(.phone) }
        if user.emailConfirmedAt != nil, let email = user.email, !email.isEmpty { providers.insert(.email) }
        if case .string? = user.appMetadata["google_sub"] { providers.insert(.google) }
        self.init(id: user.id.uuidString, isAnonymous: user.isAnonymous, providers: providers,
                  phone: user.phone.flatMap { $0.isEmpty ? nil : $0 },
                  email: user.email.flatMap { $0.isEmpty ? nil : $0 })
    }
}
