// shanshui@3 的画法载荷。旧 p 是布局骨架, 不参与最终笔毫绘制。
// 所有新增随机细节只用 Brush 的 UInt32 哈希, 不持有 Entropy。
import CoreGraphics
import Foundation

extension ZXArt {
    enum SSPaintV3: Sendable {
        case stroke(SSBrushPathV3)
        case surface
        case omit
    }

    struct SSBrushPathV3: Sendable {
        /// 相对旧多边形首点; placed / fit 的平移只改变 p, 不必修改载荷。
        var relative: [SIMD3<Double>]
        var style: Brush.Style
        var seed: UInt32
        var keepsFill: Bool
        var rings: [SSRingV3] = []
    }

    struct SSRingV3: Sendable {
        var relativeCenter: SIMD2<Double>
        var radius: Double
        var seed: UInt32
    }

    /// 逐边检查新笔的实际几何, 避免用整笔包围盒把绕开诗栏的山也剔除。
    static func clearsVerseV3(_ shape: Shape, rect: CGRect, padding: Double = 4) -> Bool {
        let box = rect.insetBy(dx: -padding, dy: -padding)
        let points = shape.points
        guard !points.isEmpty, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return false }
        func crosses(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool {
            var lo = 0.0, hi = 1.0
            for (start, delta, minV, maxV) in [
                (Double(a.x), Double(b.x - a.x), Double(box.minX), Double(box.maxX)),
                (Double(a.y), Double(b.y - a.y), Double(box.minY), Double(box.maxY)),
            ] {
                if abs(delta) < 1e-12 {
                    if start < minV || start > maxV { return false }
                } else {
                    let t0 = (minV - start) / delta, t1 = (maxV - start) / delta
                    lo = max(lo, min(t0, t1)); hi = min(hi, max(t0, t1))
                    if lo > hi { return false }
                }
            }
            return true
        }
        for (a, b) in zip(points, points.dropFirst()) { if crosses(a, b) { return false } }
        if shape.closed || shape.fill != nil, crosses(points.last!, points[0]) { return false }
        // 有填充的多边形可能把整块诗句框包在里面, 此时边不与框相交。
        if shape.fill != nil {
            let x = Double(box.midX), y = Double(box.midY)
            var inside = false, previous = points.last!
            for p in points {
                let ax = Double(previous.x), ay = Double(previous.y), bx = Double(p.x), by = Double(p.y)
                if (ay > y) != (by > y), x < ax + (bx - ax) * (y - ay) / (by - ay) { inside.toggle() }
                previous = p
            }
            if inside { return false }
        }
        return true
    }
}

extension ShanShuiEngine {
    /// 在原来顺着山势的折线上截取一段 9…26 单位的短皴。只改画法, 不改旧轮廓和取数。
    func cunCenterlineV3(_ points: [P], seed: UInt32) -> [P] {
        guard points.count > 1 else { return points }
        var lengths = [0.0]
        for (a, b) in zip(points, points.dropFirst()) {
            lengths.append(lengths.last! + ZXArt.distance(a, b))
        }
        let total = lengths.last!
        let length = min(total, 9 + 17 * ZXArt.Brush.random(seed, 70))
        let start = (total - length) * ZXArt.Brush.random(seed, 71), end = start + length
        var result: [P] = []
        for i in 1..<points.count {
            let a = lengths[i - 1], b = lengths[i]
            guard b > a, b >= start, a <= end else { continue }
            func at(_ d: Double) -> P {
                let t = (d - a) / (b - a)
                return P(points[i - 1].x + (points[i].x - points[i - 1].x) * t,
                         points[i - 1].y + (points[i].y - points[i - 1].y) * t)
            }
            if result.isEmpty { result.append(at(max(start, a))) }
            result.append(at(min(end, b)))
        }
        return result
    }

