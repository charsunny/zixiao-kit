//  CompositionContext+Account.swift — 账号: ZXAuth 的薄门面
//
//  模型 (架构决定 D3): 匿名优先。启动即有一个 Supabase 匿名用户 (authenticated 角色, 有 uid),
//  收藏与阅读按 'u:<uid>' 上云。之后:
//  - Apple 登录: 交给子晓系共用服务端换 session (`ZXAppleExchange`, 头 x-zx-app), 得到这个 Apple ID
//    在子晓系的统一账号 —— 通常是一次账号切换; 匿名期间的本机数据由 `PoetUserData` 并进新账号再回推。
//  - 手机号: 先按「绑定到当前匿名号」走 (uid 不变); 号码已属于另一个账号 (`.identityInUse(.phone)`)
//    时改走「登录那个账号」(换 uid), 本机数据同样并过去。诗人应用的用户数据只有收藏与阅读, 并入不丢东西,
//    所以这里不另外弹「放弃匿名数据」的确认 (玄览的日课才需要)。
//  - 退出: 本地清 session, 立即重新匿名登录 (界面一直有可写的账号)。
//  - 注销: 服务端 `zx_delete_account` 删全库里自己的行与 auth 用户 → 清本应用的本地诗文缓存
//    (阅读偏好等设备设置保留) → 重新匿名登录。

import Foundation
import ZixiaoCore

/// 手机号验证码当前走的是哪条路。
enum PhoneFlow: Sendable {
    /// 绑定到当前用户 (uid 不变)。
    case link
    /// 登录号码所属的旧账号 (换 uid)。
    case signIn
}

@MainActor
public extension CompositionContext {
    /// 账号状态 (匿名 / 已绑定 / 无)。
    var accountState: ZXAuthState { auth.state }

    /// 已绑定 Apple 或手机号 (匿名用户不算「已登录」—— 界面上它显示为「登录以同步」)。
    var isSignedIn: Bool {
        if case .linked = auth.state { return true }
        return false
    }

    /// 启动账号: 用户数据跟上账号, 离线队列开始联网补传, 然后恢复 session 或匿名登录。
    /// `PoetAppBoot` 建好上下文后调用一次; 重复调用无害。
    func startSession() async {
        userData.attach(auth)
        await outbox.startMonitoring()
        await auth.bootstrap()
    }

    // MARK: Apple

    /// 用 Apple 面板交回的凭证登录。`rawNonce` 是请求时放进 sha256 之前的原文 (`ZXAppleNonce`)。
    /// - Parameter fullName: Apple 只在第一次授权时给; 账号还没有昵称时写进去。
    func signInWithApple(idToken: String, rawNonce: String, fullName: String? = nil) async throws {
        guard supportsAppleSignIn else { throw ZXCoreError.providerDisabled }
        if auth.userId == nil { await auth.bootstrap() }
        let result = auth.userId == nil
            ? try await auth.signInWithApple(idToken: idToken, nonce: rawNonce)
            : try await auth.linkApple(idToken: idToken, nonce: rawNonce)
        // ZXAuth.linkApple 不转交姓名 (kit gap): 统一账号还没有昵称时补写, 失败不影响登录。
        if let fullName, !fullName.isEmpty, result.user.displayName == nil {
            try? await auth.updateDisplayName(fullName)
        }
    }

    /// 自持流程: 弹 Apple 面板并登录。
    func signInWithApple() async throws {
        let credential = try await ZXAppleSignIn().request()
        try await signInWithApple(idToken: credential.idToken, rawNonce: credential.rawNonce,
                                  fullName: credential.fullName)
    }

    // MARK: 手机号

    /// 发验证码。11 位大陆号自动补 +86。
    func sendPhoneOTP(_ phone: String) async throws {
        if auth.userId == nil { await auth.bootstrap() }
        do {
            try await auth.sendPhoneOTP(phone)
            phoneFlow = .link
        } catch ZXCoreError.identityInUse(.phone) {
            try await auth.signInWithPhone(phone)
            phoneFlow = .signIn
        } catch ZXCoreError.notSignedIn {
            // 匿名登录也没成 (服务端没开匿名 / 断网后恢复): 只能登录已有账号。
            try await auth.signInWithPhone(phone)
            phoneFlow = .signIn
        }
    }

    /// 校验验证码, 完成绑定或登录。
    func verifyPhoneOTP(_ phone: String, code: String) async throws {
        switch phoneFlow {
        case .link: try await auth.verifyPhoneOTP(phone, code: code)
        case .signIn: try await auth.verifyPhoneSignIn(phone, code: code)
        }
        phoneFlow = .link
    }

    // MARK: 退出与注销

    /// 退出: 清本地 session, 再匿名登录一个新用户。账号里的数据留在云端, 登回来即可见。
    func signOut() async {
        await auth.signOut()
        await auth.bootstrap()
    }

    /// 注销账号 (App Store 5.1.1(v))。服务端删全库里自己的数据与 auth 用户, 然后清掉本应用
    /// 的本地诗文缓存 (阅读偏好等设备设置不动), 最后匿名登录一个新用户。
    func deleteAccount() async throws {
        let uid = auth.userId
        try await auth.deleteAccount()
        userData.clearLocal(for: uid)
        await auth.bootstrap()
    }
}
