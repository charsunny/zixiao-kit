import SwiftUI
import XCTest
@testable import ZixiaoDesign

final class VerticalTextTests: XCTestCase {
    /// 与 Flutter `vertical_forms.dart` 的表逐项一致。
    func testFormsTableMatchesFlutter() {
        let expected: [Character: Character] = [
            "，": "︐", "。": "︒", "、": "︑", "：": "︓", "；": "︔", "！": "︕", "？": "︖",
            "「": "﹁", "」": "﹂", "『": "﹃", "』": "﹄", "“": "﹁", "”": "﹂", "‘": "﹃", "’": "﹄",
            "（": "︵", "）": "︶", "《": "︽", "》": "︾", "〈": "︿", "〉": "﹀", "—": "｜", "…": "︙",
        ]
        XCTAssertEqual(ZXVerticalForms.map, expected)
    }

    func testConvert() {
        XCTAssertEqual(ZXVerticalForms.convert("春眠不觉晓，处处闻啼鸟。"), "春眠不觉晓︐处处闻啼鸟︒")
        XCTAssertEqual(ZXVerticalForms.convert("《论语》：「学而」"), "︽论语︾︓﹁学而﹂")
        XCTAssertEqual(ZXVerticalForms.convert("abc 天地"), "abc 天地")
    }

    func testPunctuationDetection() {
        XCTAssertTrue(ZXVerticalForms.isPunctuation("，"))
        XCTAssertTrue(ZXVerticalForms.isPunctuation("︒"))   // 已转过的直排形也算
        XCTAssertTrue(ZXVerticalForms.isPunctuation("·"))
        XCTAssertFalse(ZXVerticalForms.isPunctuation("天"))
    }

    func testGlyphsSplitLinesIntoColumns() {
        let g = ZXVerticalLayout.glyphs("床前明月光，\n疑是地上霜。")
        XCTAssertEqual(String(g.map(\.character)), "床前明月光︐疑是地上霜︒")
        XCTAssertEqual(g.filter(\.startsLine).count, 1)
        XCTAssertTrue(g[6].startsLine)
        // 不回绕: 每行一列
        XCTAssertEqual(ZXVerticalLayout.columns(g, capacity: nil), [Array(0...5), Array(6...11)])
    }

    func testWrapAndHangingPunctuation() {
        let g = ZXVerticalLayout.glyphs("学而时习之，不亦说乎")
        // 一列 5 字: 「，」排到第 6 格放不下, 挂在第一列末尾, 不居第二列之首
        let cols = ZXVerticalLayout.columns(g, capacity: 5)
        XCTAssertEqual(cols, [Array(0...5), Array(6...9)])
        // 一列 3 字: 普通回绕
        XCTAssertEqual(ZXVerticalLayout.columns(g, capacity: 3).map(\.count), [3, 3, 3, 1])
    }

    func testBlankLineKeepsAnEmptyColumn() {
        let g = ZXVerticalLayout.glyphs("甲\n\n乙")
        XCTAssertEqual(ZXVerticalLayout.columns(g, capacity: nil).count, 3)
        XCTAssertEqual(ZXVerticalLayout.columns([], capacity: 4), [[]])
    }

    // MARK: - 逐字效果

    func testGlyphEffectIdentityAndDefaults() {
        XCTAssertTrue(ZXGlyphEffect().isIdentity)
        XCTAssertFalse(ZXGlyphEffect(opacity: 0.5).isIdentity)
        XCTAssertFalse(ZXGlyphEffect(blur: 1).isIdentity)
        XCTAssertFalse(ZXGlyphEffect(scale: 1.06).isIdentity)
        XCTAssertTrue(ZXGlyphEffect(opacity: 1, blur: 0, scale: 1).isIdentity)
        // 缺省环境里没有效果函数: 竖排不加任何修饰器。
        XCTAssertNil(EnvironmentValues().zxGlyphEffect)
    }

    /// 字序号 = 阅读顺序: 换行符不占序号, 每个字格一个序号 (效果函数按这个序号取)。
    func testGlyphIndexIsReadingOrder() {
        let g = ZXVerticalLayout.glyphs("床前明月光，\n疑是地上霜。")
        XCTAssertEqual(g.count, 12)
        let columns = ZXVerticalLayout.columns(g, capacity: nil)
        XCTAssertEqual(columns.flatMap { $0 }, Array(0..<12), "列从右到左、列内自上而下, 序号恰好依次")
    }
}
