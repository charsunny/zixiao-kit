//  ZXHairline.swift — 发丝线
//
//  设计系统契约里的分隔线。不用 `Divider()`: 系统分隔色与身份无关, 而且 Divider 在
//  HStack / VStack 里会自己决定方向, 放进 ZStack 或 overlay 时方向不可控。
//  与 `InkDivider(style: .hairline)` 画法相同; 新代码用这个名字, 对齐契约。

import SwiftUI

public struct ZXHairline: View, Sendable {
    let axis: Axis

    @Environment(\.zxTheme) private var theme
    @Environment(\.displayScale) private var displayScale

    public init(axis: Axis = .horizontal) {
        self.axis = axis
    }

    public var body: some View {
        // 至少一个物理像素: 半点在 @2x 屏上正好一像素, 在 @3x 屏上是一个半, 都看得见。
        let thickness = max(ZXMetric.hairline, 1 / displayScale)
        Rectangle()
            .fill(theme.color.separator)
            .frame(width: axis == .vertical ? thickness : nil,
                   height: axis == .horizontal ? thickness : nil)
            .frame(maxWidth: axis == .horizontal ? .infinity : nil,
                   maxHeight: axis == .vertical ? .infinity : nil)
            .accessibilityHidden(true)
    }
}
