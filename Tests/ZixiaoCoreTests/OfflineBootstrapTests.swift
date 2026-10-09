import Foundation
import Supabase
import XCTest
@testable import ZixiaoCore

@MainActor
final class OfflineBootstrapTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testOptOutOfAnonymousAccountKeepsFirstLaunchLocal() async {
        let backend = MockAuthBackend()
        let auth = ZXAuth(backend: backend, createAnonymousIfMissing: false)
        await auth.bootstrap()
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertTrue(auth.isBootstrapped)
        XCTAssertNil(auth.bootstrapError)
        XCTAssertEqual(backend.count("restore"), 1)
        XCTAssertEqual(backend.count("signInAnonymously"), 0)
    }

    func testCachedLinkedIdentityRestoresAndSignOutDoesNotCreateReplacement() async {
        let user = ZXAuthUser(id: "offline-owner", isAnonymous: false, providers: [.apple])
        let backend = MockAuthBackend(stored: user)
        let auth = ZXAuth(backend: backend, createAnonymousIfMissing: false)
        await auth.bootstrap()
        XCTAssertEqual(auth.state, .linked(userId: user.id, providers: [.apple]))
        await auth.signOut()
        await auth.bootstrap()
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertEqual(backend.count("signInAnonymously"), 0)
    }

    func testPreferCachedSessionRestoresExpiredIdentityWithoutRefreshing() async throws {
        let (client, owner) = try client(expiredSession: true)
        let backend = ZXSupabaseAuthBackend(client: { client }, preferCachedSession: true)
        let restored = try await backend.restoreSession()
        XCTAssertEqual(restored?.id.lowercased(), owner.uuidString.lowercased())
        XCTAssertTrue(client.auth.currentSession?.isExpired == true)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "Local identity restoration must not ask the token endpoint")
    }

    func testPreferCachedSessionWithNoStoredAccountDoesNotRequestAnything() async throws {
        let (client, _) = try client(expiredSession: false)
        let backend = ZXSupabaseAuthBackend(client: { client }, preferCachedSession: true)
        let restored = try await backend.restoreSession()
        XCTAssertNil(restored)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testExistingDefaultStillAttemptsToRefreshExpiredSession() async throws {
        let (client, owner) = try client(expiredSession: true)
        StubURLProtocol.handler = { _ in AppleExchangeTests.response(503, ["message": "offline fixture"]) }
        let restored = try await ZXSupabaseAuthBackend(client: { client }).restoreSession()
        XCTAssertEqual(restored?.id.lowercased(), owner.uuidString.lowercased())
        XCTAssertTrue(StubURLProtocol.requests.contains { $0.path == "/auth/v1/token" })
    }

    private func client(expiredSession: Bool) throws -> (SupabaseClient, UUID) {
        StubURLProtocol.reset()
        let owner = UUID()
        let storage = InMemoryAuthStorage()
        let key = "offline-bootstrap-test"
        if expiredSession {
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            let user = User(id: owner, appMetadata: ["provider": .string("email")],
                            userMetadata: ["zx_apple_linked": .bool(true)], aud: "authenticated",
                            createdAt: date, updatedAt: date)
            let session = Session(accessToken: "expired-fixture", tokenType: "bearer", expiresIn: 1,
                                  expiresAt: 1, refreshToken: "fixture-refresh", user: user)
            try storage.store(key: key, value: JSONEncoder().encode(session))
        }
        let client = SupabaseClient(supabaseURL: URL(string: "https://data.example.com")!, supabaseKey: "fixture",
                                    options: SupabaseClientOptions(auth: .init(storage: storage, storageKey: key,
                                                                              autoRefreshToken: false, emitLocalSessionAsInitialSession: true),
                                                                   global: .init(session: AppleExchangeTests.stubbedSession())))
        return (client, owner)
    }
}
