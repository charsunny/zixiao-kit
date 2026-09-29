import XCTest
@testable import ZixiaoCore

@MainActor
final class AuthStateTests: XCTestCase {
    let anonId = "aaaaaaaa-0000-0000-0000-000000000001"

    // MARK: - 状态推导

    func testStateDerivation() {
        XCTAssertEqual(ZXAuthState(user: nil), .signedOut)
        XCTAssertEqual(ZXAuthState(user: ZXAuthUser(id: "ABC", isAnonymous: true)), .anonymous(userId: "abc"))
        XCTAssertEqual(ZXAuthState(user: ZXAuthUser(id: "abc", isAnonymous: false, providers: [.apple])),
                       .linked(userId: "abc", providers: [.apple]))
        // 老 GoTrue: 绑了手机但 is_anonymous 没翻, 仍算已绑定。
        XCTAssertEqual(ZXAuthState(user: ZXAuthUser(id: "abc", isAnonymous: true, providers: [.phone])),
                       .linked(userId: "abc", providers: [.phone]))
        XCTAssertTrue(ZXAuthState.anonymous(userId: "x").isAnonymous)
        XCTAssertEqual(ZXAuthState.linked(userId: "x", providers: [.phone]).providers, [.phone])
    }

    // MARK: - bootstrap

    func testBootstrapWithoutSessionSignsInAnonymously() async {
        let backend = MockAuthBackend()
        let auth = ZXAuth(backend: backend)
        XCTAssertEqual(auth.state, .signedOut)
        let state = await auth.bootstrap()
        XCTAssertEqual(state, .anonymous(userId: anonId))
        XCTAssertEqual(auth.state, .anonymous(userId: anonId))
        XCTAssertTrue(auth.isBootstrapped)
        XCTAssertNil(auth.bootstrapError)
        XCTAssertEqual(backend.calls, ["restore", "signInAnonymously"])
        XCTAssertTrue(auth.signOutLosesData)
    }

    func testBootstrapRestoresExistingSessionWithoutNewUser() async {
        let existing = ZXAuthUser(id: "bbbbbbbb-0000-0000-0000-000000000002", isAnonymous: false, providers: [.apple])
        let backend = MockAuthBackend(stored: existing)
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        XCTAssertEqual(auth.state, .linked(userId: existing.id, providers: [.apple]))
        XCTAssertEqual(backend.count("signInAnonymously"), 0)
        XCTAssertFalse(auth.signOutLosesData)
    }

    func testConcurrentBootstrapSharesOneAttempt() async {
        let backend = MockAuthBackend()
        let auth = ZXAuth(backend: backend)
        async let a = auth.bootstrap()
        async let b = auth.bootstrap()
        let (first, second) = await (a, b)
        XCTAssertEqual(first, second)
        XCTAssertEqual(backend.count("signInAnonymously"), 1)
    }

    func testBootstrapNetworkFailureDoesNotBlockAndCanRetry() async {
        let backend = MockAuthBackend()
        backend.restoreError = .network
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertTrue(auth.isBootstrapped)
        XCTAssertEqual(auth.bootstrapError, .network)

        backend.restoreError = nil
        await auth.bootstrap()
        XCTAssertEqual(auth.state, .anonymous(userId: anonId))
        XCTAssertNil(auth.bootstrapError)
    }

    func testBootstrapTimesOut() async {
        let backend = MockAuthBackend()
        backend.restoreDelay = .seconds(5)
        let auth = ZXAuth(backend: backend, bootstrapTimeout: .milliseconds(50))
        let started = Date()
        await auth.bootstrap()
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(auth.bootstrapError, .network)
        XCTAssertEqual(auth.state, .signedOut)
    }

    func testAnonymousSignInDisabledIsReported() async {
        let backend = MockAuthBackend()
        backend.signInError = .providerDisabled
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        XCTAssertEqual(auth.bootstrapError, .providerDisabled)
        XCTAssertEqual(auth.state, .signedOut)
    }

    // MARK: - Apple

    func testLinkAppleKeepsUserId() async throws {
        let backend = MockAuthBackend()
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        try await auth.linkApple(idToken: "tok", nonce: "raw")
        XCTAssertEqual(auth.state, .linked(userId: anonId, providers: [.apple]))
        XCTAssertTrue(backend.calls.contains("linkApple:tok:raw"))
    }

    func testLinkAppleIdentityInUseLeavesStateUntouched() async {
        let backend = MockAuthBackend()
        backend.linkAppleResult = { _ in .failure(.identityInUse(.apple)) }
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        do {
            try await auth.linkApple(idToken: "tok", nonce: "raw")
            XCTFail("应当抛错")
        } catch {
            XCTAssertEqual(error as? ZXCoreError, .identityInUse(.apple))
        }
        XCTAssertEqual(auth.state, .anonymous(userId: anonId))
    }

    func testLinkAppleDetectsUserIdChange() async {
        let other = ZXAuthUser(id: "cccccccc-0000-0000-0000-000000000003", isAnonymous: false, providers: [.apple])
        let backend = MockAuthBackend()
        backend.linkAppleResult = { _ in .success(other) }
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        do {
            try await auth.linkApple(idToken: "tok", nonce: "raw")
            XCTFail("user id 变了必须报错")
        } catch {
            XCTAssertEqual(error as? ZXCoreError, .identityChanged(before: anonId, after: other.id))
        }
        // 本地 session 已是另一个人, 状态如实跟过去。
        XCTAssertEqual(auth.userId, other.id)
    }

