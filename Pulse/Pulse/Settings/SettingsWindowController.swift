import AppKit
import SwiftUI
import PulseCore

@MainActor
final class SettingsWindowController {
    let panel = SettingsPanel()
    let model = SettingsModel()
    private(set) var isOpen = false
    var onClose: () -> Void = {}
    private var clickAway: Any?
    /// Bumped by every `close()`. The delayed order-out captures the value it was scheduled with
    /// and only fires if it is still the current one, so a timer left over from an earlier close
    /// can never pull the window out from under a newer open/close cycle.
    private var closeToken = 0

    init(prefs: Preferences, store: UsageStore, actions: SettingsActions, updatesAvailable: Bool) {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "dev"
        model.loginItemNeedsApproval = LoginItem.current == .needsApproval
        let view = SettingsView(prefs: prefs, store: store, model: model, actions: actions,
                                updatesAvailable: updatesAvailable,
                                version: version, repositoryURL: Self.repositoryURL(from: info))
        // `MarginHostingView`, not the plain first-mouse one: `SettingsView` pads itself by
        // `CalloutPositioner.shadowMargin` so `SettingsPanel.hasShadow` has somewhere to draw,
        // and clicks in that transparent band must reach whatever is behind the window.
        let hosting = MarginHostingView(rootView: view)
        hosting.margin = CalloutPositioner.shadowMargin
        panel.contentView = hosting
        panel.onEscape = { [weak self] in self?.close() }
    }

    /// Show or clear the login-item approval hint. It appears while the panel is already on
    /// screen, and the panel is sized to its content, so the window has to grow by that one
    /// line or the hint (and the bottom of the panel with it) would be clipped.
    func setLoginItemNeedsApproval(_ value: Bool) {
        guard model.loginItemNeedsApproval != value else { return }
        model.loginItemNeedsApproval = value
        refit()
        // SwiftUI may not have re-laid the hosting view out by the time the mutation returns;
        // one more pass on the next turn of the run loop catches it either way, and `refit` is
        // a no-op once the height already matches.
        Task { @MainActor [weak self] in self?.refit() }
    }

