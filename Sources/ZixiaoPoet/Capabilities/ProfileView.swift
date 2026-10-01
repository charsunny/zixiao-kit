import SwiftUI
import AuthenticationServices
import ZixiaoCore

struct ProfileView: View {
    let ctx: CompositionContext
    @State private var indexed: [UUID: Poem] = [:]
    @State private var loading = true
    @State private var failed = false
    @Namespace private var books
    @Environment(\.dynamicTypeSize) private var typeSize
    private var theme: Theme { ctx.theme }
    private var savedIDs: [UUID] { ctx.userData.bookmarks.filter { $0.targetType == "poem" }.map(\.targetId) }
    private var previewIDs: [UUID] { Array(savedIDs.prefix(6)) + ctx.userData.reading.prefix(4).map(\.poemId) }
    private var saved: [Poem] { savedIDs.prefix(6).compactMap { indexed[$0] } }
    private var recent: Poem? { ctx.userData.reading.first.flatMap { indexed[$0.poemId] } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if loading { ProgressView("正在打开书房…").frame(maxWidth: .infinity) }
                if failed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("部分作品暂未载入，已保留可用内容。").font(.subheadline).foregroundStyle(.secondary)
                        Button("重新载入") { Task { await load() } }.frame(minHeight: 44)
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    NativeSectionHeader(title: "最近翻阅") { EmptyView() }
                    if let recent {
                        NavigationLink { PoemDetailView(ctx: ctx, poem: recent).readingTransition(recent.id, in: books) } label: {
                            Group {
                                if typeSize.isAccessibilitySize {
                                    recentDescription(recent)
                                } else {
                                    HStack(alignment: .center, spacing: 20) {
                                        ReadingCover(title: ctx.workTitle(recent), author: ctx.composition.poet.name, genre: ctx.genre(for: recent), height: 190)
                                            .frame(width: 122).readingTransitionSource(recent.id, in: books).accessibilityHidden(true)
                                        recentDescription(recent).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20).background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }.buttonStyle(.plain)
                    } else if !loading && ctx.userData.reading.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("你的阅读，从这里留下。").font(.title3.weight(.semibold))
                            Text("最近打开的作品会回到这里。读到喜欢的篇章，轻点书签，留在自己的书房。")
                                .font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                            NavigationLink { CorpusDirectoryView(ctx: ctx) } label: {
                                Label("挑一篇开始阅读", systemImage: "book").frame(minHeight: 44)
                            }.buttonStyle(.borderless)
                        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    NativeSectionHeader(title: "我的收藏") {
                        NavigationLink { LibraryView(ctx: ctx, kind: .bookmarks) } label: {
                            Text("全部 \(savedIDs.count)").font(.subheadline)
                        }.accessibilityLabel("全部收藏，\(savedIDs.count) 篇")
                    }
                    if !saved.isEmpty {
                        ForEach(saved.prefix(3)) { poem in
                            NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                                HStack(spacing: 16) {
                                    if !typeSize.isAccessibilitySize {
                                        RoundedRectangle(cornerRadius: 4).fill(theme.accent.opacity(0.12))
                                            .frame(width: 42, height: 56).overlay { Text(ctx.genre(for: poem).label).font(.headline).foregroundStyle(theme.accent) }
                                            .accessibilityHidden(true)
                                    }
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(ctx.workTitle(poem)).font(.headline).foregroundStyle(.primary)
                                        Text(poem.firstLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }.padding(.vertical, 5).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    } else if !loading && savedIDs.isEmpty {
                        Label("把想重读的篇章，留在这里。", systemImage: "bookmark")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    NativeSectionHeader(title: "阅读记录") {
                        NavigationLink { LibraryView(ctx: ctx, kind: .history) } label: { Text("查看全部").font(.subheadline) }
                    }
                    if ctx.userData.reading.count < 2 {
                        Text(ctx.userData.reading.isEmpty ? "开始阅读后，这里会按时间留下记录。" : "最近的一篇在上方，之后的阅读会依次留在这里。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(ctx.userData.reading.dropFirst().prefix(3)) { record in
                        if let poem = indexed[record.poemId] {
                            NavigationLink { PoemDetailView(ctx: ctx, poem: poem) } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(ctx.workTitle(poem)).font(.headline).foregroundStyle(.primary)
                                    if let date = record.readDate { Text(date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                                }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                if let message = ctx.userData.userDataError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                        Button("重新同步") { Task { await ctx.userData.refresh(); await load() } }.frame(minHeight: 44)
                    }
                }
            }.padding(.horizontal, 20).padding(.vertical, 22).poetReadableWidth(680)
        }.background(theme.paper).foregroundStyle(theme.ink)
            .navigationTitle(ctx.composition.placement(.profile)?.label ?? "书房").toolbarTitleDisplayMode(.inlineLarge)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { LibrarySettingsView(ctx: ctx) } label: { Label("书房设置", systemImage: "gearshape") }
            } }
            .task(id: previewIDs) { await load() }
            .refreshable { await ctx.userData.refresh(); await load() }
    }
    private func recentDescription(_ poem: Poem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ctx.workTitle(poem)).font(.title3.bold()).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Text(poem.firstLine).font(.subheadline).foregroundStyle(.secondary)
            if let date = ctx.userData.reading.first?.readDate {
                Text(date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
            }
            Label("再读一会儿", systemImage: "arrow.right").font(.subheadline.weight(.semibold)).foregroundStyle(theme.accent).padding(.top, 4)
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

private struct LibrarySettingsView: View {
    let ctx: CompositionContext
    @State private var showingAccount = false
    var body: some View {
        List {
            Section("账号与同步") {
                Button { showingAccount = true } label: {
                    Label(ctx.isSignedIn ? "管理账号" : "登录与同步", systemImage: "person.crop.circle")
                }
                Text(ctx.isSignedIn ? "收藏与最近阅读跟随账号同步。" : "当前使用本机身份保存。登录后，本机收藏可并入账号。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("关于") {
                NavigationLink("关于\(ctx.composition.app.displayName)与语料") { AboutView(ctx: ctx) }
                if let guide = ctx.guide {
                    NavigationLink("\(ctx.narrativeLabel)与资料说明") { GuideSourcesView(ctx: ctx, guide: guide) }
                }
            }
        }.navigationTitle("书房设置").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAccount) { AccountView(ctx: ctx) }
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

struct LibraryView: View {
    enum Kind { case bookmarks, history }
    let ctx: CompositionContext
    let kind: Kind
    @State private var poems: [Poem] = []
    @State private var loading = true
    @State private var failed = false
    @State private var query = ""
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
                VStack(alignment: .leading, spacing: 5) {
                    PoemRow(poem: poem, theme: ctx.theme, showsDisclosure: false, displayTitle: ctx.workTitle(poem))
                    if kind == .history, let date = ctx.userData.reading.first(where: { $0.poemId == poem.id })?.readDate {
                        Text(date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }.listRowBackground(ctx.theme.paper).listRowSeparatorTint(ctx.theme.rule)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).poetReadableWidth().background(ctx.theme.paper)
        .navigationTitle(kind == .bookmarks ? "我的收藏" : "阅读记录")
        .navigationBarTitleDisplayMode(.inline)
        .poetNavigationSubtitle(kind == .history ? "最近 50 篇，按阅读时间排列" : "\(ids.count) 篇喜欢的诗文")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "查找标题或诗句")
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if loading { LoadingStateView() }
            else if failed { LoadFailureView(retry: load) }
            else if poems.isEmpty {
                ContentUnavailableView(kind == .bookmarks ? "还没有收藏" : "还没有阅读记录",
                    systemImage: kind == .bookmarks ? "bookmark" : "book",
                    description: Text("从作品页打开一篇诗文，慢慢读。"))
            } else if filtered.isEmpty { ContentUnavailableView.search(text: query) }
        }
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

struct AboutView: View {
    let ctx: CompositionContext
    private var theme: Theme { ctx.theme }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                EditorialHeading(eyebrow: "微诗 · 诗人志系列", title: ctx.composition.app.displayName,
                                 introduction: ctx.composition.app.tagline, theme: theme)
                if let thesis = ctx.composition.app.thesis {
                    Text(thesis).font(PoetFont.verse).lineSpacing(8).foregroundStyle(theme.accent)
                }
                EditorialRule(theme: theme)
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(text: "如何读这本志", theme: theme)
                    Text("在今日遇见一篇作品，沿\(ctx.narrativeLabel)篇章了解处境，再回到原文。喜欢的篇章，留在自己的书房。")
                        .font(PoetFont.body).lineSpacing(8)
                    Text("年谱记载与诗文原文按现有底本呈现。主题选篇和短导读为编辑整理；白话、提要与赏析由 AI 辅助生成，供阅读参考。")
                        .font(PoetFont.body).lineSpacing(8).foregroundStyle(theme.secondaryInk)
                }
                EditorialRule(theme: theme)
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(text: "语料从哪里来", theme: theme)
                    ForEach(ctx.composition.data?.sources ?? [], id: \.self) { source in
                        Text(source).font(PoetFont.callout).lineSpacing(6)
                            .foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    }
                }
                EditorialRule(theme: theme)
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(text: "收藏与阅读记录", theme: theme)
                    Text(ctx.isSignedIn
                        ? "与微诗共用账号，\(ctx.composition.app.displayName)的收藏和阅读记录单独保存。"
                        : "暂不登录也可以阅读和收藏。本机已有记录会在登录后并入账号，方便换设备继续阅读。")
                        .font(PoetFont.body).lineSpacing(8).foregroundStyle(theme.secondaryInk)
                }
            }.padding(.horizontal, Metric.gutter).padding(.vertical, 24).poetReadableWidth(640)
        }
        .background(theme.paper).foregroundStyle(theme.ink)
        .navigationTitle("关于与语料").navigationBarTitleDisplayMode(.inline)
    }
}

private struct AccountView: View {
    let ctx: CompositionContext
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                GlazePanel(theme: ctx.theme) { SignInBlock(ctx: ctx) }
                    .padding(Metric.gutter).poetReadableWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ctx.theme.paper)
            .navigationTitle(ctx.isSignedIn ? "账号与同步" : "登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .tint(ctx.theme.accent).presentationDragIndicator(.visible)
    }
}

