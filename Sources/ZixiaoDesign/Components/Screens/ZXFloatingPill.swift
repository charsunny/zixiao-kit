//  ZXFloatingPill.swift — 浮动胶囊工具条
//
//  平时是一粒胶囊, 不挡正文; 点一下展开成一排动作, 做完自己收回。
//  给沉浸式页面 (阅读器) 用: 工具常驻会一直压在字上, 藏进菜单又多一层。
//
//  变形: iOS 26 起, 胶囊与展开后的工具条是同一片玻璃 (GlassEffectContainer + glassEffectID),
//  系统负责把一片玻璃「拉长」成另一片; iOS 17/18 用 matchedGeometryEffect 让底板在两种形态间
//  插值, 效果接近但没有折射。

import SwiftUI

/// 工具条上的一个动作。
public struct ZXPillAction: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    /// 选中态 (如「竖排」已开)。给 VoiceOver 读, 也画成实心底。
    public let isSelected: Bool
    public let role: ButtonRole?
    public let perform: @MainActor @Sendable () -> Void

    public init(id: String, title: String, systemImage: String, isSelected: Bool = false,
                role: ButtonRole? = nil, perform: @escaping @MainActor @Sendable () -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.role = role
        self.perform = perform
    }
}

public struct ZXFloatingPill: View {
    let title: String?
    let systemImage: String
    let actions: [ZXPillAction]
    let collapsesOnAction: Bool
    let onLongPress: (@MainActor () -> Void)?
    let external: Binding<Bool>?

    @State private var ownExpanded = false
    /// 长按刚触发过: 抬手时 Button 仍会收到一次点按, 这一次要吞掉, 否则长按后胶囊会顺带展开。
    @State private var swallowNextTap = false
    @Namespace private var morph
    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 按钮视觉尺寸。44pt 是最小点按区, 这里就用它 —— 胶囊本来就是给手指的。
    private let hit: CGFloat = 44

    /// - Parameters:
    ///   - title: 收起时胶囊上的字 (可选; 不给只显示图标)。也是无障碍标签。
    ///   - systemImage: 收起时的图标。
    ///   - actions: 展开后的一排动作。
    ///   - isExpanded: 外部持有展开状态 (比如翻页时要收起); nil 则自己持有。
    ///   - collapsesOnAction: 点完一个动作后自动收起。
    ///   - onLongPress: 长按收起态胶囊的回调 (可选)。VoiceOver 下以「自定义动作」提供。
    public init(_ title: String? = nil, systemImage: String, actions: [ZXPillAction],
                isExpanded: Binding<Bool>? = nil, collapsesOnAction: Bool = true,
                onLongPress: (@MainActor () -> Void)? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.actions = actions
        self.external = isExpanded
        self.collapsesOnAction = collapsesOnAction
        self.onLongPress = onLongPress
    }

    private var expanded: Bool { external?.wrappedValue ?? ownExpanded }

    private func setExpanded(_ value: Bool) {
        withAnimation(theme.motion.adapted(theme.motion.bouncy, reduceMotion: reduceMotion)) {
            if let external { external.wrappedValue = value } else { ownExpanded = value }
        }
    }

    public var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: theme.space.sm) { content }
            } else {
                content
            }
        }
        // 展开是一次「打开」, 给一下轻触觉; 收起不给, 免得每次点动作都震两下。
        .sensoryFeedback(.impact(weight: .light), trigger: expanded) { _, new in new }
    }

    @ViewBuilder
    private var content: some View {
        if expanded {
            toolbar
        } else {
            collapsed
        }
    }

    private var collapsed: some View {
        Button {
            if swallowNextTap { swallowNextTap = false; return }
            setExpanded(true)
        } label: {
            HStack(spacing: theme.space.sm) {
                Image(systemName: systemImage)
                    .font(theme.type.headline)
                if let title {
                    Text(title).font(theme.type.subhead)
                }
            }
            .foregroundStyle(theme.color.textPrimary)
            .padding(.horizontal, title == nil ? 0 : theme.space.lg)
            .frame(minWidth: hit, minHeight: hit)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .zxGlass(in: Capsule(), interactive: true)
        .morphID("pill", in: morph)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            guard let onLongPress else { return }
            swallowNextTap = true
            onLongPress()
        })
        .accessibilityLabel(title ?? "工具")
        .accessibilityHint("展开工具条")
        .accessibilityActions {
            if let onLongPress { Button("长按操作") { onLongPress() } }
        }
        .accessibilityIdentifier("zx.pill.toggle")
    }

    private var toolbar: some View {
        HStack(spacing: theme.space.xxs) {
            ForEach(actions) { action in
                Button(role: action.role) {
                    action.perform()
                    if collapsesOnAction { setExpanded(false) }
                } label: {
                    Image(systemName: action.systemImage)
                        .font(theme.type.headline)
                        .foregroundStyle(action.isSelected ? theme.color.accentOn
                                         : action.role == .destructive ? theme.color.danger
                                         : theme.color.textPrimary)
                        .frame(width: hit, height: hit)
                        .background {
                            if action.isSelected { Circle().fill(theme.color.accent) }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
                .accessibilityAddTraits(action.isSelected ? .isSelected : [])
                .accessibilityIdentifier("zx.pill.\(action.id)")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            ZXHairline(axis: .vertical)
                .frame(height: hit * 0.5)
                .padding(.horizontal, theme.space.xxs)
            Button {
                setExpanded(false)
            } label: {
                Image(systemName: "xmark")
                    .font(theme.type.subhead)
                    .foregroundStyle(theme.color.textSecondary)
                    .frame(width: hit, height: hit)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起")
            .accessibilityIdentifier("zx.pill.close")
        }
        .padding(.horizontal, theme.space.xs)
        .zxGlass(in: Capsule(), interactive: true)
        .morphID("pill", in: morph)
    }
}

private extension View {
    /// 收起 / 展开两种形态认同一个 id, 形变由系统完成。
    /// iOS 26: glassEffectID —— 玻璃之间的融合变形, 只在 GlassEffectContainer 里生效;
    /// 17/18: matchedGeometryEffect —— 插值底板的位置与尺寸。
    @ViewBuilder
    func morphID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            matchedGeometryEffect(id: id, in: namespace)
        }
    }
}

#if DEBUG
private struct ZXFloatingPillPreview: View {
    @State private var vertical = true
    @State private var log = "—"
    @Environment(\.zxTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            Text("上一步: \(log)").font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
            ZXFloatingPill("工具", systemImage: "textformat.size", actions: [
                ZXPillAction(id: "smaller", title: "缩小字号", systemImage: "textformat.size.smaller") { log = "缩小字号" },
                ZXPillAction(id: "larger", title: "放大字号", systemImage: "textformat.size.larger") { log = "放大字号" },
                ZXPillAction(id: "vertical", title: "竖排", systemImage: "text.alignright", isSelected: vertical) {
                    vertical.toggle(); log = vertical ? "竖排" : "横排"
                },
                ZXPillAction(id: "excerpt", title: "摘抄", systemImage: "bookmark") { log = "摘抄" },
            ], onLongPress: { log = "长按" })
        }
    }
}

#Preview("浮动胶囊") {
    PreviewPage {
        ZXFloatingPillPreview()
    }
}
#endif
