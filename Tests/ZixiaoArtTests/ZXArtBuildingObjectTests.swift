import CoreGraphics
import Testing
@testable import ZixiaoArt

struct ZXArtBuildingObjectTests {
    @Test func stageBAssetsRepeatAndVaryAtAtlasScale() {
        let motifs: [ZXArt.SceneMotif] = [.house, .hut, .pavilion, .pagoda, .templeGate, .courtyard,
            .ruins, .cityGate, .window, .curtain, .terrace, .fence, .boat, .mooredBoat, .angler, .sail]
        for motif in motifs {
            var silhouettes = Set<[Int]>()
            for index in 0..<6 {
                let seed = ZXArt.Seed("atlas-\(motif.rawValue)-\(index)")
                let first = ShanShuiEngine(seed: seed).paintingAsset(motif)
                let second = ShanShuiEngine(seed: seed).paintingAsset(motif)
                #expect(first.map(\.p) == second.map(\.p), "\(motif): seeded geometry")
                #expect(first.map(\.fil) == second.map(\.fil), "\(motif): seeded ink")
                #expect(first.map(\.str) == second.map(\.str))
                let points = first.flatMap(\.p)
                #expect(!points.isEmpty && points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
                let x0 = points.map(\.x).min()!, x1 = points.map(\.x).max()!
                let y0 = points.map(\.y).min()!, y1 = points.map(\.y).max()!
                // Deliberately coarse: compare layout and silhouettes, not every random brush hair.
                let cells = Set(points.map { p in
                    let x = Int((p.x - x0) / max(1, x1 - x0) * 12)
                    let y = Int((p.y - y0) / max(1, y1 - y0) * 12)
                    return y * 13 + x
                })
                silhouettes.insert(cells.sorted())
            }
            #expect(silhouettes.count >= 3, "\(motif) needs at least three forms in its six atlas seeds")
        }
    }

    @Test func boatHullsKeepPaperAndTheirAnchorContour() throws {
        for motif in [ZXArt.SceneMotif.boat, .mooredBoat, .angler, .sail] {
            for index in 0..<6 {
                let canv = ShanShuiEngine(seed: .init("atlas-\(motif.rawValue)-\(index)")).paintingAsset(motif)
                let hull = try #require(canv.first)
                #expect(hull.fil == .white, "The hull is outlined, never a grey silhouette")
                #expect(hull.p.first == hull.p.last)
                let x = hull.p.map(\.x), y = hull.p.map(\.y)
                #expect(x.max()! - x.min()! > (y.max()! - y.min()!) * 4)
                #expect(hull.p.first!.y < y.max()! - 5, "Bow rises above the waterline")
            }
        }
    }

    @Test func mooringJoinsHullToBankAndWindowStaysInHouse() throws {
        for size in [CGSize(width: 750, height: 1000), CGSize(width: 1200, height: 675)] {
            for scene in [ZXArt.PoetryScene.waterTown, .farewell, .moonNight] {
                for index in 0..<6 {
                    let selection = ZXArt.SceneSelection(scene: scene,
                        options: .init(motifs: ZXArt.defaultMotifs(for: scene)), matched: [])
                    let drawing = try #require(ZXArt.drawing(procedural: selection.paintingProcedural(seed: "objects-\(index)",
                        verseSide: "right"), palette: .paperInk, pixelSize: size))
                    if scene == .moonNight {
                        let house = try #require(drawing.sceneElements.first { $0.motif == "house" }).bounds.cgRect
                        let window = try #require(drawing.sceneElements.first { $0.motif == "window" }).bounds.cgRect
                        #expect(house.insetBy(dx: house.width * 0.08, dy: house.height * 0.1).contains(window))
                        #expect(window.minY > house.minY + house.height * 0.45)
                    } else {
                        let bank = try #require(drawing.sceneElements.first { $0.motif == "groundBank" }).bounds.cgRect
                        let boat = try #require(drawing.sceneElements.first { $0.motif == "mooredBoat" }).bounds.cgRect
                        let post = try #require(drawing.sceneElements.first { $0.motif == "mooringPost" }).bounds.cgRect
                        let rope = try #require(drawing.sceneElements.first { $0.motif == "mooringRope" }).bounds.cgRect
                        #expect(post.maxY >= bank.minY - 0.003 && post.maxY <= bank.maxY + 0.003)
                        #expect(post.midX >= bank.minX && post.midX <= bank.maxX)
                        #expect(rope.intersects(post.insetBy(dx: -0.002, dy: -0.002)))
                        #expect(rope.intersects(boat.insetBy(dx: -0.002, dy: -0.002)))
                        #expect(drawing.anchors?.boats.count == 1)
                        let anchor = try #require(drawing.anchors?.boats.first)
                        #expect(anchor.x >= boat.minX && anchor.x <= boat.maxX)
                    }
                }
            }
        }
    }
}
