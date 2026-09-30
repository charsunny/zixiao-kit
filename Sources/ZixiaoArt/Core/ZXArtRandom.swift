//  ZXArtRandom.swift — 原作的随机源: Blum-Blum-Shub 式 PRNG + p5.js Perlin 噪声
//
//  Ported from shan-shui-inf (index.html <script id="PRNG">, <script id="PerlinNoise">) and
//  nonflowers (main.js) — both carry the identical code. MIT License, (c) 2018 Lingdong Huang.
//  Full license text: ZXArtLicenses.swift / LICENSES/.
//
//  逐位对齐的要点 (改动前请跑 ZXArtParityTests):
//  - `hash`: base64(JSON.stringify(seed)), 按 `z += code * 128^i` 用 Double 累加 —— 会丢精度,
//    但 IEEE 双精度下与 V8 完全一致, 所以照抄。
//  - `next`: `s = (s * s) % m`, s*s 超过 2^53, 同样是有意照抄的双精度乘法 + fmod。
//  - Perlin 表在「第一次取噪声」时用 PRNG 填 4096 个值 —— 这会消耗随机序列, 调用顺序必须同原作。
//  - `<<` / `&` 是 JS 的 int32 语义 (ToInt32 回绕)。

import Foundation
import ZixiaoDesign

extension ZXArt {
    /// 原作 PRNG: `s ← s² mod (p·q)`, p = 999979, q = 999983。
    struct PRNG: Sendable {
        static let p: Double = 999_979
        static let q: Double = 999_983
        static let m: Double = p * q

        private(set) var s: Double = 1234

        init(seed: Seed) {
            let h = PRNG.hash(seed.string)
            var y: Double = 0
            var z: Double = 0
            while y.truncatingRemainder(dividingBy: PRNG.p) == 0 || y.truncatingRemainder(dividingBy: PRNG.q) == 0
                    || y == 0 || y == 1 {
                y = (h + z).truncatingRemainder(dividingBy: PRNG.m)
                z += 1
            }
            s = y
            for _ in 0..<10 { _ = next() }
        }

        /// 播种后的整数状态 (原作 console.log 的 "int seed" 之后再走 10 步)。
        var state: Double { s }

        mutating func next() -> Double {
            s = (s * s).truncatingRemainder(dividingBy: PRNG.m)
            return s / PRNG.m
        }

        /// `window.btoa(JSON.stringify(x))` 逐字符 `code * 128^i` 求和。
        static func hash(_ seed: String) -> Double {
            let json = jsonQuoted(seed)
            // btoa 只接受 Latin-1; 超出时原作会抛异常, 这里退回 UTF-8 (文档化的偏差)。
            let bytes: [UInt8] = json.unicodeScalars.allSatisfy { $0.value < 256 }
                ? json.unicodeScalars.map { UInt8($0.value) }
                : Array(json.utf8)
            let b64 = Data(bytes).base64EncodedString()
            var z: Double = 0
            for (i, c) in b64.utf8.enumerated() {
                z += Double(c) * pow(128, Double(i))
            }
            return z
        }

        /// JSON.stringify 对字符串的转义 (够用的子集: 引号、反斜杠、控制符)。
        static func jsonQuoted(_ s: String) -> String {
            var out = "\""
            for u in s.unicodeScalars {
                switch u {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\r": out += "\\r"
                case "\t": out += "\\t"
                case "\u{08}": out += "\\b"
                case "\u{0C}": out += "\\f"
                default:
                    if u.value < 0x20 {
                        out += String(format: "\\u%04x", u.value)
                    } else {
                        out.unicodeScalars.append(u)
                    }
                }
            }
            return out + "\""
        }
    }

    /// p5.js 的 Perlin 噪声 (4 octave, falloff 0.5), 表由 PRNG 懒填充。
    struct PerlinTable: Sendable {
        static let size = 4095
        let values: [Double]
    }
}

// MARK: - Entropy (PRNG + Perlin, 引用语义, 单线程)

