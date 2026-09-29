//  SealView.swift — 方印
//
//  印是一件物, 不是一个标签: 方块、微微歪一点、印泥色只取身份的 seal 槽。
//  朱砂在一屏里应当是最稀有的颜色 (PoetKit 的 SealDot、Flutter 的 QzSeal 都守这一条),
//  所以这里不提供「换个颜色」的参数 —— 要别的颜色, 换身份。

import SwiftUI

public struct SealView: View, Sendable {
    /// 印的两种刻法。
    public enum Style: Sendable, Hashable {
        /// 朱文 (阳刻): 字是朱色, 底是纸。
        case zhuwen
        /// 白文 (阴刻): 底是朱色, 字是纸。
        case baiwen
    }

    let characters: [Character]
    let style: Style
    let size: CGFloat
    let stamped: Bool
    let tilted: Bool

    @Environment(\.zxTheme) private var theme

    /// - Parameters:
    ///   - text: 印文, 1–4 字。超过 4 字只取前 4 —— 更长的印文在这个尺寸上已认不出, 不如截断。
    ///   - style: 朱文 / 白文。
    ///   - size: 印面边长。
    ///   - stamped: false 表示「还没盖上」, 只留一圈淡边与淡字 (打卡、收集类场景)。
    ///   - tilted: 真盖的印很少是正的; 默认歪约 2.6°, 与 Flutter 版一致。
    public init(_ text: String, style: Style = .baiwen, size: CGFloat = 44,
                stamped: Bool = true, tilted: Bool = true) {
        self.characters = Array(text.filter { !$0.isWhitespace }.prefix(4))
        self.style = style
        self.size = size
        self.stamped = stamped
        self.tilted = tilted
    }

    private var inkColor: Color { stamped ? theme.seal : theme.seal.opacity(0.5) }
    private var textColor: Color {
        guard stamped else { return theme.seal.opacity(0.55) }
        return style == .baiwen ? theme.paper() : theme.seal
    }
    private var fillColor: Color {
        stamped && style == .baiwen ? theme.seal : .clear
    }

    public var body: some View {
        let border = size * (style == .zhuwen ? 0.075 : 0.05)
        let inner = size - border * 2 - size * 0.08
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .fill(fillColor)
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .strokeBorder(style == .baiwen && stamped ? theme.paper(0.6) : inkColor,
                              lineWidth: style == .baiwen && stamped ? border * 0.6 : border)
                .padding(style == .baiwen && stamped ? border : 0)
            SealGrid(characters: characters, side: inner, useKai: useKai, color: textColor)
        }
        .frame(width: size, height: size)
        .rotationEffect(.radians(tilted ? -0.045 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(characters))
    }

    /// 印用楷; 但随包楷体是子集, 印文里只要有一个字不在子集里就整方印改用粗宋 ——
    /// 一方印里混两种字体比整方印换字体难看得多。
    private var useKai: Bool {
        ZXFonts.covers(String(characters), fontNamed: ZXFonts.kaiName)
    }
}

/// 印面排字。汉印的章法: 从右往左、从上往下读。
/// - 1 字: 居中。
/// - 2 字: 左右并列, 右起; 每字压扁横向、拉长纵向, 占满方阵的半边。
/// - 3 字: 右一列一字 (拉长), 左一列两字。
/// - 4 字: 田字方阵, 右列上下两字, 左列上下两字。
private struct SealGrid: View {
    let characters: [Character]
    let side: CGFloat
    let useKai: Bool
    let color: Color

    var body: some View {
        switch characters.count {
        case 0:
            EmptyView()
        case 1:
            glyph(characters[0], width: side, height: side)
        case 2:
            HStack(spacing: 0) {
                glyph(characters[1], width: side / 2, height: side)
                glyph(characters[0], width: side / 2, height: side)
            }
        case 3:
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    glyph(characters[1], width: side / 2, height: side / 2)
                    glyph(characters[2], width: side / 2, height: side / 2)
                }
                glyph(characters[0], width: side / 2, height: side)
            }
        default:
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    glyph(characters[2], width: side / 2, height: side / 2)
                    glyph(characters[3], width: side / 2, height: side / 2)
                }
                VStack(spacing: 0) {
                    glyph(characters[0], width: side / 2, height: side / 2)
                    glyph(characters[1], width: side / 2, height: side / 2)
                }
            }
        }
    }

    /// 字按格子的宽定字号, 再按高宽比纵向拉伸 —— 印文的字形随格子变形, 正是篆刻的做法。
    private func glyph(_ ch: Character, width: CGFloat, height: CGFloat) -> some View {
        // 拉长的格子 (2 字、3 字印的长字) 字号略放: 楷体字面在字身里本就偏小, 压扁后更显瘦。
        let fontSize = width * (height > width ? 1.05 : 0.92)
        return Text(String(ch))
            .font(useKai ? ZXFont.kai(fontSize, relativeTo: nil)
                       : ZXFont.serif(fontSize, weight: .bold, relativeTo: nil))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .scaleEffect(x: 1, y: min(height / width, 1.8), anchor: .center)
            .frame(width: width, height: height)
    }
}

#if DEBUG
#Preview("方印") {
    PreviewPage {
        HStack(spacing: 20) {
            SealView("玄")
            SealView("子曰")
            SealView("子曰", style: .zhuwen)
            SealView("长乐未央", size: 64)
            SealView("长乐未央", style: .zhuwen, size: 64)
        }
        HStack(spacing: 20) {
            SealView("三字印", size: 56)
            SealView("未", stamped: false)
            SealView("书斋", size: 28)
        }
    }
}
#endif
