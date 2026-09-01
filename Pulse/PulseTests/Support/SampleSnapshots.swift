import Foundation
import PulseCore

enum Sample {
    static let now = Date(timeIntervalSince1970: 1_788_038_400)   // 2026-08-29T21:20:00Z

    static func snapshot(session: Double, weekly: Double? = nil, fetchedAt: Date = now, plan: String? = "max") -> UsageSnapshot {
        var windows = [UsageWindow(kind: .session, label: "Current session", usedPercent: session, resetsAt: now.addingTimeInterval(51 * 60))]
        if let weekly {
            windows.append(UsageWindow(kind: .weekly, label: "All models", usedPercent: weekly, resetsAt: now.addingTimeInterval(5 * 86_400)))
        }
        return UsageSnapshot(windows: windows, fetchedAt: fetchedAt, plan: plan)
    }
}
