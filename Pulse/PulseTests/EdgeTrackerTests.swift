import Testing
import Foundation
@testable import Pulse

@Suite struct EdgeTrackerTests {
    let t0 = Date(timeIntervalSince1970: 1_788_038_400)

    @Test func startsCollapsedAndExpandsWithinProximity() {
        var e = EdgeTracker()
        #expect(e.state == .collapsed)
        #expect(e.update(distance: 45, holdOpen: false, now: t0) == nil)
        #expect(e.update(distance: 44, holdOpen: false, now: t0) == .expand)
        #expect(e.state == .expanded)
        #expect(e.update(distance: 10, holdOpen: false, now: t0) == nil)
    }

    @Test func collapsesOnlyAfterGraceFarFromTheEdge() {
        var e = EdgeTracker()
        _ = e.update(distance: 0, holdOpen: false, now: t0)
        #expect(e.update(distance: 201, holdOpen: false, now: t0) == nil)                       // grace starts
        #expect(e.update(distance: 300, holdOpen: false, now: t0.addingTimeInterval(0.39)) == nil)
        #expect(e.update(distance: 300, holdOpen: false, now: t0.addingTimeInterval(0.4)) == .collapse)
        #expect(e.state == .collapsed)
    }

    @Test func comingBackCancelsTheGrace() {
        var e = EdgeTracker()
        _ = e.update(distance: 0, holdOpen: false, now: t0)
        _ = e.update(distance: 250, holdOpen: false, now: t0)
        _ = e.update(distance: 100, holdOpen: false, now: t0.addingTimeInterval(0.2))            // within 200: cancel
        #expect(e.update(distance: 250, holdOpen: false, now: t0.addingTimeInterval(0.5)) == nil) // new grace from 0.5
        #expect(e.update(distance: 250, holdOpen: false, now: t0.addingTimeInterval(0.89)) == nil)
        #expect(e.update(distance: 250, holdOpen: false, now: t0.addingTimeInterval(0.9)) == .collapse)
    }

    @Test func holdOpenBlocksCollapseAndResetsGrace() {
        var e = EdgeTracker()
        _ = e.update(distance: 0, holdOpen: false, now: t0)
        _ = e.update(distance: 400, holdOpen: true, now: t0)
        #expect(e.update(distance: 400, holdOpen: true, now: t0.addingTimeInterval(5)) == nil)
        #expect(e.update(distance: 400, holdOpen: false, now: t0.addingTimeInterval(5)) == nil)   // grace starts now
        #expect(e.update(distance: 400, holdOpen: false, now: t0.addingTimeInterval(5.4)) == .collapse)
    }

    @Test func forceCollapseAndExpandSetStateDirectly() {
        var e = EdgeTracker()
        e.force(.expanded)
        #expect(e.state == .expanded)
        e.force(.collapsed)
        #expect(e.state == .collapsed)
    }
}
