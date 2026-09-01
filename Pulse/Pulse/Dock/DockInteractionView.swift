import AppKit
import SwiftUI

/// The panel's content view. Owns every mouse interaction so the dock works while
/// the app is never active; hosts `DockView` purely for drawing. Flipped so its
/// coordinates match `DockLayout` (top-left origin).
///
/// Nothing is drawn here and nothing sits behind the hosting view: the slab is `DockView`'s own
/// `.glassEffect`, which samples the desktop straight through the transparent window. `style`
/// stays because hit-testing still needs the silhouette.
@MainActor
final class DockInteractionView: NSView {
    var layout: DockLayout { didSet { hosting.frame = bounds } }
    var style: DockStyle = .notch
    var onHoverCell: (Int?) -> Void = { _ in }
    var onHoverGear: (Bool) -> Void = { _ in }
    var onExit: () -> Void = {}
    var onClickCell: (Int) -> Void = { _ in }
    var onClickGear: () -> Void = {}
    var onRightClick: (NSPoint) -> Void = { _ in }
    var onDrag: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}
    /// The cell currently held down, or `nil` when nothing is. The hosted SwiftUI tree never
    /// sees an event, so the press dip has to be driven from here through the model.
    var onPressCell: (Int?) -> Void = { _ in }

    private let hosting: NSHostingView<DockView>
    private var trackingArea: NSTrackingArea?
    private var mouseDownScreenPoint: NSPoint?
    private var dragging = false
    private var lastHoverCell: Int?
    private var lastHoverGear = false

    init(model: DockModel, layout: DockLayout) {
        self.layout = layout
        hosting = NSHostingView(rootView: DockView(model: model))
        super.init(frame: NSRect(origin: .zero, size: layout.windowSize))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    /// Every event lands here, never in the hosted SwiftUI tree — and only where the dock is
    /// actually drawn. The window is `windowSize`, a flare margin taller than the panel body at
    /// each end, and that margin is transparent everywhere the flares don't reach (everywhere at
    /// all, in the Pill style): a click there is a click on the desktop, so hit-testing the
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
        onPressCell(layout.cellIndex(at: layoutPoint(event)))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownScreenPoint else { return }
        let now = NSEvent.mouseLocation
        if !dragging, abs(now.y - start.y) < Metrics.dragThreshold { return }
        // The press became a drag: the ring springs back while the dock moves.
        if !dragging { onPressCell(nil) }
        dragging = true
        onDrag(now.y - start.y)
        mouseDownScreenPoint = now
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownScreenPoint = nil; dragging = false }
        onPressCell(nil)
        if dragging { onDragEnded(); return }
        let p = layoutPoint(event)
        if let index = layout.cellIndex(at: p) { onClickCell(index) }
        else if layout.gearFrame.contains(p) { onClickGear() }
    }

    override func rightMouseDown(with event: NSEvent) { onRightClick(NSEvent.mouseLocation) }
}
