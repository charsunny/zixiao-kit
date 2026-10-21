//  ShanShuiPrimitives.swift — 山水的笔触原语: poly / stroke / blob / texture
//
//  Ported from shan-shui-inf index.html (<script id="Util">, stroke, blob, div, texture).
//  MIT License, (c) 2018 Lingdong Huang — https://github.com/LingDong-/shan-shui-inf
//  Full license text: ZXArtLicenses.swift / LICENSES/.
//
//  原作每个函数返回一段 SVG 字符串, 字符串拼接的先后就是绘制先后。这里返回 `SSCanv`
//  (多边形数组), 拼接语义完全相同 —— 包括「先算后画」的地方 (例如 tree03 先生成叶簇、
//  后把树干放在前面)。随机数的消耗顺序 = JS 的求值顺序 (参数从左到右、对象字面量按键序、
//  `&&` / `||` 短路)。

import Foundation
import ZixiaoColor

extension ZXArt {
    /// 原作的 CSS 颜色, 0…255 + alpha。山水全是灰阶 (r == g == b)。
    struct SSColor: Hashable, Sendable {
        var r: Double, g: Double, b: Double, a: Double
        init(_ r: Double, _ g: Double, _ b: Double, _ a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }
        static func gray(_ v: Double, _ a: Double) -> SSColor { SSColor(v, v, v, a) }
        static let white = SSColor(255, 255, 255, 1)
        static let clear = SSColor(0, 0, 0, 0)
        /// `"rgba(100,100,100," + x.toFixed(3) + ")"`
        static func ink(_ alpha: Double, digits: Int = 3) -> SSColor { .gray(100, ZXArt.toFixed(alpha, digits)) }
    }

    /// 一个 `<polyline>`。`fil`/`str` 为 nil 表示 "none"。
    struct SSPoly: Sendable {
        var p: [P]
        var fil: SSColor?
        var str: SSColor?
        var wid: Double
        /// 远山的灰走淡墨映射。
        var wash: Bool = false
        /// @3 只附带画法; p 仍是 @2 的构图 / fit / cull / 锚点几何。
        var paintV3: SSPaintV3? = nil
    }

    typealias SSCanv = [SSPoly]
}

/// 山水生成器的状态: 一个随机源 + 原作 MEM 里跨 chunk 的规划矩阵。单线程、一次性。
final class ShanShuiEngine {
    typealias P = ZXArt.P
    typealias C = ZXArt.SSColor
    let e: ZXArt.Entropy
    /// `MEM.planmtx` (键可为负; 缺省为 JS 的 undefined → nil)。
    var planmtx: [Int: Double] = [:]
    var memXmin: Double = 0
    var memXmax: Double = 0
    let cwid: Double = 512
    /// 构图开关: 不画电塔 (原作彩蛋, 对「画屏」不合适)。关掉时仍按原作消耗随机数。
    var drawTowers = true
    /// 意象锚点的记录开关 (@1 / @2 构图用, 见 ShanShuiAnchors.swift)。关掉时 `composeV2` 与 `mountain()` 的行为不变,
    /// 只是不记 —— 单测拿它对照「记录不改变出图」。
    var recordsAnchors = true
    /// Winter scenes: rock texture is painted lighter so slope tops read as snow left in paper.
    var snowLight = 1.0
    /// `mountain()` 生成时记下的树 / 屋 (山的原始坐标; composeV2 随山的平移换算后取走)。nil = 不记 (原作第一屏)。
    var anchorLog: [ZXArt.AnchorPiece]?
    /// 构图 (`compose` / `composeV2`) 记下的东西, 已是最终位置 (逻辑坐标)。
    var anchorPieces: [ZXArt.AnchorPiece] = []

    init(seed: ZXArt.Seed) { e = ZXArt.Entropy(seed: seed) }

    @inline(__always) func r() -> Double { e.random() }
    @inline(__always) func n(_ x: Double, _ y: Double = 0, _ z: Double = 0) -> Double { e.noise(x, y, z) }

    // MARK: poly

