import Foundation
import os
import UserNotifications
import PulseCore

protocol NotificationPosting: Sendable {
    func post(title: String, body: String, identifier: String)
    /// Ask for notification authorization now, posting nothing. Called once at launch so the
    /// permission prompt arrives up-front and the app appears in System Settings → Notifications
    /// immediately — lazy-only registration meant neither happened until the first alert, which
    /// at a 95% threshold could be never (and read as "notifications are broken").
    func warmUp()
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

    /// What to remember from a `requestAuthorization` answer. Only a definitive answer is
    /// cached: a grant, or a real denial. An errored request stays `nil` so the next alert asks
    /// again — caching an error as "denied" killed notifications for the process on one
    /// transient failure, the same overbroad latch the Keychain reader had.
    static func decision(allowed: Bool, errored: Bool) -> Bool? {
        allowed ? true : (errored ? nil : false)
    }

    func warmUp() {
        guard granted.withLock({ $0 }) == nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [granted] allowed, error in
            granted.withLock { $0 = Self.decision(allowed: allowed, errored: error != nil) }
        }
    }

    func post(title: String, body: String, identifier: String) {
        switch granted.withLock({ $0 }) {
        case .some(true):
            deliverNotification(title: title, body: body, identifier: identifier)
        case .some(false):
            return
        case nil:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [granted] allowed, error in
                granted.withLock { $0 = Self.decision(allowed: allowed, errored: error != nil) }
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

    /// Request notification authorization up-front (no-op once decided). Called at launch.
    func warmUp() { poster.warmUp() }

    func process(statuses: [ProviderID: ProviderStatus], order: [ProviderID]) {
        let before = evaluator.fired
        for id in order {
            guard let snapshot = statuses[id]?.snapshot else { continue }
            for event in evaluator.evaluate(provider: id, windows: snapshot.windows, threshold: prefs.alertThreshold) {
                let kind = if case .limitReached = event.kind { "full" } else { "threshold" }
                poster.post(title: "Tokenly", body: AlertMessage.body(for: event, now: Date()), identifier: "\(id.rawValue).\(event.windowLabel).\(kind)")
            }
        }
        if evaluator.fired != before { prefs.firedAlerts = evaluator.fired }
    }
}
