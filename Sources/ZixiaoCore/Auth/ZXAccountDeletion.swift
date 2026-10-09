import Foundation

/// Server-side account deletion also removes private media before removing the auth user.
/// A database-only RPC cannot perform that object-storage cleanup.
public struct ZXAccountDeletion: Sendable {
    public static let endpointInfoKey = "ZXDeleteAccountURL"
    public static let defaultEndpoint = URL(string: "https://www.weshici.com/api/mobile/auth/delete-account")!
    public let endpoint: URL
    public let app: String
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(endpoint: URL, app: String = "", session: URLSession = .shared) {
        self.init(endpoint: endpoint, app: app, transport: { try await session.data(for: $0) })
    }

    public init(endpoint: URL, app: String = "",
                transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.endpoint = endpoint; self.app = app; self.transport = transport
    }

    public static func current() -> Self {
        let exchange = ZXAppleExchange.currentConfiguration
        if let raw = Bundle.main.object(forInfoDictionaryKey: endpointInfoKey) as? String,
           let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
            return Self(endpoint: url, app: exchange?.app ?? "")
        }
        return Self(endpoint: endpoint(for: exchange), app: exchange?.app ?? "")
    }

    /// Preserve a deployment prefix when the Apple exchange uses the standard route.
    public static func endpoint(for exchange: ZXAppleExchange.Configuration?) -> URL {
        guard let exchange, var url = URLComponents(url: exchange.endpoint, resolvingAgainstBaseURL: false) else {
            return defaultEndpoint
        }
        let suffix = "/api/mobile/auth/apple/exchange"
        let prefix = url.path.hasSuffix(suffix) ? String(url.path.dropLast(suffix.count)) : ""
        url.path = prefix + "/api/mobile/auth/delete-account"; url.query = nil; url.fragment = nil
        return url.url ?? defaultEndpoint
    }

    public func makeRequest(accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty else { throw ZXCoreError.notSignedIn }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !app.isEmpty { request.setValue(app, forHTTPHeaderField: "x-zx-app") }
        request.httpBody = Data("{}".utf8)
        return request
    }

    public func delete(accessToken: String) async throws {
        let (data, response) = try await transport(makeRequest(accessToken: accessToken))
        guard let http = response as? HTTPURLResponse else { throw ZXCoreError.network }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(http.statusCode), body?["ok"] as? Bool == true else {
            let message = body?["error"] as? String ?? body?["message"] as? String ?? "账号注销未完成"
            throw ZXAuthFailure(.backend(message), detail: "\(message) (HTTP \(http.statusCode))")
        }
    }
}
