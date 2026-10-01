//  BookCoverView.swift — 代码生成的线装书封面
//
//  纯代码画, 没有图片资源: 书库里几百本书不可能一本本去找封面, 而线装书的封面
//  本来就近乎素面 —— 一张书衣、一条题签、一道订线, 就是全部。
//
//  与 Flutter 版 `book_cover.dart` 的有意不同: Flutter 版把部类签条放在左边、题签居中;
//  这里按真线装书来 —— 书从右往左翻, 订口在**右侧** (四眼订: 四个线孔, 线从孔里绕过书脊),
//  题签贴在**左上**。部类色改画成书脊两端的「包角」(真书上是包在订口两角的绫绢)。
//
//  书衣 (`Cloth`) 可由调用方染色 (如 App 按部类给的矿物色纸): 题签仍是纸色、题字仍是墨,
//  只有压在书衣上的署名、订线、线孔描边改用书衣自带的那支墨 —— 内核不替调用方挑颜色,
//  只负责「深浅外观各取一支」。

import SwiftUI

public struct BookCoverView: View, Sendable {
    /// 封面的三档尺寸, 都是 3:4, 与 Flutter 版一致。
    public enum Size: Sendable, Hashable {
        /// 书架上的一本。
        case shelf
        /// 「正在阅读」大卡里的那本。
        case reading
        /// 书目页顶部的大封面。
        case page
        /// 自定宽度。
        case width(CGFloat)

        public var width: CGFloat {
            switch self {
            case .shelf: return 108
            case .reading: return 132
            case .page: return 156
            case .width(let w): return w
            }
        }
        public var height: CGFloat { width * 4 / 3 }
    }

    /// 书衣的颜色, 浅深外观各一组。`nil` (默认) 是素面: 书衣取 `theme.surface`, 与加这个参数之前一致。
    public struct Cloth: Sendable, Hashable {
        /// 一种外观下的书衣。
        public struct Shade: Sendable, Hashable {
            /// 书衣底色 (不透明)。
            public let fill: Color
            /// 压在书衣上的墨: 署名小字用全色, 订线与线孔描边用它的淡色。
            /// 它与 `fill` 的对比度由调用方保证 (署名是正文级小字, 要 ≥ 4.5:1)。
            public let ink: Color

            public init(fill: Color, ink: Color) {
                self.fill = fill
                self.ink = ink
            }
        }

        public let light: Shade
        public let dark: Shade

        public init(light: Shade, dark: Shade) {
            self.light = light
            self.dark = dark
        }

        /// 按外观取一组。
        public func shade(isDark: Bool) -> Shade { isDark ? dark : light }
    }

    let title: String
    let byline: String
    let size: Size
    let cornerTint: Color?
    let cloth: Cloth?
    let isRemote: Bool

    @Environment(\.zxTheme) private var theme

    /// - Parameters:
    ///   - title: 书名, 竖排在题签里; 长名自动折成两列, 不截字。
    ///   - author: 作者 / 朝代等署名 (如「春秋 · 孔子弟子」), 横排在封面底部。
    ///   - cornerTint: 包角颜色 (如部类色)。内核不知道「经史子集」各配什么色, 由调用方给;
    ///     nil 不画包角。
    ///   - cloth: 书衣颜色 (如部类色); nil 是素面 (`theme.surface`)。题签不随它变。
    ///   - isRemote: 云端的书、还没下到本机: 右下角一枚半透明的下载记号。
    public init(title: String, author: String? = nil, size: Size = .shelf,
                cornerTint: Color? = nil, cloth: Cloth? = nil, isRemote: Bool = false) {
        self.title = title
        self.byline = author ?? ""
        self.size = size
        self.cornerTint = cornerTint
        self.cloth = cloth
        self.isRemote = isRemote
    }

