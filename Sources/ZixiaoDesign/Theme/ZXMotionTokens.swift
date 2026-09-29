//  ZXMotionTokens.swift — 动效
//
//  五种手感, 按「这次变化有多重」挑, 不按「想要多炫」挑:
//  snappy 是控件的应答, smooth 是内容的切换, bouncy 是落定的一下, standard 是没有情绪的
//  淡入淡出, hero 是整页级的转场。任何一处都要经 `adapted(_:reduceMotion:)`。

import SwiftUI

/// 动效 token。经 `theme.motion` 取用:
/// `withAnimation(theme.motion.adapted(theme.motion.snappy, reduceMotion: reduceMotion)) { … }`
public struct ZXMotionTokens: Sendable, Equatable {
    /// 控件应答: 开关、选中、按压回弹。
    public let snappy: Animation
    /// 内容切换: 展开收起、换页、列表增删。
    public let smooth: Animation
    /// 落定: 数字落格、卡片归位。只给「一次」的动作用, 不给持续的动作。
    public let bouncy: Animation
    /// 无情绪的淡入淡出。
    public let standard: Animation
    /// 整页级转场。
    public let hero: Animation
    /// 减少动态时的替身: 短、无弹、只剩渐变。
    public let reduced: Animation

    public init(snappy: Animation = .snappy(duration: 0.3),
                smooth: Animation = .smooth(duration: 0.35),
                bouncy: Animation = .spring(duration: 0.45, bounce: 0.3),
                standard: Animation = .easeInOut(duration: 0.25),
                hero: Animation = .spring(duration: 0.55, bounce: 0.12),
                reduced: Animation = .easeInOut(duration: 0.15)) {
        self.snappy = snappy
        self.smooth = smooth
        self.bouncy = bouncy
        self.standard = standard
        self.hero = hero
        self.reduced = reduced
    }

    public static let defaults = ZXMotionTokens()

    /// 按「减少动态」改写一支动效。
    ///
    /// 为什么不直接返回 nil (不动): 状态变化本身仍要被看见 —— 瞬切会让人以为没点上。
    /// 减少动态要去掉的是位移与回弹带来的眩晕, 不是反馈; 所以换成 0.15 秒的无弹渐变。
    public func adapted(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }
}
