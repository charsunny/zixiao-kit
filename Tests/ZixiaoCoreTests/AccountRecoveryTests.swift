import XCTest
@testable import ZixiaoCore

/// 找回旧账号: identityInUse → 界面确认放弃匿名数据 → signIn* 换到旧账号。
@MainActor
final class AccountRecoveryTests: XCTestCase {
    let anonId = "aaaaaaaa-0000-0000-0000-000000000001"
    let oldAccount = ZXAuthUser(id: "dddddddd-0000-0000-0000-000000000004", isAnonymous: false,
                                providers: [.apple, .phone], phone: "+8613800138000")
    var dir: URL!

    override func setUp() async throws { dir = makeTempDirectory() }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    private func makeOutbox() -> ZXOutbox {
        ZXOutbox(fileURL: dir.appendingPathComponent("outbox.json"), transport: MockTransport(),
                 policy: ZXOutboxPolicy(jitter: 0, autoDrain: false))
    }

    func testAppleIdentityInUseThenSwitch() async throws {
        let backend = MockAuthBackend()
        backend.linkAppleResult = { _ in .failure(.identityInUse(.apple)) }
        backend.existingAccount = oldAccount
        let outbox = makeOutbox()
        let localState = ZXLocalUserState(directory: dir.appendingPathComponent("users"))
        let auth = ZXAuth(backend: backend, outbox: outbox)
        await auth.bootstrap()

        // 匿名期间攒下的本地态与待传写入。
        try await localState.recordOpen(for: auth.userId)
        try await localState.setFlag(.liZhu, true, for: auth.userId)
        try await outbox.enqueue(table: "zen_reflections", payload: ["user_id": .string(anonId)])

        // 1. 绑定失败: 这个 Apple ID 属于旧账号。状态不动。
        do {
            try await auth.linkApple(idToken: "tok1", nonce: "n1")
            XCTFail("应当 identityInUse")
        } catch {
            XCTAssertEqual(error as? ZXCoreError, .identityInUse(.apple))
        }
        XCTAssertEqual(auth.state, .anonymous(userId: anonId))

        // 2. 界面确认放弃匿名数据后, 用新凭证登录旧账号。
        let result = try await auth.signInWithApple(idToken: "tok2", nonce: "n2")
        XCTAssertEqual(result.user.id, oldAccount.id)
        XCTAssertEqual(result.abandonedUserId, anonId)
        XCTAssertEqual(auth.state, .linked(userId: oldAccount.id, providers: [.apple, .phone]))
        XCTAssertTrue(backend.calls.contains("signInWithApple:tok2:n2"))

        // 3. 队列交给新用户, 旧匿名号的待传写入丢弃。
        let owner = await outbox.currentOwner
        let pending = await outbox.pendingCount
        XCTAssertEqual(owner, oldAccount.id)
        XCTAssertEqual(pending, 0)

        // 4. App 用返回的旧 id 清本地态; 设备级「历注」不受影响。
        try await localState.remove(for: result.abandonedUserId)
        let abandoned = await localState.snapshot(for: anonId)
        XCTAssertEqual(abandoned, .empty)
        let liZhu = await localState.flag(.liZhu, for: auth.userId)
        XCTAssertTrue(liZhu)
    }

    func testPhoneIdentityInUseThenSwitch() async throws {
        let backend = MockAuthBackend()
        backend.requestPhoneError = .identityInUse(.phone)
        backend.existingAccount = oldAccount
        let outbox = makeOutbox()
        let auth = ZXAuth(backend: backend, outbox: outbox)
        await auth.bootstrap()

        do {
            try await auth.sendPhoneOTP("13800138000")
            XCTFail("应当 identityInUse")
        } catch {
            XCTAssertEqual(error as? ZXCoreError, .identityInUse(.phone))
        }
        XCTAssertNil(auth.pendingPhone)

        try await auth.signInWithPhone("138 0013 8000")
        XCTAssertEqual(auth.pendingSignInPhone, "+8613800138000")
        XCTAssertEqual(auth.state, .anonymous(userId: anonId), "发码不换人")

        let result = try await auth.verifyPhoneSignIn("13800138000", code: "654321")
        XCTAssertEqual(result.abandonedUserId, anonId)
        XCTAssertEqual(auth.userId, oldAccount.id)
        XCTAssertNil(auth.pendingSignInPhone)
        XCTAssertTrue(backend.calls.contains("verifyPhoneSignIn:+8613800138000:654321"))
        let owner = await outbox.currentOwner
        XCTAssertEqual(owner, oldAccount.id)
    }

    func testPhoneSignInWithoutAccountDoesNotSwitch() async {
        let backend = MockAuthBackend()   // existingAccount == nil
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        do {
            try await auth.signInWithPhone("13800138000")
            XCTFail()
        } catch {
            XCTAssertEqual(error as? ZXCoreError, .accountNotFound)
        }
        XCTAssertNil(auth.pendingSignInPhone)
        XCTAssertEqual(auth.state, .anonymous(userId: anonId))
    }

    func testWrongSignInCodeKeepsCurrentUser() async throws {
        let backend = MockAuthBackend()
        backend.existingAccount = oldAccount
        backend.verifyPhoneError = .invalidCode
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        try await auth.signInWithPhone("13800138000")
        do {
            _ = try await auth.verifyPhoneSignIn("13800138000", code: "000000")
            XCTFail()
        } catch {
            XCTAssertEqual(error as? ZXCoreError, .invalidCode)
        }
        XCTAssertEqual(auth.state, .anonymous(userId: anonId))
        XCTAssertEqual(auth.pendingSignInPhone, "+8613800138000")
    }

    func testSignInFromSignedOutHasNothingToAbandon() async throws {
        let backend = MockAuthBackend()
        backend.existingAccount = oldAccount
        let auth = ZXAuth(backend: backend)
        let result = try await auth.signInWithApple(idToken: "t", nonce: "n")
        XCTAssertNil(result.abandonedUserId)
        XCTAssertEqual(auth.userId, oldAccount.id)
    }

    func testSignInToSameAccountHasNothingToAbandon() async throws {
        let backend = MockAuthBackend(stored: oldAccount)
        backend.existingAccount = oldAccount
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        let result = try await auth.signInWithApple(idToken: "t", nonce: "n")
        XCTAssertNil(result.abandonedUserId)
    }

    func testRecoveryIsOfflineSafe() async {
        let auth = ZXAuth(backend: MockAuthBackend(configured: false))
        do { _ = try await auth.signInWithApple(idToken: "t", nonce: "n"); XCTFail() } catch {
            XCTAssertEqual(error as? ZXCoreError, .offline)
        }
        do { try await auth.signInWithPhone("13800138000"); XCTFail() } catch {
            XCTAssertEqual(error as? ZXCoreError, .offline)
        }
        do { _ = try await auth.verifyPhoneSignIn("13800138000", code: "123456"); XCTFail() } catch {
            XCTAssertEqual(error as? ZXCoreError, .offline)
        }
    }
}
