import ZixiaoPoetCore
#if DEBUG
import SwiftUI
import Supabase
import ZixiaoCore
import ZixiaoDesign

/// Local-only fixtures: the workspace never starts the root's network bootstrap.
/// 占位诗人与占位产品 —— 内核里不出现任何真实诗人; 导读只随产品 App 包发, 预览里没有。
///
/// 编成的 `identity.palette` 是必填的声明字段, 但上屏颜色一律来自 `.zxTheme(...)` (内核从不读它),
/// 所以预览里填的是占位字样而不是色值 —— 视图代码与预览都不出现十六进制。
@MainActor
private func workspacePreview() -> CompositionContext {
    let json = """
    {
      "schemaVersion": 1,
      "poet": {"slug":"preview-poet","name":"某诗人","dynasty":"tang","birth":700,"death":760},
      "app": {"bundleId":"com.example.preview","displayName":"预览志"},
      "capabilities": {
        "itinerary": {"prominence":"tab","label":"远游","order":0},
        "corpus": {"prominence":"tab","label":"诗集","order":1,
          "genres":[{"id":"shi","label":"诗","count":3,"status":"ready"}]}
      },
      "identity": {
        "era":"唐","rationale":"本地预览",
        "palette":{"paper":"theme","ink":"theme","accent":"theme","seal":"theme","rule":"theme","night":"theme"},
        "type":{"display":"Source Han Serif","body":"Source Han Serif","ui":"system"},
        "slots":{}
      }
    }
    """
    let composition = try! JSONDecoder().decode(PoetComposition.self, from: Data(json.utf8))
    let store = PoetStore(client: SupabaseClient(supabaseURL: URL(string: "http://127.0.0.1:1")!,
                                                supabaseKey: "preview-only"),
                          poetName: "某诗人")
    let outbox = ZXOutbox(fileURL: URL.temporaryDirectory.appending(path: "preview-outbox.json"),
                          transport: ZXSupabaseOutboxTransport())
    return CompositionContext(composition: composition, store: store, outbox: outbox)
}

/// 预览的身份: 与 App 一样走随包的纸墨朱印, 按外观解析。
private let previewIdentity = (try? ZXIdentity.bundled(.paperInkSeal)) ?? .fallback

#Preview("远游 · 宽窗口", traits: .fixedLayout(width: 1100, height: 800)) {
    NarrativeWorkspaceView(ctx: workspacePreview(), capability: .itinerary)
        .environment(\.horizontalSizeClass, .regular)
        .zxTheme(previewIdentity)
}

#Preview("诗集 · 紧凑窗口", traits: .fixedLayout(width: 393, height: 852)) {
    CorpusView(ctx: workspacePreview()).environment(\.horizontalSizeClass, .compact)
        .zxTheme(previewIdentity)
}

#Preview("导读 · 内容未就绪") {
    NarrativeWorkspaceView(ctx: workspacePreview(), capability: .itinerary)
        .zxTheme(previewIdentity)
}
#endif
