import Testing
import CoreGraphics
@testable import Pulse

struct DockMetricsTests {
    @Test func mediumMatchesTheV3Constants() {
        let m = DockMetrics(size: .medium)
        #expect(m.scale == 1)
        #expect(m.panelWidth == 78 && m.ringDiameter == 48 && m.ringStroke == 3.5 && m.innerRadius == 22 && m.flareRadius == 20)
        #expect(m.cellHeight == 75)          // 48 + 7 + 20
        #expect(m.percentFontSize == 16 && m.smallLabelFontSize == 11)
    }
    @Test func smallAndLargeScaleEveryDimensionTogether() {
        let s = DockMetrics(size: .small), l = DockMetrics(size: .large)
        #expect(s.scale == 0.8 && l.scale == 1.25)
        #expect(s.panelWidth == 62 && l.panelWidth == 98)      // rounded to whole points
        #expect(abs(s.ringDiameter - 38.4) < 0.001 && l.ringDiameter == 60)
        #expect(abs(s.ringStroke - 2.8) < 0.001 && abs(l.ringStroke - 4.375) < 0.001)
        #expect(l.cellHeight == l.ringDiameter + l.labelGap + l.labelHeight)
        #expect(l.percentFontSize == 20 && s.percentFontSize == 12.8)
    }
    @Test func sizesRoundTripThroughRawValues() {
        for size in DockSize.allCases { #expect(DockSize(rawValue: size.rawValue) == size) }
        #expect(DockSize.allCases == [.small, .medium, .large])
    }
}
