import AppKit

/// The dock's window. All shared panel configuration lives in `FloatingPanel`.
@MainActor
final class DockPanel: FloatingPanel {
    override init(contentRect: NSRect) {
        super.init(contentRect: contentRect)
        // The dock is glass in both silhouettes now (spec §18.2), and glass needs a shadow to
        // sit off the desktop. SwiftUI's `.shadow` can't render outside a content-sized window,
        // so it comes from AppKit — spilling into the flare margin, which is transparent and
        // click-through. `invalidateShadow()` must follow every frame change: NSWindow does not
        // retrace a borderless panel's shadow on its own.
        hasShadow = true
    }
}
