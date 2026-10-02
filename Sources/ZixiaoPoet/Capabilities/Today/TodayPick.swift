//  TodayPick.swift — 今日一刻: 选哪一刻、怎么记住
//
//  一天只有一个主角。按优先级:
//  (a) 编好的刻 (`PoetMoments`) 里, 日精度、农历月日正是这一天的;
//  (b) 年谱里这一天的事目, 关联着库里读得到的作品 (`PoetStore.linkedEvents`) —— 由事目 + 作品合成一刻;
//  (c) 都没有就在同月前后若干天里就近取 (刻优先, 再事目), 并明说「取最近的 X月X日」;
//  (d) 年谱也没有 (诗人没有事目, 或附近全无关联作品) 就退到导读的选读篇目, 不带日子。
//
//  同一天的候选不止一个时按日序号轮换 (`DailyRotation`), 选定后按日期记进 UserDefaults
//  (`TodayPickStore`): 重启不换, 离线也能把今天这一页再翻开。

import Foundation
import ZixiaoDesign

/// 今日页的一刻 (已解析成界面要的字段, 可缓存)。
struct TodayPick: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        /// 编好的刻。
        case moment
        /// 由年谱事目 + 关联作品合成。
        case event
        /// 导读选读 (没有日子)。
        case reading
    }

    let kind: Kind
    /// 刻 id / 事目 id / `reading-<作品 id>`。也是转场源的 id。
    let id: String
    /// 刻 id (kind == .moment)。
    let momentID: String?
    /// 这一刻涉及的事目 (算「另有 N 条记载」时扣掉)。
    let eventIDs: [UUID]
    /// 公元年 (夏历年对应的公元年数); 选读为 nil。
    let year: Int?
    /// 农历月日 (选读为 nil)。
    let month: Int?
    let day: Int?
    /// 月日正是所看的那一天; false = 就近取的。
    let isExact: Bool
    /// 作品题 (竖排的那一行)。
    let title: String
    /// 引句 (刻的 workQuote, 或作品首句)。
    let quote: String?
    /// 处境: 刻的按语 / 事目叙事 / 选读按语。
    let context: String
    let placeLabel: String?
    /// 驻点 (poet_stations.id)。
    let stationID: UUID?
    let latitude: Double?
    let longitude: Double?
    /// 所在卷 / 分期 (epochSequence)。
    let chapter: Int?
    let chapterTitle: String?
    /// 画屏的 seed (不含分期; 画时拼 `forPlace(seed, epoch: chapter)`)。
    let placeSeed: String
    /// 有墨迹就用墨迹做画面。
    let artworkID: String?
    /// 作品 (读本要推的那一篇)。离线取不到时为 nil, 点「读这一篇」再取。
    let workID: UUID?
    let poem: Poem?

    /// 画屏偏色: 按这一刻的农历月 (正二三春 …); 选读不偏。
    var season: ZXSeasonTint? {
        guard let month else { return nil }
        switch month {
        case 1...3: return .spring
        case 4...6: return .summer
        case 7...9: return .autumn
        default: return .winter
        }
    }

    var artRecipe: PoetScreenArt { .forPlace(placeSeed, epoch: chapter, season: season) }

    /// 「八月十九」(就近取时给读者看那一天)。
    var monthDayLabel: String? {
        guard let month, let day else { return nil }
        return TodayText.monthDay(month: month, day: day)
    }
}

// MARK: - 文字小件

enum TodayText {
    /// 「八月十九」「正月初三」。
    static func monthDay(month: Int, day: Int) -> String {
        let names = PoetMoments.MomentDate.lunarMonthNames
        let head = (1...12).contains(month) ? "\(names[month])月" : ""
        return head + ((1...30).contains(day) ? PoetMoments.MomentDate.lunarDay(day) : "")
    }

    /// 日格里的农历日: 初一写月名 (「九月」), 其余写日 (「十九」「初三」)。
    static func cellDay(month: Int, day: Int) -> String {
        day == 1 ? "\(PoetMoments.MomentDate.lunarMonthNames[min(max(month, 1), 12)])月"
            : PoetMoments.MomentDate.lunarDay(day)
    }

