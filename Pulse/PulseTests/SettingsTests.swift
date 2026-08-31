import Testing
import Foundation
import AppKit
import SwiftUI
import ServiceManagement
import PulseCore
@testable import Pulse

@MainActor
@Suite struct RepositoryURLTests {
    @Test func anAbsentOrEmptyValueIsNoLink() {
        #expect(SettingsWindowController.repositoryURL(from: nil) == nil)
        #expect(SettingsWindowController.repositoryURL(from: [:]) == nil)
        #expect(SettingsWindowController.repositoryURL(from: ["PulseRepositoryURL": ""]) == nil)
        #expect(SettingsWindowController.repositoryURL(from: ["PulseRepositoryURL": "   "]) == nil)
    }

    @Test func plainHTTPIsRejected() {
        // Anything but https is "not set": the About link is the one place Pulse sends a user
        // out to the network, and it is not going to do that in the clear.
        #expect(SettingsWindowController.repositoryURL(from: ["PulseRepositoryURL": "http://example.com/pulse"]) == nil)
        #expect(SettingsWindowController.repositoryURL(from: ["PulseRepositoryURL": "https:///no-host"]) == nil)
    }

    @Test func aValidHTTPSURLIsReturned() {
        let url = SettingsWindowController.repositoryURL(from: ["PulseRepositoryURL": " https://example.com/pulse "])
        #expect(url == URL(string: "https://example.com/pulse"))
    }
}

@MainActor
@Suite struct MarginHostingViewTests {
    /// The settings window is bigger than the sheet by `CalloutPositioner.shadowMargin` on all
    /// four sides so `SettingsPanel.hasShadow` has room to draw. That band is transparent, and a
    /// click in it belongs to whatever is behind the window — not to the settings sheet.
    @Test func clicksInTheShadowMarginAreNotTheSheets() {
        let margin: CGFloat = 40
        // The hosting view sits at a non-zero origin inside its container, so the
        // `convert(point, from: superview)` inside `hitTest` is exercised for real —
        // with the view at the origin the conversion is the identity and a missing
        // conversion would pass anyway.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300 + 2 * margin + 40, height: 400 + 2 * margin + 40))
        let hosting = MarginHostingView(rootView: Rectangle().fill(Color.red))
        hosting.margin = margin
        hosting.frame = NSRect(x: 20, y: 20, width: 300 + 2 * margin, height: 400 + 2 * margin)
        container.addSubview(hosting)

        // Probe points are in *container* coordinates (what `hitTest` receives); the view's
        // 20 pt origin makes the internal conversion to view coordinates observable.
        #expect(hosting.hitTest(NSPoint(x: 30, y: 220)) == nil)                    // left band
        #expect(hosting.hitTest(NSPoint(x: 390, y: 220)) == nil)                   // right band
        #expect(hosting.hitTest(NSPoint(x: 210, y: 30)) == nil)                    // below
        #expect(hosting.hitTest(NSPoint(x: 210, y: 490)) == nil)                   // above
        #expect(hosting.hitTest(NSPoint(x: 210, y: 260)) === hosting)              // the sheet
    }

    /// A zero margin has to leave the whole view live, so the class is safe to use anywhere a
    /// plain `FirstMouseHostingView` would be.
    @Test func aZeroMarginHitsEverywhere() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let hosting = MarginHostingView(rootView: Rectangle().fill(Color.red))
        hosting.frame = container.bounds
        container.addSubview(hosting)
        #expect(hosting.hitTest(NSPoint(x: 1, y: 1)) === hosting)
    }
}

@Suite struct AppearanceModeTests {
    /// `auto` is "no override": `NSApp.appearance = nil` follows the system live, which is the
    /// whole Auto behaviour (spec §19.6). The other two pin the named appearance.
    @Test func autoIsNoOverrideAndTheOthersPin() {
        #expect(AppearanceMode.auto.pinnedAppearanceName == nil)
        #expect(AppearanceMode.light.pinnedAppearanceName == .aqua)
        #expect(AppearanceMode.dark.pinnedAppearanceName == .darkAqua)
    }
}

@MainActor
@Suite struct SettingsUsageTests {
    private func snapshot(_ percent: Double) -> UsageSnapshot {
        UsageSnapshot(windows: [UsageWindow(kind: .session, label: "Current session", usedPercent: percent, resetsAt: nil)],
                      fetchedAt: Date(), plan: nil)
    }

