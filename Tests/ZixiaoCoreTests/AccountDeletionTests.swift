import Foundation
import XCTest
import ZixiaoCore

final class AccountDeletionTests: XCTestCase {
    func testEndpointUsesConfiguredHostAndDeploymentPrefix() {
        let configuration = ZXAppleExchange.Configuration(baseURLString: "https://example.invalid/desktop", app: "test")
        XCTAssertEqual(ZXAccountDeletion.endpoint(for: configuration).absoluteString,
                       "https://example.invalid/desktop/api/mobile/auth/delete-account")
        XCTAssertEqual(ZXAccountDeletion.endpoint(for: nil), ZXAccountDeletion.defaultEndpoint)
    }

    func testSuccessfulRequestIncludesCurrentBearerAndApp() async throws {
        let endpoint = URL(string: "https://example.invalid/api/mobile/auth/delete-account")!
        let deletion = ZXAccountDeletion(endpoint: endpoint, app: "test") { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url, endpoint)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-zx-app"), "test")
            return (Data(#"{"ok":true}"#.utf8), HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        try await deletion.delete(accessToken: "test-token")
    }

    func testPrivateMediaCleanupFailureIsPropagated() async {
        let endpoint = URL(string: "https://example.invalid/api/mobile/auth/delete-account")!
        let deletion = ZXAccountDeletion(endpoint: endpoint) { _ in
            (Data(#"{"error":"private media cleanup failed"}"#.utf8),
             HTTPURLResponse(url: endpoint, statusCode: 503, httpVersion: nil, headerFields: nil)!)
        }
        do { try await deletion.delete(accessToken: "test-token"); XCTFail("Must not report deletion success") }
        catch let failure as ZXAuthFailure { XCTAssertEqual(failure.error, .backend("private media cleanup failed")) }
        catch { XCTFail("Unexpected error: \(error)") }
    }
}
