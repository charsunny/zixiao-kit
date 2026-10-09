import ZixiaoPoetCore
import SwiftUI
import MapKit
import SwiftPieces
import ZixiaoDesign

/// 行迹: 本卷地图。`focusEpoch` 是分期序号 (与导读篇章的 `epoch.sequence` 同号); 缺省 = 「全部」总图。
/// 聚焦一卷时只有本卷的驻点与路线满强度, 其余驻点退成小灰点 (不可点), 地图缩放到本卷驻点。
struct LifeMapView: View {
    let ctx: CompositionContext
    @State private var camera: MapCameraPosition
    @State private var selectedPlaceID: String?
    @State private var selectedVisitID: Int?
    /// 聚焦的篇章 (epoch.sequence); -1 = 全部。
    @State private var chapterID: Int
    @State private var showingDirectory = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zxTheme) private var theme

    init(ctx: CompositionContext, focusEpoch: Int? = nil) {
        self.ctx = ctx
        let focus = focusEpoch.flatMap { epoch in
            ctx.guide?.visits.contains { $0.chapterID == epoch } == true ? epoch : nil
        } ?? Self.allChapters
        _chapterID = State(initialValue: focus)
        _camera = State(initialValue: Self.fit(Self.coordinates(ctx, chapter: focus)))
    }

    private static let allChapters = -1
    private static let allLabel = "全部"
    private var isFocused: Bool { chapterID != Self.allChapters }
    private var visits: [LifeVisit] { Self.visits(ctx, chapter: chapterID) }
    private var places: [HistoricalPlace] {
        let ids = Set(visits.map(\.placeID))
        return ctx.guide?.places.filter { ids.contains($0.id) } ?? []
    }
    private var selectedVisit: LifeVisit? { visits.first { $0.id == selectedVisitID } }
    private var selectedPlace: HistoricalPlace? { places.first { $0.id == selectedVisit?.placeID } }
    private var coordinates: [CLLocationCoordinate2D] { Self.coordinates(ctx, chapter: chapterID) }
    /// 聚焦时本卷之外的驻点: 只画成小灰点, 不进选择, 不进无障碍树。
    private var mutedPlaces: [HistoricalPlace] {
        guard isFocused else { return [] }
        let focused = Set(places.map(\.id))
        return ctx.guide?.places.filter { !focused.contains($0.id) } ?? []
    }
    /// 有驻留记录的篇章才进切换条 (没有驻点的卷聚焦后只会是一张空图)。
    private var chapterEpochs: [Epoch] {
        let withVisits = Set(ctx.guide?.visits.map(\.chapterID) ?? [])
        return ctx.lifeEpochs.filter { withVisits.contains($0.sequence) }
    }
    private var chapterLabel: String { chapterEpochs.first { $0.sequence == chapterID }?.label ?? Self.allLabel }
    private var isApproximate: Bool { ctx.composition.placement(.itinerary)?.fidelity == .approximate }
    private func period(_ visit: LifeVisit) -> String { isApproximate ? "约 \(visit.period)" : visit.period }
    var body: some View {
        Group {
            if !ctx.hasItineraryData {
                LifeUI.Empty(title: "行程正在整理", message: "当前没有足够资料绘制可核验的路线。", systemImage: "map")
            } else {
                GeometryReader { geometry in
                    if typeSize.isAccessibilitySize || geometry.size.height < 430 {
                        ScrollView {
                            VStack(spacing: 0) { controls; map.frame(height: Self.scrollingMapHeight); detail }
                        }
                    } else {
                        VStack(spacing: 0) { controls; map; detail }
                    }
                }
            }
        }
        .background(theme.paper())
        .onAppear { if selectedVisitID == nil { select(visits.first, focus: false) } }
        .onChange(of: selectedPlaceID) { _, newValue in
            guard let newValue, newValue != selectedVisit?.placeID else { return }
            select(visits.first { $0.placeID == newValue }, focus: false)
        }
        .onChange(of: chapterID) { _, _ in
            select(visits.first, focus: false)
            fitCamera(animated: true)
        }
        .sheet(isPresented: $showingDirectory) {
            NavigationStack {
                List {
                    Section {
                        ForEach(visits) { visit in
                            if let place = places.first(where: { $0.id == visit.placeID }) {
                                Button {
                                    select(visit, focus: true)
                                    showingDirectory = false
                                } label: {
                                    VStack(alignment: .leading, spacing: theme.space.sm) {
                                        HStack {
                                            Text(place.name).font(theme.type.headline)
                                            Spacer()
                                            Text(period(visit)).font(theme.type.caption.monospacedDigit())
                                                .foregroundStyle(theme.color.textSecondary)
                                        }
                                        Text("今 \(place.modernName)").font(theme.type.caption)
                                            .foregroundStyle(theme.color.textSecondary)
                                        Text(visit.summary).font(theme.type.subhead).foregroundStyle(theme.color.textPrimary)
                                    }.padding(.vertical, theme.space.sm).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    } footer: {
                        Text("同一地点多次到访，按行程先后分别列出。这里只整理主要驻留与转折，完整事目请查阅编年。")
                            .font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
                    }.listRowBackground(theme.surface)
                    if let guide = ctx.guide {
                        Section {
                            NavigationLink { GuideSourcesView(ctx: ctx, guide: guide) } label: {
                                Text("地名与地图资料").font(theme.type.body)
                            }
                        }.listRowBackground(theme.surface)
                    }
                }
                .scrollContentBackground(.hidden).background(theme.paper())
                .foregroundStyle(theme.color.textPrimary)
                .zxNavigationTitle("行程目录", role: .secondary)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingDirectory = false } } }
            }
        }
    }
    /// 篇章切换条: 「全部」+ 各卷标题。选中 = 聚焦的卷; 切换时地图随之飞向本卷驻点。
    private var chapterRail: some View {
        FilterRail(options: [Self.allLabel] + chapterEpochs.map(\.label), selection: railSelection,
                   style: .init(chip: theme.color.fill, label: theme.color.textPrimary,
                                secondaryLabel: theme.color.textSecondary,
                                indicator: theme.color.textPrimary, onIndicator: theme.paper(),
                                chipHeight: 36))
            .accessibilityLabel("\(ctx.narrativeLabel)篇章，\(chapterLabel)")
    }
    private var railSelection: Binding<Set<String>> {
        Binding {
            [chapterLabel]
        } set: { chosen in
            guard let title = chosen.first else { return }
            chapterID = chapterEpochs.first { $0.label == title }?.sequence ?? Self.allChapters
        }
    }
    private var controls: some View {
        VStack(spacing: 0) {
            chapterRail
            HStack(spacing: theme.space.lg) {
                Text(isFocused ? "\(chapterLabel) · \(visits.count) 站" : "全部 · \(visits.count) 站")
                    .font(theme.type.caption.monospacedDigit()).foregroundStyle(theme.color.textSecondary)
                    .lineLimit(1).accessibilityLabel("当前显示\(chapterLabel)，\(visits.count) 站")
                Spacer(minLength: 0)
                Button("全览", systemImage: "arrow.up.left.and.arrow.down.right") { fitCamera(animated: true) }
                    .labelStyle(.iconOnly).accessibilityLabel("显示当前篇章的全部行程")
                Button("行程目录", systemImage: "list.bullet") { showingDirectory = true }.labelStyle(.iconOnly)
            }.font(theme.type.subhead).buttonStyle(.borderless).tint(theme.accent)
                .frame(minHeight: LifeUI.minTapTarget).padding(.horizontal, theme.space.margin)
        }
    }
    private var map: some View {
        Map(position: $camera, selection: $selectedPlaceID) {
            if coordinates.count > 1 {
                // 路线走次色 (契约里给图表第二组的色), 驻点走 accent: 纸墨朱印里 accent 就是朱印,
                // 路线若也用它, 虚线与驻点就糊成一种红。线宽与虚线节奏是图形尺寸, 不是版面间距。
                MapPolyline(coordinates: coordinates)
                    .stroke(theme.color.secondary.opacity(0.75),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 6]))
            }
            // 本卷之外的驻点: 无 tag 就不可选; 内容只是一枚小圆, 不进无障碍树。
            ForEach(mutedPlaces) { place in
                Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                    Circle().fill(theme.muted.opacity(0.6)).frame(width: 8, height: 8)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }.annotationTitles(.hidden)
            }
            ForEach(places) { place in
                Marker(place.name, coordinate: place.coordinate).tint(theme.seal).tag(place.id)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls { MapCompass(); MapScaleView() }
        .accessibilityLabel("\(ctx.narrativeLabel)地图，\(isFocused ? "聚焦\(chapterLabel)，" : "")标记使用古地名。也可以使用行程目录逐站查看。")
    }
    @ViewBuilder private var detail: some View {
        if let visit = selectedVisit, let place = selectedPlace {
            VStack(alignment: .leading, spacing: theme.space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(place.name).font(theme.type.title2).foregroundStyle(theme.color.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(period(visit)).font(theme.type.subhead.monospacedDigit())
                        .foregroundStyle(theme.color.textSecondary)
                    Spacer(minLength: 0)
                }
                Text("今 \(place.modernName)").font(theme.type.caption).foregroundStyle(theme.color.textSecondary)
                Text(visit.summary).font(theme.type.subhead).foregroundStyle(theme.color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("上一站", systemImage: "chevron.left") { step(-1) }.labelStyle(.iconOnly)
                        .frame(minWidth: LifeUI.minTapTarget, minHeight: LifeUI.minTapTarget)
                        .disabled(visit.id == visits.first?.id)
                    Text("\((visits.firstIndex { $0.id == visit.id } ?? 0) + 1) / \(visits.count)")
                        .font(theme.type.caption.monospacedDigit()).foregroundStyle(theme.color.textSecondary).accessibilityLabel("当前第 \((visits.firstIndex { $0.id == visit.id } ?? 0) + 1) 站，共 \(visits.count) 站")
                    Button("下一站", systemImage: "chevron.right") { step(1) }.labelStyle(.iconOnly)
                        .frame(minWidth: LifeUI.minTapTarget, minHeight: LifeUI.minTapTarget)
                        .disabled(visit.id == visits.last?.id)
                    Spacer()
                    if ctx.hasChronicleData {
                        NavigationLink { ChronicleEventsView(ctx: ctx, year: visit.yearStart) } label: {
                            Text("读这一年").font(theme.type.subhead.weight(.semibold))
                        }.frame(minHeight: LifeUI.minTapTarget)
                    }
                }.buttonStyle(.borderless).tint(theme.accent)
                Text(isApproximate ? "古地名与年代均按资料标为约略位置" : "古地名标记 · 连线为主要行程示意")
                    .font(theme.type.caption).foregroundStyle(theme.color.textTertiary)
            }.padding(.horizontal, theme.space.margin).padding(.top, theme.space.lg).padding(.bottom, theme.space.sm)
                .poetReadableWidth(LifeUI.listColumnWidth)
        }
    }
    /// 大字号 / 矮窗口时地图放进滚动页, 给它一个固定高度 (地图是「物」, 不是版面间距)。
    private static let scrollingMapHeight: CGFloat = 300

    private func step(_ delta: Int) {
        guard let current = visits.firstIndex(where: { $0.id == selectedVisitID }), visits.indices.contains(current + delta) else { return }
        select(visits[current + delta], focus: true)
    }
    private func fitCamera(animated: Bool) {
        let target = Self.fit(coordinates)
        guard animated else { camera = target; return }
        withAnimation(theme.motion.adapted(theme.motion.hero, reduceMotion: reduceMotion)) { camera = target }
    }
    private static func visits(_ ctx: CompositionContext, chapter: Int) -> [LifeVisit] {
        ctx.guide?.visits.filter { chapter == allChapters || $0.chapterID == chapter } ?? []
    }
    private static func coordinates(_ ctx: CompositionContext, chapter: Int) -> [CLLocationCoordinate2D] {
        guard let guide = ctx.guide else { return [] }
        let index = Dictionary(guide.places.map { ($0.id, $0.coordinate) }, uniquingKeysWith: { first, _ in first })
        return visits(ctx, chapter: chapter).compactMap { index[$0.placeID] }
    }
    /// 把一组驻点装进视野: 外包框放大一圈留白; 单点 / 近点用与逐站聚焦相同的 3.5° 跨度, 不至于缩到街区。
    private static func fit(_ points: [CLLocationCoordinate2D]) -> MapCameraPosition {
        guard let first = points.first else { return .automatic }
        var (minLat, maxLat, minLon, maxLon) = (first.latitude, first.latitude, first.longitude, first.longitude)
        for point in points {
            minLat = min(minLat, point.latitude); maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude); maxLon = max(maxLon, point.longitude)
        }
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 3.5),
                                    longitudeDelta: max((maxLon - minLon) * 1.5, 3.5))
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        return .region(MKCoordinateRegion(center: center, span: span))
    }
    private func select(_ visit: LifeVisit?, focus: Bool) {
        selectedVisitID = visit?.id
        selectedPlaceID = visit?.placeID
        if focus, let point = places.first(where: { $0.id == visit?.placeID })?.coordinate {
            withAnimation(theme.motion.adapted(theme.motion.hero, reduceMotion: reduceMotion)) {
                camera = .region(MKCoordinateRegion(center: point, span: MKCoordinateSpan(latitudeDelta: 3.5, longitudeDelta: 3.5)))
            }
        }
    }
}
private extension HistoricalPlace {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
