import Foundation
import Testing
@testable import PulseCore

@MainActor
@Suite struct UsageStoreTests {
    let clock = FakeClock(now: Date(timeIntervalSince1970: 1_788_038_400))
    let claude = FakeProvider(.claude)
    let codex = FakeProvider(.codex)

    func makeStore(enabled: Set<ProviderID> = [.claude, .codex]) -> UsageStore {
        UsageStore(providers: [claude, codex], enabled: enabled, http: FakeHTTPClient(), clock: clock, policy: PollPolicy())
    }

    @Test func startsLoadingForEnabledProvidersOnly() {
        let store = makeStore(enabled: [.claude])
        #expect(store.statuses == [.claude: .loading])
    }

    @Test func firstTickFetchesAndPublishesLive() async {
        let store = makeStore()
        claude.enqueue(snapshot(73, at: clock.now)); codex.enqueue(snapshot(21, at: clock.now))
        await store.tick()
        #expect(store.statuses[.claude] == .live(snapshot(73, at: clock.now)))
        #expect(store.statuses[.codex] == .live(snapshot(21, at: clock.now)))
        #expect(claude.calls == 1 && codex.calls == 1)
    }

    @Test func doesNotRefetchBeforeIntervalElapses() async {
        let store = makeStore(enabled: [.claude])
        claude.enqueue(snapshot(10, at: clock.now)); claude.repeatLast()
        await store.tick()
        clock.advance(by: 59); await store.tick()
        #expect(claude.calls == 1)
        clock.advance(by: 1); await store.tick()
        #expect(claude.calls == 2)
    }

    @Test func failureWithoutSnapshotIsDisconnected() async {
        let store = makeStore(enabled: [.claude])
        claude.enqueue(.network("boom"))
        await store.tick()
        #expect(store.statuses[.claude] == .disconnected(.network("boom")))
    }

    @Test func failureAfterSnapshotKeepsLiveThenGoesStale() async {
        let store = makeStore(enabled: [.claude])
        let snap = snapshot(50, at: clock.now)
        claude.enqueue(snap); claude.enqueue(.network("down")); claude.repeatLast()
        await store.tick()                                   // live
        clock.advance(by: 60); await store.tick()            // fails, still live
        #expect(store.statuses[.claude] == .live(snap))
        clock.advance(by: 60); await store.tick()            // 120 s old — still live
        clock.advance(by: 181); await store.tick()           // 301 s old → stale
        #expect(store.statuses[.claude] == .stale(snap, lastError: .network("down")))
    }

    @Test func backsOffExponentiallyAndCaps() async {
        let store = makeStore(enabled: [.claude])
        claude.enqueue(.network("x")); claude.repeatLast()
        await store.tick()                                    // failure #1 → next in 60
        let expected = [60.0, 120, 240, 300, 300]
        for delay in expected {
            let before = claude.calls
            clock.advance(by: delay - 1); await store.tick()
            #expect(claude.calls == before, "fetched too early before \(delay)s")
            clock.advance(by: 1); await store.tick()
            #expect(claude.calls == before + 1, "did not fetch at \(delay)s")
        }
    }

    @Test func successResetsBackoff() async {
        let store = makeStore(enabled: [.claude])
        claude.enqueue(.network("x")); claude.enqueue(.network("x")); claude.enqueue(snapshot(1, at: clock.now)); claude.repeatLast()
        await store.tick()
        clock.advance(by: 60); await store.tick()
        clock.advance(by: 120); await store.tick()            // success
        #expect(store.nextAttempt(for: .claude) == clock.now.addingTimeInterval(60))
    }

    @Test func rateLimitedHonorsRetryAfter() async {
        let store = makeStore(enabled: [.claude])
        claude.enqueue(.rateLimited(retryAfter: 90)); claude.repeatLast()
        await store.tick()
        #expect(store.nextAttempt(for: .claude) == clock.now.addingTimeInterval(90))
    }

    // Every credential-class failure drops the snapshot and disconnects; they differ only in how
    // soon the next attempt is scheduled, so each one gets its own test.

    @Test func missingCredentialsRetryAtInterval() async {
        let store = makeStore(enabled: [.claude])
        claude.enqueue(snapshot(5, at: clock.now)); claude.enqueue(.credentialsMissing(hint: "h")); claude.repeatLast()
        await store.tick()
        clock.advance(by: 60); await store.tick()
        #expect(store.statuses[.claude] == .disconnected(.credentialsMissing(hint: "h")))
        #expect(store.nextAttempt(for: .claude) == clock.now.addingTimeInterval(60))
        // Signing in fixes this at any moment, so repeated failures must not stretch the interval.
        clock.advance(by: 60); await store.tick()
        #expect(store.nextAttempt(for: .claude) == clock.now.addingTimeInterval(60))
    }

