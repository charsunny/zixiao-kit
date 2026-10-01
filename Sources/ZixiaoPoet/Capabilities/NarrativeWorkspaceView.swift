import SwiftUI

/// The same chapter selection survives the system's transition between a sidebar
/// and a compact navigation stack. No device-name or orientation branching.
struct NarrativeWorkspaceView: View {
    let ctx: CompositionContext
    let capability: CapabilityID
    @State private var selection: Destination?
    @State private var visibility: NavigationSplitViewVisibility = .all

    private enum Destination: Hashable {
        case overview
        case chapter(Epoch)
        case lens(Lens.Kind)
        case network
        case sources
    }

    private var title: String { ctx.composition.placement(capability)?.label ?? ctx.narrativeLabel }
    private var lenses: [Lens] {
        (ctx.composition.placement(capability)?.lenses ?? []).filter(ctx.itineraryLensIsAvailable)
    }
    private var networkLabel: String? {
        ctx.hasNetworkData ? ctx.composition.lenses(hostedIn: capability).first { $0.id == .network }?.placement.label : nil
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            List(selection: $selection) {
                Section {
                    NavigationLink(value: Destination.overview) {
                        Label("\(ctx.composition.poet.name)小传", systemImage: "book.closed")
                    }
                }
                Section("\(ctx.lifeEpochs.count) 个导读篇章") {
                    ForEach(ctx.lifeEpochs) { epoch in
                        NavigationLink(value: Destination.chapter(epoch)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(epoch.label).font(.headline)
                                Text(epoch.period(in: ctx.composition.poet))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }.padding(.vertical, 8)
                        }
                    }
                }
                if !lenses.isEmpty || networkLabel != nil {
                    Section("深入查阅") {
                        ForEach(lenses) { lens in
                            NavigationLink(value: Destination.lens(lens.id)) {
                                Label(lens.label, systemImage: lens.id == .chronicle ? "list.bullet.rectangle" : "map")
                            }
                        }
                        if let networkLabel {
                            NavigationLink(value: Destination.network) {
                                Label(networkLabel, systemImage: "person.2")
                            }
                        }
                    }
                }
                if ctx.guide != nil {
                    Section {
                        NavigationLink(value: Destination.sources) {
                            Label("资料与纪年说明", systemImage: "text.book.closed")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(title)
            .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 390)
            .overlay {
                if ctx.lifeEpochs.isEmpty {
                    if ctx.store.loadError != nil { LoadFailureView(retry: { await ctx.store.bootstrap() }) }
                    else { ContentUnavailableView("导读正在整理", systemImage: "text.book.closed") }
                }
            }
        } detail: {
            NavigationStack {
                destination
            }.id(selection)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder private var destination: some View {
        switch selection {
        case .chapter(let epoch):
            EpochDetailView(ctx: ctx, epoch: epoch, selectChapter: { selection = .chapter($0) })
                .id(epoch.id)
        case .lens(.chronicle):
            ChronicleList(ctx: ctx, upTo: ctx.composition.poet.death)
                .navigationTitle("编年").toolbarTitleDisplayMode(.inlineLarge)
        case .lens:
            LifeMapView(ctx: ctx).navigationTitle("行迹").toolbarTitleDisplayMode(.inlineLarge)
        case .network:
            NetworkView(ctx: ctx).navigationTitle(networkLabel ?? "交游").toolbarTitleDisplayMode(.inlineLarge)
        case .sources:
            if let guide = ctx.guide { GuideSourcesView(ctx: ctx, guide: guide) }
        case .overview, nil:
            introduction
        }
    }

    private var introduction: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EditorialHeading(eyebrow: ctx.composition.poet.name, title: "沿\(title)读懂作品",
                                 introduction: ctx.guide?.biography, theme: ctx.theme)
                if let note = ctx.guide?.chronologyNote {
                    Text(note).font(.footnote).foregroundStyle(.secondary).lineSpacing(5)
                }
                if let first = ctx.lifeEpochs.first {
                    Button { selection = .chapter(first) } label: {
                        Label("从\(first.label)读起", systemImage: "book")
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.poetActionStyle(prominent: true)
                }
            }.padding(Metric.gutter).poetReadableWidth(640)
        }.background(ctx.theme.paper).navigationTitle(title).toolbarTitleDisplayMode(.inlineLarge)
    }
}
