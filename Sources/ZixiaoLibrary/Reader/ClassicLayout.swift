import ZixiaoLibraryCore
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
    /// 白话 (夹注 / 白话列) 的格子按白话里的位置计。
    public var index: Int
    public var isPunctuation: Bool
}

/// 白话在竖排里怎么摆 (纯版式; 与界面上的「夹注 / 对照 / 不显示白话」一一对应)。
public enum ClassicPlainLayout: Sendable, Hashable {
    /// 不排白话。
    case none
    /// 双行夹注: 白话以小字接在原文段后 —— 末列还有空格就从空处起, 每列两行, 右行先读。
    case interlinear
    /// 白话另起列: 单行小字, 接在原文段后的新列里 (竖排的「对照」)。
    case columns
}

/// 一列里的双行夹注: 从第 `startRow` 个小字行起, 右行、左行各若干字。
///
/// 小字行以半格计: 一格原文的高度排两行小字 (`ClassicLayout.noteRowsPerCell`)。
/// 与正文一样, 标点不居行首 —— 行满了而下一个字是标点, 就挤在行尾, 所以一行可能比空位多一个字。
public struct ClassicNoteRun: Sendable, Hashable {
    /// 起点 (小字行, 自列首起算)。原文占了 k 格, 夹注就从 `k * noteRowsPerCell` 起。
    public var startRow: Int
    /// 右行 (先读)。
    public var right: [ClassicCell]
    /// 左行 (后读)。
    public var left: [ClassicCell]

    /// 按读序 (先右后左) 的白话原文。
    public var text: String { (right + left).map(\.original).joined() }
    /// 两行里较长的那行占几行 (含挤进来的标点)。
    public var rowCount: Int { max(right.count, left.count) }
}

public struct ClassicColumn: Sendable, Hashable {
    /// 一列排的是原文还是白话列 (`ClassicPlainLayout.columns`)。
    public enum Role: Sendable, Hashable {
        case text
        case plain
    }

    /// 原文列: 大字格; 白话列: 小字格 (每格半格高)。只有夹注的列 `cells` 为空。
    public var cells: [ClassicCell]
    /// 这一列属于哪一段。
    public var passageId: String
    public var role: Role = .text
    /// 接在这一列原文之后 (或独占一列) 的双行夹注。
    public var notes: ClassicNoteRun?

    /// 这一列的原文 (横排标点); 白话列是那一截白话。不含夹注, 夹注见 `notes?.text`。
    public var text: String { cells.map(\.original).joined() }
}

public struct ClassicPage: Sendable, Hashable {
    /// `columns[0]` 是最右一列。
    public var columns: [ClassicColumn]

    public var firstPassageId: String? { columns.first?.passageId }

    public func contains(passageId: String) -> Bool { columns.contains { $0.passageId == passageId } }

    /// 本页里属于某段的列 (下标, 自右起), 高亮与定位用。
    public func columnIndices(of passageId: String) -> [Int] {
        columns.indices.filter { columns[$0].passageId == passageId }
    }
}

public enum ClassicLayout {
    /// 一格原文的高度排几行夹注小字。定成整数, 版式才能先算后画、纯函数可测。
    public static let noteRowsPerCell = 2

