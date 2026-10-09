import ZixiaoPoetCore
//  LifeScrollModel.swift — 一生长卷的取数与路由
//
//  刻里的作品只给了 id。导读随包带着一部分作品 (离线可读), 其余一次批量向库里取, 缓存在这里;
//  点开一篇还没取到的作品时再单取一次 (`PoetStore.poem(id:)`)。

import Foundation
import Observation

/// 长卷里推入的页。全部经一个 `navigationDestination(item:)` 推, 不在行里嵌 NavigationLink ——
/// 目的页类型由这里的 `AnyView` 切断 (真机 TypeDecoder 栈溢出, 见 `readingTransition`)。
enum LifeRoute: Hashable {
    /// 行迹 (现为全书地图; 本卷地图另做)。
    case map
    /// 年谱 (按年的事目目录)。
    case chronicle
    /// 交游。
    case network
    /// 读本。`source` 是转场源的 id (哪张封面放大进来)。
    case poem(Poem, source: String)
    /// 墨迹。
    case artwork(String)
    /// 资料与纪年说明。
    case sources
}

/// 年谱 sheet 的一年。
struct LifeYear: Identifiable, Hashable {
    let year: Int
    var id: Int { year }
}

/// 长卷里的滚动锚点。
enum LifeAnchor: Hashable {
    case chapter(Int)
    case moment(String)
}

@MainActor
@Observable
final class LifeScrollModel {
    private(set) var poems: [UUID: Poem] = [:]
    /// 正在单取的作品 (点了还没回来)。
    private(set) var resolving: Set<UUID> = []
    /// 批量取失败 (离线)。作品卡仍显示引句, 点开时再试。
    private(set) var prefetchFailed = false
    @ObservationIgnored private var prefetched = false

    func poem(_ id: UUID) -> Poem? { poems[id] }

    /// 先用导读里随包的作品, 其余一次批量取回。
    func prefetch(_ ids: [UUID], guide: PoetGuide?, store: PoetStore) async {
        guard !prefetched else { return }
        var missing: [UUID] = []
        var seen = Set<UUID>()
        for id in ids where seen.insert(id).inserted {
            if let local = guide?.poem(id) { poems[id] = local } else if poems[id] == nil { missing.append(id) }
        }
        guard !missing.isEmpty else { prefetched = true; return }
        do {
            for chunk in stride(from: 0, to: missing.count, by: 100).map({ Array(missing[$0..<min($0 + 100, missing.count)]) }) {
                for poem in try await store.poems(ids: chunk) { poems[poem.id] = poem }
            }
            prefetched = true
            prefetchFailed = false
        } catch {
            if !Task.isCancelled { prefetchFailed = true }
        }
    }

    /// 点开一篇: 有缓存直接给, 没有就单取。取不到返回 nil。
    func resolve(_ id: UUID, store: PoetStore) async -> Poem? {
        if let hit = poems[id] { return hit }
        guard resolving.insert(id).inserted else { return nil }
        defer { resolving.remove(id) }
        guard let fetched = try? await store.poem(id: id) else { return nil }
        poems[id] = fetched
        return fetched
    }
}

extension PoetMoments.Chapter {
    var anchor: LifeAnchor { .chapter(epochSequence) }

    /// 「卷一」…: 按卷在长卷里的位置 (1 起), 不按分期序号 (分期序号从 0 起)。
    static func ordinalLabel(_ position: Int) -> String { "卷\(chineseNumeral(position))" }

    static func chineseNumeral(_ n: Int) -> String {
        let digits = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        guard n > 0 else { return digits[0] }
        if n < 10 { return digits[n] }
        if n < 20 { return "十" + (n == 10 ? "" : digits[n - 10]) }
        if n < 100 { return digits[n / 10] + "十" + (n % 10 == 0 ? "" : digits[n % 10]) }
        return String(n)
    }
}
