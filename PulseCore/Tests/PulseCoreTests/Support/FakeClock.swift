import Foundation
@testable import PulseCore

final class FakeClock: PulseClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(now: Date = Date(timeIntervalSince1970: 1_788_038_400)) { _now = now }  // 2026-08-29T21:20:00Z
    var now: Date { lock.withLock { _now } }
    func advance(by seconds: TimeInterval) { lock.withLock { _now = _now.addingTimeInterval(seconds) } }
}
