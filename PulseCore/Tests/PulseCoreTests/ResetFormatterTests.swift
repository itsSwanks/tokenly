import Foundation
import Testing
@testable import PulseCore

@Suite struct ResetFormatterTests {
    // 2026-08-29T21:20:00Z — a Saturday.
    let now = Date(timeIntervalSince1970: 1_788_038_400)
    let utc = TimeZone(identifier: "UTC")!
    let locale = Locale(identifier: "en_US_POSIX")

    func text(_ offset: TimeInterval?) -> String {
        ResetFormatter.text(resetsAt: offset.map { now.addingTimeInterval($0) }, now: now, timeZone: utc, locale: locale)
    }

    @Test func unknownIsDash() { #expect(text(nil) == "—") }
    @Test func underAMinute() { #expect(text(30) == "Resets in <1 min"); #expect(text(-5) == "Resets in <1 min") }
    @Test func minutes() { #expect(text(51 * 60) == "Resets in 51 min"); #expect(text(3599) == "Resets in 60 min") }
    @Test func hoursAndMinutes() { #expect(text(2 * 3600 + 5 * 60) == "Resets in 2 h 05 min"); #expect(text(23 * 3600 + 59 * 60) == "Resets in 23 h 59 min") }
    @Test func aDayOrMoreIsAbsoluteWeekdayTime() {
        #expect(text(24 * 3600) == "Resets Sun 21:20")
        #expect(text(5 * 24 * 3600 + 7 * 3600 + 30 * 60) == "Resets Fri 04:50")
    }
}
