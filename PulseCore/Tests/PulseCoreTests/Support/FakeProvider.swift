import Foundation
@testable import PulseCore

final class FakeProvider: Provider, @unchecked Sendable {
    let id: ProviderID
    private let lock = NSLock()
    private var results: [Result<UsageSnapshot, ProviderError>] = []
    private(set) var calls = 0

    init(_ id: ProviderID) { self.id = id }

    func enqueue(_ snapshot: UsageSnapshot) { lock.withLock { results.append(.success(snapshot)) } }
    func enqueue(_ error: ProviderError) { lock.withLock { results.append(.failure(error)) } }
    /// Keeps returning the last queued result once the queue is drained.
    func repeatLast() { lock.withLock { sticky = results.last } }
    private var sticky: Result<UsageSnapshot, ProviderError>?

    func fetch(using http: any HTTPClient, clock: any PulseClock) async throws(ProviderError) -> UsageSnapshot {
        let result: Result<UsageSnapshot, ProviderError> = lock.withLock {
            calls += 1
            if results.isEmpty { return sticky ?? .failure(.network("no result queued")) }
            let r = results.removeFirst()
            if results.isEmpty { sticky = sticky ?? r }
            return r
        }
        return try result.get()
    }
}

func snapshot(_ pct: Double, at date: Date) -> UsageSnapshot {
    UsageSnapshot(windows: [UsageWindow(kind: .session, label: "Current session", usedPercent: pct, resetsAt: nil)], fetchedAt: date, plan: nil)
}
