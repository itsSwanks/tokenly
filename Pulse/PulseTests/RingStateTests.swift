import Testing
import CoreGraphics
import PulseCore
@testable import Pulse

@Suite struct RingStateTests {
    @Test func loadingAndDisconnectedMapDirectly() {
        #expect(RingState(status: .loading) == .loading)
        #expect(RingState(status: .disconnected(.credentialsMissing(hint: "x"))) == .disconnected)
        #expect(RingState(status: .loading).label == "")
        #expect(RingState(status: .disconnected(.network("x"))).label == "—")
    }

    @Test func liveUsesTheSessionWindowAndSemanticLevel() {
        let state = RingState(status: .live(Sample.snapshot(session: 73, weekly: 7)))
        #expect(state == .value(percent: 73, level: .orange, pulses: false, exhausted: false, dimmed: false))
        #expect(state.label == "73%")
    }

    @Test func nearLimitPulsesAndExhaustedReadsLimitReached() {
        #expect(RingState(status: .live(Sample.snapshot(session: 94))) == .value(percent: 94, level: .red, pulses: true, exhausted: false, dimmed: false))
        let full = RingState(status: .live(Sample.snapshot(session: 100)))
        #expect(full == .value(percent: 100, level: .red, pulses: false, exhausted: true, dimmed: false))
        #expect(full.label == "Limit reached")
    }

    @Test func staleIsDimmedButKeepsTheValue() {
        let state = RingState(status: .stale(Sample.snapshot(session: 21), lastError: .network("down")))
        #expect(state == .value(percent: 21, level: .green, pulses: false, exhausted: false, dimmed: true))
        #expect(state.label == "21%")
    }

    @Test func percentLabelRoundsToWholeNumbers() {
        #expect(RingState(status: .live(Sample.snapshot(session: 42.6))).label == "43%")
        #expect(RingState(status: .live(Sample.snapshot(session: 0.2))).label == "0%")
    }

    @Test func snapshotWithoutWindowsIsDisconnected() {
        let empty = UsageSnapshot(windows: [], fetchedAt: Sample.now, plan: nil)
        #expect(RingState(status: .live(empty)) == .disconnected)
    }

    @Test func layoutWindowSizeIncludesFlares() {
        let layout = DockLayout(cellCount: 1, edge: .right)
        #expect(layout.flareInset == 20)
        #expect(layout.windowSize.height == layout.size.height + 40)
        #expect(layout.contentOrigin == CGPoint(x: 0, y: 20))
    }
}
