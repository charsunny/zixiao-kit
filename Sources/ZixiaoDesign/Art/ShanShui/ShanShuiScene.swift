//  ShanShuiScene.swift — 水、原作的横卷规划 (mountplanner / chunkloader) 与竖幅构图 + 公开 API
//
//  water / mountplanner / chunkloader / chunkrender / 背景纸纹 ported from shan-shui-inf index.html.
//  MIT License, (c) 2018 Lingdong Huang — https://github.com/LingDong-/shan-shui-inf
//  Full license text: ZXArtLicenses.swift / LICENSES/.
//
//  原作是无限横卷 (视窗 3000×800, 按 512 宽的 chunk 规划)。`originalScene` 原样复现它的第一屏,
//  用来做整幅画的逐多边形对拍; 手机壁纸用的是 `compose` —— 自己的竖幅构图, 只调用移植过来的
//  生成器 (山 / 远山 / 平岸 / 水 / 船), 不改它们的内部。

import CoreGraphics
import Foundation

extension ShanShuiEngine {
    // MARK: water

    func water(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 2, len: Double = 800,
               clu: Int = 10) -> ZXArt.SSCanv {
        var canv: ZXArt.SSCanv = []
        var ptlist: [[P]] = []
        var yk = 0.0
        for _ in 0..<clu {
            var row: [P] = []
            let xk = (r() - 0.5) * (len / 8)
            yk += r() * 5
            let lk = len / 4 + r() * (len / 4)
            let reso = 5.0
            var j = -lk
            while j < lk {
                row.append(P(j + xk, sin(j * 0.2) * hei * n(j * 0.1) - 20 + yk))
                j += reso
            }
            ptlist.append(row)
        }
        for j in 1..<ptlist.count {
            let c = C.ink(0.3 + r() * 0.3)
            canv += stroke(ptlist[j].map { P($0.x + xoff, $0.y + yoff) }, wid: 1, col: c)
        }
        return canv
    }

    // MARK: mountplanner / chunkloader (原作第一屏)

    struct PlanItem { var tag: String; var x: Double; var y: Double }

    func mountplanner(_ xmin: Double, _ xmax: Double) -> [PlanItem] {
        var reg: [PlanItem] = []
        func chadd(_ it: PlanItem, _ mind: Double = 10) -> Bool {
            for k in reg where abs(k.x - it.x) < mind { return false }
            reg.append(it)
            return true
        }
        let samp = 0.03
        let ns: (Double, Double) -> Double = { x, _ in max(self.n(x * samp) - 0.55, 0) * 2 }
        let yr: (Double) -> Double = { x in self.n(x * 0.01, Double.pi) }
        func locmax(_ x: Double, _ y: Double, _ rr: Double) -> Bool {
            let z0 = ns(x, y)
            if z0 <= 0.3 { return false }
            var i = x - rr
            while i < x + rr {
                var j = y - rr
                while j < y + rr {
                    if ns(i, j) > z0 { return false }
                    j += 1
                }
                i += 1
            }
            return true
        }
        let xstep = 5.0
        let mwid = 200.0
        var i = xmin
        while i < xmax {
            let i1 = Int((i / xstep).rounded(.down))
            if let v = planmtx[i1], v != 0, !v.isNaN {} else { planmtx[i1] = 0 }
            i += xstep
        }
        i = xmin
        while i < xmax {
            var j = 0.0
            while j < yr(i) * 480 {
                if locmax(i, j, 2) {
                    let xof = i + 2 * (r() - 0.5) * 500
                    let yof = j + 300
                    if chadd(PlanItem(tag: "mount", x: xof, y: yof)) {
                        var k = ((xof - mwid) / xstep).rounded(.down)
                        while k < (xof + mwid) / xstep {
                            planmtx[Int(k)] = (planmtx[Int(k)] ?? .nan) + 1
                            k += 1
                        }
                    }
                }
                j += 30
            }
            if abs(i).truncatingRemainder(dividingBy: 1000) < max(1, xstep - 1) {
                _ = chadd(PlanItem(tag: "distmount", x: i, y: 280 - r() * 50))
            }
            i += xstep
        }
        i = xmin
        while i < xmax {
            if planmtx[Int((i / xstep).rounded(.down))] == 0 {
                if r() < 0.01 {
                    var j = 0.0
                    while j < 4 * r() {
                        let x = i + 2 * (r() - 0.5) * 700
                        _ = chadd(PlanItem(tag: "flatmount", x: x, y: 700 - j * 50))
                        j += 1
                    }
                }
            }
            i += xstep
        }
        i = xmin
        while i < xmax {
            if r() < 0.2 {
                _ = chadd(PlanItem(tag: "boat", x: i, y: 300 + r() * 390), 400)
            }
            i += xstep
        }
        return reg
    }

