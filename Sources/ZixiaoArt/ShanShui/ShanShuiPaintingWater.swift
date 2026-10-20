// Water is drawn by its banks, current and broken reflections; paper supplies the light.
import Foundation

enum PaintingWaterKind: String, CaseIterable {
    case lake, pond, river, sea
}

/// A single channel controls both banks and every flow mark. It widens toward the viewer.
struct PaintingWaterChannel {
    let width: Double
    let height: Double
    let phase: Double
    let broad: Bool

    func point(_ t: Double, across: Double) -> ZXArt.P {
        let half = width * (0.035 + (broad ? 0.39 : 0.20) * pow(t, 0.85))
        let sway = width * (broad ? 0.11 : 0.23) * sin(t * .pi * 2 + phase)
        let center = min(width - half - width * 0.025, max(half + width * 0.025, width * 0.5 + sway))
        return .init(center + half * across, height * t)
    }

    var left: [ZXArt.P] { (0...40).map { point(Double($0) / 40, across: -1) } }
    var right: [ZXArt.P] { (0...40).map { point(Double($0) / 40, across: 1) } }
}

extension ShanShuiEngine {
    func paintingChannel(width: Double, height: Double, river: Bool = false) -> ZXArt.SSCanv {
        let channel = PaintingWaterChannel(width: width, height: height, phase: r() * 1.2, broad: river)
        let left = channel.left, right = channel.right
        // The unpainted water cuts through the rock bed rather than becoming another rock contour.
        var c = [poly(left + right.reversed(), fil: .white, str: nil)]
        for bank in [left, right] {
            for start in stride(from: 0, to: 36, by: 9) {
                let segment = Array(bank[start...min(start + 7, 40)])
                c += inkLine(segment, width: river ? 2.8 : 3.2, tone: 0.08, dry: 0.35)
                c += inkLine(segment, width: river ? 0.9 : 1.2, tone: 0.38, dry: 0.42)
            }
        }
        // Longitudinal currents bend with the channel. Short transverse marks signal shallow riffles.
        for lane in river ? [0.08] : [-0.55, 0.08, 0.55] {
            for start in [0.14, 0.46, 0.74] {
                let points = (0...9).map { channel.point(start + Double($0) * 0.017, across: lane) }
                c += inkLine(points, width: 0.65, tone: river ? 0.12 : 0.30, dry: 0.55)
            }
        }
        for i in 0..<10 {
            let t = 0.18 + Double(i) * 0.075
            let a = channel.point(t, across: i % 2 == 0 ? -0.7 : -0.1)
            let b = channel.point(t, across: i % 2 == 0 ? 0.1 : 0.7)
            c += inkLine([a, P((a.x + b.x) / 2, a.y + 1.1), b], width: 0.65, tone: 0.22, dry: 0.6)
        }
        if !river {
            // A few stones sit outside the flow, with the current breaking around their toes.
            for (t, side) in [(0.32, -1.0), (0.57, 1.0), (0.81, -1.0)] {
                let p = channel.point(t, across: side)
                let size = width * (0.055 + t * 0.035)
                let stone = [P(p.x, p.y), P(p.x + side * size * 0.55, p.y - size * 0.7),
                    P(p.x + side * size * 1.4, p.y - size * 0.6), P(p.x + side * size * 1.7, p.y + 1)]
                c.append(poly(stone, fil: .white, str: nil))
                c += inkEdges(stone, width: 0.9, tone: 0.40)
            }
        }
        return c
    }

