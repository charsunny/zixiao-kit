import CoreGraphics
import Foundation
import Testing
@testable import ZixiaoArt

struct ZXArtElementsCompletionTests {
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
