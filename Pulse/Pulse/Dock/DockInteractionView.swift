import AppKit
import SwiftUI

/// The panel's content view. Owns every mouse interaction so the dock works while
/// the app is never active; hosts `DockView` purely for drawing. Flipped so its
/// coordinates match `DockLayout` (top-left origin).
///
/// In the Glass style it also carries an `NSVisualEffectView` *behind* the hosting view, for
/// the same reason the callout does: SwiftUI's materials blur what is inside the window, and
/// this window is transparent, so only the AppKit view samples the desktop. It is masked to
/// the `DockShape` path, and hidden entirely in the Notch style, whose panel is opaque.
@MainActor
final class DockInteractionView: NSView {
    var layout: DockLayout { didSet { hosting.frame = bounds; updateGlass() } }
    var style: DockStyle = .notch { didSet { guard style != oldValue else { return }; updateGlass() } }
    var onHoverCell: (Int?) -> Void = { _ in }
    var onHoverGear: (Bool) -> Void = { _ in }
    var onExit: () -> Void = {}
    var onClickCell: (Int) -> Void = { _ in }
    var onClickGear: () -> Void = {}
    var onRightClick: (NSPoint) -> Void = { _ in }
    var onDrag: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    private let hosting: NSHostingView<DockView>
    private let glass = NSVisualEffectView()
    private var trackingArea: NSTrackingArea?
    private var mouseDownScreenPoint: NSPoint?
    private var dragging = false
    private var lastHoverCell: Int?
    private var lastHoverGear = false

    init(model: DockModel, layout: DockLayout) {
        self.layout = layout
        hosting = NSHostingView(rootView: DockView(model: model))
        super.init(frame: NSRect(origin: .zero, size: layout.windowSize))
        wantsLayer = true
        // Pinned to dark like the callout: the Glass dock is the dark material whatever the
        // Mac's system appearance is set to.
        appearance = NSAppearance(named: .darkAqua)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.wantsLayer = true
        // Border and tint are painted once, by `DockView` above; a layer-level border here
        // would double the alpha.
        glass.layer?.borderWidth = 0
        glass.autoresizingMask = []
        glass.isHidden = true
        addSubview(glass)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        updateGlass()
    }

    /// The window is always exactly `layout.windowSize`, so every resize arrives here.
    /// (`layout()` — NSView's own hook — cannot be overridden while a stored property of the
    /// same name exists, and renaming that property would churn every call site for nothing.)
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateGlass()
    }

    /// Keeps the vibrancy under the panel body only — never under the flare margin, which is
    /// transparent in both styles — and masked to the silhouette the tint draws.
    private func updateGlass() {
        glass.isHidden = style != .glass
        guard style == .glass else { return }
        // Shape-layer paths are implicitly animated; without this the mask would morph over a
        // quarter-second when a provider is toggled, lagging the window's instant resize.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glass.frame = CGRect(origin: layout.contentOrigin, size: layout.size)
        // The glass path is vertically symmetric, so the mask reads identically whether the
        // enclosing flipped view's layer geometry is flipped or not.
        let mask = glass.layer?.mask as? CAShapeLayer ?? CAShapeLayer()
        mask.path = DockShape(edge: layout.edge, style: .glass).path(in: CGRect(origin: .zero, size: layout.size)).cgPath
        glass.layer?.mask = mask
        CATransaction.commit()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    /// Every event lands here, never in the hosted SwiftUI tree — and only where the dock is
    /// actually drawn. The window is `windowSize`, a flare margin taller than the panel body at
    /// each end, and that margin is transparent everywhere the flares don't reach (everywhere at
    /// all, in the Glass style): a click there is a click on the desktop, so hit-testing the
    /// silhouette rather than `bounds` lets it through to whatever is behind.
    ///
    /// Hover is unaffected — `mouseMoved`/`mouseEntered`/`mouseExited` are delivered by this
    /// view's tracking area, which AppKit drives from geometry rather than from `hitTest`.
    override func hitTest(_ point: NSPoint) -> NSView? {
        DockShape.contains(windowPoint: convert(point, from: superview), layout: layout, style: style) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func layoutPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x - layout.contentOrigin.x, y: p.y - layout.contentOrigin.y)
    }

    override func mouseMoved(with event: NSEvent) { updateHover(layoutPoint(event)) }
    override func mouseEntered(with event: NSEvent) { updateHover(layoutPoint(event)) }
    override func mouseExited(with event: NSEvent) {
        lastHoverCell = nil; lastHoverGear = false
        onExit()
    }

    private func updateHover(_ p: CGPoint) {
        let cell = layout.cellIndex(at: p)
        let gear = layout.gearFrame.contains(p)
        if cell != lastHoverCell { lastHoverCell = cell; onHoverCell(cell) }
        if gear != lastHoverGear { lastHoverGear = gear; onHoverGear(gear) }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownScreenPoint = NSEvent.mouseLocation
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownScreenPoint else { return }
        let now = NSEvent.mouseLocation
        if !dragging, abs(now.y - start.y) < Metrics.dragThreshold { return }
        dragging = true
        onDrag(now.y - start.y)
        mouseDownScreenPoint = now
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownScreenPoint = nil; dragging = false }
        if dragging { onDragEnded(); return }
        let p = layoutPoint(event)
        if let index = layout.cellIndex(at: p) { onClickCell(index) }
        else if layout.gearFrame.contains(p) { onClickGear() }
    }

    override func rightMouseDown(with event: NSEvent) { onRightClick(NSEvent.mouseLocation) }
}
