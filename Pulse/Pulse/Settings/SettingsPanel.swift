import AppKit

/// Non-activating but key-capable so Esc closes it and pickers respond.
///
/// Every shared trait (borderless + non-activating style, floating level,
/// all-Spaces collection behavior, transparency, no shadow, no auto-hide on deactivate,
/// no close-release, no animation) already lives in `FloatingPanel`; this subclass only
/// adds what differs — it can take the keyboard, and Esc closes it.
@MainActor
final class SettingsPanel: FloatingPanel {
    var onEscape: () -> Void = {}

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Metrics.settingsWidth, height: 520))
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { onEscape() }
}