extension ZXArt {
    /// 一次生成期间共享的随机源。原作里 `Math.random` 与 `Noise` 是全局单例; 这里是每次
    /// `generate` 新建一个, 所以生成是纯函数、可并发。
    final class Entropy {
        private var prng: PRNG
        private var table: UnsafeMutablePointer<Double>?

        init(seed: Seed) {
            prng = PRNG(seed: seed)
        }

        deinit { table?.deallocate() }

        var state: Double { prng.state }

        /// `Math.random()`
        @inline(__always)
        func random() -> Double { prng.next() }

        /// 已填好的 Perlin 表 (滤镜需要带走)。未填时按原作规则先填。
        var perlinValues: [Double] {
            let t = ensureTable()
            return Array(UnsafeBufferPointer(start: t, count: PerlinTable.size + 1))
        }

        @inline(__always)
        private func ensureTable() -> UnsafeMutablePointer<Double> {
            if let t = table { return t }
            let t = UnsafeMutablePointer<Double>.allocate(capacity: PerlinTable.size + 1)
            for i in 0...PerlinTable.size { t[i] = prng.next() }
            table = t
            return t
        }

        /// `Noise.noise(x, y, z)`
        func noise(_ x: Double, _ y: Double = 0, _ z: Double = 0) -> Double {
            ZXArt.perlin(ensureTable(), x, y, z)
        }
    }

    /// p5.js noise() 本体。`y || 0`: NaN 的 y / z 按 0 处理 (原作语义)。
    @inline(__always)
    static func perlin(_ perlin: UnsafePointer<Double>, _ x0: Double, _ y0: Double, _ z0: Double) -> Double {
        var x = x0, y = y0.isNaN ? 0 : y0, z = z0.isNaN ? 0 : z0
        if x < 0 { x = -x }
        if y < 0 { y = -y }
        if z < 0 { z = -z }
        // 快路径: 坐标不大时 int32 不会回绕, 直接用 Int 算 (结果与 ToInt32 完全一致)。
        if x < 4_000_000, y < 4_000_000, z < 250_000 {
            var xi = Int(x), yi = Int(y), zi = Int(z)  // x ≥ 0, floor == trunc
            var xf = x - Double(xi), yf = y - Double(yi), zf = z - Double(zi)
            var r = 0.0
            var ampl = 0.5
            for _ in 0..<4 {
                var of = xi &+ (yi &<< 4) &+ (zi &<< 8)
                let rxf = 0.5 * (1.0 - cos(xf * Double.pi))
                let ryf = 0.5 * (1.0 - cos(yf * Double.pi))
                var n1 = perlin[of & 4095]
                n1 += rxf * (perlin[(of &+ 1) & 4095] - n1)
                var n2 = perlin[(of &+ 16) & 4095]
                n2 += rxf * (perlin[(of &+ 17) & 4095] - n2)
                n1 += ryf * (n2 - n1)
                of &+= 256
                n2 = perlin[of & 4095]
                n2 += rxf * (perlin[(of &+ 1) & 4095] - n2)
                var n3 = perlin[(of &+ 16) & 4095]
                n3 += rxf * (perlin[(of &+ 17) & 4095] - n3)
                n2 += ryf * (n3 - n2)
                n1 += 0.5 * (1.0 - cos(zf * Double.pi)) * (n2 - n1)
                r += n1 * ampl
                ampl *= 0.5
                xi <<= 1; xf *= 2
                yi <<= 1; yf *= 2
                zi <<= 1; zf *= 2
                if xf >= 1.0 { xi += 1; xf -= 1 }
                if yf >= 1.0 { yi += 1; yf -= 1 }
                if zf >= 1.0 { zi += 1; zf -= 1 }
            }
            return r
        }
        return perlinSlow(perlin, x, y, z)
    }

