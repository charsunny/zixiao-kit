// Shared static atmosphere for shanshui@5 scenes and review atlases.
import Foundation
import ZixiaoColor

extension ShanShuiEngine {
    func paintingAtmosphere(_ motif: ZXArt.SceneMotif) -> ZXArt.SSCanv {
        switch motif {
        case .moon: return paintingMoon()
        case .waterfall: return paintingWaterfall().canvas
        case .rain, .snow: return [] // App weather overlay; snow-covered terrain reserves paper.
        default: return paintingLegacy(sceneAsset(motif))
        }
    }
}

extension ZXArt {
    /// Keep the atlas on the same palette path as the scene, including vermilion and dark paper.
    static func appendPaintingShapes(_ canv: SSCanv, motif: SceneMotif? = nil,
                                     palette: Palette, into shapes: inout [Shape]) {
        let start = shapes.count
        appendShapes(canv, palette: palette, into: &shapes)
        for i in start..<shapes.count {
            if motif == .sunset || motif == .sunrise {
                shapes[i].fill = ZXHex(red: 0.67, green: 0.25, blue: 0.20).opacity(palette.isDark ? 0.40 : 0.26)
            } else if motif == .moon, palette.isDark, let fill = shapes[i].fill {
                shapes[i].fill = palette.ink.opacity(fill.alpha > 0.9 ? 0.52 : 0.05)
            }
        }
    }
}
