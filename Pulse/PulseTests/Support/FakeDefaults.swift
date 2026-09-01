import Foundation

/// A throwaway UserDefaults suite so tests never touch the real preferences.
func makeTestDefaults() -> UserDefaults {
    let name = "pulse-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
