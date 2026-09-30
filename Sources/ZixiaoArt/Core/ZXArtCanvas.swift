//  ZXArtCanvas.swift — 在 SwiftUI 里直接画一张 `ZXArt.Drawing`
//
//  用 `Canvas` + `withCGContext` 调同一个 Core Graphics 绘制过程, 与 `ZXArt.render` 出图一致。
//  适合 App 内实时预览; 小组件请用 `ZXArt.render` 预渲染的 CGImage (小组件的 Canvas 每次
//  刷新都会重画, 花卉的滤镜层很贵)。

import SwiftUI
import ZixiaoDesign

public struct ZXArtCanvas: View {
    private let drawing: ZXArt.Drawing
    @Environment(\.displayScale) private var displayScale

    public init(_ drawing: ZXArt.Drawing) {
        self.drawing = drawing
    }

    public var body: some View {
        Canvas(opaque: true, rendersAsynchronously: true) { context, size in
            let scale = displayScale
            context.withCGContext { cg in
                ZXArt.draw(drawing, in: cg, rect: CGRect(origin: .zero, size: size), pixelsPerUnit: scale)
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("山水 · 纸墨") {
    ZXArtCanvas(ZXArt.ShanShui.generate(seed: 42, size: CGSize(width: 402, height: 874)))
        .ignoresSafeArea()
}

#Preview("花 · 夜色") {
    ZXArtCanvas(ZXArt.Flowers.generate(seed: 42, size: CGSize(width: 338, height: 158),
                                       params: .init(palette: .night)))
        .frame(width: 338, height: 158)
}
#endif
