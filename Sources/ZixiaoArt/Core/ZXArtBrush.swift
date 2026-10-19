//  ZXArtBrush.swift — 独立的笔触几何: 压力、笔毫、飞白与开口墨圈
//
//  自行实现, 不取用 Entropy, 不影响 shanshui / nonflowers @1、@2。
//  跨平台取数的精确定义 (全部 UInt32 运算按 2^32 回绕; JS 乘法用 Math.imul、右移用 >>>):
//  h = seed XOR (index &* 0x9E3779B9); h = (h XOR (h >> 16)) &* 0x7FEB352D;
//  h = (h XOR (h >> 15)) &* 0x846CA68B; hash = h XOR (h >> 16)。
//  random(seed, index) = Double(hash) / 4294967296, 范围 [0, 1)。
//  noise(seed, x): k = floor(x), t = x-k, u = t*t*(3-2*t),
//  a = random(seed, UInt32(k mod 2^32)), b = random(seed, UInt32((k+1) mod 2^32)),
//  返回 a+(b-a)*u。所有噪声都是此一维值噪声, 不用三角函数取随机数。

import Foundation
import ZixiaoColor

public extension ZXArt {
    /// 无共享状态的笔触引擎。坐标与宽度均为逻辑单位, 可直接交给现有渲染器。
    enum Brush: Sendable {
        /// 顿笔渐收、两头尖、钉头、捺、按、起、梭形、锥形、点、等宽。
        public enum Profile: String, Sendable, CaseIterable {
            case brush, tip, nail, na, press, rise, lens, cone, dot, even
        }

        public struct Style: Sendable, Hashable {
            public var width: Double
            /// 焦 .96 / 浓 .82 / 重 .60 / 淡 .34 / 清 .16; 以墨色的 alpha 表达。
            public var tone: Double
            public var dry: Double
            /// 留给湿层的比例; 第 1 步只存值, 不改变几何与出图。
            public var wet: Double
            /// 正值表示中心线前进方向的左侧含墨更多, 范围 −1…1。
            public var side: Double
            public var bristles: Int?
            public var rough: Double
            public var fade: Double?
            /// 动画固定参考弧长, 也固定笔毫采样数; 墨体仍按实际弧长采样。
            public var gapLength: Double?
            public var profile: Profile

            public init(width: Double = 4, tone: Double = 0.82, dry: Double = 0.4, wet: Double = 0,
                        side: Double = 0, bristles: Int? = nil, rough: Double = 0.2, fade: Double? = nil,
                        gapLength: Double? = nil, profile: Profile = .brush) {
                self.width = width; self.tone = tone; self.dry = dry; self.wet = wet
                self.side = side; self.bristles = bristles; self.rough = rough; self.fade = fade
                self.gapLength = gapLength; self.profile = profile
            }
        }

        /// 墨体按左边正序、右边倒序围合; 首点不重复, 转 Shape 时显式闭合。
        public struct Stroke: Sendable {
            public var body: [SIMD2<Float>]
            public var bodyAlpha: (start: Float, end: Float)
            public var bristles: [Bristle]

            public init(body: [SIMD2<Float>] = [], bodyAlpha: (start: Float, end: Float) = (0, 0),
                        bristles: [Bristle] = []) {
                self.body = body; self.bodyAlpha = bodyAlpha; self.bristles = bristles
            }

            public struct Bristle: Sendable {
                public var runs: [[SIMD2<Float>]]
                public var width: Float
                public var alpha: Float

                public init(runs: [[SIMD2<Float>]], width: Float, alpha: Float) {
                    self.runs = runs; self.width = width; self.alpha = alpha
                }
            }
        }

        /// 第三维是压力 (通常传 1)。无长度、非有限输入或非正宽度返回空笔触。
        public static func stroke(_ centerline: [SIMD3<Double>], style: Style, seed: UInt32) -> Stroke {
            stroke(centerline, style: style, seed: seed, progress: 1)
        }

