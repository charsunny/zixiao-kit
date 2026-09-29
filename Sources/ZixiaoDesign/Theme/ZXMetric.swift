//  ZXMetric.swift — 尺度
//
//  只放组件自己要用的几个数。页面级的留白、栏宽由各 App 定, 不进内核。

import CoreGraphics

public enum ZXMetric: Sendable {
    /// 面板圆角。PoetKit 对齐 iOS 26 系统卡取 26, Flutter 版的主角卡取 20;
    /// 内核取 20 —— 线装书、印这类方正的东西旁边, 太圆的卡会显得软。要更圆的产品自己传。
    public static let panelRadius: CGFloat = 20
    /// 面板内边距。
    public static let panelPadding: CGFloat = 20
    /// 分隔线的粗细: 半点。在 @3x 屏上是一个半物理像素, 刚好看得见又不抢。
    public static let hairline: CGFloat = 0.5
}
