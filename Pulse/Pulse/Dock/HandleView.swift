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
}

/// The auto-hide resting UI: one glowing dot per enabled provider inside the frosted strip.
/// The frost itself is the window's `NSVisualEffectView` (`HandleContainerView`); this view
/// draws only the dots, so the glass is never double-painted.
struct HandleView: View {
    let model: HandleModel

    var body: some View {
        let layout = model.layout
        ZStack(alignment: .topLeading) {
            // The tint over the window's vibrancy, under the dots — the same two-layer recipe
            // the callout and the Glass dock use. The container's `CAShapeLayer` mask rounds
            // it along with everything else in the window.
            Palette.handleTint
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
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }
}
