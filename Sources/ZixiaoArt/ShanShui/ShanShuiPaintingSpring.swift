import Foundation

extension ShanShuiEngine {
    /// 清泉石上流: discontinuous rock lips define the water, never a pair of road edges.
    func paintingRockyStream() -> ZXArt.SSCanv {
        let lean = r() < 0.5 ? -1.0 : 1.0
        let bends = [P(60, 0), P(60 + lean * (14 + r() * 8), 48),
            P(60 - lean * (9 + r() * 12), 105), P(60 + lean * 12, 151), P(60, 205)]
        let center = inkCurve(bends, steps: 10)
        func edge(_ side: Double) -> [P] {
            center.map { p in
                let t = p.y / 205
                return P(p.x + side * (3 + t * 8), p.y)
            }
        }
        var c = [poly(edge(-1) + edge(1).reversed(), fil: .white, str: nil)]
        let count = 3 + Int(r() * 65536) % 2
        for k in 0..<count {
            let t = Double(k) / Double(count)
            let index = min(center.count - 1, Int(t * Double(center.count - 1)))
            let p = center[index]
            let gap = 4 + t * 8
            for side in [-1.0, 1.0] {
                let breadth = 16 + t * 22 + r() * 10
                let inner = p.x + side * gap
                let x0 = side < 0 ? inner - breadth : inner
                c += paintingStone(x0: x0, x1: x0 + breadth,
                    top: p.y + (side < 0 ? 0 : 5 + r() * 10),
                    floor: min(205, p.y + 43 + t * 16 + r() * 13),
                    style: .cliff, rank: 1)
            }
            if k > 0 {
                // A projecting stone interrupts the flow; paper-white water slips over its lip.
                let side = k % 2 == 0 ? -1.0 : 1.0
                let x = p.x + side * gap * 0.4
                let lip = [P(x - gap * 0.7, p.y + 31), P(x, p.y + 29), P(x + gap * 0.6, p.y + 30)]
                c += inkLine(lip, width: 1.2, tone: 0.55, dry: 0.48)
                for j in 0..<2 {
                    let start = P(x + Double(j) * 3, p.y + 32)
                    c += inkLine([start, start + P(-1, 5 + t * 4)], width: 0.7, tone: 0.25, dry: 0.5)
                }
                c += inkLine([P(p.x - gap * 0.5, p.y + 43), P(p.x + gap * 0.4, p.y + 44)],
                    width: 0.8, tone: 0.36, dry: 0.48)
            }
        }
        for j in 0..<3 {
            let y = 187 + Double(j) * 6
            c += inkLine([P(51 - Double(j) * 2, y), P(62 + Double(j) * 3, y + 0.4)],
                width: 0.75, tone: 0.29, dry: 0.55)
        }
        return c
    }
}
