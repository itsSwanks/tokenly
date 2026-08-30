import Foundation
import PulseCore

struct AlertEvent: Equatable {
    enum Kind: Equatable { case threshold(Int), limitReached }
    let provider: ProviderID
    let windowLabel: String
    let kind: Kind
    let percent: Double
    let resetsAt: Date?
}

/// Pure crossing detector (spec §7). `fired` maps "provider.window" → the level
/// last fired (the threshold value, or 100). Dropping below the threshold re-arms.
struct AlertEvaluator {
    var fired: [String: Double]

    mutating func evaluate(provider: ProviderID, windows: [UsageWindow], threshold: Int) -> [AlertEvent] {
        var events: [AlertEvent] = []
        for w in windows {
            let key = "\(provider.rawValue).\(w.label)"
            let pct = w.usedPercent
            if pct < Double(threshold) {
                fired[key] = nil
                continue
            }
            let last = fired[key]
            if pct >= 100 {
                if last != 100 {
                    events.append(AlertEvent(provider: provider, windowLabel: w.label, kind: .limitReached, percent: pct, resetsAt: w.resetsAt))
                    fired[key] = 100
                }
            } else if last == nil {
                events.append(AlertEvent(provider: provider, windowLabel: w.label, kind: .threshold(threshold), percent: pct, resetsAt: w.resetsAt))
                fired[key] = Double(threshold)
            }
        }
        return events
    }
}

enum AlertMessage {
    static func body(for event: AlertEvent, now: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        let name = event.provider.displayName
        let noun: String = switch event.windowLabel {
        case "Current session": "session"
        case "Weekly", "All models": "weekly limit"
        case "Gemini CLI quota": "CLI quota"
        default: event.windowLabel.lowercased()
        }
        switch event.kind {
        case .threshold:
            return "\(name) \(noun) at \(Int(event.percent.rounded()))%"
        case .limitReached:
            let subject = noun.hasSuffix("limit") ? noun : "\(noun) limit"
            let reset = ResetFormatter.text(resetsAt: event.resetsAt, now: now, timeZone: timeZone, locale: locale)
            // No reset time known: the formatter's em dash placeholder would read as
            // "Claude session limit reached — —" in a notification.
            guard reset != "—" else { return "\(name) \(subject) reached" }
            let lowered = reset.prefix(1).lowercased() + reset.dropFirst()
            return "\(name) \(subject) reached — \(lowered)"
        }
    }
}
