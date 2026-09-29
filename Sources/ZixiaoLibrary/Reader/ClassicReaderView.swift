import SwiftUI
import ZixiaoDesign

/// 竖排 / 横排。
public enum ReaderOrientation: String, Sendable, Codable, CaseIterable {
    /// 线装书: 字从上到下, 列从右到左, 往右划翻下一页。
    case vertical
    /// 横排对照: 原文与白话左右并列。
    case horizontal
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

    @State private var chapterId: String
    @State private var orientation: ReaderOrientation
    /// 当前位置落在哪一段: 竖排是本页第一段, 横排是视口第一段。切换横竖、旋转屏幕都按它复位。
    @State private var anchorPassageId: String?
    @State private var showsChapterList = false
    @State private var lastReported: ReaderLocation?
    @State private var finishedReported: Set<String> = []

    /// 颜色与字来自 ZixiaoDesign 的主题。App 在根视图用 `.zxTheme(identity)` 注入, 随外观切换重新解析;
    /// 没注入时是单色墨系浅色 (ZXTheme 的环境默认值)。
    @Environment(\.zxTheme) private var theme
    @Environment(\.legibilityWeight) private var legibilityWeight

    /// - Parameters:
    ///   - chapterId: 打开哪一章; nil 为第一章。
    ///   - initialPassageId: 续读的段落 (来自 `BookProgress.passageId`)。
    ///   - finishedChapterIds: 章目里打勾用。
    ///   - onLocationChange: 翻页 / 滚动 / 换章后报告位置 (同一位置不重复报)。
    ///   - onChapterFinished: 翻到章末 (一页就完的章摊开即算)。
    ///   - onExcerpt: 长按一段。
    public init(
        book: Book,
        chapterId: String? = nil,
        initialPassageId: String? = nil,
        orientation: ReaderOrientation = .vertical,
        fontSize: CGFloat = 22,
        finishedChapterIds: Set<String> = [],
        onLocationChange: ((ReaderLocation) -> Void)? = nil,
        onChapterFinished: ((Chapter) -> Void)? = nil,
        onExcerpt: ((ReaderSelection) -> Void)? = nil
    ) {
        self.book = book
        self.fontSize = fontSize
        self.finishedChapterIds = finishedChapterIds
        self.onLocationChange = onLocationChange
        self.onChapterFinished = onChapterFinished
        self.onExcerpt = onExcerpt
        let start = chapterId.flatMap { book.chapter(id: $0) } ?? book.chapters.first
        _chapterId = State(initialValue: start?.id ?? "")
        _orientation = State(initialValue: orientation)
        _anchorPassageId = State(initialValue: initialPassageId)
    }

    private var style: ZXReaderStyle { ZXReaderStyle(theme: theme, legibilityWeight: legibilityWeight) }

