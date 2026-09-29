import SwiftUI
import ZixiaoDesign

/// 竖排 / 横排。
public enum ReaderOrientation: String, Sendable, Codable, CaseIterable {
    /// 线装书: 字从上到下, 列从右到左, 往右划翻下一页。
    case vertical
    /// 横排对照: 原文与白话左右并列。
    case horizontal
}

/// 白话 (段落 `plain`) 怎么显示。竖排与横排各有对应的排法, 一个偏好管两种版式。
public enum ReaderPlainMode: String, Sendable, Codable, CaseIterable {
    /// 夹注: 竖排以双行小字接在原文段后; 横排以小字接在原文之下。
    case interlinear
    /// 对照: 竖排白话另起单行小字列; 横排原文与白话左右并列。
    case parallel
    /// 不显示白话。
    case hidden

    /// 界面上的名字。
    public var title: String {
        switch self {
        case .interlinear: "夹注"
        case .parallel: "对照"
        case .hidden: "不显示白话"
        }
    }

    /// 三态轮换的下一个: 夹注 → 对照 → 不显示 → 夹注。
    public var next: ReaderPlainMode {
        switch self {
        case .interlinear: .parallel
        case .parallel: .hidden
        case .hidden: .interlinear
        }
    }

    /// 竖排版式里的排法。
    public var classicLayout: ClassicPlainLayout {
        switch self {
        case .interlinear: .interlinear
        case .parallel: .columns
        case .hidden: .none
        }
    }
}

/// 竖排轻点页边的去向 (纯逻辑, 见 `ClassicReaderView.pageTurn`)。
enum ReaderPageTurn: Equatable {
    case page(Int)
    case previousChapter
    case nextChapter
}

/// 外部定位请求: 同一段再定位一次也要生效, 所以带一个递增的序号。
struct ReaderLocateRequest: Equatable {
    var passageId: String
    var token: Int
}

/// 阅读位置回报: 直接喂给 `ReadingStateStore.move`。
public struct ReaderLocation: Sendable, Hashable {
    public var bookId: String
    public var chapterId: String
    public var passageId: String?

    /// 公开构造: App 恢复「上次读到」与测试都要能造一个位置。
    public init(bookId: String, chapterId: String, passageId: String? = nil) {
        self.bookId = bookId
        self.chapterId = chapterId
        self.passageId = passageId
    }
}

/// 长按选中的一段。App 决定是弹摘抄面板还是直接收进摘抄本。
public struct ReaderSelection: Sendable, Hashable {
    public var bookId: String
    public var bookTitle: String
    public var chapter: Chapter
    public var passage: Passage

    public init(bookId: String, bookTitle: String, chapter: Chapter, passage: Passage) {
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.chapter = chapter
        self.passage = passage
    }

    public func makeExcerpt(at date: Date = Date()) -> Excerpt {
        Excerpt(bookId: bookId, bookTitle: bookTitle, chapterId: chapter.id, chapterTitle: chapter.title,
                passageId: passage.id, text: passage.text, createdAt: date)
    }
}

/// 版式度量: 一个字占的高、一列占的宽, 都从字号推出来 (与 Flutter 版 `ClassicMetrics` 同值, 两端版式一致)。
struct ClassicMetrics: Hashable {
    var fontSize: CGFloat
    var cellHeight: CGFloat { fontSize * 1.48 }
    var columnWidth: CGFloat { fontSize * 1.72 }

    /// 天头留给眉批 (以后做), 地脚留一点。
    static let top: CGFloat = 30
    static let bottom: CGFloat = 22
    static let right: CGFloat = 18
    /// 版心: 左侧一条, 书名、鱼尾、页码在里面。
    static let banxin: CGFloat = 34

    func charsPerColumn(in size: CGSize) -> Int {
        max(1, min(200, Int(((size.height - Self.top - Self.bottom) / cellHeight).rounded(.down))))
    }

    func columnsPerPage(in size: CGSize) -> Int {
        max(1, min(60, Int(((size.width - Self.banxin - Self.right) / columnWidth).rounded(.down))))
    }
}

/// 线装书阅读器。
///
/// 竖排为默认: 版框 (四周双边)、界栏、左侧版心 (书名 · 章名 · 鱼尾 · 汉字页码); 可切横排对照;
/// 顶栏点章名跳章, 底栏上一章 / 下一章; 长按一段回调 `onExcerpt`。
/// 竖排轻点页边翻页 (左边下一页、右边上一页), 章首 / 章尾再点跨章。
/// 白话按 `plainMode` 排: 夹注 (竖排双行小注) / 对照 / 不显示。
/// `passageBinding` 给一段 id: 翻到 (滚到) 该段并高亮一次, 然后写回 nil。
///
/// 阅读器不持有阅读状态: 位置、读完一章都通过回调交给 App, 由 App 写进 `ReadingStateStore`。
/// 这样同一个视图既能用在书斋, 也能用在「今日一句」的展开页, 而不会意外改动进度。
///
/// 说明: SwiftUI 的 View 在主线程上使用, 这里持有 UI 回调闭包, 所以不声明 `Sendable`;
/// 它交出去的数据 (`ReaderLocation` / `ReaderSelection` / `Chapter`) 都是 `Sendable` 值类型。
public struct ClassicReaderView: View {
    private let book: Book
    private let fontSize: CGFloat
    private let finishedChapterIds: Set<String>
    private let onLocationChange: ((ReaderLocation) -> Void)?
    private let onChapterFinished: ((Chapter) -> Void)?
    private let onExcerpt: ((ReaderSelection) -> Void)?
    /// App 持有的章与横竖排 (可选)。给了就读写它, 没给用下面的内部状态 —— 旧调用方行为不变。
    private let chapterBinding: Binding<String>?
    private let orientationBinding: Binding<ReaderOrientation>?
    /// false: 不画自带的顶栏 (章名 / 横竖切换) 与底栏 (上一章 / 页码 / 下一章), 由 App 自己的导航栏承担。
    private let showsChrome: Bool
    private let plainMode: ReaderPlainMode
    /// 外部定位: 设了就定位并高亮, 处理完写回 nil。
    private let passageBinding: Binding<String?>?

