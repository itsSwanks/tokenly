import AppKit

/// Non-activating but key-capable so Esc closes it and pickers respond.
///
/// Every shared trait (borderless + non-activating style, floating level,
/// all-Spaces collection behavior, transparency, no auto-hide on deactivate,
/// no close-release, no animation) already lives in `FloatingPanel`; this subclass only
/// adds what differs — it can take the keyboard, Esc closes it, and it casts a real drop shadow.
@MainActor
final class SettingsPanel: FloatingPanel {
    var onEscape: () -> Void = {}

    init() {
        // The sheet plus the transparent `CalloutPositioner.shadowMargin` band `SettingsView`
        // pads it with; a placeholder until the first `open()`, but it keeps the first layout
        // (and so the first `fittingSize`) honest.
        super.init(contentRect: NSRect(x: 0, y: 0,
                                       width: Metrics.settingsWidth + 2 * CalloutPositioner.shadowMargin,
                                       height: 520 + 2 * CalloutPositioner.shadowMargin))
        // A SwiftUI `.shadow` cannot render outside a content-sized window, so AppKit draws it
        // instead, into the margin. `invalidateShadow()` must follow every `setFrame` — a
        // borderless panel does not retrace it on its own.
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { onEscape() }
}
