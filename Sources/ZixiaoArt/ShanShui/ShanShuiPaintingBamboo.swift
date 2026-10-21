// shanshui@5: distinct, separated leaf groups and jointed culms.
import Foundation

extension ShanShuiEngine {
    func paintingBamboo() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let form = Int(r() * 65536) % 3, stalks = 3 + Int(r() * 65536) % 3
        let wind = form == 1 ? -24.0 : (form == 2 ? 24.0 : 0)
        for k in 0..<stalks {
            let far = k == 0, x = 20 + Double(k) * 80 / Double(stalks - 1)
            let height = 104 + r() * 59, lean = wind + (r() - 0.5) * 20
            let tone = far ? 0.30 : 0.60 + r() * 0.18
            let joints = 5 + k % 2
            func point(_ t: Double) -> P { P(x + lean * t, 175 - height * t) }
            for j in 0..<joints {
                let t = Double(j) / Double(joints), next = Double(j + 1) / Double(joints)
                c += inkLine([point(t + 0.006), point(next - 0.005)], width: far ? 1.6 : 2.4,
                    tone: tone, dry: 0.28, profile: .even)
                if j > 0 {
                    let p = point(t)
                    c += inkLine([p + P(-2.5, 0.5), p + P(0, -0.4), p + P(2.6, 0.4)],
                        width: 0.9, tone: min(0.90, tone + 0.18), dry: 0.25)
                }
            }
            let clusters = far ? 2 : 3 + k % 2
            for q in 0..<clusters {
                let t = 0.36 + Double(q) * 0.56 / Double(max(1, clusters - 1))
                let base = point(t), side = q % 2 == k % 2 ? -1.0 : 1.0
                let end = base + P(side * (14 + r() * 10), -4 - r() * 7)
                c += inkLine([base, end], width: 0.65, tone: tone, dry: 0.25)
                for b in 0..<(q % 2 == 0 ? 3 : 4) {
                    let root = end + P(side * Double(b) * 1.3, Double(b) * 0.4)
                    let a = -0.45 + Double(b) * 0.51 + (r() - 0.5) * 0.16
                    let length = 13 + r() * 10
                    let tip = root + P(side * cos(a) * length, sin(a) * length + wind * 0.09)
                    c += inkLine([root, (root + tip) / 2 + P(0, 1.2), tip],
                        width: 2.4 + r() * 1.3, tone: tone + 0.05, dry: 0.18, profile: .lens)
                }
            }
        }
        return c
    }

    func paintingGrass() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let count = 2 + Int(r() * 65536) % 4
        for k in 0..<count {
            let root = P(10 + Double(k) * (19 + r() * 8), 22 + r() * 4)
            for j in 0..<(4 + Int(r() * 3)) {
                let spread = (Double(j) - 2) * (2 + r() * 2)
                let tip = root + P(spread, -5 - r() * 11)
                c += inkLine(inkCurve([root, root + P(spread * 0.3, -5), tip]),
                    width: 1.5 + r(), tone: 0.55 + r() * 0.3, dry: 0.35, profile: .cone)
            }
            c += inkLine([root + P(-4, 1), root + P(5, 0)], width: 1.6, tone: 0.75, dry: 0.45)
        }
        return c
    }

    func paintingPineNeedles(_ x: Double, _ y: Double, width: Double, height: Double) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let clusters = 3 + Int(r() * 3)
        for k in 0..<clusters {
            let p = P(x - width * 0.30 + Double(k) * width * 0.60 / Double(clusters - 1),
                y + (r() - 0.4) * height * 0.6)
            let radius = 7 + r() * 7, start = -.pi * (0.92 + r() * 0.12)
            let spread = k % 3 == 0 ? .pi * 1.4 : .pi * 0.95
            for j in 0..<13 {
                let a = start + Double(j) / 12 * spread
                let end = p + P(cos(a), sin(a)) * radius * (0.8 + r() * 0.2)
                c += inkLine([end, p], width: 0.62 + r() * 0.28, tone: 0.52 + r() * 0.3, dry: 0.3)
            }
            c += inkBlot(p.x, p.y, radius: 1.0, squash: 0.5, tone: 0.8)
        }
        return c
    }
}
