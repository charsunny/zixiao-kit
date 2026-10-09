//  ReaderTimeline.swift — 读本「此时」的判定: 一篇作品落在一生的哪里。
//
//  纯函数, 不碰网络与界面 (测试直接喂 fixture)。顺序:
//  (a) 有一刻以这篇为作品 → 用刻 (编辑写过的年号、月日、地、按语);
//  (b) 否则年谱把它系到了事目 → 用主事目那一年的事目;
//  (c) 都没有 → 「未编年」。

import Foundation

/// 一篇作品在一生里的位置。
public enum ReaderPlacement: Equatable, Sendable {
    /// 编辑过的一刻以这篇为作品。
    case moment(PoetMoments.Moment)
    /// 没有刻, 但年谱系年到了事目: 主事目那一年的边, 按月日排 (非空)。
    case events([WorkEventLink])
    /// 没有系年。
    case undated

    /// 系年 (公元年数, 与事目表同一约定); 未编年为 nil。
    public var year: Int? {
        switch self {
        case .moment(let moment): return moment.workDating == .contextual ? nil : moment.date.year
        case .events(let links): return links.first?.event.year
        case .undated: return nil
        }
    }

    /// 事目所属的诗人。只有 (b) 带; 刻要另查作品的作者。
    public var poetID: UUID? {
        if case .events(let links) = self { return links.first?.poetId }
        return nil
    }
}

public enum ReaderTimeline {
    /// 「此时」卡最多列几条事目。
    public static let shownEventLimit = 2

    public static func placement(of poemID: UUID, moments: PoetMoments?, links: [WorkEventLink]) -> ReaderPlacement {
        if let moment = moment(for: poemID, in: moments) { return .moment(moment) }
        let events = primaryYearLinks(links)
        return events.isEmpty ? .undated : .events(events)
    }

    /// 以这篇为作品的第一刻 (按长卷的阅读顺序)。
    public static func moment(for poemID: UUID, in moments: PoetMoments?) -> PoetMoments.Moment? {
        guard let moments else { return nil }
        for chapter in moments.chapters {
            if let hit = chapter.moments.first(where: { $0.workId == poemID }) { return hit }
        }
        return nil
    }

    /// 主事目定年: 匹配分最高的那条 (缺分按 0), 同分取最早。返回那一年的全部边 (按事目去重),
    /// 按月日排, 只知年 / 月的排在后面。别的年份的边不混进来 —— 一张卡只讲一个时刻。
    public static func primaryYearLinks(_ links: [WorkEventLink]) -> [WorkEventLink] {
        var seen = Set<UUID>()
        let unique = links.filter { seen.insert($0.event.id).inserted }
        guard let primary = unique.min(by: { a, b in
            let (sa, sb) = (a.matchScore ?? 0, b.matchScore ?? 0)
            return sa != sb ? sa > sb : dateKey(a.event) < dateKey(b.event)
        }) else { return [] }
        return unique.filter { $0.event.year == primary.event.year }
            .sorted { dateKey($0.event) < dateKey($1.event) }
    }

    /// 同年作品: 按月日 (未知殿后) 稳定排序, 去重, 去掉当前这篇, 至多 `limit` 篇。
    public static func sameYearIDs(_ rows: [YearWorkRow], excluding poemID: UUID, limit: Int) -> [UUID] {
        var seen: Set<UUID> = [poemID]
        return rows.enumerated()
            .sorted { a, b in
                let (ka, kb) = (monthDay(a.element.month, a.element.day), monthDay(b.element.month, b.element.day))
                return ka != kb ? ka < kb : a.offset < b.offset
            }
            .map(\.element.poemId)
            .filter { seen.insert($0).inserted }
            .prefix(max(0, limit)).map { $0 }
    }

    /// 相关墨迹: `relatedPoemIDs` (或旧的单值 `relatedPoemID`) 指向这篇的, 按清单顺序。
    public static func relatedArtworks(for poemID: UUID, in artworks: [Artwork]) -> [Artwork] {
        artworks.filter { $0.relatedPoemIDs?.contains(poemID) == true || $0.relatedPoemID == poemID }
    }

    /// 「这一年还有 N 条记载」: 年内事目总数减去卡上已列的。
    public static func remainingCount(yearTotal: Int, shown: Int) -> Int { max(0, yearTotal - shown) }

    // MARK: 文字

    /// 刻的时地行:「元丰五年 · 三月（寒食） · 黄州」。
    public static func momentLine(_ moment: PoetMoments.Moment) -> String {
        if moment.workDating == .contextual {
            return ["主题选读", moment.placeLabel].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return [moment.date.displayLabel, moment.placeLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// 事目的时地行:「元丰五年 · 三月初五 · 黄州」。只知年时没有月日; 没有地时不写地。
    public static func eventLine(_ event: PoetEvent, eraLabel: String, place: String?) -> String {
        [eraLabel, event.lunarLabel, place].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// 地名: 优先预载驻点的古地名 (黄冈市 → 黄州); 没有预载时退回原始地名去掉行政后缀。
    public static func placeName(stationID: UUID?, stations: [Station], fallback: String?) -> String? {
        if let stationID, let station = stations.first(where: { $0.id == stationID }) { return station.displayName }
        guard let fallback, !fallback.isEmpty else { return nil }
        let trimmed = fallback.replacingOccurrences(of: "[市县区]$", with: "", options: .regularExpression)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// 事目正文的摘录: 叙事 (`PoetEvent.narrative`, 已去掉纪年与作品尾) 再去掉开头的处境套语
    /// (「在黄冈，任黄州团练副使。」「赴凤翔途中。」) —— 时地行已经写了, 卡上留给事情本身。
    /// 去完为空时保留原叙事。
    public static func excerpt(_ event: PoetEvent) -> String {
        let narrative = event.narrative
        let stripped = narrative
            .replacingOccurrences(of: #"^(?:(?:在|赴)[^，。]{1,16}[，。])?(?:任[^。]{1,30}。)?"#, with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? narrative : stripped
    }

    // MARK: 排序键

    private static func dateKey(_ event: PoetEvent) -> (Int, Int, Int) {
        (event.year, event.month ?? 13, event.day ?? 31)
    }
    private static func monthDay(_ month: Int?, _ day: Int?) -> (Int, Int) { (month ?? 13, day ?? 31) }
}
