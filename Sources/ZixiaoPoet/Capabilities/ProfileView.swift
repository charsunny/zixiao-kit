//  ProfileView.swift — 书房: 账号卡、最近翻阅、收藏、阅读记录; 设置 / 账号 / 登录 / 注销 / 关于
//
//  账号模型 (D3): 匿名优先。未绑定 Apple / 手机号的用户也有一个云端匿名身份 (`ctx.isSignedIn == false`),
//  界面上显示「登录以同步」。登录 = 绑定 (或切到该身份已有的统一账号, 本机记录并过去)。
//  退出后立即换成一个新的匿名身份; 注销走全库 RPC (`ctx.deleteAccount()`), 完成后同样回到新的匿名身份。
//  文案里不出现任何产品名 / 诗人名: 产品名一律取编成的 `app.displayName`。

import SwiftUI
import AuthenticationServices
import ZixiaoCore
import ZixiaoDesign

struct ProfileView: View {
    let ctx: CompositionContext
    @State private var indexed: [UUID: Poem] = [:]
    @State private var loading = true
    @State private var failed = false
    @State private var showingLogin = false
    @State private var showingDirectory = false
    @Namespace private var books
    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 最近翻阅里那本书的宽度 (「正在阅读」一档), 随 Dynamic Type。
    @ScaledMetric(relativeTo: .title3) private var coverWidth = BookCoverView.Size.reading.width
    private var savedIDs: [UUID] { ctx.userData.bookmarks.filter { $0.targetType == "poem" }.map(\.targetId) }
    private var previewIDs: [UUID] { Array(savedIDs.prefix(6)) + ctx.userData.reading.prefix(4).map(\.poemId) }
    private var saved: [Poem] { savedIDs.prefix(6).compactMap { indexed[$0] } }
    private var recent: Poem? { ctx.userData.reading.first.flatMap { indexed[$0.poemId] } }

