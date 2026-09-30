//  ZXArtLicenses.swift — 第三方许可 (随代码分发, 也可在「致谢」页展示)
//
//  ZXArt 的两个生成器移植自 Lingdong Huang 的作品, 均为 MIT 许可:
//
//  shan-shui-inf — https://github.com/LingDong-/shan-shui-inf
//  (ported at commit 9f754d2b2e73495db7883d4d4055a7b0903b0454)
//
//  nonflowers — https://github.com/LingDong-/nonflowers
//  (ported at commit 03b653d220f16c6bed7ea9c7edc852f7e91846cb)
//
//  -------------------------------------------------------------------------------------------
//  MIT License
//
//  Copyright (c) 2018 Lingdong Huang
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//  -------------------------------------------------------------------------------------------
//  (两个仓库的 LICENSE 文件逐字相同; 仓库根 LICENSES/ 下各存一份。)

public extension ZXArt {
    /// 一条第三方致谢。
    struct Acknowledgement: Sendable, Hashable {
        public let name: String
        public let url: String
        public let license: String
        public let text: String
    }

    /// App「致谢 / 开源许可」页应列出的条目 (MIT 要求随分发附上版权与许可声明)。
    static let acknowledgements: [Acknowledgement] = [
        Acknowledgement(name: "shan-shui-inf", url: "https://github.com/LingDong-/shan-shui-inf",
                        license: "MIT", text: mitLicenseText),
        Acknowledgement(name: "nonflowers", url: "https://github.com/LingDong-/nonflowers",
                        license: "MIT", text: mitLicenseText),
    ]

    internal static let mitLicenseText = """
    MIT License

    Copyright (c) 2018 Lingdong Huang

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """
}
