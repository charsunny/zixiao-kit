// Shared drawing methods for shanshui@5 scenes and the six-seed atlas.
import Foundation
import ZixiaoColor

extension ShanShuiEngine {
    func paintingAtmosphere(_ motif: ZXArt.SceneMotif) -> ZXArt.SSCanv {
        switch motif {
        case .moon, .crescent: return paintingMoon(crescent: motif == .crescent)
        case .sunrise, .sunset:
            let radius = 24.0
            var c = sceneEllipse(40, 40, radius, radius, fill: C(171, 64, 51, 0.70), tone: 0)
            // Clouds obscure an unequal part of the rim; never stripe the disc like a badge.
            let form = Int(r() * 65536) % 3
            if form > 0 {
                let y = form == 1 ? 58.0 : 51.0
                let edge = inkCurve([P(12, y + 2), P(49, y - 1),
                    P(59, y + 1), P(70, y - 2)])
                c.append(poly(edge + [P(72, 68), P(12, 68)], fil: .white, str: nil))
                c += inkLine(edge, width: 1.2, tone: 0.12, dry: 0.68)
            }
            return c
        case .stars:
            var c: ZXArt.SSCanv = []
            let count = 4 + Int(r() * 65536) % 6
            for k in 0..<count {
                let x = 8 + Double(k) / Double(count) * 170 + r() * 9
                let y = 8 + r() * 65
                c += inkBlot(x, y, radius: 0.7 + r() * 0.65, squash: 0.9, tone: 0.35 + r() * 0.25)
            }
            return c
        case .rain:
            let form = Int(r() * 65536) % 3
            let slant = [4.0, 9, 15][form]
            var c: ZXArt.SSCanv = []
            for _ in 0..<(17 + form * 11) {
                let x = 18 + r() * 160, y = r() * 105, length = 6 + r() * 13
                c += inkLine([P(x, y), P(x - slant * length / 18, y + length)],
                    width: 0.55 + r() * 0.25, tone: 0.13 + r() * 0.12, dry: 0.42)
            }
            return c
        case .snow:
            var c: ZXArt.SSCanv = []
            for _ in 0..<(10 + Int(r() * 14)) {
                let x = r() * 180, y = r() * 110, radius = 0.8 + r() * 1.3
                c += sceneEllipse(x, y, radius, radius * 0.85, fill: .white, tone: 0.08)
            }
            return c
        case .waterfall: return paintingWaterfall().canvas
        default: return paintingLegacy(sceneAsset(motif))
        }
    }
}

extension ZXArt {
    /// Both callers map the same cinnabar marker and paper reservations, including on dark paper.
    static func appendPaintingShapes(_ canv: SSCanv, motif: SceneMotif? = nil,
                                     palette: Palette, into shapes: inout [Shape]) {
        for polygon in canv {
            let start = shapes.count
            appendShapes([polygon], palette: palette, into: &shapes)
            for i in start..<shapes.count {
                if let fill = polygon.fil, fill.r > fill.g + 50,
                   motif == .sunset || motif == .sunrise {
                    shapes[i].fill = ZXHex(red: 0.67, green: 0.25, blue: 0.20).opacity(palette.isDark ? 0.48 : 0.38)
                } else if motif == .moon || motif == .crescent, palette.isDark, polygon.fil == .white {
                    shapes[i].fill = palette.ink.opacity(0.52)
                }
            }
        }
    }
}
