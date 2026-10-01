import Foundation
import os

/// 「Apple identity token 换 session」—— 子晓系 App 共用的服务端登录接口 (现由微诗 web 提供,
/// 统一后端方案见 `.claude/plans/unified-backend.md`)。
///
/// 为什么不用 GoTrue 自带的 Apple provider: 阿里云托管的 GoTrue 没开 Apple (`provider_disabled`);
/// 而且产品决定子晓系各 App 共用一个账号体系 —— 同一 Apple ID 在微诗 / 玄览登录是同一个人。微诗服务端
/// 校验 Apple token (iss / aud / nonce), 按 Apple `sub` 找到 (或新建) 那个人的 profile, 再用 Supabase admin
/// 签出**同一个 Supabase 项目**的真实 GoTrue session, 我们拿回 access / refresh token 后 `setSession` 即可。
///
/// 请求:
/// ```
/// POST <base>/api/mobile/auth/apple/exchange
/// x-zx-app: xuanlan
/// { "identity_token": "...", "nonce": "<原文>", "platform": "ios", "app": "xuanlan", "full_name"?: "..." }
/// ```
/// 成功 (2xx): `{ access_token, refresh_token, expires_at, session_id, user: { id, display_name, ... } }`;
/// 失败: `{ error: "..." }` + 非 2xx —— 抛 `ZXAuthFailure`, `detail` 是服务端原文 (界面会显示)。
///
/// 配置: App 启动时 `ZXAppleExchange.configure(baseURLString:app:)`; 没配时回落读 Info.plist 的
/// `ZXAppleExchangeURL` (完整地址) 或 `ZXWeshiciAPIBaseURL` (base) + `ZXAppSlug`。
public struct ZXAppleExchange: Sendable {
    /// 接口路径 (拼在 base URL 后)。
    public static let path = "/api/mobile/auth/apple/exchange"
    /// 区分产品的请求头 (与统一后端方案同名)。
    public static let appHeader = "x-zx-app"
    /// Info.plist 键: 完整接口地址 (覆盖 base + path)。
    public static let urlInfoKey = "ZXAppleExchangeURL"
    /// Info.plist 键: 微诗接口 base URL (玄览 project.yml 已有)。
    public static let baseURLInfoKey = "ZXWeshiciAPIBaseURL"
    /// Info.plist 键: 产品标识 (`x-zx-app` 的值)。
    public static let appInfoKey = "ZXAppSlug"

    /// 接口地址 + 产品标识。
    public struct Configuration: Sendable, Hashable {
        public var endpoint: URL
        /// `x-zx-app` 的值, 如 `"xuanlan"`。空串表示不带 (服务端按微诗处理)。
        public var app: String

        public init(endpoint: URL, app: String) {
            self.endpoint = endpoint
            self.app = app.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// 从 base URL 字符串拼出接口地址。没有 scheme 时补 `https://`; 空串 / 未展开的构建变量 / 占位符返回 nil。
        public init?(baseURLString: String?, app: String) {
            guard let raw = baseURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  ZXSupabase.isUsableValue(raw) else { return nil }
            let withScheme = raw.contains("://") ? raw : "https://\(raw)"
            guard var components = URLComponents(string: withScheme),
                  let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
                  components.host?.isEmpty == false else { return nil }
            let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
            components.path = base + ZXAppleExchange.path
            components.query = nil
            components.fragment = nil
            guard let url = components.url else { return nil }
            self.init(endpoint: url, app: app)
        }

        /// 从 Info.plist 读: `ZXAppleExchangeURL` 优先, 否则 `ZXWeshiciAPIBaseURL` + path; `ZXAppSlug` 给产品标识。
        public init?(info: [String: Any]?) {
            let app = (info?[ZXAppleExchange.appInfoKey] as? String).flatMap {
                ZXSupabase.isUsableValue($0) ? $0 : nil
            } ?? ""
            if let full = info?[ZXAppleExchange.urlInfoKey] as? String, ZXSupabase.isUsableValue(full),
               let url = URL(string: full), let scheme = url.scheme?.lowercased(),
               scheme == "https" || scheme == "http", url.host?.isEmpty == false {
                self.init(endpoint: url, app: app)
                return
            }
            self.init(baseURLString: info?[ZXAppleExchange.baseURLInfoKey] as? String, app: app)
        }
    }

    /// 换回来的 session。
    public struct Session: Sendable, Hashable {
        public var accessToken: String
        public var refreshToken: String
        /// 秒级时间戳; 服务端没给时为 nil (setSession 会自己解 JWT 的 exp)。
        public var expiresAt: Int?
        /// 服务端 profile id (= Supabase user id)。
        public var userId: String?
        /// 服务端 profile 的昵称 (微诗的 profiles.display_name), 仅供参考。
        public var profileDisplayName: String?
    }

    // MARK: - 全局配置

    private static let configured = OSAllocatedUnfairLock<Configuration?>(initialState: nil)

