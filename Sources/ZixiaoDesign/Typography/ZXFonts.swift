//  ZXFonts.swift — 随包字体的注册与取用
//
//  **iOS 不带任何中文衬线字体** (PoetKit 实测过: 设备上只有苹方)。`.serif` design
//  落到 New York, 中文没字形就静默回落黑体 —— 所以宋体与楷体只能自带。
//  SPM 包的资源进不了 App 的 Info.plist `UIAppFonts`, 只能在运行时用 CoreText
//  注册进当前进程; 这就是 `registerAll()` 存在的原因。

import CoreText
import os
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public enum ZXFonts: Sendable {
    /// 思源宋体 SC (内部名是 CN 版) 常规体的 PostScript 名。
    public static let serifRegularName = "SourceHanSerifCN-Regular"
    /// 思源宋体粗体。只有常规与粗两档, 中间字重一律就近落到这两档。
    public static let serifBoldName = "SourceHanSerifCN-Bold"
    /// 秋鸿楷。**这是一份裁过字的子集** (七百余字, 只够印、题字与品牌字),
    /// 任意正文用它会大面积回落; 用之前拿 `covers(_:fontNamed:)` 问一声。
    public static let kaiName = "Slideqiuhong-Regular"

    /// 随包字体文件 (文件名, 扩展名, PostScript 名)。
    static let files: [(file: String, ext: String, postScriptName: String)] = [
        ("SourceHanSerifSC-Regular", "otf", serifRegularName),
        ("SourceHanSerifSC-Bold", "otf", serifBoldName),
        ("QiuHongKai", "ttf", kaiName),
    ]

    /// nil = 还没试过; 否则是上次注册的结果。结果缓存下来, 因为 `ZXFont` 每次取字
    /// 都会顺手调一次 `registerAll()`, 失败时不能每次都重新读三个几 MB 的文件。
    private static let state = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    /// 注册全部随包字体。幂等、线程安全, 可多次调用: App 启动时调一次最好,
    /// 但忘了也不要紧 —— `ZXFont` 取字前会自己调 (Preview 里没有 App 启动流程,
    /// 靠的就是这一点)。
    ///
    /// - Returns: 三个字体是否都已可用。
    @discardableResult
    public static func registerAll() -> Bool {
        state.withLock { done in
            if let done { return done }
            let ok = files.map { register($0.file, ext: $0.ext, postScriptName: $0.postScriptName) }
                .allSatisfy { $0 }
            done = ok
            return ok
        }
    }

    private static func register(_ file: String, ext: String, postScriptName: String) -> Bool {
        // 别处 (App 的 UIAppFonts、另一个包) 已经注册过同名字体: 不必再注册, 也不算失败。
        if isAvailable(postScriptName) { return true }
        let bundle = Bundle.module
        // `.process` 可能把 Fonts/ 子目录拍平, 两处都找。
        guard let url = bundle.url(forResource: file, withExtension: ext, subdirectory: "Fonts")
            ?? bundle.url(forResource: file, withExtension: ext)
        else { return false }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // 「已注册」「重名」都意味着字体其实在, 吞掉; 其余错误也不抛 ——
            // 字体缺席时 SwiftUI 会回落系统字, 宁可是黑体, 不能崩。结果以下面的实测为准。
            _ = error?.takeRetainedValue()
        }
        return isAvailable(postScriptName)
    }

    /// 按 PostScript 名找得到这个字体。`CTFontCreateWithName` 找不到时会给一个
    /// 替身而不是 nil, 所以要比对返回字体的真名。
    public static func isAvailable(_ postScriptName: String) -> Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        return (CTFontCopyPostScriptName(font) as String) == postScriptName
    }

    /// 这个字体是否覆盖 `text` 的每一个字 (空白不计)。
    ///
    /// 用处: 秋鸿楷是子集, 一方印里若有一个字不在子集里, CoreText 会只把那一个字
    /// 回落到苹方, 一方印里出现两种字体 —— 比整方印都用宋体难看得多。
    public static func covers(_ text: String, fontNamed postScriptName: String) -> Bool {
        registerAll()
        guard isAvailable(postScriptName) else { return false }
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        let scalars = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        let units = Array(String(String.UnicodeScalarView(scalars)).utf16)
        guard !units.isEmpty else { return true }
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        // 返回 false 表示至少有一个字没有字形。
        return CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
    }
}

// MARK: - 取字

