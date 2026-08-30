import Foundation
import Security

public protocol KeychainReading: Sendable {
    /// Password bytes of the generic-password item with this service name, or nil.
    func genericPassword(service: String) -> Data?
}

/// Reads another app's generic-password item. macOS prompts the user the first time
/// ("Pulse wants to access …"); this reader never writes, updates, or deletes.
///
/// A denied or otherwise unavailable Keychain latches off for the life of the process. Any status
/// beyond `errSecSuccess` and `errSecItemNotFound` — `errSecAuthFailed` when the user clicks Deny,
/// `errSecUserCanceled`, `errSecInteractionNotAllowed` when no UI can be shown — means asking again
/// would only re-prompt, and a polling app asks on every cycle. After one such status every later
/// call returns nil immediately without going back to the Keychain. `errSecItemNotFound` is not
/// latched: it is a normal answer (no such item) and costs the user nothing to repeat.
public final class SecKeychainReader: KeychainReading {
    private let lock = NSLock()
    nonisolated(unsafe) private var unavailable = false

    public init() {}

    public func genericPassword(service: String) -> Data? {
        guard !lock.withLock({ unavailable }) else { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        default:
            lock.withLock { unavailable = true }
            return nil
        }
    }
}