    struct Chunk { var tag: String; var x: Double; var y: Double; var canv: ZXArt.SSCanv }

    /// `chunkloader(xmin, xmax)` + `chunkrender(xmin, xmax)` — 原作网页打开时的第一屏。
    func originalScene(xmin: Double = 0, xmax: Double = 3000) -> ZXArt.SSCanv {
        var chunks: [Chunk] = []
        func add(_ c: Chunk) {
            if chunks.isEmpty { chunks.append(c); return }
            if c.y <= chunks[0].y { chunks.insert(c, at: 0); return }
            if c.y >= chunks[chunks.count - 1].y { chunks.append(c); return }
            for j in 0..<(chunks.count - 1) where chunks[j].y <= c.y && c.y <= chunks[j + 1].y {
                chunks.insert(c, at: j + 1)
                return
            }
        }
        while xmax > memXmax - cwid || xmin < memXmin + cwid {
            let plan: [PlanItem]
            if xmax > memXmax - cwid {
                plan = mountplanner(memXmax, memXmax + cwid)
                memXmax += cwid
            } else {
                plan = mountplanner(memXmin - cwid, memXmin)
                memXmin -= cwid
            }
            for (i, p) in plan.enumerated() {
                let fi = Double(i)
                switch p.tag {
                case "mount":
                    add(Chunk(tag: p.tag, x: p.x, y: p.y, canv: mountain(p.x, p.y, fi * 2 * r())))
                    add(Chunk(tag: p.tag, x: p.x, y: p.y - 10000, canv: water(p.x, p.y, fi * 2)))
                case "flatmount":
                    let seed = 2 * r() * Double.pi
                    let w = 600 + r() * 400
                    let cho = 0.5 + r() * 0.2
                    add(Chunk(tag: p.tag, x: p.x, y: p.y, canv: flatMount(p.x, p.y, seed, hei: 100, wid: w, cho: cho)))
                case "distmount":
                    let seed = r() * 100
                    let len = e.choice([500.0, 1000, 1500])
                    add(Chunk(tag: p.tag, x: p.x, y: p.y, canv: distMount(p.x, p.y, seed, hei: 150, len: len)))
                case "boat":
                    let seed = r()
                    let fli = e.choice([true, false])
                    add(Chunk(tag: p.tag, x: p.x, y: p.y, canv: boat01(p.x, p.y, seed, sca: p.y / 800, fli: fli)))
                default:
                    break
                }
            }
        }
        var canv: ZXArt.SSCanv = []
        for c in chunks where xmin - cwid < c.x && c.x < xmax + cwid { canv += c.canv }
        return canv
    }

    // MARK: 背景纸纹 (原作最后一个 <script>: 512×512 镜像纸)

    func backgroundPaper() -> ZXArt.PaperTexture {
        let side = ZXArt.PaperTexture.side
        var shade = [UInt8](repeating: 0, count: side * side)
        func put(_ x: Int, _ y: Int, _ v: UInt8) {
            if x >= 0 && x < side && y >= 0 && y < side { shade[y * side + x] = v }
        }
        for i in 0...(side / 2) {
            for j in 0...(side / 2) {
                var c = 245 + n(Double(i) * 0.1, Double(j) * 0.1) * 10
                c -= r() * 20
                let v = UInt8(min(max((255 - c).rounded(), 0), 255))
                put(i, j, v); put(side - i, j, v); put(i, side - j, v); put(side - i, side - j, v)
            }
        }
        return ZXArt.PaperTexture(shade: shade, texel: 1, strength: 1)
    }
}

// MARK: - 竖幅构图

