import Foundation
import Observation
import PulseCore

/// Everything `CalloutView` draws. Updated by `CalloutWindowController`.
@MainActor
@Observable
final class CalloutModel {
    var provider: ProviderID = .claude
    var status: ProviderStatus = .loading
    var now = Date()
    var edge: ScreenEdge = .right
    var tailY: CGFloat = 0      // from the bottom, AppKit convention; the view converts
    var height: CGFloat = 0
    /// Drives the card's fade (spec §16 "glass frost"). Flipped on once the panel is on
    /// screen, off on hide.
    var isPresented = false
    /// Bumped on every `show` and every `move`; the card re-frosts and de-blurs each time,
    /// so sliding between rings replays the entry instead of just gliding.
    var frostKey = 0
}