    /// 中文数字 (1–9999): 944 → 九百四十四, 1005 → 一千零五, 15 → 十五。其余原样。
    static func numeral(_ n: Int) -> String {
        let digits = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        guard n > 0, n < 10_000 else { return String(n) }
        if n < 10 { return digits[n] }
        if n < 20 { return "十" + (n == 10 ? "" : digits[n - 10]) }
        var out = "", pendingZero = false, started = false
        for (unit, name) in [(1000, "千"), (100, "百"), (10, "十"), (1, "")] {
            let d = (n / unit) % 10
            if d == 0 { if started { pendingZero = true }; continue }
            if pendingZero { out += "零"; pendingZero = false }
            out += digits[d] + name
            started = true
        }
        return out
    }

    /// 作品首句 (引句缺省): 第一行, 长段落 (文) 截到第一个句号; 再长截断。
    static func opening(_ poem: Poem) -> String? {
        guard let first = poem.lines.lazy.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else { return nil }
        var line = first
        if line.count > 32, let stop = line.firstIndex(where: { "。！？".contains($0) }) {
            line = String(line[...stop])
        }
        return line.count > 40 ? String(line.prefix(40)) + "…" : line
    }

    /// 竖排的题: 去掉括注 (「定风波（莫听穿林打叶声）」→「定风波」), 过长截断 (画里至多两列)。
    static func verticalTitle(_ title: String) -> String {
        var t = title.replacingOccurrences(of: "[（(][^）)]*[）)]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { t = title }
        return t.count > 10 ? String(t.prefix(9)) + "…" : t
    }
}

// MARK: - 选

@MainActor
enum TodayPicker {
    /// 就近取的窗口 (同月前后各几天)。
    static let window = 7

    /// 选出 `date` 那一天的一刻。年谱要联网: 取不到时抛错 (调用方有缓存用缓存, 没有就显示离线态);
    /// 当天就有编好的刻时不联网。
    static func pick(for date: Date, ctx: CompositionContext) async throws -> TodayPick? {
        let lunar = PoetLunarDay.of(date)
        let rotation = DailyRotation.dayNumber(date)
        let dayMoments = (ctx.moments?.chapters ?? []).flatMap { chapter in
            chapter.moments.filter { $0.date.precision == .day && $0.date.month == lunar.month }
                .map { (chapter: chapter, moment: $0) }
        }
        func moments(on day: Int) -> [(chapter: PoetMoments.Chapter, moment: PoetMoments.Moment)] {
            dayMoments.filter { $0.moment.date.day == day }
        }

        // (a) 当天的刻。
        let exact = moments(on: lunar.day)
        if !exact.isEmpty {
            let hit = exact[rotation % exact.count]
            return await momentPick(hit.moment, chapter: hit.chapter, exact: true, ctx: ctx)
        }

        let daily = ctx.composition.placement(.daily)
        let usesArchive = ctx.composition.enabledDailyCards.contains(.onThisDay)
        let fallback = daily?.onThisDay?.fallback ?? .nearestDay
        let reach = fallback == .hide ? 0 : window

        // (b)(c) 年谱: 一次取同月一个窗口, 先当天, 再由近及远; 同一距离刻优先。
        let linked: [PoetLinkedEvent] = usesArchive
            ? try await ctx.store.linkedEvents(month: lunar.month,
                                               days: max(1, lunar.day - reach)...min(30, lunar.day + reach))
            : []
        // 文 (诏敕表状居多) 只作末选: 当天只有文时, 先看附近的刻与诗词赋, 都没有再回来用它。
        var weak: (event: PoetLinkedEvent, exact: Bool)?
        for delta in 0...reach {
            let days = Set([lunar.day - delta, lunar.day + delta]).sorted()
            if delta > 0 {
                let near = days.flatMap { moments(on: $0) }
                if !near.isEmpty {
                    let hit = near[rotation % near.count]
                    return await momentPick(hit.moment, chapter: hit.chapter, exact: false, ctx: ctx)
                }
            }
            let candidates = linked.filter { $0.event.day.map(days.contains) ?? false }
            guard let chosen = choose(candidates, rotation: rotation) else { continue }
            if eventRank(chosen) <= formRank("fu") {
                return await linkedPick(chosen, exact: delta == 0, ctx: ctx)
            }
            if weak == nil { weak = (chosen, delta == 0) }
        }
        if let weak { return await linkedPick(weak.event, exact: weak.exact, ctx: ctx) }

        // (d) 导读选读。
        return readingPick(rotation: rotation, ctx: ctx)
    }

