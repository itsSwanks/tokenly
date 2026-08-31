import Observation

/// Transient settings-panel state: what the panel has to show that is *not* a preference and so
/// has no business in `Preferences`, which is UserDefaults and nothing else (spec §8).
@MainActor
@Observable
final class SettingsModel {
    /// macOS accepted the login-item registration but is holding it for the user's approval
    /// (`SMAppService.Status.requiresApproval`). Drives a one-line hint under the toggle.
    var loginItemNeedsApproval = false

    /// Whether the glass sheet is inserted. `SettingsWindowController` flips it inside a
    /// `withAnimation` so `.glassEffectTransition(.materialize)` has an insertion/removal to play
    /// (spec §18.4); the window itself is never faded. Starts `false` so the very first `open()`
    /// is an insertion rather than a sheet that is simply already there.
    var isPresented = false
}
