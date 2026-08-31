import Foundation
import Security

public protocol KeychainReading: Sendable {
    /// Password bytes of the generic-password item with this service name, or nil.
    func genericPassword(service: String) -> Data?
}

/// Reads another app's generic-password item. macOS prompts the user the first time
/// ("Pulse wants to access …"); this reader never writes, updates, or deletes.
///
/// An explicit user refusal latches the Keychain off for the life of the process:
/// `errSecAuthFailed` (Deny) and `errSecUserCanceled` mean asking again would only re-prompt,
/// and a polling app asks on every cycle. Every other failure is treated as transient and is
/// retried on the next poll — in particular `errSecInteractionNotAllowed`, which the keychain
/// returns around sleep/wake and the lock screen when it cannot show UI. Latching on those
/// disconnected Claude until relaunch after every Mac sleep (one bad tick flipped the latch,
/// and the loader then fell back to an expired credentials file forever).
/// `errSecItemNotFound` is a normal answer (no such item) and never latches.
public final class SecKeychainReader: KeychainReading {
    private let lock = NSLock()
    nonisolated(unsafe) private var unavailable = false

    public init() {}

    /// True only for statuses that mean the *user* refused — the sole reasons to stop asking.
    static func latches(_ status: OSStatus) -> Bool {
        status == errSecAuthFailed || status == errSecUserCanceled
    }

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
            if Self.latches(status) {
                lock.withLock { unavailable = true }
            }
            return nil
        }
    }
}
