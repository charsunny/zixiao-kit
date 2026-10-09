@testable import ZixiaoLibraryCore
import XCTest
@testable import ZixiaoLibrary

final class ModelDecodingTests: XCTestCase {
    func testDecodesLunyu() throws {
        let book = try JSONDecoder().decode(Book.self, from: Fixtures.data("lunyu.json"))
        XCTAssertEqual(book.schema, 1)
        XCTAssertEqual(book.id, "lunyu")
        XCTAssertEqual(book.version, 1)
        XCTAssertEqual(book.title, "论语")
        XCTAssertEqual(book.titleHant, "論語")
        XCTAssertEqual(book.author, "孔子弟子及再传弟子")
        XCTAssertEqual(book.dynasty, "春秋战国")
        XCTAssertEqual(book.category, "经")
        XCTAssertEqual(book.subcategory, "四书")
        XCTAssertEqual(book.tags, ["p0", "儒"])
        XCTAssertEqual(book.script, "hans")
        XCTAssertEqual(book.updated, "2026-09-27")
        XCTAssertEqual(book.hash, "sha256:870e56ac2e77d860e9baa391e889acfc6058cfcfa92d7a5cc46ae54e4050a589")
        XCTAssertEqual(book.plain.kindValue, .none)
        XCTAssertEqual(book.source.name, "zh.wikisource")
        XCTAssertEqual(book.source.license, "CC-BY-SA-4.0")
        XCTAssertEqual(book.source.attribution, "维基文库贡献者")
        XCTAssertEqual(book.source.revid, 10602746)
        XCTAssertEqual(book.source.pages?.count, 20)
        XCTAssertEqual(book.source.pages?.first?.title, "論語/學而第一")
        XCTAssertEqual(book.source.crossChecked, ["daizhige-org:儒藏/四书/论语.md"])
        XCTAssertEqual(book.chapters.count, 20)
        XCTAssertEqual(book.passageCount, 501)
        XCTAssertEqual(book.chapters[0].title, "学而第一")
        XCTAssertEqual(book.chapters[16].no, 17)

        let p = try XCTUnwrap(book.passage(id: "01.01"))
        XCTAssertTrue(p.text.hasPrefix("子曰：“学而时习之"))
        XCTAssertFalse(p.hasPlain)
        XCTAssertTrue(p.notes.isEmpty)
        XCTAssertNotNil(book.passage(id: "02.17"))
        XCTAssertNil(book.passage(id: "99.01"))
    }

    func testDecodesBundledCatalog() throws {
        let catalog = try JSONDecoder().decode(BookCatalog.self, from: Fixtures.data("catalog.json"))
        XCTAssertEqual(catalog.schema, 1)
        XCTAssertEqual(catalog.generated, "2026-09-28")
        XCTAssertEqual(catalog.books.map(\.id), ["lunyu", "daodejing", "xinjing", "caigentan", "chanshi"])
        XCTAssertEqual(catalog.featured.count, 5)
        let lunyu = try XCTUnwrap(catalog.entry(id: "lunyu"))
        XCTAssertFalse(lunyu.bundled, "bundled 不在 JSON 里, 由 BookStore 合并时标")
        XCTAssertEqual(lunyu.authorLine, "春秋战国 · 孔子弟子及再传弟子")
        XCTAssertEqual(catalog.books(in: "子").count, 3)
    }

    func testDecodesCloudCatalogWithURLHashBytes() throws {
        let catalog = try JSONDecoder().decode(BookCatalog.self, from: Fixtures.data("cloud-catalog.json"))
        let xinjing = try XCTUnwrap(catalog.entry(id: "xinjing"))
        XCTAssertEqual(xinjing.version, 1)
        XCTAssertEqual(xinjing.hash, Fixtures.xinjingHash)
        XCTAssertEqual(xinjing.sha256Hex, String(Fixtures.xinjingHash.dropFirst(7)))
        XCTAssertEqual(xinjing.bytes, 1442)
        XCTAssertEqual(xinjing.downloadURL?.absoluteString, "https://qizen.weshici.com/books/v1/xinjing/1/book.json.gz")
        XCTAssertFalse(xinjing.hasPlain)
    }

    /// 诗词集的段级字段: 题 / 作者 / 段级出处 (cross_checked 是字符串) / verified / zen_verses; 以及白话与注。
    func testDecodesPassageVariants() throws {
        let json = #"""
        {"id":"01.01","title":"凡读我诗者","author":"寒山","dynasty":"唐","text":"凡读我诗者，心中须护净。\n悭贪继日廉，谄曲登时正。",
         "plain":"凡是读我诗的人……","notes":[{"anchor":"护净","text":"守护清净","src":"编者"}],"tags":["修身"],
         "source":{"name":"zh.wikisource","url":"https://x","page":"寒山詩","revid":2673216,"license":"CC-BY-SA-4.0",
                   "scan_revids":[2672915],"cross_checked":"chinese-poetry 全唐诗","stanzas":[1,2]},
         "verified":true,"zen_verses":["white-cloud"]}
        """#
        let p = try JSONDecoder().decode(Passage.self, from: Data(json.utf8))
        XCTAssertEqual(p.title, "凡读我诗者")
        XCTAssertEqual(p.author, "寒山")
        XCTAssertEqual(p.lines.count, 2)
        XCTAssertTrue(p.hasPlain)
        XCTAssertEqual(p.notes, [PassageNote(anchor: "护净", text: "守护清净", src: "编者")])
        XCTAssertEqual(p.source?.crossChecked, ["chinese-poetry 全唐诗"])
        XCTAssertEqual(p.source?.scanRevids, [2672915])
        XCTAssertEqual(p.verified, true)
        XCTAssertEqual(p.zenVerses, ["white-cloud"])

        // 往返不丢字段。
        let again = try JSONDecoder().decode(Passage.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(again, p)
    }

    func testBookRoundTripsAndDefaults() throws {
        let minimal = #"{"id":"x","title":"小书","chapters":[{"id":"01","paragraphs":[{"id":"01.01","text":"一"}]}]}"#
        let book = try JSONDecoder().decode(Book.self, from: Data(minimal.utf8))
        XCTAssertEqual(book.version, 1)
        XCTAssertEqual(book.category, "子")
        XCTAssertEqual(book.plain.kind, "none")
        XCTAssertEqual(book.chapters[0].no, 0)

        let lunyu = try JSONDecoder().decode(Book.self, from: Fixtures.data("lunyu.json"))
        let roundTrip = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(lunyu))
        XCTAssertEqual(roundTrip, lunyu)
    }

    func testUnknownPlainKindFallsBackToNone() throws {
        let info = try JSONDecoder().decode(PlainInfo.self, from: Data(#"{"kind":"future-kind","label":"意译"}"#.utf8))
        XCTAssertEqual(info.kindValue, .none)
        XCTAssertEqual(info.label, "意译")
        let reviewed = try JSONDecoder().decode(PlainInfo.self, from: Data(#"{"kind":"llm-draft","reviewed_by":"某"}"#.utf8))
        XCTAssertEqual(reviewed.kindValue, .llmDraft)
        XCTAssertEqual(reviewed.reviewedBy, "某")
    }
}
