import CryptoKit
import Foundation
import Security

/// Apple 登录的 nonce。与平台无关, 单独拿出来便于测试。
///
/// 为什么要 nonce: Apple 面板收到的是 sha256(原文), 签进 id token; 我们把原文交给 GoTrue,
/// 它再算一次 sha256 与 token 里的比对 —— 截获的 token 换一个客户端就用不了 (防重放)。
public enum ZXAppleNonce {
    /// URL 安全字符集 (与 Flutter 版 `_generateNonce` 一致; PoetKit 旧表漏了大写 W, 这里补上)。
    static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")

    /// 生成随机原文。用拒绝采样去掉取模偏差 (256 不是 65 的倍数)。
    public static func make(length: Int = 32) -> String {
        precondition(length > 0)
        var result = ""
        result.reserveCapacity(length)
        let limit = UInt8(256 - 256 % charset.count)   // 65 个字符 → 195: 只收 [0,195) 的字节
        while result.count < length {
            var bytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            precondition(status == errSecSuccess, "SecRandomCopyBytes 失败: \(status)")
            for byte in bytes where byte < limit && result.count < length {
                result.append(charset[Int(byte) % charset.count])
            }
        }
        return result
    }

    /// 小写十六进制的 sha256, 交给 `ASAuthorizationAppleIDRequest.nonce`。
    public static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Apple 面板交回的凭证。`rawNonce` 原样交给 `ZXAuth.linkApple(idToken:nonce:)`。
public struct ZXAppleCredential: Sendable, Hashable {
    public let idToken: String
    public let rawNonce: String
    /// 只有第一次授权时 Apple 才给姓名与邮箱, 之后都是 nil —— 要存就趁这一次。
    public let fullName: String?
    public let email: String?

    public init(idToken: String, rawNonce: String, fullName: String? = nil, email: String? = nil) {
        self.idToken = idToken
        self.rawNonce = rawNonce
        self.fullName = fullName
        self.email = email
    }
}

#if os(iOS) || os(macOS)
import AuthenticationServices
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Apple 登录辅助。iOS 使用当前 scene，原生 macOS 使用发起操作的窗口。
///
/// 两种用法:
/// 1. 自持流程: `let cred = try await ZXAppleSignIn().request()`;
/// 2. HIG 推荐的官方 `SignInWithAppleButton`: 在 `onRequest` 里 `let nonce = ZXAppleSignIn.prepare(request)`,
///    在 `onCompletion` 里 `try ZXAppleSignIn.credential(from: authorization, rawNonce: nonce)`。
/// 拿到凭证后都交给 `ZXAuth.linkApple`, 这里不碰 Supabase。
///
/// 凭证由 `ZXAuth` 交给子晓系共用的 `ZXAppleExchange` 换取 session。
@MainActor
public final class ZXAppleSignIn: NSObject {
    private var continuation: CheckedContinuation<ZXAppleCredential, any Error>?
    private var rawNonce = ""
    private var controller: ASAuthorizationController?
    private var requestedPresentationAnchor: ASPresentationAnchor?

    public override init() { super.init() }

    /// 弹出 Apple 登录面板。用户取消抛 `ZXCoreError.cancelled`。
    public func request(presentationAnchor: ASPresentationAnchor? = nil) async throws -> ZXAppleCredential {
        // 同一个实例同时只允许一次, 否则前一次的 continuation 会被覆盖而永远不 resume。
        if continuation != nil { throw ZXCoreError.cancelled }
        requestedPresentationAnchor = presentationAnchor
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            let request = ASAuthorizationAppleIDProvider().createRequest()
            rawNonce = Self.prepare(request)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller   // 持住, 否则面板回调前控制器就被释放了
            controller.performRequests()
        }
    }

    /// 给请求填上 scope 与 sha256(nonce), 返回 nonce 原文。给 `SignInWithAppleButton.onRequest` 用。
    public static func prepare(_ request: ASAuthorizationAppleIDRequest) -> String {
        let raw = ZXAppleNonce.make()
        request.requestedScopes = [.fullName, .email]
        request.nonce = ZXAppleNonce.sha256(raw)
        return raw
    }

    /// 从授权结果取凭证。给 `SignInWithAppleButton.onCompletion` 用。
    public static func credential(from authorization: ASAuthorization, rawNonce: String) throws -> ZXAppleCredential {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = cred.identityToken,
              let token = String(data: data, encoding: .utf8) else {
            throw ZXCoreError.noIdentityToken
        }
        // 中文姓名按「姓 + 名」拼, 不加空格。
        let name = [cred.fullName?.familyName, cred.fullName?.givenName].compactMap { $0 }.joined()
        return ZXAppleCredential(idToken: token, rawNonce: rawNonce,
                                 fullName: name.isEmpty ? nil : name, email: cred.email)
    }

    /// 把系统错误翻成 `ZXCoreError`: 用户取消不算错误。
    public static func map(_ error: any Error) -> ZXCoreError {
        if let auth = error as? ASAuthorizationError, auth.code == .canceled { return .cancelled }
        return ZXCoreError(error)
    }

    private func finish(_ result: Result<ZXAppleCredential, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
        requestedPresentationAnchor = nil
    }
}

extension ZXAppleSignIn: ASAuthorizationControllerDelegate {
    public func authorizationController(controller: ASAuthorizationController,
                                        didCompleteWithAuthorization authorization: ASAuthorization) {
        finish(Result { try Self.credential(from: authorization, rawNonce: rawNonce) })
    }

    public func authorizationController(controller: ASAuthorizationController,
                                        didCompleteWithError error: any Error) {
        finish(.failure(Self.map(error)))
    }
}

extension ZXAppleSignIn: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let requestedPresentationAnchor { return requestedPresentationAnchor }
        #if os(macOS)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow ?? ASPresentationAnchor()
        #else
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let key = scenes.lazy.compactMap(\.keyWindow).first { return key }
        if let scene = scenes.first { return ASPresentationAnchor(windowScene: scene) }
        return ASPresentationAnchor()
        #endif
    }
}
#endif
