import CoreGraphics
import Foundation
import Testing
@testable import ZixiaoArt

struct ZXArtPaintingSceneTests {
    @Test func versionAndSavedSelectionRemainIndependent() throws {
        let selection = ZXArt.poetryScene(text: "明月松间照，清泉石上流", title: "山居秋暝")
        let legacy = selection.procedural(seed: "same-poem")
        let painting = selection.paintingProcedural(seed: "same-poem")
        #expect(legacy.generator == "shanshui@4")
        #expect(painting.generator == "shanshui@5")
        #expect(legacy.seed == painting.seed)
        #expect(legacy.params == painting.params)
        #expect(painting.downgraded() == painting)
        #expect(painting.isSupported)
        #expect(try JSONDecoder().decode(ZXArt.Procedural.self, from: JSONEncoder().encode(painting)) == painting)
        let size = CGSize(width: 375, height: 500)
        let old = try #require(ZXArt.drawing(procedural: legacy, palette: .paperInk, pixelSize: size))
        let new = try #require(ZXArt.drawing(procedural: painting, palette: .paperInk, pixelSize: size))
        #expect(old.pointCount != new.pointCount)
        #expect(old.sceneElements != new.sceneElements)
    }

    @Test(arguments: ZXArt.PoetryScene.allCases)
    func everyCompositionFitsItsVerseAndViewport(scene: ZXArt.PoetryScene) throws {
        let sizes = [CGSize(width: 375, height: 500), CGSize(width: 375, height: 375), CGSize(width: 600, height: 337.5)]
        for side in ["left", "right", "top"] {
            for size in sizes {
                let selection = ZXArt.SceneSelection(scene: scene,
                    options: .init(motifs: ZXArt.defaultMotifs(for: scene)), matched: [])
                let recipe = selection.paintingProcedural(seed: "geometry-" + scene.rawValue, verseSide: side)
                let drawing = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: size))
                let repeated = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: size))
                #expect(drawing.sceneElements == repeated.sceneElements)
                #expect(drawing.pointCount == repeated.pointCount)
                #expect(drawing.sceneElements.count > 1)
                let verse = try #require(recipe.verseLayout(pixelSize: size)).rect
                for element in drawing.sceneElements {
                    let bounds = element.bounds.cgRect
                    #expect(CGRect(x: -0.001, y: -0.001, width: 1.002, height: 1.002).contains(bounds))
                    #expect(!bounds.intersects(verse))
                }
                #expect(drawing.pointCount < 600_000)
                #expect(drawing.shapeCount < 12_000)
                for shape in drawing.layers.flatMap(\.shapes) {
                    #expect(shape.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
                }
            }
        }
    }

    @Test func geometryAndColourAdaptToAnActualNightPalette() throws {
        let selection = ZXArt.poetryScene(text: "风雪夜归人", title: "逢雪宿芙蓉山主人")
        let recipe = selection.paintingProcedural(seed: "winter-night")
        let size = CGSize(width: 375, height: 500)
        let day = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: size))
        let night = try #require(ZXArt.drawing(procedural: recipe, palette: .night, pixelSize: size))
        #expect(day.sceneElements == night.sceneElements)
        #expect(day.background != night.background)
        #expect(Set(night.sceneElements.map(\.motif)).isSuperset(of: ["snow", "oldTree", "house"]))
        #expect(night.anchors?.buildings.isEmpty == false)
    }
}
