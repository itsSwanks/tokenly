import CoreGraphics

/// Places the callout beside the dock so its tail points at a ring. AppKit coordinates.
enum CalloutPositioner {
    /// Transparent band the callout window carries beyond the bubble on its three non-tail
    /// sides, purely so the drop shadow has somewhere to fall.
    ///
    /// An `NSWindow` clips its shadow to its own frame. The callout used to be exactly bubble
    /// sized, so the spec's `0 18 50 rgba(0,0,0,.45)` was shaved off at the card's edges and
    /// only a hairline of it survived. 40 pt clears a 50 pt blur pushed 18 pt down. Nothing is
    /// painted in the band — the glass stays inset to the bubble, and `CalloutContainerView`
    /// hit-tests it away so clicks there reach whatever is behind.
    static let shadowMargin: CGFloat = 40

    /// - Parameters:
    ///   - calloutSize: the *bubble* — card plus tail — not the window.
    ///   - margin: the transparent band to add on the non-tail sides. `0` for callers that
    ///     want a bubble-sized window (the settings panel draws its own SwiftUI shadow).
    /// - Returns: the *window* frame — the bubble grown by `margin` — and the tail's y measured
    ///   from the **bubble's** bottom edge, which is the space `CalloutView` offsets its tail in.
    static func place(calloutSize: CGSize, dockFrame: CGRect, ringCenterY: CGFloat, edge: ScreenEdge,
                      in visible: CGRect, margin: CGFloat = shadowMargin) -> (frame: CGRect, tailY: CGFloat) {
        let x = edge == .right ? dockFrame.minX - Metrics.calloutGap - calloutSize.width : dockFrame.maxX + Metrics.calloutGap
        let y = DockPositioner.clampedY(ringCenterY - calloutSize.height / 2, height: calloutSize.height, in: visible)
        let tailY = min(max(ringCenterY - y, Metrics.tailHalfHeight), calloutSize.height - Metrics.tailHalfHeight)
        // The *bubble* is what gets clamped into `visible`; the margin is allowed to hang past
        // the screen, since it is transparent and only the shadow that spills into it is lost.
        let frame = CGRect(x: edge == .right ? x - margin : x, y: y - margin,
                           width: calloutSize.width + margin, height: calloutSize.height + 2 * margin)
        return (frame, tailY)
    }

    /// Where the bubble sits inside a window `place` framed — the inverse of the margin it
    /// added. In view coordinates (y up), so `CalloutContainerView` can lay its glass and its
    /// hosting view out against it.
    static func bubbleRect(inWindowOfSize size: CGSize, edge: ScreenEdge, margin: CGFloat = shadowMargin) -> CGRect {
        CGRect(x: edge == .right ? margin : 0, y: margin,
               width: max(0, size.width - margin), height: max(0, size.height - 2 * margin))
    }
}
