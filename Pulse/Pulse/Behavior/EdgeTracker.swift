import Foundation

/// Auto-hide state machine (spec §4.4). Fed the cursor's distance to the dock's
/// screen edge; decides when to slide out and, after a grace period, back in.
struct EdgeTracker: Equatable {
    enum State: Equatable { case collapsed, expanded }
    enum Transition: Equatable { case expand, collapse }

    private(set) var state: State = .collapsed
    private var graceStartedAt: Date?

    // `Date` arithmetic at real-world (2026-ish) timestamps loses ~2e-8s of precision per
    // `addingTimeInterval` round trip, so a grace period measured as exactly `Motion.collapseGrace`
    // can land a hair under it. An epsilon many orders of magnitude below the ~33ms mouse-poll
    // interval absorbs that without affecting real timing.
    private let graceEpsilon: TimeInterval = 1e-6

    mutating func update(distance: CGFloat, holdOpen: Bool, now: Date) -> Transition? {
        switch state {
        case .collapsed:
            guard distance <= Metrics.edgeProximity else { return nil }
            state = .expanded
            graceStartedAt = nil
            return .expand
        case .expanded:
            if holdOpen || distance <= Metrics.edgeFarAway {
                graceStartedAt = nil
                return nil
            }
            guard let started = graceStartedAt else {
                graceStartedAt = now
                return nil
            }
            guard now.timeIntervalSince(started) >= Motion.collapseGrace - graceEpsilon else { return nil }
            state = .collapsed
            graceStartedAt = nil
            return .collapse
        }
    }

    mutating func force(_ newState: State) {
        state = newState
        graceStartedAt = nil
    }
}