    /// Re-height the panel to its content, keeping it centered where it was — then clamped back
    /// into the screen's visible frame with the same helper `open()` reaches through
    /// `CalloutPositioner.place`, so a panel already sitting near the bottom edge grows upward
    /// instead of past it.
    private func refit() {
        guard isOpen, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let margin = CalloutPositioner.shadowMargin
        // The padded height: `fittingSize` includes the transparent shadow band `SettingsView`
        // wraps itself in, and the window is exactly that size.
        let height = content.fittingSize.height
        var frame = panel.frame
        guard height != frame.height else { return }
        frame.origin.y -= (height - frame.height) / 2
        frame.size.height = height
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            // The *sheet* is what gets clamped, exactly as in `open()`: the band is empty, so it
            // is allowed to hang past the screen, and clamping the padded frame instead would
            // hold the sheet a whole margin in from the bottom of the screen.
            frame.origin.y = DockPositioner.clampedY(frame.origin.y + margin, height: height - 2 * margin, in: visible) - margin
        }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    /// The public repository, read from `Info.plist` rather than hard-coded, so the link is
    /// simply absent until whoever publishes a build fills `PulseRepositoryURL` in. Anything
    /// that isn't a non-empty `https` URL is treated as "not set".
    static func repositoryURL(from info: [String: Any]?) -> URL? {
        guard let raw = (info?["PulseRepositoryURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    isolated deinit {
        // Explicit `isolated deinit` (SE-0371) puts teardown on the main actor so it can touch
        // `clickAway` directly. Belt-and-braces: if this window controller is torn down while the
        // panel is still open, the global monitor must not outlive it.
        if let clickAway { NSEvent.removeMonitor(clickAway) }
    }

    /// Reduce Motion read on the AppKit side: `open`/`close` drive the SwiftUI flip from here, so
    /// there is no `@Environment` to read it from. Same as `CalloutWindowController`.
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Opens beside the dock on its inward side, vertically centered on the dock.
    func open(besideDock dockFrame: CGRect, edge: ScreenEdge, screen: NSScreen) {
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let margin = CalloutPositioner.shadowMargin
        // `fittingSize` already carries the transparent band `SettingsView` pads itself with, so
        // the sheet is that minus the band above and below. Place the *sheet* — `margin: 0`, the
        // same bubble-sized placement the panel has always used, so the gap beside the dock is
        // unchanged and the sheet (not the empty band) is what gets clamped into the screen —
        // then grow the window back over the band on all four sides. `place`'s own `margin:` is
        // no help here: it adds the band on the away-from-the-dock side only, because the
        // callout's tail side sits flush against the dock, and this sheet is padded symmetrically.
        let sheet = CGSize(width: Metrics.settingsWidth, height: content.fittingSize.height - 2 * margin)
        let (sheetFrame, _) = CalloutPositioner.place(calloutSize: sheet, dockFrame: dockFrame, ringCenterY: dockFrame.midY,
                                                      edge: edge, in: screen.visibleFrame, margin: 0)
        panel.setFrame(sheetFrame.insetBy(dx: -margin, dy: -margin), display: true)
        // A borderless panel does not retrace its shadow for a new frame on its own.
        panel.invalidateShadow()
        // Pulse is an .accessory app with no main menu: never activate for the settings panel — doing
        // so would steal focus and hand the menu bar to an empty menu (spec §4.1). The panel can still
        // become key (SettingsPanel.canBecomeKey), so Esc and control interaction work without it.
        panel.makeKeyAndOrderFront(nil)
        isOpen = true
        // Set after the panel is on screen, and inside a `withAnimation`: this assignment is what
        // *inserts* the glass in `SettingsView`, and `.glassEffectTransition` plays only for an
        // insertion carried by an animation transaction (spec §18.4).
        withAnimation(Motion.reduced(Motion.materialize, reduceMotion: reduceMotion)) {
            model.isPresented = true
        }
        clickAway = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // A first-mouse (or synthesised) down over the panel can reach the global monitor
                // even though the panel receives it too — the window server treats a down on a
                // not-yet-key window of an inactive app as dispatched to "another application".
                // A click on the sheet is never "away", so it must not close the panel; the
                // transparent shadow band around it still counts as away, exactly like the
                // desktop it lets clicks fall through to.
                let sheet = self.panel.frame.insetBy(dx: CalloutPositioner.shadowMargin,
                                                     dy: CalloutPositioner.shadowMargin)
                guard !sheet.contains(NSEvent.mouseLocation) else { return }
                self.close()
            }
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        if let clickAway { NSEvent.removeMonitor(clickAway) }
        clickAway = nil
        let reduceMotion = self.reduceMotion
        withAnimation(Motion.reduced(Motion.materialize, reduceMotion: reduceMotion)) {
            model.isPresented = false
        }
        // Order out only once the dissolve has played — pulling the window out from under it
        // would cut the transition off on frame one. The token makes the wait safe to interleave:
        // a close → open → close inside 0.4 s leaves the first timer pending, and without it that
        // stale timer would order the window out in the middle of the *second* dissolve.
        closeToken += 1
        let token = closeToken
        let dissolve = reduceMotion ? Motion.reducedSeconds : Motion.materializeSeconds
        // `panel` is captured strongly on purpose: `AppController` builds a fresh controller per
        // open, so a gear → close → gear inside the dissolve can release *this* controller before
        // the timer fires — and a deallocated owner must still take its floating, all-Spaces
        // window off screen rather than strand it with no monitor and no way to close it.
        DispatchQueue.main.asyncAfter(deadline: .now() + dissolve) { [panel, weak self] in
            guard let self else { panel.orderOut(nil); return }
            guard !self.isOpen, token == self.closeToken else { return }
            self.panel.orderOut(nil)
        }
        onClose()
    }
}
