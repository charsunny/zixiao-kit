//  ZXPalettePicker.swift — 色样选择；档位与上锁后的行为交给产品。
import SwiftUI

public struct ZXPalettePicker: View {
    @Binding private var selection: String
    private let entries: [ZXPaletteCatalog.Entry]
    private let includesSeasonal: Bool
    private let season: ZXSeasonTint
    private let isLocked: (String) -> Bool
    private let onLockedTap: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.zxTheme) private var theme

    public init(selection: Binding<String>, entries: [ZXPaletteCatalog.Entry] = ZXPaletteCatalog.entries,
                includesSeasonal: Bool = true, season: ZXSeasonTint, isLocked: @escaping (String) -> Bool = { _ in false },
                onLockedTap: @escaping (String) -> Void = { _ in }) {
        _selection = selection
        self.entries = entries
        self.includesSeasonal = includesSeasonal
        self.season = season
        self.isLocked = isLocked
        self.onLockedTap = onLockedTap
    }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 150))], spacing: 16) {
            ForEach(entries) { entry in
                card(id: entry.id, name: entry.name, imagery: entry.imagery,
                     swatch: scheme == .dark ? entry.dark : entry.light)
            }
            if includesSeasonal, let seasonal = ZXPaletteCatalog.entries.first(where: {
                $0.bundled == ZXPaletteCatalog.palette(for: season)
            }) {
                card(id: ZXPaletteCatalog.seasonalID, name: ZXPaletteCatalog.seasonalLabel(for: season),
                     imagery: "五行之季，应时换色", swatch: scheme == .dark ? seasonal.dark : seasonal.light)
            }
        }
    }

    private func card(id: String, name: String, imagery: String, swatch: ZXIdentity.Swatch) -> some View {
        Button {
            if isLocked(id) { onLockedTap(id) }
            else { selection = id }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("一日一诗").font(.body).foregroundStyle(Color(zxHex: swatch.ink))
                    Spacer(minLength: 4)
                    Circle().fill(Color(zxHex: swatch.accent)).frame(width: 12, height: 12)
                    Rectangle().fill(Color(zxHex: swatch.seal)).frame(width: 16, height: 16)
                }
                .padding(12)
                .background(Color(zxHex: swatch.paper), in: RoundedRectangle(cornerRadius: 8))
                HStack(alignment: .firstTextBaseline) {
                    Text(name).font(.headline)
                    Spacer(minLength: 4)
                    if isLocked(id) { Image(systemName: "lock.fill") }
                    if selection == id { Image(systemName: "checkmark.circle.fill") }
                }
                Text(imagery).font(.subheadline).foregroundStyle(theme.color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(theme.color.textPrimary)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(reduceTransparency ? theme.color.surface : theme.color.bg,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                selection == id ? theme.color.accent : theme.color.separator, lineWidth: selection == id ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)，\(imagery)")
        .accessibilityValue(isLocked(id) ? "需解锁，可预览" : "可使用")
        .accessibilityAddTraits(selection == id ? [.isSelected] : [])
        .accessibilityIdentifier("palette.\(id)")
    }
}

#Preview {
    ScrollView { ZXPalettePicker(selection: .constant("moon-white"), season: .autumn).padding() }
}
