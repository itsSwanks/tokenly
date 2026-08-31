import AppKit
import SwiftUI

/// Hosting view that takes clicks without the window being key (the Retry pill).
///
/// Not `final`: `MarginHostingView` (the settings sheet) is this plus a click-through shadow
/// margin, and every panel that hosts SwiftUI wants the first-mouse behaviour underneath.
class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Container that reports enter/leave for the hover grace logic and holds the SwiftUI bubble.
///
/// It carries no material of its own any more: the glass is one `.glassEffect` inside
/// `CalloutView`, in the bubble-and-tail shape, so nothing here has to work around the tail
/// sticking out of a rectangular effect view.
///
/// The window is larger than the bubble by `CalloutPositioner.shadowMargin` on three sides so
/// the window shadow has room; everything here — content, tracking, hit-testing — is confined
/// to `bubbleRect`, so that band stays empty and click-through.
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
    private var trackingArea: NSTrackingArea?

    /// The bubble's rect in this view's coordinates.
    private var bubbleRect: CGRect { CalloutPositioner.bubbleRect(inWindowOfSize: bounds.size, edge: edge) }

    /// A pass-through, but not a redundant one: declaring `init?(coder:)` below stops this class
    /// inheriting `NSView`'s designated initializers, and the controller builds it with `init()`.
    override init(frame frameRect: NSRect) { super.init(frame: frameRect) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        content?.frame = bubbleRect
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

/// The callout's window. All shared panel configuration lives in `FloatingPanel`. It is never
/// faded: it is ordered in opaque and the glass inside materializes (spec §18.4).
@MainActor
final class CalloutPanel: FloatingPanel {
    init() {
        // Bubble plus the transparent shadow margin `CalloutPositioner.place` will keep adding;
        // only a placeholder until the first `place()`, but it keeps the first layout honest.
        super.init(contentRect: NSRect(x: 0, y: 0,
                                       width: Metrics.calloutWidth + Metrics.tailLength + CalloutPositioner.shadowMargin,
                                       height: 200 + 2 * CalloutPositioner.shadowMargin))
        // SwiftUI's `.shadow` can't render outside a content-sized window (there's no
        // margin for it to spill into), so the card's shadow comes from AppKit instead — over
        // `CalloutPositioner.shadowMargin`, which is the margin it spills into.
        // `invalidateShadow()` must be called after every place()/resize so it retraces
        // the new frame — NSWindow doesn't do that on its own for a borderless panel.
        hasShadow = true
    }
}
