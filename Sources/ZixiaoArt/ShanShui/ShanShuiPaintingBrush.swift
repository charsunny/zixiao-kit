// shanshui@5 painting path. Preserve this version when adding future painting styles.
// Brush vocabulary for shanshui@5. Earlier generators never call these routines.
import Foundation

extension ShanShuiEngine {
    func inkSeed() -> UInt32 { UInt32(r() * 4_294_967_295) }

    /// Loaded centre, irregular pressure, split hairs and a drying tail.
    func inkLine(_ points: [P], width: Double = 1.5, tone: Double = 0.65,
                 dry: Double = 0.28, profile: ZXArt.Brush.Profile = .brush) -> ZXArt.SSCanv {
        guard points.count > 1 else { return [] }
        let seed = inkSeed()
        let path = points.enumerated().map { index, p in
            SIMD3(p.x, p.y, 0.78 + 0.22 * sin(Double(index) * 0.73 + 0.5))
        }
        let style = ZXArt.Brush.Style(width: width, tone: tone, dry: dry, side: 0.45,
            bristles: width > 3 ? 3 : 1, rough: 0.32, fade: 0.22, profile: profile)
        let stroke = ZXArt.Brush.stroke(path, style: style, seed: seed)
        var result: ZXArt.SSCanv = []
        if stroke.body.count > 2 {
            result.append(poly(inkSimplified(stroke.body.map { P(Double($0.x), Double($0.y)) }),
                fil: .gray(0, Double(stroke.bodyAlphaStart + stroke.bodyAlphaEnd) / 2), str: nil))
        }
        for hair in stroke.bristles {
            for run in hair.runs {
                result.append(poly(inkSimplified(run.map { P(Double($0.x), Double($0.y)) }),
                    fil: nil, str: .gray(0, Double(hair.alpha)), wid: Double(hair.width)))
            }
        }
        return result
    }

    /// Error-bounded simplification in asset units (subpixel after placement).
    /// Pressure extrema and broken-hair endpoints survive; oversampled straight runs do not.
    private func inkSimplified(_ points: [P], tolerance: Double = 0.08) -> [P] {
        guard points.count > 3 else { return points }
        var keep = Set([0, points.count - 1]), work = [(0, points.count - 1)]
        while let (lo, hi) = work.popLast() {
            guard hi > lo + 1 else { continue }
            let a = points[lo], b = points[hi], dx = b.x - a.x, dy = b.y - a.y
            let length = dx * dx + dy * dy
            var maximum = tolerance * tolerance, selected: Int?
            for i in (lo + 1)..<hi {
                let p = points[i]
                let t = length > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length)) : 0
                let ex = p.x - a.x - dx * t, ey = p.y - a.y - dy * t, distance = ex * ex + ey * ey
                if distance > maximum { maximum = distance; selected = i }
            }
            if let selected { keep.insert(selected); work.append((lo, selected)); work.append((selected, hi)) }
        }
        return keep.sorted().map { points[$0] }
    }

    /// Architectural corners retain their joints; a single spline would round them into icons.
    func inkEdges(_ points: [P], width: Double = 1.5, tone: Double = 0.65, dry: Double = 0.35) -> ZXArt.SSCanv {
        zip(points, points.dropFirst()).flatMap { a, b in inkLine([a, b], width: width, tone: tone, dry: dry) }
    }

    func inkBlot(_ x: Double, _ y: Double, radius: Double, squash: Double = 0.65,
                 angle: Double = 0, tone: Double = 0.55) -> ZXArt.SSCanv {
        let points = ZXArt.Brush.blot(center: SIMD2(x, y), radius: radius,
            squash: squash, angle: angle, seed: inkSeed())
        return [poly(inkSimplified(points.map { P(Double($0.x), Double($0.y)) }), fil: .gray(0, tone), str: nil)]
    }

    func inkCurve(_ points: [P], steps: Int = 6) -> [P] {
        guard points.count > 2 else { return points }
        var result: [P] = []
        for i in 0..<(points.count - 1) {
            let a = points[max(0, i - 1)], b = points[i]
            let c = points[i + 1], d = points[min(points.count - 1, i + 2)]
            for k in 0..<steps {
                let t = Double(k) / Double(steps), t2 = t * t, t3 = t2 * t
                func q(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                    0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                result.append(P(q(a.x, b.x, c.x, d.x), q(a.y, b.y, c.y, d.y)))
            }
        }
        result.append(points.last!)
        return result
    }

    /// Faceted rock masses, broken hemp-fibre texture and clustered moss dots.
    func paintingRock(width: Double = 125, height: Double = 70, tone: Double = 1) -> ZXArt.SSCanv {
        paintingLegacy(rock(width / 2, height, r() * 40, hei: height, wid: width, tex: 70, sha: 3), textured: true).map { p in
            var q = p
            if var c = q.fil, c != .white { c.a *= tone; q.fil = c }
            if var c = q.str { c.a *= tone; q.str = c }
            return q
        }
    }

    func paintingBank() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for (x, y, width, height) in [(112.0, 29.0, 140.0, 65.0), (10, 38, 120, 73), (58, 50, 110, 61), (215, 48, 95, 45)] {
            c += paintingRock(width: width, height: height, tone: 0.85).map { poly in
                var p = poly; p.p = poly.p.map { P($0.x + x, $0.y + y) }; return p
            }
        }
        return c
    }

    func paintingMountain() -> ZXArt.SSCanv {
        paintingLegacy(mountain(140, 420, r() * 80, hei: 420, wid: 280, tex: 240, veg: false), textured: true)
    }

    func paintingDistant(_ index: Int) -> ZXArt.SSCanv {
        let phase = r() * 12
        let ridge = (0...100).map { i -> P in
            let t = Double(i) / 100
            let envelope = pow(max(0, sin(t * .pi)), 0.6)
            let peak = 12 + 28 * n(t * 6 + phase, Double(index) * 2) + 13 * sin(t * 15 + phase)
            return P(t * 360, 70 - max(3, peak) * envelope)
        }
        var c = [poly(ridge + [P(360, 95), P(0, 95)], fil: .gray(0, 0.10 + Double(index) * 0.025), str: nil)]
        c += inkLine(ridge, width: 0.8, tone: 0.15, dry: 0.6)
        return c
    }
}
