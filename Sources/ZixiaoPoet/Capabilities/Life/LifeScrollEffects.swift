import ZixiaoPoetCore
//  LifeScrollEffects.swift — 长卷的滚动手感: 卷封面吸附、封面视差、点年份落到哪一刻
//
//  - 吸附 (`LifeCoverSnap`): 只有卷封面是吸附目标, 刻照常自由滚。手指离开时系统给出惯性落点,
//    落点落在某张封面「里」(封面露出一部分) 就补到两头之一 —— 封面整张贴顶, 或封面整张让出
//    (正文贴着导航栏下沿开始); 落点正好停在一张封面「前」不远且正往下翻, 就把那张封面翻上来。
//    其余落点一概不动, 读刻时不被拽走。
//  - 视差 (`LifeParallax`): 画比内容慢 (落后 0.4), 卷名反向略快并淡出, 印不动; 第一卷在顶端
//    下拉时画被拉长贴住屏顶, 不露纸。全部是 `visualEffect` 里的纯函数, 不起状态、不触发布局。
//  - 年份落点 (`LifeJump`): 点年轨上的年份 → 那一年的第一刻; 那年没有刻 → 所在卷里那年之后的
//    第一刻 (没有就最后一刻); 卷里一刻都没有 (桩卷) → 卷封面。

import SwiftUI

// MARK: - 吸附

/// 一张卷封面在内容坐标里的位置 (含顶端出血带)。
struct LifeCoverSpan: Equatable {
    var minY: CGFloat
    var height: CGFloat
    var maxY: CGFloat { minY + height }
}

/// 各卷封面的最新位置。吸附行为持有它的引用而不是一份快照: SwiftUI 会在几份留存的行为值上
/// 调 `updateTarget` (D2b 实测: 同一时刻有的值还带着懒加载估算期的旧位置, 把一次跳卷拽偏了),
/// 引用保证每一份读到的都是最新的; 位置变了也不必让根页重算 body。
@MainActor
final class LifeCoverStore {
    private var frames: [Int: CGRect] = [:]
    /// 封面顶端出血带的高。
    var bleed: CGFloat = 0
    /// 滚到一刻用的锚点 (`LifeMetrics.momentAnchor`), 随版面更新。放在这里而不是让闭包捕获 metrics:
    /// `.task` 等长寿闭包会抓住第一次布局 (安全区还是 0) 的值 (D2b 实测 `-lifeMoment` 落进了状态栏下)。
    var momentAnchor: UnitPoint = .top

    /// 程序跳转 (点年份、拖轨、VoiceOver、DEBUG) 期间不吸附: 跳转那一刻懒加载的卷高常在改,
    /// 封面的新位置要晚一拍才报上来, 拿旧位置去吸会把跳转拽偏 (D2b 实测)。用户手势不经过这里。
    private var holdUntil: ContinuousClock.Instant?

    func set(_ frame: CGRect, for sequence: Int) { frames[sequence] = frame }

    func holdSnapping(for duration: Duration = .milliseconds(800)) {
        holdUntil = ContinuousClock.now.advanced(by: duration)
    }

    var isHolding: Bool { holdUntil.map { ContinuousClock.now < $0 } ?? false }

    var spans: [LifeCoverSpan] {
        frames.values.map { LifeCoverSpan(minY: $0.minY, height: $0.height) }.sorted { $0.minY < $1.minY }
    }
}

