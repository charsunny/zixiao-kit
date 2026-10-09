import ZixiaoPoetCore
//  ReadingCover.swift — 单篇作品的「书衣」
//
//  画法交给 kit 的 `BookCoverView` (代码生成的线装封面: 书衣、左上题签竖排书名、右侧四眼订线)。
//  这里只决定两件事: 尺寸 (3:4, 由调用方给宽或高), 与「哪一类」—— 体裁画成书脊两端的包角,
//  色取身份的角色 (印 / 次色 / 淡墨), 内核不写任何色值。

import SwiftUI
import ZixiaoDesign

struct ReadingCover: View {
    let title: String
    let author: String
    let genre: Genre
    /// 封面高度; 宽度按 3:4 推出。与 `width` 都不给时用书目页大封面 (随 Dynamic Type 放大)。
    var height: CGFloat? = nil
    /// 封面宽度; 给了就以它为准。
    var width: CGFloat? = nil
    @Environment(\.zxTheme) private var theme
    @ScaledMetric(relativeTo: .title3) private var defaultWidth = BookCoverView.Size.page.width

    private var coverWidth: CGFloat {
        width ?? height.map { $0 * 3 / 4 } ?? defaultWidth
    }

    /// 体裁 → 包角。诗用印色, 词用次色, 文赋用淡墨; 其余素面不画包角。
    private var cornerTint: Color? {
        switch genre.id {
        case "shi": theme.color.seal
        case "ci": theme.color.secondary
        case "wen", "fu": theme.color.muted
        default: nil
        }
    }

    var body: some View {
        BookCoverView(title: title, author: "\(genre.label) · \(author)",
                      size: .width(coverWidth), cornerTint: cornerTint)
    }
}
