//  ZXArtRenderer.swift — Drawing → CGImage (Core Graphics)
//
//  只用 CoreGraphics + Foundation: 可在小组件扩展、后台线程、App Intents 里调用 (无 UIKit /
//  UIApplication / WebKit / JavaScriptCore)。
//
//  确定性: 同一张 Drawing、同一像素尺寸 → 同一份像素 (同一设备 / 系统版本上逐字节相同)。
//  位图按固定条数的横带并行渲染 (条数只由像素高度决定, 与 CPU 核数无关), 每条带是共享缓冲区上的
//  一个子 CGContext; 形状的覆盖率按像素独立计算, 带与带之间没有接缝。
//
//  批量: 相邻且样式完全相同 (填色 / 描色 / 线宽) 的形状并成一条路径, 一次 fillStroke。重叠处按
//  非零环绕取并集, 不再重复叠透明度 —— 只影响栅格, 不影响几何 (对拍在几何层做)。
//
//  逐像素滤镜 (nonflowers 的 Filter.fade / Filter.wispy) ported from nonflowers main.js,
//  MIT License, (c) 2018 Lingdong Huang. Full license text: ZXArtLicenses.swift / LICENSES/.

import CoreGraphics
import Foundation
import ZixiaoColor

public extension ZXArt {
    /// 渲染成位图。`size` 是点尺寸, `scale` 是每点像素 (widget @3x 传 3)。画面按
    /// aspect-fill 铺满 (生成时已按同一长宽比构图, 通常正好铺满)。
    static func render(_ drawing: Drawing, size: CGSize, scale: CGFloat) -> CGImage? {
        render(drawing, pixelWidth: Int((size.width * scale).rounded()), pixelHeight: Int((size.height * scale).rounded()))
    }

    /// 渲染成 `pixelWidth × pixelHeight` 的 sRGB 位图 (RGBA8, 预乘, 不透明)。
    /// 线程安全: 只读 `drawing`, 可在任意线程并发调用 (矢量栅格化经 `cgLock` 串行, 逐像素的纸纹 /
    /// 滤镜 / 雾化并行)。峰值内存约 `2 × w × h × 4` 字节 (成图 + 滤镜层离屏)。
    static func render(_ drawing: Drawing, pixelWidth: Int, pixelHeight: Int) -> CGImage? {
        let pw = max(1, pixelWidth), ph = max(1, pixelHeight)
        guard let full = makeBitmap(width: pw, height: ph), let base = full.data else { return nil }
        let bpr = full.bytesPerRow
        let prepared = Prepared(drawing)
        // 纸与纸纹直接写像素 (最近邻取纹素, 按整张图的坐标取模), 按行并行。
        let ground = PaperGround(drawing, pixelWidth: pw, pixelHeight: ph)
        let buffer = SendableBuffer(pointer: base)
        parallelRows(ph) { rows in ground.fill(buffer.pointer, bytesPerRow: bpr, rows: rows) }
        // 位图坐标 y 向上; 翻成 y 向下 (与原作 SVG / canvas 一致)。
        full.translateBy(x: 0, y: CGFloat(ph))
        full.scaleBy(x: 1, y: -1)
        let rect = CGRect(x: 0, y: 0, width: pw, height: ph)
        draw(prepared, in: full, rect: rect, visible: rect, pixelsPerUnit: 1, ground: false)
        return full.makeImage()
    }
}

extension ZXArt {
    /// CoreGraphics 的矢量栅格化在多个线程同时进行时 (即使是互不相干的上下文) 会偶发地出不同的
    /// 抗锯齿结果 (iOS 27 模拟器实测: 同一张图并发渲染, 少数形状边缘差几十级)。ZXArt 的所有矢量绘制
    /// 都经过这把锁串行, 保证同输入逐字节同输出; 逐像素的部分不持锁、并行。
    static let cgLock = NSLock()

    @inline(__always)
    static func withCG<T>(_ body: () -> T) -> T {
        cgLock.lock()
        defer { cgLock.unlock() }
        return body()
    }

    /// 把 0..<height 行切成固定块数并行处理 (块的切法只由高度决定; 各行互不依赖, 结果与切法无关)。
    static func parallelRows(_ height: Int, _ body: (Range<Int>) -> Void) {
        let chunks = min(8, max(1, height / 128))
        if chunks == 1 { body(0..<height); return }
        DispatchQueue.concurrentPerform(iterations: chunks) { c in
            body((height * c / chunks)..<(height * (c + 1) / chunks))
        }
    }