    func pathV3(_ points: [P], origin: P, style: ZXArt.Brush.Style, seed: UInt32,
                keepsFill: Bool) -> ZXArt.SSBrushPathV3 {
        .init(relative: points.map { SIMD3($0.x - origin.x, $0.y - origin.y, 1) },
              style: style, seed: seed, keepsFill: keepsFill)
    }

    /// 没有原 stroke/n0 的向量线 (树干、栏杆、篙) 用已有坐标推出种子。
    func coordinateSeedV3(_ p: P) -> UInt32 {
        guard p.x.isFinite, p.y.isFinite else { return 0 }
        let x = UInt32(truncatingIfNeeded: Int64((p.x * 1024).rounded()))
        let y = UInt32(truncatingIfNeeded: Int64((p.y * 1024).rounded()))
        return ZXArt.Brush.hash(x, y)
    }

    /// sin → lens; 恒宽 → even; 渐收 → brush; 起笔 → rise; 双瓣 / 非单峰 → nail。
    func profileV3(_ fun: (Double) -> Double) -> ZXArt.Brush.Profile {
        let a = fun(0), b = fun(0.5), c = fun(1)
        if abs(a - b) < 0.02 && abs(b - c) < 0.02 { return .even }
        if abs(a) < 0.02 && abs(c) < 0.02 && b > 0.5 { return .lens }
        if a > c + 0.2 { return .brush }
        if c > a + 0.2 { return .rise }
        return .nail
    }

    func polyV3(_ points: [P], xof: Double = 0, yof: Double = 0, fil: C? = .clear,
                str: C?, wid: Double = 0) -> ZXArt.SSPoly {
        var legacy = poly(points, xof: xof, yof: yof, fil: fil, str: str, wid: wid)
        if let str, str.a > 0, str.r < 250, wid > 0, let origin = legacy.p.first {
            let style = ZXArt.Brush.Style(width: wid, tone: str.a * (1 - str.r / 255), dry: 0.4,
                                          wet: 0.2, side: 0.6, darkDirection: SIMD2(1, 0.35), profile: .nail)
            legacy.paintV3 = .stroke(pathV3(legacy.p, origin: origin, style: style,
                                           seed: coordinateSeedV3(origin), keepsFill: true))
        }
        return legacy
    }

    func trunkV3(_ points: [P], fil: C?, str: C, wid: Double, centerline: [P]? = nil) -> ZXArt.SSPoly {
        var legacy = poly(points, fil: fil, str: str, wid: wid)
        if let origin = legacy.p.first {
            let style = ZXArt.Brush.Style(width: wid * 1.4, tone: str.a * (1 - str.r / 255), dry: 0.4,
                                          wet: 0.25, side: 0.75, darkDirection: SIMD2(1, 0.15), profile: .press)
            legacy.paintV3 = .stroke(pathV3(centerline ?? points, origin: origin, style: style,
                                           seed: coordinateSeedV3(origin), keepsFill: true))
        }
        return legacy
    }

    func surfaceV3(_ points: [P], xof: Double, yof: Double) -> ZXArt.SSPoly {
        var legacy = poly(points, xof: xof, yof: yof, fil: .white, str: nil)
        legacy.paintV3 = .surface
        return legacy
    }

    func boatRingsV3(_ canv: inout ZXArt.SSCanv, x: Double, y: Double, scale: Double, seed: Double) {
        guard let last = canv.indices.last, case .some(.stroke(var path)) = canv[last].paintV3,
              let origin = canv[last].p.first else { return }
        let base = UInt32((seed * 4_294_967_296).rounded(.down))
        for k in 0..<2 {
            path.rings.append(.init(relativeCenter: SIMD2(x - origin.x + Double(k) * 24 * scale,
                                                         y - origin.y + (12 + Double(k) * 4) * scale),
                                    radius: (14 + Double(k) * 6) * scale,
                                    seed: ZXArt.Brush.hash(base, UInt32(k))))
        }
        canv[last].paintV3 = .stroke(path)
    }
}