    @Test func disabledIsOffWhateverTheStatusSays() {
        #expect(SettingsUsage.label(status: .live(snapshot(25)), enabled: false) == "Off")
        #expect(SettingsUsage.label(status: nil, enabled: false) == "Off")
    }

    @Test func liveAndStaleShowTheRoundedSessionPercent() {
        #expect(SettingsUsage.label(status: .live(snapshot(24.6)), enabled: true) == "25%")
        #expect(SettingsUsage.label(status: .stale(snapshot(0), lastError: .network("x")), enabled: true) == "0%")
        #expect(SettingsUsage.label(status: .live(snapshot(100)), enabled: true) == "100%")
    }

    @Test func noNumbersMeansADash() {
        #expect(SettingsUsage.label(status: .loading, enabled: true) == "—")
        #expect(SettingsUsage.label(status: .disconnected(.network("x")), enabled: true) == "—")
        #expect(SettingsUsage.label(status: nil, enabled: true) == "—")
        let empty = UsageSnapshot(windows: [], fetchedAt: Date(), plan: nil)
        #expect(SettingsUsage.label(status: .live(empty), enabled: true) == "—")
    }
}

@Suite struct ProviderReorderTests {
    @Test func proposedIndexRoundsToTheNearestSlotAndClamps() {
        #expect(ProviderReorder.proposedIndex(from: 0, translation: 43, rowHeight: 38, count: 3) == 1)
        #expect(ProviderReorder.proposedIndex(from: 0, translation: 18, rowHeight: 38, count: 3) == 0)
        #expect(ProviderReorder.proposedIndex(from: 0, translation: 500, rowHeight: 38, count: 3) == 2)
        #expect(ProviderReorder.proposedIndex(from: 2, translation: -500, rowHeight: 38, count: 3) == 0)
        #expect(ProviderReorder.proposedIndex(from: 1, translation: -22, rowHeight: 38, count: 3) == 0)
        #expect(ProviderReorder.proposedIndex(from: 1, translation: 0, rowHeight: 38, count: 0) == 1)
    }

    @Test func onlyRowsBetweenFromAndProposedMakeWay() {
        // Dragging row 0 down onto row 1: row 1 steps up, row 2 stays.
        #expect(ProviderReorder.rowOffset(index: 1, draggedFrom: 0, proposed: 1, rowHeight: 38) == -38)
        #expect(ProviderReorder.rowOffset(index: 2, draggedFrom: 0, proposed: 1, rowHeight: 38) == 0)
        // Dragging row 2 up to the top: both others step down.
        #expect(ProviderReorder.rowOffset(index: 0, draggedFrom: 2, proposed: 0, rowHeight: 38) == 38)
        #expect(ProviderReorder.rowOffset(index: 1, draggedFrom: 2, proposed: 0, rowHeight: 38) == 38)
        // No proposal change: nothing moves; the dragged row itself is the caller's business.
        #expect(ProviderReorder.rowOffset(index: 1, draggedFrom: 0, proposed: 0, rowHeight: 38) == 0)
        #expect(ProviderReorder.rowOffset(index: 0, draggedFrom: 0, proposed: 2, rowHeight: 38) == 0)
    }

    @Test func reorderedMovesOneElementAndShrugsAtBadIndices() {
        #expect(ProviderReorder.reordered([1, 2, 3], from: 0, to: 2) == [2, 3, 1])
        #expect(ProviderReorder.reordered([1, 2, 3], from: 2, to: 0) == [3, 1, 2])
        #expect(ProviderReorder.reordered([1, 2, 3], from: 1, to: 1) == [1, 2, 3])
        #expect(ProviderReorder.reordered([1, 2, 3], from: 5, to: 0) == [1, 2, 3])
    }
}

@Suite struct LoginItemTests {
    /// `.requiresApproval` is its own answer, not "off": the registration succeeded and macOS
    /// is only waiting for the user to allow it, so the toggle stays on and the panel explains.
    @Test func statusMapsToTheThreeAnswersTheToggleNeeds() {
        #expect(LoginItem.outcome(for: .enabled) == .on)
        #expect(LoginItem.outcome(for: .requiresApproval) == .needsApproval)
        #expect(LoginItem.outcome(for: .notRegistered) == .off)
        #expect(LoginItem.outcome(for: .notFound) == .off)
    }
}
