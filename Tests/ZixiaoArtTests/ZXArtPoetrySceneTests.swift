import CoreGraphics
import Foundation
import XCTest
@testable import ZixiaoArt

final class ZXArtPoetrySceneTests: XCTestCase {
    func testSceneEvidenceAndTitleFalseFriends() {
        let cases: [(String, String, ZXArt.PoetryScene)] = [
            ("明月松间照，清泉石上流", "山居秋暝", .retreat),
            ("青箬笠，绿蓑衣，斜风细雨不须归", "渔歌子", .fishing),
            ("水村山郭酒旗风", "江南春", .waterTown),
            ("客舍青青柳色新", "送元二使安西", .farewell),
            ("依依墟里烟", "归园田居", .village),
            ("千朵万朵压枝低", "江畔独步寻花", .spring),
            ("小荷才露尖尖角", "小池", .lotusPond),
            ("枯藤老树昏鸦，古道西风瘦马", "天净沙·秋思", .autumnTravel),
            ("风雪夜归人", "逢雪宿芙蓉山主人", .winterForest),
            ("举头望明月", "静夜思", .moonNight),
            ("清晨入古寺", "题破山寺后禅院", .temple),
            ("庭院深深深几许", "蝶恋花", .courtyard),
            ("念天地之悠悠", "登幽州台歌", .historic),
            ("大漠孤烟直，长河落日圆", "使至塞上", .desert),
            ("海上生明月", "望月怀远", .ocean),
        ]
        for (text, title, expected) in cases {
            XCTAssertEqual(ZXArt.poetryScene(text: text, title: title).scene, expected, title)
        }
        XCTAssertNotEqual(ZXArt.poetryScene(text: "春光正好", title: "天净沙").scene, .desert)
        XCTAssertFalse(ZXArt.poetryScene(text: "纤云弄巧", title: "鹊桥仙").options.contains(.bridge))
        XCTAssertFalse(ZXArt.poetryScene(text: "岁月如流，三月初三").options.contains(.moon))
    }

    func testWeatherStateAndSmokeAreNotInterchangeable() {
        let after = ZXArt.poetryScene(text: "空山新雨后", title: "山居秋暝")
        XCTAssertTrue(after.options.contains(.afterRain))
        XCTAssertFalse(after.options.contains(.rain))
        let village = ZXArt.poetryScene(text: "依依墟里烟", title: "归园田居")
        XCTAssertTrue(village.options.contains(.cookingSmoke))
        XCTAssertFalse(village.options.contains(.mist))
        let desert = ZXArt.poetryScene(text: "大漠孤烟直，长河落日圆")
        XCTAssertTrue(desert.options.contains(.beaconSmoke))
        XCTAssertFalse(desert.options.contains(.mist))
        let moon = ZXArt.poetryScene(text: "晓风残月，月落乌啼")
        XCTAssertTrue(moon.options.contains(.crescent))
        XCTAssertFalse(moon.options.contains(.moon))
        XCTAssertFalse(moon.options.contains(.sunset))
    }

    func testSceneRecipeRoundTripAndIndependentVersion() throws {
        let source = ZXArt.poetryScene(text: "大漠孤烟直，长河落日圆").procedural(seed: "review-1")
        let recipe = try JSONDecoder().decode(ZXArt.Procedural.self, from: JSONEncoder().encode(source))
        XCTAssertEqual(recipe, source)
        XCTAssertTrue(recipe.isSupported)
        XCTAssertEqual(recipe.downgraded(), recipe, "V3 rollout cannot change the separate scene generator")
        XCTAssertTrue(ZXArt.Procedural.supportedGenerators.contains("shanshui@4"))
        var unknown = recipe; unknown.generator = "shanshui@99"
        XCTAssertFalse(unknown.isSupported)
        unknown = recipe; unknown.variant = "未知场景"
        XCTAssertFalse(unknown.isSupported)
    }

    func testEverySceneFitsEveryVerseSideAndFrameDeterministically() throws {
        let sizes = [CGSize(width: 510, height: 510), CGSize(width: 750, height: 1000), CGSize(width: 1062, height: 598)]
        for scene in ZXArt.PoetryScene.allCases {
            for size in sizes {
                for side in ["left", "right", "top"] {
                    let selection = ZXArt.SceneSelection(scene: scene, options: .init(motifs: ZXArt.defaultMotifs(for: scene)), matched: [])
                    let p = selection.procedural(seed: "geometry-" + scene.rawValue, verseSide: side)
                    let drawing = try XCTUnwrap(ZXArt.drawing(procedural: p, palette: .paperInk, pixelSize: size))
                    let repeatDrawing = try XCTUnwrap(ZXArt.drawing(procedural: p, palette: .paperInk, pixelSize: size))
                    XCTAssertEqual(drawing.sceneElements, repeatDrawing.sceneElements)
                    XCTAssertEqual(drawing.shapeCount, repeatDrawing.shapeCount)
                    XCTAssertGreaterThan(drawing.sceneElements.count, 1, "\(scene) / \(side) / \(size)")
                    let verse = try XCTUnwrap(p.verseLayout(pixelSize: size)).rect
                    for element in drawing.sceneElements {
                        let rect = CGRect(x: element.bounds.x, y: element.bounds.y, width: element.bounds.width, height: element.bounds.height)
                        XCTAssertTrue(CGRect(x: -0.001, y: -0.001, width: 1.002, height: 1.002).contains(rect))
                        XCTAssertFalse(rect.intersects(verse), "\(scene): \(element.motif) occludes verse")
                    }
                    for shape in drawing.layers.flatMap(\.shapes) {
                        XCTAssertTrue(shape.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
                    }
                    XCTAssertLessThan(drawing.pointCount, 150_000, "bounded background cost")
                }
            }
        }
    }
}
