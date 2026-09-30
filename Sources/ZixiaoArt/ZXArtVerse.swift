//  ZXArtVerse.swift — @2 的「诗句框」: 画为诗留出的一块空, 客户端把诗排进这块空里
//
//  @1 只留顶部一条 (quiet_top) 或横幅左侧一块, 竖排诗句落在画上会盖住山与花。@2 反过来: 先按
//  (verse_side, 版式, quiet_top, verse_columns, verse_chars) 定出诗句框, 再让构图绕开它 ——
//  竖排 (left / right) 是一侧的一道竖栏 (锁屏在时钟区之下), 横排 (top) 是时钟区之下的一条横带。
//
//  诗句框只取决于配方参数与画布长宽比, 不取决于随机数: 客户端不必生成整张画就能排字 (桌面组件的字与
//  背景是分开画的)。`ZXArt.Procedural.verseLayout(pixelSize:)` 与 `Drawing.verseRect` 是同一个数。
//  改这里的任何比例都会改变 @2 的出图 —— 与构图同一条版本规则 (另开 @3)。

import CoreGraphics
import Foundation

public extension ZXArt {
    /// 诗句落在画的哪一边。
    enum VerseSide: String, Sendable, Hashable, Codable, CaseIterable {
        /// 左侧竖栏, 竖排。
        case left
        /// 右侧竖栏, 竖排 (缺省: 题画诗多在右上)。
        case right
        /// 时钟区之下一条横带, 横排 (横幅小组件: 左侧一栏, 横排)。
        case top

        /// 竖排 (右起成列) 还是横排 (一句一行)。
        public var isVertical: Bool { self != .top }
    }

    /// @2 的诗句框。`rect` 是单位坐标 (0…1, 左上为原点, x 乘画布宽、y 乘画布高)。
    struct VerseLayout: Sendable, Hashable {
        public var side: VerseSide
        public var rect: CGRect
        /// 竖排 (列) 还是横排 (行)。
        public var isVertical: Bool { side.isVertical }

        public init(side: VerseSide, rect: CGRect) {
            self.side = side
            self.rect = rect
        }

        /// 放大到画布 (pt 或像素)。
        public func rect(in size: CGSize) -> CGRect {
            CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                   width: rect.width * size.width, height: rect.height * size.height)
        }
    }

    /// 诗句框 (单位坐标)。纯函数。
    ///
    /// 量度按客户端的排法估 (都是「× 字号」): 竖排一块宽 = 列数 + 列距 0.62 × (列数 − 1) + 署名与印 1.6,
    /// 高 = 1.18 × (字数 − 1) + 1.44; 横排一块高 = 1.82 × 行数 + 署名 1.43, 宽 = 1.14 × 字数。
    /// - Parameters:
    ///   - aspect: 画布 宽 / 高。
    ///   - quietTop: 竖幅顶部的时钟区 (画布高度的份额, 已夹到 0…0.5)。方幅 / 横幅不用。
    ///   - columns: 诗句几列 (竖) / 几行 (横), nil = 2, 夹到 1…4。
    ///   - chars: 最长一句几个字, nil = 7, 夹到 4…10。
    static func verseLayout(side: VerseSide, frame: Frame, aspect: Double, quietTop: Double,
                            columns: Int?, chars: Int?) -> VerseLayout {
        let n = Double(min(max(columns ?? 2, 1), 4))
        let c = Double(min(max(chars ?? 7, 4), 10))
        let a = max(aspect, 0.01)
        let colW = n + (n - 1) * 0.62 + 1.6
        let colH = (c - 1) * 1.18 + 1.44
        let rowH = n * 1.82 + 1.43
        let rowW = c * 1.14
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
        let r: CGRect
        switch (frame, side) {
        case (.portrait, .left), (.portrait, .right):
            // 字号 (画布宽的份额) ≤ 0.075, 整栏不宽于 0.44
            let pad = 0.02
            let fs = min(0.075, 0.40 / colW)
            let w = clamp(fs * colW + 2 * pad, 0.26, 0.44)
            let top = quietTop + 0.02
            let h = clamp((fs * colH + 2 * pad) * a, 0.12, 0.80 - top)
            r = CGRect(x: side == .right ? 0.95 - w : 0.05, y: top, width: w, height: h)
        case (.portrait, .top):
            let fs = min(0.075, 0.84 / rowW)
            let top = quietTop + 0.01
            let h = clamp((fs * rowH + 0.04) * a, 0.08, 0.30)
            r = CGRect(x: 0.06, y: top, width: 0.88, height: h)
        case (.square, .left), (.square, .right):
            // 栏高按最大字号 0.08 定 (不随列数缩): 小号组件只排两列, 字要按高放得下
            let pad = 0.03
            let fs = min(0.08, 0.40 / colW)
            let w = clamp(fs * colW + 2 * pad, 0.30, 0.46)
            let h = clamp((0.08 * colH + 2 * pad) * a, 0.30, 0.88)
            r = CGRect(x: side == .right ? 0.95 - w : 0.05, y: 0.06, width: w, height: h)
        case (.square, .top):
            let fs = min(0.075, 0.84 / rowW)
            let h = clamp((fs * rowH + 0.06) * a, 0.20, 0.46)
            r = CGRect(x: 0.06, y: 0.06, width: 0.88, height: h)
        case (.wide, .left), (.wide, .right):
            // 字号按高 (画布高的份额) 定, 栏宽换算回画布宽
            let fs = min(0.13, 0.84 / colH)
            let w = clamp((fs * colW + 0.12) / a, 0.30, 0.46)
            r = CGRect(x: side == .right ? 0.96 - w : 0.04, y: 0.06, width: w, height: 0.88)
        case (.wide, .top):
            // 横幅没有「上方」可言: 左侧一栏, 横排
            let fs = min(0.13, 0.84 / rowH)
            let w = clamp((fs * rowW + 0.12) / a, 0.34, 0.46)
            r = CGRect(x: 0.04, y: 0.06, width: w, height: 0.88)
        }
        return VerseLayout(side: side, rect: r)
    }
}