    var body: some View {
        ZXShellScrollView {
            VStack(alignment: .leading, spacing: theme.space.xxl) {
                AccountCard(ctx: ctx, showLogin: { showingLogin = true })
                if loading { LoadingStateView(label: "正在打开书房…") }
                if failed {
                    VStack(alignment: .leading, spacing: theme.space.sm) {
                        Text("部分作品暂未载入，已保留可用内容。").font(theme.type.subhead)
                            .foregroundStyle(theme.color.textSecondary)
                        Button("重新载入") { Task { await load() } }
                            .font(theme.type.subhead).frame(minHeight: PoetLayout.minHitTarget)
                    }
                }
                recentSection
                savedSection
                historySection
                if let message = ctx.userData.userDataError {
                    VStack(alignment: .leading, spacing: theme.space.sm) {
                        PoetErrorLine(message: message)
                        Button("重新同步") { Task { await ctx.userData.refresh(); await load() } }
                            .font(theme.type.subhead).frame(minHeight: PoetLayout.minHitTarget)
                    }
                }
            }
            .padding(.horizontal, theme.space.margin).padding(.vertical, theme.space.xl)
            .poetReadableWidth(680)
        }
        .background(theme.paper()).foregroundStyle(theme.color.textPrimary).tint(theme.color.accent)
        .zxNavigationTitle(ctx.composition.placement(.profile)?.label ?? "书房", role: .root)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            NavigationLink { LibrarySettingsView(ctx: ctx) } label: { Label("书房设置", systemImage: "gearshape") }
        } }
        .navigationDestination(isPresented: $showingDirectory) { CorpusDirectoryView(ctx: ctx) }
        .sheet(isPresented: $showingLogin) { LoginSheet(ctx: ctx) }
        .task(id: previewIDs) { await load() }
        .refreshable { await ctx.userData.refresh(); await load() }
    }

    // MARK: 最近翻阅

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            ZixiaoDesign.SectionLabel("最近翻阅")
            if let recent {
                NavigationLink { PoemDetailView(ctx: ctx, poem: recent).readingTransition(recent.id, in: books) } label: {
                    Group {
                        if typeSize.isAccessibilitySize {
                            recentDescription(recent)
                        } else {
                            HStack(alignment: .center, spacing: theme.space.margin) {
                                ReadingCover(title: ctx.workTitle(recent), author: ctx.composition.poet.name,
                                             genre: ctx.genre(for: recent), width: coverWidth)
                                    .readingTransitionSource(recent.id, in: books).accessibilityHidden(true)
                                recentDescription(recent).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(theme.space.margin)
                    .zxSurface(.e1, in: RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
                }.buttonStyle(.plain)
            } else if !loading && ctx.userData.reading.isEmpty {
                ZXGhostState("你的阅读，从这里留下。",
                             message: "最近打开的作品会回到这里。读到喜欢的篇章，轻点书签，留在自己的书房。",
                             actionTitle: "挑一篇开始阅读", systemImage: "book") {
                    showingDirectory = true
                }
            }
        }
    }

    private func recentDescription(_ poem: Poem) -> some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            Text(ctx.workTitle(poem)).font(theme.type.title3).foregroundStyle(theme.color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(poem.firstLine).font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
            if let date = ctx.userData.reading.first?.readDate {
                Text(date, format: .dateTime.month().day().hour().minute()).font(theme.type.caption)
                    .foregroundStyle(theme.color.textTertiary)
            }
            Label("再读一会儿", systemImage: "arrow.right").font(theme.type.subhead.weight(.semibold))
                .foregroundStyle(theme.color.accent).padding(.top, theme.space.xs)
        }
    }

    // MARK: 我的收藏

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            ShelfHeader(title: "我的收藏", linkTitle: "全部 \(savedIDs.count)",
                        accessibilityLabel: "全部收藏，\(savedIDs.count) 篇") {
                LibraryView(ctx: ctx, kind: .bookmarks)
            }
            if !saved.isEmpty {
                ForEach(saved.prefix(3)) { poem in
                    NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                        SavedPoemRow(poem: poem, title: ctx.workTitle(poem), genre: ctx.genre(for: poem).label)
                    }.buttonStyle(.plain)
                    InkDivider()
                }
            } else if !loading && savedIDs.isEmpty {
                Label("把想重读的篇章，留在这里。", systemImage: "bookmark")
                    .font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                    .padding(.vertical, theme.space.sm)
            }
        }
    }

    // MARK: 阅读记录

    private var historySection: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            ShelfHeader(title: "阅读记录", linkTitle: "查看全部", accessibilityLabel: "查看全部阅读记录") {
                LibraryView(ctx: ctx, kind: .history)
            }
            if ctx.userData.reading.count < 2 {
                Text(ctx.userData.reading.isEmpty ? "开始阅读后，这里会按时间留下记录。" : "最近的一篇在上方，之后的阅读会依次留在这里。")
                    .font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
            }
            ForEach(ctx.userData.reading.dropFirst().prefix(3)) { record in
                if let poem = indexed[record.poemId] {
                    NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                        VStack(alignment: .leading, spacing: theme.space.xs) {
                            Text(ctx.workTitle(poem)).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                            if let date = record.readDate {
                                Text(date, format: .dateTime.month().day().hour().minute())
                                    .font(theme.type.caption).foregroundStyle(theme.color.textTertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: PoetLayout.minHitTarget + theme.space.sm, alignment: .leading)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    InkDivider()
                }
            }
        }
    }

    private func load() async {
        let requested = previewIDs
        failed = false
        var available = indexed.filter { requested.contains($0.key) }
        for id in requested { if let poem = ctx.guide?.poem(id) { available[id] = poem } }
        indexed = available
        loading = available.isEmpty && !requested.isEmpty
        do {
            let poems = try await ctx.store.poems(ids: Array(Set(requested)))
            guard !Task.isCancelled, requested == previewIDs else { return }
            for poem in poems { available[poem.id] = ctx.guide?.poem(poem.id) ?? poem }
            indexed = available
            failed = requested.contains { available[$0] == nil }
        } catch {
            guard !Task.isCancelled, requested == previewIDs else { return }
            failed = requested.contains { available[$0] == nil }
        }
        loading = false
    }
}

