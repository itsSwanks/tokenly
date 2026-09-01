import AppKit
import SwiftUI

/// A hosting view whose outer `margin` is click-through: the settings sheet keeps a transparent
/// band around it for the window shadow, and clicks there belong to the desktop.
///
/// The callout does the same job with `CalloutContainerView`, which it needs anyway for its
/// tracking areas and its off-centre (tail-side) bubble rect. The settings sheet has neither —
/// it is centred in its window and wants no hover tracking — so it inherits the first-mouse
/// behaviour and adds only the hit test.
final class MarginHostingView<Content: View>: FirstMouseHostingView<Content> {
    var margin: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.insetBy(dx: margin, dy: margin).contains(convert(point, from: superview)) ? super.hitTest(point) : nil
    }
}
