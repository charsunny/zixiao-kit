import Foundation
import CryptoKit

public enum ZXCloudLibraryScope {
    public static func suffix(_ owner: String) -> String {
        SHA256.hash(data: Data(owner.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
    }
    /// nil intentionally addresses legacy guest data; it must never be auto-uploaded.
    public static func key(_ base: String, owner: String?) -> String {
        owner.map { base + ".account." + suffix($0) } ?? base
    }
    public static func session() async throws -> ZXCloudLibrarySession {
        let session = try await ZXSupabase.requireClient().auth.session
        guard !session.user.isAnonymous else { throw ZXCloudLibraryError.signedOut }
        return .init(userID: session.user.id.uuidString.lowercased(), accessToken: session.accessToken)
    }
}

public extension ZXJSONValue {
    var cloudString: String? { if case .string(let value) = self { value } else { nil } }
}

public extension Notification.Name {
    static let zxCloudLibraryLocalChange = Notification.Name("zx.cloud-library.local-change")
}