    /// 事目 → 一刻: 已经编进某一刻的用刻 (有按语、有长卷可去), 否则由事目合成。
    private static func linkedPick(_ chosen: PoetLinkedEvent, exact: Bool, ctx: CompositionContext) async -> TodayPick {
        if let owner = ctx.moments?.chapters.lazy.compactMap({ chapter in
            chapter.moments.first { $0.eventIds.contains(chosen.event.id) }.map { (chapter, $0) }
        }).first {
            return await momentPick(owner.1, chapter: owner.0, exact: exact, ctx: ctx)
        }
        return eventPick(chosen, exact: exact, ctx: ctx)
    }

    nonisolated static func eventRank(_ e: PoetLinkedEvent) -> Int { e.works.map { formRank($0.poem.form) }.min() ?? 9 }

    /// 同一天的事目里挑一条: 诗词赋优先于文 (诏敕表状读来不是「今天读它的理由」), 再看匹配置信度;
    /// 最好的一档里按日序号轮换。
    private static func choose(_ events: [PoetLinkedEvent], rotation: Int) -> PoetLinkedEvent? {
        guard !events.isEmpty else { return nil }
        let best = events.map(eventRank).min() ?? 9
        let tier = events.filter { eventRank($0) == best }
            .sorted { ($0.event.year, $0.event.id.uuidString) < ($1.event.year, $1.event.id.uuidString) }
        let confident = tier.filter { ($0.bestWork?.matchScore ?? 0) >= 0.9 }
        let pool = confident.isEmpty ? tier : confident
        return pool[rotation % pool.count]
    }

    nonisolated static func formRank(_ form: String) -> Int {
        switch form {
        case "ci", "shi": 0
        case "fu": 1
        case "wen": 2
        default: 3
        }
    }

    private static func momentPick(_ moment: PoetMoments.Moment, chapter: PoetMoments.Chapter, exact: Bool,
                                   ctx: CompositionContext) async -> TodayPick {
        var poem: Poem?
        if let work = moment.workId {
            poem = ctx.guide?.poem(work)
            if poem == nil { poem = try? await ctx.store.poem(id: work) }
        }
        let station = moment.placeId.flatMap { id in ctx.store.stations.first { $0.id == id } }
        let place = station.map { (lat: $0.latitude, lon: $0.longitude) }
            ?? guidePlace(named: moment.placeLabel, ctx: ctx)
        return TodayPick(
            kind: .moment, id: moment.id, momentID: moment.id, eventIDs: moment.eventIds,
            year: moment.date.year, month: moment.date.month, day: moment.date.day, isExact: exact,
            title: poem.map(ctx.workTitle) ?? moment.title,
            quote: moment.workQuote ?? poem.flatMap(TodayText.opening),
            context: moment.lede, placeLabel: moment.placeLabel, stationID: moment.placeId,
            latitude: place?.lat, longitude: place?.lon,
            chapter: chapter.epochSequence, chapterTitle: chapter.title, placeSeed: chapter.placeSeed,
            artworkID: moment.artworkId, workID: moment.workId, poem: poem)
    }

    private static func eventPick(_ linked: PoetLinkedEvent, exact: Bool, ctx: CompositionContext) -> TodayPick {
        let event = linked.event
        let work = linked.bestWork
        let poem = work?.poem
        let chapter = ctx.moments?.chapters.first { $0.contains(year: event.year) }
        let epoch = chapter?.epochSequence ?? ctx.lifeEpochs.first { $0.contains(event.year) }?.sequence
        let place = linked.station?.displayName
        let seed = ctx.composition.placeSeed(for: place) ?? chapter?.placeSeed
            ?? place ?? "\(ctx.composition.poet.slug)-\(epoch ?? 0)"
        // 年谱写法的篇名更全时用它 (「念奴娇·中秋」比库里的词牌「念奴娇」认得出是哪一首)。
        let title: String = {
            guard let poem else { return work?.title ?? event.workTitles.first ?? "" }
            let shown = ctx.workTitle(poem)
            if let annal = work?.title, annal.count > shown.count, annal.hasPrefix(poem.title) { return annal }
            return shown
        }()
        return TodayPick(
            kind: .event, id: event.id.uuidString, momentID: nil, eventIDs: [event.id],
            year: event.year, month: event.month, day: event.day, isExact: exact,
            title: title, quote: poem.flatMap(TodayText.opening), context: event.narrative,
            placeLabel: place, stationID: linked.station?.id,
            latitude: linked.station?.latitude, longitude: linked.station?.longitude,
            chapter: epoch,
            chapterTitle: chapter?.title ?? ctx.lifeEpochs.first { $0.sequence == epoch }?.label,
            placeSeed: seed, artworkID: nil, workID: poem?.id, poem: poem)
    }

