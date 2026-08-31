import Testing
import SwiftUI
@testable import Pulse

struct MotionTests {
    @Test func reducedMotionSwapsSpringsForAShortEase() {
        #expect(Motion.reduced(Motion.lift, reduceMotion: true) == .easeOut(duration: 0.18))
        #expect(Motion.reduced(Motion.lift, reduceMotion: false) == Motion.lift)
    }
    @Test func springCurveOvershoots() {
        var cp = [Float](repeating: 0, count: 2)
        Motion.springCurve.getControlPoint(at: 1, values: &cp)
        #expect(cp[1] > 1)   // y1 above 1 is what makes the window land with a spring
    }
}
