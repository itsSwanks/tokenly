import CoreGraphics

/// Pure geometry of the auto-hide resting handle, in top-left-origin panel coordinates
/// (spec §17.1). A 9 pt frosted strip flush to the screen edge holding one glow dot per
/// enabled provider, padded 14 pt at each end.
struct HandleLayout: Equatable {
    let dotCount: Int

    init(dotCount: Int) {
        self.dotCount = max(0, dotCount)
    }

    /// Height is padding + dots + the gaps between them. `max(0, n - 1)` rather than a bare
    /// `n - 1`: with no providers enabled the handle is the two paddings and nothing else,
    /// where the literal formula would subtract a gap that isn't there.
    var size: CGSize {
        let dots = CGFloat(dotCount) * Metrics.handleDot + CGFloat(max(0, dotCount - 1)) * Metrics.handleDotGap
        return CGSize(width: Metrics.handleWidth, height: 2 * Metrics.handlePaddingV + dots)
    }

    /// Dot centers, top to bottom. The three terms are hoisted out of the closure because a
    /// single `CGFloat` expression mixing them all is a type-checker cliff.
    var dotCenters: [CGPoint] {
        let x: CGFloat = Metrics.handleWidth / 2
        let firstY: CGFloat = Metrics.handlePaddingV + Metrics.handleDot / 2
        let pitch: CGFloat = Metrics.handleDot + Metrics.handleDotGap
        return (0..<dotCount).map { CGPoint(x: x, y: firstY + CGFloat($0) * pitch) }
    }
}