    @State private var ownChapterId: String
    @State private var ownOrientation: ReaderOrientation
    /// 当前位置落在哪一段: 竖排是本页第一段, 横排是视口第一段。切换横竖、旋转屏幕都按它复位。
    @State private var anchorPassageId: String?
    @State private var showsChapterList = false
    @State private var lastReported: ReaderLocation?
    @State private var finishedReported: Set<String> = []
    @State private var locateRequest: ReaderLocateRequest?
    /// 定位后的一次高亮: 哪一段、当前不透明度 (1 → 0 淡出)。
    @State private var flashPassageId: String?
    @State private var flashOpacity: Double = 0
    @State private var flashTask: Task<Void, Never>?

    /// 颜色与字来自 ZixiaoDesign 的主题。App 在根视图用 `.zxTheme(identity)` 注入, 随外观切换重新解析;
    /// 没注入时是单色墨系浅色 (ZXTheme 的环境默认值)。
    @Environment(\.zxTheme) private var theme
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 高亮停留多久后开始淡出 (等翻页 / 滚动落定), 与淡出的时长。
    static let flashHold: Duration = .milliseconds(350)
    static let flashFade: Double = 1.2

    /// - Parameters:
    ///   - chapterId: 打开哪一章; nil 为第一章。
    ///   - initialPassageId: 续读的段落 (来自 `BookProgress.passageId`)。
    ///   - finishedChapterIds: 章目里打勾用。
    ///   - onLocationChange: 翻页 / 滚动 / 换章后报告位置 (同一位置不重复报)。
    ///   - onChapterFinished: 翻到章末 (一页就完的章摊开即算)。
    ///   - onExcerpt: 长按一段。
    ///   - chapterBinding: App 持有当前章 (跳章、标题显示章名)。给了就忽略 `chapterId`;
    ///     阅读器内部换章 (底栏、章目) 也写回它。id 不在书里时按第一章显示。
    ///   - orientationBinding: App 持有横竖排。给了就忽略 `orientation`。
    ///   - showsChrome: 是否画自带的顶栏与底栏; false 时只剩书页与翻页。
    ///   - plainMode: 白话的排法 (夹注 / 对照 / 不显示)。段落没有白话时三者一样。
    ///   - passageBinding: 外部定位。设成一段的 id (可在别的章, 阅读器自己找到章并切过去, 写回
    ///     `chapterBinding`): 竖排翻到含该段的页、横排滚到该段, 用主题强调色的淡底高亮一次 (1.2 秒淡出,
    ///     减少动态时不做动画), 然后写回 nil —— 同一段再设一次会再定位一次。书里没有这段时只写回 nil。
    public init(
        book: Book,
        chapterId: String? = nil,
        initialPassageId: String? = nil,
        orientation: ReaderOrientation = .vertical,
        fontSize: CGFloat = 22,
        finishedChapterIds: Set<String> = [],
        onLocationChange: ((ReaderLocation) -> Void)? = nil,
        onChapterFinished: ((Chapter) -> Void)? = nil,
        onExcerpt: ((ReaderSelection) -> Void)? = nil,
        chapterBinding: Binding<String>? = nil,
        orientationBinding: Binding<ReaderOrientation>? = nil,
        showsChrome: Bool = true,
        plainMode: ReaderPlainMode = .interlinear,
        passageBinding: Binding<String?>? = nil
    ) {
        self.plainMode = plainMode
        self.passageBinding = passageBinding
        self.book = book
        self.fontSize = fontSize
        self.finishedChapterIds = finishedChapterIds
        self.onLocationChange = onLocationChange
        self.onChapterFinished = onChapterFinished
        self.onExcerpt = onExcerpt
        self.chapterBinding = chapterBinding
        self.orientationBinding = orientationBinding
        self.showsChrome = showsChrome
        let start = chapterId.flatMap { book.chapter(id: $0) } ?? book.chapters.first
        _ownChapterId = State(initialValue: start?.id ?? "")
        _ownOrientation = State(initialValue: orientation)
        _anchorPassageId = State(initialValue: initialPassageId)
    }

    private var style: ZXReaderStyle { ZXReaderStyle(theme: theme, legibilityWeight: legibilityWeight) }

    /// 当前章: 外部绑定优先, 否则内部状态。写入同理。
    private var chapterId: String {
        get { chapterBinding?.wrappedValue ?? ownChapterId }
        nonmutating set {
            if let chapterBinding { chapterBinding.wrappedValue = newValue } else { ownChapterId = newValue }
        }
    }

    private var orientation: ReaderOrientation {
        get { orientationBinding?.wrappedValue ?? ownOrientation }
        nonmutating set {
            if let orientationBinding { orientationBinding.wrappedValue = newValue } else { ownOrientation = newValue }
        }
    }

    private var chapterIndex: Int? { Self.chapterIndex(of: chapterId, in: book) }

    /// 章 id → 下标; 不在书里 (外部绑定给了错的 id) 时退回第一章, 书没有章时为 nil。
    static func chapterIndex(of id: String, in book: Book) -> Int? {
        book.chapters.firstIndex { $0.id == id } ?? (book.chapters.isEmpty ? nil : 0)
    }
    private var chapter: Chapter? { chapterIndex.map { book.chapters[$0] } }

