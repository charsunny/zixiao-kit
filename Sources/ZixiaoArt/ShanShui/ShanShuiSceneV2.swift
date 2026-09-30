//  ShanShuiSceneV2.swift — shanshui@2: 给诗留一块「诗句框」的构图
//
//  @1 (`compose`, ShanShuiScene.swift) 一字未动。@2 用同一套移植过来的生成器 (山 / 远山 / 平岸 / 水 / 船),
//  构图换成「诗在一侧, 画在另一侧」:
//    - 竖排 (verse_side left / right): 诗句框是一侧的竖栏 (锁屏在时钟区之下)。主峰 / 侧山贴另一侧的外缘,
//      远山只铺在画栏 (两端收尖, 不伸进诗栏); 诗栏之下 (竖幅 / 方幅) 满宽: 矮山、水、船、近岸。
//    - 横排 (verse_side top): 诗句框是时钟区下的一条横带, 画在横带之下满宽 (与 @1 同一种构图)。
//  兜底: 每一段山量出伸进诗栏的最深处, 整段朝画栏平移 (`fit`); 最后仍有点落在诗栏里的笔画 (水纹、船、树梢)
//  整笔去掉 (`cull`)。所以诗句框里基本是空纸。
//
//  随机数从本引擎按固定顺序取 (web 预览 zxart-compose.js 逐行对照)。改动这里任何取数 / 位置都会改变 @2
//  的出图 —— 另开 @3, 保留本函数。

import CoreGraphics
import Foundation