    func paintingSurface(_ kind: PaintingWaterKind, width: Double = 320, height: Double = 140) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let rows = kind == .sea ? 12 : (kind == .pond ? 9 : 12)
        for row in 0..<rows {
            let t = Double(row + 1) / Double(rows + 1)
            let y = height * (0.04 + 0.90 * pow(t, 1.55))
            let count = kind == .sea ? 3 : 2
            for group in 0..<count {
                let span = width * (0.10 + 0.24 * t) * (0.7 + r() * 0.55)
                let x = (Double(group) + 0.12 + r() * 0.48) / Double(count) * (width - span)
                let amplitude = kind == .sea ? height * (0.002 + 0.022 * t * t) : height * 0.003
                let points = (0...14).map { i -> P in
                    let u = Double(i) / 14
                    let lift = kind == .sea ? sin(u * .pi * 2) + 0.35 * sin(u * .pi * 4) : sin(u * .pi)
                    return P(x + span * u, y + amplitude * lift)
                }
                if row % 3 == 1 {
                    c += inkLine(points, width: 2.5 + t * 3, tone: 0.035 + t * 0.025, dry: 0.45)
                }
                c += inkLine(points, width: 0.55 + t * 0.55,
                    tone: 0.12 + t * (kind == .sea ? 0.26 : 0.15), dry: 0.55)
                if kind == .sea, row > 5 {
                    // Follow the crest with an incomplete return, leaving a white lip of foam.
                    c += inkLine(Array(points.dropFirst(3).dropLast(2)).map { P($0.x - span * 0.025, $0.y + 2 + t * 3) },
                        width: 0.65, tone: 0.20, dry: 0.62)
                }
            }
        }
        if kind == .sea {
            for (a, b) in [(0.03, 0.32), (0.39, 0.68), (0.73, 0.97)] {
                c += inkLine([P(width * a, 0), P(width * b, 0.5)], width: 0.7, tone: 0.18, dry: 0.65)
            }
        }
        if kind == .river {
            for side in [0.0, 0.74] {
                c += inkLine(inkCurve([P(width * side, height * 0.68),
                    P(width * (side + 0.08), height * 0.64), P(width * (side + 0.20), height * 0.69)]),
                    width: 1.0, tone: 0.20, dry: 0.65)
            }
        }
        if kind == .pond {
            for (x, y, radius) in [(width * 0.26, height * 0.44, width * 0.075),
                                    (width * 0.65, height * 0.76, width * 0.10)] {
                for (start, end) in [(0.10, 0.77), (1.14, 1.75)] {
                    let arc = (0...16).map { i -> P in
                        let angle = (start + (end - start) * Double(i) / 16) * .pi
                        return P(x + radius * cos(angle), y + radius * 0.16 * sin(angle))
                    }
                    c += inkLine(arc, width: 0.7, tone: 0.30, dry: 0.5)
                }
            }
        }
        return c
    }

    func paintingReflection(width: Double, height: Double) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        let count = max(3, min(13, Int(height / 3)))
        for i in 0..<count {
            let t = Double(i) / Double(count - 1), span = width * (0.22 + 0.65 * t) * (0.6 + r() * 0.4)
            let x = width / 2 - span / 2 + (r() - 0.5) * width * 0.12, y = height * t
            c += inkLine([P(x, y), P(x + span * 0.45, y + 0.5), P(x + span, y - 0.3)],
                width: 1.3 + r() * 1.7, tone: 0.10 * (1 - t * 0.65), dry: 0.5)
        }
        return c
    }

    func paintingRiverRibbon() -> ZXArt.SSCanv {
        let width = 340.0, height = 65.0
        let middle = (0...40).map { i -> P in
            let t = Double(i) / 40
            return P(width * t, height * (0.40 + 0.14 * sin(t * .pi * 2 + 0.3)))
        }
        let far = middle.enumerated().map { i, p in P(p.x, p.y - 11 * pow(1 - Double(i) / 40, 0.7)) }
        let near = middle.enumerated().map { i, p in P(p.x, p.y + 18 * pow(1 - Double(i) / 40, 0.7)) }
        var c = [poly(far + near.reversed(), fil: .white, str: nil)]
        for bank in [far, near] {
            c += inkLine(bank, width: 3, tone: 0.06, dry: 0.4)
            c += inkLine(bank, width: 0.8, tone: 0.32, dry: 0.55)
        }
        for start in stride(from: 2, to: 34, by: 5) {
            for offset in [-3.0, 4] {
                c += inkLine(Array(middle[start...start + 4]).map { P($0.x, $0.y + offset) },
                    width: 0.65, tone: 0.22, dry: 0.6)
            }
        }
        return c
    }
}
