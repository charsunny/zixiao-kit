//  ZXBentoGrid.swift — 混排网格 (bento)
//
//  大小不一的块拼成一面墙: 主角占 2×2, 配角 1×1, 横条 2×1, 竖条 1×2。
//  用自定义 `Layout` 而不是 LazyVGrid: LazyVGrid 每格一样大, 做不出跨行跨列;
//  Grid 能跨列不能跨行。
//
//  排布算法抽成纯函数 `ZXBentoLayout.place(sizes:columns:)`, 测试不起 UI 就能验证。

import SwiftUI

/// 一块占几格。
public enum ZXBentoSize: String, CaseIterable, Sendable, Hashable {
    /// 1×1
    case small
    /// 2×1 (横条)
    case wide
    /// 1×2 (竖条)
    case tall
    /// 2×2 (主角)
    case large

    public var columnSpan: Int {
        switch self {
        case .small, .tall: 1
        case .wide, .large: 2
        }
    }

    public var rowSpan: Int {
        switch self {
        case .small, .wide: 1
        case .tall, .large: 2
        }
    }
}

/// 一块落在哪: 起始列、起始行 (都从 0 起) 与实际跨度。
public struct ZXBentoSlot: Sendable, Hashable {
    public let column: Int
    public let row: Int
    public let columnSpan: Int
    public let rowSpan: Int

    public init(column: Int, row: Int, columnSpan: Int, rowSpan: Int) {
        self.column = column
        self.row = row
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
    }
}

/// 一次排布的结果。`slots` 与输入的 `sizes` 一一对应、顺序相同。
public struct ZXBentoPlacement: Sendable, Hashable {
    public let slots: [ZXBentoSlot]
    /// 总行数。
    public let rows: Int

    public init(slots: [ZXBentoSlot], rows: Int) {
        self.slots = slots
        self.rows = rows
    }
}

public enum ZXBentoLayout {
    /// 按行贪心排布: 每一块依次放进「从上到下、从左到右第一个放得下的位置」。
    ///
    /// 为什么允许回填前面的空洞 (而不是只往后排): 只往后排时, 一块 2×2 后面跟 1×1 与 2×1,
    /// 横条放不进 2×2 旁边那一列, 就会在它右侧留下一个永久的洞; 回填让后来的小块补进去,
    /// 墙面更整。代价是视觉顺序可能与数据顺序略有出入 —— 读屏仍按数据顺序读, 所以把
    /// 最重要的块放在最前面即可。
    ///
    /// 跨度大于列数的块夹到列数 (单列时 2×2 变成 1×2), 不会放不下。
    public static func place(sizes: [ZXBentoSize], columns: Int) -> ZXBentoPlacement {
        let columns = max(columns, 1)
        var occupied: [[Bool]] = []
        var slots: [ZXBentoSlot] = []
        slots.reserveCapacity(sizes.count)

        func isFree(row: Int, column: Int, width: Int, height: Int) -> Bool {
            for r in row..<(row + height) where r < occupied.count {
                for c in column..<(column + width) where occupied[r][c] { return false }
            }
            return true
        }

        for size in sizes {
            let width = min(size.columnSpan, columns)
            let height = size.rowSpan
            var row = 0
            search: while true {
                for column in 0...(columns - width) where isFree(row: row, column: column, width: width, height: height) {
                    while occupied.count < row + height { occupied.append(Array(repeating: false, count: columns)) }
                    for r in row..<(row + height) {
                        for c in column..<(column + width) { occupied[r][c] = true }
                    }
                    slots.append(ZXBentoSlot(column: column, row: row, columnSpan: width, rowSpan: height))
                    break search
                }
                row += 1
            }
        }
        return ZXBentoPlacement(slots: slots, rows: occupied.count)
    }
}

// MARK: - Layout

private struct ZXBentoSizeKey: LayoutValueKey {
    static let defaultValue: ZXBentoSize = .small
}

public extension View {
    /// 声明这一块在 `ZXBentoGrid` 里占几格。只对网格的直接子视图生效。
    func zxBento(_ size: ZXBentoSize) -> some View {
        layoutValue(key: ZXBentoSizeKey.self, value: size)
    }
}

/// 混排网格。子视图用 `.zxBento(_:)` 声明大小, 不声明的算 1×1。
///
/// 行高 = 列宽 × `rowAspect`, 所以 1×1 默认是正方形; 跨格的块把中间的间距也吃进去,
/// 2×2 与两个 1×1 叠起来严丝合缝。
public struct ZXBentoGrid: Layout {
    public var columns: Int
    public var spacing: CGFloat
    public var rowAspect: CGFloat

