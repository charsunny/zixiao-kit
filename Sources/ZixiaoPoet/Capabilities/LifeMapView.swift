import SwiftUI
import MapKit
import ZixiaoDesign

struct LifeMapView: View {
    let ctx: CompositionContext
    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedPlaceID: String?
    @State private var selectedVisitID: Int?
    @State private var chapterID = -1
    @State private var showingDirectory = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zxTheme) private var theme
    private var visits: [LifeVisit] { ctx.guide?.visits.filter { chapterID == -1 || $0.chapterID == chapterID } ?? [] }
    private var places: [HistoricalPlace] {
        let ids = Set(visits.map(\.placeID))
        return ctx.guide?.places.filter { ids.contains($0.id) } ?? []
    }
    private var selectedVisit: LifeVisit? { visits.first { $0.id == selectedVisitID } }
    private var selectedPlace: HistoricalPlace? { places.first { $0.id == selectedVisit?.placeID } }
    private var coordinates: [CLLocationCoordinate2D] {
        visits.compactMap { visit in places.first { $0.id == visit.placeID }?.coordinate }
    }
    private var chapterLabel: String { ctx.lifeEpochs.first { $0.id == chapterID }?.label ?? "全部\(ctx.narrativeLabel)" }
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
        .onChange(of: chapterID) { _, _ in select(visits.first, focus: false); camera = .automatic }
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
    private var controls: some View {
        HStack(spacing: theme.space.lg) {
            Menu {
                Picker("\(ctx.narrativeLabel)篇章", selection: $chapterID) {
                    Text("全部\(ctx.narrativeLabel)").tag(-1)
                    ForEach(ctx.lifeEpochs) { epoch in Text(epoch.label).tag(epoch.id) }
                }
            } label: { Label(chapterLabel, systemImage: "line.3.horizontal.decrease").frame(minHeight: LifeUI.minTapTarget) }
                .accessibilityLabel("筛选地图，\(chapterLabel)")
            Spacer(minLength: 0)
            Button("全览", systemImage: "arrow.up.left.and.arrow.down.right") { camera = .automatic }
                .labelStyle(.iconOnly).accessibilityLabel("显示当前篇章的全部行程")
            Button("行程目录", systemImage: "list.bullet") { showingDirectory = true }.labelStyle(.iconOnly)
        }.font(theme.type.subhead).buttonStyle(.borderless).tint(theme.accent)
            .frame(minHeight: LifeUI.minTapTarget).padding(.horizontal, theme.space.margin)
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
            ForEach(places) { place in
                Marker(place.name, coordinate: place.coordinate)
                    .tint(place.id == selectedPlaceID ? theme.seal : theme.accent).tag(place.id)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls { MapCompass(); MapScaleView() }
        .accessibilityLabel("\(ctx.narrativeLabel)地图，标记使用古地名。也可以使用行程目录逐站查看。")
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
