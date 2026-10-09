import Foundation
import Supabase
import XCTest
@testable import ZixiaoCore

/// T43: Apple 登录改走子晓系共用的「换 session」接口 (`ZXAppleExchange`) + `setSession`。
/// 覆盖: 配置 / URL 拼接、请求体与头、响应解析、非 2xx 原文透传、setSession 之后的状态推导、`ZXAuth` 的切换语义。
final class AppleExchangeTests: XCTestCase {
    static let endpoint = URL(string: "https://www.weshici.com/api/mobile/auth/apple/exchange")!
    static let config = ZXAppleExchange.Configuration(endpoint: endpoint, app: "xuanlan")

    override func tearDown() {
        StubURLProtocol.reset()
        ZXAppleExchange.configure(nil)
        super.tearDown()
    }

    // MARK: - 配置

    func testConfigurationFromBaseURL() {
        let a = ZXAppleExchange.Configuration(baseURLString: "https://www.weshici.com", app: "xuanlan")
        XCTAssertEqual(a?.endpoint, Self.endpoint)
        XCTAssertEqual(a?.app, "xuanlan")
        // 没有 scheme 补 https; 末尾斜杠不重复。
        let b = ZXAppleExchange.Configuration(baseURLString: " www.weshici.com/ ", app: " xuanlan ")
        XCTAssertEqual(b?.endpoint, Self.endpoint)
        XCTAssertEqual(b?.app, "xuanlan")
        // 带前缀路径的 base 保留前缀。
        let c = ZXAppleExchange.Configuration(baseURLString: "https://api.example.com/zx", app: "xuanlan")
        XCTAssertEqual(c?.endpoint.absoluteString, "https://api.example.com/zx/api/mobile/auth/apple/exchange")
        // 缺失 / 未展开 / 占位符 / 非 http(s)。
        XCTAssertNil(ZXAppleExchange.Configuration(baseURLString: nil, app: "xuanlan"))
        XCTAssertNil(ZXAppleExchange.Configuration(baseURLString: "", app: "xuanlan"))
        XCTAssertNil(ZXAppleExchange.Configuration(baseURLString: "$(WESHICI_API_BASE_URL)", app: "xuanlan"))
        XCTAssertNil(ZXAppleExchange.Configuration(baseURLString: "ftp://www.weshici.com", app: "xuanlan"))
    }

    func testConfigurationFromInfoPlist() {
        let fromBase = ZXAppleExchange.Configuration(info: [
            "ZXWeshiciAPIBaseURL": "https://www.weshici.com", "ZXAppSlug": "xuanlan",
        ])
        XCTAssertEqual(fromBase, Self.config)
        let override = ZXAppleExchange.Configuration(info: [
            "ZXWeshiciAPIBaseURL": "https://www.weshici.com",
            "ZXAppleExchangeURL": "https://api.zixiao.example/auth/apple",
        ])
        XCTAssertEqual(override?.endpoint.absoluteString, "https://api.zixiao.example/auth/apple")
        XCTAssertEqual(override?.app, "")
        XCTAssertNil(ZXAppleExchange.Configuration(info: [:]))
        XCTAssertNil(ZXAppleExchange.Configuration(info: nil))
    }

    func testExplicitConfigurationWins() throws {
        XCTAssertTrue(ZXAppleExchange.configure(baseURLString: "https://www.weshici.com", app: "xuanlan"))
        XCTAssertEqual(ZXAppleExchange.currentConfiguration, Self.config)
        XCTAssertEqual(try ZXAppleExchange.current().configuration, Self.config)
        // 不可用的 base 不覆盖已有配置。
        XCTAssertFalse(ZXAppleExchange.configure(baseURLString: "$(X)", app: "xuanlan"))
        XCTAssertEqual(ZXAppleExchange.currentConfiguration, Self.config)
    }

    // MARK: - 请求