    public var body: some View {
        let w = size.width
        let h = size.height
        let bindX = w * 0.9             // 订线距左边的位置 (右侧 10% 是订口)
        let glyph = (w * 0.13).rounded()
        let small = (w * 0.085).rounded()
        let footer = byline.isEmpty ? 0 : small * 1.3 + 8
        let slipTop = w * 0.09
        let slipPad = w * 0.045
        let slipMaxHeight = h - slipTop - footer - w * 0.12
        let shade = cloth?.shade(isDark: theme.isDark)

        ZStack(alignment: .topLeading) {
            // 书衣
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(shade?.fill ?? theme.surface)

            // 包角
            if let cornerTint {
                let cornerH = w * 0.1
                VStack(spacing: 0) {
                    Rectangle().fill(cornerTint).frame(height: cornerH)
                    Spacer(minLength: 0)
                    Rectangle().fill(cornerTint).frame(height: cornerH)
                }
                .frame(width: w - bindX + w * 0.02, height: h)
                .offset(x: bindX - w * 0.02)
            }

            // 订线与线孔
            BindingThread(bindX: bindX)
                .stroke(shade?.ink.opacity(0.4) ?? theme.ink(0.28), lineWidth: max(0.6, w * 0.006))
            BindingHoles(bindX: bindX, diameter: max(2, w * 0.03))
                .fill(theme.paper())
            BindingHoles(bindX: bindX, diameter: max(2, w * 0.03))
                .stroke(shade?.ink.opacity(0.5) ?? theme.ink(0.35), lineWidth: 0.5)

            // 题签: 左上。双线框 —— 外框是签纸的边, 内框一道极淡的墨线, 刻本题签的常见样子。
            VerticalText(title,
                         font: theme.displayFont(glyph, relativeTo: nil),
                         color: theme.ink(),
                         charSpacing: 1,
                         columnSpacing: glyph * 0.3)
                .frame(maxHeight: slipMaxHeight - slipPad * 2, alignment: .top)
                .padding(slipPad)
                .background {
                    Rectangle().fill(theme.paper())
                        .overlay { Rectangle().strokeBorder(theme.ink(0.14), lineWidth: 0.5).padding(2) }
                        .overlay { Rectangle().strokeBorder(theme.border, lineWidth: 0.5) }
                }
                .offset(x: w * 0.11, y: slipTop)

            // 署名
            if !byline.isEmpty {
                Text(byline)
                    .font(theme.bodyFont(small, relativeTo: nil))
                    .foregroundStyle(shade?.ink ?? theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: bindX - 12)
                    .offset(x: 6, y: h - footer + 2)
            }

            if isRemote {
                let d = w * 0.17
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: w * 0.09, weight: .medium))
                    .foregroundStyle(theme.muted)
                    .frame(width: d, height: d)
                    .background(theme.paper(0.72), in: Circle())
                    .overlay(Circle().strokeBorder(theme.border, lineWidth: 0.5))
                    .offset(x: bindX - d - 6, y: h - footer - d - 4)
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 0.5)
        }
        // 深色底上阴影看不见, 画了只会让边缘发脏; 深色靠 surface 比纸亮一级来分层。
        .shadow(color: theme.isDark ? .clear : theme.ink(0.08), radius: 4, x: 0, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(byline.isEmpty ? title : "\(title)，\(byline)")
        .accessibilityHint(isRemote ? "尚未下载" : "")
    }
}

/// 四眼订的线孔纵向位置 (占封面高度的比例)。上下两孔靠近书头书脚, 中间两孔三等分。
private let holeRatios: [CGFloat] = [0.1, 0.37, 0.63, 0.9]

/// 订线: 沿订口的一道竖线, 加上每个孔向右绕过书脊的一段横线。
private struct BindingThread: Shape {
    let bindX: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: bindX, y: 0))
        p.addLine(to: CGPoint(x: bindX, y: rect.height))
        for r in holeRatios {
            let y = rect.height * r
            p.move(to: CGPoint(x: bindX, y: y))
            p.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return p
    }
}

private struct BindingHoles: Shape {
    let bindX: CGFloat
    let diameter: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for r in holeRatios {
            p.addEllipse(in: CGRect(x: bindX - diameter / 2, y: rect.height * r - diameter / 2,
                                    width: diameter, height: diameter))
        }
        return p
    }
}

#if DEBUG
#Preview("线装封面") {
    PreviewPage {
        HStack(alignment: .top, spacing: 16) {
            BookCoverView(title: "论语", author: "春秋 · 孔子弟子")
            BookCoverView(title: "般若波罗蜜多心经", author: "唐 · 玄奘译", size: .reading, isRemote: true)
            PreviewTinted { tint in
                BookCoverView(title: "道德经", author: "老子", size: .page, cornerTint: tint)
            }
        }
    }
}

/// 包角色从身份里取 (预览里借印泥色), 内核预览也不写死颜色。
private struct PreviewTinted<Content: View>: View {
    @Environment(\.zxTheme) private var theme
    @ViewBuilder let content: (Color) -> Content
    var body: some View { content(theme.seal) }
}
#endif
