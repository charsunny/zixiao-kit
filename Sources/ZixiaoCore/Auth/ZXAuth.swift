import Foundation
import Observation

/// 账号: 匿名优先, 之后绑定 Apple / 手机号, user id 始终不变 (架构决定 7)。
///
/// 为什么 @MainActor @Observable 而不是 actor: 它的全部意义是驱动界面 (登录页、我的页的「已绑定」),
/// 状态放在主线程上 SwiftUI 可直接观察; 真正的网络活在 `ZXAuthBackend` 里, 不占主线程。
///
/// App 侧用法:
/// ```swift
/// ZXSupabase.configure(urlString: info["SUPABASE_URL"], anonKey: info["SUPABASE_ANON_KEY"])
/// let auth = ZXAuth(outbox: outbox)
/// await auth.bootstrap()     // 启动时一次; 不抛错, 失败记在 bootstrapError, 不挡路由
/// ```
@MainActor
@Observable
public final class ZXAuth {
    /// 当前状态。
    public private(set) var state: ZXAuthState = .signedOut
    /// 当前用户的详情 (手机号、邮箱), 给「我的」页显示。
    public private(set) var user: ZXAuthUser?
    /// 首次 bootstrap 已经结束 (成功或放弃)。冷启动时路由可据此决定是否还显示加载。
    public private(set) var isBootstrapped = false
    /// 最近一次 bootstrap 的失败原因; 成功后清空。`.offline` 表示未配置后端。
    public private(set) var bootstrapError: ZXCoreError?
    /// 未配置后端 (离线模式)。
    public private(set) var isOffline: Bool
    /// 已发出绑定验证码、等待填写的手机号 (E.164)。
    public private(set) var pendingPhone: String?
    /// 已发出「找回账号」登录验证码、等待填写的手机号 (E.164)。与绑定分开, 免得界面把两个流程搅在一起。
    public private(set) var pendingSignInPhone: String?

    @ObservationIgnored private let backend: any ZXAuthBackend
    @ObservationIgnored private let outbox: ZXOutbox?
    @ObservationIgnored private let bootstrapTimeout: Duration
    @ObservationIgnored private var bootstrapTask: Task<ZXAuthState, Never>?

    /// - Parameters:
    ///   - backend: 默认走 `ZXSupabase` 的配置; 测试注入 mock。
    ///   - outbox: 传入后, 用户一变就调 `setOwner`, 队列只替当前用户补传, 换账号时丢弃上一位的待传写入。
    ///   - bootstrapTimeout: 启动时每一步网络的上限, 后端不通时不能把启动挂死 (Flutter 版取 6 秒)。
    public init(backend: any ZXAuthBackend = ZXSupabaseAuthBackend(), outbox: ZXOutbox? = nil,
                bootstrapTimeout: Duration = .seconds(6)) {
        self.backend = backend
        self.outbox = outbox
        self.bootstrapTimeout = bootstrapTimeout
        self.isOffline = !backend.isConfigured
    }

    public var userId: String? { state.userId }
    /// 匿名用户退出就再也回不来 (没有任何可以登回去的身份), 界面上退出前要据此提醒。
    public var signOutLosesData: Bool { state.isAnonymous }

    // MARK: - 启动

    /// 恢复 session; 没有则匿名登录。可重复调用: 并发调用共享同一次尝试, 已登录时只是刷新一次用户。
    ///
    /// 不抛错: 后端不通时 App 照常进入 (离线可用), 失败原因留在 `bootstrapError`, 联网后再调一次即可。
    @discardableResult
    public func bootstrap() async -> ZXAuthState {
        if let running = bootstrapTask { return await running.value }
        let task = Task { await self.runBootstrap() }
        bootstrapTask = task
        let result = await task.value
        bootstrapTask = nil
        return result
    }

    private func runBootstrap() async -> ZXAuthState {
        defer { isBootstrapped = true }
        isOffline = !backend.isConfigured
        guard !isOffline else {
            bootstrapError = .offline
            return state
        }
        let backend = self.backend
        do {
            let restored = try await withTimeout(bootstrapTimeout) { try await backend.restoreSession() }
            if let restored {
                await apply(restored)
            } else {
                let fresh = try await withTimeout(bootstrapTimeout) { try await backend.signInAnonymously() }
                await apply(fresh)
            }
            bootstrapError = nil
        } catch {
            bootstrapError = ZXCoreError(error)
        }
        return state
    }

    // MARK: - 绑定

    /// 把 Apple 身份绑到当前 (通常是匿名) 用户上。`nonce` 传原文, 见 `ZXAppleSignIn`。
    ///
    /// - Throws: `.identityInUse(.apple)` 这个 Apple ID 已是别的账号; `.identityChanged` 绑完 user id 变了。
    public func linkApple(idToken: String, nonce: String) async throws {
        let before = try requireUser()
        do {
            let linked = try await backend.linkApple(idToken: idToken, nonce: nonce)
            try await acceptLinked(linked, before: before)
        } catch {
            throw ZXCoreError(error)
        }
    }

