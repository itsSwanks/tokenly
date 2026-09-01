import SwiftUI

/// The dock silhouette. `.notch` is a rounded rectangle whose screen-edge side is flat and
/// which grows out of the edge through two concave quarter-circle flares; `.pill` is the same
/// rounded rectangle with no flares at all, so its bounding box is exactly `rect`. Drawn as one
/// path either way, so the panel is a single fill.
struct DockShape: Shape {
    let edge: ScreenEdge
    var style: DockStyle = .notch
    /// The dock's size setting: corner and flare radii scale with the slab (spec §18.3).
    var metrics: DockMetrics = .medium

    /// The scale is what a size change actually changes, and every radius below is derived from
    /// it — so animating it lets the corners and flares *interpolate* through the size morph
    /// instead of snapping to the new radii on the first frame while the window glides (§18.4).
    var animatableData: CGFloat {
        get { metrics.scale }
        set { metrics = DockMetrics(scale: newValue) }
    }

    func path(in rect: CGRect) -> Path {
        var p = style == .pill ? pillPath(in: rect) : notchPath(in: rect)
        if edge == .left {
            p = p.applying(CGAffineTransform(translationX: rect.maxX + rect.minX, y: 0).scaledBy(x: -1, y: 1))
        }
        return p
    }

    /// Built for the right edge (flat side at maxX); `path(in:)` mirrors it for the left.
    private func notchPath(in rect: CGRect) -> Path {
        let r = metrics.innerRadius, f = metrics.flareRadius
        var p = Path()
        let x0 = rect.minX, x1 = rect.maxX, y0 = rect.minY, y1 = rect.maxY
        p.move(to: CGPoint(x: x1, y: y0 - f))                                   // top of the upper flare, on the edge
        p.addArc(center: CGPoint(x: x1 - f, y: y0 - f), radius: f,             // concave: curve inward to the panel top
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: x0 + r, y: y0))
        p.addArc(center: CGPoint(x: x0 + r, y: y0 + r), radius: r,             // top-left rounded corner
                 startAngle: .degrees(-90), endAngle: .degrees(-180), clockwise: true)
        p.addLine(to: CGPoint(x: x0, y: y1 - r))
        p.addArc(center: CGPoint(x: x0 + r, y: y1 - r), radius: r,             // bottom-left rounded corner
                 startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: x1 - f, y: y1))
        p.addArc(center: CGPoint(x: x1 - f, y: y1 + f), radius: f,             // concave lower flare
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: x1, y: y0 - f))
        p.closeSubpath()
        return p
    }

    /// The same inward corners as the notch, square against the screen edge, nothing outside
    /// `rect`. Built right-edge-first like `notchPath`, so the rounded side is the left one.
    private func pillPath(in rect: CGRect) -> Path {
        EdgeSlabPath.path(in: rect, radius: metrics.innerRadius, roundedSide: .left)
    }
}

extension DockShape {
    /// True when a point in the dock *window's* own coordinates — top-left origin, flare
    /// margins included — falls inside the silhouette.
    ///
    /// The window is `DockLayout.windowSize`, taller than the panel body by a flare margin at
    /// each end, and in both styles most of that margin is transparent: the Notch flares fill
    /// only a quarter-circle beside the screen edge, and the Pill slab fills none of it at all.
    /// Hit-testing the bounding box instead would swallow clicks in empty space.
    static func contains(windowPoint: CGPoint, layout: DockLayout, style: DockStyle) -> Bool {
        DockShape(edge: layout.edge, style: style, metrics: layout.metrics)
            .path(in: CGRect(origin: layout.contentOrigin, size: layout.size))
            .contains(windowPoint)
    }
}

/// `EdgeSlabPath` as a SwiftUI `Shape`, for `.glassEffect(in:)` and clipping.
struct EdgeSlabShape: Shape {
    let radius: CGFloat
    let roundedSide: EdgeSlabPath.Side

    func path(in rect: CGRect) -> Path { EdgeSlabPath.path(in: rect, radius: radius, roundedSide: roundedSide) }
}

/// A rounded rectangle rounded on one vertical side only — the shape shared by the Pill dock
/// and the auto-hide handle, both of which sit flush against a screen edge and so round only
/// their inward corners. Always built rounding the *right* side; callers mirror for the left
/// edge. Kept out of `Shape` so `DockShape.pillPath` and `EdgeSlabShape` can share one builder.
enum EdgeSlabPath {
    enum Side { case left, right }

    static func path(in rect: CGRect, radius: CGFloat, roundedSide: Side) -> Path {
        // Only one vertical side is rounded, so the two arcs sit side by side vertically but
        // never horizontally: the real limits are `r ≤ width` and `2r ≤ height`. Halving the
        // width as well (the rounded-rectangle rule) would flatten a 9 pt handle's 6 pt
        // corners to 4.5.
        let r = min(radius, min(rect.width, rect.height / 2))
        let x0 = rect.minX, x1 = rect.maxX, y0 = rect.minY, y1 = rect.maxY
        var p = Path()
        switch roundedSide {
        case .right:
            p.move(to: CGPoint(x: x0, y: y0))
            p.addLine(to: CGPoint(x: x1 - r, y: y0))
            p.addArc(center: CGPoint(x: x1 - r, y: y0 + r), radius: r,
                     startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: x1, y: y1 - r))
            p.addArc(center: CGPoint(x: x1 - r, y: y1 - r), radius: r,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: x0, y: y1))
        case .left:
            p.move(to: CGPoint(x: x1, y: y0))
            p.addLine(to: CGPoint(x: x0 + r, y: y0))
            p.addArc(center: CGPoint(x: x0 + r, y: y0 + r), radius: r,
                     startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)
            p.addLine(to: CGPoint(x: x0, y: y1 - r))
            p.addArc(center: CGPoint(x: x0 + r, y: y1 - r), radius: r,
                     startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            p.addLine(to: CGPoint(x: x1, y: y1))
        }
        p.closeSubpath()
        return p
    }
}