    /// 完全按 JS 语义 (Double + ToInt32) 的慢路径, 只在坐标极大 / 非有限时走。
    static func perlinSlow(_ perlin: UnsafePointer<Double>, _ x: Double, _ y: Double, _ z: Double) -> Double {
        var xi = x.rounded(.down), yi = y.rounded(.down), zi = z.rounded(.down)
        var xf = x - xi, yf = y - yi, zf = z - zi
        var r = 0.0
        var ampl = 0.5
        for _ in 0..<4 {
            let ofD = xi + Double(jsInt32(yi) &<< 4) + Double(jsInt32(zi) &<< 8)
            let of = Int(jsInt32(ofD))
            let rxf = 0.5 * (1.0 - cos(xf * Double.pi))
            let ryf = 0.5 * (1.0 - cos(yf * Double.pi))
            var n1 = perlin[of & 4095]
            n1 += rxf * (perlin[Int(jsInt32(ofD + 1)) & 4095] - n1)
            var n2 = perlin[Int(jsInt32(ofD + 16)) & 4095]
            n2 += rxf * (perlin[Int(jsInt32(ofD + 17)) & 4095] - n2)
            n1 += ryf * (n2 - n1)
            let of2 = ofD + 256
            n2 = perlin[Int(jsInt32(of2)) & 4095]
            n2 += rxf * (perlin[Int(jsInt32(of2 + 1)) & 4095] - n2)
            var n3 = perlin[Int(jsInt32(of2 + 16)) & 4095]
            n3 += rxf * (perlin[Int(jsInt32(of2 + 17)) & 4095] - n3)
            n2 += ryf * (n3 - n2)
            n1 += 0.5 * (1.0 - cos(zf * Double.pi)) * (n2 - n1)
            r += n1 * ampl
            ampl *= 0.5
            xi = Double(jsInt32(xi) &<< 1); xf *= 2
            yi = Double(jsInt32(yi) &<< 1); yf *= 2
            zi = Double(jsInt32(zi) &<< 1); zf *= 2
            if xf >= 1.0 { xi += 1; xf -= 1 }
            if yf >= 1.0 { yi += 1; yf -= 1 }
            if zf >= 1.0 { zi += 1; zf -= 1 }
        }
        return r
    }

    /// ECMAScript ToInt32。
    static func jsInt32(_ v: Double) -> Int32 {
        guard v.isFinite else { return 0 }
        let t = v.rounded(.towardZero)
        let m = t.truncatingRemainder(dividingBy: 4_294_967_296)
        let u = m < 0 ? m + 4_294_967_296 : m
        return Int32(truncatingIfNeeded: UInt32(u))
    }
}

// MARK: - 原作的随机工具 (Util)

extension ZXArt.Entropy {
    /// `randChoice(arr)` —— 注意: 调用前 JS 已按顺序求值了数组里每一项 (可能各自消耗随机数)。
    @inline(__always)
    func choice<T>(_ arr: [T]) -> T { arr[Int((Double(arr.count) * random()).rounded(.down))] }

    /// `normRand(m, M)`
    @inline(__always)
    func normRand(_ m: Double, _ M: Double) -> Double { ZXArt.mapval(random(), 0, 1, m, M) }

    /// `wtrand(func)` (原作递归, 这里循环, 取数顺序相同)。
    func wtrand(_ f: (Double) -> Double) -> Double {
        while true {
            let x = random()
            let y = random()
            if y < f(x) { return x }
        }
    }

    /// `randGaussian()`
    func randGaussian() -> Double {
        wtrand { x in pow(M_E, -24 * pow(x - 0.5, 2)) } * 2 - 1
    }
}

extension ZXArt {
    @inline(__always)
    static func mapval(_ value: Double, _ istart: Double, _ istop: Double, _ ostart: Double, _ ostop: Double) -> Double {
        ostart + (ostop - ostart) * (((value - istart) * 1.0) / (istop - istart))
    }

    /// `Number.prototype.toFixed(d)` 再 parseFloat —— 原作把透明度拼进 CSS 字符串时会这样截断,
    /// 截断后的值又被 parseFloat 读回来参与后续计算 (tree01/03 的叶色), 所以要照做。
    static func toFixed(_ x: Double, _ digits: Int) -> Double {
        guard x.isFinite else { return x }
        let p = pow(10, Double(digits))
        return (x * p).rounded(.toNearestOrAwayFromZero) / p
    }

    /// JS `x | 0`。
    @inline(__always)
    static func or0(_ x: Double) -> Int { Int(jsInt32(x)) }
}
