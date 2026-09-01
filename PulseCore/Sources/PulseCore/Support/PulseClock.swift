import Foundation

/// Injectable time source. Named `PulseClock` to avoid clashing with Swift's `Clock`.
public protocol PulseClock: Sendable {
    var now: Date { get }
}

public struct SystemClock: PulseClock {
    public init() {}
    public var now: Date { Date() }
}