    /// `poly(plist, {xof, yof, fil, str, wid})` — fil 缺省 rgba(0,0,0,0), str 缺省 = fil。
    /// Swift 里 `str` 必须显式给出 (nil = "none"); 原作「缺省 = fil」的调用点照抄成 `str: fil`。
    func poly(_ plist: [P], xof: Double = 0, yof: Double = 0, fil: C? = .clear, str: C?, wid: Double = 0) -> ZXArt.SSPoly {
        let s: C? = str
        let pts: [P]
        if xof == 0 && yof == 0 { pts = plist } else { pts = plist.map { P($0.x + xof, $0.y + yof) } }
        return ZXArt.SSPoly(p: pts, fil: fil, str: s, wid: wid)
    }

    // MARK: stroke

    static let sinFun: @Sendable (Double) -> Double = { sin($0 * Double.pi) }

    /// `stroke(ptlist, {xof, yof, wid, col, noi, out, fun})`
    func stroke(_ ptlist: [P], xof: Double = 0, yof: Double = 0, wid: Double = 2,
                col: C = C(200, 200, 200, 0.9), noi: Double = 0.5, out: Double = 1,
                fun: (Double) -> Double = ShanShuiEngine.sinFun) -> ZXArt.SSCanv {
        if ptlist.isEmpty { return [] }
        let n0 = r() * 10
        let cnt = ptlist.count
        var v0: [P] = [], v1: [P] = []
        if cnt > 2 {
            v0.reserveCapacity(cnt); v1.reserveCapacity(cnt)
            for i in 1..<(cnt - 1) {
                var w = wid * fun(Double(i) / Double(cnt))
                w = w * (1 - noi) + w * noi * n(Double(i) * 0.5, n0)
                let a1 = atan2(ptlist[i].y - ptlist[i - 1].y, ptlist[i].x - ptlist[i - 1].x)
                let a2 = atan2(ptlist[i].y - ptlist[i + 1].y, ptlist[i].x - ptlist[i + 1].x)
                var a = (a1 + a2) / 2
                if a < a2 { a += Double.pi }
                v0.append(P(ptlist[i].x + w * cos(a), ptlist[i].y + w * sin(a)))
                v1.append(P(ptlist[i].x - w * cos(a), ptlist[i].y - w * sin(a)))
            }
        }
        var vtx: [P] = []
        vtx.reserveCapacity(v0.count + v1.count + 3)
        vtx.append(ptlist[0])
        vtx += v0
        vtx.append(ptlist[cnt - 1])
        vtx += v1.reversed()
        vtx.append(ptlist[0])
        return [poly(xof == 0 && yof == 0 ? vtx : vtx.map { P($0.x + xof, $0.y + yof) }, fil: col, str: col, wid: out)]
    }

    // MARK: blob

    static let blobFun: @Sendable (Double) -> Double = { x in
        x <= 1 ? pow(sin(x * Double.pi), 0.5) : -pow(sin((x + 1) * Double.pi), 0.5)
    }

    /// `blob(x, y, {len, wid, ang, col, noi, ret:1, fun})` 的点列。
    func blobPoints(_ x: Double, _ y: Double, len: Double = 20, wid: Double = 5, ang: Double = 0,
                    noi: Double = 0.5, fun: (Double) -> Double = ShanShuiEngine.blobFun) -> [P] {
        let reso = 20.0
        var lalist: [(Double, Double)] = []
        lalist.reserveCapacity(21)
        for i in 0...20 {
            let p = (Double(i) / reso) * 2
            let xo = len / 2 - abs(p - 1) * len
            let yo = (fun(p) * wid) / 2
            lalist.append(((xo * xo + yo * yo).squareRoot(), atan2(yo, xo)))
        }
        var nslist: [Double] = []
        nslist.reserveCapacity(21)
        let n0 = r() * 10
        for i in 0...20 { nslist.append(n(Double(i) * 0.05, n0)) }
        ZXArt.loopNoise(&nslist)
        var plist: [P] = []
        plist.reserveCapacity(21)
        for i in 0..<lalist.count {
            let ns = nslist[i] * noi + (1 - noi)
            plist.append(P(x + cos(lalist[i].1 + ang) * lalist[i].0 * ns,
                           y + sin(lalist[i].1 + ang) * lalist[i].0 * ns))
        }
        return plist
    }