    /// 段落定位 (纯函数): 含该段的章的下标。先看 `preferring` 那一章 (当前章), 再按书序找;
    /// 书里没有这段为 nil。
    static func chapterIndex(containing passageId: String, in book: Book, preferring chapterId: String?) -> Int? {
        if let chapterId, let index = book.chapters.firstIndex(where: { $0.id == chapterId }),
           book.chapters[index].passages.contains(where: { $0.id == passageId }) {
            return index
        }
        return book.chapters.firstIndex { $0.passages.contains { $0.id == passageId } }
    }

    /// 竖排轻点页边 (纯函数): 往下一页 (左边) 或上一页 (右边); 已在章尾 / 章首时跨章。
    static func pageTurn(from page: Int, pageCount: Int, towardNext: Bool) -> ReaderPageTurn {
        if towardNext {
            return page + 1 < pageCount ? .page(page + 1) : .nextChapter
        }
        return page > 0 ? .page(min(page - 1, max(pageCount - 1, 0))) : .previousChapter
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsChrome { topBar }
            if let chapter {
                frame {
                    switch orientation {
                    case .vertical:
                        VerticalChapterView(
                            book: book, chapter: chapter, fontSize: fontSize, style: style,
                            plainLayout: plainMode.classicLayout,
                            anchorPassageId: $anchorPassageId,
                            locateRequest: locateRequest,
                            flashPassageId: flashPassageId, flashOpacity: flashOpacity,
                            onPassage: { report(chapter: chapter, passageId: $0) },
                            onReachedEnd: { finished(chapter) },
                            onLongPress: { select(chapter: chapter, passageId: $0) },
                            onAdjacentChapter: { goAdjacent($0) }
                        )
                    case .horizontal:
                        HorizontalChapterView(
                            chapter: chapter, fontSize: fontSize, style: style, plainMode: plainMode,
                            anchorPassageId: $anchorPassageId,
                            locateRequest: locateRequest,
                            flashPassageId: flashPassageId, flashOpacity: flashOpacity,
                            onPassage: { report(chapter: chapter, passageId: $0) },
                            onReachedEnd: { finished(chapter) },
                            onLongPress: { select(chapter: chapter, passageId: $0) }
                        )
                    }
                }
                // 白话排法改了, 竖排要重新分页: 与章、横竖、字号一样重建, 按锚定的段落找回页码。
                .id("\(chapter.id)|\(orientation.rawValue)|\(fontSize)|\(plainMode.rawValue)")
                if showsChrome { bottomBar } else { Spacer().frame(height: 12) }
            } else {
                Spacer()
                Text("这本书没有正文。").font(style.serif(15)).foregroundStyle(style.ink(0.5))
                Spacer()
            }
        }
        .background(style.paper.ignoresSafeArea())
        .sheet(isPresented: $showsChapterList) { chapterList }
        .onChange(of: chapterId) { _, _ in
            // 外部绑定换了章 (App 的章目): 锚点若不在新章里就从章首读, 并报一次位置。
            // 内部 `go` 已先清了锚点、报过位置, 这里因去重不会重复回调。
            guard let chapter else { return }
            if let anchor = anchorPassageId, !chapter.passages.contains(where: { $0.id == anchor }) {
                anchorPassageId = nil
            }
            report(chapter: chapter, passageId: anchorPassageId ?? chapter.passages.first?.id)
        }
        .onChange(of: passageBinding?.wrappedValue ?? nil) { _, new in
            if let new { locate(new) }
        }
        .task {
            // 打开时就带着定位 (如摘抄本「回原文」): 与之后设定同样处理。
            if let initial = passageBinding?.wrappedValue { locate(initial) }
        }
        .onDisappear { flashTask?.cancel() }
    }

    // MARK: 版框与栏

    /// 四周双边: 外粗内细两道框, 线装书的版框。
    private func frame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .overlay(Rectangle().stroke(style.ink(0.35), lineWidth: 0.5))
            .padding(6)
            .background(style.paper)
            .overlay(Rectangle().stroke(style.ink(0.55), lineWidth: 1))
            .shadow(color: style.ink(0.06), radius: 10, y: 8)
            .padding(.horizontal, 12)
            .padding(.top, 8)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                showsChapterList = true
            } label: {
                HStack(spacing: 6) {
                    Text(chapter?.title ?? book.title)
                        .font(style.serif(16, weight: .bold, relativeTo: .headline))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }
                .foregroundStyle(style.ink)
            }
            .accessibilityHint("打开章目")
            Spacer(minLength: 8)
            Button {
                orientation = orientation == .vertical ? .horizontal : .vertical
            } label: {
                Image(systemName: orientation == .vertical ? "text.justify.left" : "text.alignright")
                    .foregroundStyle(style.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(orientation == .vertical ? "横排对照" : "竖排")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private var bottomBar: some View {
        let index = chapterIndex ?? 0
        let prev = index > 0 ? book.chapters[index - 1] : nil
        let next = index + 1 < book.chapters.count ? book.chapters[index + 1] : nil
        return HStack(spacing: 8) {
            // 章名可长可短, 两头各占一半, 装不下就省略 —— 不能撑破。
            navButton(prev.map { "‹ \($0.title)" }, alignment: .leading) { prev.map(go) }
            Text("\(index + 1) / \(book.chapters.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(style.ink(0.5))
            navButton(next.map { "\($0.title) ›" }, alignment: .trailing) { next.map(go) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func navButton(_ label: String?, alignment: Alignment, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label ?? "")
                .font(style.serif(14, weight: .bold))
                .foregroundStyle(style.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: alignment)
        }
        .disabled(label == nil)
    }

    private var chapterList: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(book.chapters) { ch in
                    Button {
                        go(ch)
                        showsChapterList = false
                    } label: {
                        HStack(spacing: 12) {
                            Text(HanNumeral.ordinal(ch.no > 0 ? ch.no : (book.chapters.firstIndex(of: ch) ?? 0) + 1))
                                .font(style.serif(12))
                                .foregroundStyle(style.ink(0.45))
                                .frame(minWidth: 64, alignment: .leading)
                            Text(ch.title)
                                .font(style.serif(16, weight: ch.id == chapterId ? .bold : .regular))
                                .foregroundStyle(style.ink)
                            Spacer()
                            if finishedChapterIds.contains(ch.id) {
                                Image(systemName: "checkmark").font(.caption).foregroundStyle(style.ink(0.45))
                                    .accessibilityLabel("已读")
                            }
                        }
                    }
                    .id(ch.id)
                    .listRowBackground(ch.id == chapterId ? style.ink(0.05) : style.paper)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(style.paper)
                .onAppear { proxy.scrollTo(chapterId, anchor: .center) }
            }
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showsChapterList = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: 事件

    private func go(_ chapter: Chapter) {
        guard chapter.id != chapterId else { return }
        chapterId = chapter.id
        anchorPassageId = nil
        report(chapter: chapter, passageId: chapter.passages.first?.id)
    }

    /// 上一章 (-1) / 下一章 (+1)。往回跨章时落在上一章末段所在的页, 接着往回读; 往前跨章从章首起。
    private func goAdjacent(_ step: Int) {
        guard let index = chapterIndex, book.chapters.indices.contains(index + step) else { return }
        let target = book.chapters[index + step]
        guard step < 0, let last = target.passages.last?.id else { return go(target) }
        anchorPassageId = last
        chapterId = target.id
        report(chapter: target, passageId: last)
    }

    /// 外部定位: 找章 → 必要时换章 → 请子视图翻到 / 滚到 → 高亮 → 写回 nil。
    private func locate(_ passageId: String) {
        defer {
            if passageBinding?.wrappedValue != nil { passageBinding?.wrappedValue = nil }
        }
        guard let index = Self.chapterIndex(containing: passageId, in: book, preferring: chapter?.id) else { return }
        let target = book.chapters[index]
        anchorPassageId = passageId
        if target.id != chapter?.id { chapterId = target.id }
        locateRequest = ReaderLocateRequest(passageId: passageId, token: (locateRequest?.token ?? 0) + 1)
        flash(passageId)
    }

    /// 高亮一次: 立即显出, 停一会儿 (翻页 / 滚动落定) 再 1.2 秒淡出; 减少动态时不淡出, 到时直接撤掉。
    private func flash(_ passageId: String) {
        flashTask?.cancel()
        flashPassageId = passageId
        flashOpacity = 1
        let reduceMotion = reduceMotion
        flashTask = Task { @MainActor in
            try? await Task.sleep(for: Self.flashHold)
            guard !Task.isCancelled else { return }
            if !reduceMotion {
                withAnimation(.easeOut(duration: Self.flashFade)) { flashOpacity = 0 }
            }
            try? await Task.sleep(for: .seconds(Self.flashFade))
            guard !Task.isCancelled else { return }
            flashOpacity = 0
            flashPassageId = nil
        }
    }

    private func report(chapter: Chapter, passageId: String?) {
        if let passageId { anchorPassageId = passageId }
        let location = ReaderLocation(bookId: book.id, chapterId: chapter.id, passageId: passageId)
        guard location != lastReported else { return }
        lastReported = location
        onLocationChange?(location)
    }

    private func finished(_ chapter: Chapter) {
        // 一章只报一次: 来回翻到末页不该重复记「读完」。
        guard finishedReported.insert(chapter.id).inserted else { return }
        onChapterFinished?(chapter)
    }

    private func select(chapter: Chapter, passageId: String) {
        guard let passage = chapter.passages.first(where: { $0.id == passageId }) else { return }
        onExcerpt?(ReaderSelection(bookId: book.id, bookTitle: book.title, chapter: chapter, passage: passage))
    }
}

// MARK: - 竖排

/// 一章分页, 右翻左。
private struct VerticalChapterView: View {
    let book: Book
    let chapter: Chapter
    let fontSize: CGFloat
    let style: ZXReaderStyle
    let plainLayout: ClassicPlainLayout
    @Binding var anchorPassageId: String?
    let locateRequest: ReaderLocateRequest?
    let flashPassageId: String?
    let flashOpacity: Double
    let onPassage: (String) -> Void
    let onReachedEnd: () -> Void
    let onLongPress: (String) -> Void
    let onAdjacentChapter: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pageIndex = 0
    @State private var pressedPassageId: String?
    /// 长按摘抄之后松手, 同一次触摸还会报一次轻点; 记下来吞掉, 免得摘抄面板底下翻了页。
    @State private var swallowNextTap = false

    var body: some View {
        GeometryReader { geo in
            let metrics = ClassicMetrics(fontSize: fontSize)
            let pages = ClassicLayout.paginate(
                passages: chapter.passages,
                charsPerColumn: metrics.charsPerColumn(in: geo.size),
                columnsPerPage: metrics.columnsPerPage(in: geo.size),
                plain: plainLayout
            )
            TabView(selection: $pageIndex) {
                ForEach(pages.indices, id: \.self) { i in
                    ClassicPageView(
                        page: pages[i], size: geo.size, metrics: metrics, style: style,
                        banxinTitle: "\(book.title) · \(chapter.title)", pageNumber: i + 1,
                        pressedPassageId: pressedPassageId,
                        flashPassageId: flashPassageId, flashOpacity: flashOpacity,
                        onPressing: { id, pressing in
                            pressedPassageId = pressing ? id : nil
                            if pressing { swallowNextTap = false }
                        },
                        onLongPress: { id in
                            swallowNextTap = true
                            onLongPress(id)
                        },
                        onEdgeTap: { towardNext in turn(towardNext: towardNext, pageCount: pages.count) }
                    )
                    // 页内的字与手势按从左到右的坐标画, 不受外层方向翻转影响。
                    .environment(\.layoutDirection, .leftToRight)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // 竖排书的下一页在左边: 把分页容器整体设成从右到左, 往右划就把下一页带进来。
            .environment(\.layoutDirection, .rightToLeft)
            .onChange(of: pageIndex) { _, new in
                guard pages.indices.contains(new) else { return }
                if let first = pages[new].firstPassageId { onPassage(first) }
                if new == pages.count - 1 { onReachedEnd() }
            }
            // 尺寸变了就重排, 并按锚定的段落找回页码 —— 旋转屏幕或切回竖排不丢位置。
            .task(id: geo.size) {
                let target = ClassicLayout.page(containing: anchorPassageId, in: pages)
                if target != pageIndex { pageIndex = target }
                if let first = pages[safe: target]?.firstPassageId { onPassage(first) }
                // 一页就完的章没有「翻到末页」这回事, 摊开即读完。
                if pages.count <= 1 || target == pages.count - 1 { onReachedEnd() }
            }
            // 同一章里的外部定位: 翻到含该段的第一页 (换章时整个视图重建, 由上面的 task 按锚点找页)。
            .onChange(of: locateRequest) { _, request in
                guard let request, pages.contains(where: { $0.contains(passageId: request.passageId) }) else { return }
                let target = ClassicLayout.page(containing: request.passageId, in: pages)
                if target != pageIndex { pageIndex = target }
            }
        }
    }

    private func turn(towardNext: Bool, pageCount: Int) {
        if swallowNextTap {
            swallowNextTap = false
            return
        }
        switch ClassicReaderView.pageTurn(from: pageIndex, pageCount: pageCount, towardNext: towardNext) {
        case let .page(target):
            if reduceMotion {
                pageIndex = target
            } else {
                withAnimation(.easeInOut(duration: 0.28)) { pageIndex = target }
            }
        case .previousChapter:
            onAdjacentChapter(-1)
        case .nextChapter:
            onAdjacentChapter(1)
        }
    }
}

/// 一页线装书: 界栏 + 竖排正文 (含夹注与白话列) + 左侧版心。正文与线用 Canvas 一次画完 (一页几百字,
/// 逐字建视图太重), 手势与无障碍用每列一个透明热区叠在上面。
private struct ClassicPageView: View {
    let page: ClassicPage
    let size: CGSize
    let metrics: ClassicMetrics
    let style: ZXReaderStyle
    let banxinTitle: String
    let pageNumber: Int
    let pressedPassageId: String?
    let flashPassageId: String?
    let flashOpacity: Double
    let onPressing: (String, Bool) -> Void
    let onLongPress: (String) -> Void
    /// 轻点页边: true 为左边 (下一页), false 为右边 (上一页)。
    let onEdgeTap: (Bool) -> Void

    /// 页边轻点区各占页宽的这么多。中间留给长按与将来的「轻点收放工具条」。
    static let edgeFraction: CGFloat = 0.28

    private var textRight: CGFloat { size.width - ClassicMetrics.right }
    /// 夹注与白话列的小字行高: 半格。
    private var smallRow: CGFloat { metrics.cellHeight / CGFloat(ClassicLayout.noteRowsPerCell) }
    private var fitting: Int { metrics.charsPerColumn(in: size) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, canvasSize in
                drawRules(context, canvasSize)
                drawHighlight(context)
                drawColumns(context, canvasSize)
                drawBanxin(context, canvasSize)
            }
            if let flashPassageId {
                flashLayer(flashPassageId)
            }
            ForEach(page.columns.indices, id: \.self) { i in
                hitTarget(for: page.columns[i], at: i)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        // 与列上的长按并存: 轻点不抢长按, 长按之后的松手由上层吞掉。
        .simultaneousGesture(SpatialTapGesture().onEnded { value in
            if value.location.x < size.width * Self.edgeFraction {
                onEdgeTap(true)
            } else if value.location.x > size.width * (1 - Self.edgeFraction) {
                onEdgeTap(false)
            }
        })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("第\(HanNumeral.string(pageNumber))页")
    }

    private func columnX(_ i: Int) -> CGFloat { textRight - CGFloat(i + 1) * metrics.columnWidth }

    /// 一列的占高 (原文、白话列、夹注取最低的那处): 满列时挤进来的标点只上提着占半格多,
    /// 不能让高亮与热区捅出版框。
    private func columnHeight(_ column: ClassicColumn) -> CGFloat {
        func extent(count: Int, capacity: Int, row: CGFloat, from start: Int = 0) -> CGFloat {
            CGFloat(start + min(count, capacity)) * row + (count > capacity ? row * 0.65 : 0)
        }
        var bottom: CGFloat
        switch column.role {
        case .text: bottom = extent(count: column.cells.count, capacity: fitting, row: metrics.cellHeight)
        case .plain: bottom = extent(count: column.cells.count, capacity: fitting * ClassicLayout.noteRowsPerCell, row: smallRow)
        }
        if let notes = column.notes {
            let capacity = fitting * ClassicLayout.noteRowsPerCell - notes.startRow
            bottom = max(bottom, extent(count: notes.rowCount, capacity: capacity, row: smallRow, from: notes.startRow))
        }
        return bottom + 8
    }

    private func columnRect(_ i: Int) -> CGRect {
        CGRect(x: columnX(i) + 2, y: ClassicMetrics.top - 4,
               width: metrics.columnWidth - 4, height: columnHeight(page.columns[i]))
    }

    private func hitTarget(for column: ClassicColumn, at i: Int) -> some View {
        let height = columnHeight(column)
        return Color.clear
            .contentShape(Rectangle())
            .frame(width: metrics.columnWidth, height: height)
            .offset(x: columnX(i), y: ClassicMetrics.top - 4)
            .onLongPressGesture(minimumDuration: 0.45) {
                onLongPress(column.passageId)
            } onPressingChanged: { pressing in
                onPressing(column.passageId, pressing)
            }
            .accessibilityElement()
            .accessibilityLabel(accessibilityText(column))
            .accessibilityAction(named: "摘抄") { onLongPress(column.passageId) }
    }

    /// 直排标点读屏念不出来, 读原字; 夹注与白话列说明是白话。
    private func accessibilityText(_ column: ClassicColumn) -> String {
        var parts: [String] = []
        if !column.cells.isEmpty {
            parts.append(column.role == .plain ? "白话：\(column.text)" : column.text)
        }
        if let notes = column.notes { parts.append("白话：\(notes.text)") }
        return parts.joined(separator: " ")
    }

    /// 外部定位后的一次高亮: 强调色淡底, 不透明度由上层动画 (淡出)。
    /// 只按段落 id 决定画不画 —— 若也按不透明度判断, 动画一开始视图就被拿掉, 看不到淡出。
    private func flashLayer(_ passageId: String) -> some View {
        ForEach(page.columnIndices(of: passageId), id: \.self) { i in
            let rect = columnRect(i)
            Rectangle()
                .fill(style.accent.opacity(0.2))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .opacity(flashOpacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 乌丝栏: 每列之间一道细线; 版心边一道通高的线。
    private func drawRules(_ context: GraphicsContext, _ size: CGSize) {
        let columns = Int(((textRight - ClassicMetrics.banxin) / metrics.columnWidth).rounded(.down))
        var rules = Path()
        for i in 0...max(columns, 0) {
            let x = textRight - CGFloat(i) * metrics.columnWidth
            rules.move(to: CGPoint(x: x, y: ClassicMetrics.top - 8))
            rules.addLine(to: CGPoint(x: x, y: size.height - ClassicMetrics.bottom + 8))
        }
        context.stroke(rules, with: .color(style.rule), lineWidth: 0.5)
        var edge = Path()
        edge.move(to: CGPoint(x: ClassicMetrics.banxin, y: 8))
        edge.addLine(to: CGPoint(x: ClassicMetrics.banxin, y: size.height - 8))
        context.stroke(edge, with: .color(style.ink(0.3)), lineWidth: 0.5)
    }

    private func drawHighlight(_ context: GraphicsContext) {
        guard let pressedPassageId else { return }
        for i in page.columnIndices(of: pressedPassageId) {
            context.fill(Path(columnRect(i)), with: .color(style.ink(0.06)))
        }
    }

    private func drawColumns(_ context: GraphicsContext, _ size: CGSize) {
        let font = style.fixedSerif(metrics.fontSize, weight: .medium)
        let small = style.fixedSerif(ZXReaderStyle.captionSize(for: metrics.fontSize))
        let smallCapacity = fitting * ClassicLayout.noteRowsPerCell
        // 同一页同一个字只解析一次; 「之」「而」「不」这类字一页能出现十几次。
        // 正文、夹注、白话列三种字各一张表 (字号或墨色不同)。
        var resolved: [String: GraphicsContext.ResolvedText] = [:]
        var resolvedNote: [String: GraphicsContext.ResolvedText] = [:]
        var resolvedPlain: [String: GraphicsContext.ResolvedText] = [:]

        func draw(_ glyph: String, font: Font, color: Color, cache: inout [String: GraphicsContext.ResolvedText],
                  at point: CGPoint) {
            let text = cache[glyph] ?? context.resolve(Text(glyph).font(font).foregroundStyle(color))
            cache[glyph] = text
            context.draw(text, at: point, anchor: .center)
        }

        for (i, column) in page.columns.enumerated() {
            let centerX = columnX(i) + metrics.columnWidth / 2
            switch column.role {
            case .text:
                for (j, cell) in column.cells.enumerated() {
                    // 标点挤在列尾时是第 N+1 个, 稍微上提贴着前一个字。
                    let lift: CGFloat = j >= fitting ? metrics.cellHeight * 0.35 : 0
                    let centerY = ClassicMetrics.top + (CGFloat(j) + 0.5) * metrics.cellHeight - lift
                    draw(cell.glyph, font: font, color: style.ink, cache: &resolved, at: CGPoint(x: centerX, y: centerY))
                }
            case .plain:
                // 白话列: 单行小字, 半格一字, 墨淡一档。
                for (j, cell) in column.cells.enumerated() {
                    let lift: CGFloat = j >= smallCapacity ? smallRow * 0.35 : 0
                    let centerY = ClassicMetrics.top + (CGFloat(j) + 0.5) * smallRow - lift
                    draw(cell.glyph, font: small, color: style.ink(0.62), cache: &resolvedPlain,
                         at: CGPoint(x: centerX, y: centerY))
                }
            }
            // 双行夹注: 一列并排两行小字, 右行先读。两行的中线各在半列的中间偏内一点, 不贴界栏。
            if let notes = column.notes {
                let capacity = smallCapacity - notes.startRow
                let offset = metrics.columnWidth * 0.24
                for (line, x) in [(notes.right, centerX + offset), (notes.left, centerX - offset)] {
                    for (r, cell) in line.enumerated() {
                        let lift: CGFloat = r >= capacity ? smallRow * 0.35 : 0
                        let centerY = ClassicMetrics.top + (CGFloat(notes.startRow + r) + 0.5) * smallRow - lift
                        draw(cell.glyph, font: small, color: style.ink(0.78), cache: &resolvedNote,
                             at: CGPoint(x: x, y: centerY))
                    }
                }
            }
        }
    }

    /// 版心: 书名 · 章名 (竖排小字) · 鱼尾 · 汉字页码。
    private func drawBanxin(_ context: GraphicsContext, _ size: CGSize) {
        let small = style.fixedSerif(11)
        let color = style.ink(0.55)
        let midX = ClassicMetrics.banxin / 2
        let step: CGFloat = 11 * 1.15
        var y: CGFloat = 12 + step / 2
        // 空格在竖排里只会留下空格子, 版心本来就窄, 去掉。
        for ch in banxinTitle.filter({ !$0.isWhitespace }).prefix(14) {
            let glyph = String(ZXVerticalForms.vertical(ch))
            context.draw(Text(glyph).font(small).foregroundStyle(color), at: CGPoint(x: midX, y: y))
            y += step
        }
        // 页码自下而上排, 算出起点后与书名一样逐字竖写。
        let number = HanNumeral.string(pageNumber)
        var numberY = size.height - 12 - step * CGFloat(number.count) + step / 2
        let fishTop = numberY - step / 2 - 10 - 9
        drawYuWei(context, in: CGRect(x: midX - 7, y: fishTop, width: 14, height: 9))
        for ch in number {
            context.draw(Text(String(ch)).font(small).foregroundStyle(color), at: CGPoint(x: midX, y: numberY))
            numberY += step
        }
    }

    /// 鱼尾: 版心中缝的那个燕尾形, 折页时对齐用的。画成黑鱼尾: 上平, 下缘向内开叉。
    private func drawYuWei(_ context: GraphicsContext, in rect: CGRect) {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.45))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        context.fill(path, with: .color(style.ink))
    }
}

// MARK: - 横排对照

/// 横排: 一段原文; 有白话时按 `plainMode`: 对照 (原文在左、白话在右)、夹注 (白话小字接在原文下)、不显示。
private struct HorizontalChapterView: View {
    let chapter: Chapter
    let fontSize: CGFloat
    let style: ZXReaderStyle
    let plainMode: ReaderPlainMode
    @Binding var anchorPassageId: String?
    let locateRequest: ReaderLocateRequest?
    let flashPassageId: String?
    let flashOpacity: Double
    let onPassage: (String) -> Void
    let onReachedEnd: () -> Void
    let onLongPress: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var visibleId: String?
    // 「读完一章」的三个条件, 只存布尔: 滚动时几何每帧都在变, 存布尔则只在跨过阈值时才触发重绘。
    @State private var sentinelVisible = false
    @State private var firstPassageGone = false
    @State private var contentFits = false

    private static let viewportSpace = "reader.viewport"
    private static let contentSpace = "reader.content"

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(chapter.passages) { passage in
                            row(passage)
                                .id(passage.id)
                                .background {
                                    if passage.id == chapter.passages.first?.id { firstPassageTracker }
                                }
                        }
                        sentinel(viewportHeight: viewport.size.height)
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                    .coordinateSpace(.named(Self.contentSpace))
                }
                .coordinateSpace(.named(Self.viewportSpace))
                .scrollPosition(id: $visibleId, anchor: .top)
                .onAppear {
                    if let anchorPassageId { proxy.scrollTo(anchorPassageId, anchor: .top) }
                }
                .onChange(of: visibleId) { _, new in
                    if let new { onPassage(new) }
                }
                // 同一章里的外部定位: 滚到该段 (换章时视图重建, 由上面的 onAppear 按锚点滚)。
                .onChange(of: locateRequest) { _, request in
                    guard let request else { return }
                    if reduceMotion {
                        proxy.scrollTo(request.passageId, anchor: .top)
                    } else {
                        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(request.passageId, anchor: .top) }
                    }
                }
            }
        }
        .onChange(of: sentinelVisible) { checkFinished() }
        .onChange(of: firstPassageGone) { checkFinished() }
        .onChange(of: contentFits) { checkFinished() }
    }

    /// 读完 = 章末哨兵真的进了视口, 并且「首段已经离开屏幕」(确实往下读过) 或「整章本来就不满一屏」。
    ///
    /// 不能只看末段 `onAppear`: LazyVStack 会预先加载视口外的几行, 短章一打开末段就「出现」了,
    /// 用户一眼没看也会被记成读完 (Flutter 版没有这个问题, 它看的是滚动到底)。
    private func checkFinished() {
        if sentinelVisible && (firstPassageGone || contentFits) { onReachedEnd() }
    }

    /// 首段的底边是否已经滚出视口上沿。首段被 LazyVStack 回收也算离开 ——
    /// 续读时直接定位到中段, 首段根本没加载, 同样说明它不在屏幕上。
    private var firstPassageTracker: some View {
        FrameReporter(space: Self.viewportSpace) { frame in
            firstPassageGone = frame.maxY <= 0
        }
        .onDisappear { firstPassageGone = true }
    }

    /// 末段之后的一条零高哨兵。
    private func sentinel(viewportHeight: CGFloat) -> some View {
        Color.clear
            .frame(height: 1)
            .background {
                FrameReporter(space: Self.viewportSpace) { frame in
                    sentinelVisible = frame.minY <= viewportHeight && frame.maxY >= 0
                }
                FrameReporter(space: Self.contentSpace) { frame in
                    // 内容坐标空间含上内边距, 哨兵底边再加下内边距就是整章内容的高度。
                    contentFits = frame.maxY + 18 <= viewportHeight
                }
            }
            .onDisappear { sentinelVisible = false }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func row(_ p: Passage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = p.title {
                Text(joinedAuthorLine(title, p.author))
                    .font(style.serif(12, relativeTo: .caption))
                    .foregroundStyle(style.ink(0.5))
            }
            if p.hasPlain, let plain = p.plain, plainMode != .hidden {
                if plainMode == .parallel {
                    HStack(alignment: .top, spacing: 12) {
                        original(p).frame(maxWidth: .infinity, alignment: .leading)
                        Rectangle().fill(style.rule).frame(width: 0.5)
                        plainText(plain).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    // 横排的「夹注」: 白话小字紧接原文之下, 与竖排双行小注同一个意思 —— 注随文走。
                    VStack(alignment: .leading, spacing: 6) {
                        original(p)
                        plainText(plain)
                    }
                }
            } else {
                original(p)
            }
        }
        .padding(.vertical, 4)
        .background {
            // 外部定位的一次高亮。只按段落 id 决定画不画, 不透明度由上层动画淡出。
            if p.id == flashPassageId {
                Rectangle()
                    .fill(style.accent.opacity(0.2))
                    .padding(.horizontal, -8)
                    .opacity(flashOpacity)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.45) { onLongPress(p.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "摘抄") { onLongPress(p.id) }
    }

    private func plainText(_ plain: String) -> some View {
        Text(plain)
            .font(style.serif(ZXReaderStyle.plainSize(for: fontSize), relativeTo: .callout))
            .foregroundStyle(style.ink(0.62))
            .lineSpacing(ZXReaderStyle.plainSize(for: fontSize) * 0.6)
            .accessibilityLabel("白话: \(plain)")
    }

    private func original(_ p: Passage) -> some View {
        Text(p.text)
            .font(style.serif(fontSize * 0.86, weight: .medium))
            .foregroundStyle(style.ink)
            .lineSpacing(fontSize * 0.86 * 0.8)
            // 不开 textSelection: 它在 iOS 上同样靠长按唤起, 会吞掉「长按摘抄」。复制走摘抄面板。
    }
}

/// 把自身在某坐标空间里的 frame 报出去。放在 background 里用, 不影响布局。
private struct FrameReporter: View {
    let space: String
    let report: (CGRect) -> Void

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .named(space))
            Color.clear
                .onAppear { report(frame) }
                .onChange(of: frame) { _, new in report(new) }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Preview

#if DEBUG
enum PreviewBooks {
    /// 预览读测试目录里的真实样书; 读不到 (比如文件被挪走) 就用内置小样, 预览总能出来。
    static let lunyu: Book = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/ZixiaoLibraryTests/Resources/lunyu.json")
        if let data = try? Data(contentsOf: url), let book = try? JSONDecoder().decode(Book.self, from: data) {
            return book
        }
        return sample
    }()

    /// 带白话的小样, 看横排对照用。白话是占位意译, 不是审定稿。
    static let sample = Book(
        id: "sample", title: "论语", category: "经",
        chapters: [
            Chapter(id: "01", no: 1, title: "学而第一", passages: [
                Passage(id: "01.01", text: "子曰：“学而时习之，不亦说乎？有朋自远方来，不亦乐乎？人不知而不愠，不亦君子乎？”",
                        plain: "孔子说：学了又按时温习，不也很愉快吗？有朋友从远方来，不也很快乐吗？别人不了解我，我却不恼怒，不也是君子吗？"),
                Passage(id: "01.02", text: "曾子曰：“吾日三省吾身：为人谋而不忠乎？与朋友交而不信乎？传不习乎？”"),
            ]),
            Chapter(id: "02", no: 2, title: "为政第二", passages: [
                Passage(id: "02.01", text: "子曰：“为政以德，譬如北辰，居其所而众星共之。”"),
            ]),
        ]
    )
}

/// 预览外壳: 用 ZixiaoDesign 的随包身份注入主题 (与 ZixiaoDesign 的 `PreviewPage` 同一思路 ——
/// 那个是模块内部类型, 跨模块用不到, 这里按阅读器整屏的需要另写一个)。
private struct ReaderPreview: View {
    let identity: ZXBundledIdentity
    var scheme: ColorScheme = .light
    let content: ClassicReaderView

    var body: some View {
        if let loaded = try? ZXIdentity.bundled(identity) {
            content
                .zxTheme(ZXTheme(loaded, colorScheme: scheme))
                .environment(\.colorScheme, scheme)
        } else {
            Text("身份 \(identity.rawValue) 加载失败")
        }
    }
}

#Preview("竖排 · monochrome-ink") {
    ReaderPreview(identity: .monochromeInk, content: ClassicReaderView(
        book: PreviewBooks.lunyu, chapterId: "17",
        onLocationChange: { print("位置", $0) },
        onChapterFinished: { print("读完", $0.title) },
        onExcerpt: { print("摘抄", $0.passage.id) }
    ))
}

#Preview("竖排 · paper-ink-seal") {
    ReaderPreview(identity: .paperInkSeal, content: ClassicReaderView(book: PreviewBooks.lunyu, chapterId: "17"))
}

#Preview("竖排 · monochrome-ink 深色") {
    ReaderPreview(identity: .monochromeInk, scheme: .dark, content: ClassicReaderView(book: PreviewBooks.lunyu))
}

#Preview("竖排夹注 · paper-ink-seal") {
    ReaderPreview(identity: .paperInkSeal, content: ClassicReaderView(book: PreviewBooks.sample, plainMode: .interlinear))
}

#Preview("竖排白话列 · paper-ink-seal 深色") {
    ReaderPreview(identity: .paperInkSeal, scheme: .dark,
                  content: ClassicReaderView(book: PreviewBooks.sample, plainMode: .parallel))
}

#Preview("横排对照 · paper-ink-seal") {
    ReaderPreview(identity: .paperInkSeal, content: ClassicReaderView(book: PreviewBooks.sample, orientation: .horizontal, plainMode: .parallel))
}

#Preview("横排对照 · paper-ink-seal 深色") {
    ReaderPreview(identity: .paperInkSeal, scheme: .dark,
                  content: ClassicReaderView(book: PreviewBooks.sample, orientation: .horizontal))
}
#endif
