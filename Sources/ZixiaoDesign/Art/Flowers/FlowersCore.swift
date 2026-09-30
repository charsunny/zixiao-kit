//  FlowersCore.swift — 花卉的几何核心: v3 / hsv / leaf / stem / branch
//
//  Ported from nonflowers main.js (v3, rgba, hsv, lerpHue, grot, tubify, stroke, leaf, stem, branch).
//  MIT License, (c) 2018 Lingdong Huang — https://github.com/LingDong-/nonflowers
//  Full license text: ZXArtLicenses.swift / LICENSES/.
//
//  原作把叶片 / 花瓣当成三维带子 (逐段欧拉旋转) 投影到画布, 每段两块四边形, 颜色按法线与
//  光向的夹角取 hsv。这里输出同样的多边形序列 (`FPoly`), 画布上的逐像素处理 (纸纹、fade、
//  wispy 滤镜) 留给渲染器。

import Foundation

extension ZXArt {
    typealias V3 = SIMD3<Double>

    /// nonflowers 的颜色: `rgba(floor r, floor g, floor b, a.toFixed(3))`, 分量可能越界 (画布会夹)。
    struct FColor: Hashable, Sendable {
        var r: Double, g: Double, b: Double, a: Double
    }

    struct FPoly: Sendable {
        var p: [P]
        var col: FColor
        var fil: Bool
        var str: Bool
        /// 0 = lay0 (枝叶, fade + wispy, 正片叠底), 1 = lay1 (花, wispy)。
        var layer: Int
    }

    enum V3Math {
        static let forward = V3(0, 0, 1), up = V3(0, 1, 0), right = V3(1, 0, 0)

        static func rotvec(_ vec: V3, _ axis: V3, _ th: Double) -> V3 {
            let l = axis.x, m = axis.y, n = axis.z
            let x = vec.x, y = vec.y, z = vec.z
            let c = cos(th), s = sin(th)
            let m11 = l * l * (1 - c) + c, m12 = m * l * (1 - c) - n * s, m13 = n * l * (1 - c) + m * s
            let m21 = l * m * (1 - c) + n * s, m22 = m * m * (1 - c) + c, m23 = n * m * (1 - c) - l * s
            let m31 = l * n * (1 - c) - m * s, m32 = m * n * (1 - c) + l * s, m33 = n * n * (1 - c) + c
            return V3(x * m11 + y * m12 + z * m13, x * m21 + y * m22 + z * m23, x * m31 + y * m32 + z * m33)
        }

        static func roteuler(_ v: V3, _ rot: V3) -> V3 {
            var vec = v
            if rot.z != 0 { vec = rotvec(vec, forward, rot.z) }
            if rot.x != 0 { vec = rotvec(vec, right, rot.x) }
            if rot.y != 0 { vec = rotvec(vec, up, rot.y) }
            return vec
        }

        static func mag(_ v: V3) -> Double { (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot() }
        static func dot(_ u: V3, _ v: V3) -> Double { u.x * v.x + u.y * v.y + u.z * v.z }
        static func cross(_ u: V3, _ v: V3) -> V3 {
            V3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
        }
        static func ang(_ u: V3, _ v: V3) -> Double { acos(dot(u, v) / (mag(u) * mag(v))) }
        static func lerp(_ u: V3, _ v: V3, _ p: Double) -> V3 {
            V3(u.x * (1 - p) + v.x * p, u.y * (1 - p) + v.y * p, u.z * (1 - p) + v.z * p)
        }

        /// 5° 网格暴力搜欧拉角 (原作如此)。
        static func toeuler(_ v0: V3) -> V3 {
            let ep = 5.0
            var ma = 2 * Double.pi
            var mr = V3(0, 0, 0)
            let deg2rad = Double.pi / 180
            let lim = ep * deg2rad
            var x = -180.0
            while x < 180 {
                var y = -90.0
                while y < 90 {
                    let r = V3(x * deg2rad, y * deg2rad, 0)
                    let v = roteuler(V3(0, 0, 1), r)
                    let a = ang(v0, v)
                    if a < lim { return r }
                    if a < ma { ma = a; mr = r }
                    y += ep
                }
                x += ep
            }
            return mr
        }
    }

