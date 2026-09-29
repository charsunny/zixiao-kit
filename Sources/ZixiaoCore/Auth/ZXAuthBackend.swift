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
}
