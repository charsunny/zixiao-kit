import ZixiaoColor
//  ZXNavigationBarAppearance.swift — 让系统导航栏标题用身份的展示字族
//
//  SwiftUI 的 navigationTitle 没有字体 API, 大字标题永远是系统无衬线。契约要求
//  display / title 用身份的展示字族 (宋), 所以只能走 UIKit 的外观代理, 在 App 启动时
//  设一次。字号沿用系统默认 (大字 34 / 内联 17), 只换字族, Dynamic Type 由系统按
//  textStyle 缩放。
//
//  已弃用 (charsunny, 2026-09-29): 导航栏标题改为一律用 iOS 26 系统默认样式 (字体、位置都交给
//  系统, 见 `ZXNavigationTitle.swift`), App 启动时不再调用本类型。保留一个版本周期后删除。

#if canImport(UIKit)
import SwiftUI
import UIKit

@available(*, deprecated, message: "导航栏标题统一用系统默认样式, 不再改外观代理")
public enum ZXNavigationBarAppearance {
    /// 在 App 启动时调用一次 (需先 `ZXFonts.registerAll()`)。
    /// - Parameters:
    ///   - identity: 取其 `type.display` 字族; 解析不到自定义字体时不改动系统外观。
    ///   - inkHex: 标题颜色, 一般传身份浅色的 ink; 深色由系统按 UIColor 动态色处理时
    ///     这里传 nil 则沿用系统 label 色 (推荐, 免得浅深各设一套)。
    @MainActor
    public static func apply(identity: ZXIdentity, inkHex: ZXHex? = nil) {
        _ = ZXFonts.registerAll()
        let face = ZXFace(descriptor: identity.type.display)
        guard let large = uiFont(face, size: 34, weight: .bold),
              let inline = uiFont(face, size: 17, weight: .semibold) else { return }

        let color: UIColor = inkHex.map { UIColor(Color(zxHex: $0)) } ?? .label
        let largeAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large),
            .foregroundColor: color,
        ]
        let inlineAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline),
            .foregroundColor: color,
        ]

        let proxy = UINavigationBar.appearance()
        proxy.largeTitleTextAttributes = largeAttributes
        proxy.titleTextAttributes = inlineAttributes
        // iOS 13+ 的三套外观也要设, 否则滚动到边缘时会回到系统字体。
        for appearance in [proxy.standardAppearance, proxy.scrollEdgeAppearance, proxy.compactAppearance].compactMap({ $0 }) {
            appearance.largeTitleTextAttributes = largeAttributes
            appearance.titleTextAttributes = inlineAttributes
        }
    }

    private static func uiFont(_ face: ZXFace, size: CGFloat, weight: UIFont.Weight) -> UIFont? {
        switch face {
        case .serif, .serifBold:
            // 大字标题用粗宋, 内联用粗宋也可读; 只有一档 Bold 字重可用。
            return UIFont(name: ZXFonts.serifBoldName, size: size)
        case .kai:
            return UIFont(name: ZXFonts.kaiName, size: size)
        case .system:
            return nil
        }
    }
}
#endif