    func testRequestShape() throws {
        let exchange = ZXAppleExchange(configuration: Self.config, session: .shared)
        let request = try exchange.makeRequest(idToken: "id.tok.en", nonce: "raw-nonce", fullName: "  李白 ")
        XCTAssertEqual(request.url, Self.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-zx-app"), "xuanlan")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        XCTAssertEqual(body, [
            "identity_token": "id.tok.en", "nonce": "raw-nonce", "platform": ZXAppleExchange.Platform.current.rawValue,
            "app": "xuanlan", "full_name": "李白",
        ])
    }

    func testRequestOmitsBlankNameAndEmptyApp() throws {
        let exchange = ZXAppleExchange(configuration: .init(endpoint: Self.endpoint, app: ""), session: .shared)
        let request = try exchange.makeRequest(idToken: "t", nonce: "n", fullName: "   ")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-zx-app"))
        let body = try XCTUnwrap(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        XCTAssertEqual(body, ["identity_token": "t", "nonce": "n", "platform": ZXAppleExchange.Platform.current.rawValue])
    }

    func testExplicitPlatformFlowsThroughConfigurationAndRequest() throws {
        for platform in [ZXAppleExchange.Platform.ios, .macos] {
            let configuration = try XCTUnwrap(ZXAppleExchange.Configuration(info: [
                "ZXWeshiciAPIBaseURL": "https://www.weshici.com",
                "ZXAppSlug": "library",
                "ZXAppleExchangePlatform": platform.rawValue,
            ]))
            XCTAssertEqual(configuration.platform, platform)
            let request = try ZXAppleExchange(configuration: configuration, session: .shared)
                .makeRequest(idToken: "test-token", nonce: "test-nonce")
            let body = try XCTUnwrap(request.httpBody.flatMap {
                try JSONSerialization.jsonObject(with: $0) as? [String: String]
            })
            XCTAssertEqual(body["platform"], platform.rawValue)
            XCTAssertEqual(body["app"], "library")
        }
    }

    // MARK: - 响应

    func testParsesSuccess() async throws {
        let exchange = ZXAppleExchange(configuration: Self.config) { request in
            XCTAssertEqual(request.url, Self.endpoint)
            return Self.response(200, [
                "status": "ok", "access_token": "acc", "refresh_token": "ref", "expires_at": 1_900_000_000,
                "session_id": "BBBBBBBB-0000-0000-0000-000000000002",
                "user": ["id": "BBBBBBBB-0000-0000-0000-000000000002", "display_name": " 玄友abcdef "],
            ])
        }
        let session = try await exchange.exchange(idToken: "t", nonce: "n")
        XCTAssertEqual(session.accessToken, "acc")
        XCTAssertEqual(session.refreshToken, "ref")
        XCTAssertEqual(session.expiresAt, 1_900_000_000)
        XCTAssertEqual(session.userId, "bbbbbbbb-0000-0000-0000-000000000002")
        XCTAssertEqual(session.profileDisplayName, "玄友abcdef")
    }

    func testNon2xxPassesServerErrorThrough() async {
        let message = "invalid Apple credential: invalid Apple token audience"
        let exchange = ZXAppleExchange(configuration: Self.config) { _ in Self.response(400, ["error": message]) }
        do {
            _ = try await exchange.exchange(idToken: "t", nonce: "n")
            XCTFail("应当抛错")
        } catch let failure as ZXAuthFailure {
            XCTAssertEqual(failure.error, .backend(message))
            XCTAssertEqual(failure.detail, "\(message) (HTTP 400)")
            XCTAssertEqual(ZXCoreError(failure), .backend(message))
            XCTAssertEqual(ZXAuth.detail(of: failure), "\(message) (HTTP 400)")
        } catch {
            XCTFail("应当是 ZXAuthFailure: \(error)")
        }
    }

    func testNon2xxVariants() {
        // 429 → 限流; 非 JSON 正文 → 取正文; 空正文 → HTTP 状态。
        XCTAssertEqual(failure(429, json: ["error": "too many"])?.error, .rateLimited)
        XCTAssertEqual(failure(429, json: ["error": "too many"])?.detail, "too many (HTTP 429)")
        XCTAssertEqual(failure(502, raw: Data("Bad Gateway".utf8))?.error, .backend("Bad Gateway"))
        XCTAssertEqual(failure(500, raw: Data())?.detail, "HTTP 500 (HTTP 500)")
        XCTAssertEqual(failure(500, json: ["message": "boom"])?.error, .backend("boom"))
        // 2xx 却没有 token。
        XCTAssertEqual(failure(200, json: ["status": "ok"])?.error, .backend("Apple 登录接口返回里缺少 session"))
    }

    func testTransportErrorMapsToNetwork() async {
        let exchange = ZXAppleExchange(configuration: Self.config) { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await exchange.exchange(idToken: "t", nonce: "n")
            XCTFail()
        } catch {
            XCTAssertEqual(ZXCoreError(error), .network)
            XCTAssertNotNil(ZXAuth.detail(of: error))
        }
    }

    // MARK: - setSession 之后的状态推导 (纯函数)

    func testBrokerUserWithAppleMarkerIsLinkedApple() {
        let user = ZXAuthUser.fromGoTrue(
            id: "BBBBBBBB-0000-0000-0000-000000000002", isAnonymous: false, identityProviders: ["email"],
            phone: "", phoneConfirmed: false,
            email: "profile-0123456789abcdef01234567@auth.weshici.local", emailConfirmed: true,
            appMetadata: ["provider": .string("mobile_broker")],
            userMetadata: [ZXUserMetadata.appleLinkedKey: .bool(true), "display_name": .string("玄友")]
        )
        XCTAssertEqual(user.id, "bbbbbbbb-0000-0000-0000-000000000002")
        XCTAssertEqual(user.providers, [.apple])
        XCTAssertNil(user.email, "合成邮箱不显示")
        XCTAssertEqual(user.displayName, "玄友")
        XCTAssertEqual(ZXAuthState(user: user), .linked(userId: user.id, providers: [.apple]))
    }

    func testBrokerUserWithoutMarkerIsStillLinked() {
        let user = ZXAuthUser.fromGoTrue(
            id: "bbbbbbbb-0000-0000-0000-000000000002", isAnonymous: false, identityProviders: ["email"],
            phone: nil, phoneConfirmed: false, email: "profile-x@AUTH.WESHICI.LOCAL", emailConfirmed: true,
            appMetadata: [:], userMetadata: [:]
        )
        XCTAssertEqual(user.providers, [])
        XCTAssertEqual(ZXAuthState(user: user), .linked(userId: user.id, providers: []))
    }

    func testRealEmailAndPhoneStillCount() {
        let user = ZXAuthUser.fromGoTrue(
            id: "cccccccc-0000-0000-0000-000000000003", isAnonymous: false, identityProviders: [],
            phone: "8613800138000", phoneConfirmed: true, email: "a@b.com", emailConfirmed: true,
            appMetadata: ["google_sub": .string("g1")], userMetadata: [:]
        )
        XCTAssertEqual(user.providers, [.phone, .email, .google])
        XCTAssertEqual(user.email, "a@b.com")
        let anon = ZXAuthUser.fromGoTrue(
            id: "aaaaaaaa-0000-0000-0000-000000000001", isAnonymous: true, identityProviders: [],
            phone: nil, phoneConfirmed: false, email: nil, emailConfirmed: false, appMetadata: [:], userMetadata: [:]
        )
        XCTAssertEqual(ZXAuthState(user: anon), .anonymous(userId: anon.id))
    }

    // MARK: - 后端端到端 (URLProtocol 桩: 换 session → setSession → 记 Apple 标记)

    func testBackendExchangesAndSetsSession() async throws {
        let newId = "bbbbbbbb-0000-0000-0000-000000000002"
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            switch (request.httpMethod ?? "", path) {
            case ("POST", "/api/mobile/auth/apple/exchange"):
                return Self.response(200, [
                    "status": "ok", "access_token": Self.jwt(sub: newId), "refresh_token": "ref-1",
                    "expires_at": Int(Date().timeIntervalSince1970) + 3600, "session_id": newId,
                    "user": ["id": newId, "display_name": "玄友abcdef"],
                ])
            case ("GET", "/auth/v1/user"):
                return Self.response(200, Self.goTrueUser(id: newId, marked: false))
            case ("PUT", "/auth/v1/user"):
                return Self.response(200, Self.goTrueUser(id: newId, marked: true))
            default:
                return Self.response(404, ["error": "unexpected \(request.httpMethod ?? "") \(path)"])
            }
        }
        let backend = Self.stubbedBackend()
        let user = try await backend.linkApple(idToken: "apple.id.token", nonce: "raw")

        XCTAssertEqual(user.id, newId)
        XCTAssertEqual(user.providers, [.apple])
        XCTAssertNil(user.email)
        XCTAssertEqual(ZXAuthState(user: user), .linked(userId: newId, providers: [.apple]))

        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.map { "\($0.method) \($0.path)" },
                       ["POST /api/mobile/auth/apple/exchange", "GET /auth/v1/user", "PUT /auth/v1/user"])
        let exchange = requests[0]
        XCTAssertEqual(exchange.headers["x-zx-app"], "xuanlan")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: exchange.body) as? [String: String])
        XCTAssertEqual(body["identity_token"], "apple.id.token")
        XCTAssertEqual(body["nonce"], "raw")
        XCTAssertEqual(body["platform"], ZXAppleExchange.Platform.current.rawValue)
        // setSession 用的是换来的 access token。
        XCTAssertEqual(requests[1].headers["Authorization"], "Bearer \(Self.jwt(sub: newId))")
        let marker = try XCTUnwrap(try JSONSerialization.jsonObject(with: requests[2].body) as? [String: Any])
        XCTAssertEqual((marker["data"] as? [String: Any])?[ZXUserMetadata.appleLinkedKey] as? Bool, true)
    }

    func testBackendSkipsMarkerWhenAlreadyMarkedAndSurvivesMarkerFailure() async throws {
        let newId = "bbbbbbbb-0000-0000-0000-000000000002"
        StubURLProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/api/mobile/auth/apple/exchange"):
                return Self.response(200, ["access_token": Self.jwt(sub: newId), "refresh_token": "ref-1"])
            case ("GET", "/auth/v1/user"):
                return Self.response(200, Self.goTrueUser(id: newId, marked: true))
            default:
                return Self.response(500, ["msg": "no"])
            }
        }
        let user = try await Self.stubbedBackend().signInWithApple(idToken: "t", nonce: "n")
        XCTAssertEqual(user.providers, [.apple])
        XCTAssertEqual(StubURLProtocol.requests.map(\.method), ["POST", "GET"])

        // 标记写不上 (500) 不算失败, 本次结果照样带 Apple。
        StubURLProtocol.reset()
        StubURLProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/api/mobile/auth/apple/exchange"):
                return Self.response(200, ["access_token": Self.jwt(sub: newId), "refresh_token": "ref-1"])
            case ("GET", "/auth/v1/user"):
                return Self.response(200, Self.goTrueUser(id: newId, marked: false))
            default:
                return Self.response(500, ["msg": "no"])
            }
        }
        let unmarked = try await Self.stubbedBackend().linkApple(idToken: "t", nonce: "n")
        XCTAssertEqual(unmarked.providers, [.apple])
    }

    func testBackendPassesServerErrorThroughAndDoesNotTouchSession() async {
        StubURLProtocol.handler = { _ in
            Self.response(400, ["error": "invalid Apple credential: invalid Apple token nonce"])
        }
        do {
            _ = try await Self.stubbedBackend().linkApple(idToken: "t", nonce: "n")
            XCTFail()
        } catch {
            XCTAssertEqual(ZXCoreError(error), .backend("invalid Apple credential: invalid Apple token nonce"))
            XCTAssertEqual(ZXAuth.detail(of: error), "invalid Apple credential: invalid Apple token nonce (HTTP 400)")
        }
        XCTAssertEqual(StubURLProtocol.requests.map(\.path), ["/api/mobile/auth/apple/exchange"])
    }

    func testBackendWithoutExchangeConfigIsProviderDisabled() async {
        let client = Self.stubbedClient()
        let backend = ZXSupabaseAuthBackend(client: { client }, appleExchange: {
            ZXAppleExchange.configure(nil)
            return try ZXAppleExchange.current()
        })
        do {
            _ = try await backend.linkApple(idToken: "t", nonce: "n")
            XCTFail()
        } catch {
            // 测试宿主的 Info.plist 没有 ZXWeshiciAPIBaseURL。
            XCTAssertEqual(ZXCoreError(error), .providerDisabled)
            XCTAssertNotNil(ZXAuth.detail(of: error))
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    // MARK: - 工具

    private func failure(_ status: Int, json: [String: Any]? = nil, raw: Data? = nil) -> ZXAuthFailure? {
        let (data, response) = json.map { Self.response(status, $0) } ?? Self.response(status, raw: raw ?? Data())
        do {
            _ = try ZXAppleExchange.parse(data: data, response: response)
            return nil
        } catch {
            return error as? ZXAuthFailure
        }
    }

    static func response(_ status: Int, _ json: [String: Any]) -> (Data, URLResponse) {
        response(status, raw: (try? JSONSerialization.data(withJSONObject: json)) ?? Data())
    }

    static func response(_ status: Int, raw: Data) -> (Data, URLResponse) {
        let http = HTTPURLResponse(url: endpoint, statusCode: status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        return (raw, http)
    }

    /// 只需 payload 可解 (setSession 读 exp 判断是否过期), 签名不校验。
    static func jwt(sub: String) -> String {
        func b64(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let exp = 4_000_000_000
        return "\(b64(["alg": "HS256", "typ": "JWT"])).\(b64(["sub": sub, "exp": exp, "role": "authenticated"])).sig"
    }

    static func goTrueUser(id: String, marked: Bool) -> [String: Any] {
        var userMetadata: [String: Any] = ["profile_id": id, "auth_origin": "mobile_broker"]
        if marked { userMetadata[ZXUserMetadata.appleLinkedKey] = true }
        return [
            "id": id, "aud": "authenticated", "role": "authenticated",
            "email": "profile-0123456789abcdef01234567@auth.weshici.local",
            "email_confirmed_at": "2026-10-01T00:00:00Z", "phone": "",
            "app_metadata": ["provider": "mobile_broker", "providers": ["email"]],
            "user_metadata": userMetadata,
            "identities": [[
                "id": id, "identity_id": "eeeeeeee-0000-0000-0000-000000000005", "user_id": id,
                "identity_data": ["email": "profile-0123456789abcdef01234567@auth.weshici.local", "sub": id],
                "provider": "email", "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z",
                "last_sign_in_at": "2026-10-01T00:00:00Z",
            ]],
            "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z",
            "is_anonymous": false,
        ]
    }

    static func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func stubbedClient() -> SupabaseClient {
        SupabaseClient(
            supabaseURL: URL(string: "https://data.example.com")!, supabaseKey: "anon-key",
            options: SupabaseClientOptions(
                auth: .init(storage: InMemoryAuthStorage(), autoRefreshToken: false,
                            emitLocalSessionAsInitialSession: true),
                global: .init(session: stubbedSession())
            )
        )
    }

    static func stubbedBackend() -> ZXSupabaseAuthBackend {
        let client = stubbedClient()
        let session = stubbedSession()
        return ZXSupabaseAuthBackend(client: { client },
                                     appleExchange: { ZXAppleExchange(configuration: config, session: session) })
    }
}

/// `ZXAuth` 的切换语义 (mock 后端模拟「换 session 换到了另一个账号」)。
@MainActor
final class AppleExchangeAuthTests: XCTestCase {
    let anonId = "aaaaaaaa-0000-0000-0000-000000000001"
    let unified = ZXAuthUser(id: "bbbbbbbb-0000-0000-0000-000000000002", isAnonymous: false, providers: [.apple])

    func testLinkAppleSwitchesFromAnonymousToUnifiedAccount() async throws {
        let backend = MockAuthBackend()
        let unified = self.unified
        backend.linkAppleResult = { _ in .success(unified) }
        let outbox = ZXOutbox(fileURL: makeTempDirectory().appendingPathComponent("outbox.json"),
                              transport: MockTransport(), policy: ZXOutboxPolicy(jitter: 0, autoDrain: false))
        let auth = ZXAuth(backend: backend, outbox: outbox)
        await auth.bootstrap()
        XCTAssertEqual(auth.state, .anonymous(userId: anonId))

        let result = try await auth.linkApple(idToken: "tok", nonce: "raw")
        XCTAssertEqual(result.user.id, unified.id)
        XCTAssertEqual(result.abandonedUserId, anonId)
        XCTAssertTrue(result.abandonedWasAnonymous)
        XCTAssertEqual(auth.state, .linked(userId: unified.id, providers: [.apple]))
        XCTAssertNil(auth.lastErrorDetail)
        let owner = await outbox.currentOwner
        XCTAssertEqual(owner, unified.id)
    }

    /// 换号前先把匿名号排队的写入传完 (换 session 之前, 仍以匿名号的身份), 再交出队列。
    func testSwitchDrainsAnonymousOutboxBeforeExchange() async throws {
        let backend = MockAuthBackend()
        let unified = self.unified
        backend.linkAppleResult = { _ in .success(unified) }
        let transport = MockTransport()
        let outbox = ZXOutbox(fileURL: makeTempDirectory().appendingPathComponent("outbox.json"),
                              transport: transport, policy: ZXOutboxPolicy(jitter: 0, autoDrain: false))
        let auth = ZXAuth(backend: backend, outbox: outbox)
        await auth.bootstrap()
        let anonId = self.anonId
        try await outbox.enqueue(table: "zen_practice_days", payload: ["user_id": .string(anonId)])
        // 投递那一刻后端还没被调用 (session 仍是匿名号)。
        transport.onDeliver = { _ in
            XCTAssertFalse(backend.calls.contains("linkApple:tok:raw"), "必须先传完再换 session")
        }

        try await auth.linkApple(idToken: "tok", nonce: "raw")
        XCTAssertEqual(transport.sent.map(\.owner), [anonId])
        let pending = await outbox.pendingCount
        XCTAssertEqual(pending, 0)
        let owner = await outbox.currentOwner
        XCTAssertEqual(owner, unified.id)
    }

    /// 传不出去 (断网) 不挡换号: 未传完的按原规则随 setOwner 丢弃 (本机数据由 App 并进新账号)。
    func testSwitchProceedsWhenDrainFails() async throws {
        let backend = MockAuthBackend()
        let unified = self.unified
        backend.linkAppleResult = { _ in .success(unified) }
        let transport = MockTransport()
        transport.script([], then: .retryLater("offline"))
        let outbox = ZXOutbox(fileURL: makeTempDirectory().appendingPathComponent("outbox.json"),
                              transport: transport, policy: ZXOutboxPolicy(jitter: 0, autoDrain: false))
        let auth = ZXAuth(backend: backend, outbox: outbox)
        await auth.bootstrap()
        try await outbox.enqueue(table: "zen_practice_days", payload: ["user_id": .string(anonId)])
        let result = try await auth.linkApple(idToken: "tok", nonce: "raw")
        XCTAssertEqual(result.user.id, unified.id)
        let pending = await outbox.pendingCount
        XCTAssertEqual(pending, 0)
    }

    func testLinkAppleSameUserIsPlainLink() async throws {
        let backend = MockAuthBackend()
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        let result = try await auth.linkApple(idToken: "tok", nonce: "raw")
        XCTAssertNil(result.abandonedUserId)
        XCTAssertFalse(result.abandonedWasAnonymous)
        XCTAssertEqual(auth.state, .linked(userId: anonId, providers: [.apple]))
    }

    func testLinkAppleServerErrorKeepsAnonymousAndRecordsDetail() async {
        let backend = MockAuthBackend()
        let message = "invalid Apple credential: invalid Apple token audience"
        backend.linkAppleFailure = ZXAuthFailure(.backend(message), detail: "\(message) (HTTP 400)")
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        do {
            try await auth.linkApple(idToken: "t", nonce: "n")
            XCTFail()
        } catch {
            XCTAssertEqual(error as? ZXCoreError, .backend(message))
        }
        XCTAssertEqual(auth.lastErrorDetail, "\(message) (HTTP 400)")
        XCTAssertEqual(auth.state, .anonymous(userId: anonId))
    }

    func testSignInWithAppleReportsAnonymousAbandon() async throws {
        let backend = MockAuthBackend()
        backend.existingAccount = unified
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        let result = try await auth.signInWithApple(idToken: "t", nonce: "n")
        XCTAssertEqual(result.abandonedUserId, anonId)
        XCTAssertTrue(result.abandonedWasAnonymous)
    }
}

// MARK: - 桩

/// supabase-swift 的会话存储 (测试不碰钥匙串)。
final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { values[key] = nil } }
}

/// 拦下所有请求, 按 `handler` 回应, 并记下请求 (方法 / 路径 / 头 / 正文)。
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Recorded: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: (@Sendable (URLRequest) -> (Data, URLResponse))?
    nonisolated(unsafe) private static var _requests: [Recorded] = []

    static var handler: (@Sendable (URLRequest) -> (Data, URLResponse))? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }
    static var requests: [Recorded] { lock.withLock { _requests } }
    static func reset() { lock.withLock { _handler = nil; _requests = [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.read(request.httpBodyStream)
        var headers: [String: String] = [:]
        for (key, value) in request.allHTTPHeaderFields ?? [:] { headers[key] = value }
        // 头名大小写不敏感: 统一按原样 + 常见写法都能查到。
        if let app = request.value(forHTTPHeaderField: "x-zx-app") { headers["x-zx-app"] = app }
        if let auth = request.value(forHTTPHeaderField: "Authorization") { headers["Authorization"] = auth }
        let recorded = Recorded(method: request.httpMethod ?? "GET", path: request.url?.path ?? "",
                                headers: headers, body: body)
        Self.lock.withLock { Self._requests.append(recorded) }
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let (data, response) = handler(request)
        let http = response as? HTTPURLResponse
        let rewritten = HTTPURLResponse(url: request.url ?? AppleExchangeTests.endpoint,
                                        statusCode: http?.statusCode ?? 200, httpVersion: "HTTP/1.1",
                                        headerFields: http?.allHeaderFields as? [String: String]) ?? response
        client?.urlProtocol(self, didReceive: rewritten, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
