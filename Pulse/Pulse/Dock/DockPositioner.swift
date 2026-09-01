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

    /// How far the cursor is from `target` — the handle while the dock rests, the dock itself
    /// once it is out — or `nil` when the cursor isn't on that screen at all. Zero inside the
    /// rect; outside, the larger of the two per-axis gaps, so a threshold reaches equally far
    /// beside, above and below the target and no further. Measuring against a rect rather than
    /// the bare edge is what keeps the trigger local: the edge is as tall as the screen, the
    /// handle is a few dots.
    ///
    /// Membership is tested against the whole `screenFrame`, so the menu-bar and Dock strips
    /// still count as "on this screen"; without that test a cursor on *another* display would
    /// still measure a finite distance and could pop the dock open on a screen the user isn't
    /// pointing at.
    static func distance(from point: CGPoint, to target: CGRect, screenFrame: CGRect) -> CGFloat? {
        guard screenFrame.contains(point) else { return nil }
        let dx = max(target.minX - point.x, point.x - target.maxX, 0)
        let dy = max(target.minY - point.y, point.y - target.maxY, 0)
        return max(dx, dy)
    }
}