    func testLinkRequiresSignedInUser() async {
        let auth = ZXAuth(backend: MockAuthBackend())
        do {
            try await auth.linkApple(idToken: "t", nonce: "n")
            XCTFail()
        } catch {
            XCTAssertEqual(error as? ZXCoreError, .notSignedIn)
        }
    }

    // MARK: - 手机号

    func testPhoneLinkFlowKeepsUserId() async throws {
        let backend = MockAuthBackend()
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        try await auth.sendPhoneOTP("138 0013 8000")
        XCTAssertEqual(auth.pendingPhone, "+8613800138000")
        XCTAssertTrue(backend.calls.contains("requestPhone:+8613800138000"))

        try await auth.verifyPhoneOTP("13800138000", code: " 123456 ")
        XCTAssertEqual(auth.state, .linked(userId: anonId, providers: [.phone]))
        XCTAssertEqual(auth.user?.phone, "+8613800138000")
        XCTAssertNil(auth.pendingPhone)
        XCTAssertTrue(backend.calls.contains("verifyPhone:+8613800138000:123456"))
    }

    func testPhoneThenAppleAccumulatesProviders() async throws {
        let backend = MockAuthBackend()
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        try await auth.sendPhoneOTP("13800138000")
        try await auth.verifyPhoneOTP("13800138000", code: "123456")
        try await auth.linkApple(idToken: "t", nonce: "n")
        XCTAssertEqual(auth.state, .linked(userId: anonId, providers: [.phone, .apple]))
    }

    func testInvalidPhoneAndCodeAreRejectedLocally() async {
        let backend = MockAuthBackend()
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        do { try await auth.sendPhoneOTP("12345"); XCTFail() } catch {
            XCTAssertEqual(error as? ZXCoreError, .invalidPhone)
        }
        do { try await auth.verifyPhoneOTP("13800138000", code: "12ab56"); XCTFail() } catch {
            XCTAssertEqual(error as? ZXCoreError, .invalidCode)
        }
        XCTAssertEqual(backend.count("requestPhone"), 0)
        XCTAssertEqual(backend.count("verifyPhone"), 0)
    }

    func testWrongCodeKeepsAnonymous() async throws {
        let backend = MockAuthBackend()
        backend.verifyPhoneError = .invalidCode
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        try await auth.sendPhoneOTP("13800138000")
        do { try await auth.verifyPhoneOTP("13800138000", code: "000000"); XCTFail() } catch {
            XCTAssertEqual(error as? ZXCoreError, .invalidCode)
        }
        XCTAssertEqual(auth.state, .anonymous(userId: anonId))
        XCTAssertEqual(auth.pendingPhone, "+8613800138000")
    }

    func testPhoneNormalization() {
        XCTAssertEqual(ZXAuth.normalizePhone("13800138000"), "+8613800138000")
        XCTAssertEqual(ZXAuth.normalizePhone("138-0013-8000"), "+8613800138000")
        XCTAssertEqual(ZXAuth.normalizePhone("+86 138 0013 8000"), "+8613800138000")
        XCTAssertEqual(ZXAuth.normalizePhone("8613800138000"), "+8613800138000")
        XCTAssertEqual(ZXAuth.normalizePhone("0085291234567"), "+85291234567")
        XCTAssertEqual(ZXAuth.normalizePhone("+1 415 555 2671"), "+14155552671")
        XCTAssertNil(ZXAuth.normalizePhone("12345"))
        XCTAssertNil(ZXAuth.normalizePhone("+0123456789"))
        XCTAssertNil(ZXAuth.normalizePhone(""))
        XCTAssertNil(ZXAuth.normalizePhone("１３８００１３８０００"))   // 全角数字不收
    }

    // MARK: - 退出与删号

    func testSignOutClearsStateEvenWhenServerUnreachable() async {
        let backend = MockAuthBackend()
        backend.signOutError = .network
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        await auth.signOut()
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertNil(auth.user)
        XCTAssertNil(backend.stored)
    }

    func testSignOutThenBootstrapCreatesFreshAnonymousUser() async {
        let backend = MockAuthBackend()
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        await auth.signOut()
        await auth.bootstrap()
        XCTAssertEqual(auth.state, .anonymous(userId: anonId))
        XCTAssertEqual(backend.count("signInAnonymously"), 2)
    }

    func testDeleteAccount() async throws {
        let backend = MockAuthBackend()
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        try await auth.deleteAccount()
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertEqual(backend.count("deleteAccount"), 1)
    }

    func testDeleteAccountRequiresUser() async {
        let auth = ZXAuth(backend: MockAuthBackend())
        do { try await auth.deleteAccount(); XCTFail() } catch {
            XCTAssertEqual(error as? ZXCoreError, .notSignedIn)
        }
    }

    // MARK: - 与离线队列联动

    func testAuthDrivesOutboxOwner() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let outbox = ZXOutbox(fileURL: dir.appendingPathComponent("outbox.json"), transport: MockTransport(),
                              policy: ZXOutboxPolicy(jitter: 0, autoDrain: false))
        let auth = ZXAuth(backend: MockAuthBackend(), outbox: outbox)
        await auth.bootstrap()
        let owner = await outbox.currentOwner
        XCTAssertEqual(owner, anonId)

        try await outbox.enqueue(table: "zen_reflections", payload: ["id": "r1"])
        await auth.signOut()
        let ownerAfter = await outbox.currentOwner
        let pending = await outbox.pendingCount
        XCTAssertNil(ownerAfter)
        XCTAssertEqual(pending, 0, "退出后上一位用户的待传写入必须丢弃")
    }
}
