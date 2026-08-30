import AppKit
import PulseCore

@MainActor
final class CalloutWindowController {
    let panel = CalloutPanel()
    let model = CalloutModel()
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    var onRetry: (ProviderID) -> Void = { _ in }

    private let store: UsageStore
    private let prefs: Preferences
    private let container = CalloutContainerView()
    private let hosting: FirstMouseHostingView<CalloutView>
    private var lastPlacement: (ringCenterY: CGFloat, dockFrame: CGRect, screen: NSScreen)?
    private(set) var isVisible = false
    /// Follow animations in flight. A counter, not a flag, because a second `move()` can start
    /// before the first group's completion handler runs, and a plain flag would be cleared by
    /// the older animation while the newer one is still gliding.
    private var followsInFlight = 0
    /// A `render()` that arrived mid-follow and still owes the window a re-fit.
    private var refitPending = false

    init(store: UsageStore, prefs: Preferences) {
        self.store = store
        self.prefs = prefs
        hosting = FirstMouseHostingView(rootView: CalloutView(model: model))
        hosting.rootView = CalloutView(model: model, onRetry: { [weak self] in
            guard let self else { return }
            self.onRetry(self.model.provider)
        })
        // Both views start at the panel's content size so the autoresizing mask has a
        // non-degenerate frame to grow from when the window is resized.
        // The container fills the window; the hosting view is inset inside the transparent
        // shadow margin by `CalloutContainerView.layout()`, so it carries no autoresizing mask
        // of its own — a mask would stretch it back over the margin on the next resize.
        container.frame = NSRect(origin: .zero, size: panel.frame.size)
        container.content = hosting
        panel.contentView = container
        container.onEnter = { [weak self] in self?.onEnter() }
        container.onExit = { [weak self] in self?.onExit() }
    }

    /// Show for a provider with the tail at `ringCenterY` (screen coordinates).
    func show(provider: ProviderID, ringCenterY: CGFloat, dockFrame: CGRect, screen: NSScreen) {
        configure(provider: provider)
        place(ringCenterY: ringCenterY, dockFrame: dockFrame, screen: screen, animated: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        isVisible = true
        // Set after the panel is on screen so SwiftUI animates in rather than laying the
        // card out already settled.
        model.isPresented = true
        model.frostKey += 1
        // Same duration as the SwiftUI card's `.opacity(model.isPresented ? ...)` fade
        // (`Motion.calloutFadeIn`), so the window's vibrancy and the card's tint ramp in
        // on one clock instead of the window outrunning the content.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Motion.calloutFadeIn
            ctx.timingFunction = Motion.timingFunction
            panel.animator().alphaValue = 1
        }
    }

    /// Slide to another ring. The frost replays while the window glides, so switching
    /// providers reads as a fresh callout rather than a card whose text swapped mid-flight.
    func move(provider: ProviderID, ringCenterY: CGFloat, dockFrame: CGRect, screen: NSScreen) {
        configure(provider: provider)
        model.frostKey += 1
        place(ringCenterY: ringCenterY, dockFrame: dockFrame, screen: screen, animated: true)
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        refitPending = false
        model.isPresented = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Motion.calloutOut
            ctx.timingFunction = Motion.timingFunction
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // AppKit invokes animation completions on the main thread.
            MainActor.assumeIsolated {
                // A `show()` may have raced ahead of this completion; only order out if
                // the callout is still meant to be hidden.
                guard let self, !self.isVisible else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    /// Called every poll tick so reset countdowns and status stay current.
    func render() {
        model.now = Date()
        model.status = store.statuses[model.provider] ?? .loading
        guard isVisible else { return }
        // A follow animation owns the frame until it lands. Re-fitting mid-glide would snap the
        // window to its destination — and to a height measured while SwiftUI is still swapping
        // the card's content, so the callout could settle at the *previous* provider's height.
        // Remember the re-fit and run it once the animation ends.
        guard followsInFlight == 0 else { refitPending = true; return }
        resizeToFit(animated: false)
    }

    private func configure(provider: ProviderID) {
        model.provider = provider
        model.edge = prefs.edge
        model.status = store.statuses[provider] ?? .loading
        model.now = Date()
        container.edge = prefs.edge     // keeps the glass off the tail column when the edge flips
    }

    private func place(ringCenterY: CGFloat, dockFrame: CGRect, screen: NSScreen, animated: Bool) {
        hosting.layoutSubtreeIfNeeded()
        // The floor matches the shortest card (loading): any taller and the window would
        // outgrow the card, leaving the tail — offset from the card's own height — misaligned.
        let size = CGSize(width: Metrics.calloutWidth + Metrics.tailLength, height: max(80, hosting.fittingSize.height))
        let (frame, tailY) = CalloutPositioner.place(calloutSize: size, dockFrame: dockFrame, ringCenterY: ringCenterY, edge: prefs.edge, in: screen.visibleFrame)
        model.tailY = tailY
        lastPlacement = (ringCenterY, dockFrame, screen)
        guard frame != panel.frame else { return }      // the per-second re-fit is usually a no-op
        if animated {
            followsInFlight += 1
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Motion.calloutFollow
                ctx.timingFunction = Motion.timingFunction
                panel.animator().setFrame(frame, display: true)
            }, completionHandler: { [weak self] in
                // AppKit invokes animation completions on the main thread.
                MainActor.assumeIsolated { self?.followEnded() }
            })
        } else {
            panel.setFrame(frame, display: true)
        }
        panel.invalidateShadow()
    }

    /// One follow animation landed. Once the last of them has, pay back any re-fit `render()`
    /// deferred while they were running, so a card that grew mid-glide settles at its real
    /// height instead of keeping the height it was measured at when the move began.
    private func followEnded() {
        followsInFlight = max(0, followsInFlight - 1)
        guard followsInFlight == 0, refitPending else { return }
        refitPending = false
        guard isVisible else { return }
        resizeToFit(animated: false)
    }

    private func resizeToFit(animated: Bool) {
        guard let last = lastPlacement else { return }
        place(ringCenterY: last.ringCenterY, dockFrame: last.dockFrame, screen: last.screen, animated: animated)
    }
}
