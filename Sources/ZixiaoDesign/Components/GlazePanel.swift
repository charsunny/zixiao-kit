//  GlazePanel.swift — 釉面面板
//
//  从 PoetKit 移植。内容压在不透明的「纸」上; Liquid Glass 属于导航与控件,
//  不给正文卡用 —— 玻璃后面透出滚动的正文, 17pt 的字就游起来了。

import SwiftUI

/// 面板的釉色。只有两种, 都来自身份: 不再像 PoetKit 那样写死一支汝窑天青,
/// 那是某一个产品的身份色, 进了内核就成了所有产品的颜色。
public enum ZXGlaze: Sendable, Hashable {
    /// 卡面 (身份的 surface 槽)。默认, 承载长文与条目。
    case surface
    /// 淡墨: 纸上染一层 5% 的墨。给「主角卡」用 —— 一屏一处。
    /// 单色墨系的强调本来就是「墨得更实」, 有色相的身份里它也只是纸的另一种调子,
    /// 不会压住正文。
    case wash
}

/// 一块圆角面板。不投影: 靠釉色与纸色的差分层 —— 加阴影立刻就是 iOS 18 的味道。
public struct GlazePanel<Content: View>: View {
    let glaze: ZXGlaze
    let crackled: Bool
    let padding: CGFloat
    let cornerRadius: CGFloat
    let content: Content

    @Environment(\.zxTheme) private var theme

    /// - Parameters:
    ///   - crackled: 开片。只给主角卡开 —— 长正文压在纹上会难读。
    public init(glaze: ZXGlaze = .surface, crackled: Bool = false,
                padding: CGFloat = ZXMetric.panelPadding,
                cornerRadius: CGFloat = ZXMetric.panelRadius,
                @ViewBuilder content: () -> Content) {
        self.glaze = glaze
        self.crackled = crackled
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    switch glaze {
                    case .surface:
                        shape.fill(theme.surface)
                    case .wash:
                        shape.fill(theme.paper())
                        shape.fill(theme.ink(0.05))
                    }
                    if crackled {
                        CrackleGlaze()
                            .stroke(theme.ink(CrackleGlaze.intensity), lineWidth: 0.5)
                            .clipShape(shape)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
    }
}

/// 开片 (釉面龟裂纹)。
///
/// 分寸在这里, 不在实现里: **汝窑无纹者尤佳**。开片是烧造时的意外, 好汝窑的纹细而疏;
/// 金丝铁线那种醒目的大开片是哥窑。画成看得清的裂纹网就是贴图了。
/// 所以默认只有 6% 的墨, 斜着看才看得见。
struct CrackleGlaze: Shape {
    static let intensity: Double = 0.06

    func path(in rect: CGRect) -> Path {
        var p = Path()
        // 确定性随机: 同一块卡每次重绘纹路一样。开片烧出来就定死了, 不该随滚动闪烁。
        var seed: UInt64 = 0x5EA1_C0DE
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFF) / 65535.0
        }
        for _ in 0..<14 {
            var x = rnd() * rect.width
            var y = rnd() * rect.height
            p.move(to: CGPoint(x: x, y: y))
            // 每条纹 2–4 折, 转角不超过 ±60°, 模仿釉面应力开裂的走向
            var angle = rnd() * 2 * .pi
            for _ in 0..<(2 + Int(rnd() * 3)) {
                angle += (rnd() - 0.5) * (.pi / 1.5)
                let len = 18 + rnd() * 46
                x += cos(angle) * len
                y += sin(angle) * len
                p.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return p
    }
}

#if DEBUG
#Preview("釉面") {
    PreviewPage {
        GlazePanel(glaze: .wash, crackled: true) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("今日", trailing: "九月廿八")
                Text("雨过天青云破处").font(ZXFont.serif(22, weight: .bold, relativeTo: .title2))
                Text("主角卡: 淡墨釉, 开片只在斜看时出现。").font(ZXFont.serif(15))
            }
        }
        GlazePanel {
            Text("正文卡: 卡面釉色, 不开片。").font(ZXFont.serif(17))
        }
    }
}
#endif

// 内容可跨并发域传递时, 面板也可以 —— 面板自己只存 Sendable 的值。
extension GlazePanel: Sendable where Content: Sendable {}
