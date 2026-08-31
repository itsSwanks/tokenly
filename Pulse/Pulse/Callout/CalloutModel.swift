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
    /// Inserts and removes the glass bubble (spec §18.4 "callout appears"). Flipped on once the
    /// panel is on screen, off on hide — inside a `withAnimation`, which is what plays the
    /// materialize transition.
    var isPresented = false
}