/// 收藏行: 体裁小签 + 题目 + 首句。
private struct SavedPoemRow: View {
    let poem: Poem
    let title: String
    let genre: String
    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 体裁小签的尺寸 (固有尺寸: 一枚竖长的签)。
    private static let tagSize = CGSize(width: 42, height: 56)
    var body: some View {
        HStack(spacing: theme.space.lg) {
            if !typeSize.isAccessibilitySize {
                RoundedRectangle(cornerRadius: theme.radius.xs, style: .continuous).fill(theme.color.fill)
                    .frame(width: Self.tagSize.width, height: Self.tagSize.height)
                    .overlay { Text(genre).font(theme.type.headline).foregroundStyle(theme.color.accent) }
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: theme.space.xs) {
                Text(title).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                Text(poem.firstLine).font(theme.type.subhead).foregroundStyle(theme.color.textSecondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(theme.type.caption)
                .foregroundStyle(theme.color.textTertiary).accessibilityHidden(true)
        }
        .padding(.vertical, theme.space.xs).contentShape(Rectangle())
    }
}

// MARK: - 账号卡

/// 书房顶部的账号卡。匿名: 「登录以同步」, 点开登录页; 已绑定: 显示绑定方式, 点进账号页。
private struct AccountCard: View {
    let ctx: CompositionContext
    let showLogin: () -> Void
    @Environment(\.zxTheme) private var theme

    var body: some View {
        if ctx.isSignedIn {
            NavigationLink { AccountView(ctx: ctx) } label: { card }
                .buttonStyle(.plain)
                .accessibilityHint("查看账号与同步")
        } else {
            Button(action: showLogin) { card }
                .buttonStyle(ZXPressStyle(scale: 0.98))
                .accessibilityHint("用 Apple 或手机号登录")
        }
    }

    private var card: some View {
        HStack(spacing: theme.space.lg) {
            Image(systemName: ctx.isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                .font(theme.type.title1)
                .foregroundStyle(ctx.isSignedIn ? theme.color.accent : theme.color.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: theme.space.xs) {
                Text(ctx.isSignedIn ? "已登录" : "登录以同步")
                    .font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                Text(ctx.isSignedIn
                     ? AccountText.providers(of: ctx)
                     : "收藏与阅读记录先存在这台设备上，登录后可在其他设备继续。")
                    .font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(theme.type.caption)
                .foregroundStyle(theme.color.textTertiary).accessibilityHidden(true)
        }
        .padding(theme.space.lg)
        .zxSurface(.e1, in: RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// 账号相关的几句共用文案。
@MainActor
enum AccountText {
    /// 「已绑定 Apple 账号 · 手机号 +86 138****5678」。
    static func providers(of ctx: CompositionContext) -> String {
        let providers = ctx.accountState.providers
        var parts: [String] = []
        if providers.contains(.apple) { parts.append(ZXProvider.apple.displayName) }
        if providers.contains(.phone) {
            parts.append(ctx.auth.user?.phone.map { "\(ZXProvider.phone.displayName) \(masked($0))" }
                         ?? ZXProvider.phone.displayName)
        }
        if providers.contains(.email) { parts.append(ZXProvider.email.displayName) }
        if providers.contains(.google) { parts.append(ZXProvider.google.displayName) }
        return parts.isEmpty ? "收藏与阅读记录跟随账号同步。" : "已绑定 " + parts.joined(separator: " · ")
    }

    /// 手机号只露前三后四。
    static func masked(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        let local = digits.hasPrefix("86") && digits.count == 13 ? String(digits.dropFirst(2)) : digits
        guard local.count >= 7 else { return phone }
        let prefix = digits.count != local.count ? "+86 " : ""
        return prefix + local.prefix(3) + "****" + local.suffix(4)
    }

    /// 界面上的错误句: `ZXCoreError` 的说明; 取消返回 nil (静默)。
    static func message(for error: any Error, fallback: String) -> String? {
        let mapped = ZXCoreError(error)
        if mapped == .cancelled { return nil }
        if case .backend = mapped { return fallback }
        return mapped.errorDescription ?? fallback
    }
}

// MARK: - 书房设置

private struct LibrarySettingsView: View {
    let ctx: CompositionContext
    @Environment(\.zxTheme) private var theme
    var body: some View {
        List {
            Section {
                NavigationLink { AccountView(ctx: ctx) } label: {
                    Label(ctx.isSignedIn ? "账号与同步" : "登录以同步",
                          systemImage: ctx.isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                        .font(theme.type.body)
                }
            } header: { ListSectionTitle("账号与同步") } footer: {
                Text(ctx.isSignedIn ? AccountText.providers(of: ctx)
                     : "暂不登录也可以阅读和收藏。登录后，本机的收藏与阅读记录会并入账号。")
                    .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
            }
            .listRowBackground(theme.color.surface)
            Section {
                NavigationLink { AboutView(ctx: ctx) } label: {
                    Text("关于\(ctx.composition.app.displayName)与语料").font(theme.type.body)
                }
                if let guide = ctx.guide {
                    NavigationLink { GuideSourcesView(ctx: ctx, guide: guide) } label: {
                        Text("\(ctx.narrativeLabel)与资料说明").font(theme.type.body)
                    }
                }
                AboutLinks(app: ctx.composition.app)
            } header: { ListSectionTitle("关于") }
            .listRowBackground(theme.color.surface)
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden)
        .background(theme.paper()).tint(theme.color.accent)
        .zxNavigationTitle("书房设置", role: .secondary)
    }
}

/// 「隐私政策」「支持与反馈」两条外链 (地址来自编成; 缺省不显示)。
private struct AboutLinks: View {
    let app: AppMeta
    @Environment(\.zxTheme) private var theme
    var body: some View {
        if let privacy = app.privacyLink {
            Link(destination: privacy) { linkLabel("隐私政策", systemImage: "hand.raised") }
                .accessibilityHint("在浏览器中打开")
        }
        if let support = app.supportLink {
            Link(destination: support) { linkLabel("支持与反馈", systemImage: "questionmark.bubble") }
                .accessibilityHint("在浏览器中打开")
        }
    }
    private func linkLabel(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage).font(theme.type.body).foregroundStyle(theme.color.textPrimary)
            Spacer()
            Image(systemName: "arrow.up.right").font(theme.type.caption)
                .foregroundStyle(theme.color.textTertiary).accessibilityHidden(true)
        }
        .frame(minHeight: PoetLayout.minHitTarget)
    }
}

private extension ReadingState {
    var readDate: Date? {
        guard let lastReadAt else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: lastReadAt) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: lastReadAt)
    }
}

// MARK: - 收藏 / 阅读记录全表

struct LibraryView: View {
    enum Kind { case bookmarks, history }
    let ctx: CompositionContext
    let kind: Kind
    @State private var poems: [Poem] = []
    @State private var loading = true
    @State private var failed = false
    @State private var query = ""
    @State private var showingDirectory = false
    @Environment(\.zxTheme) private var theme
    private var ids: [UUID] {
        kind == .bookmarks ? ctx.userData.bookmarks.filter { $0.targetType == "poem" }.map(\.targetId)
            : ctx.userData.reading.map(\.poemId)
    }
    private var filtered: [Poem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? poems : poems.filter { $0.title.localizedStandardContains(term) || $0.content.localizedStandardContains(term) }
    }
    var body: some View {
        List(filtered) { poem in
            NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                VStack(alignment: .leading, spacing: theme.space.xs) {
                    PoemRow(poem: poem, showsDisclosure: false, displayTitle: ctx.workTitle(poem))
                    if kind == .history, let date = ctx.userData.reading.first(where: { $0.poemId == poem.id })?.readDate {
                        Text(date, format: .dateTime.month().day().hour().minute())
                            .font(theme.type.caption).foregroundStyle(theme.color.textTertiary)
                    }
                }.padding(.vertical, theme.space.xs)
            }.listRowBackground(theme.paper()).listRowSeparatorTint(theme.rule)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).poetReadableWidth()
        .background(theme.paper()).tint(theme.color.accent)
        .zxNavigationTitle(kind == .bookmarks ? "我的收藏" : "阅读记录",
                           subtitle: kind == .history ? "最近 50 篇，按阅读时间排列" : "\(ids.count) 篇喜欢的诗文",
                           role: .secondary)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "查找标题或诗句")
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if loading { LoadingStateView() }
            else if failed { LoadFailureView(retry: load) }
            else if poems.isEmpty {
                ZXGhostState(kind == .bookmarks ? "还没有收藏" : "还没有阅读记录",
                             message: kind == .bookmarks ? "读到喜欢的篇章，轻点书签，就会留在这里。"
                                                         : "从作品页打开一篇诗文，慢慢读。",
                             actionTitle: "挑一篇开始阅读", systemImage: "book") {
                    showingDirectory = true
                }
                .background(theme.paper())
            } else if filtered.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .navigationDestination(isPresented: $showingDirectory) { CorpusDirectoryView(ctx: ctx) }
        .task(id: ids) { await load() }
        .refreshable { await ctx.userData.refresh(); await load() }
    }
    private func load() async {
        let bundled = ctx.guide?.poems(ids) ?? []
        if poems.isEmpty { poems = bundled }
        loading = poems.isEmpty && !ids.isEmpty
        failed = false
        do {
            let fetched = try await ctx.store.poems(ids: ids)
            guard !Task.isCancelled else { return }
            let remote = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            let local = Dictionary(uniqueKeysWithValues: bundled.map { ($0.id, $0) })
            poems = ids.compactMap { local[$0] ?? remote[$0] }
        } catch { if !Task.isCancelled { failed = poems.isEmpty && !ids.isEmpty } }
        loading = false
    }
}

// MARK: - 关于

struct AboutView: View {
    let ctx: CompositionContext
    @Environment(\.zxTheme) private var theme
    private var app: AppMeta { ctx.composition.app }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.xxl) {
                VStack(alignment: .leading, spacing: theme.space.md) {
                    ZixiaoDesign.SectionLabel("诗人志系列")
                    Text(app.displayName).font(theme.type.display).tracking(theme.type.tracking(for: .display))
                        .foregroundStyle(theme.color.textPrimary).accessibilityAddTraits(.isHeader)
                    if let tagline = app.tagline {
                        Text(tagline).font(theme.type.body).lineSpacing(theme.space.sm)
                            .foregroundStyle(theme.color.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let thesis = app.thesis {
                    Text(thesis).font(theme.bodyFont(19, relativeTo: .title3)).lineSpacing(theme.space.sm)
                        .foregroundStyle(theme.color.accent)
                }
                InkDivider()
                aboutSection("如何读这本志") {
                    paragraph("在今日遇见一篇作品，沿\(ctx.narrativeLabel)篇章了解处境，再回到原文。喜欢的篇章，留在自己的书房。",
                              primary: true)
                    paragraph("年谱记载与诗文原文按现有底本呈现。主题选篇和短导读为编辑整理；白话、提要与赏析由 AI 辅助生成，供阅读参考。")
                }
                if let credits = app.credits, !credits.isEmpty {
                    InkDivider()
                    aboutSection("内容来源") {
                        ForEach(credits, id: \.self) { credit in
                            Text(credit).font(theme.type.callout).lineSpacing(theme.space.xs + theme.space.xxs)
                                .foregroundStyle(theme.color.textSecondary).fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                InkDivider()
                aboutSection("收藏与阅读记录") {
                    paragraph(ctx.isSignedIn
                        ? "收藏和阅读记录跟随账号同步。同一账号也可用于子晓纪的其他应用，\(app.displayName)的记录单独保存。"
                        : "暂不登录也可以阅读和收藏，记录先保存在这台设备上。登录后会并入账号，方便换设备继续阅读。")
                }
                if app.privacyLink != nil || app.supportLink != nil {
                    InkDivider()
                    aboutSection("隐私与支持") {
                        VStack(alignment: .leading, spacing: 0) { AboutLinks(app: app) }
                    }
                }
            }
            .padding(.horizontal, theme.space.margin).padding(.vertical, theme.space.xl).poetReadableWidth(640)
        }
        .background(theme.paper()).foregroundStyle(theme.color.textPrimary).tint(theme.color.accent)
        .zxNavigationTitle("关于与语料", role: .secondary)
    }

    private func aboutSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            ZixiaoDesign.SectionLabel(title)
            content()
        }
    }

    private func paragraph(_ text: String, primary: Bool = false) -> some View {
        Text(text).font(theme.type.body).lineSpacing(theme.space.sm)
            .foregroundStyle(primary ? theme.color.textPrimary : theme.color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 账号页

/// 账号与同步: 绑定方式 → 退出 → 注销。匿名时 (退出 / 注销之后) 改为「登录以同步」。
private struct AccountView: View {
    let ctx: CompositionContext
    @State private var showingLogin = false
    @State private var confirmingSignOut = false
    @State private var signingOut = false
    @Environment(\.zxTheme) private var theme

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: theme.space.sm) {
                    Label(ctx.isSignedIn ? "已登录" : "未登录",
                          systemImage: ctx.isSignedIn ? "checkmark.circle.fill" : "person.crop.circle")
                        .font(theme.type.headline)
                        .foregroundStyle(ctx.isSignedIn ? theme.color.accent : theme.color.textPrimary)
                    Text(ctx.isSignedIn
                         ? AccountText.providers(of: ctx)
                         : "现在使用的是这台设备上的匿名身份。登录后，收藏与阅读记录会随账号同步。")
                        .font(theme.type.subhead).foregroundStyle(theme.color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, theme.space.xs)
                if !ctx.isSignedIn {
                    Button { showingLogin = true } label: {
                        Label("登录以同步", systemImage: "person.crop.circle.badge.plus").font(theme.type.body)
                    }.frame(minHeight: PoetLayout.minHitTarget)
                }
            } footer: {
                Text("同一账号可用于子晓纪的各个应用，各应用的收藏与阅读记录分开保存。")
                    .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
            }
            .listRowBackground(theme.color.surface)
            if ctx.isSignedIn || PoetQA.deleteAccountPreview {
                Section {
                    Button(role: .destructive) { confirmingSignOut = true } label: {
                        HStack {
                            Text(signingOut ? "正在退出…" : "退出登录").font(theme.type.body)
                            if signingOut { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(signingOut || !ctx.isSignedIn).frame(minHeight: PoetLayout.minHitTarget)
                    .accessibilityIdentifier("zx.poet.signOut")
                    NavigationLink { DeleteAccountView(ctx: ctx) } label: {
                        Text("注销账号").font(theme.type.body).foregroundStyle(theme.color.danger)
                    }
                    .accessibilityIdentifier("zx.poet.deleteAccount")
                } footer: {
                    Text("注销会永久删除账号与全部云端数据；这台设备上的阅读设置保留。")
                        .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                }
                .listRowBackground(theme.color.surface)
            }
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden)
        .background(theme.paper()).tint(theme.color.accent)
        .zxNavigationTitle("账号与同步", role: .secondary)
        .sheet(isPresented: $showingLogin) { LoginSheet(ctx: ctx) }
        .confirmationDialog("退出当前账号？", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task {
                    signingOut = true
                    await ctx.signOut()
                    signingOut = false
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("账号里的收藏与阅读记录会留在云端，再次登录即可找回。退出后，这台设备会换成一个新的匿名身份，从空的书房开始。")
        }
    }
}

// MARK: - 注销账号

/// 截图 / 走查用的 DEBUG 开关 (与 `PoetAppRoot` 的 `-tab` 同法), 发布包里恒为 false。
enum PoetQA {
    /// `-qaDeleteAccountPreview YES`: 匿名态也显示「注销账号」入口与按钮 (确认后 `delete()` 不发请求)。
    static var deleteAccountPreview: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "qaDeleteAccountPreview")
        #else
        false
        #endif
    }
}

/// 注销: 说明删什么 → 确认 (destructive) → 进度 → 回到匿名态 (返回账号页, 那里已显示「未登录」)。
private struct DeleteAccountView: View {
    let ctx: CompositionContext
    @State private var confirming = false
    @State private var deleting = false
    @State private var errorMessage: String?
    @Environment(\.zxTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.xl) {
                VStack(alignment: .leading, spacing: theme.space.sm) {
                    Text("注销后，以下内容会被永久删除，无法恢复：")
                        .font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: theme.space.md) {
                    item("bookmark", "\(ctx.composition.app.displayName)里的收藏、阅读进度与笔记")
                    item("square.stack", "同一账号在子晓纪其他应用中的数据")
                    item("link", "Apple 账号 / 手机号与这个账号的绑定随之解除")
                }
                .padding(theme.space.margin)
                .zxSurface(.e1, in: RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
                Text("这台设备上的阅读设置（字号、纸色、排版方向）会保留。注销完成后，应用会以一个新的匿名身份继续使用；之后用同一个 Apple 账号或手机号登录，会得到一个全新的账号。")
                    .font(theme.type.subhead).lineSpacing(theme.space.xs)
                    .foregroundStyle(theme.color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let errorMessage { PoetErrorLine(message: errorMessage) }
                Button(role: .destructive) { confirming = true } label: {
                    HStack(spacing: theme.space.sm) {
                        if deleting { ProgressView().tint(theme.color.statusOn) }
                        Text(deleting ? "正在注销…" : "注销账号")
                    }
                    .font(theme.type.headline)
                    .foregroundStyle(theme.color.statusOn)
                    .frame(maxWidth: .infinity, minHeight: PoetLayout.minHitTarget + theme.space.xs)
                    .background(theme.color.danger, in: RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                }
                .buttonStyle(ZXPressStyle())
                .disabled(deleting || !(ctx.isSignedIn || PoetQA.deleteAccountPreview))
                .accessibilityIdentifier("zx.poet.deleteAccount.confirm")
            }
            .padding(.horizontal, theme.space.margin).padding(.vertical, theme.space.xl).poetReadableWidth(640)
        }
        .background(theme.paper()).tint(theme.color.accent)
        .zxNavigationTitle("注销账号", role: .secondary)
        .navigationBarBackButtonHidden(deleting)
        .confirmationDialog("确定注销账号？", isPresented: $confirming, titleVisibility: .visible) {
            Button("注销账号", role: .destructive) { Task { await delete() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("账号与全部云端数据会被永久删除，无法恢复。")
        }
        .sensoryFeedback(.warning, trigger: confirming) { _, new in new }
    }

    private func item(_ systemImage: String, _ text: String) -> some View {
        Label {
            Text(text).font(theme.type.body).foregroundStyle(theme.color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(theme.color.danger)
        }
    }

    private func delete() async {
        // 只有已绑定的账号才走删号 RPC (DEBUG 预览开关打开时, 匿名态也能走到这里, 但不发请求)。
        guard ctx.isSignedIn else {
            errorMessage = "当前没有已登录的账号。"
            return
        }
        deleting = true; errorMessage = nil
        defer { deleting = false }
        do {
            try await ctx.deleteAccount()
            dismiss()
        } catch {
            errorMessage = AccountText.message(for: error, fallback: "注销未完成，请检查网络后重试。")
                ?? "注销未完成，请稍后重试。"
        }
    }
}

// MARK: - 登录

/// 登录页 (sheet): Apple → 或手机号 (号码 → 验证码)。成功即关闭。
private struct LoginSheet: View {
    let ctx: CompositionContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.zxTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.space.xl) {
                    Text("登录后，收藏与阅读记录随账号同步，换一台设备也能接着读。本机已有的收藏会并入账号。")
                        .font(theme.type.body).lineSpacing(theme.space.xs)
                        .foregroundStyle(theme.color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if ctx.supportsAppleSignIn {
                        AppleSignInBlock(ctx: ctx)
                        HStack(spacing: theme.space.md) {
                            InkDivider()
                            Text("或用手机号").font(theme.type.footnote).foregroundStyle(theme.color.textTertiary).fixedSize()
                            InkDivider()
                        }
                    }
                    PhoneSignInBlock(ctx: ctx)
                }
                .padding(theme.space.margin).poetReadableWidth(560)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.paper())
            .zxNavigationTitle("登录以同步", role: .secondary)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .tint(theme.color.accent)
        .presentationDragIndicator(.visible)
        .onChange(of: ctx.isSignedIn) { _, signedIn in if signedIn { dismiss() } }
    }
}

private struct AppleSignInBlock: View {
    let ctx: CompositionContext
    @State private var nonce = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @Environment(\.zxTheme) private var theme
    /// 系统 Apple 按钮的高度 (HIG 最小 44, 与主按钮同高)。
    private static let buttonHeight: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            SignInWithAppleButton(.signIn) { request in
                nonce = ZXAppleSignIn.prepare(request)
            } onCompletion: { result in
                Task { await complete(result) }
            }
            .signInWithAppleButtonStyle(theme.isDark ? .white : .black)
            .frame(height: Self.buttonHeight)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
            .disabled(busy)
            .overlay { if busy { ProgressView() } }
            .accessibilityLabel("通过 Apple 登录")
            .accessibilityIdentifier("zx.poet.signInApple")
            if let errorMessage { PoetErrorLine(message: errorMessage) }
        }
    }

    private func complete(_ result: Result<ASAuthorization, any Error>) async {
        errorMessage = nil
        switch result {
        case .failure(let error):
            // Apple 面板自己失败 (未登 Apple ID、授权被拒…); 取消静默。
            let mapped = ZXAppleSignIn.map(error)
            if mapped != .cancelled { errorMessage = "Apple 登录未完成，请重试。" }
        case .success(let authorization):
            busy = true
            defer { busy = false }
            do {
                let credential = try ZXAppleSignIn.credential(from: authorization, rawNonce: nonce)
                try await ctx.signInWithApple(idToken: credential.idToken, rawNonce: credential.rawNonce,
                                              fullName: credential.fullName)
            } catch {
                errorMessage = AccountText.message(for: error, fallback: "Apple 登录暂不可用，请稍后重试。")
            }
        }
    }
}

private struct PhoneSignInBlock: View {
    let ctx: CompositionContext
    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var phase: ZXCodeEntryPhase = .editing
    @State private var busy = false
    @State private var errorMessage: String?
    @FocusState private var phoneFocused: Bool
    @Environment(\.zxTheme) private var theme
    /// 输入框与主按钮的高度 (固有尺寸)。
    private static let controlHeight: CGFloat = 48

    private var digits: String { phone.filter { $0.isASCII && $0.isNumber } }
    private var validPhone: Bool {
        let clean = phone.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if clean.hasPrefix("+") {
            return clean.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
                && (8...15).contains(digits.count) && digits.first != "0"
        }
        return clean.allSatisfy { $0.isASCII && $0.isNumber } && digits.count == 11 && digits.first == "1"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            if codeSent { codeStep } else { phoneStep }
            if let errorMessage { PoetErrorLine(message: errorMessage) }
        }
    }

    private var phoneStep: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            TextField("手机号", text: $phone)
                .keyboardType(.phonePad).textContentType(.telephoneNumber)
                .focused($phoneFocused)
                .font(theme.type.body.monospacedDigit())
                .foregroundStyle(theme.color.textPrimary)
                .padding(.horizontal, theme.space.lg)
                .frame(minHeight: Self.controlHeight)
                .background(theme.color.fill, in: RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                .disabled(busy)
                .accessibilityLabel("手机号")
                .accessibilityIdentifier("zx.poet.phoneField")
            Text("中国大陆可直接输入 11 位手机号，其他地区请加国家代码。")
                .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
            Button { Task { await sendCode() } } label: {
                HStack(spacing: theme.space.sm) {
                    if busy { ProgressView().tint(theme.color.accentOn) }
                    Text(busy ? "正在发送…" : "获取验证码")
                }
                .font(theme.type.headline)
                .foregroundStyle(theme.color.accentOn)
                .frame(maxWidth: .infinity, minHeight: Self.controlHeight)
                .background(theme.color.accent.opacity(validPhone ? 1 : 0.4),
                            in: RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
            }
            .buttonStyle(ZXPressStyle())
            .disabled(busy || !validPhone)
            .accessibilityIdentifier("zx.poet.sendCode")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起键盘") { phoneFocused = false }
            }
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            Text("验证码已发送至 \(phone)").font(theme.type.callout).foregroundStyle(theme.color.textPrimary)
            ZXCodeEntry(code: $code, phase: phase) { value in
                Task { await verify(value) }
            }
            HStack {
                ZXResendCountdown { Task { await sendCode(resend: true) } }
                Spacer()
                Button("更换手机号") {
                    codeSent = false; code = ""; phase = .editing; errorMessage = nil
                }
                .font(theme.type.footnote).frame(minHeight: PoetLayout.minHitTarget)
                .disabled(busy)
            }
        }
    }

    private func sendCode(resend: Bool = false) async {
        guard validPhone, !busy else { return }
        busy = true; errorMessage = nil
        defer { busy = false }
        do {
            try await ctx.sendPhoneOTP(phone)
            code = ""; phase = .editing
            if !resend { codeSent = true }
        } catch {
            errorMessage = AccountText.message(for: error, fallback: "验证码未能发送，请检查号码或稍后重试。")
        }
    }

    private func verify(_ value: String) async {
        guard !busy else { return }
        busy = true; errorMessage = nil; phase = .verifying
        defer { busy = false }
        do {
            try await ctx.verifyPhoneOTP(phone, code: value)
            phase = .succeeded
        } catch {
            phase = .failed
            errorMessage = AccountText.message(for: error, fallback: "验证码无效或已过期，请核对后重试。")
        }
    }
}