extension ZXArt.ShanShui {
    static func generateV3Traced(seed: ZXArt.Seed, size: CGSize, params: Params,
                                 verse: ZXArt.VerseLayout) -> (drawing: ZXArt.Drawing, trace: ZXArt.Trace) {
        let aspect = Double(size.height / size.width)
        let W = aspect >= 1 ? logicalShortSide : logicalShortSide / aspect
        let H = aspect >= 1 ? logicalShortSide * aspect : logicalShortSide
        let engine = ShanShuiEngine(seed: seed)
        let composed = engine.composeV3(width: W, height: H, params: params, verse: verse)
        var trace = ZXArt.Trace(logicalWidth: W, logicalHeight: H, prngAfter: engine.e.state)
        // 布局骨架指纹和 @2 相同; 最终笔毫指纹另记在 drawing.layers。
        for part in composed.parts { for p in part.canv { trace.add(p.p.map { ($0.x, $0.y) }) } }
        var paper = params.paperTexture ? engine.backgroundPaper() : nil
        paper?.tint = params.palette.ink
        let built = layersV3(composed.parts, palette: params.palette, width: W, height: H, verse: verse)
        var drawing = ZXArt.Drawing(width: W, height: H, background: params.palette.paper, paper: paper,
                                     layers: built.layers)
        drawing.setVerse(verse, quietTop: params.quietTop)
        drawing.anchors = composed.anchors
        drawing.nearSpans = built.nearSpans
        return (drawing, trace)
    }

