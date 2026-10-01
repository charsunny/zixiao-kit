//  PoetAppBoot.swift — 诗人应用共用的启动层
//
//  每个产品的 @main 只做三件事: 配置 ZixiaoCore (Supabase / Apple 换 session)、注入身份
//  (`.zxTheme(...)`)、声明自己的能力开关; 界面名字一律来自自己包内的 composition.json。
//  读不到编成时宁可不写名字, 也不能在一位诗人的启动页上出现另一位 —— 那是最廉价也最刺眼的串味。

import SwiftUI
import ZixiaoDesign

public struct PoetAppBoot: View {
    /// 仅当该 App 的 bundle id 已在开发者后台开通 Sign in with Apple 时才为 true。
    let supportsAppleSignIn: Bool
    /// 启动页字样。缺省用编成里的 displayName; 只有当产品另有惯用写法 (如繁体题名)
    /// 时才由该 App 显式给出。
    let splashTitle: String?
    /// 编成与诗人资源所在的包 (默认主包)。
    let bundle: Bundle

    @State private var ctx: CompositionContext?
    @State private var productName: String?
    @State private var bootError: String?

    public init(supportsAppleSignIn: Bool = false, splashTitle: String? = nil, bundle: Bundle = .main) {
        self.supportsAppleSignIn = supportsAppleSignIn
        self.splashTitle = splashTitle
        self.bundle = bundle
    }

    public var body: some View {
        if let ctx {
            PoetAppRoot(context: ctx)
                // 账号: 恢复 session 或匿名登录; 用户数据跟着账号拉取合并。
                .task { await ctx.startSession() }
        } else {
            PoetBootView(title: splashTitle ?? productName, error: bootError, retry: boot)
                .task { boot() }
        }
    }

    /// 编成随 App 包发, 冷启动离线可得 —— 导航结构不该等网络。数据才走 Supabase。
    private func boot() {
        bootError = nil
        do {
            let composition = try PoetComposition.load(from: bundle)
            // 先记下名字: 即便随后取客户端失败, 错误文案也能称呼对产品。
            productName = composition.app.displayName
            let client = try PoetStoreConfig.makeClient()
            ctx = CompositionContext(
                composition: composition,
                store: PoetStore(client: client, poetName: composition.poet.name),
                resources: PoetResources(bundle: bundle, composition: composition),
                supportsAppleSignIn: supportsAppleSignIn)
        } catch {
            bootError = error.localizedDescription
        }
    }
}

/// 启动页。
struct PoetBootView: View {
    /// 编成没读出来时为 nil。此时一个字都不写, 好过写错一个诗人。
    let title: String?
    let error: String?
    let retry: () -> Void

    @Environment(\.zxTheme) private var theme

    var body: some View {
        ZStack {
            theme.paper().ignoresSafeArea()
            if error != nil {
                ContentUnavailableView {
                    Label(title.map { "暂时无法打开\($0)" } ?? "暂时无法打开", systemImage: "book.closed")
                        .font(theme.type.title3).foregroundStyle(theme.ink())
                } description: {
                    Text("应用资料未能载入，请重试。").font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                } actions: {
                    Button("重新打开", action: retry).font(theme.type.headline).buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: theme.space.xl) {
                    if let title {
                        Text(title)
                            .font(theme.displayFont(34, relativeTo: .largeTitle))
                            .tracking(theme.type.tracking(for: .display))
                    }
                    ProgressView {
                        Text("正在翻开诗文…").font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                    }
                }
                .foregroundStyle(theme.ink())
            }
        }
        .tint(theme.accent)
    }
}
