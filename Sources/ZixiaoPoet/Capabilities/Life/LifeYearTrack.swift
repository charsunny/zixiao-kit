import ZixiaoPoetCore
//  LifeYearTrack.swift — 年轨: 屏幕前沿一条细线, 标着年份; 点年份跳到那一年, 按住拖动跳卷
//
//  每卷在轨上占等长一段 (乌台一年与元祐九年一样长 —— 这是目录, 不是比例尺, 等分才好拖),
//  段内按年线性。标签: 每卷的起始年必标 (墨稍重), 段里放得下再补逢五的年 (1040 1045 …),
//  标签按 90° 转成竖读 (与竖排西文同向), 从刻度处往下写; 放不下的就不标, 绝不叠字。
//  画面本身不接触摸: 手势在 `LifeRailGestureHook` (挂在滚动视图上, 普通滑动直接穿过年轨)。
//  按住进入拖轨时浮出当前卷的名签, 换卷一下选择反馈。VoiceOver 下是一个可调节元素
//  (上下轻扫换卷), 另有每个年份标签的自定义动作。

import SwiftUI
import UIKit
import ZixiaoDesign

/// 年轨的刻度与标签: 纯值, 年轨画它, 手势按它把 y 换成卷 / 年。
struct LifeRailLayout: Equatable {
    struct Label: Equatable, Identifiable {
        let year: Int
        /// 刻度的 y。
        let y: CGFloat
        /// 字从哪里起 (末一个标签贴着下端时会往上让)。
        let textStart: CGFloat
        let isChapterStart: Bool
        var id: Int { year }
    }

    let height: CGFloat
    let segment: CGFloat
    let chapterCount: Int
    let labelLength: CGFloat
    let labels: [Label]

    init(chapters: [PoetMoments.Chapter], height: CGFloat, labelLength: CGFloat, gap: CGFloat) {
        self.height = height
        self.chapterCount = chapters.count
        self.labelLength = labelLength
        let segment = height / CGFloat(max(chapters.count, 1))
        self.segment = segment
        guard !chapters.isEmpty, height > 0 else { labels = []; return }

        // 卷 i 管 [起始年, 下一卷起始年) 这几年; 末卷管到它的末年。
        func span(_ index: Int) -> (start: Int, end: Int) {
            let start = chapters[index].startYear
            let next = index + 1 < chapters.count ? chapters[index + 1].startYear : chapters[index].endYear + 1
            return (start, max(next, start + 1))
        }
        func y(_ year: Int, in index: Int) -> CGFloat {
            let (start, end) = span(index)
            let fraction = min(max(CGFloat(year - start) / CGFloat(end - start), 0), 1)
            return segment * (CGFloat(index) + fraction)
        }

        var candidates: [(year: Int, y: CGFloat, major: Bool)] = []
        for index in chapters.indices {
            candidates.append((chapters[index].startYear, y(chapters[index].startYear, in: index), true))
        }
        if let last = chapters.last, last.endYear > last.startYear {
            candidates.append((last.endYear, height, true))
        }
        for index in chapters.indices {
            let (start, end) = span(index)
            for year in (start + 1)..<end where year % 5 == 0 {
                candidates.append((year, y(year, in: index), false))
            }
        }
        // 卷起始年先占位, 逢五的年在空处补; 每个标签占 [字起, 字起 + 字长], 之间至少留 gap。
        var placed: [Label] = []
        for candidate in candidates {
            let textStart = min(max(candidate.y, 0), max(height - labelLength, 0))
            let clear = placed.allSatisfy { other in
                textStart >= other.textStart + labelLength + gap || textStart + labelLength + gap <= other.textStart
            }
            guard clear, !placed.contains(where: { $0.year == candidate.year }) else { continue }
            placed.append(Label(year: candidate.year, y: candidate.y, textStart: textStart,
                                isChapterStart: candidate.major))
        }
        labels = placed.sorted { $0.y < $1.y }
    }

    /// y 落在哪一卷的段里。
    func chapterIndex(at y: CGFloat) -> Int {
        guard chapterCount > 0, segment > 0 else { return 0 }
        return min(max(Int(y / segment), 0), chapterCount - 1)
    }

    /// 离 y 最近的年份标签 (按字的中心量)。
    func label(near y: CGFloat) -> Label? {
        labels.min { abs($0.textStart + labelLength / 2 - y) < abs($1.textStart + labelLength / 2 - y) }
    }
}

struct LifeYearTrack: View {
    let chapters: [PoetMoments.Chapter]
    /// 当前看到的卷 (epochSequence)。
    let current: Int?
    /// 正在拖轨经过的卷 (epochSequence); nil = 没在拖。
    let scrubbing: Int?
    /// 刚点中的年份 (短暂加重)。
    let flashYear: Int?
    /// 刻度算好 / 变了时报给根页 (手势按它换算)。
    let onLayout: (LifeRailLayout) -> Void
    /// 跳到某卷 (VoiceOver 调节)。
    let select: (Int) -> Void
    /// 跳到某年 (VoiceOver 自定义动作)。
    let selectYear: (Int) -> Void
    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 竖线离年轨前沿的距离 (标签在线的外侧, 贴屏幕前沿)。
    static let lineX: CGFloat = 19.5
    /// 标签中心离前沿的距离。
    static let labelX: CGFloat = 9
    /// 当前卷那一段的粗细。
    static let activeWidth: CGFloat = 3
    /// 年轨标签的字号上限: 再大竖读的字就宽过 22pt 的年轨。
    static let typeSizeCap: DynamicTypeSize = .xxLarge

