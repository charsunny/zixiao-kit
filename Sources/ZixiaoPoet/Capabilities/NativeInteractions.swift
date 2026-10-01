import SwiftUI

extension View {
    func readingTransitionSource<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        modifier(ReadingTransitionSource(id: id, namespace: namespace))
    }
    func readingTransition<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        modifier(ReadingTransition(id: id, namespace: namespace))
    }
}

private struct ReadingTransitionSource<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *), !reduceMotion {
            content.matchedTransitionSource(id: id, in: namespace)
        } else { content }
    }
}

private struct ReadingTransition<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *), !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else { content }
    }
}

struct NativeSectionHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { heading; accessory.font(.subheadline).foregroundStyle(.secondary) }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    heading
                    Spacer(minLength: 4)
                    accessory.font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var heading: some View {
        Text(title).font(.title2.bold()).foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }
}

extension NativeSectionHeader where Accessory == EmptyView {
    init(_ title: String) { self.title = title; self.accessory = EmptyView() }
}
