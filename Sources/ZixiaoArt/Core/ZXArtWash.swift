//  ZXArtWash.swift — 湿墨取样: 无状态整数哈希、逻辑坐标 2D 值噪声与固定泊松盘

import Foundation

extension ZXArt {
    enum WashNoise {
        /// 扩展 Brush.hash 到二维; 负格点按 UInt32 回绕, 不持有 / 消耗 Entropy 或 Perlin 表。
        @inline(__always)
        static func value(_ x: Double, _ y: Double, seed: UInt32) -> Double {
            let ix = floor(x), iy = floor(y)
            let tx = x - ix, ty = y - iy
            let u = tx * tx * (3 - 2 * tx), v = ty * ty * (3 - 2 * ty)
            func index(_ n: Double) -> UInt32 {
                let r = n.truncatingRemainder(dividingBy: 4_294_967_296)
                return UInt32(r < 0 ? r + 4_294_967_296 : r)
            }
            func at(_ dx: Double, _ dy: Double) -> Double {
                Brush.random(Brush.hash(seed, index(iy + dy)), index(ix + dx))
            }
            let a = at(0, 0), b = at(1, 0), c = at(0, 1), d = at(1, 1)
            return (a + (b - a) * u) + ((c + (d - c) * u) - (a + (b - a) * u)) * v
        }

        @inline(__always)
        static func fbm(_ x: Double, _ y: Double, seed: UInt32) -> Double {
            (value(x * 0.035, y * 0.035, seed: seed) * 4
             + value(x * 0.079, y * 0.079, seed: seed ^ 0x68E31DA4) * 2
             + value(x * 0.173, y * 0.173, seed: seed ^ 0xB5297A4D)) / 7
        }

        /// 12 个固定的非规则盘内点 (最小点距 > 0.38), 两档半径复用; 不在规则圆周上采样。
        static let disk: [SIMD2<Double>] = [
            SIMD2(-0.16, -0.12), SIMD2(0.34, -0.08), SIMD2(-0.53, 0.20),
            SIMD2(0.03, 0.46), SIMD2(0.52, 0.39), SIMD2(-0.38, -0.60),
            SIMD2(0.17, -0.57), SIMD2(0.75, -0.40), SIMD2(-0.85, -0.20),
            SIMD2(-0.46, 0.75), SIMD2(0.08, 0.91), SIMD2(0.91, 0.03)
        ]

        /// 逻辑单位位移; 每个分量被限制在 ±0.38 bleed, support 可据此确定。
        static func displacement(_ x: Double, _ y: Double, bleed: Double) -> SIMD2<Double> {
            let dx = (fbm(x, y, seed: 0xA511E9B3) - 0.5) * 0.7
                + (value(x * 0.8, y * 0.8, seed: 0x63D83595) - 0.5) * 0.06
            let dy = (fbm(x, y, seed: 0x9E3779B9) - 0.5) * 0.7
                + (value(x * 0.8, y * 0.8, seed: 0x1B56C4E9) - 0.5) * 0.06
            return SIMD2(dx * bleed, dy * bleed)
        }

        static func tooth(_ amount: Double?, paper: PaperTexture?, x: Double, y: Double) -> Double {
            let strength = Brush.unit(amount ?? 0)
            guard strength > 0 else { return 1 }
            let shade: Double
            if let paper, paper.shade.count == PaperTexture.side * PaperTexture.side,
               paper.texel.isFinite, paper.texel > 0 {
                func wrap(_ q: Double) -> Int {
                    let r = floor(q / paper.texel).truncatingRemainder(dividingBy: Double(PaperTexture.side))
                    return Int(r < 0 ? r + Double(PaperTexture.side) : r)
                }
                shade = min(1, Double(paper.shade[wrap(y) * PaperTexture.side + wrap(x)]) / 255
                            * max(0, paper.strength) * 5)
            } else {
                shade = value(x * 1.7, y * 1.7, seed: 0xD1B54A35)
            }
            return 1 - strength * shade
        }
    }
}
