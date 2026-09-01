import Testing
import CoreGraphics
@testable import Pulse

@Suite struct HandleLayoutTests {
    @Test func threeDotsMatchTheSpecGeometry() {
        let layout = HandleLayout(dotCount: 3)
        let expectedWidth: CGFloat = 9
        #expect(layout.size.width == expectedWidth)
        // 14 top + 3 dots × 5 + 2 gaps × 13 + 14 bottom
        let expectedHeight: CGFloat = 14 + 3 * 5 + 2 * 13 + 14
        #expect(layout.size.height == expectedHeight)
        #expect(layout.dotCenters.count == 3)
        let expectedX: CGFloat = 4.5
        #expect(layout.dotCenters.allSatisfy { $0.x == expectedX })
        let firstY: CGFloat = 14 + 2.5
        #expect(layout.dotCenters[0].y == firstY)
        let expectedPitch: CGFloat = 18
        #expect(layout.dotCenters[1].y - layout.dotCenters[0].y == expectedPitch)
        // Symmetric: the last dot's bottom sits one padding above the handle's bottom.
        #expect(layout.size.height - (layout.dotCenters[2].y + 2.5) == layout.dotCenters[0].y - 2.5)
    }

    @Test func oneDotIsCentredBetweenThePaddings() {
        let layout = HandleLayout(dotCount: 1)
        let expectedHeight: CGFloat = 14 + 5 + 14
        #expect(layout.size.height == expectedHeight)
        #expect(layout.dotCenters.count == 1)
        #expect(layout.dotCenters[0].y == layout.size.height / 2)
    }

    @Test func zeroDotsIsJustThePadding() {
        let layout = HandleLayout(dotCount: 0)
        let expectedHeight: CGFloat = 28
        #expect(layout.size.height == expectedHeight)
        #expect(layout.dotCenters.isEmpty)
    }

    @Test func negativeCountsClampToZero() {
        let layout = HandleLayout(dotCount: -3)
        #expect(layout.dotCount == 0)
        #expect(layout.dotCenters.isEmpty)
    }
}
