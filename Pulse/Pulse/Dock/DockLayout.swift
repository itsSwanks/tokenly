import CoreGraphics

/// Pure geometry of the dock panel in top-left-origin panel coordinates.
/// Everything that draws or hit-tests the dock reads from here.
///
/// v3 dropped the `collapsed` variant: the hidden dock is the *same* panel slid fully
/// off-screen, and the resting UI is a separate window (`HandleLayout`). One geometry means
/// the window never resizes as it hides, so the slide is a pure translation.
///
/// Every dimension comes from `metrics` (spec §18.3), so the Small/Medium/Large setting scales
/// the whole slab — window, cells, gear and flares — from one factor, and a size change is just
/// a different layout value that the window and the content animate to together.
struct DockLayout: Equatable {
    let cellCount: Int
    let edge: ScreenEdge
    let metrics: DockMetrics

    init(cellCount: Int, edge: ScreenEdge, metrics: DockMetrics = .medium) {
        self.cellCount = max(0, cellCount)
        self.edge = edge
        self.metrics = metrics
    }

    var size: CGSize {
        let cells = CGFloat(cellCount) * metrics.cellHeight + CGFloat(max(0, cellCount - 1)) * metrics.cellGap
        return CGSize(width: metrics.panelWidth, height: metrics.paddingTop + cells + metrics.gearRowHeight + metrics.paddingBottom)
    }

    /// Ring centers, top to bottom. The three terms are hoisted out of the closure because a
    /// single `CGFloat` expression mixing them all is a type-checker cliff.
    var cellCenters: [CGPoint] {
        let x: CGFloat = metrics.panelWidth / 2
        let firstY: CGFloat = metrics.paddingTop + metrics.ringDiameter / 2
        let pitch: CGFloat = metrics.cellHeight + metrics.cellGap
        return (0..<cellCount).map { CGPoint(x: x, y: firstY + CGFloat($0) * pitch) }
    }

    /// Ring + label rectangle for each cell (the hover/click target).
    var cellFrames: [CGRect] {
        cellCenters.map { c in
            CGRect(x: c.x - metrics.ringDiameter / 2, y: c.y - metrics.ringDiameter / 2,
                   width: metrics.ringDiameter, height: metrics.cellHeight)
        }
    }

    var gearCenter: CGPoint {
        CGPoint(x: size.width / 2, y: size.height - metrics.paddingBottom - metrics.gearRowHeight / 2)
    }

    var gearFrame: CGRect {
        CGRect(x: gearCenter.x - metrics.gearRowHeight / 2, y: gearCenter.y - metrics.gearRowHeight / 2,
               width: metrics.gearRowHeight, height: metrics.gearRowHeight)
    }

    func cellIndex(at point: CGPoint) -> Int? {
        cellFrames.firstIndex { $0.contains(point) }
    }

    /// The concave flares are drawn outside the panel body; the window is taller by this much
    /// on each side. The Pill style draws no flares but keeps the same margin, which is where
    /// its drop shadow spills.
    var flareInset: CGFloat { metrics.flareRadius }

    /// Window size in points, including the flare margins.
    var windowSize: CGSize {
        CGSize(width: size.width, height: size.height + 2 * flareInset)
    }

    /// Where the panel body sits inside the window (top-left origin).
    var contentOrigin: CGPoint {
        CGPoint(x: 0, y: flareInset)
    }
}