extension ShanShuiEngine {
    /// 构图 @2 (shanshui@2)。`verse.rect` 是单位坐标。
    func composeV2(width W: Double, height H: Double, params: ZXArt.ShanShui.Params,
                   verse: ZXArt.VerseLayout) -> [Part] {
        drawTowers = false
        let d = min(max(params.density, 0), 1)
        let q = min(max(params.quietTop, 0), 0.5) * H
        let wide = W > H * 1.3
        let portrait = H >= W * 1.3
        let texScale = 0.7 + 0.6 * d
        // 诗句框 (逻辑单位) 与让开的距离
        let vx0 = Double(verse.rect.minX) * W, vx1 = Double(verse.rect.maxX) * W
        let vy1 = Double(verse.rect.maxY) * H
        let g = 0.03 * min(W, H)
        // s: 画在哪边。-1 = 画在左 (诗在右), +1 = 画在右 (诗在左), 0 = 画在下 (诗是上方的横带)
        let s: Double
        switch verse.side {
        case .right: s = -1
        case .left: s = 1
        case .top: s = wide ? 1 : 0
        }
        // 画的顶: 横带 → 横带下沿; 竖幅 → 时钟区下沿; 方幅 / 横幅 → 4%
        let top = s == 0 ? vy1 + g : (portrait ? q : 0.04 * H)
        let R = H - top
        // 画栏 [ax0, ax1] (竖栏的另一侧; 横带时满宽)
        let ax0 = s > 0 ? vx1 + g : 0
        let ax1 = s < 0 ? vx0 - g : W
        let aw = ax1 - ax0
        // 禁区: y < ey1 且 x 在诗栏一侧 (竖栏一直到画布边, 横带满宽)
        let ey1 = s == 0 ? top : vy1 + g
        let ex0 = vx0 - g, ex1 = vx1 + g
        // 诗栏之下还有没有地方 (竖幅 / 方幅有; 横幅的竖栏占满高)
        let roomBelow = s == 0 || ey1 < H - 0.15 * R

        func blocked(_ x: Double, _ y: Double) -> Bool {
            guard y < ey1 else { return false }
            if s < 0 { return x > ex0 }
            if s > 0 { return x < ex1 }
            return x > ex0 && x < ex1
        }
        func fy(_ f: Double) -> Double { top + f * R }

        /// 一条横贯的东西 (远山、水纹、船) 在高度 [y0, y1] 上可以铺开的 x 范围: 碰到禁区的高度只铺画栏。
        func span(_ y0: Double, _ y1: Double) -> (Double, Double) {
            (s != 0 && y0 < ey1) ? (ax0, ax1) : (0, W)
        }
        /// 让一段画让开诗栏: 禁区高度内伸进诗栏的最深处, 整段朝画栏一侧平移。
        func fit(_ canv: ZXArt.SSCanv) -> ZXArt.SSCanv {
            guard s != 0 else { return canv }
            var over = 0.0
            for p in canv {
                for v in p.p where v.x.isFinite && v.y.isFinite && v.y < ey1 {
                    over = s < 0 ? max(over, v.x - ex0) : max(over, ex1 - v.x)
                }
            }
            guard over > 0 else { return canv }
            return ShanShuiEngine.shifted(canv, dx: s < 0 ? -over : over, dy: 0)
        }

        var parts: [Part] = []

        /// 远山: 铺满 span 的一条 (满宽时两端各出画 10%; 贴着诗栏的一端收在栏外), 渲染时雾化。
        func distant(_ y: Double, _ hei: Double, peak: Double = 0.9) -> Part {
            let (sa, sb) = span(y - hei, y + 30)
            let xa = sa > 0 ? sa : -0.1 * W
            let xb = sb < W ? sb : 1.1 * W
            let len = max(((xb - xa) / 50).rounded(.down) * 50, 100)
            let start = sa > 0 ? xb - len : xa
            var c = distMount(start, y, r() * 100, hei: hei, len: len)
            // 贴着诗栏的一端: 原作两端收得陡 (sin^0.5), 这里再把最后一段往山脚压平 (smoothstep), 收成细尖
            if sa > 0 || sb < W {
                let lt = min(0.4 * len, 140)
                let end = sa > 0 ? start : start + len
                c = c.map { poly in
                    var q = poly
                    q.p = poly.p.map { v in
                        let t = min(max(abs(v.x - end) / lt, 0), 1)
                        let f = t * t * (3 - 2 * t)
                        return P(v.x, y + (v.y - y) * f)
                    }
                    return q
                }
            }
            return Part(canv: c, mist: .init(depth: hei * 1.1, blur: 1.2, peak: peak, floorY: y + 8, floorDepth: hei * 0.55))
        }
        func waterLines(_ y0: Double, _ y1: Double, count: Int) -> ZXArt.SSCanv {
            var c: ZXArt.SSCanv = []
            for k in 0..<count {
                let t = count == 1 ? 0.5 : Double(k) / Double(count - 1)
                let y = y0 + (y1 - y0) * t + (r() - 0.5) * 10
                let (xa, xb) = span(y - 25, y + 30)
                let sp = xb - xa
                let x = xa + sp * (0.35 + 0.3 * r())
                c += water(x, y, Double(k) * 2, hei: 2, len: sp * (0.3 + 0.2 * r()), clu: 3 + Int(3 * d))
            }
            return c
        }
        func boat(_ y: Double, _ sca: Double) -> ZXArt.SSCanv {
            let (xa, xb) = span(y - 30, y + 10)
            let x = xa + (xb - xa) * (0.25 + 0.5 * r())
            return boat01(x, y, r(), sca: sca, fli: e.choice([true, false]))
        }
        /// 近岸 (同 @1): 平岸 + 一丛同种的树 + 一两块石。`cx` 在画布边上, `inward` 指向画面内侧。
        func bank(_ cx: Double, _ y: Double, wid: Double, inward: Double) -> ZXArt.SSCanv {
            var c = flatMount(cx, y, 2 * r() * Double.pi, hei: 90, wid: wid, tex: 70 * texScale, cho: 0.5 + r() * 0.2,
                              dec: false)
            guard let top = ShanShuiEngine.top(c) else { return c }
            let ground = top + 14
            let species = r() < 0.5 ? 1 : 3
            let count = 2 + Int(r() * (1 + 2 * d))
            let tx0 = cx + inward * wid * (0.06 + 0.06 * r())
            for k in 0..<count {
                let tx = tx0 + inward * Double(k) * (9 + 7 * r())
                let ht = (species == 1 ? 55 : 70) * (0.75 + 0.5 * r())
                if species == 1 {
                    c += tree01(tx, ground + 4 * r(), hei: ht, wid: 2 + 2 * r(), col: .ink(0.45 + 0.15 * r()))
                } else {
                    let bc = r() * 0.08
                    c += tree03(tx, ground + 4 * r(), hei: ht, ben: { pow($0 * bc, 1) }, col: .ink(0.35 + 0.1 * r()))
                }
            }
            let rocks = 1 + (r() < 0.4 ? 1 : 0)
            for k in 0..<rocks {
                let rx = cx + inward * wid * (0.26 + 0.08 * Double(k) + 0.05 * r())
                c += rock(rx, ground + 6, r() * 100, hei: 10 + 8 * r(), wid: 14 + 10 * r(), sha: 2)
            }
            return c
        }

        // 主体贴哪条边: 竖栏时 = 画栏一侧; 横带时随机 (同 @1)。
        // mx(f): 从主体一侧的画布边往里 f 个画栏宽; ox(f): 从对侧往里 f —— 诗栏之下 (有地方时) 或画栏内缘。
        let m: Double = s != 0 ? s : (r() < 0.5 ? -1 : 1)
        let bw = s != 0 ? aw : W
        func mx(_ f: Double) -> Double { m < 0 ? f * bw : W - f * bw }
        func ox(_ f: Double) -> Double {
            if roomBelow { return m < 0 ? W - f * W : f * W }
            return m < 0 ? ax1 - f * aw : ax0 + f * aw
        }

        switch params.variant {
        case .alpine:
            parts.append(distant(fy(0.20), 60))
            let backCount = d < 0.25 ? 0 : (d < 0.7 ? 1 : 2)
            var backs: ZXArt.SSCanv = []
            // 竖栏且诗栏下有地方: 先画诗句下的矮山 (画面两边才平衡), 再画外缘的次峰
            let lowFirst = s != 0 && roomBelow
            for k in 0..<backCount {
                if (k == 0) != lowFirst {
                    // 主峰后、贴外缘的次峰
                    let bx = mx(0.12 + 0.08 * r())
                    let hei = (0.5 + 0.15 * r()) * R
                    let wid = (0.6 + 0.2 * r()) * bw
                    let b = mountain(bx, fy(0.6), r() * 100, hei: hei, wid: wid, tex: 150 * texScale)
                    backs += fit(placed(b, topY: fy(0.12 + 0.08 * r())))
                } else {
                    // 对侧一座矮山 (竖栏时在诗句之下)
                    let bx = ox(0.2 + 0.08 * r())
                    let b = mountain(bx, fy(0.75), r() * 100, hei: 0.3 * R, wid: 0.55 * bw, tex: 120 * texScale)
                    backs += fit(placed(b, topY: max(fy(0.30 + 0.08 * r()), roomBelow ? ey1 + 0.02 * R : 0)))
                }
            }
            parts.append(Part(canv: backs))
            let cx = mx(0.45 + 0.1 * r())
            let hei = (0.9 + 0.2 * r()) * R
            let wid = (0.95 + 0.25 * r()) * bw
            let m0 = mountain(cx, fy(0.75), r() * 100, hei: hei, wid: wid, tex: 220 * texScale)
            let main = fit(placed(m0, topY: fy(0.03 + 0.05 * r())))
            // 水从主峰山脚 (实测) 往下铺, 画在山的下面。
            let base = min(ShanShuiEngine.bottom(main) ?? fy(0.8), H - 0.12 * R)
            parts.append(Part(canv: waterLines(base - 0.02 * R, H - 0.03 * R, count: 2 + Int(3 * d))))
            parts.append(Part(canv: main))
            if d > 0.2 { parts.append(Part(canv: boat(fy(0.90 + 0.06 * r()), 0.6))) }
        case .riverbank:
            parts.append(distant(fy(0.16), 55))
            let hei = (0.55 + 0.15 * r()) * R
            let m1 = mountain(mx(0.3), fy(0.45), r() * 100, hei: hei, wid: s != 0 ? 1.2 * aw : 0.8 * W,
                              tex: 160 * texScale)
            parts.append(Part(canv: fit(placed(m1, topY: fy(0.10 + 0.08 * r())))))
            if d > 0.45 {
                let m2 = mountain(ox(0.08), fy(0.5), r() * 100, hei: 0.35 * R, wid: 0.55 * bw, tex: 100 * texScale,
                                  veg: true)
                parts.append(Part(canv: fit(placed(m2, topY: max(fy(0.30 + 0.06 * r()), roomBelow ? ey1 + 0.02 * R : 0)))))
            }
            parts.append(Part(canv: waterLines(fy(0.55), fy(0.74), count: 2 + Int(2 * d))))
            if d > 0.2 { parts.append(Part(canv: boat(fy(0.64), 0.55))) }
            // 近岸在主山的对侧下角 (横幅的竖栏占满高时, 贴主山一侧的外缘)
            let bwid = (0.75 + 0.15 * r()) * bw
            if roomBelow {
                parts.append(Part(canv: bank(m < 0 ? W : 0, fy(0.95), wid: bwid, inward: m)))
            } else {
                parts.append(Part(canv: bank(m < 0 ? 0 : W, fy(0.95), wid: bwid, inward: -m)))
            }
        case .distant:
            let rows = d < 0.4 ? 2 : 3
            // 竖栏且诗栏下空间够 (≥ 30% 画高): 第一层在画栏 (收尖), 其余几层压低到诗句之下, 满宽
            let below = s != 0 && H - ey1 > 0.3 * R
            var waterTop = fy(0.62)
            var lastY = 0.0
            for k in 0..<rows {
                let fk = Double(k)
                if below && k > 0 {
                    let hei = (80 + 35 * fk) * 0.7
                    let y = max(k == 1 ? 0 : lastY + 0.06 * R, ey1 + hei + 0.01 * R)
                    lastY = y
                    parts.append(distant(y, hei, peak: 0.5 + 0.22 * fk))
                    waterTop = max(waterTop, y + 0.04 * R)
                } else {
                    parts.append(distant(fy(0.14 + 0.13 * fk), 80 + 35 * fk, peak: 0.5 + 0.22 * fk))
                }
            }
            parts.append(Part(canv: waterLines(waterTop, max(fy(0.92), waterTop + 0.05 * R), count: 2 + Int(2 * d))))
            if d > 0.15 { parts.append(Part(canv: boat(max(fy(0.72 + 0.1 * r()), waterTop + 0.03 * R), 0.5))) }
            if d > 0.5 {
                parts.append(Part(canv: bank(m < 0 ? 0 : W, fy(0.97), wid: 0.7 * bw, inward: -m)))
            }
        }

        // 兜底: 仍有点落在禁区里的笔画整笔去掉。
        return parts.map { part in
            var p = part
            p.canv = part.canv.filter { poly in !poly.p.contains { v in v.x.isFinite && v.y.isFinite && blocked(v.x, v.y) } }
            return p
        }
    }
}
