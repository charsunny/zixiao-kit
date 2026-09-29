//  PreviewSupport.swift — 预览用的页面外壳 (只在 DEBUG 编译)
//
//  每个组件的 #Preview 都要同时看两套身份、两种外观: 单色墨系在朱印身份下是否还站得住,
//  深色下纸墨互换后层级是否守恒 —— 这比只看一张浅色图更能暴露「写死了颜色」的地方。

#if DEBUG
import SwiftUI

struct PreviewPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(ZXBundledIdentity.allCases, id: \.self) { which in
                    ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                        if let identity = try? ZXIdentity.bundled(which) {
                            let theme = ZXTheme(identity, colorScheme: scheme)
                            VStack(alignment: .leading, spacing: 16) {
                                Text("\(identity.name) · \(scheme == .dark ? "深" : "浅")")
                                    .font(ZXFont.system(11, relativeTo: .caption2))
                                    .foregroundStyle(theme.muted)
                                content
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.paper())
                            .zxTheme(theme)
                            .environment(\.colorScheme, scheme)
                        }
                    }
                }
            }
        }
    }
}
#endif
