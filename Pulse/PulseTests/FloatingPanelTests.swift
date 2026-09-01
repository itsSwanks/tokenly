import AppKit
import Testing
@testable import Pulse

/// Runs against the live WindowServer through the test host app. Every ordering call is
/// verified a spin later, never synchronously: the server updates its on-screen list one
/// run-loop turn after the order — the same reason production only verifies after the
/// expand animation has settled.
@MainActor
@Suite(.serialized) struct FloatingPanelTests {
    /// Counts order-outs so a test can prove `ensureOnScreen` did not cycle a healthy panel.
    private final class CountingPanel: FloatingPanel {
        var orderOutCount = 0
        override func orderOut(_ sender: Any?) {
            orderOutCount += 1
            super.orderOut(sender)
        }
    }

    private func spin(_ seconds: TimeInterval = 0.15) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Far outside every display: the dock's parked frame is fully off-screen too, and the
    /// server must still count an ordered-in panel there as on screen or auto-hide would
    /// read every parked dock as lost.
    private func makePanel() -> CountingPanel {
        CountingPanel(contentRect: NSRect(x: -2000, y: -2000, width: 40, height: 40))
    }

    @Test func neverOrderedPanelIsNotOnTheServerList() {
        let panel = makePanel()
        #expect(panel.serverSeesOnScreen == false)
    }

    @Test func orderedInPanelIsOnTheServerListEvenAtAFullyOffScreenFrame() {
        let panel = makePanel()
        panel.orderFrontRegardless()
        spin()
        #expect(panel.serverSeesOnScreen == true)
        panel.orderOut(nil)
    }

    @Test func orderedOutPanelLeavesTheServerList() {
        let panel = makePanel()
        panel.orderFrontRegardless()
        spin()
        panel.orderOut(nil)
        spin()
        #expect(panel.serverSeesOnScreen == false)
    }

    @Test func ensureOnScreenBringsBackAPanelTheServerDoesNotList() {
        let panel = makePanel()
        // A panel the server does not list, that its owner believes should be up, is the
        // publicly reachable stand-in for the post-sleep desync; the heal path is identical.
        panel.ensureOnScreen()
        spin()
        #expect(panel.serverSeesOnScreen == true)
        panel.orderOut(nil)
    }

    @Test func ensureOnScreenDoesNotCycleAHealthyVisiblePanel() {
        let panel = makePanel()
        panel.orderFrontRegardless()
        spin()
        panel.ensureOnScreen()
        #expect(panel.orderOutCount == 0)
        #expect(panel.isVisible == true)
        panel.orderOut(nil)
    }
}
