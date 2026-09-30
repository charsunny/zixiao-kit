//  ZXArtRenderer.swift — Drawing → CGImage (Core Graphics)
//
//  只用 CoreGraphics + Foundation: 可在小组件扩展、后台线程、App Intents 里调用 (无 UIKit /
//  UIApplication / WebKit / JavaScriptCore)。确定性: 同一张 Drawing 在同一设备上渲染结果相同。
//
//  逐像素滤镜 (nonflowers 的 Filter.fade / Filter.wispy) ported from nonflowers main.js,
//  MIT License, (c) 2018 Lingdong Huang. Full license text: ZXArtLicenses.swift / LICENSES/.

import CoreGraphics
import Foundation
import ZixiaoDesign

public extension ZXArt {
    /// 渲染成位图。`size` 是点尺寸, `scale` 是每点像素 (widget @3x 传 3)。画面按
    /// aspect-fill 铺满 (生成时已按同一长宽比构图, 通常正好铺满)。
    static func render(_ drawing: Drawing, size: CGSize, scale: CGFloat) -> CGImage? {
        let pw = max(1, Int((size.width * scale).rounded()))
        let ph = max(1, Int((size.height * scale).rounded()))
        guard let ctx = makeBitmap(width: pw, height: ph) else { return nil }
        // 位图坐标 y 向上; 翻成 y 向下 (与原作 SVG / canvas 一致)。
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: 1, y: -1)
        draw(drawing, in: ctx, rect: CGRect(x: 0, y: 0, width: pw, height: ph), pixelsPerUnit: 1)
        return ctx.makeImage()
    }

    /// 画进一个 y 向下的上下文 (SwiftUI Canvas 的 `withCGContext`、或 `render` 翻转过的位图)。
    /// `rect` 用上下文当前单位; `pixelsPerUnit` 是这些单位对应的设备像素 (滤镜层离屏位图用)。
    static func draw(_ drawing: Drawing, in ctx: CGContext, rect: CGRect, pixelsPerUnit: CGFloat) {
        let s = max(Double(rect.width) / drawing.width, Double(rect.height) / drawing.height)
        let ox = Double(rect.midX) - drawing.width * s / 2
        let oy = Double(rect.midY) - drawing.height * s / 2
        ctx.saveGState()
        ctx.clip(to: rect)
        let bg = drawing.background
        ctx.setFillColor(red: bg.red, green: bg.green, blue: bg.blue, alpha: 1)
        ctx.fill(rect)
        if let paper = drawing.paper, let tile = paperTile(paper, paperColor: bg) {
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(ox), y: CGFloat(oy))
            ctx.scaleBy(x: CGFloat(s * paper.texel), y: CGFloat(s * paper.texel))
            ctx.interpolationQuality = .low
            ctx.draw(tile, in: CGRect(x: 0, y: 0, width: PaperTexture.side, height: PaperTexture.side), byTiling: true)
            ctx.restoreGState()
        }
        for layer in drawing.layers {
            if let filter = layer.filter {
                drawFiltered(layer, filter: filter, in: ctx, rect: rect, s: s, ox: ox, oy: oy, ppu: Double(pixelsPerUnit))
            } else {
                ctx.saveGState()
                ctx.setBlendMode(layer.blend == .multiply ? .multiply : .normal)
                ctx.setAlpha(CGFloat(layer.opacity))
                if layer.opacity < 1 { ctx.beginTransparencyLayer(auxiliaryInfo: nil) }
                ctx.translateBy(x: CGFloat(ox), y: CGFloat(oy))
                ctx.scaleBy(x: CGFloat(s), y: CGFloat(s))
                drawShapes(layer.shapes, in: ctx)
                if layer.opacity < 1 { ctx.endTransparencyLayer() }
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
    }

    // MARK: - 内部

    internal static func makeBitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    }

    /// 形状按 SVG / canvas 语义: 先填 (非零环绕, 隐式闭合) 后描 (不闭合, 斜接, 平头)。
    internal static func drawShapes(_ shapes: [Shape], in ctx: CGContext) {
        ctx.setLineJoin(.miter)
        ctx.setLineCap(.butt)
        var buf: [CGPoint] = []
        for sh in shapes {
            guard sh.points.count >= 2 else { continue }
            buf.removeAll(keepingCapacity: true)
            for p in sh.points { buf.append(CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))) }
            let stroke = sh.lineWidth > 0 ? sh.stroke : nil
            if let f = sh.fill {
                ctx.setFillColor(red: f.red, green: f.green, blue: f.blue, alpha: f.alpha)
                ctx.addLines(between: buf)
                if sh.closed { ctx.closePath() }
                if let st = stroke {
                    // SVG 先填后描; fillStroke 同顺序, 但填充会隐式闭合而描边不会 —— 分两次画。
                    ctx.fillPath()
                    ctx.setStrokeColor(red: st.red, green: st.green, blue: st.blue, alpha: st.alpha)
                    ctx.setLineWidth(CGFloat(sh.lineWidth))
                    ctx.addLines(between: buf)
                    if sh.closed { ctx.closePath() }
                    ctx.strokePath()
                } else {
                    ctx.fillPath()
                }
            } else if let st = stroke {
                ctx.setStrokeColor(red: st.red, green: st.green, blue: st.blue, alpha: st.alpha)
                ctx.setLineWidth(CGFloat(sh.lineWidth))
                ctx.addLines(between: buf)
                if sh.closed { ctx.closePath() }
                ctx.strokePath()
            }
        }
    }

    /// 512² 纸纹图块: 纸色往 tint 偏 shade/255·strength。
    internal static func paperTile(_ paper: PaperTexture, paperColor: ZXHex) -> CGImage? {
        let side = PaperTexture.side
        guard paper.shade.count == side * side else { return nil }
        var px = [UInt8](repeating: 0, count: side * side * 4)
        let tint = paper.tint
        let pr = paperColor.red * 255, pg = paperColor.green * 255, pb = paperColor.blue * 255
        let tr = tint.red * 255, tg = tint.green * 255, tb = tint.blue * 255
        for i in 0..<(side * side) {
            let t = min(1, Double(paper.shade[i]) / 255 * paper.strength)
            px[i * 4] = UInt8((pr + (tr - pr) * t).rounded())
            px[i * 4 + 1] = UInt8((pg + (tg - pg) * t).rounded())
            px[i * 4 + 2] = UInt8((pb + (tb - pb) * t).rounded())
            px[i * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// 滤镜层: 离屏画 → 逐像素 (只处理不透明像素, 只在形状包围盒内) → 按混合模式贴回。
    private static func drawFiltered(_ layer: Layer, filter: LayerFilter, in ctx: CGContext, rect: CGRect,
                                     s: Double, ox: Double, oy: Double, ppu: Double) {
        // 形状包围盒 (上下文单位)
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for sh in layer.shapes {
            for p in sh.points {
                let x = Double(p.x), y = Double(p.y)
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard minX.isFinite else { return }
        let pad = 4.0
        var box = CGRect(x: minX * s + ox - pad, y: minY * s + oy - pad,
                         width: (maxX - minX) * s + 2 * pad, height: (maxY - minY) * s + 2 * pad)
        box = box.intersection(rect)
        guard !box.isNull, box.width >= 1, box.height >= 1 else { return }
        let bw = Int((Double(box.width) * ppu).rounded(.up)), bh = Int((Double(box.height) * ppu).rounded(.up))
        guard let off = makeBitmap(width: bw, height: bh) else { return }
        // 离屏: y 向下, 原点 = box 左上角, 单位 = 设备像素。
        off.translateBy(x: 0, y: CGFloat(bh))
        off.scaleBy(x: 1, y: -1)
        off.scaleBy(x: CGFloat(ppu), y: CGFloat(ppu))
        off.translateBy(x: -box.minX, y: -box.minY)
        off.saveGState()
        off.translateBy(x: CGFloat(ox), y: CGFloat(oy))
        off.scaleBy(x: CGFloat(s), y: CGFloat(s))
        drawShapes(layer.shapes, in: off)
        off.restoreGState()

        if let data = off.data {
            let pix = data.bindMemory(to: UInt8.self, capacity: bw * bh * 4)
            filter.perlin.withUnsafeBufferPointer { perlinBuf in
                guard let table = perlinBuf.baseAddress, perlinBuf.count >= 4096 else { return }
                let doFade = filter.passes.contains(.fade)
                let doWispy = filter.passes.contains(.wispy)
                // 像素 (px, py) → 上下文单位 → 画布单位 → 原作图层像素坐标
                let ax = 1 / (ppu * s) * filter.scale
                let bx = (Double(box.minX) - ox) / s * filter.scale + filter.offsetX
                let by = (Double(box.minY) - oy) / s * filter.scale + filter.offsetY
                for py in 0..<bh {
                    let ly = Double(py) * ax + by
                    let row = pix + py * bw * 4
                    for pxi in 0..<bw {
                        let q = row + pxi * 4
                        let A = q[3]
                        if A == 0 { continue }
                        let lx = Double(pxi) * ax + bx
                        let af = Double(A)
                        // getImageData: 反预乘成 0…255 的整数
                        var r = (Double(q[0]) * 255 / af).rounded()
                        var g = (Double(q[1]) * 255 / af).rounded()
                        var b = (Double(q[2]) * 255 / af).rounded()
                        var a = af
                        if doFade {
                            let nz = ZXArt.perlin(table, lx * 0.01, ly * 0.01, 0)
                            a = a * min(max(nz, 0), 1)
                            a = clampedByte(a)
                        }
                        if doWispy {
                            let nz = ZXArt.perlin(table, lx * 0.2, ly * 0.2, 0)
                            let m = ZXArt.perlin(table, lx * 0.5, ly * 0.5, 2)
                            g = g * (0.95 + 0.05 * m)
                            b = b * (0.9 + 0.1 * m)
                            a = a * (0.5 + 0.5 * nz)
                        }
                        r = clampedByte(r); g = clampedByte(g); b = clampedByte(b); a = clampedByte(a)
                        // putImageData → 重新预乘
                        q[3] = UInt8(a)
                        q[0] = UInt8((r * a / 255).rounded())
                        q[1] = UInt8((g * a / 255).rounded())
                        q[2] = UInt8((b * a / 255).rounded())
                    }
                }
            }
        }
        guard let img = off.makeImage() else { return }
        ctx.saveGState()
        ctx.setBlendMode(layer.blend == .multiply ? .multiply : .normal)
        ctx.setAlpha(CGFloat(layer.opacity))
        // 目标是 y 向下的上下文: 先翻回 y 向上再贴图, 否则图会倒过来。
        ctx.translateBy(x: box.minX, y: box.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: box.width, height: box.height))
        ctx.restoreGState()
    }

    /// Uint8ClampedArray 的写入: 夹到 0…255, 四舍六入五成双。
    @inline(__always)
    private static func clampedByte(_ v: Double) -> Double {
        if !(v > 0) { return 0 }
        if v >= 255 { return 255 }
        return v.rounded(.toNearestOrEven)
    }
}
