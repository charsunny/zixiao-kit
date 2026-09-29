//  ZXGhostState.swift — 幽灵空态: 「还没有内容, 去创建」
//
//  与 `EmptyState` 分工:
//  - `EmptyState` 是古语引文式的安静空态 —— 「书架还空着」, 配一句「学而时习之」;
//    不急着让人做什么, 用在浏览型页面。
//  - `ZXGhostState` 用在「等你来填」的页面 (摘抄本、笔记): 几行淡淡的幽灵行预示内容
//    填进来会长什么样, 再给一个主动作。空白本身在教人怎么用, 比一句说明更直接。
//
//  幽灵行是装饰, 读屏跳过; 减少动态时不呼吸。

import SwiftUI

public struct ZXGhostState: View {
    let title: String
    let message: String?
    let actionTitle: String
    let systemImage: String?
    let rows: Int
    let action: @MainActor () -> Void

    /// 主动作被点了几次, 只用来触发触觉。
    @State private var taps = 0
    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 幽灵行的固有几何: 行高与行首方块的边长。
    private let rowHeight: CGFloat = 56
    private let markSize: CGFloat = 36
    private let lineHeight: CGFloat = 10
    /// 主按钮高度: 大于 44 的最小点按区, 与幽灵行一样是「手指尺寸」。
    private let buttonHeight: CGFloat = 48
    /// 幽灵行的最大宽度: 宽屏上拉满一整行就不像「几条摘句」了。
    private let rowsMaxWidth: CGFloat = 360
    /// 一次呼吸的周期 (秒)。慢, 才像「在等」而不是「在加载」—— 骨架屏的快扫是加载的语言。
    private let breathPeriod: Double = 2.8

    /// - Parameters:
    ///   - title: 一句说明 (「还没有摘抄」)。
    ///   - message: 可选的补充 (「读书时长按一句, 就能摘到这里」)。
    ///   - actionTitle: 主动作的字 (「去读一卷」)。
    ///   - systemImage: 主动作前的图标 (可选)。
    ///   - rows: 幽灵行数, 夹在 3…4。再多就像列表加载失败了。
    ///   - action: 主动作。
    public init(_ title: String, message: String? = nil, actionTitle: String, systemImage: String? = nil,
                rows: Int = 3, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.systemImage = systemImage
        self.rows = min(max(rows, 3), 4)
        self.action = action
    }

    public var body: some View {
        VStack(spacing: theme.space.xl) {
            ghostRows
            VStack(spacing: theme.space.sm) {
                Text(title)
                    .font(theme.type.title3)
                    .foregroundStyle(theme.color.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .font(theme.type.subhead)
                        .foregroundStyle(theme.color.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            Button {
                taps += 1
                action()
            } label: {
                HStack(spacing: theme.space.sm) {
                    if let systemImage { Image(systemName: systemImage) }
                    Text(actionTitle)
                }
                .font(theme.type.headline)
                .foregroundStyle(theme.color.accentOn)
                .padding(.horizontal, theme.space.xl)
                .frame(minHeight: buttonHeight)
                .background(theme.color.accent, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(ZXPressStyle())
            .sensoryFeedback(.impact(weight: .light), trigger: taps)
            .accessibilityIdentifier("zx.ghostState.action")
        }
        .padding(.vertical, theme.space.xxl)
        .padding(.horizontal, theme.space.margin)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var ghostRows: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            VStack(spacing: theme.space.sm) {
                ForEach(0..<rows, id: \.self) { index in
                    ghostRow(index: index)
                        .opacity(reduceMotion ? 0.8 : breath(t: t, index: index))
                }
            }
        }
        .frame(maxWidth: rowsMaxWidth)
        .accessibilityHidden(true)
    }

    /// 呼吸: 0.55…1 之间的正弦, 每行错开四分之一拍, 像一口气从上往下走。
    private func breath(t: Double, index: Int) -> Double {
        let phase = (t / breathPeriod + Double(index) * 0.25) * 2 * .pi
        return 0.775 + 0.225 * sin(phase)
    }

    private func ghostRow(index: Int) -> some View {
        // 行宽错落 (而不是一样长): 一样长的灰条像表格, 错落才像一条条真实的摘句。
        let widths: [CGFloat] = [0.82, 0.64, 0.74, 0.56]
        let ghost = theme.color.fill
        return HStack(spacing: theme.space.md) {
            RoundedRectangle(cornerRadius: theme.radius.sm, style: .continuous)
                .fill(ghost)
                .frame(width: markSize, height: markSize)
            VStack(alignment: .leading, spacing: theme.space.sm) {
                GeometryReader { proxy in
                    Capsule().fill(ghost)
                        .frame(width: proxy.size.width * widths[index % widths.count], height: lineHeight)
                }
                .frame(height: lineHeight)
                GeometryReader { proxy in
                    Capsule().fill(ghost)
                        .frame(width: proxy.size.width * widths[(index + 2) % widths.count] * 0.6, height: lineHeight)
                }
                .frame(height: lineHeight)
            }
        }
        .padding(.horizontal, theme.space.md)
        .frame(height: rowHeight)
        .zxSurface(.e0, in: RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
    }
}

/// 按下时略缩、松手回弹。主按钮与可点的卡片共用。
/// 减少动态时不缩放, 改为按下变淡 —— 仍有按下的反馈, 只是没有位移。
public struct ZXPressStyle: ButtonStyle {
    /// 按下时的缩放比例。
    public var scale: CGFloat
    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(scale: CGFloat = 0.96) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(theme.motion.adapted(configuration.isPressed ? theme.motion.snappy : theme.motion.bouncy,
                                            reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

#if DEBUG
#Preview("幽灵空态") {
    PreviewPage {
        ZXGhostState("还没有摘抄", message: "读书时长按一句, 就能摘到这里", actionTitle: "去读一卷",
                     systemImage: "book") {}
    }
}
#endif
