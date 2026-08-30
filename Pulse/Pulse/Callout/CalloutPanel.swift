import AppKit
import SwiftUI

/// Hosting view that takes clicks without the window being key (the Retry pill).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Container that reports enter/leave for the hover grace logic and carries the callout's
/// frosted glass behind the SwiftUI content.
///
/// The vibrancy has to be an AppKit view: SwiftUI's own materials blur what is *inside* the
/// window, and the callout's window is transparent, so only `NSVisualEffectView` with
/// `.behindWindow` blending picks up the desktop. It is a sibling *behind* the hosting view
/// rather than its superview because it is rectangular — the tail must stay outside it, or
/// the glass would draw a square block around the triangle.
///
/// The window is larger than the bubble by `CalloutPositioner.shadowMargin` on three sides so
/// the window shadow has room; everything here — glass, content, tracking, hit-testing — is
/// confined to `bubbleRect`, so that band stays empty and click-through.
@MainActor
final class CalloutContainerView: NSView {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    var edge: ScreenEdge = .right { didSet { needsLayout = true } }
    /// The SwiftUI bubble. Framed by `layout()` rather than an autoresizing mask, since it has
    /// to sit inside the shadow margin instead of filling the window.
    var content: NSView? {
        didSet {
            guard content !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let content { addSubview(content) }
            needsLayout = true
        }
    }
    private let glass = NSVisualEffectView()
    private var trackingArea: NSTrackingArea?

    /// The bubble's rect in this view's coordinates.
    private var bubbleRect: CGRect { CalloutPositioner.bubbleRect(inWindowOfSize: bounds.size, edge: edge) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Pinned to dark: the callout is always the v2 dark glass material, regardless of the
        // Mac's system appearance — a Light Mode host would otherwise turn the vibrancy pale.
        appearance = NSAppearance(named: .darkAqua)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.wantsLayer = true
        glass.layer?.cornerRadius = Metrics.calloutRadius
        glass.layer?.masksToBounds = true
        // Border is painted once, by CalloutView's SwiftUI `strokeBorder` above the tint;
        // a second layer-level border here would double the alpha (~.175 instead of .14).
        glass.layer?.borderWidth = 0
        glass.autoresizingMask = []
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let bubble = bubbleRect
        content?.frame = bubble
        // Cover the card only; the tail column sits on whichever side the tail points.
        let inset = Metrics.tailLength
        glass.frame = NSRect(x: bubble.minX + (edge == .left ? inset : 0), y: bubble.minY,
                             width: max(0, bubble.width - inset), height: bubble.height)
        // The tracking rect is a fixed rectangle now rather than `.inVisibleRect`, so it has to
        // be rebuilt whenever the bubble moves inside the window — every resize, every edge flip.
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // Bounded by the bubble, not `.inVisibleRect`: entering the transparent shadow margin
        // is not entering the callout, and treating it as such would hold the hover grace open
        // 40 pt away from the card.
        let area = NSTrackingArea(rect: bubbleRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    /// Clicks in the shadow margin belong to whatever is behind the window, not to the callout.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bubbleRect.contains(convert(point, from: superview)) ? super.hitTest(point) : nil
    }

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}

/// The callout's window. All shared panel configuration lives in `FloatingPanel`;
/// it starts fully transparent so `show()` can fade it in.
@MainActor
final class CalloutPanel: FloatingPanel {
    init() {
        // Bubble plus the transparent shadow margin `CalloutPositioner.place` will keep adding;
        // only a placeholder until the first `place()`, but it keeps the first layout honest.
        super.init(contentRect: NSRect(x: 0, y: 0,
                                       width: Metrics.calloutWidth + Metrics.tailLength + CalloutPositioner.shadowMargin,
                                       height: 200 + 2 * CalloutPositioner.shadowMargin))
        alphaValue = 0
        // SwiftUI's `.shadow` can't render outside a content-sized window (there's no
        // margin for it to spill into), so the card's shadow comes from AppKit instead — over
        // `CalloutPositioner.shadowMargin`, which is the margin it spills into.
        // `invalidateShadow()` must be called after every place()/resize so it retraces
        // the new frame — NSWindow doesn't do that on its own for a borderless panel.
        hasShadow = true
    }
}
