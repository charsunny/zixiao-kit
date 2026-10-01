// Content stays on opaque paper. Liquid Glass belongs to navigation and controls.
// System bars own their backgrounds; custom floating controls share one glass container.
//
// 过渡 shim (M1): `Metric` / `PoetFont` / `Glaze` / `GlazePanel` / `SectionLabel` / `PlaceChip`
// 保留 PoetKit 的调用形状, 取值全部来自 ZixiaoDesign (ZXTheme 的 token、kit 组件)。
// M2 把视图改为直接用 `theme.space` / `theme.type` / kit 组件后删除。

import SwiftUI
import ZixiaoDesign

// MARK: - 尺度

@available(*, deprecated, message: "M2: use theme.space / theme.radius")
public enum Metric {
    /// 页面左右留白 = `theme.space.margin`。
    public static let gutter: CGFloat = ZXSpaceTokens.standard.margin
    /// 读本栏宽。ZX token 里没有栏宽 (页面级尺度由产品定), 沿用原值。
    public static let readingWidth: CGFloat = 760
    /// 卡片圆角 = `theme.radius.xl`。
    public static let radius: CGFloat = ZXRadiusTokens.standard.xl
    public static let cardPadding: CGFloat = ZXMetric.panelPadding
    /// 卡与卡之间 = `theme.space.xl`。
    public static let blockGap: CGFloat = ZXSpaceTokens.standard.xl
    /// 卡内条目之间 = `theme.space.lg`。
    public static let itemGap: CGFloat = ZXSpaceTokens.standard.lg
}

// MARK: - 字

/// 字阶全部取自当前 ZXTheme (`PoetThemeResolver.current`): 宋体由 ZixiaoDesign 随包注册
/// (`ZXFonts.registerAll()`), App 不再带字体。
@available(*, deprecated, message: "M2: use theme.type / theme.displayFont / bodyFont / uiFont")
@MainActor
public enum PoetFont {
    private static var theme: ZXTheme { PoetThemeResolver.current }

    /// 点名宋体 (随 kit 注册的思源宋体); 点不到退系统字体。缩放走 UIFontMetrics。
    static func serif(_ size: CGFloat, _ weight: UIFont.Weight = .regular,
                      _ style: UIFont.TextStyle = .body) -> UIFont {
        let bold = weight.rawValue >= UIFont.Weight.semibold.rawValue || UIAccessibility.isBoldTextEnabled
        let base = UIFont(name: bold ? ZXFonts.serifBoldName : ZXFonts.serifRegularName, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }

    public static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        theme.uiFont(size, weight: weight)
    }

    public static var display: Font { theme.type.display }
    public static var poemTitle: Font { theme.type.display(30, relativeTo: .largeTitle) }
    public static var cardTitle: Font { theme.type.title2 }
    public static var entryTitle: Font { theme.type.headline }
    public static var body: Font { theme.type.body }
    /// 诗文比散文大一级。
    public static var verse: Font { theme.bodyFont(19) }
    public static var callout: Font { theme.type.callout }
    public static var meta: Font { theme.type.footnote }
    public static var numeral: Font { theme.type.numeral(34, relativeTo: .largeTitle) }
    /// SF Symbol 的尺寸。图标不是文字, 不挂字阶。
    public static func icon(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    public static var label: Font { theme.uiFont(13, weight: .medium) }
}

// MARK: - 容器

@available(*, deprecated, message: "M2: use ZixiaoDesign.GlazePanel(glaze:)")
public enum Glaze {
    /// 卡面 (`ZXGlaze.surface`)。
    case paper
    /// 主角卡 (`ZXGlaze.wash`, 淡墨釉)。原先写死的汝窑天青是某一个产品的身份色, 不进内核。
    case celadon

    @MainActor func color(_ theme: Theme) -> Color {
        switch self {
        case .paper: return theme.surface
        case .celadon: return theme.wash
        }
    }

