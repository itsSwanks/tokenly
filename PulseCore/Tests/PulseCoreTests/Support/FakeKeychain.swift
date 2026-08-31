import Foundation
@testable import PulseCore

/// Counts reads so tests can assert the Keychain was never consulted — the on-disk file is
/// meant to answer alone whenever it can, because a real Keychain read costs a macOS prompt.
final class FakeKeychain: KeychainReading, @unchecked Sendable {
    private let lock = NSLock()
    private let items: [String: Data]
    private var _reads = 0

    var reads: Int { lock.withLock { _reads } }

    init(_ items: [String: String] = [:]) { self.items = items.mapValues { Data($0.utf8) } }

    func genericPassword(service: String) -> Data? {
        lock.withLock {
            _reads += 1
            return items[service]
        }
    }
}