/// 只吸卷封面的滚动目标行为。坐标: 长卷的滚动视图忽略顶端安全区, 内容偏移 0 就是内容顶贴屏顶,
/// 所以「封面贴顶」的偏移就是封面在内容里的 minY。
/// 程序滚动 (`scrollTo`) 也会经过这里 (速度 0): 跳卷落在封面顶、跳刻落在正文里, 都不在吸附区内, 原样放行。
struct LifeCoverSnap: ScrollTargetBehavior {
    let store: LifeCoverStore
    /// 停在封面里多深以内回弹到封面顶 (占封面可让出行程的比例)。
    static let snapBackProgress: CGFloat = 0.4
    /// 封面前多远 (占封面高的比例) 以内, 正往下翻就把封面翻上来。
    static let pullInFraction: CGFloat = 0.4
    /// 低于这个速度算「松手停住」, 不按方向判。单位是 pt/ms (实测: 700 pt/s 的拖动报 0.69), 0.1 ≈ 100 pt/s。
    static let restingVelocity: CGFloat = 0.1
    /// 离封面顶 / 让出位这么近就算已经对齐 (浮点误差), 不再动。
    static let tolerance: CGFloat = 1

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard context.axes.contains(.vertical) else { return }
        let (covers, bleed, holding) = MainActor.assumeIsolated { (store.spans, store.bleed, store.isHolding) }
        guard !covers.isEmpty, !holding else { return }
        let proposed = target.rect.minY
        let velocity = context.velocity.dy
        let maxOffset = max(context.contentSize.height - context.containerSize.height, 0)
        guard let snapped = Self.snap(proposed, velocity: velocity, covers: covers, bleed: bleed) else { return }
        target.rect.origin.y = min(snapped, maxOffset)
    }

    /// 纯函数, 便于推演: 落点 `proposed` (内容偏移) 该补到哪; nil = 不吸。
    static func snap(_ proposed: CGFloat, velocity: CGFloat, covers: [LifeCoverSpan], bleed: CGFloat) -> CGFloat? {
        for cover in covers {
            let top = cover.minY
            let passOut = cover.maxY - bleed
            guard passOut > top else { continue }
            if proposed > top + tolerance, proposed < passOut - tolerance {
                // 落在封面里: 停得浅回封面顶, 停得深翻过封面; 有明显方向时顺着方向走, 不逆着手。
                let progress = (proposed - top) / (passOut - top)
                let threshold: CGFloat = velocity > restingVelocity ? 0.15
                    : velocity < -restingVelocity ? 0.85 : snapBackProgress
                return progress < threshold ? top : passOut
            }
            if proposed <= top, proposed >= top - cover.height * pullInFraction, velocity > restingVelocity {
                // 正往下翻, 落点停在封面前不远: 把封面翻上来。往回翻 (读上一卷卷末) 不拦。
                return top
            }
        }
        return nil
    }
}

// MARK: - 视差

enum LifeParallax {
    /// 画相对内容落后的比例: 内容走 1, 画在屏上只走 0.6。
    static let artLag: CGFloat = 0.4
    /// 卷名反向的漂移比例。
    static let titleDrift: CGFloat = 0.15
    /// 封面离开顶端多少 (占封面高) 时卷名淡尽。
    static let titleFadeSpan: CGFloat = 0.45

    /// 画需要的下沿余量: 封面从下方进场、下沿已在屏内时, 画上移最多 `artLag × (视口高 − 封面高)`。
    static func overscan(viewport: CGFloat, cover: CGFloat) -> CGFloat {
        (artLag * max(viewport - cover, 0)).rounded(.up) + 2
    }

    /// 画的位移 / 拉伸。`minY`: 封面顶在滚动视图里的 y (贴屏顶 = 0)。
    static func art(minY: CGFloat, isFirst: Bool, overscan: CGFloat, height: CGFloat,
                    reduceMotion: Bool) -> (offset: CGFloat, scale: CGFloat) {
        if isFirst, minY > 0 {
            // 第一卷在顶端下拉: 画顶钉在屏顶, 往下拉长, 不露出画上方的纸。跟手 1:1, 不算动效。
            return (-minY, (height + minY) / max(height, 1))
        }
        guard !reduceMotion else { return (0, 1) }
        return (max(-artLag * minY, -overscan), 1)
    }

    /// 卷名: 封面往上离开时反向略快 (多上移一点) 并淡出; 进场时不动。
    static func title(minY: CGFloat, height: CGFloat, reduceMotion: Bool) -> (offset: CGFloat, opacity: Double) {
        guard !reduceMotion, minY < 0 else { return (0, 1) }
        let progress = min(-minY / max(height * titleFadeSpan, 1), 1)
        return (titleDrift * minY, Double(1 - progress))
    }
}

/// 只把上沿往外扩的矩形: 第一卷的画要伸进导航栏下, 其余三边照常裁。
struct LifeTopBleedRect: Shape {
    var top: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - top, width: rect.width, height: rect.height + top))
    }
}

// MARK: - 年份落点

/// 点一个年份要去的地方。
struct LifeJump: Equatable {
    /// 卷 (epochSequence)。
    var chapter: Int
    /// 卷里的那一刻; nil = 卷封面。
    var moment: String?

    static func resolve(year: Int, in chapters: [PoetMoments.Chapter]) -> LifeJump? {
        guard let first = chapters.first else { return nil }
        // 那一年有刻: 第一刻。
        for chapter in chapters {
            if let moment = chapter.moments.first(where: { $0.workDating != .contextual && $0.date.year == year }) {
                return LifeJump(chapter: chapter.epochSequence, moment: moment.id)
            }
        }
        // 没有刻: 所在卷 (起始年不晚于这一年的最后一卷), 卷里那年之后的第一刻, 否则最近的一刻。
        let chapter = chapters.last { $0.startYear <= year } ?? first
        let dated = chapter.moments.filter { $0.workDating != .contextual }
        let moment = dated.first { $0.date.year > year } ?? dated.last
        return LifeJump(chapter: chapter.epochSequence, moment: moment?.id)
    }
}
