import Foundation
@testable import ZixiaoCore

/// 可注入的认证后端: 按脚本返回, 记录调用, 不联网。
final class MockAuthBackend: ZXAuthBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _configured: Bool
    private var _stored: ZXAuthUser?
    private var _calls: [String] = []
    private var _nextAnonymousId = "aaaaaaaa-0000-0000-0000-000000000001"

    /// 各步骤的脚本化错误 / 结果。
    var restoreError: ZXCoreError?
    var signInError: ZXCoreError?
    var linkAppleResult: ((ZXAuthUser) -> Result<ZXAuthUser, ZXCoreError>)?
    var requestPhoneError: ZXCoreError?
    var verifyPhoneError: ZXCoreError?
    var signOutError: ZXCoreError?
    var restoreDelay: Duration?
    /// 带底层原文的后端失败 (模拟 `ZXSupabaseAuthBackend` 抛的 `ZXAuthFailure`)。
    var linkAppleFailure: ZXAuthFailure?
    var updateMetadataError: (any Error)?
    /// 最近一次 `updateUserMetadata` 收到的 patch。
    private var _lastMetadataPatch: [String: ZXJSONValue]?
    var lastMetadataPatch: [String: ZXJSONValue]? { lock.withLock { _lastMetadataPatch } }

    init(configured: Bool = true, stored: ZXAuthUser? = nil) {
        _configured = configured
        _stored = stored
    }

    var calls: [String] { lock.withLock { _calls } }
    var stored: ZXAuthUser? { lock.withLock { _stored } }
    func count(_ name: String) -> Int { calls.filter { $0.hasPrefix(name) }.count }

    private func record(_ call: String) { lock.withLock { _calls.append(call) } }
    private func setStored(_ user: ZXAuthUser?) { lock.withLock { _stored = user } }

    var isConfigured: Bool { lock.withLock { _configured } }

    func restoreSession() async throws -> ZXAuthUser? {
        record("restore")
        if let restoreDelay { try await Task.sleep(for: restoreDelay) }
        if let restoreError { throw restoreError }
        return stored
    }

    func signInAnonymously() async throws -> ZXAuthUser {
        record("signInAnonymously")
        // 让出一下, 使并发 bootstrap 真的交错。
        await Task.yield()
        if let signInError { throw signInError }
        let user = ZXAuthUser(id: _nextAnonymousId, isAnonymous: true)
        setStored(user)
        return user
    }

    func linkApple(idToken: String, nonce: String) async throws -> ZXAuthUser {
        record("linkApple:\(idToken):\(nonce)")
        if let linkAppleFailure { throw linkAppleFailure }
        guard let current = stored else { throw ZXCoreError.notSignedIn }
        if let script = linkAppleResult {
            let user = try script(current).get()
            setStored(user)
            return user
        }
        var user = current
        user.isAnonymous = false
        user.providers.insert(.apple)
        setStored(user)
        return user
    }

    func requestPhoneLink(phone: String) async throws {
        record("requestPhone:\(phone)")
        if let requestPhoneError { throw requestPhoneError }
    }

    func verifyPhoneLink(phone: String, code: String) async throws -> ZXAuthUser {
        record("verifyPhone:\(phone):\(code)")
        if let verifyPhoneError { throw verifyPhoneError }
        guard var user = stored else { throw ZXCoreError.notSignedIn }
        user.isAnonymous = false
        user.providers.insert(.phone)
        user.phone = phone
        setStored(user)
        return user
    }

    /// 「找回」时服务端上那个旧账号。nil 表示号码 / Apple ID 下没有账号。
    var existingAccount: ZXAuthUser?

    func signInWithApple(idToken: String, nonce: String) async throws -> ZXAuthUser {
        record("signInWithApple:\(idToken):\(nonce)")
        guard let existingAccount else { throw ZXCoreError.accountNotFound }
        setStored(existingAccount)
        return existingAccount
    }

    func requestPhoneSignIn(phone: String) async throws {
        record("requestPhoneSignIn:\(phone)")
        if existingAccount == nil { throw ZXCoreError.accountNotFound }
    }

    func verifyPhoneSignIn(phone: String, code: String) async throws -> ZXAuthUser {
        record("verifyPhoneSignIn:\(phone):\(code)")
        if let verifyPhoneError { throw verifyPhoneError }
        guard let existingAccount else { throw ZXCoreError.accountNotFound }
        setStored(existingAccount)
        return existingAccount
    }

    func signOut() async throws {
        record("signOut")
        setStored(nil)   // 与 supabase-swift 一致: 先清本地, 再打服务端
        if let signOutError { throw signOutError }
    }

    func deleteAccount() async throws {
        record("deleteAccount")
        setStored(nil)
    }

    func updateUserMetadata(_ data: [String: ZXJSONValue]) async throws -> ZXAuthUser {
        record("updateUserMetadata")
        lock.withLock { _lastMetadataPatch = data }
        if let updateMetadataError { throw updateMetadataError }
        guard let current = stored else { throw ZXCoreError.notSignedIn }
        let user = ZXUserMetadata.applying(data, to: current)
        setStored(user)
        return user
    }
}

/// 可手动拨动的时钟。
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_790_000_000)) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

/// 脚本化的队列出口。
final class MockTransport: ZXOutboxTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _outcomes: [ZXOutboxDelivery] = []
    private var _fallback: ZXOutboxDelivery = .delivered
    private var _sent: [ZXOutboxEntry] = []
    /// 投递时的钩子 (模拟飞行途中发生的事)。
    var onDeliver: (@Sendable (ZXOutboxEntry) async -> Void)?

    var sent: [ZXOutboxEntry] { lock.withLock { _sent } }

    /// 依次返回这些结果, 用完后返回 `fallback`。
    func script(_ outcomes: [ZXOutboxDelivery], then fallback: ZXOutboxDelivery = .delivered) {
        lock.withLock {
            _outcomes = outcomes
            _fallback = fallback
        }
    }

    func deliver(_ entry: ZXOutboxEntry) async -> ZXOutboxDelivery {
        if let onDeliver { await onDeliver(entry) }
        return lock.withLock {
            _sent.append(entry)
            return _outcomes.isEmpty ? _fallback : _outcomes.removeFirst()
        }
    }
}

/// 手动推送「断 / 通」的连通性来源。
final class MockConnectivity: ZXConnectivity, @unchecked Sendable {
    let stream: AsyncStream<Bool>
    let continuation: AsyncStream<Bool>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
    }

    func updates() -> AsyncStream<Bool> { stream }
    func send(_ online: Bool) { continuation.yield(online) }
}

func makeTempDirectory(_ function: String = #function) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ZixiaoCoreTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// 轮询等待条件成立 (给异步触发的补传用)。
func waitUntil(timeout: TimeInterval = 3, _ condition: @escaping () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}
