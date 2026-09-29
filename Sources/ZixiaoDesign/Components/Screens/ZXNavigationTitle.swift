//  ZXNavigationTitle.swift — 导航栏标题用身份的展示字族 (宋)
//
//  `.navigationTitle` 没有字体 API, iOS 26 以下只能靠 `ZXNavigationBarAppearance` 这条
//  UIKit appearance proxy 兜底; iOS 26 起 Liquid Glass 导航栏拆出了专门的标题槏位
//  (`ToolbarItemPlacement.largeTitle` / `.title`), 放一个自定义 `Text` 进去才是"正确"
//  路线, 而不是继续 hack appearance proxy (那条路径在新版导航栏上还未必生效)。
//
//  这个结论来自 /tmp/navspike 的实测 (见 Sources/Scenarios.swift 与 f.png / g.png):
//  - `ToolbarItem(placement: .largeTitle)` 配 `.toolbarTitleDisplayMode(.inlineLarge)`:
//    大字标题能放自定义字体, 且不会像 `.principal` 那样跟系统标题重叠显示两份。
//  - `ToolbarItem(placement: .title)` 配 `.inline`: 同样能放自定义字体; iOS 26 以下
//    这个槏位自动降级为 `.principal`, 所以不必再对旧系统单独分支。
//
//  root / secondary 两档角色直接对应 `ZXTabShell.swift` 里已有的两档折叠模式:
//  root 用 `zxRootTitleDisplayMode()` (inlineLarge, 不折叠), secondary 用
//  `zxSecondaryTitleDisplayMode()` (inline)。折叠模式与字体从这一份收口, 页面自己
//  不必再关心"用哪个 placement"。
//
//  仍然调用 `.navigationTitle(title)`: 系统返回按钮上的文字、VoiceOver 读的页面名都
//  来自它, ToolbarItem 只是换掉"画出来给人看的那份"; 两者缺一, 无障碍或返回按钮的
//  文字就会跟屏幕上看到的不一致。

import SwiftUI

/// 一处导航标题在导航层级里的角色。决定标题栏折叠模式与字号阶。
public enum ZXNavigationTitleRole: Sendable, Hashable {
    /// Tab 根页: 大字标题 (34pt), 不随滚动折叠。
    case root
    /// 二级页 / sheet: 内联标题 (17pt, 与 headline 同一阶)。
    case secondary
}

public extension View {
    /// 导航栏标题, 用身份的展示字族 (宋) 而不是系统无衬线。
    ///
    /// - Parameters:
    ///   - title: 标题文字。同时经 `.navigationTitle` 交给系统 (返回按钮文字、
    ///     VoiceOver 页面名), 不要因为这里"看起来"换了字体就省掉它。
    ///   - subtitle: 副标题, 系统支持时 (iOS 26 起) 经 `.navigationSubtitle(_:)` 放出;
    ///     两个角色都能用 —— 比如「摘抄本」二级页的标题下面挂一行「N 条」。试过
    ///     `ToolbarItem(placement: .subtitle)` (理论上能吃自定义字体, 更贴合契约), 实机
    ///     上放了但完全不显示, 换回了这个字符串版 API (细节见 `ZXNavigationSubtitleModifier`)。
    ///     **iOS 26 以下这里什么都不放** —— 早期系统没有能把副标题钉在导航栏上的 API,
    ///     调用方需要副标题时自己在内容顶部加一行 (`TodayScreen` 就是这么做的, 见它的
    ///     `TodaySubtitleFallback`)。
    ///   - role: 见 `ZXNavigationTitleRole`。
    @ViewBuilder
    func zxNavigationTitle(_ title: String, subtitle: String? = nil, role: ZXNavigationTitleRole) -> some View {
        switch role {
        case .root:
            self
                .navigationTitle(title)
                .zxRootTitleDisplayMode()
                .modifier(ZXNavigationTitleModifier(title: title, subtitle: subtitle, role: .root))
        case .secondary:
            self
                .navigationTitle(title)
                .zxSecondaryTitleDisplayMode()
                .modifier(ZXNavigationTitleModifier(title: title, subtitle: subtitle, role: .secondary))
        }
    }
}

