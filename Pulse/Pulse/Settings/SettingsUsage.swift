import Foundation
import PulseCore

/// The provider row's right-aligned figure (spec §19.3). Pure so it is testable: the row shows
/// the same session percentage the ring does, "—" when there is nothing to show yet, and "Off"
/// the moment the provider is disabled — whatever stale status the store still holds for it.
enum SettingsUsage {
    static func label(status: ProviderStatus?, enabled: Bool) -> String {
        guard enabled else { return "Off" }
        switch status {
        case .live(let snapshot), .stale(let snapshot, _):
            guard let window = snapshot.sessionWindow else { return "—" }
            return "\(Int(window.usedPercent.rounded()))%"
        case .loading, .disconnected, nil:
            return "—"
        }
    }
}
