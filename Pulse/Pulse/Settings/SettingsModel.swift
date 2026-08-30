import Observation

/// Transient settings-panel state: what the panel has to show that is *not* a preference and so
/// has no business in `Preferences`, which is UserDefaults and nothing else (spec §8).
@MainActor
@Observable
final class SettingsModel {
    /// macOS accepted the login-item registration but is holding it for the user's approval
    /// (`SMAppService.Status.requiresApproval`). Drives a one-line hint under the toggle.
    var loginItemNeedsApproval = false
}