struct SignInBlock: View {
    let ctx: CompositionContext
    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var message: String?
    @State private var rawNonce = ""
    @State private var resendAfter = Date.distantPast
    @State private var confirmingSignOut = false
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focused: Field?
    private enum Field { case phone, code }
    private var theme: Theme { ctx.theme }
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
        VStack(alignment: .leading, spacing: 18) {
            if ctx.isSignedIn {
                Label("已登录", systemImage: "checkmark.circle.fill")
                    .font(PoetFont.entryTitle).foregroundStyle(theme.accent)
                Text("与微诗共用账号，\(ctx.composition.app.displayName)的收藏和阅读记录单独保存。")
                    .font(PoetFont.body).foregroundStyle(theme.secondaryInk)
                Button("退出登录", role: .destructive) { confirmingSignOut = true }
                    .frame(minHeight: 44).disabled(busy)
            } else {
                Text("让喜欢的诗文，随你到下一台设备。")
                    .font(PoetFont.body).foregroundStyle(theme.secondaryInk)
                if ctx.supportsAppleSignIn {
                SignInWithAppleButton(.continue) { request in
                    rawNonce = ZXAppleNonce.make()
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = ZXAppleNonce.sha256(rawNonce)
                } onCompletion: { result in Task { await completeApple(result) } }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(busy)
                Text("或用手机号").font(PoetFont.meta).foregroundStyle(theme.secondaryInk)
                }
                if codeSent {
                    Text("验证码已发送至 \(phone)").font(PoetFont.callout)
                    Button("更换手机号") { codeSent = false; code = ""; message = nil; focused = .phone }
                        .disabled(busy).frame(minHeight: 44)
                    TextField("6 位验证码", text: $code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .focused($focused, equals: .code)
                        .accessibilityLabel("短信验证码")
                        .font(.body.monospacedDigit()).padding(14)
                        .background(theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .disabled(busy)
                        .onChange(of: code) { _, value in code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = max(0, Int(ceil(resendAfter.timeIntervalSince(context.date))))
                        Button(seconds > 0 ? "\(seconds) 秒后可重新发送" : "重新发送验证码") {
                            Task { await sendCode() }
                        }
                        .font(PoetFont.meta).frame(minHeight: 44)
                        .disabled(seconds > 0 || busy)
                    }
                } else {
                    TextField("手机号", text: $phone)
                        .keyboardType(.phonePad).textContentType(.telephoneNumber)
                        .focused($focused, equals: .phone)
                        .font(.body).padding(14)
                        .background(theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .disabled(busy).accessibilityLabel("手机号")
                    Text("中国大陆可直接输入 11 位手机号，其他地区请加国家代码。")
                        .font(PoetFont.meta).foregroundStyle(theme.secondaryInk)
                }
                Button {
                    Task { if codeSent { await verify() } else { await sendCode() } }
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().tint(.primary) }
                        Text(busy ? "正在处理…" : (codeSent ? "登录" : "获取验证码"))
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }
                .poetActionStyle(prominent: true).controlSize(.large)
                .disabled(busy || !validPhone || (codeSent && code.count != 6))
                Text("登录后，本机已有收藏会并入账号，重复的会自动合并。")
                    .font(PoetFont.meta).foregroundStyle(theme.secondaryInk)
            }
            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(PoetFont.meta).foregroundStyle(theme.seal)
            }
        }
        .foregroundStyle(theme.ink)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起键盘") { focused = nil }
            }
        }
        .confirmationDialog("退出当前账号？", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task {
                    busy = true; message = nil
                    await ctx.signOut()
                    busy = false
                }
            }
        } message: { Text("账号内的收藏会保留，退出后显示本机记录。") }
    }

    private func sendCode() async {
        guard validPhone, !busy else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            try await ctx.sendPhoneOTP(phone)
            codeSent = true; code = ""; resendAfter = .now.addingTimeInterval(60); focused = .code
        } catch { message = "验证码未能发送，请检查号码或稍后重试。" }
    }
    private func verify() async {
        guard code.count == 6, !busy else { return }
        busy = true; message = nil; focused = nil
        defer { busy = false }
        do { try await ctx.verifyPhoneOTP(phone, code: code) }
        catch { message = "验证码无效或已过期，请核对后重试。" }
    }
    private func completeApple(_ result: Result<ASAuthorization, Error>) async {
        busy = true; message = nil
        defer { busy = false }
        do {
            guard case .success(let auth) = result,
                  let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8)
            else {
                if case .failure(let error) = result,
                   (error as? ASAuthorizationError)?.code != .canceled { message = "Apple 登录未完成，请重试。" }
                return
            }
            let name = [credential.fullName?.familyName, credential.fullName?.givenName].compactMap { $0 }.joined()
            try await ctx.signInWithApple(idToken: token, rawNonce: rawNonce, fullName: name.isEmpty ? nil : name)
        } catch { message = "Apple 登录暂不可用，请稍后重试。" }
    }
}