    var zx: ZXGlaze { self == .celadon ? .wash : .surface }
}

/// PoetKit 调用形状的面板, 实际画 `ZixiaoDesign.GlazePanel`。
@available(*, deprecated, message: "M2: use ZixiaoDesign.GlazePanel")
struct GlazePanel<Content: View>: View {
    let theme: Theme
    var padding: CGFloat = Metric.cardPadding
    var glaze: Glaze = .paper
    var crackled: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        ZixiaoDesign.GlazePanel(glaze: glaze.zx, crackled: crackled, padding: padding,
                                cornerRadius: Metric.radius) { content }
    }
}

/// PoetKit 调用形状的分栏标签, 实际画 `ZixiaoDesign.SectionLabel`。
@available(*, deprecated, message: "M2: use ZixiaoDesign.SectionLabel")
struct SectionLabel: View {
    let text: String
    let theme: Theme
    var trailing: String? = nil

    var body: some View {
        ZixiaoDesign.SectionLabel(text, trailing: trailing)
    }
}

/// 地名徽标。capsule 是 iOS 的原生语言。贬所之类的强调地走印色, 其余走强调色。
@available(*, deprecated, message: "M2: restyle with theme tokens")
public struct PlaceChip: View {
    let text: String
    let theme: Theme
    var emphasized: Bool = false
    private var tint: Color { emphasized ? theme.seal : theme.accent }
    public var body: some View {
        Text(text)
            .font(PoetFont.label)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - 导航栏

public extension View {
    /// iOS 26 的大标题下面可以直接挂一行副标题（Fitness 的「Friday, Sep 4」就是它）。
    /// 低版本没有这个 API，调用方自己在内容区补一行。
    @ViewBuilder func poetNavigationSubtitle(_ text: String) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { self.navigationSubtitle(text) } else { self }
        #else
        self
        #endif
    }

}

/// iOS 26 是否有 navigationSubtitle —— 决定日期挂在导航栏还是画进内容区。
@MainActor public var hasNavigationSubtitle: Bool {
    if #available(iOS 26.0, *) { return true } else { return false }

}

// MARK: - Adaptive navigation and controls

extension View {
    func poetReadableWidth(_ width: CGFloat = Metric.readingWidth) -> some View {
        frame(maxWidth: width)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder func poetActionStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

/// One optical sampling container for adjacent custom navigation surfaces.
struct PoetGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else { content }
    }
}

struct PoetGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let theme: Theme
    func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency {
            content.glassEffect(.regular, in: .rect(cornerRadius: Metric.radius))
        } else {
            content.background(theme.surface, in: RoundedRectangle(cornerRadius: Metric.radius))
        }
    }
}

struct LoadFailureView: View {
    var title = "暂时无法载入"
    var message = "请检查网络连接后重试。"
    var retry: () async -> Void
    @State private var retrying = false
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button(retrying ? "正在重试…" : "重试") {
                Task { retrying = true; await retry(); retrying = false }
            }
            .poetActionStyle()
            .disabled(retrying)
        }
    }
}

struct LoadingStateView: View {
    var label = "正在载入…"
    var body: some View {
        ProgressView(label)
            .frame(maxWidth: .infinity, minHeight: 140)
            .accessibilityLabel(label)
    }
}

#if DEBUG
#Preview("纸面与玻璃操作层") {
    let theme = Theme(PoetThemeResolver.current)
    ZStack {
        theme.paper.ignoresSafeArea()
        VStack(spacing: 24) {
            GlazePanel(theme: theme, glaze: .celadon) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "今日诗文", theme: theme)
                    Text("从一句诗，走进一生").font(PoetFont.cardTitle)
                    Text("诗文有纸的温润，操作有玻璃的轻盈。")
                        .font(PoetFont.body).foregroundStyle(theme.secondaryInk)
                }
            }
            PoetGlassGroup {
                HStack(spacing: 16) {
                    Button("选择年份", systemImage: "calendar") { }.poetActionStyle()
                    Button("开始阅读", systemImage: "book") { }.poetActionStyle(prominent: true)
                }
            }
        }.padding(Metric.gutter).poetReadableWidth()
    }.tint(theme.accent).foregroundStyle(theme.ink)
}
#Preview("加载失败") {
    LoadFailureView(title: "诗文暂未载入") { }
}
#endif