    /// 四位年份竖读时的长度: 随字号, 封顶到 `typeSizeCap` (标签本身也封在这一档)。
    private var labelLength: CGFloat {
        let category = UIContentSizeCategory(min(typeSize, Self.typeSizeCap))
        return UIFontMetrics(forTextStyle: .caption2)
            .scaledValue(for: 26, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
            .rounded(.up)
    }

    private var active: Int? { scrubbing ?? current }
    private var activeIndex: Int? { active.flatMap { seq in chapters.firstIndex { $0.epochSequence == seq } } }

    var body: some View {
        GeometryReader { geo in
            let layout = LifeRailLayout(chapters: chapters, height: geo.size.height,
                                        labelLength: labelLength, gap: theme.space.sm)
            ZStack(alignment: .topLeading) {
                haze(height: geo.size.height)
                Rectangle().fill(theme.rule)
                    .frame(width: 1, height: geo.size.height)
                    .offset(x: Self.lineX - 0.5)
                ForEach(layout.labels) { label in
                    Rectangle().fill(theme.ink(label.isChapterStart ? 0.4 : 0.25))
                        .frame(width: label.isChapterStart ? 5 : 3, height: 1)
                        .offset(x: Self.lineX - (label.isChapterStart ? 5 : 3), y: min(label.y, geo.size.height - 1))
                    yearLabel(label)
                        .position(x: Self.labelX, y: label.textStart + layout.labelLength / 2)
                }
                if let index = activeIndex {
                    Capsule().fill(theme.ink(scrubbing == nil ? 0.55 : 0.85))
                        .frame(width: Self.activeWidth, height: max(layout.segment - 4, 6))
                        .offset(x: Self.lineX - Self.activeWidth / 2, y: layout.segment * CGFloat(index) + 2)
                }
                if scrubbing != nil, let index = activeIndex {
                    nameTag(index: index, layout: layout)
                        .transition(.opacity)
                }
            }
            .frame(width: LifeLayout.trackInset, height: geo.size.height, alignment: .topLeading)
            .onChange(of: layout, initial: true) { _, layout in onLayout(layout) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("年轨")
            .accessibilityValue(activeIndex.map { accessibilityValue(chapters[$0], position: $0 + 1) } ?? "")
            .accessibilityHint("上下轻扫换卷; 也可在动作里选年份")
            .accessibilityAdjustableAction { direction in
                let index = activeIndex ?? 0
                let next = direction == .increment ? min(index + 1, chapters.count - 1) : max(index - 1, 0)
                guard chapters.indices.contains(next) else { return }
                select(chapters[next].epochSequence)
            }
            .accessibilityActions {
                ForEach(layout.labels) { label in
                    Button("跳到 \(String(label.year)) 年") { selectYear(label.year) }
                }
            }
        }
        .frame(width: LifeLayout.trackInset)
        .allowsHitTesting(false)
        .animation(theme.motion.adapted(theme.motion.snappy, reduceMotion: reduceMotion), value: scrubbing == nil)
        .animation(theme.motion.adapted(theme.motion.standard, reduceMotion: reduceMotion), value: flashYear)
    }

    private func accessibilityValue(_ chapter: PoetMoments.Chapter, position: Int) -> String {
        "\(PoetMoments.Chapter.ordinalLabel(position))，\(chapter.title)，\(chapter.yearsLabel)"
    }

    /// 年轨底下一层向内渐隐的纸: 落在纸上看不出, 落在卷封面的画上替标签垫一层; 拖轨时加浓。
    private func haze(height: CGFloat) -> some View {
        LinearGradient(colors: [theme.paper(scrubbing == nil ? 0.7 : 0.94), theme.paper(0)],
                       startPoint: .leading, endPoint: .trailing)
            .frame(width: LifeLayout.trackInset + theme.space.xs, height: height + theme.space.lg * 2)
            .offset(y: -theme.space.lg)
            .accessibilityHidden(true)
    }

    private func yearLabel(_ label: LifeRailLayout.Label) -> some View {
        let emphasized = label.year == flashYear
            || (scrubbing != nil && label.isChapterStart && chapters.firstIndex { $0.startYear == label.year } == activeIndex)
        return Text(String(label.year))
            .font(theme.uiFont(11, relativeTo: .caption2).monospacedDigit()
                .weight(label.isChapterStart || emphasized ? .medium : .regular))
            .foregroundStyle(emphasized ? theme.color.textPrimary
                             : label.isChapterStart ? theme.color.textSecondary : theme.muted)
            .lineLimit(1)
            .fixedSize()
            .dynamicTypeSize(...Self.typeSizeCap)
            .rotationEffect(.degrees(90))
    }

    /// 拖轨时浮出: 当前卷的名签。
    private func nameTag(index: Int, layout: LifeRailLayout) -> some View {
        let chapter = chapters[index]
        return VStack(alignment: .leading, spacing: theme.space.xxs) {
            Text("\(PoetMoments.Chapter.ordinalLabel(index + 1)) · \(chapter.title)")
                .font(theme.type.subhead.weight(.medium))
                .foregroundStyle(theme.color.textPrimary)
            Text(chapter.yearsLabel)
                .font(theme.type.footnote.monospacedDigit())
                .foregroundStyle(theme.color.textSecondary)
        }
        .padding(.horizontal, theme.space.md)
        .padding(.vertical, theme.space.sm)
        .zxSurface(.e2, in: RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
        .fixedSize()
        .offset(x: Self.lineX + theme.space.xxxl,
                y: min(max(layout.segment * CGFloat(index) + layout.segment / 2 - theme.space.xl, 0),
                       layout.height - theme.space.xxxl))
    }
}
