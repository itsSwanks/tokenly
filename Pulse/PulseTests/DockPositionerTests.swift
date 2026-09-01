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

    @Test func distanceToTheRightEdgeIsMeasuredFromTheVisibleFrame() {
        let near = DockPositioner.distanceToEdge(point: CGPoint(x: 1430, y: 400), edge: .right, visible: visible, screenFrame: screenFrame)
        let expectedNear: CGFloat = 10
        #expect(near == expectedNear)
        // Inside the screen but above the visible frame (the menu-bar strip) still counts.
        let inMenuBar = DockPositioner.distanceToEdge(point: CGPoint(x: 1430, y: 890), edge: .right, visible: visible, screenFrame: screenFrame)
        #expect(inMenuBar == expectedNear)
    }

    @Test func distanceToTheLeftEdgeGrowsRightward() {
        let d = DockPositioner.distanceToEdge(point: CGPoint(x: 37, y: 400), edge: .left, visible: visible, screenFrame: screenFrame)
        let expected: CGFloat = 37
        #expect(d == expected)
    }

    @Test func aPointOnAnotherDisplayHasNoDistance() {
        // A second display to the right: without the screen test this would read as a large
        // negative number and count as "at the edge".
        #expect(DockPositioner.distanceToEdge(point: CGPoint(x: 2200, y: 400), edge: .right, visible: visible, screenFrame: screenFrame) == nil)
        #expect(DockPositioner.distanceToEdge(point: CGPoint(x: -300, y: 400), edge: .left, visible: visible, screenFrame: screenFrame) == nil)
    }
}