    /// `rgba(r,g,b,a)` 字符串化时的取整。
    static func fcolor(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> FColor {
        FColor(r: r.rounded(.down), g: g.rounded(.down), b: b.rounded(.down), a: toFixed(a, 3))
    }

    /// `hsv(h, s, v, a)`
    static func hsv(_ h: Double, _ s: Double, _ v: Double, _ a: Double) -> FColor {
        let c = v * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let idx = Int((h / 60).rounded(.down))
        let table: [(Double, Double, Double)] = [(c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x)]
        // 原作越界会抛异常 (h 恒在 0…360, 实际不发生); 这里取模兜底。
        let t = table[((idx % 6) + 6) % 6]
        return fcolor((t.0 + m) * 255, (t.1 + m) * 255, (t.2 + m) * 255, a)
    }

    /// `lerpHue(h0, h1, p)` — 绕 360° 取最短方向 (sort 是稳定的: 并列时取靠前的方法)。
    static func lerpHue(_ h0: Double, _ h1: Double, _ p: Double) -> Double {
        let methods: [(Double, Double)] = [
            (abs(h1 - h0), mapval(p, 0, 1, h0, h1)),
            (abs(h1 + 360 - h0), mapval(p, 0, 1, h0, h1 + 360)),
            (abs(h1 - 360 - h0), mapval(p, 0, 1, h0, h1 - 360)),
        ]
        var best = methods[0]
        for m in methods.dropFirst() where m.0 < best.0 { best = m }
        return (best.1 + 720).truncatingRemainder(dividingBy: 360)
    }

    /// 颜色区间 {min:[h,s,v,a], max:[h,s,v,a]}
    struct HSVRange: Sendable, Hashable {
        var min: [Double]
        var max: [Double]
    }
}

/// nonflowers 生成器的状态: 随机源 + 多边形输出 (按调用顺序 = 绘制顺序)。
final class FlowersEngine {
    typealias P = ZXArt.P
    typealias V3 = ZXArt.V3
    let e: ZXArt.Entropy
    var polys: [ZXArt.FPoly] = []
    /// 季节预设改子枝颜色用; nil = 原作 (子枝用 branch 的缺省色)。
    var childColorOverride: ZXArt.HSVRange?

    init(seed: ZXArt.Seed) { e = ZXArt.Entropy(seed: seed) }

    @inline(__always) func r() -> Double { e.random() }
    @inline(__always) func n(_ x: Double, _ y: Double = 0, _ z: Double = 0) -> Double { e.noise(x, y, z) }

    /// `polygon({ctx, pts, xof, yof, col, fil, str})`
    func polygon(_ layer: Int, _ pts: [V3], xof: Double, yof: Double, col: ZXArt.FColor, fil: Bool, str: Bool) {
        polys.append(ZXArt.FPoly(p: pts.map { P($0.x + xof, $0.y + yof) }, col: col, fil: fil, str: str, layer: layer))
    }

    func polygon2(_ layer: Int, _ pts: [P], xof: Double, yof: Double, col: ZXArt.FColor, fil: Bool, str: Bool) {
        polys.append(ZXArt.FPoly(p: pts.map { P($0.x + xof, $0.y + yof) }, col: col, fil: fil, str: str, layer: layer))
    }

    /// `stroke({pts, xof, yof, col, wid})` — 缺省宽度 `sin(xπ)·mapval(noise(10x), 0,1, .5,1)`。
    func stroke(_ layer: Int, _ pts: [P], xof: Double, yof: Double, col: ZXArt.FColor,
                wid: ((Double) -> Double)? = nil) {
        guard pts.count >= 2 else { return }
        let w = wid ?? { x in 1 * sin(x * Double.pi) * ZXArt.mapval(self.n(x * 10), 0, 1, 0.5, 1) }
        let (v0, v1) = ZXArt.tubify(pts, w)
        polygon2(layer, v0 + v1.reversed(), xof: xof, yof: yof, col: col, fil: true, str: false)
    }

