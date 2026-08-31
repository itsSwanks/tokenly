import Testing
@testable import PulseCore

@Suite struct UsageLevelTests {
    @Test(arguments: [
        (0.0, UsageLevel.green), (39.9, .green), (40.0, .yellow), (69.9, .yellow),
        (70.0, .orange), (89.9, .orange), (90.0, .red), (100.0, .red), (150.0, .red), (-5.0, .green),
    ])
    func levelBoundaries(percent: Double, expected: UsageLevel) {
        #expect(UsageLevel(percent: percent) == expected)
    }

    @Test func pulsesOnlyBetweenNinetyAndHundred() {
        #expect(UsageLevel.pulses(percent: 89.9) == false)
        #expect(UsageLevel.pulses(percent: 90) == true)
        #expect(UsageLevel.pulses(percent: 99.9) == true)
        #expect(UsageLevel.pulses(percent: 100) == false)
    }

    @Test func exhaustedAtHundred() {
        #expect(UsageLevel.isExhausted(percent: 99.99) == false)
        #expect(UsageLevel.isExhausted(percent: 100) == true)
    }
}
