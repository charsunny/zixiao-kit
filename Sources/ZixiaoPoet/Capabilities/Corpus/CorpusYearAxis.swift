import ZixiaoPoetCore
//  CorpusYearAxis.swift — 「按年读」年份轴的纯值模型
//
//  生年到卒年每年一格 (系年数据越出生卒的年份也收进来), 有作品的格子带篇数; 分期 (卷) 的起始年
//  是一条淡分隔。初始落在「当前一卷」里作品最多的那一年。轴末另有一个「未编年」伪年。
//  界面 (`CorpusYearSection`) 只画它, 测试不起视图就能核对。

import Foundation

struct CorpusYearAxis: Equatable, Sendable {
    /// 一段分期: 起始年与名 (卷名 / 分期名, 来自刻或导读)。
    struct Chapter: Equatable, Sendable {
        let start: Int
        let end: Int
        let label: String
    }

    struct Cell: Equatable, Sendable, Identifiable {
        let year: Int
        let count: Int
        /// 这一年是某一卷的起始年 (轴上在它前面画一条淡分隔; 第一格不画)。
        let startsChapter: Bool
        /// 所在分期的名 (VoiceOver 念)。
        let chapterLabel: String?
        var id: Int { year }
        var hasWorks: Bool { count > 0 }
    }

    let cells: [Cell]
    let chapters: [Chapter]
    /// 未编年篇数; nil = 不知道 (只说「尚未编年」, 不给数)。
    let undated: Int?
    let maxCount: Int

    var totalDated: Int { cells.reduce(0) { $0 + $1.count } }
    /// 没有一年有作品: 整节收起。
    var isEmpty: Bool { maxCount == 0 }

    /// - Parameters:
    ///   - lifespan: 编成的生卒年。
    ///   - counts: 年 → 篇数。
    ///   - chapters: 分期 (任意顺序; 按起始年排)。
    init(lifespan: ClosedRange<Int>, counts: [Int: Int], chapters: [Chapter], undated: Int?) {
        let years = counts.filter { $0.value > 0 }.keys
        let lower = min(lifespan.lowerBound, years.min() ?? lifespan.lowerBound)
        let upper = max(lifespan.upperBound, years.max() ?? lifespan.upperBound)
        let sorted = chapters.sorted { $0.start < $1.start }
        self.chapters = sorted
        func chapter(of year: Int) -> Chapter? { sorted.last { $0.start <= year } }
        let starts = Set(sorted.map(\.start))
        cells = (lower...upper).map { year in
            Cell(year: year, count: max(counts[year] ?? 0, 0),
                 startsChapter: year != lower && starts.contains(year),
                 chapterLabel: chapter(of: year)?.label)
        }
        self.undated = undated.map { max($0, 0) }
        maxCount = cells.map(\.count).max() ?? 0
    }

    func cell(_ year: Int) -> Cell? { cells.first { $0.year == year } }

    /// 一段年份里作品最多的一年 (同数取早); 这段里一篇都没有时取全轴最多的一年。全轴都没有为 nil。
    func peakYear(in range: ClosedRange<Int>? = nil) -> Int? {
        func peak(_ cells: [Cell]) -> Int? {
            cells.filter(\.hasWorks).max { a, b in a.count != b.count ? a.count < b.count : a.year > b.year }?.year
        }
        if let range, let hit = peak(cells.filter { range.contains($0.year) }) { return hit }
        return peak(cells)
    }

    /// 某年的分期 (年在两卷之间的空档时归前一卷)。
    func chapter(containing year: Int) -> Chapter? { chapters.last { $0.start <= year } }

    /// 当前一卷的年份: 依次取 最近读过的作品所在的卷 → 第一卷编好的长卷 → 作品最多的那一卷。
    static func focusRange(readChapter: ClosedRange<Int>?, writtenChapter: ClosedRange<Int>?,
                           axis: CorpusYearAxis) -> ClosedRange<Int>? {
        if let readChapter { return readChapter }
        if let writtenChapter { return writtenChapter }
        guard let peak = axis.peakYear(), let chapter = axis.chapter(containing: peak) else { return nil }
        return chapter.start...max(chapter.start, chapter.end)
    }
}
