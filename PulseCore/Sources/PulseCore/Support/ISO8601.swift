import Foundation

/// Providers disagree on fractional seconds and offsets; accept all of them.
public enum ISO8601 {
    // `nonisolated(unsafe)` is safe here: `ISO8601DateFormatter` is documented thread-safe, and
    // these instances are never mutated after init — only `date(from:)` is ever called on them.
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return fractional.date(from: string) ?? plain.date(from: string)
    }
}
