import CryptoKit
import XCTest
@testable import ZixiaoLibrary

final class GzipTests: XCTestCase {
    /// 流水线产物 (`gzip -9`, mtime=0) 解压后与目录 hash 一致。
    func testDecompressesPipelineGzipAndMatchesCatalogHash() throws {
        let gz = try Fixtures.data("xinjing.json.gz")
        XCTAssertTrue(Gzip.isGzip(gz))
        let raw = try Gzip.decompress(gz)
        XCTAssertEqual(raw.count, 3065)
        XCTAssertEqual("sha256:" + BookStore.sha256Hex(raw), Fixtures.xinjingHash)
        let book = try JSONDecoder().decode(Book.self, from: raw)
        XCTAssertEqual(book.id, "xinjing")
    }

    /// 带 FNAME 头的 gzip (Python `gzip.GzipFile(filename=…)` 生成): 头部变长也要跳对。
    func testSkipsFileNameHeader() throws {
        let gz = try XCTUnwrap(Data(base64Encoded: "H4sICAAAAAAC/2hlbGxvLmpzb24Aq1Z6una6khWQXPaioefZ9G1Pdi54srNbqRYAE0QyMRkAAAA="))
        let raw = try Gzip.decompress(gz)
        XCTAssertEqual(String(decoding: raw, as: UTF8.self), #"{"字":"学而时习之"}"#)
    }

    func testRejectsNonGzipAndCorruption() throws {
        XCTAssertThrowsError(try Gzip.decompress(Data("{\"id\":\"x\"}—————————".utf8))) {
            XCTAssertEqual($0 as? Gzip.Failure, .notGzip)
        }
        var gz = try Fixtures.data("xinjing.json.gz")
        XCTAssertThrowsError(try Gzip.decompress(gz.prefix(gz.count / 2)))
        // 改尾部 CRC 的一个字节: 正文照样能解, 但必须被 CRC 挡住。
        gz[gz.count - 8] ^= 0xFF
        XCTAssertThrowsError(try Gzip.decompress(gz)) {
            XCTAssertEqual($0 as? Gzip.Failure, .checksumMismatch)
        }
    }

    func testCRC32KnownVector() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
    }
}
