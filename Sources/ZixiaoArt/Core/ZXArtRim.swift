// 山脊浓边: 逻辑坐标的幂次衰减与横向 fbm 雾带; 无 Entropy, 无块内坐标。
import Foundation

public extension ZXArt {
    /// A layer that dissolves downward into cloud (山腰云锁): full ink above `top`, none below
    /// `bottom`, along a billowing edge. The ink itself thins, so the paper shows through; no
    /// paper-coloured patch is painted over it.
    struct LayerFade: Sendable, Hashable {
        public var top: Double
        public var bottom: Double
        public var seed: UInt32

        public init(top: Double, bottom: Double, seed: UInt32 = 0) {
            self.top = top; self.bottom = bottom; self.seed = seed
        }

        func keep(x: Double, y: Double) -> Double {
            guard x.isFinite, y.isFinite, bottom > top else { return 1 }
            let span = bottom - top
            let billow = (WashNoise.fbm(x * 0.9, 3.7, seed: seed) - 0.5) * span * 0.55
                + abs(sin(x * 0.045 + Double(seed % 97))) * span * 0.18
            let t = Brush.unit((y - (top + billow)) / (span * 0.75))
            return 1 - t * t * (3 - 2 * t)
        }
    }

    struct LayerRim: Sendable, Hashable {
        public var width: Double
        public var power: Double
        public var peakOpacity: Double
        public var ridge: [Float]
        public var ridgeX0: Double
        public var ridgeStep: Double
        public var seed: UInt32

        public init(width: Double = 16, power: Double = 2.4, peakOpacity: Double = 0.62,
                    ridge: [Float], ridgeX0: Double = 0, ridgeStep: Double = 2, seed: UInt32 = 0) {
            self.width = width; self.power = power; self.peakOpacity = peakOpacity
            self.ridge = ridge; self.ridgeX0 = ridgeX0; self.ridgeStep = ridgeStep; self.seed = seed
        }

        /// 与 LayerMist 相同的逐列插值; 非有限 / 空山脊不产生墨色。
        func keep(x: Double, y: Double) -> Double {
            guard x.isFinite, y.isFinite, width.isFinite, width > 0,
                  power.isFinite, power > 0, ridgeX0.isFinite,
                  ridgeStep.isFinite, ridgeStep > 0, !ridge.isEmpty else { return 0 }
            let envelope = LayerMist(depth: 1, blur: 0, peakOpacity: 1, ridge: ridge,
                                     ridgeX0: ridgeX0, ridgeStep: ridgeStep)
            let top = envelope.ridgeY(at: x)
            guard top.isFinite, y >= top else { return 0 }
            let depth = y - top
            // x 的频率远低于 y, 雾带沿水平方向延伸, 多频噪声避免等距条纹。
            let fog = WashNoise.fbm(x * 0.23, y * 2.4, seed: seed ^ 0xC2B2AE35)
            let t = Brush.unit((fog - 0.4) / 0.26)
            let opening = t * t * (3 - 2 * t)
            return Brush.unit(peakOpacity) * pow(1 + depth / width, -power) * opening
        }
    }
}
