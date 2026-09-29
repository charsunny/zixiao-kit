import XCTest
@testable import ZixiaoCore

/// 未配置 Supabase 时: 不崩溃, 所有网络操作回 `.offline`。
@MainActor
final class OfflineModeTests: XCTestCase {
    override func setUp() async throws { ZXSupabase.reset() }
    override func tearDown() async throws { ZXSupabase.reset() }

    func testUnconfiguredIsOffline() {
        XCTAssertTrue(ZXSupabase.isOffline)
        XCTAssertNil(ZXSupabase.client)
        XCTAssertThrowsError(try ZXSupabase.requireClient()) { error in
            XCTAssertEqual(error as? ZXCoreError, .offline)
        }
    }

    func testMissingOrPlaceholderValuesStayOffline() {
        XCTAssertFalse(ZXSupabase.configure(urlString: nil, anonKey: nil))
        XCTAssertFalse(ZXSupabase.configure(urlString: "", anonKey: "key"))
        XCTAssertFalse(ZXSupabase.configure(urlString: "$(SUPABASE_URL)", anonKey: "$(SUPABASE_ANON_KEY)"))
        XCTAssertFalse(ZXSupabase.configure(urlString: "data.example.com", anonKey: "  "))
        XCTAssertFalse(ZXSupabase.configure(urlString: "data.example.com", anonKey: "YOUR_ANON_KEY"))
        XCTAssertFalse(ZXSupabase.configure(url: URL(string: "ftp://data.example.com"), anonKey: "k"))
        XCTAssertTrue(ZXSupabase.isOffline)
    }

    func testHostOnlyURLFromXcconfigIsAccepted() {
        // xcconfig 里 `//` 是注释, 常只填主机名。
        XCTAssertTrue(ZXSupabase.configure(urlString: "data.example.com", anonKey: "eyJ.test.key"))
        XCTAssertFalse(ZXSupabase.isOffline)
        XCTAssertNotNil(ZXSupabase.client)
        XCTAssertEqual(ZXSupabase.url?.absoluteString, "https://data.example.com")
        // 再配一个无效的回到离线。
        XCTAssertFalse(ZXSupabase.configure(urlString: "", anonKey: ""))
        XCTAssertTrue(ZXSupabase.isOffline)
    }

    func testSupabaseBackendReportsOfflineForEveryCall() async {
        let backend = ZXSupabaseAuthBackend()
        XCTAssertFalse(backend.isConfigured)
        await assertOffline { _ = try await backend.restoreSession() }
        await assertOffline { _ = try await backend.signInAnonymously() }
        await assertOffline { _ = try await backend.linkApple(idToken: "t", nonce: "n") }
        await assertOffline { try await backend.requestPhoneLink(phone: "+8613800138000") }
        await assertOffline { _ = try await backend.verifyPhoneLink(phone: "+8613800138000", code: "123456") }
        await assertOffline { _ = try await backend.signInWithApple(idToken: "t", nonce: "n") }
        await assertOffline { try await backend.requestPhoneSignIn(phone: "+8613800138000") }
        await assertOffline { _ = try await backend.verifyPhoneSignIn(phone: "+8613800138000", code: "123456") }
        await assertOffline { try await backend.signOut() }
        await assertOffline { try await backend.deleteAccount() }
    }

    func testAuthInOfflineMode() async {
        let auth = ZXAuth(backend: ZXSupabaseAuthBackend())
        XCTAssertTrue(auth.isOffline)
        let state = await auth.bootstrap()
        XCTAssertEqual(state, .signedOut)
        XCTAssertTrue(auth.isBootstrapped)
        XCTAssertEqual(auth.bootstrapError, .offline)
        await assertOffline { try await auth.linkApple(idToken: "t", nonce: "n") }
        await assertOffline { try await auth.sendPhoneOTP("13800138000") }
        await assertOffline { try await auth.verifyPhoneOTP("13800138000", code: "123456") }
        await assertOffline { try await auth.deleteAccount() }
        await auth.signOut()   // 不抛、不崩
        XCTAssertEqual(auth.state, .signedOut)
    }

    func testOutboxTransportKeepsEntriesWhileOffline() async {
        let transport = ZXSupabaseOutboxTransport()
        let entry = ZXOutboxEntry(idempotencyKey: "k", owner: "u", table: "t", operation: .insert,
                                  onConflict: nil, payload: [:], createdAt: Date())
        let outcome = await transport.deliver(entry)
        XCTAssertEqual(outcome, .retryLater("offline"))
    }

    func testErrorMessagesAreChineseAndCancelIsSilent() {
        XCTAssertEqual(ZXCoreError.offline.errorDescription, "未连接账号服务（离线模式）")
        XCTAssertNil(ZXCoreError.cancelled.errorDescription)
        XCTAssertEqual(ZXCoreError(URLError(.notConnectedToInternet)), .network)
        XCTAssertEqual(ZXCoreError(URLError(.cancelled)), .cancelled)
        XCTAssertEqual(ZXCoreError(CancellationError()), .cancelled)
    }

    private func assertOffline(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("离线时应抛 .offline", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ZXCoreError, .offline, file: file, line: line)
        }
    }
}