    /// 把一章排成页。`charsPerColumn` 与 `columnsPerPage` 由页面尺寸算出。
    /// `plain` 决定白话 (段落 `plain` 非空时) 怎么排; 默认不排, 与旧版式逐列相同。
    public static func paginate(passages: [Passage], charsPerColumn: Int, columnsPerPage: Int,
                                plain: ClassicPlainLayout = .none) -> [ClassicPage] {
        let perColumn = max(1, charsPerColumn)
        let perPage = max(1, columnsPerPage)
        var columns: [ClassicColumn] = []
        for passage in passages {
            // 诗: 换行即换列。散文: 一段一列起。
            for line in passage.lines {
                for cells in flow(cells(of: line, passageId: passage.id), perColumn: perColumn) {
                    columns.append(ClassicColumn(cells: cells, passageId: passage.id))
                }
            }
            guard plain != .none, passage.hasPlain, let text = passage.plain else { continue }
            let notes = cells(of: text, passageId: passage.id)
            guard !notes.isEmpty else { continue }
            switch plain {
            case .none:
                break
            case .columns:
                for cells in flow(notes, perColumn: perColumn * noteRowsPerCell) {
                    columns.append(ClassicColumn(cells: cells, passageId: passage.id, role: .plain))
                }
            case .interlinear:
                // 末列属于本段、还有空格: 夹注从空处起 (古书的双行小注正是这样紧接正文)。
                var startRow = 0
                var fillsLast = false
                if let last = columns.last, last.passageId == passage.id, last.role == .text, last.notes == nil,
                   last.cells.count < perColumn {
                    startRow = last.cells.count * noteRowsPerCell
                    fillsLast = true
                }
                let runs = interlinearRuns(notes, rowsPerColumn: perColumn * noteRowsPerCell, firstStartRow: startRow)
                for (k, run) in runs.enumerated() {
                    if k == 0 && fillsLast {
                        columns[columns.count - 1].notes = run
                    } else {
                        columns.append(ClassicColumn(cells: [], passageId: passage.id, notes: run))
                    }
                }
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

    /// 一行字 → 字格: 跳过空白 (但 `index` 照数), 换直排形。
    /// 标点表与直排形用 ZixiaoDesign 的 `ZXVerticalForms`, 与 `VerticalText` 同源。
    static func cells(of line: String, passageId: String) -> [ClassicCell] {
        var cells: [ClassicCell] = []
        for (index, ch) in line.enumerated() where !ch.isWhitespace {
            cells.append(ClassicCell(glyph: String(ZXVerticalForms.vertical(ch)), original: String(ch),
                                     passageId: passageId, index: index,
                                     isPunctuation: ZXVerticalForms.isPunctuation(ch)))
        }
        return cells
    }

    /// 字格 → 列: 每列 `perColumn` 字; 列满时下一个字若是标点, 挤成第 N+1 个, 其余另起一列。
    static func flow(_ cells: [ClassicCell], perColumn: Int) -> [[ClassicCell]] {
        let perColumn = max(1, perColumn)
        var columns: [[ClassicCell]] = []
        var current: [ClassicCell] = []
        for cell in cells {
            if current.count >= perColumn && !(cell.isPunctuation && current.count == perColumn) {
                columns.append(current)
                current = []
            }
            current.append(cell)
        }
        if !current.isEmpty { columns.append(current) }
        return columns
    }

    /// 双行夹注的切分 (纯函数): 第一段从 `firstStartRow` 起, 之后每段占满一整列。
    ///
    /// * 放得下一整列 (两行各占满空位): 右行、左行各 `rows` 字, 先右后左;
    /// * 最后一段: 两行对半分, 右行多一字 —— 两行齐头收尾, 是古书双行小注的样子;
    /// * 标点不居行首: 左行首字是标点就挤进右行末, 下一列首字是标点就挤进本列左行末。
    static func interlinearRuns(_ cells: [ClassicCell], rowsPerColumn: Int, firstStartRow: Int) -> [ClassicNoteRun] {
        let rowsPerColumn = max(1, rowsPerColumn)
        var runs: [ClassicNoteRun] = []
        var i = 0
        var start = min(max(0, firstStartRow), rowsPerColumn - 1)
        while i < cells.count {
            let rows = rowsPerColumn - start
            let remaining = cells.count - i
            var total: Int
            var rightCount: Int
            if remaining <= rows * 2 {
                total = remaining
                rightCount = (remaining + 1) / 2
            } else {
                total = rows * 2
                rightCount = rows
                if cells[i + total].isPunctuation { total += 1 }
            }
            if rightCount < total, cells[i + rightCount].isPunctuation { rightCount += 1 }
            runs.append(ClassicNoteRun(startRow: start,
                                       right: Array(cells[i..<(i + rightCount)]),
                                       left: Array(cells[(i + rightCount)..<(i + total)])))
            i += total
            start = 0
        }
        return runs
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
