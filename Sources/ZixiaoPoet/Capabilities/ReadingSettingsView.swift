import ZixiaoPoetCore
//  ReadingSettingsView.swift — 读本的纸色、方向与字号
//
//  三样设置都存在 AppStorage (键沿用 PoetKit 的 `poetkit.*`, 升级不丢偏好), 由 `PoemDetailView` 读。
//  颜色全部来自身份: 「原色」是身份的纸, 「柔纸」是纸上一层 5% 的淡墨 (与 kit `GlazePanel(.wash)` 同调),
//  「夜读」是同一身份按深色外观重解析出的纸墨 —— 不再写死任何色值。

import SwiftUI
import ZixiaoDesign

enum ReadingAppearance: String, CaseIterable, Identifiable {
    case automatic, warm, night
    var id: String { rawValue }
    var title: String {
        switch self { case .automatic: "原色"; case .warm: "柔纸"; case .night: "夜读" }
    }
    func colorScheme(following system: ColorScheme) -> ColorScheme { self == .night ? .dark : system }
    /// 这一档纸色下读本用的主题: 夜读按深色重解析, 其余跟随 App。
    @MainActor func theme(from base: ZXTheme) -> ZXTheme {
        self == .night ? base.poetResolved(for: .dark) : base
    }
    /// 柔纸在纸上叠的那层墨。
    static let warmWash: Double = 0.05
}

/// 读本的纸。读环境里的主题 (夜读时调用方已注入深色主题)。
struct ReadingPaper: View {
    let appearance: ReadingAppearance
    @Environment(\.zxTheme) private var theme
    var body: some View {
        ZStack {
            theme.paper()
            if appearance == .warm { theme.ink(ReadingAppearance.warmWash) }
        }
    }
}

/// 排版方向。竖排: 字从上到下、列从右到左, 一句一列 (kit `VerticalText` + `ZXVerticalForms` 直排标点)。
enum ReadingOrientation: String, CaseIterable, Identifiable {
    case horizontal, vertical
    var id: String { rawValue }
    var title: String { self == .horizontal ? "横排" : "竖排" }
}

/// 字号档位与竖排版面的量级。
///
/// 量级取自 ZixiaoLibrary 的阅读器 (`ClassicReaderView` 默认 22pt, `ClassicMetrics` 列宽 1.72 字、
/// 格高 1.48 字; `ZXReaderStyle.plainSize` 0.68): ZixiaoPoet 不依赖 ZixiaoLibrary (Package.swift
/// 不在本卡范围, kit gap 已记), 这里按同一组比例取值, 基准字号取 ZX 字阶。
enum ReadingMetrics {
    /// 三档 (标准 / 较大 / 最大), 与 PoetKit 存下的 `readingScale` 值一致。
    static let scales: [Double] = [1.0, 1.15, 1.3]
    static let scaleTitles = ["标准", "较大", "最大"]

    /// 横排正文的基准字号: 诗词 = title3 (20), 文赋 = body (17)。随 Dynamic Type。
    static func horizontalBase(prose: Bool) -> CGFloat {
        prose ? ZXTypeRole.body.size : ZXTypeRole.title3.size
    }
    /// 竖排正文的基准字号 = title2 (22), 与阅读器竖排默认字号相同。竖排格子按字号算好,
    /// 用定长字 (不随 Dynamic Type), 大小只由这里的档位控制。
    static let verticalBase: CGFloat = ZXTypeRole.title2.size
    /// 列宽 1.72 字 → 列距 = 0.72 字。
    static let columnGapRatio: CGFloat = 0.72
    /// 同列字距。宋体字身本身已带上下余白, 再留 0.08 字刚好透气 (格高约 1.48 字)。
    static let glyphGapRatio: CGFloat = 0.08
    /// 字格高度的估算 (宋体字身连行距约 1.6 字, 宁大勿小), 只用来决定文赋一列排几个字。
    static let cellHeightRatio: CGFloat = 1.6
    /// 句读: 诗词竖排时一句一列, 在这些标点之后换列。
    static let clauseBreaks: Set<Character> = ["，", "。", "；", "！", "？", "、"]

    /// 诗词竖排的分列: 每段按句读切开, 一句一列 (句末标点留在本列列尾)。
    static func verseColumns(_ lines: [String]) -> String {
        lines.map { line -> String in
            var out = ""
            for ch in line {
                out.append(ch)
                if clauseBreaks.contains(ch) { out.append("\n") }
            }
            return out.trimmingCharacters(in: .newlines)
        }.joined(separator: "\n")
    }

    static func index(of scale: Double) -> Int {
        scales.indices.min(by: { abs(scales[$0] - scale) < abs(scales[$1] - scale) }) ?? 0
    }
    static func size(base: CGFloat, scale: Double) -> CGFloat {
        (base * CGFloat(min(max(scale, scales.first ?? 1), scales.last ?? 1))).rounded()
    }
}