/// 随包字体的 SwiftUI 入口。默认走 `relativeTo:`, 跟随 Dynamic Type 缩放。
///
/// `relativeTo` 传 nil 得到不缩放的定长字: 印面、书封这类尺寸固定的「物」里的字
/// 不该随系统字号变大 —— 印面是 44pt 的方块, 字放大了只会溢出印边。
public enum ZXFont: Sendable {
    /// 思源宋体。字重就近落到常规 / 粗两档 (semibold 及以上为粗)。
    ///
    /// - Parameter legibilityWeight: 传入环境里的 `\.legibilityWeight`, 系统「粗体文本」
    ///   打开时常规体升为粗体 —— 自定义字体不会自己响应这个开关。
    public static func serif(_ size: CGFloat,
                             weight: Font.Weight = .regular,
                             relativeTo textStyle: Font.TextStyle? = .body,
                             legibilityWeight: LegibilityWeight? = nil) -> Font {
        ZXFonts.registerAll()
        let bold = isBold(weight) || legibilityWeight == .bold
        return custom(bold ? ZXFonts.serifBoldName : ZXFonts.serifRegularName, size, textStyle)
    }

    /// 秋鸿楷。只有一档字重。子集字体, 见 `ZXFonts.kaiName` 的说明。
    public static func kai(_ size: CGFloat, relativeTo textStyle: Font.TextStyle? = .body) -> Font {
        ZXFonts.registerAll()
        return custom(ZXFonts.kaiName, size, textStyle)
    }

    private static func custom(_ name: String, _ size: CGFloat, _ textStyle: Font.TextStyle?) -> Font {
        guard let textStyle else { return .custom(name, fixedSize: size) }
        return .custom(name, size: size, relativeTo: textStyle)
    }

    /// 系统无衬线 (操作层)。SwiftUI 的 `.system(size:)` 不吃 Dynamic Type,
    /// 这里与 PHFonts 一样经 `UIFontMetrics` 按文字样式缩放。
    public static func system(_ size: CGFloat,
                              weight: Font.Weight = .regular,
                              relativeTo textStyle: Font.TextStyle? = .body) -> Font {
        guard let textStyle else { return .system(size: size, weight: weight) }
        #if canImport(UIKit)
        let base = UIFont.systemFont(ofSize: size, weight: uiWeight(weight))
        return Font(UIFontMetrics(forTextStyle: uiTextStyle(textStyle)).scaledFont(for: base))
        #else
        return .system(size: size, weight: weight)
        #endif
    }

    static func isBold(_ weight: Font.Weight) -> Bool {
        [.semibold, .bold, .heavy, .black].contains(weight)
    }

    #if canImport(UIKit)
    static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }

    static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
    #endif
}

// MARK: - 字面 (身份 JSON 的字族描述 → 随包字体)

/// 身份 JSON 里 `type.display/body/ui` 描述的字面。
///
/// 描述是给设计师写的 (「Source Han Serif CN Bold」「Noto Serif SC 200」「system」),
/// 这里只认三件事: 是不是楷、是不是宋、要不要粗。Noto Serif CJK 与思源宋体同一套字形,
/// 所以 PoetKit 身份里写的 Noto Serif 也落到随包思源宋体。
public enum ZXFace: Sendable, Hashable {
    case serif
    case serifBold
    case kai
    case system

    public init(descriptor: String) {
        let d = descriptor.lowercased()
        if d.contains("kai") || d.contains("楷") || d.contains("qiuhong") {
            self = .kai
        } else if d.contains("serif") || d.contains("宋") || d.contains("song") {
            // 「Bold / Heavy / Black」或数字字重 ≥ 600 算粗
            let numeric = d.split(separator: " ").compactMap { Int($0) }.last
            let bold = ["bold", "heavy", "black", "粗"].contains { d.contains($0) } || (numeric ?? 400) >= 600
            self = bold ? .serifBold : .serif
        } else {
            self = .system
        }
    }

    /// 取这个字面的 SwiftUI 字体。`weight` 只在宋 / 系统上有意义 (宋体粗面总是粗)。
    public func font(_ size: CGFloat,
                     weight: Font.Weight = .regular,
                     relativeTo textStyle: Font.TextStyle? = .body,
                     legibilityWeight: LegibilityWeight? = nil) -> Font {
        switch self {
        case .serif:
            return ZXFont.serif(size, weight: weight, relativeTo: textStyle, legibilityWeight: legibilityWeight)
        case .serifBold:
            return ZXFont.serif(size, weight: .bold, relativeTo: textStyle)
        case .kai:
            return ZXFont.kai(size, relativeTo: textStyle)
        case .system:
            let w: Font.Weight = legibilityWeight == .bold && !ZXFont.isBold(weight) ? .semibold : weight
            return ZXFont.system(size, weight: w, relativeTo: textStyle)
        }
    }
}
