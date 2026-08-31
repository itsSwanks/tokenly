import SwiftUI
import AppKit

/// Colours that carry meaning. Everything structural (tracks, wells, pills, secondary text) is
/// `.primary`/`.secondary` at an opacity, so it adapts to the glass and to Light/Dark on its own.
enum Palette {
    static let green = Color(hex: 0x32D74B)
    /// Neon yellow disappears on a bright desktop; light mode gets a deeper amber (spec §18.5).
    /// The only `.darkAqua` left in the app, and it *reads* the effective appearance rather than
    /// pinning one — a dynamic `NSColor` has no other way to ask which side of the fence it is on.
    static let yellow = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0xE4 / 255, green: 0xFF / 255, blue: 0x1A / 255, alpha: 1)
            : NSColor(red: 0xB8 / 255, green: 0xA4 / 255, blue: 0x00 / 255, alpha: 1)
    })
    static let orange = Color(hex: 0xFF4F1F)
    static let red = Color(hex: 0xFF3B30)

    /// Structural fills on glass.
    static let well = Color.primary.opacity(0.08)
    static let track = Color.primary.opacity(0.12)
    static let pill = Color.primary.opacity(0.10)
    static let pillHover = Color.primary.opacity(0.16)
    static let disconnected = Color.secondary.opacity(0.6)
    /// The hairline that catches the light on the wells' upper edge.
    static let hairline = Color.white.opacity(0.18)

    // The settings panel's grouped inset lists (spec §19.1/§19.3).
    static let group = Color.primary.opacity(0.06)
    static let groupRing = Color.primary.opacity(0.07)
    static let separator = Color.primary.opacity(0.08)
    static let grip = Color.primary.opacity(0.3)
    /// The footer link (spec §19.5) — the design's cyan/azure pair, dynamic like `yellow`.
    static let link = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0x7C / 255, green: 0xC6 / 255, blue: 0xD8 / 255, alpha: 1)
            : NSColor(red: 0x00 / 255, green: 0x66 / 255, blue: 0xCC / 255, alpha: 1)
    })
    /// Quit's hovered text — softer than `red`, per the design; the pill behind it is `red` at 0.16.
    static let quitHover = Color(hex: 0xFF6961)
}

/// The Appearance row (spec §19.6): `auto` follows the system, the other two pin. One override —
/// `NSApp.appearance` — themes every surface, because nothing else in the app names a fixed side.
enum AppearanceMode: String, Codable, Sendable, CaseIterable {
    case auto, light, dark

    /// The name to pin `NSApp.appearance` to; `nil` means follow the system live.
    var pinnedAppearanceName: NSAppearance.Name? {
        switch self {
        case .auto: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}

/// Constants that are not the dock's — the dock scales through `DockMetrics`.
enum Metrics {
    // The auto-hide resting handle (spec §17.1).
    static let handleWidth: CGFloat = 9
    static let handlePaddingV: CGFloat = 14
    static let handleDot: CGFloat = 5
    static let handleDotGap: CGFloat = 13
    static let handleRadius: CGFloat = 6
    static let handleGlowRadius: CGFloat = 4.5

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

    static let settingsWidth: CGFloat = 352
    static let settingsRadius: CGFloat = 16
    // System-Settings density (spec §19.1): 38 pt provider rows, 40 pt control rows,
    // radius-10 inset groups, 14/14/12 panel padding.
    static let settingsPadding: CGFloat = 14
    static let settingsPaddingBottom: CGFloat = 12
    static let settingsRowHeight: CGFloat = 38
    static let settingsOptionRowHeight: CGFloat = 40
    static let settingsGroupRadius: CGFloat = 10
}

/// Motion presets (spec §18.4). SwiftUI springs for in-window motion; an overshooting cubic
/// for AppKit window moves, which can't take a `Spring` directly.
enum Motion {
    /// Hover lift / press dip.
    static let lift: Animation = .spring(duration: 0.35, bounce: 0.35)
    /// Geometry settling after a resize or reorder.
    static let settle: Animation = .spring(duration: 0.45, bounce: 0.15)
    /// A surface appearing out of the dock.
    static let materialize: Animation = .spring(duration: materializeSeconds, bounce: 0.2)
    /// Ring sweep and rolling digits.
    static let sweep: Animation = .smooth(duration: 0.7)

    /// `materialize`'s and `reduced`'s wall clocks. An `Animation` will not tell you how long it
    /// runs, and AppKit sometimes has to wait a SwiftUI animation out — the callout orders its
    /// window away only once the glass has finished dissolving. Kept beside the animations they
    /// time so the two cannot drift apart.
    static let materializeSeconds: TimeInterval = 0.4
    static let reducedSeconds: TimeInterval = 0.18

    /// Reduce Motion swaps every spring for a short ease-out.
    static func reduced(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: reducedSeconds) : animation
    }

    static let dockSlide: TimeInterval = 0.42
    static let calloutFollow: TimeInterval = 0.3
    static let pulse: TimeInterval = 2.0
    static let hoverGrace: TimeInterval = 0.14
    static let collapseGrace: TimeInterval = 0.4
    /// The handle crossfade is the other half of the dock slide — the two run against each other,
    /// so they share one clock and land together rather than leaving the handle gone (or still
    /// there) while the dock is mid-flight.
    static let handleFade: TimeInterval = dockSlide

    /// The classic "ease-out back": control point y above 1 overshoots and settles, which is
    /// as close to a spring as a `CAMediaTimingFunction` gets. Rebuilt per access —
    /// `CAMediaTimingFunction` is not Sendable, so it can't be a `static let` under Swift 6.
    static var springCurve: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.34, 1.28, 0.64, 1)
    }
    /// Plain ease-out for fades, where an overshoot would flash past full opacity.
    static var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
    }
    /// The AppKit side of `reduced`: the curve to use for window moves.
    static var windowCurve: CAMediaTimingFunction {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? timingFunction : springCurve
    }
}

enum ScreenEdge: String, Codable, Sendable {
    case left, right
}

/// The dock's silhouette (spec §18.2): `notch` grows out of the screen edge through concave
/// flares; `pill` is the flare-less slab. Both are the same glass; only the shape differs.
enum DockStyle: String, Codable, Sendable, CaseIterable {
    case notch, pill
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
