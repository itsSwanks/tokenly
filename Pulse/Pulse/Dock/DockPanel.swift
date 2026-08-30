import AppKit

/// The dock's window. All shared panel configuration lives in `FloatingPanel`.
@MainActor
final class DockPanel: FloatingPanel {
    override init(contentRect: NSRect) {
        super.init(contentRect: contentRect)
    }
}
