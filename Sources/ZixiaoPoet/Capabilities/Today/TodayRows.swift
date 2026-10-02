//  TodayRows.swift — 今日一刻之下的配角: 此刻在哪 / 继续读 / 本周
//
//  三行都是一行一事, 不套卡片: 小字分节名 + 一行内容。朱色只给本周里的「今天」。

import MapKit
import SwiftUI
import ZixiaoDesign

// MARK: - 此刻在哪

/// 一张不可操作的小地图 (以本刻驻点为中心) + 地名 + 所在卷。点开是本卷行迹。
struct TodayPlaceRow: View {
    let coordinate: CLLocationCoordinate2D
    let place: String
    let chapterTitle: String?
    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    static let mapHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            TodaySectionTitle("此刻在哪")
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: theme.space.md) { map; label }
            } else {
                HStack(spacing: theme.space.lg) {
                    map.frame(maxWidth: 168)
                    label
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(theme.type.caption.weight(.semibold))
                        .foregroundStyle(theme.color.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var map: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate, span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4))),
            interactionModes: []) {
            Annotation(place, coordinate: coordinate, anchor: .center) {
                Circle().fill(theme.color.textPrimary)
                    .frame(width: theme.space.sm, height: theme.space.sm)
                    .overlay { Circle().strokeBorder(theme.paper(), lineWidth: ZXMetric.hairline * 2) }
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        .frame(height: Self.mapHeight)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
        .accessibilityHidden(true)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: theme.space.xs) {
            Text(place).font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
            if let chapterTitle {
                Text(chapterTitle).font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
            }
        }
    }
}

// MARK: - 继续读

struct TodayResumeRow: View {
    let title: String
    let progress: Double
    let finished: Bool
    @Environment(\.zxTheme) private var theme

    private var status: String {
        if finished { return "已读完" }
        let percent = Int((min(max(progress, 0), 1) * 100).rounded())
        return percent <= 0 ? "刚开始" : "读到 \(percent)%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            TodaySectionTitle("继续读")
            HStack(spacing: theme.space.md) {
                VStack(alignment: .leading, spacing: theme.space.xs) {
                    Text("《\(title)》").font(theme.type.headline).foregroundStyle(theme.color.textPrimary)
                    HStack(spacing: theme.space.sm) {
                        ProgressView(value: finished ? 1 : min(max(progress, 0), 1))
                            .tint(theme.color.textSecondary)
                            .frame(maxWidth: 120)
                            .accessibilityHidden(true)
                        Text(status).font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(theme.type.caption.weight(.semibold))
                    .foregroundStyle(theme.color.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: LifeUI.minTapTarget)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("继续读，\(title)，\(status)")
    }
}

// MARK: - 本周

/// 本周的一天。
struct TodayWeekDay: Identifiable, Hashable {
    let date: Date
    let key: String
    /// 「一」…「日」。
    let weekday: String
    let lunarMonth: Int
    let lunarDay: Int
    var id: String { key }

    /// `today` 所在的那一周 (周一起, 东八区)。
    static func week(containing today: Date) -> [TodayWeekDay] {
        var calendar = DailyRotation.calendar
        calendar.firstWeekday = 2
        guard let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        let names = ["一", "二", "三", "四", "五", "六", "日"]
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let lunar = PoetLunarDay.of(date)
            return TodayWeekDay(date: date, key: TodayPickStore.dateKey(date), weekday: names[offset],
                                lunarMonth: lunar.month, lunarDay: lunar.day)
        }
    }
}

/// 七个小格。今天用朱色, 正在看的那一天垫一层底; 有刻 / 有可读记载的日子下面一个墨点。
struct TodayWeekStrip: View {
    let days: [TodayWeekDay]
    let todayKey: String
    let selectedKey: String
    let marked: Set<String>
    let select: (TodayWeekDay) -> Void
    @Environment(\.zxTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            TodaySectionTitle("本周")
            if typeSize.isAccessibilitySize {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.space.xs), count: 4),
                          spacing: theme.space.sm) { cells }
            } else {
                HStack(spacing: theme.space.xs) { cells }
            }
        }
    }

    @ViewBuilder private var cells: some View {
        ForEach(days) { day in cell(day) }
    }

    private func cell(_ day: TodayWeekDay) -> some View {
        let isToday = day.key == todayKey
        let isSelected = day.key == selectedKey
        let hasMark = marked.contains(day.key)
        return Button { select(day) } label: {
            VStack(spacing: theme.space.xxs) {
                Text(day.weekday)
                    .font(theme.type.caption.weight(isToday ? .semibold : .regular))
                    .foregroundStyle(isToday ? theme.seal : theme.color.textSecondary)
                Text(TodayText.cellDay(month: day.lunarMonth, day: day.lunarDay))
                    .font(theme.type.footnote.weight(isToday ? .semibold : .regular))
                    .foregroundStyle(isToday ? theme.seal : theme.color.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Circle()
                    .fill(hasMark ? theme.ink(0.55) : Color.clear)
                    .frame(width: theme.space.xs, height: theme.space.xs)
            }
            .padding(.vertical, theme.space.sm)
            .frame(maxWidth: .infinity, minHeight: LifeUI.minTapTarget)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous).fill(theme.color.fill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(day, isToday: isToday, hasMark: hasMark))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityLabel(_ day: TodayWeekDay, isToday: Bool, hasMark: Bool) -> String {
        var parts = ["星期\(day.weekday)", TodayText.monthDay(month: day.lunarMonth, day: day.lunarDay)]
        if isToday { parts.append("今天") }
        if hasMark { parts.append("有记载") }
        return parts.joined(separator: "，")
    }
}

// MARK: - 分节名

/// 配角的分节名: 墨色小字, 不带朱色记号 —— 这一页的朱色只给本周里的「今天」。
struct TodaySectionTitle: View {
    let text: String
    @Environment(\.zxTheme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(theme.type.footnote.weight(.semibold))
            .foregroundStyle(theme.color.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}
