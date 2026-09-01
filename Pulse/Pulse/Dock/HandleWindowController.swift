import AppKit
import PulseCore

/// Owns the auto-hide handle window: the glass sliver with one glow dot per enabled provider
/// that rests at the screen edge while the dock is off-screen (spec §17.1).
///
/// It is a second window rather than a mode of the dock's, because the dock now hides by
/// sliding fully off-screen — there is no dock pixel left on screen to draw a resting state in.
@MainActor
final class HandleWindowController {
    let panel = HandlePanel()
    let model = HandleModel()
    private let container = HandleContainerView()
    private let hosting: FirstMouseHostingView<HandleView>
    private(set) var isVisible = false

    init() {
        hosting = FirstMouseHostingView(rootView: HandleView(model: model))
        let initial = NSRect(origin: .zero, size: panel.frame.size)
        container.frame = initial
        hosting.frame = initial
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
    }

    /// Rebuild the dots and resize to fit, then re-place flush to `edge` at `yFraction` —
    /// the dock's own vertical center, so the handle sits where the dock will come back.
    func render(dots: [HandleDot], edge: ScreenEdge, yFraction: Double, in visible: CGRect) {
        if dots != model.dots { model.dots = dots }
        let layout = HandleLayout(dotCount: dots.count)
        if layout != model.layout { model.layout = layout }
        // The glass shape follows the edge now, so the edge belongs to the model — and, like
        // the two above, is only assigned when it actually changed, so a per-second render
        // does not invalidate every observer.
        if model.edge != edge { model.edge = edge }
        let frame = DockPositioner.frame(windowSize: layout.size, edge: edge, yFraction: yFraction, in: visible)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
    }

    /// Crossfade against the dock's slide. `animated == false` snaps, for the initial
    /// auto-hide toggle where there is no dock movement to fade against.
    func setVisible(_ value: Bool, animated: Bool) {
        guard value != isVisible else { return }
        isVisible = value
        if value { panel.orderFrontRegardless() }
        guard animated else {
            panel.alphaValue = value ? 1 : 0
            if !value { panel.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Motion.handleFade
            ctx.timingFunction = Motion.timingFunction
            panel.animator().alphaValue = value ? 1 : 0
        }, completionHandler: { [weak self] in
            // AppKit invokes animation completions on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                // A `setVisible(true)` may have raced ahead of this completion; only order out
                // if the handle is still meant to be hidden. A handle still meant to be shown
                // gets the same post-sleep re-check as the dock (`FloatingPanel.ensureOnScreen`):
                // its order-front, too, can be silently swallowed after a wake.
                if self.isVisible {
                    self.panel.ensureOnScreen()
                } else {
                    self.panel.orderOut(nil)
                }
            }
        })
    }
}
