import Testing
@testable import Pulse

@Suite struct HoverCoordinatorTests {
    @Test func hoveringARingShowsThenMovesTheCallout() {
        var h = HoverCoordinator()
        #expect(h.handle(.hoverCell(0)) == [.show(0)])
        #expect(h.visibleIndex == 0)
        #expect(h.handle(.hoverCell(1)) == [.move(1)])
        #expect(h.handle(.hoverCell(1)) == [])
    }

    @Test func leavingSchedulesAGraceTimeoutAndTimeoutHides() {
        var h = HoverCoordinator()
        _ = h.handle(.hoverCell(0))
        let effects = h.handle(.hoverCell(nil))
        #expect(effects == [.scheduleTimeout(after: Motion.hoverGrace, id: 1)])
        #expect(h.handle(.timeout(id: 1)) == [.hide])
        #expect(h.visibleIndex == nil)
    }

    @Test func leavingTwiceSchedulesOnlyOneTimeout() {
        var h = HoverCoordinator()
        _ = h.handle(.hoverCell(0))
        #expect(h.handle(.hoverCell(nil)) == [.scheduleTimeout(after: Motion.hoverGrace, id: 1)])
        #expect(h.handle(.hoverCell(nil)) == [])
    }

    @Test func forceHideWithNothingVisibleIsANoOp() {
        var h = HoverCoordinator()
        #expect(h.handle(.forceHide) == [])
    }

    @Test func staleTimeoutIsIgnoredAndEnteringCalloutCancels() {
        var h = HoverCoordinator()
        _ = h.handle(.hoverCell(0))
        _ = h.handle(.hoverCell(nil))                         // timeout id 1 pending
        #expect(h.handle(.enterCallout) == [.cancelTimeout(id: 1)])
        #expect(h.handle(.timeout(id: 1)) == [])             // cancelled: ignored
        #expect(h.visibleIndex == 0)
        _ = h.handle(.leaveCallout)                           // id 2 pending
        _ = h.handle(.hoverCell(0))                           // back on the ring: cancels id 2
        #expect(h.handle(.timeout(id: 2)) == [])
        #expect(h.visibleIndex == 0)
    }

    @Test func clickPinsAndPinnedIgnoresLeaveAndOtherHovers() {
        var h = HoverCoordinator()
        _ = h.handle(.hoverCell(0))
        #expect(h.handle(.clickCell(0)) == [])
        #expect(h.pinnedIndex == 0)
        #expect(h.handle(.hoverCell(nil)) == [])
        #expect(h.handle(.hoverCell(1)) == [])
        #expect(h.visibleIndex == 0)
    }

    @Test func clickingAnotherRingWhilePinnedMovesThePin() {
        var h = HoverCoordinator()
        _ = h.handle(.clickCell(0))
        #expect(h.visibleIndex == 0)
        #expect(h.handle(.clickCell(2)) == [.move(2)])
        #expect(h.pinnedIndex == 2)
    }

    @Test func reclickUnpinsAndClickAwayHides() {
        var h = HoverCoordinator()
        _ = h.handle(.clickCell(0))
        #expect(h.handle(.clickCell(0)) == [])
        #expect(h.pinnedIndex == nil && h.visibleIndex == 0)
        _ = h.handle(.clickCell(0))
        #expect(h.handle(.clickAway) == [.hide])
        #expect(h.pinnedIndex == nil && h.visibleIndex == nil)
        #expect(h.handle(.clickAway) == [])
    }

    @Test func forceHideClearsEverything() {
        var h = HoverCoordinator()
        _ = h.handle(.clickCell(1))
        #expect(h.handle(.forceHide) == [.hide])
        #expect(h.pinnedIndex == nil && h.visibleIndex == nil)
    }
}
