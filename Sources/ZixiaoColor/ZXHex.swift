import Foundation


/// 一个十六进制色值。解码时就校验, 身份 JSON 里写错一位会立刻报错。
public struct ZXHex: Decodable, Sendable, Hashable, CustomStringConvertible {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    /// 接受 `#RRGGBB` 与 `#RRGGBBAA` (井号可省)。
    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8,
              s.allSatisfy(\.isHexDigit),
              let value = UInt64(s, radix: 16)
        else { return nil }
        let rgb = s.count == 8 ? value >> 8 : value
        red = Double((rgb >> 16) & 0xFF) / 255
        green = Double((rgb >> 8) & 0xFF) / 255
        blue = Double(rgb & 0xFF) / 255
        alpha = s.count == 8 ? Double(value & 0xFF) / 255 : 1
    }

    /// 直接给分量 (0…1)。派生色 (混色、叠透明度) 用; 越界的分量夹回 0…1。
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
        self.red = clamp(red)
        self.green = clamp(green)
        self.blue = clamp(blue)
        self.alpha = clamp(alpha)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let hex = ZXHex(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "不是合法色值: \(raw)")
        }
        self = hex
    }

    public var description: String {
        let c = [red, green, blue].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
        return alpha < 1 ? "#\(c)\(String(format: "%02X", Int((alpha * 255).rounded())))" : "#\(c)"
    }
}

// MARK: - 派生运算
//
// 为什么放在色值上而不是 Color 上: SwiftUI 的 Color 解析要等到上屏 (还要看环境),
// 拿不到确定的分量; token 派生与对比度检查都要在纯数值上做, 测试才能不起 UI 就验证。

public extension ZXHex {
    /// 同一支色换一个不透明度 (乘在原有 alpha 上)。
    func opacity(_ alpha: Double) -> ZXHex {
        ZXHex(red: red, green: green, blue: blue, alpha: self.alpha * alpha)
    }

    /// 把自己按自身 alpha 叠到不透明的 `base` 上, 得到一支不透明色。
    /// 「墨 72% 压在纸上」这类颜色要当底色用时 (上面还要压字), 必须先落成不透明的,
    /// 否则换一张底 (卡面、夜色) 就变了颜色, 对比度也跟着失守。
    func composited(over base: ZXHex) -> ZXHex {
        let a = alpha
        return ZXHex(red: red * a + base.red * (1 - a),
                     green: green * a + base.green * (1 - a),
                     blue: blue * a + base.blue * (1 - a),
                     alpha: 1)
    }

    /// 向 `other` 混 `amount` (0…1), 保留自己的 alpha。
    func mixed(with other: ZXHex, amount: Double) -> ZXHex {
        let t = min(max(amount, 0), 1)
        return ZXHex(red: red + (other.red - red) * t,
                     green: green + (other.green - green) * t,
                     blue: blue + (other.blue - blue) * t,
                     alpha: alpha)
    }

    /// WCAG 2 相对亮度 (忽略 alpha; 半透明色请先 `composited(over:)`)。
    var relativeLuminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }

    /// WCAG 2 对比度 (1…21)。正文要 ≥ 4.5, 18pt 以上与图标 ≥ 3。
    func contrast(with other: ZXHex) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