    /// 向手机号发验证码, 准备绑定到当前用户。11 位大陆号自动补 +86。
    ///
    /// 走的是「改手机号」(phone_change) 而非「短信登录」, 理由见 `ZXSupabaseAuthBackend` 文件头:
    /// 短信登录会换成另一个 user id。
    public func sendPhoneOTP(_ phone: String) async throws {
        guard let normalized = Self.normalizePhone(phone) else { throw ZXCoreError.invalidPhone }
        _ = try requireUser()
        do {
            try await backend.requestPhoneLink(phone: normalized)
            pendingPhone = normalized
        } catch {
            throw ZXCoreError(error)
        }
    }

    /// 用验证码确认绑定。成功后状态变为 `.linked(同一 userId, providers ∋ .phone)`。
    public func verifyPhoneOTP(_ phone: String, code: String) async throws {
        guard let normalized = Self.normalizePhone(phone) else { throw ZXCoreError.invalidPhone }
        let digits = try Self.validateCode(code)
        let before = try requireUser()
        do {
            let linked = try await backend.verifyPhoneLink(phone: normalized, code: digits)
            try await acceptLinked(linked, before: before)
            pendingPhone = nil
        } catch {
            throw ZXCoreError(error)
        }
    }

    // MARK: - 找回旧账号 (会换 user id)
    //
    // 场景: 用户换了设备 / 重装, bootstrap 给了一个新的匿名号; 他去绑 Apple 或手机号, 得到
    // `.identityInUse` —— 那个身份早已属于他的旧账号。此时「绑定」走不通 (一个身份只能属于一个账号),
    // 只能「登录」旧账号, 也就是换成另一个 user id。
    //
    // 代价: 当前匿名号上的一切 (云端 `zen_*` 行、离线队列里的待传写入、本地账号级态) 都会被放弃 ——
    // 匿名号没有任何可登回去的身份, 放弃就是永久的。所以:
    // 1. 这三个方法只应在收到 `.identityInUse` 之后、由界面明确询问并得到「放弃当前匿名数据」的确认后调用;
    //    不要把它们当作普通的登录入口, 也不要在 `.identityInUse` 时静默自动调用。
    // 2. 成功后自动把离线队列交给新用户 (`outbox.setOwner`), 旧匿名号的待传写入随之丢弃
    //    (它们带着旧 user_id, 以新身份补传要么被 RLS 拒、要么写错人)。
    // 3. 返回 `ZXAccountSwitch`, 其中 `abandonedUserId` 交给 App 清理本地态:
    //    `try await localState.remove(for: switch.abandonedUserId)`。设备级偏好 (如「历注」) 不受影响。
    // 4. 服务端上被放弃的匿名 auth.users 行不在这里删 (登录前删, 万一登录失败就两头落空);
    //    清理陈旧匿名用户是服务端定时任务的事。

    /// 用 Apple 身份登录其所属的旧账号, **放弃当前匿名账号**。调用前提与代价见上方说明。
    ///
    /// `nonce` 传原文。注意 Apple 的 id token 与 nonce 一次一用: 先前 `linkApple` 用过的那一对不能复用,
    /// 界面确认后要重新走一次 `ZXAppleSignIn` 拿新凭证。
    @discardableResult
    public func signInWithApple(idToken: String, nonce: String) async throws -> ZXAccountSwitch {
        guard backend.isConfigured else { throw ZXCoreError.offline }
        let previous = state.userId
        do {
            let user = try await backend.signInWithApple(idToken: idToken, nonce: nonce)
            return await acceptSwitch(to: user, from: previous)
        } catch {
            throw ZXCoreError(error)
        }
    }

    /// 向手机号发「找回账号」的登录验证码。只登录已有账号, 号码下没有账号时抛 `.accountNotFound`。
    /// 调用前提与代价见上方说明 (发码本身不改变任何状态, 真正换人在 `verifyPhoneSignIn`)。
    public func signInWithPhone(_ phone: String) async throws {
        guard let normalized = Self.normalizePhone(phone) else { throw ZXCoreError.invalidPhone }
        guard backend.isConfigured else { throw ZXCoreError.offline }
        do {
            try await backend.requestPhoneSignIn(phone: normalized)
            pendingSignInPhone = normalized
        } catch {
            throw ZXCoreError(error)
        }
    }

    /// 用验证码登录手机号所属的旧账号, **放弃当前匿名账号**。调用前提与代价见上方说明。
    @discardableResult
    public func verifyPhoneSignIn(_ phone: String, code: String) async throws -> ZXAccountSwitch {
        guard let normalized = Self.normalizePhone(phone) else { throw ZXCoreError.invalidPhone }
        let digits = try Self.validateCode(code)
        guard backend.isConfigured else { throw ZXCoreError.offline }
        let previous = state.userId
        do {
            let user = try await backend.verifyPhoneSignIn(phone: normalized, code: digits)
            let result = await acceptSwitch(to: user, from: previous)
            pendingSignInPhone = nil
            return result
        } catch {
            throw ZXCoreError(error)
        }
    }

