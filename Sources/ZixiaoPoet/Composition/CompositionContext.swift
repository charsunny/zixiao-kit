//  CompositionContext.swift — 一个诗人应用运行时的全部依赖
//
//  编成 (导航结构) + 只读数据 (PoetStore) + 账号 (ZXAuth) + 离线队列 (ZXOutbox) + 用户数据
//  (PoetUserData) + 随包资源 (PoetResources)。由 `PoetAppBoot` 建好交给 `PoetAppRoot`。

import Foundation
import Observation
import ZixiaoCalendar
import ZixiaoCore
import ZixiaoDesign

@MainActor
@Observable
public final class CompositionContext {
    public let composition: PoetComposition
    public let store: PoetStore
    public let era: EraNaming
    public let supportsAppleSignIn: Bool
    /// 账号: 匿名优先, 之后绑定 Apple / 手机号。见 `CompositionContext+Account`。
    public let auth: ZXAuth
    /// 离线写队列 (与 `auth` 共用: 换号时它丢弃上一位的待传写入)。
    public let outbox: ZXOutbox
    /// 收藏 / 阅读进度 / 笔记。
    public let userData: PoetUserData
    /// 诗人专属资源 (导读、书画) 所在的包。
    public let resources: PoetResources
    /// 随包资源载入时的问题 (缺导读等)。不挡启动 —— 能力按有无数据自行收起 —— 但留着给诊断与测试看。
    public let resourceIssues: [PoetResourceError]
    let artworks: [Artwork]
    let guide: PoetGuide?
    @ObservationIgnored var phoneFlow: PhoneFlow = .link

    func chapterIntroduction(_ epoch: Epoch) -> String? {
        guide?.chapter(epoch)?.introduction ?? composition.editorial?.epochNotes?[String(epoch.sequence)] ?? epoch.note
    }

    var narrativeCapability: CapabilityID {
        let context = composition.capabilities[.context]?.prominence
        return context == .tab || context == .hero ? .context : .itinerary
    }

    var narrativeLabel: String {
        composition.placement(narrativeCapability)?.label ?? (narrativeCapability == .context ? "背景" : "生平")
    }

    var visibleDailyCards: [DailyCard] {
        composition.enabledDailyCards.filter { card in
            switch card {
            case .workOfDay: return !literaryGenres.isEmpty
            case .onThisDay: return true
            case .epochNote: return guide?.chapters.isEmpty == false
            case .resume: return true
            case .anecdote: return false // 尚无经审核的共享 anecdote 数据源。
            }
        }
    }

    var hasChronicleData: Bool {
        guide?.archiveCounts.isEmpty == false || composition.declaresChronicleData
    }

    var hasItineraryData: Bool {
        guard composition.placement(.itinerary) != nil else { return false }
        // 当前地图只会渲染经过编成审核、随 guide 打包的驻留点。
        // 远端骨架不具备同等精度说明，不能拿来补一张看似精确的地图。
        return guide?.visits.isEmpty == false
    }

    var visibleAssociates: [Associate] {
        let minimum = composition.placement(.network)?.minWeight ?? 0
        return store.associates.filter { $0.weight >= minimum }
    }

    var hasNetworkData: Bool {
        composition.placement(.network) != nil
            && (!visibleAssociates.isEmpty || composition.declaresNetworkData)
    }

    func itineraryLensIsAvailable(_ lens: Lens) -> Bool {
        switch lens.id {
        case .map: return hasItineraryData
        case .chronicle: return hasChronicleData
        case .estate, .seasons: return false
        }
    }

    /// - Parameters:
    ///   - resources: 诗人资源所在的包; 默认主包。
    ///   - auth / outbox: 默认按 ZixiaoCore 的全局配置新建 —— 删号走 `zx_delete_account` (migration 065);
    ///     测试与预览注入自己的。
    ///   - userData: 默认按编成的 appSlug 隔离。
    public init(composition: PoetComposition,
                store: PoetStore,
                resources: PoetResources? = nil,
                auth: ZXAuth? = nil,
                outbox: ZXOutbox? = nil,
                userData: PoetUserData? = nil,
                supportsAppleSignIn: Bool = false) {
        let resources = resources ?? PoetResources(bundle: .main, composition: composition)
        let outbox = outbox ?? ZXOutbox(transport: ZXSupabaseOutboxTransport())
        self.composition = composition
        self.store = store
        self.supportsAppleSignIn = supportsAppleSignIn
        self.resources = resources
        self.outbox = outbox
        self.auth = auth ?? ZXAuth(backend: ZXSupabaseAuthBackend(deleteAccountRPC: Self.deleteAccountRPC),
                                   outbox: outbox)
        self.userData = userData ?? PoetUserData(app: composition.app.appSlug, outbox: outbox)
        var issues: [PoetResourceError] = []
        do { self.guide = try resources.guide() } catch {
            self.guide = nil
            issues.append(Self.resourceIssue(error, resources: resources))
        }
        do { self.artworks = try resources.artworks() } catch {
            self.artworks = []
            issues.append(Self.resourceIssue(error, resources: resources))
        }
        self.resourceIssues = issues
        ArtworkImages.resources = resources
        #if DEBUG
        for issue in issues { print("ZixiaoPoet: \(issue.localizedDescription)") }
        #endif
        store.lifespan = (composition.poet.birth, composition.poet.death)
        self.era = composition.eraName
    }

    /// 全库删号 RPC (migration 065): 删 poetkit_* 及系列其他应用表里 auth.uid() 自己的行, 再删 auth.users。
    public static let deleteAccountRPC = "zx_delete_account"

    private static func resourceIssue(_ error: any Error, resources: PoetResources) -> PoetResourceError {
        (error as? PoetResourceError)
            ?? .unreadable(product: resources.productName, resource: "?", detail: String(describing: error))
    }
}
