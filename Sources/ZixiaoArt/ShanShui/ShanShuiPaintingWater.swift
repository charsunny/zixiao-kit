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
        let half = width * (broad ? 0.035 + 0.39 * pow(t, 0.85) : 0.02 + 0.10 * pow(t, 0.9))
        let sway = width * (broad ? 0.11 : 0.23) * sin(t * .pi * 2 + phase)
        let center = min(width - half - width * 0.025, max(half + width * 0.025, width * 0.5 + sway))
        return .init(center + half * across, height * t)
    }

    var left: [ZXArt.P] { (0...40).map { point(Double($0) / 40, across: -1) } }
    var right: [ZXArt.P] { (0...40).map { point(Double($0) / 40, across: 1) } }
}

extension ShanShuiEngine {
    func paintingChannel(width: Double, height: Double, river: Bool = false, phase: Double? = nil) -> ZXArt.SSCanv {
        paintingChannel(PaintingWaterChannel(width: width, height: height, phase: phase ?? r() * .pi * 2, broad: river))
    }

    func paintingChannel(_ channel: PaintingWaterChannel) -> ZXArt.SSCanv {
        let width = channel.width, height = channel.height
        let left = channel.left, right = channel.right
        var c = [poly(left + right.reversed(), fil: .white, str: nil)]
        for (bank, side) in [(left, -1.0), (right, 1.0)] {
            // Pale earth lies OUTSIDE the water; its edge touches the bank contour.
            let outer = bank.enumerated().map { i, p in
                P(p.x + side * width * (0.008 + Double(i) / 40 * 0.032), p.y + height * 0.015)
            }
            c.append(poly(bank + outer.reversed(), fil: .gray(0, 0.075), str: nil))
            var start = 0
            while start < 38 {
                let length = 4 + Int(r() * 5)
                c += inkLine(Array(bank[start...min(start + length, 40)]), width: 0.65 + r() * 0.45,
                    tone: 0.32 + r() * 0.12, dry: 0.6)
                start += length + 2 + Int(r() * 3)
            }
        }
        // Broken transverse water ripples open toward us, unlike longitudinal road ruts.
        for i in 0..<(5 + Int(r() * 4)) {
            let t = 0.15 + Double(i) * 0.09 + r() * 0.025
            guard t < 0.95 else { continue }
            let lane = -0.75 + r() * 0.35
            let a = channel.point(t, across: lane), b = channel.point(t, across: min(0.80, lane + 0.65 + r() * 0.50))
            c += inkLine([a, P((a.x + b.x) / 2, a.y + min(0.8, height * 0.009)), b],
                         width: 0.55 + t * 0.3, tone: 0.22 + t * 0.10, dry: 0.55)
        }
        if !channel.broad {
            for t in [0.42, 0.76] where r() < 0.65 {
                let side = r() < 0.5 ? -1.0 : 1.0
                let p = channel.point(t, across: side), size = min(width * 0.045, height * 0.10)
                let stone = [P(p.x - size, p.y), P(p.x - size * 0.5, p.y - size * 0.55),
                             P(p.x + size * 0.6, p.y - size * 0.4), P(p.x + size, p.y)]
                c.append(poly(stone, fil: .white, str: nil))
                c += inkLine(stone, width: 0.9, tone: 0.55, dry: 0.5)
                c += inkLine([P(p.x - size * 1.2, p.y + 1), P(p.x + size * 1.4, p.y + 1)], width: 0.55, tone: 0.30)
            }
        }
        return c
    }

