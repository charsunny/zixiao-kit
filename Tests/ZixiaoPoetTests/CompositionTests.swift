import Foundation
import XCTest
import ZixiaoCalendar
@testable import ZixiaoPoet

/// 迁自 PoetKit `EditorialAvailabilityTests` (前两例原样); 导读离线路径一例改用占位导读 ——
/// 具体诗人的导读随产品 App 包发, 内核测试不再读它们。
final class CompositionTests: XCTestCase {
    func testDailyCardsKeepEditorialOrderAndHideUnavailableExactDateHistory() throws {
        let composition = try PoetFixtures.composition(
            cards: ["resume", "on-this-day", "work-of-day", "resume"],
            includesOnThisDayConfig: true,
            dayPrecise: 0
        )

        XCTAssertEqual(composition.configuredDailyCards, [.resume, .onThisDay, .workOfDay])
        XCTAssertEqual(composition.enabledDailyCards, [.resume, .workOfDay])
    }

    func testExactDateHistoryRequiresItsConfiguration() throws {
        let withoutConfiguration = try PoetFixtures.composition(
            cards: ["on-this-day", "work-of-day"], includesOnThisDayConfig: false, dayPrecise: 12)
        let withConfiguration = try PoetFixtures.composition(
            cards: ["on-this-day", "work-of-day"], includesOnThisDayConfig: true, dayPrecise: 12)

        XCTAssertEqual(withoutConfiguration.enabledDailyCards, [.workOfDay])
        XCTAssertEqual(withConfiguration.enabledDailyCards, [.onThisDay, .workOfDay])
    }

    func testInjectedGuideContainsCompleteOfflineChapterPaths() throws {
        let bundle = try PoetFixtures.bundle(files: ["guide-placeholder.json": PoetFixtures.guideJSON])
        let resources = PoetResources(bundle: bundle, slug: "placeholder", productName: "占位志")
        let guide = try resources.guide()
        XCTAssertEqual(guide.chapters.count, 2)
        XCTAssertFalse(guide.sources.isEmpty)
        for chapter in guide.chapters {
            XCTAssertFalse(chapter.paragraphs.isEmpty)
            XCTAssertFalse(chapter.workIDs.isEmpty)
            for poemID in chapter.workIDs {
                let poem = try XCTUnwrap(guide.poem(poemID))
                XCTAssertFalse(poem.content.isEmpty)
                XCTAssertEqual(guide.chapter(containing: poem.id)?.id, chapter.id)
            }
        }
    }

    func testCompositionLoadsFromInjectedBundle() throws {
        let json = try PoetFixtures.compositionJSON(cards: ["work-of-day"], includesOnThisDayConfig: false,
                                                    dayPrecise: 0)
        let bundle = try PoetFixtures.bundle(files: ["composition.json": json])
        let composition = try PoetComposition.load(from: bundle)
        XCTAssertEqual(composition.app.displayName, "测试志")
        XCTAssertEqual(composition.app.appSlug, "test")

        let empty = try PoetFixtures.bundle(files: [:])
        XCTAssertThrowsError(try PoetComposition.load(from: empty)) { error in
            guard case CompositionError.notFound("composition") = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    /// 年号走 ZixiaoCalendar 的共用表 (PoetKit 自带的 eras.json 已删, 两表逐条相同)。
    func testEraLabelsComeFromTheSharedCalendarTable() {
        let era = EraNaming(style: .eraName)
        XCTAssertEqual(era.label(1037), "景祐四年")
        XCTAssertEqual(era.label(1082), "元丰五年")
        XCTAssertEqual(era.label(1094), "绍圣元年")
        XCTAssertEqual(era.label(1101), "建中靖国元年")
        for year in 1037...1101 {
            XCTAssertFalse(era.label(year).hasPrefix("\(year)"), "宋 \(year) 年没有年号")
        }
        XCTAssertEqual(era.label(701), "大足元年")
        XCTAssertEqual(era.label(742), "天宝元年")
        XCTAssertEqual(era.label(759), "乾元二年")
        XCTAssertEqual(EraNaming(style: .eraNameApprox).label(742), "约天宝元年")
        XCTAssertEqual(EraNaming(style: .gregorian).label(742), "742年")
    }

    func testLunarYearSexagenaryFollowsTheLunarNewYear() {
        XCTAssertEqual(PoetLunarDay.sexagenary(ofLunarYear: 2026), "丙午")
        XCTAssertEqual(PoetLunarDay.sexagenary(ofLunarYear: 1082), "壬戌")
        XCTAssertEqual(PoetLunarDay.sexagenary(ofLunarYear: 4), "甲子")
    }
}