extension ShanShuiEngine {
    /// 手机竖幅: 上方 `quietTop` 留白 (锁屏时钟 + 诗句), 山在中上, 水在下。
    func compose(width W: Double, height H: Double, params: ZXArt.ShanShui.Params) -> [(ZXArt.SSCanv, Bool)] {
        drawTowers = false
        let d = min(max(params.density, 0), 1)
        var layers: [(ZXArt.SSCanv, Bool)] = []  // (canv, isDistant)
        let q = params.quietTop * H
        let texScale = 0.6 + 0.8 * d
        // 高度方向的尺度: 原作 800 高; 竖幅用画布高度的份额来定位, 山的尺寸按宽度定。
        let s = W / 560

        func distant(_ y: Double, _ hei: Double, _ len: Double = 0) -> ZXArt.SSCanv {
            let l = len > 0 ? len : ((W + 300) / 50).rounded(.up) * 50
            return distMount(-150 + (r() - 0.5) * 100, y, r() * 100, hei: hei, len: l)
        }
        func waterBand(_ y0: Double, _ y1: Double, count: Int) -> ZXArt.SSCanv {
            var c: ZXArt.SSCanv = []
            for k in 0..<count {
                let t = count == 1 ? 0.5 : Double(k) / Double(count - 1)
                let y = y0 + (y1 - y0) * t + (r() - 0.5) * 20
                let x = W * (0.2 + 0.6 * r())
                c += water(x, y, Double(k) * 2, hei: 2, len: W * (0.9 + 0.6 * r()), clu: 6 + Int(4 * d))
            }
            return c
        }

        switch params.variant {
        case .alpine:
            layers.append((distant(q + 0.15 * H, 130 * s), true))
            // 背后的次峰
            let backCount = d < 0.3 ? 0 : (d < 0.7 ? 1 : 2)
            var backs: ZXArt.SSCanv = []
            for k in 0..<backCount {
                let side: Double = k % 2 == 0 ? (r() < 0.5 ? -1 : 1) : -1
                let x = W * (0.5 + side * (0.28 + 0.12 * r()))
                backs += mountain(x, q + 0.40 * H, r() * 100, hei: (0.20 + 0.08 * r()) * H, wid: (0.55 + 0.2 * r()) * W,
                                  tex: 120 * texScale, veg: true)
            }
            layers.append((waterBand(0.80 * H, 0.97 * H, count: 3), false))
            layers.append((backs, false))
            let mx = W * (0.38 + 0.24 * r())
            layers.append((mountain(mx, 0.80 * H, r() * 100, hei: (0.40 + 0.06 * r()) * H, wid: (0.85 + 0.2 * r()) * W,
                                    tex: 200 * texScale, veg: true), false))
            if d > 0.2 {
                let by = 0.90 * H + r() * 0.05 * H
                layers.append((boat01(W * (0.15 + 0.7 * r()), by, r(), sca: 0.55 * s, fli: e.choice([true, false])), false))
            }
        case .riverbank:
            layers.append((distant(q + 0.14 * H, 110 * s), true))
            let side: Double = r() < 0.5 ? -1 : 1
            layers.append((waterBand(0.66 * H, 0.84 * H, count: 3), false))
            layers.append((mountain(W * (0.5 + side * 0.36), q + 0.36 * H, r() * 100, hei: (0.18 + 0.06 * r()) * H,
                                    wid: 0.7 * W, tex: 150 * texScale, veg: true), false))
            if d > 0.2 {
                layers.append((boat01(W * (0.5 - side * (0.1 + 0.25 * r())), 0.76 * H, r(), sca: 0.6 * s,
                                      fli: side > 0), false))
            }
            let fw = (1.05 + 0.3 * r()) * W
            layers.append((flatMount(W * (0.5 - side * 0.12), 0.93 * H, 2 * r() * Double.pi, hei: 100, wid: fw,
                                     tex: 80 * texScale, cho: 0.5 + r() * 0.2), false))
        case .distant:
            let rows = d < 0.4 ? 2 : 3
            for k in 0..<rows {
                let y = q + (0.12 + 0.11 * Double(k)) * H
                layers.append((distant(y, (90 + 45 * Double(k)) * s), true))
            }
            layers.append((waterBand(0.68 * H, 0.95 * H, count: 2 + Int(2 * d)), false))
            if d > 0.15 {
                layers.append((boat01(W * (0.2 + 0.6 * r()), 0.82 * H, r(), sca: 0.45 * s, fli: e.choice([true, false])), false))
            }
            if d > 0.5 {
                let side: Double = r() < 0.5 ? -1 : 1
                layers.append((flatMount(W * (0.5 + side * 0.42), 0.99 * H, 2 * r() * Double.pi, hei: 100,
                                         wid: 0.7 * W, tex: 60 * texScale, cho: 0.55), false))
            }
        }
        return layers
    }
}

// MARK: - 公开 API

