import CoreGraphics
import Testing
@testable import ZixiaoArt

struct ZXArtCompositionTests {
    @Test func portraitLandscapesRiseBesideTheInscription() throws {
        let exceptions: Set<String> = ["historic", "ocean", "moon", "desert", "courtyard"]
        for poem in ZXArtSceneReviewTests.poems where !exceptions.contains(poem.id) {
            let selection = ZXArt.poetryScene(text: poem.text, title: poem.title)
            for seed in ["review-\(poem.id)"] + (0..<4).map({ "variety-\($0)-\(poem.id)" }) {
                let d = try #require(ZXArt.drawing(procedural: selection.paintingProcedural(seed: seed,
                    verseSide: "right", columns: 2, chars: 7), palette: .paperInk,
                    pixelSize: .init(width: 750, height: 1000)))
                let landscape = d.sceneElements.filter {
                    ["mainMountain", "guestMountain", "farMountain", "farShore", "oldTree", "willow", "pine", "blossom", "layeredTree"].contains($0.motif)
                }
                #expect(landscape.contains { $0.bounds.cgRect.minY <= 0.35 }, "\(seed): landscape must rise into upper left")
                if selection.scene == .retreat || selection.scene == .temple {
                    let peak = try #require(d.sceneElements.first { $0.motif == "mainMountain" }).bounds.cgRect
                    let deep = selection.paintingProcedural(seed: seed).params.scene?.composition == .depth
                    #expect(peak.height >= (deep ? 0.36 : 0.45), "\(seed): mountain height \(peak.height)")
                }
            }
        }
    }

    @Test func specialScenesHaveDepthAndAnchoredFocalPoints() throws {
        for size in [CGSize(width: 750, height: 1000), CGSize(width: 1200, height: 675)] {
            for scene in [ZXArt.PoetryScene.courtyard, .desert, .ocean] {
                for index in 0..<4 {
                    let poemID = scene == .courtyard ? "courtyard" : (scene == .desert ? "desert" : "ocean")
                    let poem = try #require(ZXArtSceneReviewTests.poems.first { $0.id == poemID })
                    let selection = ZXArt.poetryScene(text: poem.text, title: poem.title)
                    let d = try #require(ZXArt.drawing(procedural: selection.paintingProcedural(seed: "composition-\(index)"),
                        palette: .paperInk, pixelSize: size))
                    func box(_ name: String) throws -> CGRect {
                        try #require(d.sceneElements.first { $0.motif == name }, "\(scene) \(index) \(size): \(name)").bounds.cgRect
                    }
                    switch scene {
                    case .courtyard:
                        let wall = try box("courtyard"), rear = try box("courtyardRearHall")
                        #expect(wall.width < 0.75)
                        #expect(rear.minY < wall.minY)
                    case .desert:
                        let tower = try box("beaconTower"), smoke = try box("beaconSmoke")
                        #expect(abs(smoke.maxY - tower.minY) < 0.01)
                        #expect(smoke.midX >= tower.minX && smoke.midX <= tower.maxX)
                        let river = d.sceneElements.filter { $0.motif == "stream" }.map { $0.bounds.cgRect }
                        #expect(river.contains { $0.height > 0.15 })
                    case .ocean:
                        let moon = try box("moon"), reflection = try box("moonReflection"), reef = try box("reef")
                        #expect(moon.width > 0.12)
                        #expect(reflection.height > 0.20)
                        #expect(moon.maxY < reflection.minY)
                        #expect(reef.width > 0.13)
                    default: break
                    }
                }
            }
        }
    }
}
