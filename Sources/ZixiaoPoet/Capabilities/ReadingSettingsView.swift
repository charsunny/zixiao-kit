import SwiftUI

enum ReadingAppearance: String, CaseIterable, Identifiable {
    case automatic, warm, night
    var id: String { rawValue }
    var title: String {
        switch self { case .automatic: "原色"; case .warm: "柔纸"; case .night: "夜读" }
    }
    var paper: Color {
        switch self {
        case .automatic: Color.adaptive(light: "#FFFEFB", dark: "#171819")
        case .warm: Color.adaptive(light: "#F4EAD7", dark: "#29241D")
        case .night: Color(hex: "#171819")
        }
    }
    func colorScheme(following system: ColorScheme) -> ColorScheme { self == .night ? .dark : system }
}

struct ReadingSettingsView: View {
    let sample: String
    let usesProseLayout: Bool
    let theme: Theme
    @Binding var scale: Double
    @Binding var spacious: Bool
    @Binding var appearance: ReadingAppearance
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    private let sizes = [1.0, 1.15, 1.3]
    private var sizeIndex: Int { sizes.indices.min(by: { abs(sizes[$0] - scale) < abs(sizes[$1] - scale) }) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(sample)
                        .font(Font(PoetFont.serif((usesProseLayout ? 18 : 20) * scale)))
                        .lineSpacing(spacious ? 10 : 5).lineLimit(3)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                        .environment(\.colorScheme, appearance.colorScheme(following: colorScheme))
                        .accessibilityLabel("排版预览：\(sample)")
                }.listRowBackground(appearance.paper)
                Section {
                    HStack {
                        Button { scale = sizes[max(0, sizeIndex - 1)] } label: {
                            Image(systemName: "textformat.size.smaller").frame(width: 44, height: 44)
                        }.poetActionStyle().disabled(sizeIndex == 0).accessibilityLabel("缩小字号")
                        Spacer(minLength: 12)
                        Text(["标准", "较大", "最大"][sizeIndex]).font(.body.weight(.medium))
                            .accessibilityLabel("正文字号，\(["标准", "较大", "最大"][sizeIndex])")
                        Spacer(minLength: 12)
                        Button { scale = sizes[min(sizes.count - 1, sizeIndex + 1)] } label: {
                            Image(systemName: "textformat.size.larger").frame(width: 44, height: 44)
                        }.poetActionStyle().disabled(sizeIndex == sizes.count - 1).accessibilityLabel("放大字号")
                    }.padding(.vertical, 4)
                    Toggle("舒展行距", isOn: $spacious)
                } header: { Text("排版") } footer: { Text("在系统文字大小的基础上，调整阅读字号。") }
                Section("纸色") {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { appearanceChoices }
                        VStack(spacing: 12) { appearanceChoices }
                    }.padding(.vertical, 8)
                }
            }
            .navigationTitle("阅读设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .tint(theme.accent)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(620), .large])
        .presentationDragIndicator(.visible)
    }

    private var appearanceChoices: some View {
        ForEach(ReadingAppearance.allCases) { option in
            Button { appearance = option } label: {
                VStack(spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        Text("文").font(Font(PoetFont.serif(24)))
                            .frame(maxWidth: .infinity, minHeight: 64)
                        if appearance == option {
                            Image(systemName: "checkmark.circle.fill").font(.caption)
                                .padding(6)
                        }
                    }
                    .foregroundStyle(.primary).background(option.paper)
                    .environment(\.colorScheme, option.colorScheme(following: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(appearance == option ? theme.accent : .clear, lineWidth: 2) }
                    Text(option.title).font(.subheadline).fixedSize()
                }.frame(minWidth: 70, maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(option.title)纸色")
            .accessibilityAddTraits(appearance == option ? .isSelected : [])
        }
    }
}
