import CoreGraphics
import Foundation
import Testing
@testable import ZixiaoArt

struct ZXArtPaintingSceneTests {
    @Test func waterChannelsHaveSeparatedBanksAndBroadenTowardTheViewer() {
        for broad in [false, true] {
            for phase in stride(from: 0.0, to: 1.2, by: 0.08) {
                let channel = PaintingWaterChannel(width: 300, height: 240, phase: phase, broad: broad)
                var previousWidth = 0.0
                for i in 0...100 {
                    let t = Double(i) / 100
                    let left = channel.point(t, across: -1), right = channel.point(t, across: 1)
                    #expect(left.x >= 0 && right.x <= 300)
                    #expect(left.x < right.x && left.y == right.y)
                    #expect(right.x - left.x >= previousWidth - 0.000_001)
                    previousWidth = right.x - left.x
                }
            }
        }
    }

    @Test func waterScenesUseTheirOwnStructuresAndStreamCrossesTheRockBed() throws {
        let scenes: [(ZXArt.PoetryScene, String)] = [(.fishing, "riverWater"), (.waterTown, "riverWater"), (.farewell, "riverWater"),
            (.lotusPond, "pondWater"), (.moonNight, "lakeWater"), (.ocean, "waves")]
        for (scene, motif) in scenes {
            let selection = ZXArt.SceneSelection(scene: scene, options: .init(motifs: ZXArt.defaultMotifs(for: scene)), matched: [])
            let recipe = selection.paintingProcedural(seed: "water-structure-" + scene.rawValue)
            let drawing = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: .init(width: 393, height: 852)))
            #expect(drawing.sceneElements.contains { $0.motif == motif })
            #expect(drawing.anchors?.water != nil)
            #expect(drawing.pointCount < 600_000 && drawing.shapeCount < 12_000)
            if [.moonNight, .waterTown, .farewell].contains(scene) {
                let boat = try #require(drawing.sceneElements.first { ["boat", "mooredBoat"].contains($0.motif) }).bounds.cgRect
                // With a full-width ground band the near slope dissolves into water; the boat rides
                // the water at its lower edge, never on the bank top.
                let near = drawing.sceneElements.first { $0.motif == "nearBank" }?.bounds.cgRect
                let bank = try #require(near ?? drawing.sceneElements.first { $0.motif == "groundBank" }?.bounds.cgRect)
                if near != nil { #expect(boat.minX > bank.maxX) } else { #expect(boat.maxY >= bank.minY + bank.height * 0.4) }
                if let reflection = drawing.sceneElements.first(where: { $0.motif == "waterReflection" })?.bounds.cgRect {
                    #expect(!reflection.intersects(bank))
                }
            }
        }
        let mountain = ZXArt.SceneSelection(scene: .retreat, options: .init(motifs: ZXArt.defaultMotifs(for: .retreat)), matched: [])
        let pond = ZXArt.poetryScene(text: "泉眼无声惜细流，树阴照水爱晴柔。小荷才露尖尖角。", title: "小池")
        let pondDrawing = try #require(ZXArt.drawing(procedural: pond.paintingProcedural(seed: "pond-inlet"),
            palette: .paperInk, pixelSize: .init(width: 393, height: 852)))
        let inlet = try #require(pondDrawing.sceneElements.first { $0.motif == "stream" }).bounds.cgRect
        #expect(inlet.width > inlet.height * 2)
        for purpose in ZXArt.ScenePurpose.allCases {
            for composition in ZXArt.SceneComposition.allCases {
                let recipe = mountain.paintingProcedural(seed: "stream-joins-banks", purpose: purpose, composition: composition)
                let d = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: .init(width: 669, height: 951)))
                let stream = try #require(d.sceneElements.first { $0.motif == "stream" }).bounds.cgRect
                let far = try #require(d.sceneElements.first { $0.motif == "groundBank" }).bounds.cgRect
                // With a full-width ground band there is no separate near slope; the stream then runs
                // through the band from its top edge down into the dissolving lower half.
                let near = d.sceneElements.first { $0.motif == "nearBank" }?.bounds.cgRect
                // A rocky spring starts at the local stone gap, which may be below the
                // highest stone on the opposite side of the same bank.
                #expect(stream.minY >= far.minY - 0.006 && stream.minY < far.maxY)
                #expect(stream.maxY >= (near?.maxY ?? (far.minY + far.height * 0.5)) - 0.006)
                #expect(d.anchors?.water != nil)
                for object in d.sceneElements where ["hut", "pine", "bamboo"].contains(object.motif) {
                    let r = object.bounds.cgRect
                    #expect(stream.maxX <= r.minX + 0.002 || stream.minX >= r.maxX - 0.002, "\(purpose) \(composition) stream=\(stream) \(object.motif)=\(r)")
                }
            }
        }
    }

    @Test func mountainSilhouettesVaryWithoutInventingExtraSummits() {
        var forms: Set<Int> = []
        var peakPositions: [Double] = []
        var aspects: [Double] = []
        for index in 0..<64 {
            let seed = ZXArt.Seed("mountain-variety-\(index)")
            let engine = ShanShuiEngine(seed: seed)
            let profile = PaintingMountainProfile(random: { engine.r() })
            let repeatedEngine = ShanShuiEngine(seed: seed)
            let repeated = PaintingMountainProfile(random: { repeatedEngine.r() })
            #expect(profile.ridge == repeated.ridge)
            #expect(profile.width == repeated.width && profile.height == repeated.height)
            forms.insert(profile.form.rawValue)
            peakPositions.append(profile.ridge.max { $0.y < $1.y }!.x)
            aspects.append(profile.height / profile.width)
            #expect(abs(profile.elevation(at: 0)) < 0.000_001)
            #expect(abs(profile.elevation(at: 1)) < 0.000_001)
            var peaks = 0
            for i in 1..<(profile.ridge.count - 1) {
                let a = profile.ridge[i - 1], b = profile.ridge[i], c = profile.ridge[i + 1]
                if b.y > a.y && b.y > c.y { peaks += 1 }
            }
            #expect(peaks >= 1 && peaks <= 4)
            // Every interpolated slope must stay monotone between its control points.
            for i in 0..<(profile.ridge.count - 1) {
                let a = profile.ridge[i], b = profile.ridge[i + 1]
                var previous = a.y
                for step in 1...40 {
                    let value = profile.elevation(at: a.x + (b.x - a.x) * Double(step) / 40)
                    #expect(value.isFinite && value >= -0.000_001 && value <= 1.000_001)
                    #expect(b.y > a.y ? value >= previous - 0.000_001 : value <= previous + 0.000_001)
                    previous = value
                }
            }
        }
        #expect(forms.count == PaintingMountainProfile.Form.allCases.count)
        #expect(peakPositions.max()! - peakPositions.min()! > 0.35)
        #expect(aspects.max()! - aspects.min()! > 0.5)
    }

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
                            // Near trees lead the eye; the retreat's pine is the protagonist (明月松间照).
                            let lead = scene == .retreat && element.motif == "pine"
                            #expect(rect.height <= mountain.height * (lead ? 0.60 : 0.32))
                        }
                        if element.motif == "bamboo" {
                            #expect(rect.height <= mountain.height * 0.30)
                        }
                        if ["house", "hut", "pavilion", "templeGate", "cityGate", "pagoda"].contains(element.motif) {
                            #expect(rect.height <= mountain.height * (element.motif == "pagoda" ? 0.27 : 0.14))
                            #expect(rect.maxY >= mountain.minY + mountain.height * 0.5, "\(composition) \(size) \(element.motif)=\(rect) mountain=\(mountain)")
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
                        #expect(rect.minY >= 0.219, "\(composition) \(size) \(element.motif): \(rect)")
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
