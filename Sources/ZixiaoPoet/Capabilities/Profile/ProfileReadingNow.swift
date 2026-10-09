import ZixiaoPoetCore
//  ProfileReadingNow.swift — 书房的「在读」: 最近三篇, 大封面 + 一道细进度线
//
//  取 `userData.reading` 的前三条 (已按最近阅读排好)。每篇一本线装封面 (宽 ≈ 内容宽的 1/3), 封面正下方是一道发丝进度线
//  (底 = `rule`, 填充 = `seal`, 不写百分数; 各栏对齐), 再下是题目; 点一下接着读 (推入读本页)。
//  没有记录时留原来的空态 (「你的阅读，从这里留下。」)。颜色 / 间距 / 字都取 ZX token。

import SwiftUI
import ZixiaoCore
import ZixiaoDesign

struct ProfileReadingNow: View {
    let ctx: CompositionContext
    /// 最近的阅读记录 (调用方已截到三条以内)。
    let records: [ReadingState]
    /// 已载入的作品 (按 id); 还没载入的那几篇先不画。
    let poems: [UUID: Poem]
    let loading: Bool
    let namespace: Namespace.ID
    /// 空态按钮: 去目录挑一篇。
    let pickPoem: () -> Void

    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 本节的可用宽度 (封面宽按它的 1/3 推)。
    @State private var contentWidth: CGFloat = 0

    private struct Item: Identifiable {
        let record: ReadingState
        let poem: Poem
        var id: UUID { poem.id }
    }

    private var items: [Item] {
        records.prefix(Self.limit).compactMap { record in poems[record.poemId].map { Item(record: record, poem: $0) } }
    }
    static let limit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            ZixiaoDesign.SectionLabel("在读")
            if !items.isEmpty {
                shelf
            } else if !loading && records.isEmpty {
                ZXGhostState("你的阅读，从这里留下。",
                             message: "最近打开的作品会回到这里。读到喜欢的篇章，轻点书签，留在自己的书房。",
                             actionTitle: "挑一篇开始阅读", systemImage: "book", action: pickPoem)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
    }

    // MARK: 书架

    /// 三栏的栏宽: 内容宽去掉两道间距后三等分; 大字号档改成单栏竖排, 封面取半宽。
    private var columnWidth: CGFloat {
        let gap = theme.space.lg
        if typeSize.isAccessibilitySize { return max(0, ((contentWidth - gap) / 2).rounded(.down)) }
        return max(0, ((contentWidth - gap * CGFloat(Self.limit - 1)) / CGFloat(Self.limit)).rounded(.down))
    }

    @ViewBuilder private var shelf: some View {
        if contentWidth > 0 {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: theme.space.xl) {
                    ForEach(items) { column($0) }
                }
            } else {
                HStack(alignment: .top, spacing: theme.space.lg) {
                    ForEach(items) { column($0) }
                    if items.count < Self.limit { Spacer(minLength: 0) }
                }
            }
        }
    }

    private func column(_ item: Item) -> some View {
        let poem = item.poem
        let title = ctx.workTitle(poem)
        let width = columnWidth
        return NavigationLink {
            PoemDetailView(ctx: ctx, poem: poem).readingTransition(poem.id, in: namespace)
        } label: {
            VStack(alignment: .leading, spacing: theme.space.sm) {
                ReadingCover(title: title, author: ctx.composition.poet.name,
                             genre: ctx.genre(for: poem), width: width)
                    .readingTransitionSource(poem.id, in: namespace)
                ReadingHairline(fraction: item.record.finished ? 1 : item.record.progress)
                Text(title).font(theme.type.subhead.weight(.semibold)).foregroundStyle(theme.color.textPrimary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("《\(title)》，\(Self.progressPhrase(item.record))")
        .accessibilityHint("继续读")
    }

    /// 「读到三成」「已读完」「刚开始读」。
    static func progressPhrase(_ record: ReadingState) -> String {
        if record.finished { return "已读完" }
        let tenths = Int((min(max(record.progress, 0), 1) * 10).rounded())
        let digits = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
        switch tenths {
        case ..<1: return "刚开始读"
        case 10...: return "读到九成以上"
        default: return "读到\(digits[tenths - 1])成"
        }
    }
}

/// 封面下的一道发丝进度线: 底是 `rule`, 已读的一段是 `seal`。不写数字。
private struct ReadingHairline: View {
    let fraction: Double
    @Environment(\.zxTheme) private var theme

    var body: some View {
        Rectangle().fill(theme.rule)
            .frame(height: theme.space.xxs)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle().fill(theme.seal)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }
}
