import Foundation
import ZixiaoDesign

// 线装书版式的纯计算: 一章的段落 → 列 → 页。与 Flutter 版 `classic_layout.dart` 同规则, 不依赖 UI,
// 所以能单测, 也能在后台预排。
//
// 规矩只有三条, 都是古书本来的:
// * 字从上到下, 列从右到左;
// * 一段起一列 (起行), 诗每句起一列;
// * 标点不居列首 —— 列满了而下一个字是标点, 就把它挤在列尾。

/// 一个字格。
public struct ClassicCell: Sendable, Hashable {
    /// 已换成直排形的字。
    public var glyph: String
    /// 原字 (横排形), 无障碍朗读与复制用 —— 直排标点读屏念不出来。
    public var original: String
    public var passageId: String
    /// 在段落里的第几个字 (按字素计, 含被跳过的空白), 将来做句级摘抄与进度用。
    public var index: Int
    public var isPunctuation: Bool
}

public struct ClassicColumn: Sendable, Hashable {
    public var cells: [ClassicCell]
    /// 这一列属于哪一段。
    public var passageId: String

    /// 这一列的原文 (横排标点)。
    public var text: String { cells.map(\.original).joined() }
}

public struct ClassicPage: Sendable, Hashable {
    /// `columns[0]` 是最右一列。
    public var columns: [ClassicColumn]

    public var firstPassageId: String? { columns.first?.passageId }

    public func contains(passageId: String) -> Bool { columns.contains { $0.passageId == passageId } }
}

public enum ClassicLayout {
    /// 把一章排成页。`charsPerColumn` 与 `columnsPerPage` 由页面尺寸算出。
    public static func paginate(passages: [Passage], charsPerColumn: Int, columnsPerPage: Int) -> [ClassicPage] {
        let perColumn = max(1, charsPerColumn)
        let perPage = max(1, columnsPerPage)
        var columns: [ClassicColumn] = []
        for passage in passages {
            // 诗: 换行即换列。散文: 一段一列起。
            for line in passage.lines {
                var cells: [ClassicCell] = []
                var index = 0
                for ch in line {
                    defer { index += 1 }
                    if ch.isWhitespace { continue }
                    // 标点表与直排形用 ZixiaoDesign 的 `ZXVerticalForms`, 与 `VerticalText` 同源。
                    let punct = ZXVerticalForms.isPunctuation(ch)
                    // 列满时: 标点可以挤成第 N+1 个, 其余另起一列。
                    if cells.count >= perColumn && !(punct && cells.count == perColumn) {
                        columns.append(ClassicColumn(cells: cells, passageId: passage.id))
                        cells = []
                    }
                    cells.append(ClassicCell(glyph: String(ZXVerticalForms.vertical(ch)), original: String(ch), passageId: passage.id,
                                             index: index, isPunctuation: punct))
                }
                if !cells.isEmpty { columns.append(ClassicColumn(cells: cells, passageId: passage.id)) }
            }
        }
        return stride(from: 0, to: columns.count, by: perPage).map {
            ClassicPage(columns: Array(columns[$0..<min($0 + perPage, columns.count)]))
        }
    }

    /// 含某段的第一页, 找不到给 0。
    public static func page(containing passageId: String?, in pages: [ClassicPage]) -> Int {
        guard let passageId else { return 0 }
        return pages.firstIndex { $0.contains(passageId: passageId) } ?? 0
    }
}

/// 汉字数目: 页码「十七」、章序「第十七章」。
public enum HanNumeral {
    private static let digits = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    /// 0…9999 的通行写法: 十、十七、四十六、一百零五、一千二百。超出范围退回阿拉伯数字 ——
    /// 书页不会有那么多, 与其写错不如直说。
    public static func string(_ n: Int) -> String {
        guard (0...9999).contains(n) else { return String(n) }
        if n < 10 { return digits[n] }
        // 十几省「一」: 十、十七 (而「一百一十」里的一十不省, 交给下面的通用分支)。
        if n < 20 { return "十" + (n == 10 ? "" : digits[n % 10]) }
        let units: [(Int, String)] = [(1000, "千"), (100, "百"), (10, "十"), (1, "")]
        var out = ""
        var pendingZero = false
        for (value, unit) in units {
            let d = (n / value) % 10
            if d == 0 {
                if !out.isEmpty { pendingZero = true }
                continue
            }
            if pendingZero { out += "零"; pendingZero = false }
            out += digits[d] + unit
        }
        return out
    }

    /// 「第十七章」; `unit` 可换成「卷」「回」「葉」。
    public static func ordinal(_ n: Int, unit: String = "章") -> String { "第\(string(n))\(unit)" }
}
