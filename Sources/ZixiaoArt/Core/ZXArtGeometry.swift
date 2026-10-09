//  ZXArtGeometry.swift — 两个生成器共用的几何原语
//
//  Ported from shan-shui-inf (PolyTools, Util: midPt / bezmh / triangulate / distance) and
//  nonflowers (tubify ≡ shan-shui Man.expand). MIT License, (c) 2018 Lingdong Huang.
//  Full license text: ZXArtLicenses.swift / LICENSES/.
//
//  浮点运算顺序与原作逐条一致 (a*b/c 与 a*(b/c) 在双精度下不等), 改写时别「化简」。

import Foundation
import ZixiaoColor

extension ZXArt {
    typealias P = SIMD2<Double>

    @inline(__always)
    static func distance(_ p0: P, _ p1: P) -> Double {
        let dx = p0.x - p1.x, dy = p0.y - p1.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// `PolyTools.midPt(plist)` — 逐点 `v/n + acc` 累加 (顺序影响末位)。
    static func midPt(_ plist: [P]) -> P {
        let n = Double(plist.count)
        var acc = P(0, 0)
        for v in plist { acc = P(v.x / n + acc.x, v.y / n + acc.y) }
        return acc
    }

    /// `bezmh(P, w)` — 有理二次 Bézier 串 (shan-shui 2D 版)。
    static func bezmh(_ input: [P], _ w: Double = 1) -> [P] {
        var pts = input
        if pts.count == 2 { pts = [pts[0], midPt([pts[0], pts[1]]), pts[1]] }
        var plist: [P] = []
        guard pts.count >= 3 else { return plist }
        for j in 0..<(pts.count - 2) {
            let p0 = j == 0 ? pts[j] : midPt([pts[j], pts[j + 1]])
            let p1 = pts[j + 1]
            let p2 = j == pts.count - 3 ? pts[j + 2] : midPt([pts[j + 1], pts[j + 2]])
            let pl = 20
            let end = pl + (j == pts.count - 3 ? 1 : 0)
            for i in 0..<end {
                let t = Double(i) / Double(pl)
                let u = pow(1 - t, 2) + 2 * t * (1 - t) * w + t * t
                plist.append(P((pow(1 - t, 2) * p0.x + 2 * t * (1 - t) * p1.x * w + t * t * p2.x) / u,
                               (pow(1 - t, 2) * p0.y + 2 * t * (1 - t) * p1.y * w + t * t * p2.y) / u))
            }
        }
        return plist
    }

    /// `div(plist, reso)` — 折线等分加密。末点原作返回的是原数组元素的引用 (见 barkify 的处理)。
    static func div(_ plist: [P], _ reso: Double) -> [P] {
        var rlist: [P] = []
        let tl = Double(plist.count - 1) * reso
        var i = 0.0
        while i < tl {
            let lastp = plist[Int((i / reso).rounded(.down))]
            let nextp = plist[Int((i / reso).rounded(.up))]
            let p = i.truncatingRemainder(dividingBy: reso) / reso
            rlist.append(P(lastp.x * (1 - p) + nextp.x * p, lastp.y * (1 - p) + nextp.y * p))
            i += 1
        }
        if let last = plist.last { rlist.append(last) }
        return rlist
    }

    /// `Man.expand` / nonflowers `tubify` — 沿折线按宽度函数向两侧偏移, 端点按切线垂直。
    static func tubify(_ pts: [P], _ wfun: (Double) -> Double) -> ([P], [P]) {
        var v0: [P] = [], v1: [P] = []
        let n = pts.count
        guard n >= 2 else { return (v0, v1) }
        v0.reserveCapacity(n); v1.reserveCapacity(n)
        if n > 2 {
            for i in 1..<(n - 1) {
                let w = wfun(Double(i) / Double(n))
                let a1 = atan2(pts[i].y - pts[i - 1].y, pts[i].x - pts[i - 1].x)
                let a2 = atan2(pts[i].y - pts[i + 1].y, pts[i].x - pts[i + 1].x)
                var a = (a1 + a2) / 2
                if a < a2 { a += Double.pi }
                v0.append(P(pts[i].x + w * cos(a), pts[i].y + w * sin(a)))
                v1.append(P(pts[i].x - w * cos(a), pts[i].y - w * sin(a)))
            }
        }
        let l = n - 1
        let a0 = atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x) - Double.pi / 2
        let a1 = atan2(pts[l].y - pts[l - 1].y, pts[l].x - pts[l - 1].x) - Double.pi / 2
        let w0 = wfun(0), w1 = wfun(1)
        v0.insert(P(pts[0].x + w0 * cos(a0), pts[0].y + w0 * sin(a0)), at: 0)
        v1.insert(P(pts[0].x - w0 * cos(a0), pts[0].y - w0 * sin(a0)), at: 0)
        v0.append(P(pts[l].x + w1 * cos(a1), pts[l].y + w1 * sin(a1)))
        v1.append(P(pts[l].x - w1 * cos(a1), pts[l].y - w1 * sin(a1)))
        return (v0, v1)
    }
}