        /// 先建立整笔的网格再截取前缀, 不重算压力 / 噪声。p 向下取到采样点, 不追加插值点。
        public static func stroke(_ centerline: [SIMD3<Double>], style: Style, seed: UInt32,
                                  progress p: Double) -> Stroke {
            guard style.width.isFinite, style.width > 0, p.isFinite, p > 0,
                  centerline.count >= 2,
                  centerline.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return Stroke() }
            let curve = Curve(centerline)
            guard curve.length.isFinite, curve.length > 1e-9 else { return Stroke() }
            let progress = unit(p), dry = unit(style.dry), tone = unit(style.tone)
            let fade = unit(style.fade ?? dry * 0.55)
            let gapLength = style.gapLength.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            let reference = gapLength ?? curve.length
            let step = max(0.25, style.width * 0.18)
            let bodyCount = sampleCount(length: curve.length, step: step)
            // 固定 gapLength 时, 连采样网格都不随半径变化, 避免阈值附近的断点跳动。
            let hairCount = sampleCount(length: reference, step: gapLength == nil ? step : 0.5)
            let bodyLast = Int((progress * Double(bodyCount - 1)).rounded(.down))
            let hairLast = Int((progress * Double(hairCount - 1)).rounded(.down))

            func frame(_ i: Int, _ count: Int) -> (point: SIMD2<Double>, normal: SIMD2<Double>, width: Double) {
                let u = Double(i) / Double(count - 1), sample = curve.at(u)
                let w = style.width * pressure(style.profile, u) * max(0, sample.point.z)
                    * (1 + unit(style.rough) * (noise(seed ^ 0xA511E9B3, u * reference * 0.12) - 0.5) * 2)
                return (SIMD2(sample.point.x, sample.point.y), sample.normal, max(style.width * 0.04, w))
            }
            var left: [SIMD2<Float>] = [], right: [SIMD2<Float>] = []
            if bodyLast >= 1 {
                for i in 0...bodyLast {
                    let f = frame(i, bodyCount)
                    left.append(floatPoint(f.point + f.normal * (f.width * 0.5)))
                    right.append(floatPoint(f.point - f.normal * (f.width * 0.5)))
                }
            }
            let bodyOpacity = tone * pow(1 - dry, 1.6)
            let bodyEnd = Double(bodyLast) / Double(bodyCount - 1)
            var out = Stroke(body: left + Array(right.reversed()),
                             bodyAlpha: (Float(bodyOpacity), Float(bodyOpacity * (1 - fade * bodyEnd))))
            let count = style.bristles.map { min(56, max(0, $0)) }
                ?? Int(min(56, max(4, (style.width * 1.1).rounded())))
            guard count > 0 else { return out }
            for j in 0..<count {
                let key = hash(seed ^ 0x63D83595, UInt32(j))
                let off = (Double(j) + 0.15 + 0.7 * random(key, 0)) / Double(count) - 0.5
                let load = 1 - dry * (0.15 + 0.85 * abs(off) * 2) * random(key, 1)
                let scale = 0.035 + random(key, 2) * 0.065
                let end = 1 - dry * 0.2 * random(key, 3)
                let side = min(1, max(-1, style.side.isFinite ? style.side : 0))
                let sideAlpha = off * side < 0 ? 1 - abs(side) : 1
                var runs: [[SIMD2<Float>]] = [], run: [SIMD2<Float>] = []
                // 单点不成线, 暂不输出; 随 progress 增长后才成为完整段的前缀。
                func flush() {
                    if run.count >= 2 { runs.append(run) }
                    run.removeAll(keepingCapacity: true)
                }
                for i in 0...hairLast {
                    let u = Double(i) / Double(hairCount - 1), x = u * reference
                    let ink = load - dry * (0.08 + 1.15 * pow(u, 1.25))
                        + dry * ((noise(key ^ 0xB5297A4D, x * scale) - 0.5) * 1.15
                               + (noise(key ^ 0x68E31DA4, x * scale * 3.7) - 0.5) * 0.35)
                    if dry == 0 || (u <= end && ink > 0.16) {
                        let f = frame(i, hairCount)
                        let jitter = (noise(key ^ 0x1B56C4E9, x * 0.09) - 0.5) * 0.06
                        run.append(floatPoint(f.point + f.normal * ((off + jitter) * f.width)))
                    } else { flush() }
                }
                flush()
                // 透明度不随 progress 重算, 完整段与动画前缀的样式一致。
                out.bristles.append(.init(runs: runs,
                    width: Float(max(0.12, style.width / Double(count) * (0.45 + random(key, 4) * 0.55))),
                    alpha: Float(tone * sideAlpha * (0.5 + 0.5 * load) * (1 - fade * 0.5))))
            }
            return out
        }

