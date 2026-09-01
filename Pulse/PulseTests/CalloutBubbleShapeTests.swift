import Testing
import CoreGraphics
@testable import Pulse

struct CalloutBubbleShapeTests {
    @Test func tailPointsAtTheDockAndCardStaysRounded() {
        let rect = CGRect(x: 0, y: 0, width: 331, height: 160)   // 320 card + 11 tail
        let right = CalloutBubbleShape(edge: .right, tailY: 80).path(in: rect)
        #expect(right.contains(CGPoint(x: 329, y: 80)))          // tail tip, right edge
        #expect(!right.contains(CGPoint(x: 329, y: 40)))         // beside the tail: card ends at x 320
        #expect(!right.contains(CGPoint(x: 1, y: 1)))            // rounded corner is cut
        let left = CalloutBubbleShape(edge: .left, tailY: 80).path(in: rect)
        #expect(left.contains(CGPoint(x: 2, y: 80)) && !left.contains(CGPoint(x: 2, y: 40)))
        // The 0.5 pt weld where the tail's base overlaps the card. Both subpaths cover these
        // points, so under the non-zero fill rule they only stay filled while the tail winds the
        // same way the rounded rect does — wound the other way the overlap cancels to zero and
        // the tail is slit off the card.
        #expect(right.contains(CGPoint(x: 319.75, y: 80)))       // card ends 320, tail base 319.5
        #expect(left.contains(CGPoint(x: 11.25, y: 80)))         // card starts 11, tail base 11.5
    }
}
