import CoreGraphics

/// Where the dock window goes on a screen. AppKit coordinates (origin bottom-left).
enum DockPositioner {
    static func frame(windowSize: CGSize, edge: ScreenEdge, yFraction: Double, in visible: CGRect) -> CGRect {
        let x = edge == .right ? visible.maxX - windowSize.width : visible.minX
        let centerY = visible.minY + CGFloat(min(1, max(0, yFraction))) * visible.height
        let y = clampedY(centerY - windowSize.height / 2, height: windowSize.height, in: visible)
        return CGRect(x: x, y: y, width: windowSize.width, height: windowSize.height)
    }

    /// Keeps the whole window inside `visible`; a window taller than the screen sits on its bottom edge.
    static func clampedY(_ y: CGFloat, height: CGFloat, in visible: CGRect) -> CGFloat {
        let maxY = max(visible.minY, visible.maxY - height)
        return min(max(y, visible.minY), maxY)
    }

    static func yFraction(of frame: CGRect, in visible: CGRect) -> Double {
        guard visible.height > 0 else { return 0.5 }
        return Double((frame.midY - visible.minY) / visible.height)
    }

    /// How far the cursor is from the dock's edge, or `nil` when the cursor isn't on that
    /// screen at all.
    ///
    /// Two rectangles, deliberately: the distance is measured against `visible`, because that
    /// is where `frame(windowSize:edge:yFraction:in:)` puts the dock — on a display whose macOS
    /// Dock occupies the same edge, measuring against the full screen would push the trigger
    /// zone behind it. Membership is tested against the whole `screenFrame`, so the menu-bar and
    /// Dock strips still count as "on this screen"; without that test a cursor on *another*
    /// display would produce a large negative number, which reads as "closer than close" and
    /// pops the dock open on a screen the user isn't pointing at.
    static func distanceToEdge(point: CGPoint, edge: ScreenEdge, visible: CGRect, screenFrame: CGRect) -> CGFloat? {
        guard screenFrame.contains(point) else { return nil }
        return edge == .right ? visible.maxX - point.x : point.x - visible.minX
    }
}
