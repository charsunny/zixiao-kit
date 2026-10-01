import SwiftUI

/// Typographic covers for individual works, rather than reproductions of historical editions.
struct ReadingCover: View {
    let title: String
    let author: String
    let genre: Genre
    var height: CGFloat?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var paper: Color {
        switch genre.id {
        case "shi": Color.adaptive(light: "#355E59", dark: "#284943")
        case "ci": Color.adaptive(light: "#795149", dark: "#623F3A")
        case "wen": Color.adaptive(light: "#EAE0CB", dark: "#4B4435")
        default: Color.adaptive(light: "#D5E1E6", dark: "#35464F")
        }
    }
    private var ink: Color {
        switch genre.id {
        case "shi", "ci": Color(hex: "#FFF9ED")
        default: Color.adaptive(light: "#333A38", dark: "#F7F1E4")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(genre.label).font(.subheadline.weight(.medium)).foregroundStyle(ink.opacity(0.8))
            Text(title).font(Font(PoetFont.serif(23, .semibold, .title3)))
                .lineSpacing(4).lineLimit(typeSize.isAccessibilitySize ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(author).font(Font(PoetFont.serif(14, .regular, .footnote)))
                .foregroundStyle(ink.opacity(0.85))
        }
        .padding(.vertical, 22).padding(.leading, 23).padding(.trailing, 18)
        .frame(maxWidth: .infinity, alignment: .leading).frame(height: height)
        .foregroundStyle(ink)
        .background(paper)
        .overlay(alignment: .leading) {
            LinearGradient(colors: [.black.opacity(0.12), .white.opacity(0.05), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 9).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        // 书封是「一本书」不是容器，实物有影子才立得起来
        .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 4)  // lint:allow-shadow
    }
}
