// shanshui@5 painting path. Preserve this version when adding future painting styles.
// Brush vocabulary for shanshui@5. Earlier generators never call these routines.
import CoreGraphics
import Foundation

extension ShanShuiEngine {
    func inkSeed() -> UInt32 { UInt32(r() * 4_294_967_295) }

    enum InkDepth { case far, middle, near }

    /// Keep unpainted paper intact; deepen loaded strokes more than pale washes.
    func paintingInk(_ source: ZXArt.SSCanv, depth: InkDepth) -> ZXArt.SSCanv {
        let factor = depth == .near ? 1.42 : (depth == .middle ? 0.65 : 0.36)
        return source.map { poly in
            var p = poly
            if var c = p.fil, c != .white { c.a = min(0.94, c.a * factor); p.fil = c }
            if var c = p.str, c != .white { c.a = min(0.94, c.a * factor); p.str = c }
            return p
        }
    }

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

    /// Connected terrain: low hemp-fibre shoals, angular cliffs, or a descending corner headland.
    enum BankStyle { case shoal, cliff, headland }

    func paintingBank(style: BankStyle = .headland) -> ZXArt.SSCanv {
        paintingSlope(style)
    }

    func paintingMountain(form: PaintingMountainProfile.Form? = nil, terraced: Bool = false) -> ZXArt.SSCanv {
        paintingMassif(PaintingMountainProfile(form: form, random: { self.r() }), terraced: terraced)
    }

    /// Cloud at the foot of a peak (山腰云锁), painted by leaving paper: stacked paper-coloured
    /// bands with billowing upper edges, thin near the waist and solid at the foot, so the peak
    /// rises out of cloud instead of standing on the bank.
    func paintingCloud(over peak: CGRect) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let top = peak.maxY - peak.height * (0.36 + r() * 0.08), bottom = peak.maxY + peak.height * 0.04
        let x0 = peak.minX - peak.width * 0.08, x1 = peak.maxX + peak.width * 0.08
        let bands = 6
        for k in 0..<bands {
            let t = Double(k) / Double(bands - 1)
            let y = top + (bottom - top) * t * 0.82
            let phase = r() * 6, freq = 0.035 + r() * 0.03
            let edge = (0...60).map { i -> P in
                let u = Double(i) / 60, x = x0 + (x1 - x0) * u
                let billow = abs(sin(x * freq + phase)) * (5 + 6 * (1 - t))
                // The band thins to nothing at both ends, so no straight edge cuts the hills behind.
                let taper = pow(sin(u * .pi), 0.6)
                let rise = (bottom - y) * (1 - taper)
                return P(x, y + rise - billow * taper + 4 * (n(x * 0.02, Double(k)) - 0.5))
            }
            let alpha = k == bands - 1 ? 0.85 : 0.22 + 0.10 * t
            c.append(poly(edge + [P(x1, bottom), P(x0, bottom)], fil: C(255, 255, 255, alpha), str: nil))
        }
        return c
    }

    /// The far bank (对岸) of a river scene, in the manner of Ni Zan: low rounded hills on one
    /// side flattening into a level shore, distant trees as small upright dabs along the crest,
    /// a broken shore line. Pale, because it sits across the water.
    func paintingFarShore() -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let flip = r() < 0.5
        let humps = 2 + Int(r() * 2)
        var tops: [(x: Double, h: Double, w: Double)] = []
        for k in 0..<humps {
            tops.append((x: 0.10 + 0.16 * Double(k) + r() * 0.06, h: 18 + r() * 16 - Double(k) * 4, w: 0.10 + r() * 0.05))
        }
        let ridge = (0...100).map { i -> P in
            let t = Double(i) / 100, u = flip ? 1 - t : t
            var y = 0.0
            for top in tops { y = max(y, top.h * exp(-pow(abs(u - top.x) / top.w, 2))) }
            let shelf = 4 * (n(t * 7, 3) - 0.5)
            return P(t * 300, 56 - y - (u < 0.75 ? 3 : 3 * (1 - (u - 0.75) / 0.25)) + shelf)
        }
        // The body thins to nothing at both ends, so the far bank fades out instead of being cut.
        let base = ridge.enumerated().map { i, p in
            let env = pow(sin(Double(i) / 100 * .pi), 0.45)
            return P(p.x, p.y + max(0.3, (60 - p.y) * env))
        }
        c.append(poly(ridge + base.reversed(), fil: .white, str: nil))
        c.append(poly(ridge + base.reversed(), fil: .gray(0, 0.10), str: nil))
        c += inkLine(ridge, width: 0.8, tone: 0.30, dry: 0.5)
        // Hemp-fibre texture, sparse, on the hill faces only.
        for _ in 0..<26 {
            let i = Int(r() * 100), p = ridge[i]
            guard 56 - p.y > 10 else { continue }
            let len = 4 + r() * (56 - p.y) * 0.5
            c += inkLine([P(p.x, p.y + 2), P(p.x - 1, p.y + 2 + len)], width: 0.5, tone: 0.16, dry: 0.6)
        }
        // Distant trees: clustered upright dabs riding the crest (远树无枝).
        for _ in 0..<(5 + Int(r() * 4)) {
            let i = 5 + Int(r() * 90), p = ridge[i]
            for k in 0..<(2 + Int(r() * 3)) {
                let x = p.x + Double(k) * (2.2 + r()) - 2, height = 4 + r() * 5
                c += inkBlot(x, p.y - height * 0.45, radius: height * 0.5, squash: 0.45, angle: 1.5708, tone: 0.30 + r() * 0.2)
                c += inkLine([P(x, p.y), P(x, p.y - height * 0.3)], width: 0.45, tone: 0.4)
            }
        }
        // Broken shore line at the water.
        var x = 20 + r() * 20
        while x < 260 {
            let run = 18 + r() * 40
            c += inkLine([P(x, 60), P(min(300, x + run), 60 + (r() - 0.5))], width: 0.6, tone: 0.22, dry: 0.55)
            x += run + 8 + r() * 20
        }
        return c
    }

    /// Distant range: a few peaks of unequal height (one leads, the others fall away), with a
    /// readable crest and a body that the mist layer dissolves downward. Not a full-width band.
    func paintingDistant(_ index: Int) -> ZXArt.SSCanv {
        let phase = r() * 12
        let peaks = 2 + Int(r() * 2.5)
        var tops: [(x: Double, h: Double, w: Double)] = []
        for k in 0..<peaks {
            let lead = k == 0
            tops.append((x: 0.18 + 0.64 * (Double(k) + r() * 0.6) / Double(peaks),
                         h: lead ? 52 + r() * 18 : 22 + r() * 22,
                         w: lead ? 0.16 + r() * 0.06 : 0.10 + r() * 0.08))
        }
        let ridge = (0...120).map { i -> P in
            let t = Double(i) / 120
            var y = 0.0
            for top in tops {
                let d = abs(t - top.x) / top.w
                y = max(y, top.h * exp(-pow(d, 1.6)))
            }
            let foot = pow(max(0, sin(t * .pi)), 0.35)
            let wobble = 4 * (n(t * 9 + phase, Double(index) * 2) - 0.5)
            return P(t * 360, 80 - max(1.5, (y + wobble) * foot))
        }
        var c = [poly(ridge + [P(360, 95), P(0, 95)], fil: .gray(0, 0.11 + Double(index) * 0.04), str: nil)]
        c += inkLine(ridge, width: 0.7, tone: 0.18 + Double(index) * 0.06, dry: 0.55)
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
