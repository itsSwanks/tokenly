import AppKit

/// Shared base for every Pulse panel: borderless, non-activating, always-on-top,
/// present on every Space and over full-screen apps. Never becomes key, so it
/// never steals the keyboard. `DockPanel` and later the callout and settings
/// panels subclass this instead of repeating the configuration.
@MainActor
class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// True when the WindowServer itself lists this panel as on screen. `isVisible` is AppKit's
    /// own bookkeeping and the two can disagree: after a sleep/wake or display reattach the
    /// server can drop a panel from its list while AppKit still counts it visible, and every
    /// later order-front is then silently ignored. The server list also updates a run-loop turn
    /// *after* an ordering call, never synchronously — only ask once the order has had a turn
    /// to land. An ordered-in panel counts even at a fully off-screen frame, so a parked,
    /// auto-hidden dock never reads as lost.
    var serverSeesOnScreen: Bool {
        guard windowNumber > 0,
              let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return false }
        return list.contains { ($0[kCGWindowNumber as String] as? Int) == windowNumber }
    }

    /// Recover a panel that should be up but is missing from the server's on-screen list (the
    /// desync above). Cycling out first matters: from AppKit's point of view the panel may
    /// already be visible, which turns a bare order-front into a bookkeeping no-op — ordering
    /// out resets that so the front order is re-issued to the server for real. A panel the
    /// server already shows is left untouched.
    func ensureOnScreen() {
        guard !serverSeesOnScreen else { return }
        orderOut(nil)
        orderFrontRegardless()
    }
}
