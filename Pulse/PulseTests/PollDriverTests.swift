import Testing
import Foundation
import PulseCore
@testable import Pulse

@MainActor
@Suite struct PollDriverTests {
    let claude = FakeProvider(.claude, snapshot: Sample.snapshot(session: 31))

    func makeStore() -> UsageStore {
        UsageStore(providers: [claude], enabled: [.claude], http: NoNetworkHTTPClient(), clock: SystemClock())
    }

    @Test func tickFetchesAndReportsViaCallback() async {
        let store = makeStore()
        var ticks = 0
        let driver = PollDriver(store: store, interval: 60, onTick: { ticks += 1 })
        await driver.handleTick()
        #expect(claude.calls == 1)
        #expect(store.statuses[.claude]?.snapshot?.sessionWindow?.usedPercent == 31)
        #expect(ticks == 1)
    }

    /// `handleWake` and `handleNetworkPath` sit out unless the driver is running, so these two
    /// tests have to `start()` it. `start()` kicks a first poll of its own on the main actor's
    /// queue, but that job cannot run until this test suspends — by which time the explicit
    /// `handleTick()` below has already claimed the in-flight flag — so the counts stay exact.
    /// The 60 s interval keeps the timer from firing at all during the test, and
    /// `observingSystemEvents: false` keeps the live `NWPathMonitor` out of it: on a machine
    /// that is online it reports `.satisfied` from a background queue a moment after `start()`,
    /// and once the network has been reported offline that edge is worth a whole extra fetch.
    @Test func wakeForcesARefreshEvenWhenNotDue() async {
        let store = makeStore()
        let driver = PollDriver(store: store, interval: 60, onTick: {})
        driver.start(observingSystemEvents: false)
        defer { driver.stop() }
        await driver.handleTick()
        await driver.handleTick()             // not due: no second fetch
        #expect(claude.calls == 1)
        await driver.handleWake()
        #expect(claude.calls == 2)
    }

    @Test func networkRefreshesOnlyOnTheTransitionToSatisfied() async {
        let store = makeStore()
        let driver = PollDriver(store: store, interval: 60, onTick: {})
        driver.start(observingSystemEvents: false)
        defer { driver.stop() }
        await driver.handleTick()
        await driver.handleNetworkPath(satisfied: true)      // first report, already online at start → no refresh
        #expect(claude.calls == 1)
        await driver.handleNetworkPath(satisfied: false)
        await driver.handleNetworkPath(satisfied: true)      // offline → online: refresh
        #expect(claude.calls == 2)
        await driver.handleNetworkPath(satisfied: true)      // still online: nothing
        #expect(claude.calls == 2)
    }

    @Test func aStoppedDriverIgnoresWakeAndNetworkEvents() async {
        let store = makeStore()
        let driver = PollDriver(store: store, interval: 60, onTick: {})
        driver.start(observingSystemEvents: false)
        await driver.handleTick()
        driver.stop()
        await driver.handleWake()
        await driver.handleNetworkPath(satisfied: false)
        await driver.handleNetworkPath(satisfied: true)
        #expect(claude.calls == 1)
    }

    /// A provider that never answers must not freeze the dock. Every timer fire has to
    /// render what the store holds right now, even while an earlier `tick()` is still in flight.
    @Test func timerRendersEveryFireWhileAPollIsStillInFlight() async {
        let hanging = HangingProvider(.codex)
        let store = UsageStore(providers: [hanging], enabled: [.codex],
                               http: NoNetworkHTTPClient(), clock: SystemClock())
        var ticks = 0
        let driver = PollDriver(store: store, interval: 0.05, onTick: { ticks += 1 })
        driver.start(observingSystemEvents: false)
        let deadline = Date().addingTimeInterval(2)
        while ticks == 0, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(ticks >= 1)
        hanging.release()
        driver.stop()
    }

    /// `observingSystemEvents: false` for the same reason as above — no test installs a live
    /// `NWPathMonitor` or wake observer. It does not weaken the assertion: `start()` sets
    /// `isRunning` and starts the timer either way; only the two system observers are skipped.
    @Test func startAndStopToggleRunning() {
        let driver = PollDriver(store: makeStore(), interval: 60, onTick: {})
        #expect(driver.isRunning == false)
        driver.start(observingSystemEvents: false)
        #expect(driver.isRunning == true)
        driver.stop()
        #expect(driver.isRunning == false)
    }
}