    static func layersV3(_ parts: [ShanShuiEngine.Part], palette: ZXArt.Palette, width W: Double, height H: Double,
                          verse: ZXArt.VerseLayout) -> (layers: [ZXArt.Layer], nearSpans: [ZXArt.ShapeSpan]) {
        var result: [ZXArt.Layer] = [], near: [ZXArt.ShapeSpan] = []
        let inkBlend: ZXArt.BlendMode = palette.isDark ? .normal : .multiply
        let verseBox = CGRect(x: Double(verse.rect.minX) * W, y: Double(verse.rect.minY) * H,
                              width: Double(verse.rect.width) * W, height: Double(verse.rect.height) * H)
        // 新笔毫、墨圈和湿晕不能越过旧 cull 的边界; 对扩展后的几何再保守检查一次。
        func clearOfVerse(_ shape: ZXArt.Shape) -> Bool {
            let pad = max(4, Double(shape.lineWidth) * 5)
            return ZXArt.clearsVerseV3(shape, rect: verseBox, padding: pad)
        }
        func append(_ layer: ZXArt.Layer, isNear: Bool) {
            var l = layer
            l.shapes = l.shapes.filter(clearOfVerse)
            guard !l.shapes.isEmpty else { return }
            if isNear { near.append(.init(layer: result.count, range: 0..<l.shapes.count)) }
            result.append(l)
        }
        for (partIndex, part) in parts.enumerated() {
            if part.mist != nil {
                // 远山只加轻微湿化, mist 参数与旧构图完全一致。
                for var layer in layers([part], palette: palette).layers {
                    layer.wash = .init(bleed: 1.2, rim: 0.15, grain: 0.06)
                    append(layer, isNear: false)
                }
                continue
            }
            var whites: [ZXArt.Shape] = [], native: [ZXArt.Shape] = []
            var strokes: [ZXArt.Brush.Stroke] = [], styles: [ZXArt.Brush.Style] = []
            var surfaceIndex = 0
            func flushWhites() {
                append(.init(shapes: whites), isNear: part.near)
                whites.removeAll(keepingCapacity: true)
            }
            func flushPaint() {
                append(.init(blend: inkBlend, tooth: 0.18, shapes: native), isNear: part.near)
                let split = ZXArt.layers(from: strokes, styles: styles, palette: palette,
                                         wash: .init(bleed: 1.8, rim: 0.3, grain: 0.1), tooth: 0.24)
                append(split.wet, isNear: part.near)
                append(split.dry, isNear: part.near)
                native.removeAll(keepingCapacity: true)
                strokes.removeAll(keepingCapacity: true)
                styles.removeAll(keepingCapacity: true)
            }
            func surface(_ shapes: [ZXArt.Shape], index: Int) {
                let (ridge, x0) = ZXArt.LayerMist.ridge(of: shapes, step: 2)
                let seed = ZXArt.Brush.hash(UInt32(partIndex), UInt32(index))
                append(.init(blend: inkBlend, rim: .init(ridge: ridge, ridgeX0: x0, seed: seed),
                             wash: .init(bleed: 1.5, rim: 0.28, grain: 0.1), shapes: shapes), isNear: part.near)
                // 苔点以部件号 + 山脊列号哈希成簇; 不改变布局骨架或锚点。
                var moss: [ZXArt.Shape] = []
                for i in stride(from: 4, to: ridge.count, by: 13) {
                    let x = x0 + Double(i) * 2, y = Double(ridge[i])
                    guard y.isFinite, x >= 0, x <= W, ZXArt.Brush.random(seed, UInt32(i)) > 0.58 else { continue }
                    for k in 0..<3 {
                        let s = ZXArt.Brush.hash(seed, UInt32(i * 3 + k))
                        let center = SIMD2(x + (ZXArt.Brush.random(s, 0) - 0.5) * 8,
                                           y + 2 + ZXArt.Brush.random(s, 1) * 4)
                        let points = ZXArt.Brush.blot(center: center, radius: 0.9 + ZXArt.Brush.random(s, 2),
                                                      squash: 0.55, angle: -0.3, seed: s)
                        moss.append(.init(points: points, fill: palette.mapGray(0, alpha: 0.4), stroke: nil,
                                          lineWidth: 0, closed: true))
                    }
                }
                append(.init(blend: inkBlend, tooth: 0.22, shapes: moss), isNear: part.near)
            }
            // 白底是遮挡边界: 此前的湿 / 干笔必须先贴回, 否则后山会透过前山。
            for poly in part.canv {
                switch poly.paintV3 {
                case .some(.omit): continue
                case .some(.surface):
                    flushPaint()
                    ZXArt.appendShapes([poly], palette: palette, into: &whites)
                    flushWhites()
                    var mask: [ZXArt.Shape] = []
                    var ink = poly
                    ink.fil = .gray(0, 1)
                    ZXArt.appendShapes([ink], palette: palette, into: &mask)
                    surface(mask, index: surfaceIndex)
                    surfaceIndex += 1
                case .some(.stroke(let path)):
                    guard let origin = poly.p.first else { continue }
                    if path.keepsFill {
                        var fill = poly
                        fill.str = nil; fill.wid = 0
                        if fill.fil == .white {
                            flushPaint()
                            ZXArt.appendShapes([fill], palette: palette, into: &whites)
                        } else { ZXArt.appendShapes([fill], palette: palette, into: &native) }
                    }
                    flushWhites()
                    let line = path.relative.map { SIMD3($0.x + origin.x, $0.y + origin.y, $0.z) }
                    strokes.append(ZXArt.Brush.stroke(line, style: path.style, seed: path.seed))
                    styles.append(path.style)
                    for ring in path.rings {
                        let style = ZXArt.Brush.Style(width: 0.85, tone: 0.16, dry: 0.65, side: 0.3, profile: .brush)
                        strokes.append(ZXArt.Brush.ring(center: ring.relativeCenter + SIMD2(origin.x, origin.y),
                                                       radius: ring.radius, squash: 0.22, style: style, seed: ring.seed))
                        styles.append(style)
                    }
                case nil:
                    if poly.fil == .white {
                        flushPaint()
                        ZXArt.appendShapes([poly], palette: palette, into: &whites)
                    } else {
                        flushWhites()
                        ZXArt.appendShapes([poly], palette: palette, into: &native)
                    }
                }
            }
            flushWhites()
            flushPaint()
        }
        return (result, near)
    }
}
