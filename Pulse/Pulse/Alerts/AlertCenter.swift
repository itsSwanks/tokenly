import Foundation
import os
import UserNotifications
import PulseCore

protocol NotificationPosting: Sendable {
    func post(title: String, body: String, identifier: String)
}

/// Real delivery through Notification Center. Authorization is requested lazily,
/// the first time something needs to be shown (spec §7).
///
/// The answer is then remembered. `requestAuthorization` is cheap only *after* the user has
/// decided; calling it on every alert is a round trip to `usernoted` for a question already
/// answered, and — where the user declined — a standing invitation for the system to reconsider.
/// A class, not a struct, so the one `AlertCenter` holds keeps that answer for the process's life.
final class UserNotificationPoster: NotificationPosting {
    /// `nil` until the first request completes. Lock-guarded because the system answers on its
    /// own queue: a plain `var` here would be a data race under strict concurrency.
    private let granted = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    func post(title: String, body: String, identifier: String) {
        switch granted.withLock({ $0 }) {
        case .some(true):
            deliverNotification(title: title, body: body, identifier: identifier)
        case .some(false):
            return
        case nil:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [granted] allowed, _ in
                granted.withLock { $0 = allowed }
                guard allowed else { return }
                // `requestAuthorization`'s completion handler is `@Sendable`, and
                // `UNUserNotificationCenter` is not `Sendable`, so nothing but the (Sendable)
                // strings and the lock may be captured here — hence the free function below
                // re-fetching the shared center rather than a method call on `self`.
                deliverNotification(title: title, body: body, identifier: identifier)
            }
        }
    }
}

/// Posts one notification, re-fetching the (shared, thread-safe per Apple's docs)
/// `UNUserNotificationCenter` inside the `Task` so nothing non-`Sendable` crosses into it.
private func deliverNotification(title: String, body: String, identifier: String) {
    Task {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}

/// Runs the evaluator over every enabled provider each tick and persists its state.
@MainActor
final class AlertCenter {
    private let prefs: Preferences
    private let poster: any NotificationPosting
    private var evaluator: AlertEvaluator

    init(prefs: Preferences, poster: any NotificationPosting = UserNotificationPoster()) {
        self.prefs = prefs
        self.poster = poster
        evaluator = AlertEvaluator(fired: prefs.firedAlerts)
    }

    func process(statuses: [ProviderID: ProviderStatus], order: [ProviderID]) {
        let before = evaluator.fired
        for id in order {
            guard let snapshot = statuses[id]?.snapshot else { continue }
            for event in evaluator.evaluate(provider: id, windows: snapshot.windows, threshold: prefs.alertThreshold) {
                let kind = if case .limitReached = event.kind { "full" } else { "threshold" }
                poster.post(title: "Pulse", body: AlertMessage.body(for: event, now: Date()), identifier: "\(id.rawValue).\(event.windowLabel).\(kind)")
            }
        }
        if evaluator.fired != before { prefs.firedAlerts = evaluator.fired }
    }
}
