import AppKit
import SwiftUI

/// The handle's frosted strip. Same reasoning as `CalloutContainerView`: SwiftUI's materials
/// blur what is *inside* the window, and this window is transparent, so only an
/// `NSVisualEffectView` with `.behindWindow` blending picks up the desktop. Here the effect
/// view *is* the content view — the handle has no tail or margin to keep clear of — and hosts
/// the dots on top.
///
/// The corner radius is applied by a `CAShapeLayer` mask rather than `layer.cornerRadius`,
/// because only the two inward corners are rounded; the screen-edge side stays square.
@MainActor
final class HandleContainerView: NSVisualEffectView {
    var edge: ScreenEdge = .right { didSet { needsLayout = true } }

    private let border = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Pinned to dark like the callout: the handle is always the dark glass material,
        // whatever the Mac's system appearance is set to.
        appearance = NSAppearance(named: .darkAqua)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.masksToBounds = true
        // The border follows the same one-sided rounded path as the mask, so a layer-level
        // `borderWidth` (which would trace the full rectangle) is not usable here.
        border.fillColor = nil
        border.lineWidth = 1
        border.strokeColor = NSColor(Palette.handleBorder).cgColor
        layer?.addSublayer(border)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        // The path is vertically symmetric, so it is identical whether the layer's geometry is
        // flipped or not — no coordinate conversion is needed for either edge.
        let side: EdgeSlabPath.Side = edge == .right ? .left : .right
        let outline = EdgeSlabPath.path(in: bounds, radius: Metrics.handleRadius, roundedSide: side).cgPath
        // Shape-layer paths and frames are implicitly animated; without this a provider being
        // enabled would morph the mask over a quarter-second while the window itself resizes
        // instantly, so the glass would tear away from its own edge.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let mask = layer?.mask as? CAShapeLayer ?? CAShapeLayer()
        mask.path = outline
        layer?.mask = mask
        // Inset by half the line width so the 1 pt stroke lands inside the mask instead of
        // being clipped to 0.5 pt.
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        border.path = EdgeSlabPath.path(in: inset, radius: Metrics.handleRadius - 0.5, roundedSide: side).cgPath
        border.frame = bounds
        CATransaction.commit()
    }
}

/// The handle's window. Starts fully transparent so it can crossfade against the dock's slide.
@MainActor
final class HandlePanel: FloatingPanel {
    init() {
        // The empty-handle geometry, not a guess: `render()` resizes to the real dot count
        // before the window is ever shown.
        super.init(contentRect: NSRect(origin: .zero, size: HandleLayout(dotCount: 0).size))
        alphaValue = 0
    }
}
