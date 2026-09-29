//  ZXTypeTokens.swift — 字号阶
//
//  与设计系统契约同一套阶梯 (display 34 … caption 12), 差异是有意的:
//  契约里正文留给系统无衬线, 这里正文按身份走 —— 单色墨系的正文也是宋体。
//  footnote / caption 属于操作层, 走身份的 ui 字族。
//  古籍、诗词压在苹方上就成了资讯 App, 字是这套产品身份的一半。
//
//  所有字号都经 `relativeTo:` 跟随 Dynamic Type; 阶梯外的尺寸用 `display(_:relativeTo:)`
//  或 `numeral(_:relativeTo:)`, 不要在视图里写 `.system(size:)`。

import SwiftUI

/// 字号阶里的一级。纯数据, 测试与布局计算可以直接读尺寸。
public enum ZXTypeRole: String, CaseIterable, Sendable, Hashable {
    case display, title1, title2, title3, headline, body, callout, subhead, footnote, caption

    /// 基准字号 (Dynamic Type 默认档下的 pt)。
    public var size: CGFloat {
        switch self {
        case .display: 34
        case .title1: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subhead: 15
        case .footnote: 13
        case .caption: 12
        }
    }

    /// 跟随哪个系统文字样式缩放。
    public var textStyle: Font.TextStyle {
        switch self {
        case .display: .largeTitle
        case .title1: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subhead: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        }
    }

    /// display 与三级标题用身份的展示字族 (思源宋粗); footnote / caption 用 ui 字族 (见 `usesUIFace`);
    /// 其余用正文字族。
    public var usesDisplayFace: Bool {
        switch self {
        case .display, .title1, .title2, .title3: true
        default: false
        }
    }

    /// footnote 与 caption 用身份的操作层 (ui) 字族: 它们是元信息、按钮旁的小字、时间戳,
    /// 属于「操作层」而不是「正文」。有的身份 (如 ui = system) 在小字号上换无衬线, 12pt 的
    /// 宋体细笔画在低倍屏上会断; 单色墨系的 ui 仍是宋体, 所以那边看不出变化。
    public var usesUIFace: Bool {
        switch self {
        case .footnote, .caption: true
        default: false
        }
    }

    /// 默认字重。headline 是正文字族里唯一加粗的一级 —— 它是列表行的主字,
    /// 要在同字号的 body 旁边立得住。随包宋体只有常规 / 粗两档, semibold 会落到粗。
    public var weight: Font.Weight {
        self == .headline ? .semibold : .regular
    }

    /// 字距 (em)。宋体标题略放开: 汉字方块紧挨着排, 大字号下会显得挤;
    /// 小字 (footnote / caption) 也略放, 否则笔画糊在一起。正文保持 0, 让字体自己的字面说话。
    public var trackingEm: CGFloat {
        switch self {
        case .display: 0.04
        case .title1, .title2, .title3: 0.02
        case .footnote, .caption: 0.02
        default: 0
        }
    }
}

/// 字 token。经 `theme.type` 取用: `.font(theme.type.title2)`。
/// 字重在调用处变: `theme.type.subhead.weight(.medium)` (宋体只有常规 / 粗两档)。
public struct ZXTypeTokens: Sendable, Hashable {
    public let displayFace: ZXFace
    public let bodyFace: ZXFace
    public let uiFace: ZXFace
    /// 系统「粗体文本」开关。自定义字体不会自己响应, 由主题解析时传进来。
    public let legibilityWeight: LegibilityWeight?

    /// - Parameter uiFace: 操作层字族; 不给则与正文同族。
    public init(displayFace: ZXFace, bodyFace: ZXFace, uiFace: ZXFace? = nil,
                legibilityWeight: LegibilityWeight? = nil) {
        self.displayFace = displayFace
        self.bodyFace = bodyFace
        self.uiFace = uiFace ?? bodyFace
        self.legibilityWeight = legibilityWeight
    }

    /// 某一级用哪个字面。
    public func face(for role: ZXTypeRole) -> ZXFace {
        if role.usesDisplayFace { return displayFace }
        if role.usesUIFace { return uiFace }
        return bodyFace
    }

    /// 某一级的字。
    public func font(_ role: ZXTypeRole) -> Font {
        let face = face(for: role)
        return face.font(role.size, weight: role.weight, relativeTo: role.textStyle,
                         legibilityWeight: legibilityWeight)
    }

    public var display: Font { font(.display) }
    public var title1: Font { font(.title1) }
    public var title2: Font { font(.title2) }
    public var title3: Font { font(.title3) }
    public var headline: Font { font(.headline) }
    public var body: Font { font(.body) }
    public var callout: Font { font(.callout) }
    public var subhead: Font { font(.subhead) }
    public var footnote: Font { font(.footnote) }
    public var caption: Font { font(.caption) }

    /// 阶梯外的展示字 (题字、封面大字)。仍跟随 Dynamic Type。
    public func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        displayFace.font(size, weight: .bold, relativeTo: style, legibilityWeight: legibilityWeight)
    }

    /// 数字 (计数、倒计时、统计)。展示字族 + 等宽数字: 数字跳动时不左右晃。
    public func numeral(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        displayFace.font(size, weight: .bold, relativeTo: style, legibilityWeight: legibilityWeight)
            .monospacedDigit()
    }

    /// 某一级的字距 (pt), 用于 `.tracking(_:)`。按基准字号算: Dynamic Type 放大时
    /// 字距略偏紧, 这是有意的 —— 大字号下更需要紧凑, 不需要再放开。
    public func tracking(for role: ZXTypeRole) -> CGFloat {
        role.size * role.trackingEm
    }
}
