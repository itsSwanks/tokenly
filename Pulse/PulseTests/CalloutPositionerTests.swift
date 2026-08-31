import Testing
import CoreGraphics
@testable import Pulse

@Suite struct CalloutPositionerTests {
    let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)
    let dock = CGRect(x: 1362, y: 250, width: 78, height: 357)
    let size = CGSize(width: 331, height: 260)   // 320 body + 11 tail
    let margin = CalloutPositioner.shadowMargin

    @Test func rightEdgeCalloutSitsLeftOfTheDockWithTheGap() {
        let (frame, tailY) = CalloutPositioner.place(calloutSize: size, dockFrame: dock, ringCenterY: 600, edge: .right, in: visible)
        // The tail side carries no margin, so the window's own edge is still the bubble's.
        #expect(frame.maxX == dock.minX - Metrics.calloutGap)
        #expect(frame.midY == 600)                    // the margin is symmetric top and bottom
        #expect(tailY == 130)                         // tail at the ring's height, measured from the bubble's bottom
    }

    @Test func leftEdgeCalloutSitsRightOfTheDock() {
        let leftDock = CGRect(x: 0, y: 250, width: 78, height: 357)
        let (frame, _) = CalloutPositioner.place(calloutSize: size, dockFrame: leftDock, ringCenterY: 600, edge: .left, in: visible)
        #expect(frame.minX == leftDock.maxX + Metrics.calloutGap)
    }

    @Test func calloutIsClampedButTheTailStillPointsAtTheRing() {
        let (frame, tailY) = CalloutPositioner.place(calloutSize: size, dockFrame: dock, ringCenterY: 850, edge: .right, in: visible)
        // The *bubble* is clamped to the visible frame; the transparent margin hangs past it.
        #expect(frame.maxY - margin == visible.maxY)
        #expect(frame.minY + margin + tailY == 850)
        let (low, lowTail) = CalloutPositioner.place(calloutSize: size, dockFrame: dock, ringCenterY: 90, edge: .right, in: visible)
        #expect(low.minY + margin == visible.minY)
        #expect(lowTail == 20)
    }

    @Test func tailNeverLeavesTheRoundedCorners() {
        // A ring so low that its centre sits inside the corner radius: the tail stops at
        // `tailHalfHeight` (9) from the callout's bottom rather than pointing off the card.
        let (_, tailY) = CalloutPositioner.place(calloutSize: size, dockFrame: dock, ringCenterY: 74, edge: .right, in: visible)
        let expected: CGFloat = 9
        #expect(tailY == expected)
    }

    @Test func theWindowCarriesTheShadowMarginOnItsThreeNonTailSides() {
        let (right, _) = CalloutPositioner.place(calloutSize: size, dockFrame: dock, ringCenterY: 600, edge: .right, in: visible)
        #expect(right.width == size.width + margin)
        #expect(right.height == size.height + 2 * margin)

        let leftDock = CGRect(x: 0, y: 250, width: 78, height: 357)
        let (left, _) = CalloutPositioner.place(calloutSize: size, dockFrame: leftDock, ringCenterY: 600, edge: .left, in: visible)
        #expect(left.width == size.width + margin)
        #expect(left.height == size.height + 2 * margin)
    }

    @Test func aZeroMarginPlacesTheBubbleItself() {
        // What the settings panel asks for: a content-sized window, drawn exactly where the
        // callout's bubble would be.
        let (frame, _) = CalloutPositioner.place(calloutSize: size, dockFrame: dock, ringCenterY: 600, edge: .right, in: visible, margin: 0)
        #expect(frame == CGRect(x: dock.minX - Metrics.calloutGap - size.width, y: 470, width: size.width, height: size.height))
    }

    @Test func bubbleRectInvertsTheMargin() {
        for edge in [ScreenEdge.right, .left] {
            let (frame, _) = CalloutPositioner.place(calloutSize: size, dockFrame: dock, ringCenterY: 600, edge: edge, in: visible)
            let bubble = CalloutPositioner.bubbleRect(inWindowOfSize: frame.size, edge: edge)
            #expect(bubble.size == size)
            // Offsetting the bubble back into screen space lands it where a zero-margin
            // placement would have put the window.
            let (bare, _) = CalloutPositioner.place(calloutSize: size, dockFrame: dock, ringCenterY: 600, edge: edge, in: visible, margin: 0)
            #expect(bubble.offsetBy(dx: frame.minX, dy: frame.minY) == bare)
        }
    }

    @Test func bubbleRectNeverGoesNegativeOnAWindowSmallerThanTheMargin() {
        let bubble = CalloutPositioner.bubbleRect(inWindowOfSize: CGSize(width: 10, height: 10), edge: .right)
        #expect(bubble.width == 0)
        #expect(bubble.height == 0)
    }
}
