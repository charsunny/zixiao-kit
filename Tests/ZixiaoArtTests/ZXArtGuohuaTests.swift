import CoreGraphics
import Testing
@testable import ZixiaoArt

struct ZXArtGuohuaTests {
    @Test func travelersStandOnTheBankAndBridgesCrossWater() throws {
        for scene in [ZXArt.PoetryScene.farewell, .autumnTravel, .waterTown, .winterForest, .historic, .village, .spring] {
            for size in [CGSize(width: 750, height: 1000), CGSize(width: 1200, height: 675)] {
                for index in 0..<3 {
                    // The autumn poem explicitly names bridge and horse; winter names a traveler.
                    // These textual accents are optional in the generic scene defaults.
                    let accents: [ZXArt.SceneMotif] = [ZXArt.PoetryScene.autumnTravel, .village, .spring].contains(scene) ? [.bridge, .horse, .stream]
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
                        for building in drawing.sceneElements where ["house", "pavilion", "hut", "terrace", "cityGate", "ruins"].contains(building.motif) {
                            #expect(!r.intersects(building.bounds.cgRect), "\(scene) \(size) seed=\(index) person=\(r) \(building.motif)=\(building.bounds.cgRect)")
                        }
                        if let tree = drawing.sceneElements.first(where: { ["willow", "bareTree"].contains($0.motif) }) {
                            #expect(r.height < tree.bounds.cgRect.height * 0.25)
                        }
                    }
                    if [ZXArt.PoetryScene.autumnTravel, .waterTown, .village, .spring].contains(scene) {
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

    @Test func buildingsHaveGroundBelowThemIncludingHistoricAccents() throws {
        let buildings: Set<String> = ["house", "hut", "pavilion", "pagoda", "templeGate", "terrace", "ruins", "cityGate"]
        for scene in [ZXArt.PoetryScene.retreat, .temple, .historic, .village, .farewell, .waterTown, .winterForest, .moonNight] {
            for composition in [ZXArt.SceneComposition.corner, .depth, .oppositeBank] {
                for size in [CGSize(width: 750, height: 1000), CGSize(width: 1200, height: 675)] {
                    for seed in 0..<3 {
                        let extras: [ZXArt.SceneMotif] = scene == .historic ? [.ruins, .cityGate] : []
                        let selection = ZXArt.SceneSelection(scene: scene,
                            options: .init(motifs: ZXArt.defaultMotifs(for: scene) + extras), matched: [])
                        let recipe = selection.paintingProcedural(seed: "guohua-support-\(seed)", composition: composition)
                        let drawing = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: size))
                        let bank = try #require(drawing.sceneElements.first { $0.motif == "groundBank" }).bounds.cgRect
                        for building in drawing.sceneElements where buildings.contains(building.motif) {
                            let b = building.bounds.cgRect
                            #expect(b.midX >= bank.minX && b.midX <= bank.maxX)
                            #expect(b.maxY >= bank.minY - 0.003 && b.maxY <= bank.maxY + 0.003,
                                "\(scene) \(composition) \(size) seed=\(seed) \(building.motif) must meet near ground")
                        }
                        if scene == .historic {
                            let terrace = try #require(drawing.sceneElements.first { $0.motif == "terrace" }).bounds.cgRect
                            let person = try #require(drawing.sceneElements.first { $0.motif == "traveler" }).bounds.cgRect
                            let mountain = try #require(drawing.sceneElements.first { $0.motif == "mainMountain" }).bounds.cgRect
                            #expect(terrace.minY > mountain.midY && person.minY > mountain.midY)
                            #expect(person.maxY >= bank.minY - 0.003 && person.maxY <= bank.maxY + 0.003)
                            #expect(!person.intersects(terrace))
                        }
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
            let verse = try #require(recipe.verseLayout(pixelSize: .init(width: 750, height: 1000)))
            #expect(bank.minY > verse.rect.maxY)
        }
    }

    @Test func bankOutlinesVaryBeyondScalingAndMirroring() throws {
        for style in [ShanShuiEngine.BankStyle.shoal, .cliff, .headland] {
            var signatures = Set<[Int]>()
            for index in 0..<8 {
                func outline() throws -> [ZXArt.P] {
                    let engine = ShanShuiEngine(seed: .init("bank-outline-\(index)"))
                    return try #require(engine.paintingSlope(style).first).p
                }
                let points = try outline()
                let repeated = try outline()
                #expect(points.map(\.x) == repeated.map(\.x) && points.map(\.y) == repeated.map(\.y))
                let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
                let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
                // Quantized normalized shape: merely changing height/width cannot pass.
                signatures.insert(points.flatMap { [Int(($0.x - minX) / (maxX - minX) * 100),
                    Int(($0.y - minY) / (maxY - minY) * 100)] })
            }
            #expect(signatures.count >= 6)
        }
    }

    @Test func celestialDiscsStayOutsidePaintedMountainBodies() throws {
        for scene in [ZXArt.PoetryScene.temple, .retreat] {
            for composition in [ZXArt.SceneComposition.corner, .depth, .oppositeBank] {
                for size in [CGSize(width: 750, height: 1000), CGSize(width: 1200, height: 675)] {
                    for seed in ["review-temple", "review-retreat", "sky-clearance-2"] {
                        let motif: ZXArt.SceneMotif = scene == .temple ? .sunrise : .moon
                        let selection = ZXArt.SceneSelection(scene: scene,
                            options: .init(motifs: ZXArt.defaultMotifs(for: scene) + [motif]), matched: [])
                        let recipe = selection.paintingProcedural(seed: seed, composition: composition)
                        let drawing = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: size))
                        let body = try #require(drawing.sceneElements.first { $0.motif == motif.rawValue }).bounds.cgRect
                        let celestial = CGRect(x: body.minX * drawing.width, y: body.minY * drawing.height,
                            width: body.width * drawing.width, height: body.height * drawing.height)
                        // Inspect the actual filled outlines, including the guest peak, independently
                        // of the placement helper. Sample the whole disc's bounding rectangle.
                        let outlines = drawing.layers.filter { $0.fade != nil && $0.tooth != nil }
                            .compactMap { $0.shapes.first }
                        #expect(!outlines.isEmpty)
                        for shape in outlines {
                            let path = CGMutablePath()
                            path.addLines(between: shape.points.map { CGPoint(x: Double($0.x), y: Double($0.y)) })
                            path.closeSubpath()
                            var overlaps = false
                            for y in 0...24 { for x in 0...24 {
                                if path.contains(CGPoint(x: celestial.minX + celestial.width * Double(x) / 24,
                                    y: celestial.minY + celestial.height * Double(y) / 24)) { overlaps = true }
                            } }
                            #expect(!overlaps, "\(scene) \(composition) \(size) \(seed)")
                        }
                    }
                }
            }
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