        /// seed 决定起笔相位; sweep 缺省 1.86π。squash 为短轴 / 长轴, 圈始终留口。
        public static func ring(center: SIMD2<Double>, radius: Double, squash: Double, style: Style,
                                seed: UInt32, sweep: Double = 1.86 * .pi) -> Stroke {
            guard center.x.isFinite, center.y.isFinite, radius.isFinite, radius > 0,
                  squash.isFinite, squash > 0, sweep.isFinite, sweep > 0 else { return Stroke() }
            let span = min(sweep, 2 * .pi - 0.001), phase = random(seed, 0) * 2 * .pi
            let points = (0...96).map { i -> SIMD3<Double> in
                let a = phase + span * Double(i) / 96
                return SIMD3(center.x + radius * cos(a), center.y + radius * squash * sin(a), 1)
            }
            return stroke(points, style: style, seed: seed)
        }

        /// 周期值噪声调制半径, 再压扁、旋转; 首点不重复, 调用方按闭合多边形填充。
        public static func blot(center: SIMD2<Double>, radius: Double, squash: Double, angle: Double,
                                seed: UInt32) -> [SIMD2<Float>] {
            guard center.x.isFinite, center.y.isFinite, radius.isFinite, radius > 0,
                  squash.isFinite, squash > 0, angle.isFinite else { return [] }
            return (0..<48).map { i in
                let a = Double(i) / 48 * 2 * .pi, x = Double(i) / 48 * 8
                let k = UInt32(x.rounded(.down)), t = x - floor(x), u = t * t * (3 - 2 * t)
                let n = random(seed, k) + (random(seed, (k + 1) % 8) - random(seed, k)) * u
                let r = radius * (0.82 + 0.3 * n), px = r * cos(a), py = r * squash * sin(a)
                return floatPoint(center + SIMD2(px * cos(angle) - py * sin(angle), px * sin(angle) + py * cos(angle)))
            }
        }
    }
}

// MARK: - 取数、压力与弧长网格

extension ZXArt.Brush {
    static func hash(_ seed: UInt32, _ index: UInt32) -> UInt32 {
        var h = seed ^ (index &* 0x9E3779B9)
        h = (h ^ (h >> 16)) &* 0x7FEB352D
        h = (h ^ (h >> 15)) &* 0x846CA68B
        return h ^ (h >> 16)
    }

    static func random(_ seed: UInt32, _ index: UInt32) -> Double { Double(hash(seed, index)) / 4_294_967_296 }

    static func noise(_ seed: UInt32, _ x: Double) -> Double {
        let k = floor(x), t = x - k, u = t * t * (3 - 2 * t)
        func index(_ v: Double) -> UInt32 {
            let r = v.truncatingRemainder(dividingBy: 4_294_967_296)
            return UInt32(r < 0 ? r + 4_294_967_296 : r)
        }
        let a = random(seed, index(k)), b = random(seed, index(k + 1))
        return a + (b - a) * u
    }

    static func unit(_ x: Double) -> Double { x.isFinite ? min(1, max(0, x)) : 0 }
    static func floatPoint(_ p: SIMD2<Double>) -> SIMD2<Float> { SIMD2(Float(p.x), Float(p.y)) }
    static func sampleCount(length: Double, step: Double) -> Int {
        Int(min(599, max(1, ceil(length / step)))) + 1
    }

