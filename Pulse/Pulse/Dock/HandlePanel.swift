import AppKit

/// The handle's content view: a plain, transparent holder for the SwiftUI hosting view.
///
/// It carries no vibrancy, no appearance pin, no mask and no border any more — `HandleView`
/// draws the strip as one `.glassEffect` in `EdgeSlabShape` (spec §18.2), which samples the
/// desktop through the transparent window and shapes and rims itself. The holder is kept
/// (rather than making the hosting view the content view) so the window's content view stays a
/// stable, resizable box that the hosting view autoresizes inside.
@MainActor
final class HandleContainerView: NSView {
    // Declaring `init?(coder:)` stops `NSView`'s designated initializers from being inherited,
    // so this pass-through is what keeps `HandleContainerView()` available to the controller.
    override init(frame frameRect: NSRect) { super.init(frame: frameRect) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

/// The handle's window. Starts fully transparent so it can crossfade against the dock's slide.
@MainActor
final class HandlePanel: FloatingPanel {
    init() {
        // The empty-handle geometry, not a guess: `render()` resizes to the real dot count
        // before the window is ever shown.
        super.init(contentRect: NSRect(origin: .zero, size: HandleLayout(dotCount: 0).size))
        alphaValue = 0
    }
}
