import SwiftUI

enum Palette {
    static let panel = Color(hex: 0x0A0A0A)
    static let well = Color(hex: 0x1C1C1E)
    static let track = Color(hex: 0x2C2C2E)
    static let gray = Color(hex: 0x8E8E93)
    static let disconnected = Color(hex: 0x5A5A5E)
    static let green = Color(hex: 0x32D74B)
    static let yellow = Color(hex: 0xE4FF1A)
    static let orange = Color(hex: 0xFF4F1F)
    static let red = Color(hex: 0xFF3B30)
    static let pillHover = Color(hex: 0x3A3A3D)

    // The frosted glass shared by the callout (spec §16) and, in v3, the Glass dock style
    // (§17). The tint is painted *over* the window's vibrancy, so it is deliberately
    // translucent; opaque `panel` still fills the Notch dock.
    static let glassTint = Color(hex: 0x101012).opacity(0.55)   // rgba(16,16,18,.55)
    static let glassTail = Color(hex: 0x141417).opacity(0.72)   // rgba(20,20,23,.72)
    static let glassBorder = Color.white.opacity(0.14)
    static let glassHighlight = Color.white.opacity(0.12)

    /// The auto-hide handle's own tint, painted over its vibrancy the way `glassTint` is
    /// painted over the Glass dock's (CHANGES §5: `rgba(30,30,32,.5)`).
    static let handleTint = Color(hex: 0x1E1E20).opacity(0.5)

    /// The auto-hide handle's border is a touch brighter than the card's (.16 vs .14): at
    /// 9 pt wide it is nearly all border, and .14 disappears against a busy desktop.
    static let handleBorder = Color.white.opacity(0.16)
}

enum Metrics {
    static let panelWidth: CGFloat = 78
    static let paddingTop: CGFloat = 18
    static let paddingBottom: CGFloat = 10
    static let cellGap: CGFloat = 22
    static let ringDiameter: CGFloat = 48
    static let ringStroke: CGFloat = 3.5
    static let wellRadius: CGFloat = 16.5
    static let glyphSize: CGFloat = 18
    static let labelGap: CGFloat = 7
    static let labelHeight: CGFloat = 20
    static let cellHeight: CGFloat = ringDiameter + labelGap + labelHeight   // 75
    static let gearRowHeight: CGFloat = 20
    static let gearSize: CGFloat = 13
    static let innerRadius: CGFloat = 22
    static let flareRadius: CGFloat = 20

    // The auto-hide resting handle (spec §17.1) — the v2 color sliver's replacement.
    static let handleWidth: CGFloat = 9
    static let handlePaddingV: CGFloat = 14
    static let handleDot: CGFloat = 5
    static let handleDotGap: CGFloat = 13
    static let handleRadius: CGFloat = 6
    static let handleGlowRadius: CGFloat = 4.5    // ≈ `box-shadow: 0 0 9px`

    static let edgeProximity: CGFloat = 44
    static let edgeFarAway: CGFloat = 200
    static let dragThreshold: CGFloat = 5

    static let calloutWidth: CGFloat = 320
    static let calloutRadius: CGFloat = 16
    static let calloutPaddingV: CGFloat = 16
    static let calloutPaddingH: CGFloat = 18
    static let calloutGap: CGFloat = 24
    static let tailHalfHeight: CGFloat = 9
    static let tailLength: CGFloat = 11

    static let settingsWidth: CGFloat = 300
    static let settingsRadius: CGFloat = 22
    static let settingsPadding: CGFloat = 20
}

enum Motion {
    static let dockSlide: TimeInterval = 0.26
    static let calloutIn: TimeInterval = 0.16
    static let calloutOut: TimeInterval = 0.11
    static let calloutFollow: TimeInterval = 0.22
    /// Glass-frost entry (spec §16): the panel fades in while the card content de-blurs.
    static let calloutFadeIn: TimeInterval = 0.3
    static let frostIn: TimeInterval = 0.6
    static let ringSweep: TimeInterval = 0.7
    static let pulse: TimeInterval = 2.0
    static let hoverGrace: TimeInterval = 0.14
    static let collapseGrace: TimeInterval = 0.4
    /// The handle crossfades against the dock's slide: out as the dock arrives, in as it leaves.
    static let handleFade: TimeInterval = 0.25

    static func ease(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.32, 0.72, 0, 1, duration: duration)
    }
    // CAMediaTimingFunction is a class (non-Sendable), so this can't be a `static let`
    // under Swift 6 strict concurrency — build a fresh instance on each access instead.
    static var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
    }
}

enum ScreenEdge: String, Codable, Sendable {
    case left, right
}

/// How the dock panel is materialized (spec §17.2). `notch` is the original opaque slab with
/// the concave corner flares; `glass` is the flare-less frosted slab over live vibrancy.
enum DockStyle: String, Codable, Sendable, CaseIterable {
    case notch, glass
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
