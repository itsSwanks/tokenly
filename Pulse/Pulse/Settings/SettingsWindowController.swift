import AppKit
import PulseCore

@MainActor
final class SettingsWindowController {
    let panel = SettingsPanel()
    let model = SettingsModel()
    private(set) var isOpen = false
    var onClose: () -> Void = {}
    private var clickAway: Any?

    init(prefs: Preferences, actions: SettingsActions, updatesAvailable: Bool) {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "dev"
        model.loginItemNeedsApproval = LoginItem.current == .needsApproval
        let view = SettingsView(prefs: prefs, model: model, actions: actions, updatesAvailable: updatesAvailable,
                                version: version, repositoryURL: Self.repositoryURL(from: info))
        let hosting = FirstMouseHostingView(rootView: view)
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
        let height = content.fittingSize.height
        var frame = panel.frame
        guard height != frame.height else { return }
        frame.origin.y -= (height - frame.height) / 2
        frame.size.height = height
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.y = DockPositioner.clampedY(frame.origin.y, height: height, in: visible)
        }
        panel.setFrame(frame, display: true)
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

    /// Opens beside the dock on its inward side, vertically centered on the dock.
    func open(besideDock dockFrame: CGRect, edge: ScreenEdge, screen: NSScreen) {
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = CGSize(width: Metrics.settingsWidth, height: content.fittingSize.height)
        // `margin: 0` — the settings panel is content-sized and draws its own SwiftUI shadow;
        // only the callout carries a transparent band for an AppKit window shadow to spill into.
        let (frame, _) = CalloutPositioner.place(calloutSize: size, dockFrame: dockFrame, ringCenterY: dockFrame.midY,
                                                 edge: edge, in: screen.visibleFrame, margin: 0)
        panel.setFrame(frame, display: true)
        // Pulse is an .accessory app with no main menu: never activate for the settings panel — doing
        // so would steal focus and hand the menu bar to an empty menu (spec §4.1). The panel can still
        // become key (SettingsPanel.canBecomeKey), so Esc and control interaction work without it.
        panel.makeKeyAndOrderFront(nil)
        isOpen = true
        clickAway = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.close() }
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        if let clickAway { NSEvent.removeMonitor(clickAway) }
        clickAway = nil
        panel.orderOut(nil)
        onClose()
    }
}
