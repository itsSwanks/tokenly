import Foundation
import PulseCore

/// Returns a fixed snapshot; counts calls. Enough for app-level tests.
final class FakeProvider: Provider, @unchecked Sendable {
    let id: ProviderID
    private let lock = NSLock()
    private var _calls = 0
    var snapshot: UsageSnapshot
    var calls: Int { lock.withLock { _calls } }

    init(_ id: ProviderID, snapshot: UsageSnapshot) {
        self.id = id
        self.snapshot = snapshot
    }

    func fetch(using http: any HTTPClient, clock: any PulseClock) async throws(ProviderError) -> UsageSnapshot {
        lock.withLock { _calls += 1 }
        return snapshot
    }
}

/// A fetch that never returns until `release()` is called: models a provider stuck on a slow
/// network call or behind a system prompt, so the driver's render cadence can be observed
/// independently of any poll that is still in flight.
final class HangingProvider: Provider, @unchecked Sendable {
    let id: ProviderID
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    init(_ id: ProviderID) { self.id = id }

    func fetch(using http: any HTTPClient, clock: any PulseClock) async throws(ProviderError) -> UsageSnapshot {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                if released { return true }
                continuation = c
                return false
            }
            if resumeNow { c.resume() }
        }
        throw .network("released")
    }

    /// Unblocks the pending fetch (and any later one) so the test can finish deterministically.
    func release() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            released = true
            defer { continuation = nil }
            return continuation
        }
        pending?.resume()
    }
}
