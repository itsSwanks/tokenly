import PulseCore

struct SettingsActions {
    var reorder: ([ProviderID]) -> Void = { _ in }
    var setEnabled: (ProviderID, Bool) -> Void = { _, _ in }
    var setThreshold: (Int) -> Void = { _ in }
    var setEdge: (ScreenEdge) -> Void = { _ in }
    var setDockStyle: (DockStyle) -> Void = { _ in }
    var setAutoHide: (Bool) -> Void = { _ in }
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var setAutoUpdate: (Bool) -> Void = { _ in }
    var checkForUpdates: () -> Void = {}
    var quit: () -> Void = {}
    var close: () -> Void = {}
}
