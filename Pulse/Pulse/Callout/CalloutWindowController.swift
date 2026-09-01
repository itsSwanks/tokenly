import AppKit
import SwiftUI
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
    /// Bumped by every `hide()` so an older dissolve's pending order-out can tell that a newer
    /// one has taken over and bow out.
    private var hideToken = 0

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
        // The window never fades any more — the glass materializes inside it (spec §18.4), so the
        // panel is ordered in at full opacity and stays there for as long as it is on screen.
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        isVisible = true
        // Same post-sleep re-check as the dock (`FloatingPanel.ensureOnScreen`): a swallowed
        // order-front would otherwise leave every hover calling out into nothing until relaunch.
        // A beat later, because the server's on-screen list only updates a turn after the order.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.isVisible else { return }
            self.panel.ensureOnScreen()
        }
        // Set after the panel is on screen, and inside a `withAnimation`: this assignment is what
        // *inserts* the glass in `CalloutView`, and `.glassEffectTransition` plays only for an
        // insertion carried by an animation transaction.
        withAnimation(Motion.reduced(Motion.materialize, reduceMotion: reduceMotion)) {
            model.isPresented = true
        }
    }

    /// Slide to another ring. The bubble stays inserted — no second materialize — so this reads
    /// as one callout gliding down the dock while its content swaps, not as a re-entry.
    func move(provider: ProviderID, ringCenterY: CGFloat, dockFrame: CGRect, screen: NSScreen) {
        configure(provider: provider)
        place(ringCenterY: ringCenterY, dockFrame: dockFrame, screen: screen, animated: true)
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        refitPending = false
        let reduceMotion = self.reduceMotion
        withAnimation(Motion.reduced(Motion.materialize, reduceMotion: reduceMotion)) {
            model.isPresented = false
        }
        // Order out only once the dissolve has played — pulling the window out from under it
        // would cut the transition off on frame one. A `show()` can race ahead of this, so the
        // work re-checks `isVisible`; the token covers the other race, a hide → show → hide
        // inside 0.4 s, where `isVisible` is false again and the *first* timer would otherwise
        // pop the bubble in the middle of the second dissolve. No strong `panel` capture is
        // needed the way `SettingsWindowController` needs one: this controller is a `let` on
        // `AppController` and outlives every dissolve.
        hideToken += 1
        let token = hideToken
        let dissolve = reduceMotion ? Motion.reducedSeconds : Motion.materializeSeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + dissolve) { [weak self] in
            guard let self, !self.isVisible, token == self.hideToken else { return }
            self.panel.orderOut(nil)
        }
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

    /// Reduce Motion read on the AppKit side: `show`/`hide` drive the SwiftUI flip from here, so
    /// there is no `@Environment` to read it from.
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func configure(provider: ProviderID) {
        model.provider = provider
        model.edge = prefs.edge
        model.status = store.statuses[provider] ?? .loading
        model.now = Date()
        container.edge = prefs.edge     // which side of the window the bubble is inset against
    }

    private func place(ringCenterY: CGFloat, dockFrame: CGRect, screen: NSScreen, animated: Bool) {
        hosting.layoutSubtreeIfNeeded()
        // The floor matches the shortest card (loading): any taller and the window would
        // outgrow the card, leaving the tail — offset from the card's own height — misaligned.
        let size = CGSize(width: Metrics.calloutWidth + Metrics.tailLength, height: max(80, hosting.fittingSize.height))
        let (frame, tailY) = CalloutPositioner.place(calloutSize: size, dockFrame: dockFrame, ringCenterY: ringCenterY, edge: prefs.edge, in: screen.visibleFrame)
        // Animated because the tail does not always move with the window: near the top or bottom
        // of the screen the frame is clamped and the tail slides *inside* the card to keep
        // pointing at the ring. Assigned bare, that slide would snap while the window glides.
        //
        // Guarded because `place` is on the 1 Hz render path: writing the same value back would
        // still start a settle spring every second for as long as the callout stays open.
        if model.tailY != tailY {
            withAnimation(Motion.reduced(Motion.settle, reduceMotion: reduceMotion)) {
                model.tailY = tailY
            }
        }
        lastPlacement = (ringCenterY, dockFrame, screen)
        guard frame != panel.frame else { return }      // the per-second re-fit is usually a no-op
        if animated {
            followsInFlight += 1
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Motion.calloutFollow
                // Overshoots and settles, so the follow lands like the springs everything else
                // moves on (spec §18.4); `windowCurve` flattens it under Reduce Motion.
                ctx.timingFunction = Motion.windowCurve
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