    /// 底色 + 纸纹的逐像素填充。纹素 (i, j) 覆盖逻辑坐标 [i·texel, (i+1)·texel), 512 一周期。
    struct PaperGround: Sendable {
        let tile: [UInt8]?   // 512² × RGBA, 不透明
        let bg: (UInt8, UInt8, UInt8)
        let width: Int
        let ox: Double, oy: Double, texelPx: Double

        init(_ d: Drawing, pixelWidth pw: Int, pixelHeight ph: Int) {
            func byte(_ v: Double) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
            bg = (byte(d.background.red), byte(d.background.green), byte(d.background.blue))
            width = pw
            let s = max(Double(pw) / d.width, Double(ph) / d.height)
            ox = Double(pw) / 2 - d.width * s / 2
            oy = Double(ph) / 2 - d.height * s / 2
            texelPx = s * (d.paper?.texel ?? 1)
            tile = d.paper.flatMap { ZXArt.paperTileBytes($0, paperColor: d.background) }
        }

        func fill(_ base: UnsafeMutableRawPointer, bytesPerRow: Int, rows: Range<Int>) {
            let side = PaperTexture.side
            for y in rows {
                let row = (base + y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                guard let tile else {
                    for x in 0..<width { row[x * 4] = bg.0; row[x * 4 + 1] = bg.1; row[x * 4 + 2] = bg.2; row[x * 4 + 3] = 255 }
                    continue
                }
                var ty = Int(((Double(y) + 0.5 - oy) / texelPx).rounded(.down)) % side
                if ty < 0 { ty += side }
                tile.withUnsafeBufferPointer { t in
                    let trow = t.baseAddress! + ty * side * 4
                    for x in 0..<width {
                        var tx = Int(((Double(x) + 0.5 - ox) / texelPx).rounded(.down)) % side
                        if tx < 0 { tx += side }
                        let q = trow + tx * 4
                        row[x * 4] = q[0]; row[x * 4 + 1] = q[1]; row[x * 4 + 2] = q[2]; row[x * 4 + 3] = 255
                    }
                }
            }
        }
    }
}

public extension ZXArt {
    /// 画进一个 y 向下的上下文 (SwiftUI Canvas 的 `withCGContext`、或 `render` 翻转过的位图)。
    /// `rect` 用上下文当前单位; `pixelsPerUnit` 是这些单位对应的设备像素 (滤镜层离屏位图用)。
    /// `includesGround` 为 false 时不画底色与纸纹, 只画图层 (画进一个清空的上下文就是透明底的图层图; 缺省 true,
    /// 与以前逐位相同)。
    static func draw(_ drawing: Drawing, in ctx: CGContext, rect: CGRect, pixelsPerUnit: CGFloat,
                     includesGround: Bool = true) {
        let visible = ctx.boundingBoxOfClipPath.intersection(rect)
        draw(Prepared(drawing), in: ctx, rect: rect, visible: visible.isNull ? rect : visible,
             pixelsPerUnit: pixelsPerUnit, ground: includesGround)
    }
}

// MARK: - 内部

extension ZXArt {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    struct SendableBuffer: @unchecked Sendable { let pointer: UnsafeMutableRawPointer }

    /// 渲染前的一次性准备: 每个形状的纵向范围 (分带剔除用) 与样式分组 (批量用)。
    struct Prepared: Sendable {
        let drawing: Drawing
        /// 每层每个形状的 [minY, maxY] (逻辑单位)。
        let yRange: [[SIMD2<Float>]]
        /// 每层的批次: 形状下标区间, 同一批次样式相同。
        let runs: [[Range<Int>]]

        init(_ d: Drawing) {
            drawing = d
            var yr: [[SIMD2<Float>]] = [], rs: [[Range<Int>]] = []
            yr.reserveCapacity(d.layers.count)
            for layer in d.layers {
                let shapes = layer.shapes
                var ys = [SIMD2<Float>](repeating: .zero, count: shapes.count)
                var runs: [Range<Int>] = []
                var start = 0
                for i in 0..<shapes.count {
                    let sh = shapes[i]
                    var lo = Float.infinity, hi = -Float.infinity
                    for p in sh.points {
                        if p.y < lo { lo = p.y }
                        if p.y > hi { hi = p.y }
                    }
                    let pad = sh.lineWidth
                    ys[i] = SIMD2(lo - pad, hi + pad)
                    if i > start && !Prepared.sameStyle(shapes[i - 1], sh) {
                        runs.append(start..<i)
                        start = i
                    }
                }
                if start < shapes.count { runs.append(start..<shapes.count) }
                yr.append(ys)
                rs.append(runs)
            }
            yRange = yr
            runs = rs
        }

