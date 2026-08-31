import Foundation

public enum ResetFormatter {
    /// "—" · "Resets in <1 min" · "Resets in 51 min" · "Resets in 2 h 05 min" · "Resets Thu 04:50"
    public static func text(resetsAt: Date?, now: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        guard let resetsAt else { return "—" }
        let remaining = resetsAt.timeIntervalSince(now)
        if remaining < 60 { return "Resets in <1 min" }
        let totalMinutes = Int((remaining / 60).rounded(.up))
        if remaining < 3600 { return "Resets in \(totalMinutes) min" }
        if remaining < 86_400 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return "Resets in \(hours) h \(String(format: "%02d", minutes)) min"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE HH:mm"
        return "Resets \(formatter.string(from: resetsAt))"
    }
}
