import ZixiaoPoetCore
import SwiftUI
import ZixiaoDesign

/// 星图。只渲染 status=visible —— 共现抽出的 397 位 candidate 未经复核，
/// 混着篇名碎片与同人异称，进图就是把噪声当数据卖。
struct NetworkView: View {
    let ctx: CompositionContext
    // 缩放与平移。committed* 存手势结束时的值，手势进行中在它基础上叠加，
    // 否则每次 onChanged 都从 1 重算，双指缩放会一放手就跳回去。
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero
    @State private var selected: Associate?
    @State private var showingList = false
    @State private var activeGroup = "featured"
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zxTheme) private var theme

    private var placement: Placement? { ctx.composition.placement(.network) }
    private var groups: [AssociateGroup] { placement?.groups ?? [] }
    private var people: [Associate] { ctx.visibleAssociates }
    private var automaticList: Bool { typeSize.isAccessibilitySize || voiceOver || reduceMotion }
    private var graphPeople: [Associate] {
        if activeGroup == "featured" { return Array(people.prefix(12)) }
        if activeGroup == "all" { return people }
        return people.filter { $0.groupKey == activeGroup }
    }
    private static let centerID = "__self__"
    private static func radius(_ weight: Int) -> CGFloat {
        13 + sqrt(Double(weight)) * 0.9
    }

    var body: some View {
        Group {
            if people.isEmpty {
                LifeUI.Empty(title: "暂无交游记录", systemImage: "person.2")
            } else if showingList || automaticList {
                peopleList
            } else {
                graph
                    .safeAreaInset(edge: .top, spacing: theme.space.sm) { legend }
                    .safeAreaInset(edge: .bottom, spacing: theme.space.sm) {
                        Text("显示 \(graphPeople.count) 人 · 轻点看往来 · 双指缩放")
                            .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                            .padding(.vertical, theme.space.md)
                    }
            }
        }
        .background(theme.paper())
        .toolbar {
            if !automaticList {
            ToolbarItem(placement: .topBarTrailing) {
                Button(showingList ? "查看交游图" : "查看人物列表",
                       systemImage: showingList ? "point.3.connected.trianglepath.dotted" : "list.bullet") {
                    showingList.toggle()
                }
            }
            if !showingList {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("复位交游图", systemImage: "arrow.counterclockwise") {
                        withAnimation(theme.motion.adapted(theme.motion.smooth, reduceMotion: reduceMotion)) {
                            zoom = 1; committedZoom = 1
                            pan = .zero; committedPan = .zero
                        }
                    }
                }
            }
            }
        }
        .sheet(item: $selected) { associate in
            NavigationStack {
                AssociateDetailView(ctx: ctx, associate: associate)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { selected = nil }
                        }
                    }
            }
            .tint(theme.accent).presentationDragIndicator(.visible)
        }
    }

    private var peopleList: some View {
        List(people) { person in
            NavigationLink { AssociateDetailView(ctx: ctx, associate: person) } label: {
                HStack(spacing: theme.space.md) {
                    Circle().fill(color(person.groupKey)).frame(width: theme.space.sm, height: theme.space.sm)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: theme.space.xs) {
                        Text(person.name).font(theme.type.headline)
                        Text("\(label(person.groupKey)) · 年谱提及 \(person.weight) 次")
                            .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                    }
                }.padding(.vertical, theme.space.xs)
            }.listRowBackground(theme.paper()).listRowSeparatorTint(theme.rule)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).poetReadableWidth()
        .foregroundStyle(theme.color.textPrimary)
    }

    private var graph: some View {
        GeometryReader { geo in
            let layout = StarLayout(graphPeople)
            // 节点位置在最终显示坐标中缩放，按钮本身不跟着缩小。这样 24pt 的
            // 视觉胶囊可以保持轻巧，而实际命中区始终至少 44pt。
            let minimumHitScale = layout.minimumHitScale()
            let baseScale = max(minimumHitScale, layout.fitScale(in: geo.size))
            let scale = max(minimumHitScale, baseScale * zoom)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            // Canvas 闭包里不碰 @MainActor 的 theme，颜色先在外面解析好
            let linkColor = theme.rule
            let nameFont = theme.bodyFont(Self.nodeFontSize, relativeTo: nil)
            let centerFont = theme.displayFont(Self.centerFontSize, relativeTo: nil)

            ZStack {
                // 连线：所有人都连向中心。他们彼此之间的关系年谱里说不清，
                // 硬连就是编造 —— 只画确知的那一层。
                Canvas { gc, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    var path = Path()
                    for node in layout.nodes {
                        path.move(to: c)
                        path.addLine(to: CGPoint(x: c.x + node.offset.width * scale,
                                                 y: c.y + node.offset.height * scale))
                    }
                    gc.stroke(path, with: .color(linkColor),
                              style: StrokeStyle(lineWidth: Self.linkWidth, lineCap: .round))
                }
                .allowsHitTesting(false)

                ForEach(layout.nodes) { node in
                    let a = node.associate
                    Button {
                        withAnimation(theme.motion.adapted(theme.motion.snappy, reduceMotion: reduceMotion)) {
                            selected = a
                        }
                    } label: {
                        // A04: 视觉胶囊只有 24pt 高, 命中区单独撑到 ≥ 44 × 44 (宽取胶囊宽与 44 的大者)。
                        // 按钮不随图缩放 (缩放只作用在位置上), 且 `minimumHitScale` 保证任意两个 44pt
                        // 命中矩形在最终显示坐标里互不覆盖 —— 见 `StarLayout` 与 `StarLayoutTests`。
                        Bubble(text: a.name, tint: color(a.groupKey), labelColor: color(a.groupKey),
                               width: StarLayout.labelWidth(a), height: Self.nodeHeight,
                               font: nameFont, filled: false)
                            .frame(minWidth: max(LifeUI.minTapTarget, StarLayout.labelWidth(a)),
                                   minHeight: LifeUI.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // 节点是真正的视图，点击就是普通按钮 —— 不需要命中测试数学，
                    // 无障碍也就自然有了（上一版整块 accessibilityHidden 是个黑洞）。
                    .accessibilityLabel("\(a.name)，\(label(a.groupKey))，年谱提及 \(a.weight) 次")
                    .position(x: center.x + node.offset.width * scale,
                              y: center.y + node.offset.height * scale)
                }

                // 中心是印: 朱底纸字。纸压在印色上与印色压在纸上是同一对对比度, 两种外观都成立。
                Bubble(text: ctx.composition.poet.name, tint: theme.seal, labelColor: theme.paper(),
                       width: Self.centerWidth, height: Self.centerHeight, font: centerFont, filled: true)
                    .position(center)
                    .accessibilityHidden(true)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(pan)
            .contentShape(Rectangle())
            .gesture(
                SimultaneousGesture(
                    DragGesture()
                        .onChanged { v in
                            pan = CGSize(width: committedPan.width + v.translation.width,
                                         height: committedPan.height + v.translation.height)
                        }
                        .onEnded { _ in committedPan = pan },
                    MagnifyGesture()
                        .onChanged { v in
                            zoom = min(3, max(0.5, committedZoom * v.magnification))
                        }
                        .onEnded { _ in committedZoom = zoom }
                )
            )
        }
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            PoetGlassGroup {
                HStack(spacing: theme.space.md) {
                    groupButton("常见", id: "featured")
                    ForEach(groups) { group in groupButton(group.label, id: group.id) }
                    groupButton("全部", id: "all")
                }.padding(.horizontal, theme.space.margin).padding(.vertical, theme.space.xs)
            }
        }
    }

    private func groupButton(_ title: String, id: String) -> some View {
        Button {
            guard activeGroup != id else { return }
            // 布局是纯函数，换组自己就重算了；缩放平移复位，免得停在上一组的视角里。
            zoom = 1; committedZoom = 1; pan = .zero; committedPan = .zero
            activeGroup = id
        } label: {
            Text(title)
                .font(theme.type.footnote.weight(.medium))
                .padding(.horizontal, theme.space.xs)
                .frame(minWidth: LifeUI.minTapTarget, minHeight: LifeUI.minTapTarget)
                .contentShape(Rectangle())
        }
        .poetActionStyle(prominent: activeGroup == id)
        .accessibilityLabel("交游分组：\(title)")
        .accessibilityAddTraits(activeGroup == id ? [.isSelected] : [])
    }

    /// 分组色。编成里每组带的 `color` 是浅色下的一支十六进制 (深色一律回落成同一支青灰),
    /// 进不了 token 体系; 这里按分组在编成里的**顺序**轮取身份的角色色, 浅深两种外观由主题各自解析。
    /// 顺序对着首个编成 (五组交游) 的原意排: 亲族 = 印、师友 = 次色、门生 = 灰、方外 = 绿、政敌 = 墨。
    /// 单色身份里次色 / 绿会回落成墨 —— 单色系的分组本来就靠标签与列表区分, 不靠颜色。
    private func color(_ key: String?) -> Color {
        guard let index = groups.firstIndex(where: { $0.id == key }) else {
            return theme.color.textSecondary
        }
        let roles: [Color] = [theme.seal, theme.color.secondary, theme.muted, theme.color.success, theme.ink(0.72)]
        return roles[index % roles.count]
    }
    private func label(_ key: String?) -> String {
        groups.first { $0.id == key }?.label ?? "其他"
    }
}

private extension NetworkView {
    // 星图节点是「物」(尺寸由 `StarLayout` 的容量与碰撞计算约束), 不是版面文字:
    // 字号定长 (`relativeTo: nil`), 不随动态字体放大 —— 放大了胶囊就装不下, 布局也就不成立。
    // 大字号用户走人物列表 (`automaticList`), 那里是正常的动态字体。
    static let nodeHeight: CGFloat = 24
    static let nodeFontSize: CGFloat = 11
    static let centerWidth: CGFloat = 54
    static let centerHeight: CGFloat = 32
    static let centerFontSize: CGFloat = 14
    static let linkWidth: CGFloat = 0.8
}

/// 星图上的一个人。中心用实底，其余用淡底描边 —— 层级一眼可分。
private struct Bubble: View {
    let text: String
    let tint: Color
    let labelColor: Color
    let width: CGFloat
    let height: CGFloat
    let font: Font
    let filled: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(tint.opacity(filled ? 1 : 0.14))
                .overlay(Capsule().stroke(tint.opacity(filled ? 0 : 0.5), lineWidth: NetworkView.linkWidth))
                .frame(width: width, height: height)
            Text(text)
                .font(font)
                .foregroundStyle(labelColor)
                .lineLimit(1).fixedSize()
        }
    }
}

