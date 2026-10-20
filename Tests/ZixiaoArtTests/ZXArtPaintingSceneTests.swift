import CoreGraphics
import Foundation
import Testing
@testable import ZixiaoArt

struct ZXArtPaintingSceneTests {
    @Test func omittedPresentationUsesTheCurrentPainting() throws {
        let selection = ZXArt.poetryScene(text: "明月松间照，清泉石上流", title: "山居秋暝")
        let painting = selection.paintingProcedural(seed: "same-poem")
        #expect(painting.generator == "shanshui@5")
        #expect(painting.params.scene?.purpose == .inscription)
        #expect(painting.params.scene?.composition != nil)
        #expect(painting.isSupported)
        #expect(try JSONDecoder().decode(ZXArt.Procedural.self, from: JSONEncoder().encode(painting)) == painting)
        var unmarked = painting
        unmarked.params.scene?.purpose = nil
        unmarked.params.scene?.composition = nil
        let size = CGSize(width: 375, height: 500)
        let implicit = try #require(ZXArt.drawing(procedural: unmarked, palette: .paperInk, pixelSize: size))
        let explicit = try #require(ZXArt.drawing(procedural: painting, palette: .paperInk, pixelSize: size))
        #expect(implicit.pointCount == explicit.pointCount)
        #expect(implicit.sceneElements == explicit.sceneElements)
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
    @Test(arguments: ZXArt.PoetryScene.allCases, ZXArt.ScenePurpose.allCases)
    func pagePresentationsRespectTheirReadingAreas(scene: ZXArt.PoetryScene, purpose: ZXArt.ScenePurpose) throws {
        let selection = ZXArt.SceneSelection(scene: scene, options: .init(motifs: ZXArt.defaultMotifs(for: scene)), matched: [])
        for composition in ZXArt.SceneComposition.allCases {
            for size in [CGSize(width: 393, height: 852), CGSize(width: 669, height: 951), CGSize(width: 1194, height: 834)] {
                let recipe = selection.paintingProcedural(seed: "presentation-" + scene.rawValue,
                    purpose: purpose, composition: composition)
                #expect(try JSONDecoder().decode(ZXArt.Procedural.self, from: JSONEncoder().encode(recipe)) == recipe)
                let drawing = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: size))
                #expect(drawing.sceneElements.count > 1)
                #expect(drawing.pointCount < 600_000)
                #expect(drawing.shapeCount < 12_000)
                if purpose == .reading {
                    #expect(recipe.verseLayout(pixelSize: size) == nil)
                    #expect(drawing.verseRect == nil)
                }
                if let mountain = drawing.sceneElements.first(where: { $0.motif == "mainMountain" })?.bounds.cgRect {
                    for element in drawing.sceneElements {
                        let rect = element.bounds.cgRect
                        if ["pine", "oldTree", "bareTree", "layeredTree", "willow", "blossom", "maple"].contains(element.motif) {
                            #expect(rect.height <= mountain.height * 0.175)
                        }
                        if element.motif == "bamboo" {
                            #expect(rect.height <= mountain.height * 0.10)
                        }
                        if ["house", "hut", "pavilion", "templeGate", "cityGate", "pagoda"].contains(element.motif) {
                            #expect(rect.height <= mountain.height * (element.motif == "pagoda" ? 0.18 : 0.10))
                            #expect(rect.maxY >= mountain.maxY - mountain.height * 0.25)
                        }
                    }
                }
                if let bank = drawing.sceneElements.first(where: { $0.motif == "groundBank" })?.bounds.cgRect {
                    for element in drawing.sceneElements where ["house", "hut", "pavilion", "pagoda", "templeGate", "cityGate"].contains(element.motif) {
                        let r = element.bounds.cgRect
                        #expect(r.midX >= bank.minX - 0.001 && r.midX <= bank.maxX + 0.001)
                        #expect(r.maxY >= bank.minY - 0.001)
                        #expect(r.maxY <= bank.maxY + 0.001)
                    }
                }
                for element in drawing.sceneElements {
                    let rect = element.bounds.cgRect
                    #expect(CGRect(x: -0.001, y: -0.001, width: 1.002, height: 1.002).contains(rect))
                    if let verse = recipe.verseLayout(pixelSize: size) { #expect(!verse.rect.intersects(rect)) }
                    if purpose == .recommendation {
                        #expect(rect.minY >= 0.219)
                        #expect(rect.maxY <= 0.871)
                    }
                }
            }
        }
    }

    @Test func compositionsChangeSpatialArrangementWithoutChangingSubject() throws {
        let selection = ZXArt.poetryScene(text: "明月松间照，清泉石上流", title: "山居秋暝")
        let size = CGSize(width: 393, height: 852)
        let drawings = try ZXArt.SceneComposition.allCases.map { composition in
            try #require(ZXArt.drawing(procedural: selection.paintingProcedural(seed: "same-subject",
                purpose: .reading, composition: composition), palette: .paperInk, pixelSize: size))
        }
        #expect(Set(drawings.map { $0.sceneElements.map { $0.bounds } }).count == 3)
        for drawing in drawings { #expect(drawing.sceneElements.contains { $0.motif == "pine" }) }
        // Full-page reading must use both halves, rather than the inscription's left column.
        #expect(drawings.contains { $0.sceneElements.contains { $0.bounds.cgRect.maxX > 0.7 } })
    }

    @Test func standaloneMountainDoesNotSmuggleInRandomBuildings() {
        let engine = ShanShuiEngine(seed: .init("page-scale"))
        engine.anchorLog = []
        _ = engine.paintingMountain()
        #expect(engine.anchorLog?.contains { piece in
            if case .building = piece.kind { return true }
            return false
        } == false)
    }

    @Test func treeSizeVariesWithinTheApprovedRangeAndStaysStable() throws {
        let values = (0..<64).map { index in
            PaintingTreeScale.multiplier(seed: "tree-\(index)", motif: .pine, instance: 0)
        }
        #expect(values.allSatisfy { (0.5...1).contains($0) })
        #expect(try #require(values.min()) < 0.6)
        #expect(try #require(values.max()) > 0.9)
        let selection = ZXArt.poetryScene(text: "明月松间照，清泉石上流", title: "山居秋暝")
        let recipe = selection.paintingProcedural(seed: "stable-tree", purpose: .reading)
        let size = CGSize(width: 393, height: 852)
        let first = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: size))
        let repeated = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: size))
        let night = try #require(ZXArt.drawing(procedural: recipe, palette: .night, pixelSize: size))
        #expect(first.sceneElements == repeated.sceneElements)
        #expect(first.sceneElements == night.sceneElements)
    }

}