        @inline(__always)
        static func sameStyle(_ a: Shape, _ b: Shape) -> Bool {
            a.fill == b.fill && a.lineWidth == b.lineWidth && a.closed == b.closed
                && (a.lineWidth > 0 ? a.stroke == b.stroke : true)
        }
    }

    static func makeBitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: sRGB, bitmapInfo: bitmapInfo)
    }

    /// `visible`: 本次实际要出像素的区域 (上下文单位), 用来剔除形状与裁小离屏。
    /// `ground`: 是否由本函数画底色与纸纹 (位图渲染已逐像素填好时传 false)。
    static func draw(_ prepared: Prepared, in ctx: CGContext, rect: CGRect, visible: CGRect, pixelsPerUnit: CGFloat,
                     ground: Bool = true) {
        let drawing = prepared.drawing
        let s = max(Double(rect.width) / drawing.width, Double(rect.height) / drawing.height)
        let ox = Double(rect.midX) - drawing.width * s / 2
        let oy = Double(rect.midY) - drawing.height * s / 2
        let view = visible.intersection(rect)
        guard !view.isNull, view.height > 0 else { return }
        // 可见范围 → 逻辑单位的 y 区间 (剔除用, 放宽 2 个单位)
        let vy0 = Float((Double(view.minY) - oy) / s - 2), vy1 = Float((Double(view.maxY) - oy) / s + 2)
        ctx.saveGState()
        ctx.clip(to: view)
        let bg = drawing.background
        if ground {
            withCG {
                ctx.setFillColor(red: bg.red, green: bg.green, blue: bg.blue, alpha: 1)
                ctx.fill(view)
            }
        }
        if ground, let paper = drawing.paper, let tile = paperTile(paper, paperColor: bg) {
            cgLock.lock()
            defer { cgLock.unlock() }
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(ox), y: CGFloat(oy))
            ctx.scaleBy(x: CGFloat(s * paper.texel), y: CGFloat(s * paper.texel))
            ctx.interpolationQuality = .low
            ctx.draw(tile, in: CGRect(x: 0, y: 0, width: PaperTexture.side, height: PaperTexture.side), byTiling: true)
            ctx.restoreGState()
        }
        let geo = Geo(s: s, ox: ox, oy: oy, ppu: Double(pixelsPerUnit), view: view, vy0: vy0, vy1: vy1)
        for (li, layer) in drawing.layers.enumerated() {
            if let filter = layer.filter {
                drawFiltered(prepared, li, filter: filter, in: ctx, geo)
            } else if let mist = layer.mist {
                drawMisted(prepared, li, mist: mist, in: ctx, geo)
            } else {
                withCG {
                    ctx.saveGState()
                    ctx.setBlendMode(layer.blend == .multiply ? .multiply : .normal)
                    ctx.setAlpha(CGFloat(layer.opacity))
                    if layer.opacity < 1 { ctx.beginTransparencyLayer(auxiliaryInfo: nil) }
                    ctx.translateBy(x: CGFloat(ox), y: CGFloat(oy))
                    ctx.scaleBy(x: CGFloat(s), y: CGFloat(s))
                    drawShapes(prepared, li, in: ctx, vy0: vy0, vy1: vy1)
                    if layer.opacity < 1 { ctx.endTransparencyLayer() }
                    ctx.restoreGState()
                }
            }
        }
        ctx.restoreGState()
    }

    /// 画布 → 上下文的变换与可见范围。
    struct Geo {
        var s: Double, ox: Double, oy: Double, ppu: Double
        var view: CGRect
        var vy0: Float, vy1: Float
    }

    /// 形状按 SVG / canvas 语义: 先填 (非零环绕, 隐式闭合) 后描 (不闭合, 斜接, 平头)。
    /// `drawPath(.fillStroke)` 同样是先填 (隐式闭合子路径) 后描 (按原样, 不闭合)。
    static func drawShapes(_ prepared: Prepared, _ li: Int, in ctx: CGContext, vy0: Float, vy1: Float) {
        let shapes = prepared.drawing.layers[li].shapes
        let yr = prepared.yRange[li]
        ctx.setLineJoin(.miter)
        ctx.setLineCap(.butt)
        var buf: [CGPoint] = []
        buf.reserveCapacity(256)
        for run in prepared.runs[li] {
            let first = shapes[run.lowerBound]
            let stroke = first.lineWidth > 0 ? first.stroke : nil
            guard first.fill != nil || stroke != nil else { continue }
            var any = false
            for i in run {
                let r = yr[i]
                if r.y < vy0 || r.x > vy1 { continue }
                let sh = shapes[i]
                guard sh.points.count >= 2 else { continue }
                buf.removeAll(keepingCapacity: true)
                for p in sh.points { buf.append(CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))) }
                ctx.addLines(between: buf)
                if sh.closed { ctx.closePath() }
                any = true
            }
            guard any else { continue }
            if let f = first.fill {
                ctx.setFillColor(red: f.red, green: f.green, blue: f.blue, alpha: f.alpha)
            }
            if let st = stroke {
                ctx.setStrokeColor(red: st.red, green: st.green, blue: st.blue, alpha: st.alpha)
                ctx.setLineWidth(CGFloat(first.lineWidth))
            }
            ctx.drawPath(using: first.fill != nil ? (stroke != nil ? .fillStroke : .fill) : .stroke)
        }
    }

    /// 512² 纸纹图块: 纸色往 tint 偏 shade/255·strength。
    static func paperTile(_ paper: PaperTexture, paperColor: ZXHex) -> CGImage? {
        let side = PaperTexture.side
        guard let px = paperTileBytes(paper, paperColor: paperColor),
              let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: sRGB, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    static func paperTileBytes(_ paper: PaperTexture, paperColor: ZXHex) -> [UInt8]? {
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
        return px
    }

    /// 图层所有形状的包围盒 (逻辑单位), 空层返回 nil。
    static func bounds(of shapes: [Shape]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        var minX = Float.infinity, minY = Float.infinity, maxX = -Float.infinity, maxY = -Float.infinity
        for sh in shapes {
            for p in sh.points {
                if p.x < minX { minX = p.x }
                if p.x > maxX { maxX = p.x }
                if p.y < minY { minY = p.y }
                if p.y > maxY { maxY = p.y }
            }
        }
        guard minX.isFinite else { return nil }
        return (Double(minX), Double(minY), Double(maxX), Double(maxY))
    }

    /// 把 y 向上的离屏图贴到 y 向下的上下文里 `box` 处。
    static func blit(_ img: CGImage, into ctx: CGContext, box: CGRect, blend: BlendMode, opacity: Double,
                     interpolation: CGInterpolationQuality = .default) {
        ctx.saveGState()
        ctx.setBlendMode(blend == .multiply ? .multiply : .normal)
        ctx.setAlpha(CGFloat(opacity))
        ctx.interpolationQuality = interpolation
        ctx.translateBy(x: box.minX, y: box.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: box.width, height: box.height))
        ctx.restoreGState()
    }

    /// 滤镜层: 离屏画 → 逐像素 (只处理不透明像素, 只在形状包围盒 ∩ 可见区内) → 按混合模式贴回。
    private static func drawFiltered(_ prepared: Prepared, _ li: Int, filter: LayerFilter, in ctx: CGContext, _ g: Geo) {
        let layer = prepared.drawing.layers[li]
        guard let bb = bounds(of: layer.shapes) else { return }
        let s = g.s, ox = g.ox, oy = g.oy, ppu = g.ppu
        let pad = 4.0
        var box = CGRect(x: bb.minX * s + ox - pad, y: bb.minY * s + oy - pad,
                         width: (bb.maxX - bb.minX) * s + 2 * pad, height: (bb.maxY - bb.minY) * s + 2 * pad)
        box = box.intersection(g.view)
        guard !box.isNull, box.width >= 1, box.height >= 1 else { return }
        // 离屏与设备像素对齐 (分带渲染时各带的像素网格一致)。
        box = CGRect(x: (box.minX * ppu).rounded(.down) / ppu, y: (box.minY * ppu).rounded(.down) / ppu,
                     width: 0, height: 0)
            .union(CGRect(x: (box.maxX * ppu).rounded(.up) / ppu, y: (box.maxY * ppu).rounded(.up) / ppu, width: 0, height: 0))
        let bw = Int((Double(box.width) * ppu).rounded()), bh = Int((Double(box.height) * ppu).rounded())
        guard bw > 0, bh > 0, let off = makeBitmap(width: bw, height: bh) else { return }
        // 离屏: y 向下, 原点 = box 左上角, 单位 = 设备像素。
        off.translateBy(x: 0, y: CGFloat(bh))
        off.scaleBy(x: 1, y: -1)
        off.scaleBy(x: CGFloat(ppu), y: CGFloat(ppu))
        off.translateBy(x: -box.minX, y: -box.minY)
        off.translateBy(x: CGFloat(ox), y: CGFloat(oy))
        off.scaleBy(x: CGFloat(s), y: CGFloat(s))
        let vy0 = Float((Double(box.minY) - oy) / s - 2), vy1 = Float((Double(box.maxY) - oy) / s + 2)
        withCG { drawShapes(prepared, li, in: off, vy0: vy0, vy1: vy1) }

        if let data = off.data, filter.perlin.count >= 4096 {
            let pixBuf = SendableBuffer(pointer: data)
            let table = filter.perlin
            let doFade = filter.passes.contains(.fade)
            let doWispy = filter.passes.contains(.wispy)
            // 像素 (px, py) 的左上角 → 上下文单位 → 画布单位 → 原作图层像素坐标
            let ax = 1 / (ppu * s) * filter.scale
            let bx = (Double(box.minX) - ox) / s * filter.scale + filter.offsetX
            let by = (Double(box.minY) - oy) / s * filter.scale + filter.offsetY
            parallelRows(bh) { rows in
              table.withUnsafeBufferPointer { perlinBuf in
                let table = perlinBuf.baseAddress!
                let pix = pixBuf.pointer.assumingMemoryBound(to: UInt8.self)
                for py in rows {
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
                        var gg = (Double(q[1]) * 255 / af).rounded()
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
                            gg = gg * (0.95 + 0.05 * m)
                            b = b * (0.9 + 0.1 * m)
                            a = a * (0.5 + 0.5 * nz)
                        }
                        r = clampedByte(r); gg = clampedByte(gg); b = clampedByte(b); a = clampedByte(a)
                        // putImageData → 重新预乘
                        q[3] = UInt8(a)
                        q[0] = UInt8((r * a / 255).rounded())
                        q[1] = UInt8((gg * a / 255).rounded())
                        q[2] = UInt8((b * a / 255).rounded())
                    }
                }
              }
            }
        }
        guard let img = off.makeImage() else { return }
        withCG { blit(img, into: ctx, box: box, blend: layer.blend, opacity: layer.opacity) }
    }

    /// 雾化层 (远山): 低分辨率离屏 → 按山脊深度淡出 → 两遍箱式模糊 → 平滑放大贴回。
    /// 低分辨率网格对齐整张图的原点, 离屏上下各多画一圈 (≥ 模糊半径), 分带渲染无接缝。
    private static func drawMisted(_ prepared: Prepared, _ li: Int, mist: LayerMist, in ctx: CGContext, _ g: Geo) {
        let layer = prepared.drawing.layers[li]
        guard let bb = bounds(of: layer.shapes) else { return }
        let s = g.s, ox = g.ox, oy = g.oy, ppu = g.ppu
        let dev = s * ppu  // 逻辑单位 → 设备像素
        let radius = 3     // 低分辨率像素
        // 一个低分辨率像素 ≈ blur / radius 逻辑单位, 至少 1 设备像素。
        let f = max(1.0, (mist.blur * dev / Double(radius)).rounded())
        let unit = f / ppu  // 低分辨率像素的边长 (上下文单位)
        let padPx = Double(2 * radius + 2)
        // 图层包围盒 (上下文单位), 放宽模糊半径
        let blurCtx = padPx * unit
        let lb = CGRect(x: bb.minX * s + ox - blurCtx, y: bb.minY * s + oy - blurCtx,
                        width: (bb.maxX - bb.minX) * s + 2 * blurCtx, height: (bb.maxY - bb.minY) * s + 2 * blurCtx)
        // 可见区放宽 pad 后与包围盒相交, 再对齐低分辨率网格 (原点 = rect 原点, 即整张图)
        let need = g.view.insetBy(dx: -CGFloat(blurCtx), dy: -CGFloat(blurCtx)).intersection(lb)
        guard !need.isNull, need.width > 0, need.height > 0 else { return }
        let gx0 = Int((Double(need.minX) / unit).rounded(.down)), gx1 = Int((Double(need.maxX) / unit).rounded(.up))
        let gy0 = Int((Double(need.minY) / unit).rounded(.down)), gy1 = Int((Double(need.maxY) / unit).rounded(.up))
        let lw = gx1 - gx0, lh = gy1 - gy0
        guard lw > 0, lh > 0, let off = makeBitmap(width: lw, height: lh) else { return }
        let box = CGRect(x: Double(gx0) * unit, y: Double(gy0) * unit, width: Double(lw) * unit, height: Double(lh) * unit)
        off.translateBy(x: 0, y: CGFloat(lh))
        off.scaleBy(x: 1, y: -1)
        off.scaleBy(x: CGFloat(1 / unit), y: CGFloat(1 / unit))
        off.translateBy(x: -box.minX, y: -box.minY)
        off.translateBy(x: CGFloat(ox), y: CGFloat(oy))
        off.scaleBy(x: CGFloat(s), y: CGFloat(s))
        let vy0 = Float((Double(box.minY) - oy) / s - 2), vy1 = Float((Double(box.maxY) - oy) / s + 2)
        withCG { drawShapes(prepared, li, in: off, vy0: vy0, vy1: vy1) }
        guard let data = off.data else { return }
        let pix = data.bindMemory(to: UInt8.self, capacity: lw * lh * 4)

        // 按山脊深度淡出: 每列山脊只算一次
        var ridgeCol = [Double](repeating: .infinity, count: lw)
        for x in 0..<lw {
            let cx = (Double(gx0 + x) + 0.5) * unit
            ridgeCol[x] = mist.ridgeY(at: (cx - ox) / s)
        }
        for y in 0..<lh {
            let ly = ((Double(gy0 + y) + 0.5) * unit - oy) / s
            let row = pix + y * lw * 4
            for x in 0..<lw {
                let q = row + x * 4
                if q[3] == 0 { continue }
                let k = mist.keep(y: ly, ridgeY: ridgeCol[x])
                q[0] = UInt8((Double(q[0]) * k).rounded())
                q[1] = UInt8((Double(q[1]) * k).rounded())
                q[2] = UInt8((Double(q[2]) * k).rounded())
                q[3] = UInt8((Double(q[3]) * k).rounded())
            }
        }
        boxBlur(pix, width: lw, height: lh, radius: radius)
        boxBlur(pix, width: lw, height: lh, radius: radius)
        guard let img = off.makeImage() else { return }
        withCG { blit(img, into: ctx, box: box, blend: layer.blend, opacity: layer.opacity, interpolation: .high) }
    }

    /// 预乘 RGBA8 的箱式模糊 (先横后竖, 边缘按透明处理)。整数运算, 结果确定。
    static func boxBlur(_ pix: UnsafeMutablePointer<UInt8>, width w: Int, height h: Int, radius r: Int) {
        guard r > 0, w > 0, h > 0 else { return }
        let n = 2 * r + 1
        var line = [Int32](repeating: 0, count: max(w, h) * 4)
        // 横
        for y in 0..<h {
            let row = pix + y * w * 4
            for i in 0..<(w * 4) { line[i] = Int32(row[i]) }
            for c in 0..<4 {
                var acc: Int32 = 0
                for k in 0...min(r, w - 1) { acc += line[k * 4 + c] }
                for x in 0..<w {
                    row[x * 4 + c] = UInt8((acc + Int32(n / 2)) / Int32(n))
                    let add = x + r + 1, sub = x - r
                    if add < w { acc += line[add * 4 + c] }
                    if sub >= 0 { acc -= line[sub * 4 + c] }
                }
            }
        }
        // 竖
        for x in 0..<w {
            for y in 0..<h { for c in 0..<4 { line[y * 4 + c] = Int32(pix[(y * w + x) * 4 + c]) } }
            for c in 0..<4 {
                var acc: Int32 = 0
                for k in 0...min(r, h - 1) { acc += line[k * 4 + c] }
                for y in 0..<h {
                    pix[(y * w + x) * 4 + c] = UInt8((acc + Int32(n / 2)) / Int32(n))
                    let add = y + r + 1, sub = y - r
                    if add < h { acc += line[add * 4 + c] }
                    if sub >= 0 { acc -= line[sub * 4 + c] }
                }
            }
        }
    }

    /// Uint8ClampedArray 的写入: 夹到 0…255, 四舍六入五成双。
    @inline(__always)
    private static func clampedByte(_ v: Double) -> Double {
        if !(v > 0) { return 0 }
        if v >= 255 { return 255 }
        return v.rounded(.toNearestOrEven)
    }
}
