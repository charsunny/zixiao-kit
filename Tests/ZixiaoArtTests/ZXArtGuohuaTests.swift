import CoreGraphics
import Testing
@testable import ZixiaoArt

struct ZXArtGuohuaTests {
    @Test func travelersStandOnTheBankAndBridgesCrossWater() throws {
        for scene in [ZXArt.PoetryScene.farewell, .autumnTravel, .waterTown, .winterForest] {
            for size in [CGSize(width: 750, height: 1000), CGSize(width: 1200, height: 675)] {
                for index in 0..<3 {
                    // The autumn poem explicitly names bridge and horse; winter names a traveler.
                    // These textual accents are optional in the generic scene defaults.
                    let accents: [ZXArt.SceneMotif] = scene == .autumnTravel ? [.bridge, .horse, .stream]
                        : (scene == .winterForest ? [.traveler] : [])
                    let selection = ZXArt.SceneSelection(scene: scene,
                        options: .init(motifs: ZXArt.defaultMotifs(for: scene) + accents), matched: [])
                    let recipe = selection.paintingProcedural(seed: "guohua-ground-\(index)")
                    let drawing = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: size))
                    let bank = try #require(drawing.sceneElements.first { $0.motif == "groundBank" }).bounds.cgRect
                    for person in drawing.sceneElements where person.motif == "traveler" || person.motif == "horse" {
                        let r = person.bounds.cgRect
                        #expect(r.midX >= bank.minX && r.midX <= bank.maxX)
                        #expect(r.maxY >= bank.minY - 0.003 && r.maxY <= bank.maxY + 0.003)
                        for building in drawing.sceneElements where ["house", "pavilion", "hut"].contains(building.motif) {
                            #expect(!r.intersects(building.bounds.cgRect), "\(scene) \(size) seed=\(index) person=\(r) \(building.motif)=\(building.bounds.cgRect)")
                        }
                        if let tree = drawing.sceneElements.first(where: { ["willow", "bareTree"].contains($0.motif) }) {
                            #expect(r.height < tree.bounds.cgRect.height * 0.25)
                        }
                    }
                    if scene == .autumnTravel || scene == .waterTown {
                        let bridge = try #require(drawing.sceneElements.first { $0.motif == "bridge" }).bounds.cgRect
                        let channel = try #require(drawing.sceneElements.first { $0.motif == (scene == .waterTown ? "riverChannel" : "stream") }).bounds.cgRect
                        let reflection = try #require(drawing.sceneElements.first { $0.motif == "bridgeReflection" }).bounds.cgRect
                        #expect(bridge.intersects(channel))
                        #expect(bridge.midX > channel.minX && bridge.midX < channel.maxX)
                        #expect(reflection.minY >= bridge.maxY - 0.003)
                    } else if scene == .farewell {
                        #expect(drawing.sceneElements.filter { $0.motif == "traveler" }.count == 2)
                    }
                }
            }
        }
    }

    @Test func cornerAndLevelDistanceHaveDifferentTerrainInventories() throws {
        let selection = ZXArt.SceneSelection(scene: .farewell,
            options: .init(motifs: ZXArt.defaultMotifs(for: .farewell)), matched: [])
        for composition in [ZXArt.SceneComposition.corner, .oppositeBank] {
            let recipe = selection.paintingProcedural(seed: "guohua-structure", composition: composition)
            let d = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: .init(width: 750, height: 1000)))
            #expect(d.sceneElements.contains { $0.motif == "farShore" } == (composition == .oppositeBank))
            #expect(d.sceneElements.contains { $0.motif == "pavilion" })
            #expect(d.sceneElements.contains { $0.motif == "willow" })
        }
    }

    @Test func portraitGroundKeepsTheFullWidthBandUnderTheVerse() throws {
        for scene in [ZXArt.PoetryScene.retreat, .temple, .autumnTravel, .winterForest, .waterTown] {
            let selection = ZXArt.SceneSelection(scene: scene,
                options: .init(motifs: ZXArt.defaultMotifs(for: scene)), matched: [])
            let recipe = selection.paintingProcedural(seed: "guohua-full-band", verseSide: "right", columns: 2, chars: 7)
            let d = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: .init(width: 750, height: 1000)))
            let bank = try #require(d.sceneElements.first { $0.motif == "groundBank" }).bounds.cgRect
            #expect(bank.minX < 0.05 && bank.maxX > 0.95)
            #expect(bank.minY > #require(recipe.verseLayout(pixelSize: .init(width: 750, height: 1000))).rect.maxY)
        }
    }

    @Test func inkDepthPreservesPaperAndOrdersInkStrength() throws {
        let engine = ShanShuiEngine(seed: .init("guohua-ink"))
        let source = engine.paintingHouse()
        let far = engine.paintingInk(source, depth: .far)
        let middle = engine.paintingInk(source, depth: .middle)
        let near = engine.paintingInk(source, depth: .near)
        for i in source.indices {
            if source[i].fil == .white { #expect(near[i].fil == .white && far[i].fil == .white) }
            else if let a = source[i].fil, a.a > 0 {
                #expect(try #require(far[i].fil).a < #require(middle[i].fil).a)
                #expect(try #require(middle[i].fil).a <= #require(near[i].fil).a)
            }
        }
    }
}