struct ReadingSettingsView: View {
    let sample: String
    let usesProseLayout: Bool
    @Binding var scale: Double
    @Binding var spacious: Bool
    @Binding var appearance: ReadingAppearance
    @Binding var orientation: ReadingOrientation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.zxTheme) private var theme
    /// 纸色样张的高度、竖排预览的高度 (固有尺寸)。
    private static let swatchHeight: CGFloat = 64
    private static let verticalPreviewHeight: CGFloat = 180
    /// 一枚纸色样张的最小宽度 (三枚并排放不下时竖排)。
    private static let swatchMinWidth: CGFloat = 70

    private var sizeIndex: Binding<Int> {
        Binding(get: { ReadingMetrics.index(of: scale) },
                set: { scale = ReadingMetrics.scales[$0] })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .environment(\.colorScheme, appearance.colorScheme(following: colorScheme))
                        .zxTheme(appearance.theme(from: theme))
                        .accessibilityLabel("排版预览：\(sample)")
                }
                .listRowBackground(ReadingPaper(appearance: appearance).zxTheme(appearance.theme(from: theme)))
                Section {
                    Picker("排版方向", selection: $orientation) {
                        ForEach(ReadingOrientation.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("正文字号", selection: sizeIndex) {
                        ForEach(ReadingMetrics.scales.indices, id: \.self) { i in
                            Text(ReadingMetrics.scaleTitles[i]).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("正文字号")
                    Toggle("舒展行距", isOn: $spacious)
                        .font(theme.type.body)
                        .disabled(orientation == .vertical)
                } header: { ListSectionTitle("排版") } footer: {
                    Text(orientation == .vertical
                         ? "竖排时字从上到下、列从右到左，左右滑动翻看；行距由字格决定。"
                         : "在系统文字大小的基础上，调整阅读字号。")
                        .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                }
                .listRowBackground(theme.color.surface)
                Section {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: theme.space.md) { appearanceChoices }
                        VStack(spacing: theme.space.md) { appearanceChoices }
                    }.padding(.vertical, theme.space.sm)
                } header: { ListSectionTitle("纸色") }
                .listRowBackground(theme.color.surface)
            }
            .scrollContentBackground(.hidden)
            .background(theme.paper())
            .zxNavigationTitle("阅读设置", role: .secondary)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .tint(theme.color.accent)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private var preview: some View {
        if orientation == .vertical {
            ReadingPreviewVertical(sample: usesProseLayout ? sample : ReadingMetrics.verseColumns([sample]),
                                   scale: scale, height: Self.verticalPreviewHeight)
        } else {
            ReadingPreviewHorizontal(sample: sample, prose: usesProseLayout, scale: scale, spacious: spacious)
        }
    }

    private var appearanceChoices: some View {
        ForEach(ReadingAppearance.allCases) { option in
            Button { appearance = option } label: {
                VStack(spacing: theme.space.sm) {
                    AppearanceSwatch(option: option, selected: appearance == option, height: Self.swatchHeight)
                        .environment(\.colorScheme, option.colorScheme(following: colorScheme))
                        .zxTheme(option.theme(from: theme))
                    Text(option.title).font(theme.type.subhead).foregroundStyle(theme.color.textPrimary).fixedSize()
                }.frame(minWidth: Self.swatchMinWidth, maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(option.title)纸色")
            .accessibilityAddTraits(appearance == option ? .isSelected : [])
        }
    }
}

/// 纸色样张: 那一档的纸上写一个「文」。选中描强调色的边 + 勾。
private struct AppearanceSwatch: View {
    let option: ReadingAppearance
    let selected: Bool
    let height: CGFloat
    @Environment(\.zxTheme) private var theme
    /// 选中描边的粗细 (固有尺寸: 要比发丝线显眼)。
    private static let selectedBorder: CGFloat = 2
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
        ZStack(alignment: .bottomTrailing) {
            Text("文").font(theme.bodyFont(24, relativeTo: .title2)).foregroundStyle(theme.ink())
                .frame(maxWidth: .infinity, minHeight: height)
            if selected {
                Image(systemName: "checkmark.circle.fill").font(theme.type.caption)
                    .foregroundStyle(theme.color.accent).padding(theme.space.xs + theme.space.xxs)
            }
        }
        .background { ReadingPaper(appearance: option) }
        .clipShape(shape)
        .overlay { shape.strokeBorder(selected ? theme.color.accent : theme.color.separator, lineWidth: selected ? Self.selectedBorder : ZXMetric.hairline) }
    }
}

private struct ReadingPreviewHorizontal: View {
    let sample: String
    let prose: Bool
    let scale: Double
    let spacious: Bool
    @Environment(\.zxTheme) private var theme
    var body: some View {
        let size = ReadingMetrics.size(base: ReadingMetrics.horizontalBase(prose: prose), scale: scale)
        Text(sample)
            .font(theme.bodyFont(size, relativeTo: .body))
            .lineSpacing(spacious ? theme.space.sm + theme.space.xxs : theme.space.xs)
            .lineLimit(3)
            .foregroundStyle(theme.ink())
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, theme.space.md)
    }
}

private struct ReadingPreviewVertical: View {
    let sample: String
    let scale: Double
    let height: CGFloat
    @Environment(\.zxTheme) private var theme
    var body: some View {
        let size = ReadingMetrics.size(base: ReadingMetrics.verticalBase, scale: scale)
        VerticalText(sample, font: theme.bodyFont(size, relativeTo: nil), color: theme.ink(),
                     charSpacing: size * ReadingMetrics.glyphGapRatio,
                     columnSpacing: size * ReadingMetrics.columnGapRatio)
            .frame(height: height, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .clipped()
            .padding(.vertical, theme.space.md)
    }
}