// MARK: - 星图布局

/// 交游图的解析布局：同心环。
///
/// 【为什么不用力导向模拟】星形拓扑里每个人只连中心、彼此不连 —— 力模拟在这种
/// 拓扑下做的事，本质就是「把点摊到几个圈上」。既然结果注定是同心环，不如直接算：
/// 不抖动、不需要迭代到稳定、同一份数据每次跑出同一张图，而且「距离即亲疏」
/// 从近似变成精确。原先用的 Grape 已停更（2025-05 至今无提交）且在 Xcode 27
/// 编不过，去掉它同时也去掉了一个会反复咬人的依赖。
struct StarLayout {
    struct Node: Identifiable {
        let associate: Associate
        /// 相对圆心的偏移，未缩放
        let offset: CGSize
        var id: String { associate.id }
    }

    let nodes: [Node]
    /// 整图外接半径（含标签半宽），用来算自适应缩放
    let boundingRadius: CGFloat

    /// 第一环半径。要大于中心胶囊的一半 + 呼吸量，否则连线看不出长度差。
    private static let innerRadius: CGFloat = 132
    /// 环距。视觉胶囊高 24，但布局按 44pt 命中区留出行间空气。
    private static let ringGap: CGFloat = 78
    /// 同环内两个标签之间的最小空隙
    private static let labelGap: CGFloat = 26

