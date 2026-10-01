import Foundation

/// ZixiaoCore 对外只抛这一种错误。
///
/// 为什么不把 supabase-swift 的 `AuthError` / `PostgrestError` 直接抛给 App:
/// 1. 评审规则要求 UI 不直接碰 supabase-swift, 错误类型也是依赖面的一部分;
/// 2. 界面要的是「该说哪句话」, 不是 GoTrue 的错误码 —— 映射集中在 `ZXSupabaseAuthBackend` 一处做;
/// 3. 测试里的 mock 后端可以直接抛这些值, 不必伪造 HTTP 响应。
public enum ZXCoreError: Error, Sendable, Hashable {
    /// 未配置 Supabase (xcconfig 没填 URL / anon key)。离线模式下所有网络操作都回这个, 而不是崩溃。
    case offline
    /// 已配置, 但网络不通或超时。可以稍后重试。
    case network
    /// 需要一个已登录 (含匿名) 的用户, 但当前没有。
    case notSignedIn
    /// 手机号不是合法的 E.164 (也补不成 +86)。
    case invalidPhone
    /// 验证码格式不对, 或服务端判定过期 / 错误 (GoTrue 对两者回同一个 `otp_expired`)。
    case invalidCode
    /// 发送太频繁 (短信 / 请求限流)。
    case rateLimited
    /// 这个身份 (Apple ID / 手机号 / 邮箱) 已属于另一个账号, 绑不到当前账号上。
    case identityInUse(ZXProvider)
    /// 绑定后 user id 变了。这违背「匿名优先、绑定不换人」的不变量, 必须报出来, 不能静默接受。
    case identityChanged(before: String, after: String?)
    /// 找回账号时: 这个手机号下没有账号 (我们不借登录顺手建新号)。
    case accountNotFound
    /// 服务端没开这项能力 (匿名登录 / 短信 / 手动绑定身份)。
    case providerDisabled
    /// 用户自己取消 (如关掉 Apple 登录面板)。界面上应静默。
    case cancelled
    /// Apple 回调里没有 identity token。
    case noIdentityToken
    /// 其余服务端错误, 附原始信息便于排查。
    case backend(String)

    /// 把任意错误收拢成 `ZXCoreError`。只认识与后端无关的类型 (URLError / 取消);
    /// Supabase 专属的映射在 `ZXSupabaseAuthBackend.map(_:)`。
    public init(_ error: any Error) {
        switch error {
        case let own as ZXCoreError: self = own
        case let failure as ZXAuthFailure: self = failure.error
        case is CancellationError: self = .cancelled
        case let url as URLError: self = url.code == .cancelled ? .cancelled : .network
        default: self = .backend(String(describing: error))
        }
    }
}

extension ZXCoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .offline: return "未连接账号服务（离线模式）"
        case .network: return "网络不通，请稍后再试"
        case .notSignedIn: return "尚未登录"
        case .invalidPhone: return "手机号格式不对"
        case .invalidCode: return "验证码不对或已过期"
        case .rateLimited: return "操作太频繁，请稍等一两分钟再试"
        case .identityInUse(let provider): return "这个\(provider.displayName)已绑定了另一个账号"
        case .identityChanged: return "绑定没有落在当前账号上，请重试"
        case .accountNotFound: return "这个手机号还没有账号"
        case .providerDisabled: return "账号服务暂未开通这项功能"
        case .cancelled: return nil   // 静默, 不弹红字
        case .noIdentityToken: return "没拿到 Apple 身份令牌"
        case .backend(let message): return message
        }
    }
}
