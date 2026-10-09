//  CompositionIdentity.swift — 编成里的 identity 块 (L3 身份层的声明)
//
//  这是编成 JSON 的数据形状, 不是上屏用的主题: 颜色与字一律来自 App 注入的 `ZXTheme`
//  (`.zxTheme(ZXIdentity...)`)。这里保留的是编成独有、ZXIdentity 不管的部分 ——
//  纪年风格 (`chronology`)、分期变体、印文与标记槽。

import Foundation
import ZixiaoCalendar

public struct Identity: Decodable, Sendable {
    public let era: String
    /// 写不出理由的配色就是皮肤, 不是身份。这个字段必填, 就是为了逼出理由。
    public let rationale: String
    public let palette: Palette
    public let type: TypeSpec
    public let slots: Slots
    public let chronology: Chronology?
    /// 按分期覆盖部分 token。同一套色降饱和压暗, 比换一套色更能表达「同一个人, 后来」。
    public let variants: [String: Variant]?

    public struct Palette: Decodable, Sendable {
        public let paper, ink, accent, seal, rule, night: String
    }
    public struct TypeSpec: Decodable, Sendable { public let display, body, ui: String }
    public struct Slots: Decodable, Sendable {
        public enum Rule: String, Decodable, Sendable {
            case verticalHairline = "vertical-hairline", frame, none
        }
        public enum Marker: String, Decodable, Sendable {
            case sealSquare = "seal-square", dot, brushDot = "brush-dot"
        }
        public let surface: String?
        public let rule: Rule?
        public let marker: Marker?
        public let sealText: String?
    }
    public struct Chronology: Decodable, Sendable {
        /// 纪年风格。年号表与换算在 ZixiaoCalendar (`EraNaming`), 编成只选风格。
        public let style: EraNaming.Style
        public let example: String?
    }
    public struct Variant: Decodable, Sendable {
        public let after: Int
        public let palette: [String: String]?
        public let saturation: Double?
        public let brightness: Double?
    }
}
