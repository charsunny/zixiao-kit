import ZixiaoPoetCore
import SwiftUI

/// 时代背景的独立主入口。导读篇章和关联作品都来自随 App 打包的 guide，
/// 因此冷启动与断网时仍能完成「目录 → 章节 → 原文」的阅读路径。
struct ContextView: View {
    let ctx: CompositionContext

    var body: some View {
        NarrativeWorkspaceView(ctx: ctx, capability: .context)
    }
}