    /// Layout 读不到环境, 所以间距默认直接取标准尺的 `md`; 需要跟主题走时由调用方传 `theme.space.md`。
    public init(columns: Int = 2, spacing: CGFloat = ZXSpaceTokens.standard.md, rowAspect: CGFloat = 1) {
        self.columns = max(columns, 1)
        self.spacing = spacing
        self.rowAspect = rowAspect
    }

    public typealias Cache = ZXBentoPlacement

    public func makeCache(subviews: Subviews) -> ZXBentoPlacement {
        ZXBentoLayout.place(sizes: subviews.map { $0[ZXBentoSizeKey.self] }, columns: columns)
    }

    public func updateCache(_ cache: inout ZXBentoPlacement, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    /// 没有给宽度 (放进横向 ScrollView 之类) 时的每列宽度。只是兜底, 正常都在有宽度的竖向容器里。
    private static let fallbackColumnWidth: CGFloat = 160

    private func columnWidth(for width: CGFloat) -> CGFloat {
        max((width - spacing * CGFloat(columns - 1)) / CGFloat(columns), 0)
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ZXBentoPlacement) -> CGSize {
        let width: CGFloat
        if let proposed = proposal.width, proposed.isFinite {
            width = proposed
        } else {
            width = Self.fallbackColumnWidth * CGFloat(columns) + spacing * CGFloat(columns - 1)
        }
        let rowHeight = columnWidth(for: width) * rowAspect
        let rows = CGFloat(cache.rows)
        let height = rows > 0 ? rows * rowHeight + (rows - 1) * spacing : 0
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                              cache: inout ZXBentoPlacement) {
        let cellWidth = columnWidth(for: bounds.width)
        let rowHeight = cellWidth * rowAspect
        for (subview, slot) in zip(subviews, cache.slots) {
            let x = bounds.minX + CGFloat(slot.column) * (cellWidth + spacing)
            let y = bounds.minY + CGFloat(slot.row) * (rowHeight + spacing)
            let w = CGFloat(slot.columnSpan) * cellWidth + CGFloat(slot.columnSpan - 1) * spacing
            let h = CGFloat(slot.rowSpan) * rowHeight + CGFloat(slot.rowSpan - 1) * spacing
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: w, height: h))
        }
    }
}

// MARK: - 块

/// 网格里的一块: 卡面 + 按压下陷 + 滚动显现。
///
/// 按压: 缩一点、影子收回 (e1 → e0), 像按进纸里。滚动显现: 块进出屏幕边缘时淡一点、
/// 小一点, 进来时回到原样 —— 墙面在滚动里「浮上来」。减少动态时只保留淡入淡出。
public struct ZXBentoTile<Content: View>: View {
    let action: (@MainActor () -> Void)?
    let content: Content

    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - action: 点按动作; nil 则是不可点的展示块 (没有按压效果)。
    public init(action: (@MainActor () -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    public var body: some View {
        let reduce = reduceMotion
        tile
            .scrollTransition(.animated(theme.motion.adapted(theme.motion.smooth, reduceMotion: reduce))) { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : 0.35)
                    .scaleEffect(phase.isIdentity || reduce ? 1 : 0.94)
            }
    }

    @ViewBuilder
    private var tile: some View {
        let card = content
            .padding(theme.space.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        if let action {
            Button(action: action) { card }
                .buttonStyle(ZXBentoPressStyle())
        } else {
            card.zxSurface(.e1, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
    }
}

private struct ZXBentoPressStyle: ButtonStyle {
    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 下陷的幅度。
    private let pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .zxSurface(pressed ? .e0 : .e1, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
            .scaleEffect(pressed && !reduceMotion ? pressedScale : 1)
            .contentShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
            .animation(theme.motion.adapted(pressed ? theme.motion.snappy : theme.motion.bouncy,
                                            reduceMotion: reduceMotion),
                       value: pressed)
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, new in new }
    }
}

#if DEBUG
private struct ZXBentoPreview: View {
    @Environment(\.zxTheme) private var theme

    private let items: [(String, ZXBentoSize)] = [
        ("主角 2×2", .large), ("1×1", .small), ("1×1", .small),
        ("横条 2×1", .wide), ("竖条 1×2", .tall), ("1×1", .small), ("1×1", .small),
    ]

    var body: some View {
        ZXBentoGrid(columns: 2, spacing: theme.space.md, rowAspect: 0.6) {
            ForEach(items.indices, id: \.self) { i in
                ZXBentoTile(action: {}) {
                    Text(items[i].0)
                        .font(items[i].1 == .large ? theme.type.title2 : theme.type.subhead)
                        .foregroundStyle(theme.color.textPrimary)
                }
                .zxBento(items[i].1)
            }
        }
    }
}

#Preview("混排网格") {
    PreviewPage {
        ZXBentoPreview()
    }
}
#endif