    /// 导读的选读篇目 (随包, 离线可得) 按日轮换。
    static func readingPick(rotation: Int, ctx: CompositionContext) -> TodayPick? {
        guard let guide = ctx.guide else { return nil }
        let featured = guide.featured.filter { guide.poem($0.id) != nil }
        guard !featured.isEmpty, let poem = guide.poem(featured[rotation % featured.count].id) else { return nil }
        let note = featured[rotation % featured.count].note
        let chapter = guide.chapter(containing: poem.id)
        let epoch = chapter?.epoch.sequence
        let seed = ctx.moments?.chapters.first { $0.epochSequence == epoch }?.placeSeed
            ?? "\(ctx.composition.poet.slug)-\(epoch ?? 0)"
        return TodayPick(
            kind: .reading, id: "reading-\(poem.id.uuidString)", momentID: nil, eventIDs: [],
            year: nil, month: nil, day: nil, isExact: true,
            title: ctx.workTitle(poem), quote: TodayText.opening(poem),
            context: note.isEmpty ? (chapter?.introduction ?? "") : note,
            placeLabel: nil, stationID: nil, latitude: nil, longitude: nil,
            chapter: epoch, chapterTitle: chapter?.epoch.label, placeSeed: seed,
            artworkID: nil, workID: poem.id, poem: poem)
    }

    /// 导读里同名的驻留地 (驻点还没拉回来时给地图一个落点)。
    static func guidePlace(named name: String?, ctx: CompositionContext) -> (lat: Double, lon: Double)? {
        guard let name, let place = ctx.guide?.places.first(where: { $0.name == name }) else { return nil }
        return (place.latitude, place.longitude)
    }
}

extension PoetLinkedEvent {
    /// 最该读的那一篇: 体裁 (诗词赋先于文) → 置信度 → 次序。
    var bestWork: LinkedWork? {
        works.min { a, b in
            let ra = TodayPicker.formRank(a.poem.form), rb = TodayPicker.formRank(b.poem.form)
            if ra != rb { return ra < rb }
            if (a.matchScore ?? 0) != (b.matchScore ?? 0) { return (a.matchScore ?? 0) > (b.matchScore ?? 0) }
            return a.ordinal < b.ordinal
        }
    }
}

// MARK: - 记住

/// 按日期记住选定的一刻 (UserDefaults, 按 App 隔离)。只留最近 `limit` 天。
@MainActor
enum TodayPickStore {
    /// 选法或字段变了就升版本, 旧缓存作废。
    static let version = 2
    static let limit = 14

    private static func key(_ app: String) -> String { "poetkit.today.v\(version).\(app)" }

    nonisolated static func dateKey(_ date: Date) -> String {
        let c = DailyRotation.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func all(_ app: String, defaults: UserDefaults) -> [String: TodayPick] {
        guard let data = defaults.data(forKey: key(app)),
              let decoded = try? JSONDecoder().decode([String: TodayPick].self, from: data) else { return [:] }
        return decoded
    }

    static func cached(for date: Date, app: String, defaults: UserDefaults = .standard) -> TodayPick? {
        all(app, defaults: defaults)[dateKey(date)]
    }

    /// 最近缓存的一刻 (离线态挑卷封面用)。
    static func latest(app: String, defaults: UserDefaults = .standard) -> TodayPick? {
        all(app, defaults: defaults).max { $0.key < $1.key }?.value
    }

    static func save(_ pick: TodayPick, for date: Date, app: String, defaults: UserDefaults = .standard) {
        var entries = all(app, defaults: defaults)
        entries[dateKey(date)] = pick
        if entries.count > limit {
            for stale in entries.keys.sorted().dropLast(limit) { entries[stale] = nil }
        }
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key(app)) }
    }

    static func clear(app: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(app))
    }
}