public extension ZXArt {
    /// 山水 (移植 shan-shui-inf)。
    enum ShanShui {
        public enum Variant: String, Sendable, Hashable, Codable, CaseIterable {
            /// 高山: 一座主峰居中偏上, 次峰在后, 下方是水。
            case alpine = "高山"
            /// 江岸: 远山 + 侧面小山 + 前景平岸 (树、石、屋), 中间是江。
            case riverbank = "江岸"
            /// 远山: 两三层远山, 大片水面, 一叶小舟。
            case distant = "远山"
        }

        public struct Params: Sendable, Hashable {
            public var palette: Palette
            /// 0…1: 次峰数量、皴法笔数、水纹与船。
            public var density: Double
            public var variant: Variant
            /// 顶部留白 (画布高度的份额), 给锁屏时钟与诗句。
            public var quietTop: Double
            /// 是否叠原作的纸纹。
            public var paperTexture: Bool

            public init(palette: Palette = .paperInk, density: Double = 0.5, variant: Variant = .alpine,
                        quietTop: Double = 0.32, paperTexture: Bool = true) {
                self.palette = palette
                self.density = density
                self.variant = variant
                self.quietTop = quietTop
                self.paperTexture = paperTexture
            }
        }

        /// 逻辑画布的短边 (原作单位 ≈ CSS 像素)。1206 px 宽的手机约 2.15 px / 单位。
        public static let logicalShortSide: Double = 560

        /// 纯函数: 同一 (seed, size, params) 永远得到同一张画。`size` 只决定长宽比。
        public static func generate(seed: Seed, size: CGSize, params: Params = Params()) -> Drawing {
            let aspect = size.width > 0 && size.height > 0 ? Double(size.height / size.width) : 2
            let W: Double, H: Double
            if aspect >= 1 {
                W = logicalShortSide; H = logicalShortSide * aspect
            } else {
                H = logicalShortSide; W = logicalShortSide / aspect
            }
            let engine = ShanShuiEngine(seed: seed)
            let parts = engine.compose(width: W, height: H, params: params)
            var paper = params.paperTexture ? engine.backgroundPaper() : nil
            paper?.tint = params.palette.ink
            var shapes: [Shape] = []
            shapes.reserveCapacity(parts.reduce(0) { $0 + $1.0.count })
            for (canv, _) in parts { ZXArt.appendShapes(canv, palette: params.palette, into: &shapes) }
            return Drawing(width: W, height: H, background: params.palette.paper, paper: paper,
                           layers: [Layer(shapes: shapes)],
                           quietRect: CGRectCodable(x: 0, y: 0, width: W, height: params.quietTop * H))
        }

        /// 原作网页打开时的第一屏 (3000×800 横卷, 对拍与预览用)。
        public static func originalScene(seed: Seed, palette: Palette = .paperInk) -> Drawing {
            let engine = ShanShuiEngine(seed: seed)
            let canv = engine.originalScene()
            var paper = engine.backgroundPaper()
            paper.tint = palette.ink
            var shapes: [Shape] = []
            ZXArt.appendShapes(canv, palette: palette, into: &shapes)
            // 原作 viewBox: 0 0 3000/1.142 800/1.142
            return Drawing(width: 3000 / 1.142, height: 800 / 1.142, background: palette.paper, paper: paper,
                           layers: [Layer(shapes: shapes)])
        }
    }
}

extension ZXArt {
    /// SSPoly → Shape (灰阶映射到调色板; 透明填充 / 零线宽丢掉)。
    static func appendShapes(_ canv: SSCanv, palette: Palette, into shapes: inout [Shape]) {
        func map(_ c: SSColor?, wash: Bool) -> ZXHex? {
            guard let c, c.a > 0 else { return nil }
            let g = (c.r + c.g + c.b) / 3
            return wash ? palette.mapWash(g, alpha: min(c.a, 1)) : palette.mapGray(g, alpha: min(c.a, 1))
        }
        for p in canv where p.p.count >= 2 {
            let fill = map(p.fil, wash: p.wash)
            let stroke = p.wid > 0 ? map(p.str, wash: p.wash) : nil
            if fill == nil && stroke == nil { continue }
            var pts: [SIMD2<Float>] = []
            pts.reserveCapacity(p.p.count)
            var bad = false
            for v in p.p {
                if !v.x.isFinite || !v.y.isFinite { bad = true; break }
                pts.append(SIMD2<Float>(Float(v.x), Float(v.y)))
            }
            if bad { continue }
            shapes.append(Shape(points: pts, fill: fill, stroke: stroke, lineWidth: Float(p.wid)))
        }
    }
}