    /// 标签宽度估算 —— 与 Bubble 的实际宽度公式保持一致，否则容量算不准。
    static func labelWidth(_ a: Associate) -> CGFloat {
        max(44, CGFloat(a.name.count) * 12 + 14)
    }

    /// 标签高度（含上下呼吸量）。判重叠用的是矩形，不是圆 ——
    /// 标签是水平胶囊，在 3 点/9 点方向，水平半宽吃掉的正是径向空间。
    private static let labelHeight: CGFloat = 44

    private static func overlaps(_ a: (CGSize, CGFloat), _ b: (CGSize, CGFloat)) -> Bool {
        abs(a.0.width - b.0.width) < (a.1 + b.1) / 2 + labelGap / 2
            && abs(a.0.height - b.0.height) < labelHeight + labelGap / 2
    }

    init(_ people: [Associate]) {
        // 确定性：weight 降序，同分用 id 兜底。没有这一步，同样的数据可能排出两种图。
        let sorted = people.sorted {
            $0.weight != $1.weight ? $0.weight > $1.weight : $0.id < $1.id
        }

        // ① 先分环。容量用「标称半径」估 —— 实际半径只会更大（见 ②），
        //    环只会更宽松，所以这个估算不会导致同环挤压。
        var rings: [[Associate]] = []
        var remaining = ArraySlice(sorted)
        var nominal = Self.innerRadius
        while !remaining.isEmpty {
            let circumference = 2 * .pi * nominal
            var used: CGFloat = 0
            var count = 0
            for a in remaining {
                let need = Self.labelWidth(a) + Self.labelGap
                if count > 0 && used + need > circumference { break }
                used += need
                count += 1
            }
            count = max(1, count)
            rings.append(Array(remaining.prefix(count)))
            remaining = remaining.dropFirst(count)
            nominal += Self.ringGap
        }

        // ② 再逐环求【实际】半径：从上一环 + 最小环距起步，只要与已放好的任何
        //    标签矩形相交就往外推。固定 ringGap 在 3 点钟方向会被水平半宽吃掉 ——
        //    长名字时内外环真的会压上（实测最坏 -15.4pt），所以半径必须由标签算出来。
        var placed: [Node] = []
        var maxExtent: CGFloat = 0
        var radius = Self.innerRadius

        for (k, ring) in rings.enumerated() {
            if k > 0 { radius += Self.ringGap }
            let step = 2 * CGFloat.pi / CGFloat(ring.count)
            let start = -CGFloat.pi / 2 + (k.isMultiple(of: 2) ? 0 : step / 2)

            var candidates: [(CGSize, CGFloat)] = []
            while true {
                candidates = ring.enumerated().map { i, a in
                    let angle = start + CGFloat(i) * step
                    return (CGSize(width: cos(angle) * radius, height: sin(angle) * radius),
                            Self.labelWidth(a))
                }
                let clashesPlaced = placed.contains { old in
                    candidates.contains { Self.overlaps(($0.0, $0.1),
                                                        (old.offset, Self.labelWidth(old.associate))) }
                }
                let clashesSameRing = candidates.indices.contains { i in
                    candidates.indices.contains { j in
                        i < j && Self.overlaps(candidates[i], candidates[j])
                    }
                }
                if !clashesPlaced && !clashesSameRing { break }
                radius += 4          // 步长小一点，外推得刚刚好，不白撑大图
            }

            for (i, a) in ring.enumerated() {
                placed.append(Node(associate: a, offset: candidates[i].0))
                maxExtent = max(maxExtent, radius + Self.labelWidth(a) / 2)
            }
        }

        nodes = placed
        boundingRadius = max(maxExtent, Self.innerRadius)
    }