    // MARK: - 退出与删号

    /// 退出。本地一定清掉; 服务端注销失败 (如断网) 不影响本地结果, 所以不抛错。
    /// 退出后状态是 `.signedOut`; 要继续用云端功能, App 再调一次 `bootstrap()` 即得一个新的匿名用户。
    public func signOut() async {
        if backend.isConfigured {
            try? await backend.signOut()
        }
        pendingPhone = nil
        pendingSignInPhone = nil
        await apply(nil)
    }

    /// 删除账号: 调服务端 RPC 级联删除全部用户数据, 再清本地 session。
    /// 本地账号级数据 (`ZXLocalUserState`) 由 App 按原 userId 调 `remove(for:)` 清理 —— 删号前先取 `userId`;
    /// 设备级偏好 (如「历注」) 不随之清理。
    public func deleteAccount() async throws {
        _ = try requireUser()
        do {
            try await backend.deleteAccount()
        } catch {
            throw ZXCoreError(error)
        }
        pendingPhone = nil
        pendingSignInPhone = nil
        await apply(nil)
    }

    // MARK: - 内部

    private func requireUser() throws -> String {
        guard backend.isConfigured else { throw ZXCoreError.offline }
        guard let id = state.userId else { throw ZXCoreError.notSignedIn }
        return id
    }

    /// 绑定类操作的共同收尾: 核对 user id 未变 (移植自 Flutter `AppleIdentityInvariant`)。
    /// 若真变了, 本地 session 已是另一个人, 状态如实跟过去 (否则后续写入会以错误的身份进行), 再抛错让界面说明。
    private func acceptLinked(_ user: ZXAuthUser, before: String) async throws {
        await apply(user)
        guard user.id == before else {
            throw ZXCoreError.identityChanged(before: before, after: user.id)
        }
    }

    /// 找回类操作的共同收尾: 换到新用户 (apply 里会 `outbox.setOwner`), 交出被放弃的旧 id。
    private func acceptSwitch(to user: ZXAuthUser, from previous: String?) async -> ZXAccountSwitch {
        pendingPhone = nil
        await apply(user)
        let abandoned = (previous != nil && previous != user.id) ? previous : nil
        return ZXAccountSwitch(user: user, abandonedUserId: abandoned)
    }

    /// 验证码只收 4–10 位 ASCII 数字 (GoTrue 默认 6 位), 两侧空白容忍。
    private nonisolated static func validateCode(_ code: String) throws -> String {
        let digits = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (4...10).contains(digits.count), digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else {
            throw ZXCoreError.invalidCode
        }
        return digits
    }

    private func apply(_ user: ZXAuthUser?) async {
        let previous = state.userId
        self.user = user
        state = ZXAuthState(user: user)
        if previous != state.userId || user == nil {
            await outbox?.setOwner(state.userId)
        }
    }

    /// 短信通道用 E.164。11 位 1 开头的裸号补 +86; 已带 + 的原样; 86 开头 13 位补 +。
    public nonisolated static func normalizePhone(_ raw: String) -> String? {
        let kept = raw.filter { $0.isASCII && ($0.isNumber || $0 == "+") }
        var candidate: String
        if kept.hasPrefix("+") {
            candidate = kept
        } else if kept.count == 11, kept.hasPrefix("1") {
            candidate = "+86" + kept
        } else if kept.count == 13, kept.hasPrefix("86") {
            candidate = "+" + kept
        } else if kept.hasPrefix("00") {
            candidate = "+" + kept.dropFirst(2)
        } else {
            return nil
        }
        let digits = candidate.dropFirst()
        guard (7...15).contains(digits.count), digits.first != "0", !digits.contains("+") else { return nil }
        return candidate
    }
}

/// 给一个网络步骤加上时限。超时按 `.network` 处理 (与断网同一句提示)。
func withTimeout<T: Sendable>(_ limit: Duration,
                              _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw ZXCoreError.network
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw ZXCoreError.network }
        return first
    }
}

/// 「找回旧账号」的结果。
public struct ZXAccountSwitch: Sendable, Hashable {
    /// 登录后的用户 (旧账号)。
    public let user: ZXAuthUser
    /// 被放弃的前一个 user id (通常是匿名号); App 用它清理本地账号级态。
    /// 之前没有用户、或登进的恰是同一个账号时为 nil —— 此时没有东西要清。
    public let abandonedUserId: String?

    public init(user: ZXAuthUser, abandonedUserId: String?) {
        self.user = user
        self.abandonedUserId = abandonedUserId
    }
}
