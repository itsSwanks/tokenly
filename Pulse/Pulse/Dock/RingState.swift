import Foundation
import PulseCore

/// What a ring shows, derived from a provider's status. Pure so it is testable and
/// so `RingView` has no decisions of its own.
enum RingState: Equatable {
    case loading
    case disconnected
    case value(percent: Double, level: UsageLevel, pulses: Bool, exhausted: Bool, dimmed: Bool)

    init(status: ProviderStatus) {
        switch status {
        case .loading:
            self = .loading
        case .disconnected:
            self = .disconnected
        case .live(let snapshot):
            self = Self.value(from: snapshot, dimmed: false)
        case .stale(let snapshot, _):
            self = Self.value(from: snapshot, dimmed: true)
        }
    }

    private static func value(from snapshot: UsageSnapshot, dimmed: Bool) -> RingState {
        guard let window = snapshot.sessionWindow else { return .disconnected }
        let pct = window.usedPercent
        return .value(percent: pct, level: UsageLevel(percent: pct),
                      pulses: UsageLevel.pulses(percent: pct), exhausted: UsageLevel.isExhausted(percent: pct), dimmed: dimmed)
    }

    var label: String {
        switch self {
        case .loading: ""
        case .disconnected: "—"
        case .value(_, _, _, true, _): "Limit reached"
        case .value(let pct, _, _, false, _): "\(Int(pct.rounded()))%"
        }
    }

    var percent: Double? {
        if case .value(let pct, _, _, _, _) = self { return pct }
        return nil
    }

    var isDimmed: Bool {
        if case .value(_, _, _, _, let dimmed) = self { return dimmed }
        return false
    }
}