// MARK: - iOS 26: largeTitle / title 槏位 + 共用的 subtitle 槏位

private struct ZXNavigationTitleModifier: ViewModifier {
    let title: String
    let subtitle: String?
    let role: ZXNavigationTitleRole

    func body(content: Content) -> some View {
        // < iOS 26 没有 `.largeTitle` / `.title` / `.subtitle` 这几个槏位 (`.title`
        // 会自动降级为 `.principal`, 但那样会跟系统自己画的标题重叠成两份 —— navspike
        // 场景 C1/C2 就是反例), 干脆什么都不放, 交给 `ZXNavigationBarAppearance` 的
        // UIKit appearance proxy 兜底 (App 启动时调一次)。
        if #available(iOS 26.0, *) {
            content
                .toolbar {
                    switch role {
                    case .root:
                        ToolbarItem(placement: .largeTitle) { ZXNavTitleText(title, role: .root) }
                    case .secondary:
                        ToolbarItem(placement: .title) { ZXNavTitleText(title, role: .secondary) }
                    }
                }
                // 试过 `ToolbarItem(placement: .subtitle)` (能放自定义字体, 理论上更贴合
                // 契约): 实机 (iPhone 17 模拟器, iOS 26) 上放了但完全不显示, 大字标题与
                // 内联标题两种模式都一样。字符串版 `.navigationSubtitle(_:)` 才是那个真的
                // 会画出来的 API, 换掉它 —— 代价是副标题拿不到自定义字体, 落回系统无衬线,
                // 但契约只要求 display / title 用展示字族, 副标题不在其中。
                .modifier(ZXNavigationSubtitleModifier(subtitle: subtitle))
        } else {
            content
        }
    }
}

// MARK: - 读环境取字的内部 View
//
// 为什么要包一层 View 而不是在 ViewModifier.body 里直接拼 Text: ToolbarItem 的内容
// 闭包在 `.toolbar { }` 里求值, 这里需要的是「一个能读 `\.zxTheme` 的 View」,
// 单独包出来也方便复用在 root / secondary 两处, 字体全从主题解, 不硬编码字体名。

/// 大字标题 (root, 34pt) / 内联标题 (secondary, 与 headline 同阶 17pt), 都用身份的
/// 展示字族 —— 契约要求标题一律是宋体, 不区分根页与二级页。
private struct ZXNavTitleText: View {
    let title: String
    let role: ZXNavigationTitleRole

    @Environment(\.zxTheme) private var theme

    init(_ title: String, role: ZXNavigationTitleRole) {
        self.title = title
        self.role = role
    }

    var body: some View {
        Text(title)
            .font(font)
            .foregroundStyle(theme.color.textPrimary)
    }

    private var font: Font {
        switch role {
        case .root:
            // 与字号阶的 `.display` 同一档 (34pt, 跟随 `.largeTitle` 缩放)。
            theme.type.display
        case .secondary:
            // 展示字族, 但按 headline 的尺寸走 (17pt, 跟随 `.headline` 缩放) ——
            // 内联标题不该用 34pt 的大字号, 只是字族要跟大标题一致。
            theme.displayFont(ZXTypeRole.headline.size, relativeTo: ZXTypeRole.headline.textStyle)
        }
    }
}

/// 副标题, iOS 26 起。字符串版 `.navigationSubtitle(_:)` 没有字体 API, 拿不到展示字族——
/// 契约本身也只要求标题 (display / title) 用展示字族, 副标题落回系统无衬线不算违约。
private struct ZXNavigationSubtitleModifier: ViewModifier {
    let subtitle: String?

    func body(content: Content) -> some View {
        // 调用方 (`ZXNavigationTitleModifier`) 已经在 `#available(iOS 26.0, *)` 分支里
        // 才会用到这个 modifier, 这里再判一次是因为 `.navigationSubtitle` 本身要求
        // iOS 26 —— 两处判断职责不同, 不是重复。
        if let subtitle, #available(iOS 26.0, *) {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}
