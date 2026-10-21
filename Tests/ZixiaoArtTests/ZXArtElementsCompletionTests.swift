import CoreGraphics
import Foundation
import Testing
@testable import ZixiaoArt

struct ZXArtElementsCompletionTests {
    @Test func autumnScaleReadsAsMountainTreeHorsePerson() throws {
        let selection = ZXArt.poetryScene(text: "枯藤老树昏鸦，小桥流水人家，古道西风瘦马。夕阳西下。", title: "秋思")
        // Include the inspected protagonist-sized tree: a failed house placement used to
        // silently fall back to a much smaller dwelling despite the six scale seeds passing.
        let seeds = (0..<6).map { "scale-autumn-\($0)" } + ["review-autumn"]
        for (index, seed) in seeds.enumerated() {
            for size in [CGSize(width: 750, height: 1000), CGSize(width: 1200, height: 675)] {
                let drawing = try #require(ZXArt.drawing(procedural: selection.paintingProcedural(seed: seed),
                    palette: .paperInk, pixelSize: size))
                func box(_ name: String) throws -> CGRect {
                    try #require(drawing.sceneElements.first { $0.motif == name }, "\(index) \(size): \(name)").bounds.cgRect
                }
                let person = try box("traveler"), horse = try box("horse"), tree = try box("oldTree")
                let door = try box("houseDoor"), eaves = try box("houseEaves"), bridge = try box("bridge")
                #expect((3...8).contains(tree.height / person.height), "tree/person \(index) \(size)")
                #expect((0.7...1.4).contains(door.height / person.height), "door/person \(index) \(size): \(door.height / person.height)")
                #expect((1.3...1.8).contains(eaves.height / person.height), "eaves/person \(index) \(size): \(eaves.height / person.height)")
                // Head position changes with gait; the withers sit about 65% up the complete horse.
                #expect((0.7...1.3).contains(horse.height * 0.65 / (person.height * 0.78)))
                #expect((4...8).contains(bridge.width * size.width / (person.height * size.height)),
                    "bridge/person \(index) \(size): \(bridge.width * size.width / (person.height * size.height))")
            }
        }
    }

    @Test func thumbnailSeedsChangeTheSceneArrangement() throws {
        for poem in ZXArtSceneReviewTests.poems {
            let selection = ZXArt.poetryScene(text: poem.text, title: poem.title)
            var arrangements = Set<[Int]>()
            for index in 0..<4 {
                let recipe = selection.paintingProcedural(seed: "variety-\(index)-\(poem.id)")
                let d = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: .init(width: 375, height: 500)))
                let structural = d.sceneElements.filter { !["stars", "rain", "snow", "houseDoor", "houseEaves"].contains($0.motif) }
                arrangements.insert(structural.flatMap { element in
                    let b = element.bounds.cgRect
                    return [Int(b.midX * 10), Int(b.midY * 10), Int(b.width * 10), Int(b.height * 10)]
                })
            }
            #expect(arrangements.count >= 3, "\(poem.id): distinct thumbnail arrangements")
        }
    }

    @Test func selectedPoemObjectsAreActuallyDrawnAcrossFormats() throws {
        let poems = ZXArtSceneReviewTests.poems
        for poem in poems {
            let selection = ZXArt.poetryScene(text: poem.text, title: poem.title)
            for index in 0..<4 {
                for size in [CGSize(width: 750, height: 1000), CGSize(width: 1200, height: 675)] {
                    let recipe = selection.paintingProcedural(seed: "variety-\(index)-\(poem.id)")
                    let drawing = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: size))
                    let actual = Set(drawing.sceneElements.map(\.motif))
                    for motif in try #require(recipe.params.scene).canonicalMotifs {
                        #expect(actual.contains(motif.rawValue), "\(poem.id) seed=\(index) \(size): missing \(motif)")
                    }
                }
            }
        }
    }

    @Test func pavilionsStandInTheirMountainWaterbankAndCourt() throws {
        for (name, scene, motifs) in ZXArtSceneReviewTests.pavilionSamples {
            let selection = ZXArt.SceneSelection(scene: scene, options: .init(motifs: motifs), matched: [])
            for index in 0..<6 {
                for size in [CGSize(width: 750, height: 1000), CGSize(width: 1200, height: 675)] {
                    let recipe = selection.paintingProcedural(seed: "\(name)-\(index)")
                    let drawing = try #require(ZXArt.drawing(procedural: recipe, palette: .paperInk, pixelSize: size))
                    let elements = drawing.sceneElements
                    let pavilion = try #require(elements.first { $0.motif == "pavilion" }).bounds.cgRect
                    #expect(pavilion.width * size.width > 25, "\(name) \(index): readable columns")
                    #expect(!elements.contains { ["house", "hut"].contains($0.motif) })
                    if scene == .courtyard {
                        let wall = try #require(elements.first { $0.motif == "courtyard" }).bounds.cgRect
                        #expect(pavilion.minY < wall.minY)
                        #expect(pavilion.maxY > wall.minY && pavilion.maxY < wall.maxY)
                        #expect(pavilion.minX >= wall.minX && pavilion.maxX <= wall.maxX)
                        #expect(try #require(elements.firstIndex { $0.motif == "pavilion" }) < #require(elements.firstIndex { $0.motif == "courtyard" }))
                    } else if scene == .retreat {
                        let mountain = try #require(elements.first { $0.motif == "mainMountain" }).bounds.cgRect
                        #expect((0.12...0.24).contains(pavilion.height / mountain.height))
                        #expect(pavilion.maxY >= mountain.midY)
                    } else {
                        let bank = try #require(elements.first { $0.motif == "groundBank" }).bounds.cgRect
                        #expect(pavilion.midX >= bank.minX && pavilion.midX <= bank.maxX)
                        #expect(pavilion.maxY >= bank.minY && pavilion.maxY <= bank.maxY + 0.01)
                        let boat = try #require(elements.first { $0.motif == "boat" }).bounds.cgRect
                        #expect(!boat.intersects(pavilion), "Boat must leave water below the pavilion")
                    }
                }
            }
        }
    }

    @Test func wordsSelectConcreteObjectsWithoutTitleFalseFriends() {
        let autumn = ZXArt.poetryScene(text: "枯藤老树昏鸦，小桥流水人家，古道西风瘦马。夕阳西下。", title: "天净沙·秋思")
        #expect(Set(autumn.options.motifs).isSuperset(of: [.oldTree, .house, .stream, .bridge, .vine, .crow, .horse, .traveler, .sunset]))
        for (word, motif) in [("茅屋", ZXArt.SceneMotif.hut), ("草堂", .hut), ("村舍", .house),
            ("柴门", .house), ("古木", .oldTree), ("古树", .oldTree), ("春水", .stream),
            ("溪水", .stream), ("孤亭", .pavilion), ("宝塔", .pagoda), ("小舟", .boat), ("客船", .boat)] {
            #expect(ZXArt.poetryScene(text: word).options.contains(motif), "\(word)")
        }
        #expect(ZXArt.poetryScene(text: "骑驴过溪").options.donkey == true)
        #expect(!ZXArt.poetryScene(text: "月亭", title: "随笔").options.contains(.pavilion))
        #expect(!ZXArt.poetryScene(text: "亭亭净植").options.contains(.pavilion))
        #expect(!ZXArt.poetryScene(text: "纤云弄巧", title: "鹊桥仙").options.contains(.bridge))
        #expect(!ZXArt.poetryScene(text: "今宵酒醒何处", title: "雨霖铃").options.contains(.rain))
        #expect(!ZXArt.poetryScene(text: "晚风吹过", title: "西江月").options.contains(.moon))
        #expect(ZXArt.poetryScene(text: "接天莲叶无穷碧，映日荷花别样红", title: "晓出净慈寺送林子方").scene == .lotusPond)
    }

    @Test func lotusPhenologyIsSavedWithThePoemAndDoesNotChangeWithSeed() throws {
        for (text, expected) in [("小荷才露尖尖角", ZXArt.LotusState.young), ("残荷听雨", .spent),
            ("枯荷满塘", .spent), ("留得残荷听雨声", .spent), ("接天莲叶无穷碧", .flowering)] {
            let selection = ZXArt.poetryScene(text: text)
            for index in 0..<6 {
                let recipe = selection.paintingProcedural(seed: "lotus-poem-\(index)")
                #expect(recipe.params.scene?.lotusState == expected)
                #expect(try JSONDecoder().decode(ZXArt.Procedural.self, from: JSONEncoder().encode(recipe)) == recipe)
            }
        }
        // Old recipes without a state remain decodable; scenes default to full lotus.
        let options = try JSONDecoder().decode(ZXArt.SceneOptions.self, from: Data("{\"motifs\":[\"lotus\"]}".utf8))
        #expect(options.lotusState == nil)
    }

    @Test func sharedSkyAssetsAreVisibleDeterministicAndVaried() {
        for motif in [ZXArt.SceneMotif.moon, .crescent, .sunrise, .sunset, .stars, .rain, .snow] {
            var forms = Set<[ZXArt.P]>()
            for index in 0..<6 {
                let seed = ZXArt.Seed("atlas-\(motif.rawValue)-\(index)")
                let atlas = ShanShuiEngine(seed: seed).paintingAsset(motif)
                let shared = ShanShuiEngine(seed: seed).paintingAtmosphere(motif)
                #expect(!atlas.isEmpty)
                #expect(atlas.map(\.p) == shared.map(\.p))
                #expect(atlas.map(\.fil) == shared.map(\.fil))
                forms.insert(atlas.flatMap(\.p))
                #expect(atlas.flatMap(\.p).allSatisfy { $0.x.isFinite && $0.y.isFinite })
            }
            #expect(forms.count >= 3, "\(motif)")
        }
    }
}