    /// App 启动时注入。传 nil 清掉 (回落 Info.plist)。
    public static func configure(_ configuration: Configuration?) {
        configured.withLock { $0 = configuration }
    }

    /// 便捷注入: base URL 字符串 (如 Info.plist 的 `ZXWeshiciAPIBaseURL`) + 产品标识。base 不可用时返回 false 且不改配置。
    @discardableResult
    public static func configure(baseURLString: String?, app: String) -> Bool {
        guard let configuration = Configuration(baseURLString: baseURLString, app: app) else { return false }
        configure(configuration)
        return true
    }

    /// 当前生效的配置: 显式注入的 → `Bundle.main` 的 Info.plist → nil。
    public static var currentConfiguration: Configuration? {
        configured.withLock { $0 } ?? Configuration(info: Bundle.main.infoDictionary)
    }

    /// 用当前配置建一个客户端; 没配置时抛 `ZXAuthFailure(.providerDisabled, ...)`。
    public static func current(session: URLSession = .shared) throws -> ZXAppleExchange {
        guard let configuration = currentConfiguration else {
            throw ZXAuthFailure(.providerDisabled,
                                detail: "未配置 Apple 登录接口 (\(baseURLInfoKey) / ZXAppleExchange.configure)")
        }
        return ZXAppleExchange(configuration: configuration, session: session)
    }

    // MARK: - 实例

    public let configuration: Configuration
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(configuration: Configuration, session: URLSession = .shared) {
        self.init(configuration: configuration) { request in try await session.data(for: request) }
    }

    /// 注入 HTTP 出口 (测试用)。
    public init(configuration: Configuration,
                transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.configuration = configuration
        self.transport = transport
    }

    /// 组请求。`nonce` 传原文 (Apple 那边收到的是它的 sha256, 服务端会再算一次比对)。
    public func makeRequest(idToken: String, nonce: String, fullName: String? = nil) throws -> URLRequest {
        var body: [String: String] = [
            "identity_token": idToken,
            "nonce": nonce,
            "platform": "ios",
        ]
        if !configuration.app.isEmpty { body["app"] = configuration.app }
        if let name = ZXUserMetadata.normalizedName(fullName) { body["full_name"] = name }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !configuration.app.isEmpty { request.setValue(configuration.app, forHTTPHeaderField: Self.appHeader) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// 换 session。失败一律抛 `ZXAuthFailure` (映射后的 `ZXCoreError` + 原文)。
    public func exchange(idToken: String, nonce: String, fullName: String? = nil) async throws -> Session {
        let request = try makeRequest(idToken: idToken, nonce: nonce, fullName: fullName)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch is CancellationError {
            throw ZXCoreError.cancelled
        } catch {
            let mapped = ZXCoreError(error)
            if mapped == .cancelled { throw ZXCoreError.cancelled }
            let text = (error as NSError).localizedDescription
            throw ZXAuthFailure(mapped, detail: text.isEmpty ? String(describing: error) : text)
        }
        return try Self.parse(data: data, response: response)
    }

    /// 解析响应。2xx 取 token; 非 2xx 取 JSON 的 `error` (没有就 `message`, 再没有就正文前 200 字 / HTTP 状态)。
    public static func parse(data: Data, response: URLResponse) throws -> Session {
        guard let http = response as? HTTPURLResponse else {
            throw ZXAuthFailure(.backend("Apple 登录接口没有返回 HTTP 响应"), detail: "Apple 登录接口没有返回 HTTP 响应")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let status = http.statusCode
        guard (200..<300).contains(status) else {
            let message = Self.serverMessage(json: json, data: data) ?? "HTTP \(status)"
            let mapped: ZXCoreError = status == 429 ? .rateLimited : .backend(message)
            throw ZXAuthFailure(mapped, detail: "\(message) (HTTP \(status))")
        }
        guard let access = (json?["access_token"] as? String).flatMap({ $0.isEmpty ? nil : $0 }),
              let refresh = (json?["refresh_token"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) else {
            let message = "Apple 登录接口返回里缺少 session"
            throw ZXAuthFailure(.backend(message), detail: "\(message) (HTTP \(status))")
        }
        let user = json?["user"] as? [String: Any]
        let expiresAt: Int? = switch json?["expires_at"] {
        case let value as Int: value
        case let value as Double: Int(value)
        case let value as String: Int(value)
        default: nil
        }
        return Session(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expiresAt,
            userId: (user?["id"] as? String ?? json?["session_id"] as? String)?.lowercased(),
            profileDisplayName: ZXUserMetadata.normalizedName(user?["display_name"] as? String)
        )
    }

    private static func serverMessage(json: [String: Any]?, data: Data) -> String? {
        for key in ["error", "message", "msg"] {
            if let text = ZXUserMetadata.normalizedName(json?[key] as? String) { return text }
        }
        guard json == nil, let text = String(data: data.prefix(200), encoding: .utf8) else { return nil }
        return ZXUserMetadata.normalizedName(text)
    }
}
