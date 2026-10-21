import Foundation

/// Shared geometry: the deck and its reflected arch use exactly the same span and waterline.
struct PaintingBridge {
    enum Kind: CaseIterable { case arch, slab, timber }
    let kind: Kind
    let width: Double
    let rise: Double
    let railing: Bool

    var deck: [ZXArt.P] {
        (0...36).map { i in
            let t = Double(i) / 36
            return .init(width * t, kind == .arch ? 54 - sin(t * .pi) * (rise + 4) : 42 + t)
        }
    }
    var arch: [ZXArt.P] {
        (0...36).map { i in
            let t = Double(i) / 36
            return .init(width * (0.10 + 0.80 * t), 60 - sin(t * .pi) * rise)
        }
    }
}
