import AppKit
import PulseCore

/// Owns the dock panel: builds the layout from preferences + store, sizes and
/// positions the window, and forwards interaction callbacks to whoever wires them.
@MainActor
final class DockWindowController {
    let panel: DockPanel
    let model = DockModel()
    let interaction: DockInteractionView
    /// The auto-hide resting UI. Owned here rather than by `AppController` so it can be kept
    /// in step with the dock's own cells, edge and vertical position from one place.
    let handle = HandleWindowController()
    private let store: UsageStore
    private let prefs: Preferences
    private(set) var collapsed = false
    /// True only while auto-hide is on; otherwise the handle never shows, whatever the dock does.
    private var handleEnabled = false

    init(store: UsageStore, prefs: Preferences) {
        self.store = store
        self.prefs = prefs
        let layout = DockLayout(cellCount: prefs.enabledOrdered.count, edge: prefs.edge, metrics: DockMetrics(size: prefs.dockSize))
        model.layout = layout
        interaction = DockInteractionView(model: model, layout: layout)
        panel = DockPanel(contentRect: NSRect(origin: .zero, size: layout.windowSize))
        panel.contentView = interaction
        // Purely visual, and nothing outside the dock cares, so it is wired here rather than
        // routed through `AppController` like the click and hover callbacks.
        // Guarded like every other model assignment: `mouseDragged` can report the same index
        // repeatedly, and an unchanged write would still invalidate the observable and rerender
        // the dock on every drag event.
        interaction.onPressCell = { [weak model] in if model?.pressedIndex != $0 { model?.pressedIndex = $0 } }
        applyStyle(prefs.dockStyle)
    }

    /// Push a dock style through the two places that care. The drop shadow is the *window's*
    /// (`DockPanel.hasShadow`, like the callout's) rather than a SwiftUI `.shadow`, so it can
    /// fall outside the hosting view's bounds and behind the glass instead of on top of the
    /// desktop — and it is on for both silhouettes now that both are glass.
    private func applyStyle(_ style: DockStyle) {
        if model.style != style { model.style = style }
        interaction.style = style
        panel.invalidateShadow()
    }