    /// `blob(x, y, {…})` (ret = 0): 一个填充多边形。
    func blob(_ x: Double, _ y: Double, len: Double = 20, wid: Double = 5, ang: Double = 0,
              col: C = C(200, 200, 200, 0.9), noi: Double = 0.5,
              fun: (Double) -> Double = ShanShuiEngine.blobFun) -> ZXArt.SSCanv {
        [poly(blobPoints(x, y, len: len, wid: wid, ang: ang, noi: noi, fun: fun), fil: col, str: col, wid: 0)]
    }

    // MARK: texture

    /// `texture(ptlist, {xof, yof, tex, wid, len, sha, noi, col, dis})` (ret = 0)。
    func texture(_ ptlist: [[P]], xof: Double = 0, yof: Double = 0, tex: Double = 400, wid: Double = 1.5,
                 len: Double = 0.2, sha: Double = 0,
                 noi: (Double) -> Double = { 30 / $0 },
                 col: ((Double) -> C)? = nil,
                 dis: (() -> Double)? = nil) -> ZXArt.SSCanv {
        let colF: (Double) -> C = col ?? { _ in C.ink(self.r() * 0.3) }
        let disF: () -> Double = dis ?? {
            if self.r() > 0.5 { return (1.0 / 3) * self.r() } else { return (1.0 * 2) / 3 + (1.0 / 3) * self.r() }
        }
        let reso0 = ptlist.count, reso1 = ptlist[0].count
        var texlist: [[P]] = []
        var i = 0.0
        while i < tex {
            let mid = ZXArt.or0(disF() * Double(reso1))
            let hlen = Int((r() * (Double(reso1) * len)).rounded(.down))
            let start = min(max(mid - hlen, 0), reso1)
            let end = min(max(mid + hlen, 0), reso1)
            let layer = (i / tex) * Double(reso0 - 1)
            var row: [P] = []
            if start < end {
                row.reserveCapacity(end - start)
                let lf = Int(layer.rounded(.down)), lc = Int(layer.rounded(.up))
                let p = layer - layer.rounded(.down)
                for j in start..<end {
                    let x = ptlist[lf][j].x * p + ptlist[lc][j].x * (1 - p)
                    let y = ptlist[lf][j].y * p + ptlist[lc][j].y * (1 - p)
                    let nx = noi(layer + 1) * (n(x, Double(j) * 0.5) - 0.5)
                    let ny = noi(layer + 1) * (n(y, Double(j) * 0.5) - 0.5)
                    row.append(P(x + nx, y + ny))
                }
            }
            texlist.append(row)
            i += 1
        }
        var canv: ZXArt.SSCanv = []
        func off(_ l: [P]) -> [P] { l.map { P($0.x + xof, $0.y + yof) } }
        if sha != 0 {
            var j = 0
            while j < texlist.count {
                canv += stroke(off(texlist[j]), wid: sha, col: .gray(100, 0.1))
                j += 1 + 1
            }
        }
        var j = Int(sha)
        let step = 1 + Int(sha)
        while j < texlist.count {
            let c = colF(Double(j) / Double(texlist.count))
            canv += stroke(off(texlist[j]), wid: wid, col: c)
            j += step
        }
        return canv
    }
}

extension ZXArt {
    /// `loopNoise(nslist)` — 首尾接平后归一到 0…1。
    static func loopNoise(_ ns: inout [Double]) {
        let count = ns.count
        let dif = ns[count - 1] - ns[0]
        var lo = 100.0, hi = -100.0
        for i in 0..<count {
            ns[i] += (dif * Double(count - 1 - i)) / Double(count - 1)
            if ns[i] < lo { lo = ns[i] }
            if ns[i] > hi { hi = ns[i] }
        }
        for i in 0..<count { ns[i] = mapval(ns[i], lo, hi, 0, 1) }
    }
}
