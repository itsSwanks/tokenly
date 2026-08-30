import Testing
import CoreGraphics
@testable import Pulse

@Suite struct DockLayoutTests {
    @Test func threeCellsMatchTheSpecGeometry() {
        let layout = DockLayout(cellCount: 3, edge: .right)
        #expect(layout.size.width == 78)
        // 18 top + 3 cells × (48 ring + 7 gap + 20 label) + 2 gaps × 22 + gear row 20 + 10 bottom
        let expectedHeight: CGFloat = 18 + 3 * 75 + 2 * 22 + 20 + 10
        #expect(layout.size.height == expectedHeight)
        #expect(layout.cellCenters.count == 3)
        #expect(layout.cellCenters[0] == CGPoint(x: 39, y: 18 + 24))
        let expectedGap: CGFloat = 75 + 22
        #expect(layout.cellCenters[1].y - layout.cellCenters[0].y == expectedGap)
        #expect(layout.gearCenter.x == 39)
        #expect(layout.gearCenter.y == layout.size.height - 10 - 10)
    }

    @Test func cellFramesCoverRingAndLabel() {
        let layout = DockLayout(cellCount: 2, edge: .right)
        let first = layout.cellFrames[0]
        #expect(first == CGRect(x: 15, y: 18, width: 48, height: 75))
        #expect(layout.cellIndex(at: CGPoint(x: 39, y: 50)) == 0)
        #expect(layout.cellIndex(at: CGPoint(x: 39, y: 18 + 75 + 22 + 5)) == 1)
        #expect(layout.cellIndex(at: CGPoint(x: 39, y: 18 + 75 + 10)) == nil)   // in the gap
        #expect(layout.cellIndex(at: CGPoint(x: 5, y: 50)) == nil)              // outside a cell
    }

    /// v3: there is no collapsed sliver any more — the hidden dock is fully off-screen and
    /// the glass handle is the only resting UI, so the layout has one geometry, always
    /// including the flare margin.
    @Test func layoutAlwaysCarriesTheFlareMargin() {
        let layout = DockLayout(cellCount: 3, edge: .right)
        // Spelled out rather than reusing `flareInset`, so the assertion still bites if the
        // constant itself moves: 20 pt of margin above and below.
        let expectedMargin: CGFloat = 40
        #expect(DockLayout.flareInset == 20)
        #expect(layout.windowSize.width == layout.size.width)
        #expect(layout.windowSize.height == layout.size.height + expectedMargin)
        #expect(layout.contentOrigin == CGPoint(x: 0, y: 20))
    }

    @Test func zeroCellsStillHasAGear() {
        let layout = DockLayout(cellCount: 0, edge: .left)
        #expect(layout.cellCenters.isEmpty)
        let expectedZeroCellHeight: CGFloat = 18 + 20 + 10
        #expect(layout.size.height == expectedZeroCellHeight)
    }
}