    @Test func expiredCredentialsBackOff() async {
        let store = makeStore(enabled: [.claude])
        claude.enqueue(snapshot(5, at: clock.now)); claude.enqueue(.credentialsExpired(hint: "h")); claude.repeatLast()
        await store.tick()
        clock.advance(by: 60); await store.tick()              // failure #1 → 60 s
        #expect(store.statuses[.claude] == .disconnected(.credentialsExpired(hint: "h")))
        #expect(store.nextAttempt(for: .claude) == clock.now.addingTimeInterval(60))
        clock.advance(by: 60); await store.tick()              // failure #2 → 120 s
        #expect(store.nextAttempt(for: .claude) == clock.now.addingTimeInterval(120))
    }

    @Test func unsupportedAccountRetriesAtUnsupportedInterval() async {
        let store = makeStore(enabled: [.claude])
        claude.enqueue(.unsupportedAccount("no numbers")); claude.repeatLast()
        await store.tick()
        #expect(store.statuses[.claude] == .disconnected(.unsupportedAccount("no numbers")))
        #expect(store.nextAttempt(for: .claude) == clock.now.addingTimeInterval(1800))
    }

    // A snapshot goes stale on the wall clock, not on a fetch, so `tick()` must promote it on a
    // cycle where nothing is due at all. The failing fetch lands while the snapshot is still fresh
    // (so `apply` publishes `.live`), and the back-off then puts the next attempt well past the
    // staleness deadline — leaving `tick`'s own staleness sweep as the only thing that can move it.
    @Test func staleIsPromotedByTickWhenNothingIsDue() async {
        let store = UsageStore(providers: [claude], enabled: [.claude], http: FakeHTTPClient(), clock: clock,
                               policy: PollPolicy(interval: 1000, maxBackoff: 1000, staleAfter: 300))
        let snap = snapshot(50, at: clock.now)
        claude.enqueue(snap); claude.enqueue(.network("down")); claude.repeatLast()
        await store.tick()                                      // live; next attempt at +1000
        clock.advance(by: 60); await store.refreshNow(.claude)  // fails; snapshot 60 s old → live
        #expect(store.statuses[.claude] == .live(snap))
        clock.advance(by: 301); await store.tick()              // +361: next attempt is +1060 → nothing due
        #expect(claude.calls == 2)
        #expect(store.statuses[.claude] == .stale(snap, lastError: .network("down")))
    }

    @Test func enabledIsFilteredToRegisteredProviders() {
        let store = UsageStore(providers: [claude], enabled: [.claude, .gemini], http: FakeHTTPClient(), clock: clock)
        #expect(store.enabled == [.claude])
        #expect(Set(store.statuses.keys) == store.enabled)
    }

    @Test func refreshNowIgnoresSchedule() async {
        let store = makeStore(enabled: [.claude])
        claude.enqueue(snapshot(1, at: clock.now)); claude.repeatLast()
        await store.tick()
        await store.refreshNow(.claude)
        #expect(claude.calls == 2)
        await store.refreshNow(nil)
        #expect(claude.calls == 3)
    }

    @Test func disablingRemovesStatusAndEnablingReloads() async {
        let store = makeStore()
        claude.enqueue(snapshot(1, at: clock.now)); claude.repeatLast(); codex.enqueue(snapshot(2, at: clock.now)); codex.repeatLast()
        await store.tick()
        store.setEnabled(.codex, false)
        #expect(store.statuses[.codex] == nil)
        #expect(store.enabled == [.claude])
        store.setEnabled(.codex, true)
        #expect(store.statuses[.codex] == .loading)
        await store.tick()
        #expect(store.statuses[.codex] == .live(snapshot(2, at: clock.now)))
    }

    @Test func oneProviderFailingDoesNotBlockAnother() async {
        let store = makeStore()
        claude.enqueue(.network("x")); codex.enqueue(snapshot(9, at: clock.now))
        await store.tick()
        #expect(store.statuses[.claude] == .disconnected(.network("x")))
        #expect(store.statuses[.codex] == .live(snapshot(9, at: clock.now)))
    }
}