    // MARK: leaf

    struct LeafArgs {
        var xof: Double = 0
        var yof: Double = 0
        var rot = V3(Double.pi / 2, 0, 0)
        var len: Double = 500
        var seg: Int = 40
        var wid: (Double) -> Double = { sin($0 * Double.pi) * 20 }
        var vei: [Double] = [1, 3]
        var flo = false
        var col = ZXArt.HSVRange(min: [90, 0.2, 0.3, 1], max: [90, 0.1, 0.9, 1])
        var cof: (Double) -> Double = { $0 }
        var ben: ((Double) -> V3)? = nil
    }

    @discardableResult
    func leaf(_ layer: Int, _ a: LeafArgs) -> [V3] {
        let ben: (Double) -> V3 = a.ben ?? { _ in V3(self.e.normRand(-10, 10), 0, self.e.normRand(-5, 5)) }
        var disp = V3(0, 0, 0)
        var crot = V3(0, 0, 0)
        var P: [V3] = [disp], L: [V3] = [disp], R: [V3] = [disp]
        let orient: (V3) -> V3 = { ZXArt.V3Math.roteuler($0, a.rot) }
        let segD = Double(a.seg)
        for i in 0..<a.seg {
            let p = Double(i) / Double(a.seg - 1)
            let b = ben(p)
            crot = V3(crot.x + b.x * (1 / segD), crot.y + b.y * (1 / segD), crot.z + b.z * (1 / segD))
            let step = orient(ZXArt.V3Math.roteuler(V3(0, 0, a.len / segD), crot))
            disp = V3(disp.x + step.x, disp.y + step.y, disp.z + step.z)
            let w = a.wid(p)
            let lo = orient(ZXArt.V3Math.roteuler(V3(-w, 0, 0), crot))
            let ro = orient(ZXArt.V3Math.roteuler(V3(w, 0, 0), crot))
            let l = V3(disp.x + lo.x, disp.y + lo.y, disp.z + lo.z)
            let rr = V3(disp.x + ro.x, disp.y + ro.y, disp.z + ro.z)
            if i > 0 {
                let lastL = L[L.count - 1], lastP = P[P.count - 1], lastR = R[R.count - 1]
                var lt: Double
                if !a.flo {
                    let v0 = disp - lastL
                    let v1 = l - disp
                    let v2 = ZXArt.V3Math.cross(v0, v1)
                    lt = ZXArt.mapval(abs(ZXArt.V3Math.ang(v2, V3(0, -1, 0))), 0, Double.pi, 1, 0)
                } else {
                    lt = p * e.normRand(0.95, 1)
                }
                lt = a.cof(lt)
                if lt.isNaN || lt == 0 { lt = 0 }
                let h = ZXArt.lerpHue(a.col.min[0], a.col.max[0], lt)
                let s = ZXArt.mapval(lt, 0, 1, a.col.min[1], a.col.max[1])
                let v = ZXArt.mapval(lt, 0, 1, a.col.min[2], a.col.max[2])
                let al = ZXArt.mapval(lt, 0, 1, a.col.min[3], a.col.max[3])
                let c = ZXArt.hsv(h, s, v, al)
                polygon(layer, [l, lastL, lastP, disp], xof: a.xof, yof: a.yof, col: c, fil: true, str: true)
                polygon(layer, [rr, lastR, lastP, disp], xof: a.xof, yof: a.yof, col: c, fil: true, str: true)
            }
            P.append(disp); L.append(l); R.append(rr)
        }
        let black: (Double) -> ZXArt.FColor = { ZXArt.hsv(0, 0, 0, $0) }
        if a.vei.first == 1 {
            let nv = Int(a.vei[1])
            for i in 1..<P.count {
                var j = 0.0
                while j < a.vei[1] {
                    let p = j / a.vei[1]
                    let p0 = ZXArt.V3Math.lerp(L[i - 1], P[i - 1], p), p1 = ZXArt.V3Math.lerp(L[i], P[i], p)
                    let q0 = ZXArt.V3Math.lerp(R[i - 1], P[i - 1], p), q1 = ZXArt.V3Math.lerp(R[i], P[i], p)
                    polygon(layer, [p0, p1], xof: a.xof, yof: a.yof, col: black(e.normRand(0.4, 0.9)), fil: false, str: true)
                    polygon(layer, [q0, q1], xof: a.xof, yof: a.yof, col: black(e.normRand(0.4, 0.9)), fil: false, str: true)
                    j += 1
                }
                _ = nv
            }
            stroke(layer, P.map { P2($0) }, xof: a.xof, yof: a.yof, col: ZXArt.fcolor(0, 0, 0, 0.3))
        } else if a.vei.first == 2 {
            let off = Int(a.vei[1]), step = Int(a.vei[2])
            var i = 1
            while i < P.count - off {
                polygon(layer, [P[i], L[i + off]], xof: a.xof, yof: a.yof, col: black(e.normRand(0.4, 0.9)), fil: false, str: true)
                polygon(layer, [P[i], R[i + off]], xof: a.xof, yof: a.yof, col: black(e.normRand(0.4, 0.9)), fil: false, str: true)
                i += step
            }
            stroke(layer, P.map { P2($0) }, xof: a.xof, yof: a.yof, col: ZXArt.fcolor(0, 0, 0, 0.3))
        }
        stroke(layer, L.map { P2($0) }, xof: a.xof, yof: a.yof, col: ZXArt.fcolor(120, 100, 0, 0.3))
        stroke(layer, R.map { P2($0) }, xof: a.xof, yof: a.yof, col: ZXArt.fcolor(120, 100, 0, 0.3))
        return P
    }

