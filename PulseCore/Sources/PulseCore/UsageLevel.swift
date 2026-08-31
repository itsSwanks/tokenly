import Foundation

/// Urgency band for a used-percentage. Colors are the app's business; Core only names the band.
public enum UsageLevel: Sendable, Equatable, CaseIterable {
    case green, yellow, orange, red

    public init(percent: Double) {
        switch percent {
        case ..<40: self = .green
        case ..<70: self = .yellow
        case ..<90: self = .orange
        default: self = .red
        }
    }

    /// Slow breathing animation applies only while close to, but not at, the limit.
    public static func pulses(percent: Double) -> Bool { percent >= 90 && percent < 100 }

    public static func isExhausted(percent: Double) -> Bool { percent >= 100 }
}