    /// 每条曲线均以整笔归一化弧长为输入, 最后统一应用 4% 最小宽度。
    static func pressure(_ profile: Profile, _ s: Double) -> Double {
        switch profile {
        case .brush: return (0.45 + 0.55 * min(1, s / 0.08)) * pow(1 - s, 0.65)
        case .tip: return pow(max(0, sin(.pi * s)), 0.7)
        case .nail: return (0.22 + 0.78 * exp(-s * 12)) * pow(1 - s, 0.35)
        case .na: return pow(s, 0.7) * (1 - pow(s, 8)) * 1.8
        case .press: return 0.25 + 0.75 * pow(max(0, sin(.pi * s)), 0.5)
        case .rise: return pow(s, 0.6)
        case .lens: return pow(max(0, sin(.pi * s)), 1.6)
        case .cone: return 1 - s
        case .dot: return pow(max(0, sin(.pi * s)), 0.35) * (1 - 0.5 * s)
        case .even: return 1
        }
    }

    /// Catmull-Rom 每跨 16 等分 (端点复制), 再在累计弧长表上线性查值, 压力一同插值。
    struct Curve {
        var points: [SIMD3<Double>] = []
        var distances: [Double] = [0]
        var length: Double { distances.last ?? 0 }

        init(_ input: [SIMD3<Double>]) {
            for i in 0..<(input.count - 1) {
                let a = input[max(0, i - 1)], b = input[i], c = input[i + 1], d = input[min(input.count - 1, i + 2)]
                for j in 0..<16 {
                    let t = Double(j) / 16, t2 = t * t, t3 = t2 * t
                    let linear = (c - a) * t
                    let quadratic = (a * 2 - b * 5 + c * 4 - d) * t2
                    let cubic = (-a + b * 3 - c * 3 + d) * t3
                    let p = (b * 2 + linear + quadratic + cubic) * 0.5
                    points.append(p)
                }
            }
            points.append(input[input.count - 1])
            for i in 1..<points.count {
                let v = points[i] - points[i - 1]
                distances.append(distances[i - 1] + (v.x * v.x + v.y * v.y).squareRoot())
            }
        }

        func at(_ u: Double) -> (point: SIMD3<Double>, normal: SIMD2<Double>) {
            let target = u * length
            var lo = 0, hi = points.count - 1
            while lo + 1 < hi {
                let m = (lo + hi) / 2
                if distances[m] <= target { lo = m } else { hi = m }
            }
            // 重合控制点可能产生零长段, 切线向附近非零长段借。
            while hi < points.count - 1 && distances[hi] <= distances[lo] { hi += 1 }
            while lo > 0 && distances[hi] <= distances[lo] { lo -= 1 }
            let span = distances[hi] - distances[lo]
            let t = span > 0 ? (target - distances[lo]) / span : 0
            let delta = points[hi] - points[lo], norm = (delta.x * delta.x + delta.y * delta.y).squareRoot()
            return (points[lo] + delta * t, norm > 0 ? SIMD2(-delta.y / norm, delta.x / norm) : SIMD2(0, 1))
        }
    }
}

public extension ZXArt {
    /// tone 已计入笔触 alpha; 以 mapGray(0) 取纯墨, 不再重复乘 tone。
    /// Shape 只有单一填充色, 墨体首尾 alpha 暂取均值; 首尾原值留在 Stroke 供后续湿层使用。
    static func shapes(from stroke: Brush.Stroke, palette: Palette = .paperInk) -> [Shape] {
        var shapes: [Shape] = []
        if stroke.body.count >= 3 {
            let alpha = Double(stroke.bodyAlpha.start + stroke.bodyAlpha.end) * 0.5
            shapes.append(Shape(points: stroke.body, fill: palette.mapGray(0, alpha: alpha), stroke: nil,
                                lineWidth: 0, closed: true))
        }
        for hair in stroke.bristles {
            for run in hair.runs where run.count >= 2 {
                shapes.append(Shape(points: run, fill: nil, stroke: palette.mapGray(0, alpha: Double(hair.alpha)),
                                    lineWidth: hair.width, closed: false))
            }
        }
        return shapes
    }
}
