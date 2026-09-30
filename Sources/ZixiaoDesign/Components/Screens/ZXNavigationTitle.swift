//  ZXNavigationTitle.swift — 导航栏标题 (系统默认样式)
//
//  规范 (charsunny, 2026-09-29): 导航栏标题一律用 iOS 26 系统默认的标题样式 ——
//  Tab 根页 `inlineLarge`, 二级页 `inline`, 从不 `.large`; 字体、位置交给系统, 不再往
//  `ToolbarItemPlacement.largeTitle` / `.title` 槽位塞自定义 `Text` (那样 iOS 26 会把
//  大字居中画在导航栏中间, 与系统大标题的靠前位置不一致, 还会撞上右侧工具栏按钮)。
//
//  root / secondary 两档角色直接对应 `ZXTabShell.swift` 里已有的两档折叠模式:
//  root 用 `zxRootTitleDisplayMode()` (iOS 26 inlineLarge, 以下 inline), secondary 用
//  `zxSecondaryTitleDisplayMode()` (inline)。页面只调这一个修饰符, 不自己设标题模式。
import SwiftUI

/// 一处导航标题在导航层级里的角色。决定标题栏折叠模式。
public enum ZXNavigationTitleRole: Sendable, Hashable {
    /// Tab 根页: iOS 26 inlineLarge (以下 inline)。
    case root
    /// 二级页 / sheet: inline。
    case secondary
}

public extension View {
    /// 导航栏标题, 系统默认样式。
    ///
    /// - Parameters:
    ///   - title: 标题文字, 经 `.navigationTitle` 交给系统 (也是返回按钮文字与 VoiceOver 页面名)。
    ///   - subtitle: 副标题, iOS 26 起经 `.navigationSubtitle(_:)` 放出。**iOS 26 以下这里
    ///     什么都不放** —— 早期系统没有能把副标题钉在导航栏上的 API, 调用方需要副标题时
    ///     自己在内容顶部加一行 (玄览 `TodayScreen` 的 `TodaySubtitleFallback`)。
    ///   - role: 见 `ZXNavigationTitleRole`。
    @ViewBuilder
    func zxNavigationTitle(_ title: String, subtitle: String? = nil, role: ZXNavigationTitleRole) -> some View {
        switch role {
        case .root:
            self
                .navigationTitle(title)
                .zxRootTitleDisplayMode()
                .modifier(ZXNavigationSubtitleModifier(subtitle: subtitle))
        case .secondary:
            self
                .navigationTitle(title)
                .zxSecondaryTitleDisplayMode()
                .modifier(ZXNavigationSubtitleModifier(subtitle: subtitle))
        }
    }
}

/// 副标题, iOS 26 起 (`.navigationSubtitle` 本身要求 iOS 26)。
private struct ZXNavigationSubtitleModifier: ViewModifier {
    let subtitle: String?

    func body(content: Content) -> some View {
        if let subtitle, #available(iOS 26.0, *) {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}