    @inline(__always) private func P2(_ v: V3) -> P { P(v.x, v.y) }

    // MARK: stem

    struct StemArgs {
        var xof: Double = 0
        var yof: Double = 0
        var rot = V3(Double.pi / 2, 0, 0)
        var len: Double = 400
        var seg: Int = 40
        var wid: (Double) -> Double = { _ in 6 }
        var col = ZXArt.HSVRange(min: [250, 0.2, 0.4, 1], max: [250, 0.3, 0.6, 1])
        var ben: ((Double) -> V3)? = nil
    }

    @discardableResult
    func stem(_ layer: Int, _ a: StemArgs) -> [V3] {
        let ben: (Double) -> V3 = a.ben ?? { _ in V3(self.e.normRand(-10, 10), 0, self.e.normRand(-5, 5)) }
        var disp = V3(0, 0, 0)
        var crot = V3(0, 0, 0)
        var P: [V3] = [disp]
        let segD = Double(a.seg)
        for i in 0..<a.seg {
            let p = Double(i) / Double(a.seg - 1)
            let b = ben(p)
            crot = V3(crot.x + b.x * (1 / segD), crot.y + b.y * (1 / segD), crot.z + b.z * (1 / segD))
            let step = ZXArt.V3Math.roteuler(ZXArt.V3Math.roteuler(V3(0, 0, a.len / segD), crot), a.rot)
            disp = V3(disp.x + step.x, disp.y + step.y, disp.z + step.z)
            P.append(disp)
        }
        let (L, R) = ZXArt.tubify(P.map { P2($0) }, a.wid)
        let wseg = 4
        for i in 1..<P.count {
            for j in 1..<wseg {
                let m = Double(j - 1) / Double(wseg - 1)
                let nn = Double(j) / Double(wseg - 1)
                let p = Double(i) / Double(P.count - 1)
                let p0 = L[i - 1] * (1 - m) + R[i - 1] * m
                let p1 = L[i] * (1 - m) + R[i] * m
                let p2 = L[i - 1] * (1 - nn) + R[i - 1] * nn
                let p3 = L[i] * (1 - nn) + R[i] * nn
                let lt = nn / p
                let nz = n(p * 10, m * 10, nn * 10)
                let h = ZXArt.lerpHue(a.col.min[0], a.col.max[0], lt) * ZXArt.mapval(nz, 0, 1, 0.5, 1)
                let s = ZXArt.mapval(lt, 0, 1, a.col.max[1], a.col.min[1]) * ZXArt.mapval(nz, 0, 1, 0.5, 1)
                let v = ZXArt.mapval(lt, 0, 1, a.col.min[2], a.col.max[2]) * ZXArt.mapval(nz, 0, 1, 0.5, 1)
                let al = ZXArt.mapval(lt, 0, 1, a.col.min[3], a.col.max[3])
                polygon2(layer, [p0, p1, p3, p2], xof: a.xof, yof: a.yof, col: ZXArt.hsv(h, s, v, al), fil: true, str: true)
            }
        }
        stroke(layer, L, xof: a.xof, yof: a.yof, col: ZXArt.fcolor(0, 0, 0, 0.5))
        stroke(layer, R, xof: a.xof, yof: a.yof, col: ZXArt.fcolor(0, 0, 0, 0.5))
        return P
    }

