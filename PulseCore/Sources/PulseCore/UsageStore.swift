import Foundation
import Observation

public struct PollPolicy: Sendable {
    public var interval: TimeInterval
    public var maxBackoff: TimeInterval
    public var staleAfter: TimeInterval
    /// Retry cadence for an account the API will never report numbers for. Nothing the app does
    /// changes that answer, so it is re-checked rarely — only in case the plan itself changes.
    public var unsupportedInterval: TimeInterval

    public init(interval: TimeInterval = 60, maxBackoff: TimeInterval = 300, staleAfter: TimeInterval = 300,
                unsupportedInterval: TimeInterval = 1800) {
        self.interval = interval
        self.maxBackoff = maxBackoff
        self.staleAfter = staleAfter
        self.unsupportedInterval = unsupportedInterval
    }
}

/// Owns every provider's status. Driven entirely by `tick()`; never sleeps or schedules itself.
@MainActor
@Observable
public final class UsageStore {
    public private(set) var statuses: [ProviderID: ProviderStatus] = [:]
    public private(set) var enabled: Set<ProviderID>

    private struct Slot {
        var snapshot: UsageSnapshot?
        var lastError: ProviderError?
        var failures = 0
        var nextAttemptAt = Date.distantPast
        var inFlight = false
    }

    private var slots: [ProviderID: Slot] = [:]
    private let providers: [ProviderID: any Provider]
    private let http: any HTTPClient
    private let clock: any PulseClock
    private let policy: PollPolicy

    public init(providers: [any Provider],
                enabled: Set<ProviderID>? = nil,
                http: any HTTPClient = URLSessionHTTPClient(),
                clock: any PulseClock = SystemClock(),
                policy: PollPolicy = PollPolicy()) {
        let registered = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.providers = registered
        self.http = http
        self.clock = clock
        self.policy = policy
        // An id with no registered provider can never produce a status, so it is dropped here
        // rather than left in `enabled` where it would disagree with `statuses.keys` forever.
        self.enabled = (enabled ?? Set(registered.keys)).filter { registered[$0] != nil }
        for id in self.enabled {
            slots[id] = Slot()
            statuses[id] = .loading
        }
    }

    public func nextAttempt(for id: ProviderID) -> Date? { slots[id]?.nextAttemptAt }

    public func setEnabled(_ id: ProviderID, _ on: Bool) {
        guard providers[id] != nil else { return }
        if on {
            guard !enabled.contains(id) else { return }
            enabled.insert(id)
            slots[id] = Slot()
            statuses[id] = .loading
        } else {
            enabled.remove(id)
            slots[id] = nil
            statuses[id] = nil
        }
    }

    /// Fetch whichever enabled providers are due, all at once, and publish the results.
    public func tick() async {
        let now = clock.now
        for id in enabled { markStaleIfNeeded(id, now: now) }
        let due = enabled
            .filter { id in slots[id].map { !$0.inFlight && now >= $0.nextAttemptAt } ?? false }
            .sorted { $0.rawValue < $1.rawValue }
        await fetch(due)
    }

    /// Fetch immediately, ignoring back-off. `nil` means every enabled provider.
    public func refreshNow(_ id: ProviderID? = nil) async {
        let ids = (id.map { [$0] } ?? Array(enabled)).filter { enabled.contains($0) && slots[$0]?.inFlight == false }
        await fetch(ids)
    }

    private func fetch(_ ids: [ProviderID]) async {
        guard !ids.isEmpty else { return }
        for id in ids { slots[id]?.inFlight = true }
        let http = self.http, clock = self.clock, providers = self.providers
        await withTaskGroup(of: (ProviderID, Result<UsageSnapshot, ProviderError>).self) { group in
            for id in ids {
                guard let provider = providers[id] else { continue }
                group.addTask {
                    do {
                        return (id, .success(try await provider.fetch(using: http, clock: clock)))
                    } catch let error as ProviderError {
                        // Typed-throws inference does not reach into the task-group closure: the
                        // compiler sees `any Error` here rather than `fetch`'s declared
                        // `ProviderError`, so the concrete type is matched explicitly.
                        return (id, .failure(error))
                    } catch {
                        return (id, .failure(.network(String(describing: error))))
                    }
                }
            }
            // Published as each child finishes, not after the whole group: one slow provider must
            // never hold back another provider's already-fetched number.
            for await (id, result) in group { apply(id, result) }
        }
    }

    private func apply(_ id: ProviderID, _ result: Result<UsageSnapshot, ProviderError>) {
        guard var slot = slots[id], enabled.contains(id) else { return }   // disabled mid-flight
        slot.inFlight = false
        let now = clock.now
        switch result {
        case .success(let snapshot):
            slot.snapshot = snapshot
            slot.lastError = nil
            slot.failures = 0
            slot.nextAttemptAt = now.addingTimeInterval(policy.interval)
            statuses[id] = .live(snapshot)
        // Credential-class failures all drop the snapshot and disconnect, but they are not all
        // worth retrying at the same rate: a missing credential is fixed the moment the user signs
        // in (poll at the normal interval so the ring comes back quickly); an expired one usually
        // means a refresh that keeps failing (back off); an unsupported account will not change
        // until the plan does (poll rarely).
        case .failure(let error) where error.isCredentialProblem:
            slot.snapshot = nil
            slot.lastError = error
            switch error {
            case .credentialsExpired:
                slot.failures += 1
                slot.nextAttemptAt = now.addingTimeInterval(
                    min(policy.interval * pow(2, Double(slot.failures - 1)), policy.maxBackoff))
            case .unsupportedAccount:
                slot.failures = 0
                slot.nextAttemptAt = now.addingTimeInterval(policy.unsupportedInterval)
            default:
                slot.failures = 0
                slot.nextAttemptAt = now.addingTimeInterval(policy.interval)
            }
            statuses[id] = .disconnected(error)
        case .failure(let error):
            slot.lastError = error
            slot.failures += 1
            let backoff = min(policy.interval * pow(2, Double(slot.failures - 1)), policy.maxBackoff)
            if case .rateLimited(let retryAfter?) = error {
                slot.nextAttemptAt = now.addingTimeInterval(retryAfter)
            } else {
                slot.nextAttemptAt = now.addingTimeInterval(backoff)
            }
            if let snapshot = slot.snapshot {
                statuses[id] = now.timeIntervalSince(snapshot.fetchedAt) > policy.staleAfter
                    ? .stale(snapshot, lastError: error) : .live(snapshot)
            } else {
                statuses[id] = .disconnected(error)
            }
        }
        slots[id] = slot
    }

    private func markStaleIfNeeded(_ id: ProviderID, now: Date) {
        guard let slot = slots[id], let snapshot = slot.snapshot, let error = slot.lastError,
              now.timeIntervalSince(snapshot.fetchedAt) > policy.staleAfter else { return }
        statuses[id] = .stale(snapshot, lastError: error)
    }
}
