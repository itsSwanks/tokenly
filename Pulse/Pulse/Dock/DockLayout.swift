import CoreGraphics

/// Pure geometry of the dock panel in top-left-origin panel coordinates.
/// Everything that draws or hit-tests the dock reads from here.
///
/// v3 dropped the `collapsed` variant: the hidden dock is the *same* panel slid fully
/// off-screen, and the resting UI is a separate window (`HandleLayout`). One geometry means
/// the window never resizes as it hides, so the slide is a pure translation.
struct DockLayout: Equatable {
    let cellCount: Int
    let edge: ScreenEdge

    init(cellCount: Int, edge: ScreenEdge) {
        self.cellCount = max(0, cellCount)
        self.edge = edge
    }

    var size: CGSize {
        let cells = CGFloat(cellCount) * Metrics.cellHeight + CGFloat(max(0, cellCount - 1)) * Metrics.cellGap
        return CGSize(width: Metrics.panelWidth, height: Metrics.paddingTop + cells + Metrics.gearRowHeight + Metrics.paddingBottom)
    }

    /// Ring centers, top to bottom. The three terms are hoisted out of the closure because a
    /// single `CGFloat` expression mixing them all is a type-checker cliff.
    var cellCenters: [CGPoint] {
        let x: CGFloat = Metrics.panelWidth / 2
        let firstY: CGFloat = Metrics.paddingTop + Metrics.ringDiameter / 2
        let pitch: CGFloat = Metrics.cellHeight + Metrics.cellGap
        return (0..<cellCount).map { CGPoint(x: x, y: firstY + CGFloat($0) * pitch) }
    }

    /// Ring + label rectangle for each cell (the hover/click target).
    var cellFrames: [CGRect] {
        cellCenters.map { c in
            CGRect(x: c.x - Metrics.ringDiameter / 2, y: c.y - Metrics.ringDiameter / 2,
                   width: Metrics.ringDiameter, height: Metrics.cellHeight)
        }
    }

    var gearCenter: CGPoint {
        CGPoint(x: size.width / 2, y: size.height - Metrics.paddingBottom - Metrics.gearRowHeight / 2)
    }

    var gearFrame: CGRect {
        CGRect(x: gearCenter.x - Metrics.gearRowHeight / 2, y: gearCenter.y - Metrics.gearRowHeight / 2,
               width: Metrics.gearRowHeight, height: Metrics.gearRowHeight)
    }

    func cellIndex(at point: CGPoint) -> Int? {
        cellFrames.firstIndex { $0.contains(point) }
    }

    /// The concave flares are drawn outside the panel body; the window is taller by this much
    /// on each side. The Glass style draws no flares but keeps the same margin, which is where
    /// its drop shadow spills.
    static let flareInset: CGFloat = Metrics.flareRadius

    /// Window size in points, including the flare margins.
    var windowSize: CGSize {
        CGSize(width: size.width, height: size.height + 2 * Self.flareInset)
    }

    /// Where the panel body sits inside the window (top-left origin).
    var contentOrigin: CGPoint {
        CGPoint(x: 0, y: Self.flareInset)
    }
}
