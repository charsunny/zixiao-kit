//  VerticalText.swift — 竖排: 字从上到下, 列从右到左, 古书的读法
//
//  SwiftUI 没有 writing-mode。Flutter 版用 Wrap 的纵向流拼; 这里用 `Layout` 协议:
//  每个字一个等大的格子 (汉字本是方块字, 等格正是雕版的排法), 一列排满往左起新列。
//  高度有界时回绕; 无界时每一行 (换行符切开的一段) 各占一整列 —— 诗正是这样排的。
//
//  线装书阅读页的版式 (版心、界栏、夹注) 另有讲究, 归 ZixiaoLibrary; 这里只管
//  一句话、一首诗、一个书名。

import SwiftUI

public struct VerticalText: View, Sendable {
    let text: String
    let font: Font?
    let color: Color?
    let charSpacing: CGFloat
    let columnSpacing: CGFloat

    @Environment(\.zxTheme) private var theme
    @Environment(\.legibilityWeight) private var legibilityWeight

    /// - Parameters:
    ///   - font: 缺省用身份的正文字 20pt。
    ///   - color: 缺省用墨。
    ///   - charSpacing: 同列相邻两字的间距。
    ///   - columnSpacing: 列距。
    public init(_ text: String, font: Font? = nil, color: Color? = nil,
                charSpacing: CGFloat = 2, columnSpacing: CGFloat = 12) {
        self.text = text
        self.font = font
        self.color = color
        self.charSpacing = charSpacing
        self.columnSpacing = columnSpacing
    }

    public var body: some View {
        let glyphs = ZXVerticalLayout.glyphs(text)
        ZXVerticalFlow(charSpacing: charSpacing, columnSpacing: columnSpacing) {
            ForEach(glyphs.indices, id: \.self) { i in
                Text(String(glyphs[i].character))
                    .font(font ?? theme.bodyFont(20, legibilityWeight: legibilityWeight))
                    .foregroundStyle(color ?? theme.ink())
                    .fixedSize()
                    .layoutValue(key: ZXGlyphInfo.self, value: glyphs[i])
            }
        }
        // 逐字读会被 VoiceOver 念成一串单字; 整段交给它念原文。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - 排版逻辑 (纯函数, 便于测试)

/// 一个字格: 已转直排形的字、是否另起一列 (原文此处有换行)、是否标点。
public struct ZXGlyph: Sendable, Hashable {
    public let character: Character
    public let startsLine: Bool
    public let isPunctuation: Bool
}

public enum ZXVerticalLayout: Sendable {
    /// 原文 → 字格序列。换行符不占格, 只让下一个字另起一列; 连续空行保留为空列。
    public static func glyphs(_ text: String) -> [ZXGlyph] {
        var out: [ZXGlyph] = []
        var pendingBreak = false
        for ch in text {
            if ch.isNewline {
                if pendingBreak { out.append(ZXGlyph(character: "\u{3000}", startsLine: true, isPunctuation: false)) }
                pendingBreak = true
                continue
            }
            out.append(ZXGlyph(character: ZXVerticalForms.vertical(ch),
                               startsLine: pendingBreak,
                               isPunctuation: ZXVerticalForms.isPunctuation(ch)))
            pendingBreak = false
        }
        return out
    }

    /// 把字格分进各列 (从右往左的第 0、1、2… 列), 返回每列的字格下标。
    ///
    /// - Parameter capacity: 一列最多几个字; nil 表示不回绕。
    /// 避头: 标点不居列首。排到列尾放不下时让它挤在上一列的末尾 (「挂」出一格),
    /// 这是雕版与活字版里常见的处理, 比把前一个字拽到下一列更省。
    public static func columns(_ glyphs: [ZXGlyph], capacity: Int?) -> [[Int]] {
        var result: [[Int]] = []
        var current: [Int] = []
        let cap = capacity.map { max($0, 1) }
        for (i, g) in glyphs.enumerated() {
            if g.startsLine, !current.isEmpty || !result.isEmpty {
                result.append(current)
                current = []
            }
            if let cap, current.count >= cap {
                if g.isPunctuation, !current.isEmpty {
                    current.append(i)  // 挂在列尾
                    continue
                }
                result.append(current)
                current = []
            }
            current.append(i)
        }
        if !current.isEmpty || result.isEmpty { result.append(current) }
        return result
    }
}

// MARK: - Layout

struct ZXGlyphInfo: LayoutValueKey {
    static let defaultValue = ZXGlyph(character: " ", startsLine: false, isPunctuation: false)
}

/// 等格竖排流。格子取所有字里最大的那个 —— 同一段里字号一致时就是一个字的方框。
struct ZXVerticalFlow: Layout {
    let charSpacing: CGFloat
    let columnSpacing: CGFloat

    struct Cache {
        var cell: CGSize
        var glyphs: [ZXGlyph]
    }

    func makeCache(subviews: Subviews) -> Cache {
        var cell = CGSize.zero
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            cell.width = max(cell.width, size.width)
            cell.height = max(cell.height, size.height)
        }
        return Cache(cell: cell, glyphs: subviews.map { $0[ZXGlyphInfo.self] })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    private func capacity(for height: CGFloat?, cell: CGSize) -> Int? {
        guard let height, height.isFinite, cell.height > 0 else { return nil }
        // 加一点余量: 高度恰好等于 n 格时, 浮点误差不该让它少排一个字。
        return max(1, Int(((height + charSpacing) / (cell.height + charSpacing) + 0.001).rounded(.down)))
    }

    private func columns(_ proposal: ProposedViewSize, cache: Cache) -> [[Int]] {
        ZXVerticalLayout.columns(cache.glyphs, capacity: capacity(for: proposal.height, cell: cache.cell))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let cols = columns(proposal, cache: cache)
        let tallest = cols.map(\.count).max() ?? 0
        let width = CGFloat(cols.count) * cache.cell.width + CGFloat(max(cols.count - 1, 0)) * columnSpacing
        let height = CGFloat(tallest) * cache.cell.height + CGFloat(max(tallest - 1, 0)) * charSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        // 用父视图给的提议而不是 bounds 重新分列: 挂在列尾的标点会让实际高度比提议多一格,
        // 按 bounds 重算就会得到另一种分法, 与 sizeThatFits 对不上。
        let cols = columns(proposal, cache: cache)
        let cell = cache.cell
        for (c, column) in cols.enumerated() {
            // 第 0 列贴右边
            let x = bounds.maxX - cell.width / 2 - CGFloat(c) * (cell.width + columnSpacing)
            for (r, index) in column.enumerated() {
                let y = bounds.minY + cell.height / 2 + CGFloat(r) * (cell.height + charSpacing)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .center,
                                      proposal: ProposedViewSize(cell))
            }
        }
    }
}

#if DEBUG
#Preview("竖排") {
    PreviewPage {
        HStack(alignment: .top, spacing: 32) {
            VerticalText("大江东去，浪淘尽，\n千古风流人物。\n故垒西边，人道是，\n三国周郎赤壁。")
            VerticalText("《论语》曰：「学而时习之，不亦说乎？」", font: ZXFont.serif(20))
                .frame(height: 200, alignment: .top)
        }
    }
}
#endif
