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
        // Buildings are separate scene objects with their own scale and ground placement.
        let profile = PaintingMountainProfile(random: { self.r() })
        return paintingLegacy(mountain(140, 420, r() * 80, hei: profile.height,
            wid: profile.width, tex: 240, veg: false, architecture: false, profile: profile), textured: true)
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

/// Large-scale mountain structure, before surface noise and brush texture are applied.
/// The same ridge drives the outline, foothills and texture grid, so folds follow the summit.
struct PaintingMountainProfile {
    enum Form: Int, CaseIterable { case monumental, leaning, rounded, folded, clustered, longRidge }
    let form: Form
    let ridge: [SIMD2<Double>]
    let width: Double
    let height: Double
    let curvature: Double
    let textureLength: Double

    /// These are structural studies, not copies of specific paintings: a broad northern
    /// massif, a leaning crag, rounded southern hills, folded terraces and receding ridges.
    init(form requested: Form? = nil, random: () -> Double) {
        let choice = min(Form.allCases.count - 1, Int(random() * Double(Form.allCases.count)))
        form = requested ?? Form(rawValue: choice)!
        func between(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * random() }
        let control: [SIMD2<Double>]
        let widths: ClosedRange<Double>, heights: ClosedRange<Double>, curves: ClosedRange<Double>
        switch form {
        case .monumental:
            control = [.init(0, 0), .init(0.12, 0.14), .init(0.24, 0.22), .init(0.30, 0.77),
                .init(0.40, 0.96), .init(0.47, 1), .init(0.59, 0.93), .init(0.66, 0.98),
                .init(0.72, 0.76), .init(0.78, 0.70), .init(0.85, 0.17), .init(1, 0)]
            widths = 310...370; heights = 370...470; curves = 0.35...0.60
            textureLength = 0.10
        case .leaning:
            control = [.init(0, 0), .init(0.10, 0.12), .init(0.23, 0.28), .init(0.28, 0.57),
                .init(0.43, 0.64), .init(0.49, 0.82), .init(0.66, 1), .init(0.76, 0.96),
                .init(0.80, 0.72), .init(0.88, 0.25), .init(1, 0)]
            widths = 300...350; heights = 350...460; curves = 0.30...0.60
            textureLength = 0.13
        case .rounded:
            control = [.init(0, 0), .init(0.16, 0.18), .init(0.28, 0.60), .init(0.41, 0.90),
                .init(0.54, 1), .init(0.67, 0.86), .init(0.82, 0.55), .init(0.93, 0.18), .init(1, 0)]
            widths = 360...440; heights = 270...360; curves = 0.85...1
            textureLength = 0.18
        case .folded:
            control = [.init(0, 0), .init(0.10, 0.18), .init(0.16, 0.49), .init(0.26, 0.53),
                .init(0.30, 0.80), .init(0.42, 0.82), .init(0.49, 1), .init(0.59, 0.93),
                .init(0.64, 0.73), .init(0.76, 0.68), .init(0.82, 0.32), .init(1, 0)]
            widths = 330...400; heights = 330...430; curves = 0.15...0.40
            textureLength = 0.08
        case .clustered:
            control = [.init(0, 0), .init(0.12, 0.35), .init(0.18, 0.65), .init(0.27, 0.73),
                .init(0.34, 0.48), .init(0.42, 0.53), .init(0.46, 0.91), .init(0.55, 1),
                .init(0.60, 0.85), .init(0.64, 0.60), .init(0.70, 0.62), .init(0.78, 0.84),
                .init(0.86, 0.77), .init(0.92, 0.35), .init(1, 0)]
            widths = 350...430; heights = 350...460; curves = 0.40...0.70
            textureLength = 0.11
        case .longRidge:
            control = [.init(0, 0), .init(0.12, 0.38), .init(0.22, 0.52), .init(0.34, 0.44),
                .init(0.45, 0.80), .init(0.54, 0.91), .init(0.64, 1), .init(0.75, 0.82),
                .init(0.85, 0.76), .init(0.94, 0.28), .init(1, 0)]
            widths = 430...520; heights = 240...330; curves = 0.70...1
            textureLength = 0.15
        }
        // Move the entire crest and vary each shoulder without scrambling the mountain's anatomy.
        let bias = between(-0.08, 0.08)
        var knots = control.enumerated().map { i, p -> SIMD2<Double> in
            guard i > 0 && i < control.count - 1 else { return p }
            return .init(p.x + bias * sin(p.x * .pi) + between(-0.008, 0.008),
                p.y == 1 ? 1 : min(0.99, max(0, p.y + between(-0.025, 0.025))))
        }
        if random() < 0.5 { knots = knots.reversed().map { .init(1 - $0.x, $0.y) } }
        ridge = knots
        width = between(widths.lowerBound, widths.upperBound)
        height = between(heights.lowerBound, heights.upperBound)
        curvature = between(curves.lowerBound, curves.upperBound)
    }

    /// Shape-preserving cubic interpolation: no extra peaks or overshoot between ridge knots.
    func elevation(at position: Double) -> Double {
        let x = min(1, max(0, position))
        let i = min(ridge.count - 2, max(0, (ridge.firstIndex { $0.x > x } ?? ridge.count - 1) - 1))
        func slope(_ k: Int) -> Double {
            (ridge[k + 1].y - ridge[k].y) / (ridge[k + 1].x - ridge[k].x)
        }
        func tangent(_ k: Int) -> Double {
            if k == 0 { return slope(0) }
            if k == ridge.count - 1 { return slope(k - 1) }
            let a = slope(k - 1), b = slope(k)
            guard a * b > 0 else { return 0 }
            let left = ridge[k].x - ridge[k - 1].x, right = ridge[k + 1].x - ridge[k].x
            let w1 = 2 * right + left, w2 = right + 2 * left
            return (w1 + w2) / (w1 / a + w2 / b)
        }
        let a = ridge[i], b = ridge[i + 1], span = b.x - a.x, t = (x - a.x) / span
        let t2 = t * t, t3 = t2 * t
        let smooth = (2 * t3 - 3 * t2 + 1) * a.y + (t3 - 2 * t2 + t) * span * tangent(i)
            + (-2 * t3 + 3 * t2) * b.y + (t3 - t2) * span * tangent(i + 1)
        return max(0, smooth * curvature + (a.y + (b.y - a.y) * t) * (1 - curvature))
    }
}