    /// 缩到刚好放进视口 —— 这替掉了原先那个来路不明的魔法数 0.62。
    func fitScale(in size: CGSize) -> CGFloat {
        guard boundingRadius > 0 else { return 1 }
        let usable = min(size.width, size.height) - 24
        return max(0.2, min(1, usable / (boundingRadius * 2)))
    }

    /// 保持最终显示坐标里的 44pt 命中矩形互不覆盖所需的最小缩放。
    /// 密集的「全部」分组宁可允许平移浏览，也不把多个按钮压成同一块命中区域。
    func minimumHitScale(gap: CGFloat = 4) -> CGFloat {
        guard !nodes.isEmpty else { return 0 }
        var required: CGFloat = 0
        // 中心诗人虽不响应点击，也不能被外围按钮盖住。
        for node in nodes {
            let dx = abs(node.offset.width)
            let dy = abs(node.offset.height)
            let requiredX = dx > 0
                ? ((Self.labelWidth(node.associate) + 54) / 2 + gap) / dx
                : CGFloat.infinity
            let requiredY = dy > 0
                ? ((Self.labelHeight + 32) / 2 + gap) / dy
                : CGFloat.infinity
            required = max(required, min(requiredX, requiredY))
        }
        for i in nodes.indices {
            for j in nodes.indices where i < j {
                let a = nodes[i]
                let b = nodes[j]
                let dx = abs(a.offset.width - b.offset.width)
                let dy = abs(a.offset.height - b.offset.height)
                let requiredX = dx > 0
                    ? ((Self.labelWidth(a.associate) + Self.labelWidth(b.associate)) / 2 + gap) / dx
                    : CGFloat.infinity
                let requiredY = dy > 0 ? (Self.labelHeight + gap) / dy : CGFloat.infinity
                required = max(required, min(requiredX, requiredY))
            }
        }
        return required
    }
}