    /// The screen the dock lives on: the remembered one if still attached, else the one under
    /// the mouse, else main. `nil` when the machine reports no screens at all (every display
    /// asleep or disconnected) — a state every caller below simply sits out, rather than
    /// trapping on `NSScreen.screens[0]`.
    var screen: NSScreen? {
        if let name = prefs.dockScreenName, let s = NSScreen.screens.first(where: { $0.localizedName == name }) { return s }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Idempotent: render, reposition, order in. Safe to call again on a screen-parameter
    /// change, which is also how a dock that could not be shown at launch — no displays
    /// attached — appears once one is connected.
    ///
    /// `screen` is resolved once here and threaded down, rather than re-read by each callee:
    /// it consults `NSEvent.mouseLocation`, so three separate reads can legitimately disagree
    /// if the cursor crosses a display boundary mid-call and leave the dock rendered for one
    /// screen and positioned on another.
    ///
    /// The order-in is skipped while `collapsed`: a slide-parked dock has been deliberately
    /// ordered out, and ordering it back in at its hidden frame would put it on a neighbouring
    /// display's desktop at full alpha the moment one is attached on that edge — visible there
    /// until the cursor next reached the edge band. `setCollapsed(false, …)` is what brings a
    /// parked dock back. The launch-with-no-display case is unaffected: `collapsed` is false
    /// there, so the first connected screen still gets the dock ordered in.
    func show() {
        guard let screen else { return }
        render(on: screen)
        reposition(on: screen, animated: false)
        if !collapsed {
            panel.orderFrontRegardless()
            ensureExpandedOnScreen()
        }
    }

    /// Rebuild cells + layout from current preferences and statuses.
    func render() {
        guard let screen else { return }
        render(on: screen)
    }

    private func render(on screen: NSScreen) {
        let order = prefs.enabledOrdered
        // `DockCell` is `Equatable`; skipping the identical assignment keeps the per-second
        // render from invalidating every SwiftUI view that observes `cells`.
        let cells = order.map { DockCell(id: $0, state: RingState(status: store.statuses[$0] ?? .loading)) }
        if cells != model.cells { model.cells = cells }
        if model.style != prefs.dockStyle { applyStyle(prefs.dockStyle) }
        let layout = DockLayout(cellCount: order.count, edge: prefs.edge, metrics: DockMetrics(size: prefs.dockSize))
        if layout != model.layout {
            // A size change is the one layout change worth animating: the window glides to its
            // new frame while `DockView` settles its geometry on the same clock (spec §18.4).
            // Adding or removing a provider still snaps, as it always has.
            let animated = layout.metrics != model.layout.metrics
            model.layout = layout
            interaction.layout = layout
            // Resizes the window, so the shadow has to be retraced — `reposition` does that.
            reposition(on: screen, animated: animated)
        }
        handle.render(dots: cells.map { HandleDot(id: $0.id, state: $0.state) },
                      edge: prefs.edge, yFraction: prefs.dockYFraction, in: screen.visibleFrame)
    }

    /// Slide the dock fully off-screen (and reveal the handle), or bring it back.
    ///
    /// The window keeps one size throughout — the hidden state is the same panel translated
    /// past the screen edge — so the move is a pure slide with nothing left peeking. Unless a
    /// second display abuts that edge, in which case "off-screen" is another screen's desktop
    /// and the dock fades out where it stands instead.
    func setCollapsed(_ value: Bool, animated: Bool) {
        guard let screen else { return }
        guard value != collapsed else { return }
        collapsed = value
        let resting = restingFrame(in: screen)
        let hidden = hiddenFrame(for: resting, on: screen)
        let fadesInPlace = neighbourAbuts(resting, on: screen)
        // An expand may have raced ahead of the completion; only order out if the dock is
        // still meant to be hidden, or the move back in would end on an invisible window.
        let orderOutIfStillHidden: @MainActor () -> Void = { [weak self] in
            guard let self, self.collapsed else { return }
            self.panel.orderOut(nil)
        }
        if value {
            if fadesInPlace {
                fade(to: 0, animated: animated, completion: orderOutIfStillHidden)
            } else {
                slide(to: hidden, animated: animated, completion: orderOutIfStillHidden)
            }
            if handleEnabled { handle.setVisible(true, animated: animated) }
        } else {
            handle.setVisible(false, animated: animated)
            if fadesInPlace {
                panel.setFrame(resting, display: false)
                panel.invalidateShadow()
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                fade(to: 1, animated: animated) { [weak self] in self?.ensureExpandedOnScreen() }
            } else {
                // A previous fade-collapse (a display since unplugged) could have left the
                // panel transparent; the slide has to arrive visible.
                panel.alphaValue = 1
                if animated { panel.setFrame(hidden, display: false) }
                panel.orderFrontRegardless()
                slide(to: resting, animated: animated) { [weak self] in
                    self?.panel.invalidateShadow()
                    self?.ensureExpandedOnScreen()
                }
            }
        }
    }

    /// The expand's own order-front can be silently swallowed: after a sleep/wake or display
    /// reattach the WindowServer may have dropped the panel from its on-screen list while AppKit
    /// still counts it visible (see `FloatingPanel.ensureOnScreen`). The dock then slides out
    /// into nothing — and the handle is gone too, because expanding hid it — until relaunch.
    /// Re-check once the expand has settled, a beat after the order, which is the earliest the
    /// server's list can be trusted; skipped when a collapse won the race meanwhile.
    private func ensureExpandedOnScreen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, !self.collapsed else { return }
            self.panel.ensureOnScreen()
        }
    }

    /// True when another display butts against the dock's edge of `screen`, tested with a 1 pt
    /// strip just beyond it at the dock's own height: there the parked frame would sit in plain
    /// view on the neighbour rather than behind a bezel.
    private func neighbourAbuts(_ resting: CGRect, on screen: NSScreen) -> Bool {
        let strip = prefs.edge == .right
            ? CGRect(x: screen.frame.maxX, y: resting.minY, width: 1, height: resting.height)
            : CGRect(x: screen.frame.minX - 1, y: resting.minY, width: 1, height: resting.height)
        return NSScreen.screens.contains { $0 != screen && $0.frame.intersects(strip) }
    }

    /// Auto-hide on/off. Off means the handle is never shown, whatever the dock is doing.
    func setHandleEnabled(_ value: Bool) {
        handleEnabled = value
        guard value else { return handle.setVisible(false, animated: false) }
        render()
        handle.setVisible(collapsed, animated: false)
    }

    /// Place the window flush to the chosen edge at the remembered height, clamped to the
    /// visible frame — or, while collapsed, at its off-screen resting place.
    func reposition(animated: Bool) {
        guard let screen else { return }
        reposition(on: screen, animated: animated)
    }

    private func reposition(on screen: NSScreen, animated: Bool) {
        let resting = restingFrame(in: screen)
        slide(to: collapsed ? hiddenFrame(for: resting, on: screen) : resting, animated: animated) { [weak self] in
            self?.panel.invalidateShadow()
        }
    }

    private func restingFrame(in screen: NSScreen) -> CGRect {
        DockPositioner.frame(windowSize: model.layout.windowSize, edge: prefs.edge, yFraction: prefs.dockYFraction, in: screen.visibleFrame)
    }

    /// Fully past the physical display, not merely past `visibleFrame`: on a screen whose macOS
    /// Dock sits on the same edge, `visibleFrame` stops short of the bezel and a panel parked
    /// there would still be visible on top of the Dock. (`frame` always contains `visibleFrame`,
    /// so it is the outer bound on its own.)
    private func hiddenFrame(for resting: CGRect, on screen: NSScreen) -> CGRect {
        var frame = resting
        frame.origin.x = prefs.edge == .right ? screen.frame.maxX : screen.frame.minX - resting.width
        return frame
    }

    private func slide(to frame: CGRect, animated: Bool, completion: (@MainActor () -> Void)?) {
        guard animated else {
            panel.setFrame(frame, display: true)
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Motion.dockSlide
            // Overshoot-and-settle, so an AppKit window move reads like the SwiftUI springs
            // inside it — and a plain ease-out when Reduce Motion is on (spec §18.4).
            ctx.timingFunction = Motion.windowCurve
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: {
            // AppKit invokes animation completions on the main thread.
            MainActor.assumeIsolated { completion?() }
        })
    }

    /// The park move used when a neighbouring display makes a slide pointless: same duration
    /// and curve, no translation.
    private func fade(to alpha: CGFloat, animated: Bool, completion: (@MainActor () -> Void)?) {
        guard animated else {
            panel.alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Motion.dockSlide
            ctx.timingFunction = Motion.timingFunction
            panel.animator().alphaValue = alpha
        }, completionHandler: {
            // AppKit invokes animation completions on the main thread.
            MainActor.assumeIsolated { completion?() }
        })
    }

    /// Vertical drag: move by `dy` screen points, clamped, and remember the fraction.
    func drag(by dy: CGFloat) {
        guard let screen else { return }
        var frame = panel.frame
        frame.origin.y = DockPositioner.clampedY(frame.origin.y + dy, height: frame.height, in: screen.visibleFrame)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    func dragEnded() {
        guard let screen else { return }
        prefs.dockYFraction = DockPositioner.yFraction(of: panel.frame, in: screen.visibleFrame)
        prefs.dockScreenName = screen.localizedName
    }
}

extension Preferences {
    /// Display order restricted to enabled providers.
    var enabledOrdered: [ProviderID] { providerOrder.filter { enabledProviders.contains($0) } }
}