    // MARK: branch

    struct BranchArgs {
        var xof: Double = 0
        var yof: Double = 0
        var rot = V3(Double.pi / 2, 0, 0)
        var len: Double = 400
        var seg: Int = 40
        var wid: Double = 1
        var twi: Double = 5
        var col = ZXArt.HSVRange(min: [50, 0.2, 0.8, 1], max: [50, 0.2, 0.8, 1])
        var dep: Double = 3
        var frk: Double = 4
    }

    /// 返回 [(dep, 全局点列)], 先本枝后子枝 (深度优先)。
    func branch(_ layer: Int, _ a: BranchArgs) -> [(Double, [V3])] {
        let segD = Double(a.seg)
        var jnt: [(Double, Double)] = []
        var t = 0.0
        while t < a.twi {
            let pos = (r() * segD).rounded(.down)
            jnt.append((pos, e.normRand(-1, 1)))
            t += 1
        }
        func jntdist(_ x: Double) -> (Double, Double) {
            var m = segD
            var j = 0
            for (i, jt) in jnt.enumerated() {
                let d = abs(x * segD - jt.0)
                if d < m { m = d; j = i }
            }
            return (m, jnt[j].1)
        }
        let wid = a.wid
        let wfun: (Double) -> Double = { x in
            let (m, _) = jntdist(x)
            if m < 1 { return wid * (3 + 5 * (1 - x)) }
            return wid * (2 + 7 * (1 - x) * ZXArt.mapval(self.n(x * 10), 0, 1, 0.5, 1))
        }
        let bfun: (Double) -> V3 = { x in
            let (m, j) = jntdist(x)
            if m < 1 { return V3(0, j * 20, 0) }
            return V3(0, self.e.normRand(-5, 5), 0)
        }
        let P = stem(layer, StemArgs(xof: a.xof, yof: a.yof, rot: a.rot, len: a.len, seg: a.seg, wid: wfun,
                                     col: a.col, ben: bfun))
        var child: [(Double, [V3])] = []
        if a.dep > 0 && a.wid > 0.1 {
            var i = 0.0
            while i < a.frk * r() {
                let ind = Int(e.normRand(1, Double(P.count)).rounded(.down))
                let rr = ZXArt.V3Math.toeuler(P[ind] - P[ind - 1])
                let rot = V3(rr.x + e.normRand(-1, 1) * Double.pi / 6,
                             rr.y + e.normRand(-1, 1) * Double.pi / 6,
                             rr.z + e.normRand(-1, 1) * Double.pi / 6)
                let len = a.len * e.normRand(0.4, 0.6)
                let w = a.wid * e.normRand(0.4, 0.7)
                // 原作子枝不传 col / frk —— 用缺省值 (淡黄枝色, 4 叉)。
                var ca = BranchArgs(xof: a.xof + P[ind].x, yof: a.yof + P[ind].y, rot: rot, len: len,
                                    seg: a.seg, wid: w, twi: a.twi * 0.7, dep: a.dep - 1)
                if let cc = childColorOverride { ca.col = cc }
                child += branch(layer, ca)
                i += 1
            }
        }
        return [(a.dep, P.map { V3($0.x + a.xof, $0.y + a.yof, $0.z) })] + child
    }
}