    private var chapterIndex: Int? { book.chapters.firstIndex { $0.id == chapterId } }
    private var chapter: Chapter? { chapterIndex.map { book.chapters[$0] } }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            if let chapter {
                frame {
                    switch orientation {
                    case .vertical:
                        VerticalChapterView(
                            book: book, chapter: chapter, fontSize: fontSize, style: style,
                            anchorPassageId: $anchorPassageId,
                            onPassage: { report(chapter: chapter, passageId: $0) },
                            onReachedEnd: { finished(chapter) },
                            onLongPress: { select(chapter: chapter, passageId: $0) }
                        )
                    case .horizontal:
                        HorizontalChapterView(
                            chapter: chapter, fontSize: fontSize, style: style,
                            anchorPassageId: $anchorPassageId,
                            onPassage: { report(chapter: chapter, passageId: $0) },
                            onReachedEnd: { finished(chapter) },
                            onLongPress: { select(chapter: chapter, passageId: $0) }
                        )
                    }
                }
                .id("\(chapter.id)|\(orientation.rawValue)|\(fontSize)")
                bottomBar
            } else {
                Spacer()
                Text("这本书没有正文。").font(style.serif(15)).foregroundStyle(style.ink(0.5))
                Spacer()
            }
        }
        .background(style.paper.ignoresSafeArea())
        .sheet(isPresented: $showsChapterList) { chapterList }
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
    @Binding var anchorPassageId: String?
    let onPassage: (String) -> Void
    let onReachedEnd: () -> Void
    let onLongPress: (String) -> Void

    @State private var pageIndex = 0
    @State private var pressedPassageId: String?

    var body: some View {
        GeometryReader { geo in
            let metrics = ClassicMetrics(fontSize: fontSize)
            let pages = ClassicLayout.paginate(
                passages: chapter.passages,
                charsPerColumn: metrics.charsPerColumn(in: geo.size),
                columnsPerPage: metrics.columnsPerPage(in: geo.size)
            )
            TabView(selection: $pageIndex) {
                ForEach(pages.indices, id: \.self) { i in
                    ClassicPageView(
                        page: pages[i], size: geo.size, metrics: metrics, style: style,
                        banxinTitle: "\(book.title) · \(chapter.title)", pageNumber: i + 1,
                        pressedPassageId: pressedPassageId,
                        onPressing: { id, pressing in pressedPassageId = pressing ? id : nil },
                        onLongPress: onLongPress
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
        }
    }
}

/// 一页线装书: 界栏 + 竖排正文 + 左侧版心。正文与线用 Canvas 一次画完 (一页几百字, 逐字建视图太重),
/// 手势与无障碍用每列一个透明热区叠在上面。
private struct ClassicPageView: View {
    let page: ClassicPage
    let size: CGSize
    let metrics: ClassicMetrics
    let style: ZXReaderStyle
    let banxinTitle: String
    let pageNumber: Int
    let pressedPassageId: String?
    let onPressing: (String, Bool) -> Void
    let onLongPress: (String) -> Void

    private var textRight: CGFloat { size.width - ClassicMetrics.right }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, canvasSize in
                drawRules(context, canvasSize)
                drawHighlight(context)
                drawColumns(context, canvasSize)
                drawBanxin(context, canvasSize)
            }
            ForEach(page.columns.indices, id: \.self) { i in
                hitTarget(for: page.columns[i], at: i)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("第\(HanNumeral.string(pageNumber))页")
    }

    private func columnX(_ i: Int) -> CGFloat { textRight - CGFloat(i + 1) * metrics.columnWidth }

    /// 一列的占高: 满列时挤进来的标点只上提着占半格多, 不能让高亮与热区捅出版框。
    private func columnHeight(_ column: ClassicColumn) -> CGFloat {
        let fitting = metrics.charsPerColumn(in: size)
        let body = CGFloat(min(column.cells.count, fitting)) * metrics.cellHeight
        return body + 8 + (column.cells.count > fitting ? metrics.cellHeight * 0.65 : 0)
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
            .accessibilityLabel(column.text)
            .accessibilityAction(named: "摘抄") { onLongPress(column.passageId) }
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
        for (i, column) in page.columns.enumerated() where column.passageId == pressedPassageId {
            let rect = CGRect(x: columnX(i) + 2, y: ClassicMetrics.top - 4,
                              width: metrics.columnWidth - 4, height: columnHeight(column))
            context.fill(Path(rect), with: .color(style.ink(0.06)))
        }
    }

    private func drawColumns(_ context: GraphicsContext, _ size: CGSize) {
        let font = style.fixedSerif(metrics.fontSize, weight: .medium)
        let fitting = metrics.charsPerColumn(in: size)
        // 同一页同一个字只解析一次; 「之」「而」「不」这类字一页能出现十几次。
        var resolved: [String: GraphicsContext.ResolvedText] = [:]
        for (i, column) in page.columns.enumerated() {
            let centerX = columnX(i) + metrics.columnWidth / 2
            for (j, cell) in column.cells.enumerated() {
                let text = resolved[cell.glyph] ?? context.resolve(
                    Text(cell.glyph).font(font).foregroundStyle(style.ink)
                )
                resolved[cell.glyph] = text
                // 标点挤在列尾时是第 N+1 个, 稍微上提贴着前一个字。
                let lift: CGFloat = j >= fitting ? metrics.cellHeight * 0.35 : 0
                let centerY = ClassicMetrics.top + (CGFloat(j) + 0.5) * metrics.cellHeight - lift
                context.draw(text, at: CGPoint(x: centerX, y: centerY), anchor: .center)
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

/// 横排: 一段原文; 有白话时原文在左、白话在右, 左右对照。
///
/// TODO(夹注): 竖排模式下白话以双行小字夹注排在原文之后, 待版式定稿后在 `ClassicLayout` 里加「夹注列」。
private struct HorizontalChapterView: View {
    let chapter: Chapter
    let fontSize: CGFloat
    let style: ZXReaderStyle
    @Binding var anchorPassageId: String?
    let onPassage: (String) -> Void
    let onReachedEnd: () -> Void
    let onLongPress: (String) -> Void

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
            if p.hasPlain, let plain = p.plain {
                HStack(alignment: .top, spacing: 12) {
                    original(p).frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(style.rule).frame(width: 0.5)
                    Text(plain)
                        .font(style.serif(fontSize * 0.68, relativeTo: .callout))
                        .foregroundStyle(style.ink(0.62))
                        .lineSpacing(fontSize * 0.68 * 0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("白话: \(plain)")
                }
            } else {
                original(p)
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.45) { onLongPress(p.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "摘抄") { onLongPress(p.id) }
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

#Preview("横排对照 · paper-ink-seal") {
    ReaderPreview(identity: .paperInkSeal, content: ClassicReaderView(book: PreviewBooks.sample, orientation: .horizontal))
}

#Preview("横排对照 · paper-ink-seal 深色") {
    ReaderPreview(identity: .paperInkSeal, scheme: .dark,
                  content: ClassicReaderView(book: PreviewBooks.sample, orientation: .horizontal))
}
#endif
