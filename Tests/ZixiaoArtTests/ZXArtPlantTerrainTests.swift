import CoreGraphics
import Testing
@testable import ZixiaoArt

struct ZXArtPlantTerrainTests {
    @Test func plantAndTerrainAtlasSeedsRepeatAndHaveDistinctSilhouettes() {
        for motif in [ZXArt.SceneMotif.oldTree, .bareTree, .vine, .blossom, .lotus, .bamboo, .pine, .grass,
                      .waterfall, .reef, .dunes] {
            var silhouettes = Set<[Int]>()
            for index in 0..<6 {
                let seed = ZXArt.Seed("atlas-\(motif.rawValue)-\(index)")
                let first = ShanShuiEngine(seed: seed).paintingAsset(motif)
                let second = ShanShuiEngine(seed: seed).paintingAsset(motif)
                #expect(first.map(\.p) == second.map(\.p))
                #expect(first.map(\.fil) == second.map(\.fil))
                let points = first.flatMap(\.p)
                #expect(!points.isEmpty && points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
                let x0 = points.map(\.x).min()!, x1 = points.map(\.x).max()!
                let y0 = points.map(\.y).min()!, y1 = points.map(\.y).max()!
                let cells = Set(points.map { p in
                    Int((p.y - y0) / max(1, y1 - y0) * 12) * 13 + Int((p.x - x0) / max(1, x1 - x0) * 12)
                })
                silhouettes.insert(cells.sorted())
            }
            #expect(silhouettes.count >= 3, "\(motif): variation must survive coarse atlas resolution")
        }
    }

    @Test func lotusAtlasIncludesYoungFloweringAndSpentPlants() {
        let stages = (0..<6).map { index in
            ShanShuiEngine(seed: .init("atlas-lotus-\(index)")).paintingLotusDrawing().stage
        }
        #expect(Set(stages) == Set(ShanShuiEngine.LotusStage.allCases))
        for stage in ShanShuiEngine.LotusStage.allCases {
            var forms = Set<[ZXArt.P]>()
            for index in 0..<6 {
                let lotus = ShanShuiEngine(seed: .init("atlas-lotus.\(stage.rawValue)-\(index)"))
                    .paintingLotusDrawing(stage: stage)
                #expect(lotus.stage == stage)
                let points = lotus.canvas.flatMap(\.p)
                #expect(points.contains { hypot($0.x - lotus.flowerTip.x, $0.y - lotus.flowerTip.y) < 2 })
                forms.insert(points)
            }
            #expect(forms.count == 6)
        }
    }

    @Test func waterfallJoinsTheExistingStreamInBothFormats() throws {
        let selection = ZXArt.SceneSelection(scene: .retreat,
            options: .init(motifs: [.waterfall, .stream, .pine]), matched: [])
        for size in [CGSize(width: 750, height: 1000), CGSize(width: 1200, height: 675)] {
            for index in 0..<6 {
                let drawing = try #require(ZXArt.drawing(procedural: selection.paintingProcedural(
                    seed: "waterfall-connection-\(index)", verseSide: "right"), palette: .paperInk, pixelSize: size))
                let fall = try #require(drawing.sceneElements.first { $0.motif == "waterfall" }).bounds.cgRect
                let stream = try #require(drawing.sceneElements.first { $0.motif == "stream" }).bounds.cgRect
                #expect(abs(fall.maxY - stream.minY) < 0.008)
                #expect(fall.minY < stream.minY - 0.02)
                #expect(fall.maxX > stream.minX && fall.minX < stream.maxX)
            }
        }
    }

    @Test func massifsHaveBroadFeetAndContinuousSummitBearingPlanes() throws {
        for form in PaintingMountainProfile.Form.allCases {
            for index in 0..<6 {
                for terraced in [false, true] {
                    let engine = ShanShuiEngine(seed: .init("atlas-massif.\(form)-\(index)"))
                    let canvas = engine.paintingMountain(form: form, terraced: terraced)
                    let outline = try #require(canvas.first)
                    #expect(outline.fil == .white)
                    let xs = outline.p.map(\.x), ys = outline.p.map(\.y)
                    #expect(xs.max()! - xs.min()! >= (ys.max()! - ys.min()!) * 0.45)
                    if terraced {
                        let top = ys.min()!
                        #expect(zip(outline.p, outline.p.dropFirst()).contains { a, b in
                            abs(a.y - top) < 0.001 && abs(b.y - top) < 0.001 && b.x > a.x
                        }, "The summit terrace needs an actual horizontal bearing segment")
                    }
                }
            }
        }
    }

    @Test func treePerchesRemainOnBranchesAndVinesStayWithTheirTree() throws {
        for old in [false, true] {
            for index in 0..<6 {
                let tree = ShanShuiEngine(seed: .init("tree-attachments-\(index)")).paintingWoodyTree(old: old)
                let ink = tree.canvas.filter { $0.fil != .white }.flatMap(\.p)
                #expect(tree.perches.count >= 4)
                for perch in tree.perches {
                    #expect(ink.contains { hypot($0.x - perch.x, $0.y - perch.y) < 4 }, "A crow must sit on a real branch")
                }
                let xs = tree.canvas.flatMap(\.p).map(\.x), ys = tree.canvas.flatMap(\.p).map(\.y)
                let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
                #expect(tree.vine.flatMap(\.p).allSatisfy { box.insetBy(dx: -8, dy: -8).contains(CGPoint(x: $0.x, y: $0.y)) })
            }
        }
    }
}
