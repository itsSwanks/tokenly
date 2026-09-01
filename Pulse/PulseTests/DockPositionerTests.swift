import Testing
import CoreGraphics
@testable import Pulse

@Suite struct DockPositionerTests {
    // A 1440×900 display whose menu bar takes the top 25 pt and whose Dock takes the bottom 70 pt.
    let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)
    let size = CGSize(width: 78, height: 357)

    @Test func rightEdgeIsFlushWithMaxX() {
        let f = DockPositioner.frame(windowSize: size, edge: .right, yFraction: 0.5, in: visible)
        #expect(f.maxX == 1440)
        #expect(f.width == 78)
        #expect(f.midY == visible.midY)
    }

    @Test func leftEdgeIsFlushWithMinX() {
        let f = DockPositioner.frame(windowSize: size, edge: .left, yFraction: 0.5, in: visible)
        #expect(f.minX == 0)
    }

    @Test func yIsClampedInsideTheVisibleFrame() {
        let top = DockPositioner.frame(windowSize: size, edge: .right, yFraction: 1.0, in: visible)
        #expect(top.maxY == visible.maxY)
        let bottom = DockPositioner.frame(windowSize: size, edge: .right, yFraction: 0.0, in: visible)
        #expect(bottom.minY == visible.minY)
    }

    @Test func yFractionRoundTrips() {
        let f = DockPositioner.frame(windowSize: size, edge: .right, yFraction: 0.3, in: visible)
        #expect(abs(DockPositioner.yFraction(of: f, in: visible) - 0.3) < 0.0001)
    }

    @Test func tallerThanScreenPinsToBottom() {
        let huge = CGSize(width: 78, height: 2000)
        let f = DockPositioner.frame(windowSize: huge, edge: .right, yFraction: 0.5, in: visible)
        #expect(f.minY == visible.minY)
    }

    // The whole display, of which `visible` is the part left over after the menu bar and Dock.
    var screenFrame: CGRect { CGRect(x: 0, y: 0, width: 1440, height: 900) }

    // The collapsed handle the trigger halo surrounds, resting against the right edge.
    var handleFrame: CGRect { CGRect(x: 1431, y: 380, width: 9, height: 69) }

    @Test func distanceIsZeroInsideTheTarget() {
        #expect(DockPositioner.distance(from: CGPoint(x: 1435, y: 400), to: handleFrame, screenFrame: screenFrame) == 0)
    }

    @Test func distanceBesideTheTargetIsTheHorizontalGap() {
        let d = DockPositioner.distance(from: CGPoint(x: 1400, y: 400), to: handleFrame, screenFrame: screenFrame)
        let expected: CGFloat = 31
        #expect(d == expected)
    }

    @Test func distanceAboveTheTargetIsTheVerticalGap() {
        let d = DockPositioner.distance(from: CGPoint(x: 1435, y: 500), to: handleFrame, screenFrame: screenFrame)
        let expected: CGFloat = 51
        #expect(d == expected)
    }

    @Test func distanceAtACornerIsTheLargerAxisGap() {
        // 31 pt beside the handle and 51 pt above it: the halo is per-axis, so the trigger
        // reaches as far vertically as horizontally and no further — no rounded corners.
        let d = DockPositioner.distance(from: CGPoint(x: 1400, y: 500), to: handleFrame, screenFrame: screenFrame)
        let expected: CGFloat = 51
        #expect(d == expected)
    }

    @Test func theMenuBarStripStillCountsAsOnScreen() {
        // Inside the screen but above the visible frame: a handle parked at the top of the
        // visible frame must stay reachable from the menu-bar strip.
        let top = CGRect(x: 1431, y: 811, width: 9, height: 64)
        let d = DockPositioner.distance(from: CGPoint(x: 1435, y: 890), to: top, screenFrame: screenFrame)
        let expected: CGFloat = 15
        #expect(d == expected)
    }

    @Test func aPointOnAnotherDisplayHasNoDistance() {
        // A second display to the right: without the screen test the cursor over there would
        // still measure a finite distance and could pop the dock open on a screen the user
        // isn't pointing at.
        #expect(DockPositioner.distance(from: CGPoint(x: 2200, y: 400), to: handleFrame, screenFrame: screenFrame) == nil)
        #expect(DockPositioner.distance(from: CGPoint(x: -300, y: 400), to: handleFrame, screenFrame: screenFrame) == nil)
    }
}
