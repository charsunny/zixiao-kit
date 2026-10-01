import Foundation

/// 认证后端的最小接口。`ZXAuth` 只经它说话, 生产用 `ZXSupabaseAuthBackend`, 测试用 mock, 不联网。
///
/// 为什么切在这一层而不是 mock `SupabaseClient`: supabase-swift 的 `AuthClient` 是 actor 且不可继承,
/// 伪造它得起 HTTP 桩; 而状态机真正关心的只有「这一步之后用户是谁」, 抽成这几个方法就够测全部迁移。
///
/// 方法分两类: 「绑定」(link*) 必须保持 user id 不变; 「登录」(signIn*) 会换成另一个 user id,
/// 只用于找回旧账号, 见 `ZXAuth.signInWithApple` 的文档。
public protocol ZXAuthBackend: Sendable {
    /// 是否已配置后端 (未配置 = 离线模式)。
    var isConfigured: Bool { get }

    /// 恢复本地持久化的 session。没有 (或已被服务端作废) 返回 nil;
    /// 网络不通但本地有 session 时返回本地缓存的用户 —— 离线也要认得是谁。
    func restoreSession() async throws -> ZXAuthUser?

    /// 匿名登录, 建一个新的 auth.users 行。
    func signInAnonymously() async throws -> ZXAuthUser

    /// 把 Apple 身份绑到当前用户。`nonce` 是原文 (Apple 那边收到的是它的 sha256)。
    func linkApple(idToken: String, nonce: String) async throws -> ZXAuthUser

    /// 给当前用户申请绑定手机号: 服务端向新号码发验证码。
    func requestPhoneLink(phone: String) async throws

    /// 用验证码确认绑定, 返回绑定后的用户。
    func verifyPhoneLink(phone: String, code: String) async throws -> ZXAuthUser

    // MARK: 找回旧账号 (会换 user id)

    /// 用 Apple 身份登录其所属的账号 (不存在则服务端新建)。
    func signInWithApple(idToken: String, nonce: String) async throws -> ZXAuthUser

    /// 向手机号发登录验证码。只登录已存在的账号, 不新建。
    func requestPhoneSignIn(phone: String) async throws

    /// 用验证码登录手机号所属的账号。
    func verifyPhoneSignIn(phone: String, code: String) async throws -> ZXAuthUser

    /// 退出。本地 session 必须清掉, 服务端注销尽力而为。
    func signOut() async throws

    /// 删除当前账号 (服务端级联删除所有用户数据), 并清掉本地 session。
    func deleteAccount() async throws

    // MARK: 资料

    /// 把 `data` 合并进当前用户的 user_metadata (GoTrue `PUT /user`, 按顶层键合并, `null` 删键),
    /// 返回更新后的用户。键名见 `ZXUserMetadata`。
    func updateUserMetadata(_ data: [String: ZXJSONValue]) async throws -> ZXAuthUser
}

extension ZXAuthBackend {
    /// 默认实现: 不支持。老的 mock / 预览后端不必跟着改; 要支持资料编辑的后端自己实现。
    public func updateUserMetadata(_ data: [String: ZXJSONValue]) async throws -> ZXAuthUser {
        throw ZXCoreError.providerDisabled
    }
}

/// 后端失败 + 底层原文。
///
/// `ZXCoreError` 是给界面「该说哪句话」的, 映射时会丢掉 GoTrue 的原始 message / error_code / HTTP 状态
/// (如 `.providerDisabled`)。排查服务端配置 (比如 Apple provider 没开) 时又恰恰要看原文, 所以后端抛这个包装:
/// `ZXAuth` 把 `detail` 记进 `lastErrorDetail`, 对外仍只抛 `error` —— App 侧的错误类型契约不变。
/// `ZXCoreError(_:)` 也认得它 (直接取 `error`), 绕过 `ZXAuth` 直接用后端的地方照样拿到 `ZXCoreError`。
public struct ZXAuthFailure: Error, Sendable, Hashable {
    /// 映射后的错误 (界面用)。
    public let error: ZXCoreError
    /// 底层原文, 如 `Unsupported provider: provider is not enabled (validation_failed · HTTP 400)`。
    public let detail: String

    public init(_ error: ZXCoreError, detail: String) {
        self.error = error
        self.detail = detail
    }
}
