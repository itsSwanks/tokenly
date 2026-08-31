import SwiftUI
import Observation
import PulseCore

struct HandleDot: Identifiable, Equatable {
    let id: ProviderID
    let state: RingState

    /// The dot's semantic color, or gray while there is nothing real to show — the same rule
    /// the rings follow, so the handle never implies a status the dock would contradict.
    var color: Color {
        if case .value(_, let level, _, _, _) = state { return level.color }
        return Palette.disconnected
    }
}

/// Everything `HandleView` draws. Updated from `DockWindowController.render()`.
@MainActor
@Observable
final class HandleModel {
    var layout = HandleLayout(dotCount: 0)
    var dots: [HandleDot] = []
    /// Which screen edge the handle rests against — it rounds only its two inward corners, so
    /// the flat side has to follow the dock. Set by `HandleWindowController.render`.
    var edge: ScreenEdge = .right
}

/// The auto-hide resting UI: one glowing dot per enabled provider on a Liquid Glass sliver.
/// One `.glassEffect` and nothing else (spec §18.2) — the window itself is transparent, so the
/// glass samples the desktop directly and the dots are plain fills inside it.
struct HandleView: View {
    let model: HandleModel

    var body: some View {
        let layout = model.layout
        dots(layout)
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
            // The whole strip is the glass: `EdgeSlabShape` rounds only the inward side, so the
            // screen-edge side stays square and the rim light lands on the corners the user sees.
            // The dots are the glass's *content* rather than a sibling stacked on top of it, the
            // same way `DockView` nests its rings, so the framework resolves them against the
            // tone the glass rendered instead of against the window's appearance.
            .glassEffect(.regular, in: EdgeSlabShape(radius: Metrics.handleRadius,
                                                     roundedSide: model.edge == .right ? .left : .right))
    }

    @ViewBuilder
    private func dots(_ layout: HandleLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.dots.enumerated()), id: \.element.id) { index, dot in
                if index < layout.dotCenters.count {
                    let center = layout.dotCenters[index]
                    Circle()
                        .fill(dot.color)
                        .frame(width: Metrics.handleDot, height: Metrics.handleDot)
                        // ≈ `box-shadow: 0 0 9px <color>`: SwiftUI's radius is roughly half the
                        // CSS blur, and the near-opaque color keeps the bloom readable at 5 pt.
                        .shadow(color: dot.color.opacity(0.9), radius: Metrics.handleGlowRadius)
                        .position(x: center.x, y: center.y)
                }
            }
        }
    }
}
