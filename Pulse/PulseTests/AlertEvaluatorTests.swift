import Testing
import Foundation
import PulseCore
@testable import Pulse

@Suite struct AlertEvaluatorTests {
    func window(_ pct: Double, kind: UsageWindow.Kind = .session, label: String = "Current session") -> UsageWindow {
        UsageWindow(kind: kind, label: label, usedPercent: pct, resetsAt: Sample.now.addingTimeInterval(12 * 60))
    }

    @Test func firesOnceWhenCrossingTheThresholdUpward() {
        var e = AlertEvaluator(fired: [:])
        #expect(e.evaluate(provider: .claude, windows: [window(89)], threshold: 90).isEmpty)
        let events = e.evaluate(provider: .claude, windows: [window(91)], threshold: 90)
        #expect(events == [AlertEvent(provider: .claude, windowLabel: "Current session", kind: .threshold(90), percent: 91, resetsAt: Sample.now.addingTimeInterval(12 * 60))])
        #expect(e.evaluate(provider: .claude, windows: [window(93)], threshold: 90).isEmpty)
        #expect(e.fired == ["claude.Current session": 90])
    }

    @Test func firesAgainAtOneHundredAndRearmsAfterReset() {
        var e = AlertEvaluator(fired: [:])
        _ = e.evaluate(provider: .codex, windows: [window(95, kind: .weekly, label: "Weekly")], threshold: 90)
        let full = e.evaluate(provider: .codex, windows: [window(100, kind: .weekly, label: "Weekly")], threshold: 90)
        #expect(full.map(\.kind) == [.limitReached])
        #expect(e.fired["codex.Weekly"] == 100)
        #expect(e.evaluate(provider: .codex, windows: [window(100, kind: .weekly, label: "Weekly")], threshold: 90).isEmpty)
        #expect(e.evaluate(provider: .codex, windows: [window(3, kind: .weekly, label: "Weekly")], threshold: 90).isEmpty)
        #expect(e.fired["codex.Weekly"] == nil)                                           // re-armed
        #expect(e.evaluate(provider: .codex, windows: [window(92, kind: .weekly, label: "Weekly")], threshold: 90).count == 1)
    }

    @Test func jumpingStraightToFullFiresOnlyLimitReached() {
        var e = AlertEvaluator(fired: [:])
        let events = e.evaluate(provider: .claude, windows: [window(100)], threshold: 90)
        #expect(events.map(\.kind) == [.limitReached])
    }

    @Test func persistedStateSuppressesRefiringAfterRelaunch() {
        var e = AlertEvaluator(fired: ["claude.Current session": 90])
        #expect(e.evaluate(provider: .claude, windows: [window(94)], threshold: 90).isEmpty)
    }

    @Test func eachWindowIsTrackedIndependently() {
        var e = AlertEvaluator(fired: [:])
        let events = e.evaluate(provider: .claude, windows: [window(95), window(96, kind: .weekly, label: "All models")], threshold: 90)
        #expect(events.map(\.windowLabel) == ["Current session", "All models"])
    }

    @Test func messagesMatchTheSpecCopy() {
        let session = AlertEvent(provider: .claude, windowLabel: "Current session", kind: .threshold(90), percent: 91, resetsAt: nil)
        #expect(AlertMessage.body(for: session, now: Sample.now) == "Claude session at 91%")
        let weekly = AlertEvent(provider: .codex, windowLabel: "Weekly", kind: .limitReached, percent: 100, resetsAt: Sample.now.addingTimeInterval(5 * 86_400 + 7 * 3600 + 30 * 60))
        #expect(AlertMessage.body(for: weekly, now: Sample.now, timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_US_POSIX")) == "Codex weekly limit reached — resets Fri 04:50")
        let gemini = AlertEvent(provider: .gemini, windowLabel: "Gemini CLI quota", kind: .threshold(95), percent: 95, resetsAt: nil)
        #expect(AlertMessage.body(for: gemini, now: Sample.now) == "Gemini CLI quota at 95%")
        let sessionFull = AlertEvent(provider: .claude, windowLabel: "Current session", kind: .limitReached, percent: 100, resetsAt: Sample.now.addingTimeInterval(12 * 60))
        #expect(AlertMessage.body(for: sessionFull, now: Sample.now) == "Claude session limit reached — resets in 12 min")
    }

    @Test func limitReachedWithoutResetOmitsTheClause() {
        let noReset = AlertEvent(provider: .gemini, windowLabel: "Gemini CLI quota", kind: .limitReached, percent: 100, resetsAt: nil)
        #expect(AlertMessage.body(for: noReset, now: Sample.now) == "Gemini CLI quota limit reached")
        let session = AlertEvent(provider: .claude, windowLabel: "Current session", kind: .limitReached, percent: 100, resetsAt: nil)
        #expect(AlertMessage.body(for: session, now: Sample.now) == "Claude session limit reached")
    }
}
