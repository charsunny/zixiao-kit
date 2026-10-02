//  LifeYearTrack.swift — 年轨: 屏幕前沿一条细线, 拖动跳卷
//
//  每卷在轨上占等长一段 (乌台一年与元祐九年一样长 —— 这是目录, 不是比例尺, 等分才好拖)。
//  平时只有发丝线、卷界的小刻度和当前卷那一段加粗的墨, 像系统的滚动指示; 手指按上去才浮出各卷的
//  起始年份与当前卷的名签。换卷时一下选择反馈 (UISelectionFeedbackGenerator); 滚动跳转不带动画,
//  跟手; 点一下也能跳。VoiceOver 下是一个可调节元素 (上下轻扫换卷)。

import SwiftUI
import UIKit
import ZixiaoDesign

struct LifeYearTrack: View {
    let chapters: [PoetMoments.Chapter]
    /// 当前看到的卷 (epochSequence)。
    let current: Int?
    /// 跳到某卷 (epochSequence)。
    let select: (Int) -> Void
    @State private var dragging: Int?
    @State private var feedback = UISelectionFeedbackGenerator()
    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 发丝线离屏幕前沿的距离。
    static let lineX: CGFloat = 9
    /// 当前卷那一段的粗细。
    static let activeWidth: CGFloat = 3

    private var active: Int? { dragging ?? current }
    private var activeIndex: Int? { active.flatMap { seq in chapters.firstIndex { $0.epochSequence == seq } } }

    var body: some View {
        GeometryReader { geo in
            let segment = geo.size.height / CGFloat(max(chapters.count, 1))
            ZStack(alignment: .topLeading) {
                Rectangle().fill(theme.rule)
                    .frame(width: 1, height: geo.size.height)
                    .offset(x: Self.lineX - 0.5)
                ForEach(Array(chapters.enumerated()), id: \.element.id) { index, _ in
                    Rectangle().fill(theme.ink(0.35))
                        .frame(width: 7, height: 1)
                        .offset(x: Self.lineX - 3.5, y: segment * CGFloat(index))
                }
                Rectangle().fill(theme.ink(0.35))
                    .frame(width: 7, height: 1)
                    .offset(x: Self.lineX - 3.5, y: geo.size.height - 1)
                if let index = activeIndex {
                    Capsule().fill(theme.ink(dragging == nil ? 0.55 : 0.85))
                        .frame(width: Self.activeWidth, height: max(segment - 4, 6))
                        .offset(x: Self.lineX - Self.activeWidth / 2, y: segment * CGFloat(index) + 2)
                }
                if dragging != nil {
                    labels(segment: segment, height: geo.size.height)
                        .transition(.opacity)
                }
            }
            .frame(width: LifeLayout.trackInset, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(scrub(segment: segment))
        }
        .frame(width: LifeLayout.trackInset)
        .animation(theme.motion.adapted(theme.motion.snappy, reduceMotion: reduceMotion), value: dragging == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("年轨")
        .accessibilityValue(activeIndex.map { accessibilityValue(chapters[$0], position: $0 + 1) } ?? "")
        .accessibilityHint("上下轻扫换卷")
        .accessibilityAdjustableAction { direction in
            let index = activeIndex ?? 0
            let next = direction == .increment ? min(index + 1, chapters.count - 1) : max(index - 1, 0)
            guard chapters.indices.contains(next) else { return }
            select(chapters[next].epochSequence)
        }
    }

    private func accessibilityValue(_ chapter: PoetMoments.Chapter, position: Int) -> String {
        "\(PoetMoments.Chapter.ordinalLabel(position))，\(chapter.title)，\(chapter.yearsLabel)"
    }

    private func scrub(segment: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !chapters.isEmpty, segment > 0 else { return }
                let index = min(max(Int(value.location.y / segment), 0), chapters.count - 1)
                let sequence = chapters[index].epochSequence
                if dragging == nil { feedback.prepare() }
                guard dragging != sequence else { return }
                dragging = sequence
                feedback.selectionChanged()
                select(sequence)
            }
            .onEnded { _ in dragging = nil }
    }

    /// 拖动时浮出: 各卷起始年 + 末年, 当前卷再加一枚名签。
    private func labels(segment: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                yearTag(String(chapter.startYear))
                    .offset(x: Self.lineX + theme.space.sm, y: segment * CGFloat(index) - theme.space.sm)
            }
            if let last = chapters.last {
                yearTag(String(last.endYear))
                    .offset(x: Self.lineX + theme.space.sm, y: height - theme.space.lg)
            }
            if let index = activeIndex {
                let chapter = chapters[index]
                VStack(alignment: .leading, spacing: theme.space.xxs) {
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
                .offset(x: Self.lineX + theme.space.xxxl + theme.space.lg,
                        y: min(max(segment * CGFloat(index) + segment / 2 - theme.space.xl, 0), height - theme.space.xxxl))
            }
        }
        .allowsHitTesting(false)
    }

    private func yearTag(_ text: String) -> some View {
        Text(text)
            .font(theme.type.caption.monospacedDigit())
            .foregroundStyle(theme.color.textSecondary)
            .padding(.horizontal, theme.space.xs)
            .padding(.vertical, theme.space.xxs)
            .background(theme.paper(0.9), in: Capsule())
            .fixedSize()
    }
}