    func paintingSurface(_ kind: PaintingWaterKind, width: Double = 320, height: Double = 140) -> ZXArt.SSCanv {
        if kind == .sea { return paintingSea(width: width, height: height) }
        var c: ZXArt.SSCanv = []
        let rows = kind == .sea ? 12 : (kind == .pond ? 6 : 8)
        for row in 0..<rows {
            let t = Double(row + 1) / Double(rows + 1)
            let y = height * (0.04 + 0.90 * pow(t, 1.55)) + (r() - 0.5) * height * 0.03
            // 远水无波: far rows are mostly bare paper; strokes gather toward the near shore.
            let count = kind == .sea ? 3 : (r() < 0.25 + 0.75 * t ? (r() < t ? 2 : 1) : 0)
            for group in 0..<count {
                let span = width * (0.10 + 0.24 * t) * (0.7 + r() * 0.55)
                let x = (Double(group) + 0.12 + r() * 0.48) / Double(count) * (width - span)
                let amplitude = kind == .sea ? height * (0.002 + 0.022 * t * t) : height * 0.003
                let points = (0...14).map { i -> P in
                    let u = Double(i) / 14
                    let lift = kind == .sea ? sin(u * .pi * 2) + 0.35 * sin(u * .pi * 4) : sin(u * .pi)
                    return P(x + span * u, y + amplitude * lift)
                }
                if kind == .sea ? row % 3 == 1 : (t > 0.6 && r() < 0.4) {
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

    /// Groups of linked crests and turning currents, separated by untouched water.
    private func paintingSea(width: Double, height: Double) -> ZXArt.SSCanv {
        var c: ZXArt.SSCanv = []
        for group in 0..<9 {
            let t = Double(group) / 8
            let position = 0.08 + r() * 0.56
            let y = height * (0.10 + 0.76 * pow(t, 1.4))
            let span = width * (0.18 + 0.25 * t) * (0.7 + r() * 0.4)
            let x = min(width - span - 1, width * position)
            let rise = height * (0.012 + 0.065 * t)
            let turn = 0.32 + r() * 0.35
            for echo in 0..<(2 + Int(t * 3)) {
                let offset = Double(echo) * min(1.2 + t * 1.6, height * 0.018)
                let path = (0...28).map { i -> P in
                    let u = Double(i) / 28
                    let crest = exp(-pow((u - turn) / 0.19, 2))
                    let wake = sin(u * .pi * 2.5) * 0.18
                    return P(x + span * u - offset * 0.9,
                        y - rise * (crest + wake) + offset * (0.3 + 0.7 * sin(u * .pi)))
                }
                c += inkLine(path, width: echo == 0 ? 0.9 + t * 0.7 : 0.55,
                    tone: echo == 0 ? 0.20 + t * 0.24 : 0.14 + t * 0.12, dry: 0.57)
            }
            if t > 0.5 {
                let curl = inkCurve([P(x + span * turn, y - rise),
                    P(x + span * turn - rise * 0.40, y - rise * 1.16),
                    P(x + span * turn - rise * 0.65, y - rise * 0.62),
                    P(x + span * turn - rise * 0.2, y - rise * 0.5)])
                c += inkLine(curl, width: 0.65, tone: 0.32, dry: 0.5)
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
        let phase = r() * 5, bend = 0.08 + r() * 0.14, opening = 18 + r() * 16
        let middle = (0...40).map { i -> P in
            let t = Double(i) / 40
            return P(width * t, height * (0.48 + bend * sin(t * .pi * 1.5 + phase)))
        }
        let far = middle.enumerated().map { i, p in P(p.x, p.y - opening * 0.42 * pow(1 - Double(i) / 40, 0.7)) }
        let near = middle.enumerated().map { i, p in P(p.x, p.y + opening * 0.58 * pow(1 - Double(i) / 40, 0.7)) }
        var c = [poly(far + near.reversed(), fil: .white, str: nil)]
        for (bank, side) in [(far, -1.0), (near, 1.0)] {
            let outer = bank.map { P($0.x, $0.y + side * 2) }
            c.append(poly(bank + outer.reversed(), fil: .gray(0, 0.055), str: nil))
            for start in stride(from: 0, to: 36, by: 7) {
                c += inkLine(Array(bank[start...start + 4]), width: 0.8, tone: 0.32, dry: 0.6)
            }
        }
        for start in stride(from: 2, to: 32, by: 5) {
            let p = middle[start], length = 12 + r() * 20
            c += inkLine([P(p.x, p.y - 1), P(p.x + length * 0.5, p.y), P(p.x + length, p.y - 0.3)],
                         width: 0.65, tone: 0.27, dry: 0.6)
        }
        return c
    }
}