// MARK: - PolyTools.triangulate

extension ZXArt {
    /// `PolyTools.triangulate(plist, {area, convex, optimize})` — 耳切 + 按最长边二分细化。
    static func triangulate(_ plist: [P], area: Double = 100, convex: Bool = false, optimize: Bool = true) -> [[P]] {
        var out: [[P]] = []
        var rest = plist
        // 原作是尾递归 triangulate(cut[1]); 改成循环, 结果顺序相同。
        while true {
            if rest.count <= 3 {
                out += shatter(rest, area, depth: 0)
                return out
            }
            let cut = bestEar(rest, convex: convex, optimize: optimize)
            out += shatter(cut.0, area, depth: 0)
            rest = cut.1
        }
    }

    private static func lineExpr(_ pt0: P, _ pt1: P) -> (Double, Double) {
        let den = pt1.x - pt0.x
        let m = den == 0 ? Double.infinity : (pt1.y - pt0.y) / den
        let k = pt0.y - m * pt0.x
        return (m, k)
    }

    private static func intersect(_ a0: P, _ a1: P, _ b0: P, _ b1: P) -> Bool {
        let le0 = lineExpr(a0, a1)
        let le1 = lineExpr(b0, b1)
        let den = le0.0 - le1.0
        if den == 0 { return false }
        let x = (le1.1 - le0.1) / den
        let y = le0.0 * x + le0.1
        func onSeg(_ p0: P, _ p1: P) -> Bool {
            min(p0.x, p1.x) <= x && x <= max(p0.x, p1.x) && min(p0.y, p1.y) <= y && y <= max(p0.y, p1.y)
        }
        return onSeg(a0, a1) && onSeg(b0, b1)
    }

    private static func ptInPoly(_ pt: P, _ plist: [P]) -> Bool {
        var scount = 0
        for i in 0..<plist.count {
            let np = plist[i != plist.count - 1 ? i + 1 : 0]
            if intersect(plist[i], np, pt, P(pt.x + 999, pt.y + 999)) { scount += 1 }
        }
        return scount % 2 == 1
    }

    private static func lnInPoly(_ l0: P, _ l1: P, _ plist: [P]) -> Bool {
        let ep = 0.01
        let c0 = P(l0.x * (1 - ep) + l1.x * ep, l0.y * (1 - ep) + l1.y * ep)
        let c1 = P(l0.x * ep + l1.x * (1 - ep), l0.y * ep + l1.y * (1 - ep))
        for i in 0..<plist.count {
            let np = plist[i != plist.count - 1 ? i + 1 : 0]
            if intersect(c0, c1, plist[i], np) { return false }
        }
        return ptInPoly(midPt([l0, l1]), plist)
    }

    private static func sidesOf(_ plist: [P]) -> [Double] {
        (0..<plist.count).map { i in
            let pt = plist[i], np = plist[i != plist.count - 1 ? i + 1 : 0]
            return (pow(np.x - pt.x, 2) + pow(np.y - pt.y, 2)).squareRoot()
        }
    }

    private static func areaOf(_ plist: [P]) -> Double {
        let s = sidesOf(plist)
        let a = s[0], b = s[1], c = s[2]
        let h = (a + b + c) / 2
        return (h * (h - a) * (h - b) * (h - c)).squareRoot()
    }

    private static func bestEar(_ plist: [P], convex: Bool, optimize: Bool) -> ([P], [P]) {
        var cuts: [([P], [P])] = []
        for i in 0..<plist.count {
            let pt = plist[i]
            let lp = plist[i != 0 ? i - 1 : plist.count - 1]
            let np = plist[i != plist.count - 1 ? i + 1 : 0]
            var q = plist
            q.remove(at: i)
            if convex || lnInPoly(lp, np, plist) {
                let c = ([lp, pt, np], q)
                if !optimize { return c }
                cuts.append(c)
            }
        }
        var best: ([P], [P]) = (plist, [])
        var bestRatio = 0.0
        for c in cuts {
            let a = areaOf(c.0)
            let per = sidesOf(c.0).reduce(0, +)
            let r = a / per
            if r >= bestRatio { best = c; bestRatio = r }
        }
        return best
    }

    /// 原作无深度上限; 退化 (面积 NaN) 时会无限递归直到 JS 栈溢出。这里设 48 层上限。
    private static func shatter(_ plist: [P], _ a: Double, depth: Int) -> [[P]] {
        if plist.isEmpty { return [] }
        // 少于 3 点时原作同样会无限递归; 这里原样返回。
        if plist.count < 3 || areaOf(plist) < a || depth > 48 { return [plist] }
        let slist = sidesOf(plist)
        var ind = 0
        for (i, x) in slist.enumerated() where x > slist[ind] { ind = i }
        let nind = (ind + 1) % plist.count
        let lind = (ind + 2) % plist.count
        let mid = midPt([plist[ind], plist[nind]])
        return shatter([plist[ind], mid, plist[lind]], a, depth: depth + 1)
            + shatter([plist[lind], plist[nind], mid], a, depth: depth + 1)
    }
}
