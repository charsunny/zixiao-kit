// Temporary: dump element rects for diagnosis (removed after use).
import CoreGraphics
import XCTest
@testable import ZixiaoArt

final class ZXArtDebugDumpTests: XCTestCase {
    func testDumpBuildings() throws {
        for scene in [ZXArt.PoetryScene.retreat, .temple] {
            let selection = ZXArt.SceneSelection(scene: scene, options: .init(motifs: ZXArt.defaultMotifs(for: scene)), matched: [])
            for composition in ZXArt.SceneComposition.allCases {
                for size in [CGSize(width: 393, height: 852), CGSize(width: 669, height: 951), CGSize(width: 1194, height: 834)] {
                    let recipe = selection.paintingProcedural(seed: "presentation-" + scene.rawValue, purpose: .inscription, composition: composition)
                    let d = try XCTUnwrap(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: size))
                    guard let m = d.sceneElements.first(where: { $0.motif == "mainMountain" })?.bounds.cgRect else { continue }
                    for e in d.sceneElements where ["hut", "house", "pavilion", "pagoda", "templeGate", "groundBank"].contains(e.motif) {
                        let r = e.bounds.cgRect
                        print("DUMP \(scene) \(composition.rawValue) \(Int(size.width))x\(Int(size.height)) \(e.motif) maxY=\(r.maxY) minY=\(r.minY) midX=\(r.midX) mtn=\(m.minY)...\(m.maxY) mid=\(m.minY + m.height * 0.5)")
                    }
                }
            }
        }
    }
}
