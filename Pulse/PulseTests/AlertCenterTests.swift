import Testing
import Foundation
import PulseCore
@testable import Pulse

/// Records what would have gone to Notification Center. Locked and `@unchecked Sendable` like
/// the other test doubles: `NotificationPosting` is `Sendable`, and `AlertCenter` may hand it
/// work from whichever isolation domain it happens to be on.
final class RecordingPoster: NotificationPosting, @unchecked Sendable {
    struct Post: Equatable {
        let title: String
        let body: String
        let identifier: String
    }

    private let lock = NSLock()
    private var _posts: [Post] = []
    var posts: [Post] { lock.withLock { _posts } }

    func post(title: String, body: String, identifier: String) {
        lock.withLock { _posts.append(Post(title: title, body: body, identifier: identifier)) }
    }

    private var _warmUps = 0
    var warmUps: Int { lock.withLock { _warmUps } }
    func warmUp() { lock.withLock { _warmUps += 1 } }
}

/// The authorization answer may be cached only when it is definitive: a granted or a real user
/// denial. An errored request (transient — sleep/wake, usernoted hiccup) must stay undecided so
/// the next alert retries, or one bad moment kills notifications until relaunch (the same
/// overbroad-latch disease the Keychain reader had).
struct NotificationAuthorizationPolicyTests {
    @Test func definitiveAnswersAreCached() {
        #expect(UserNotificationPoster.decision(allowed: true, errored: false) == true)
        #expect(UserNotificationPoster.decision(allowed: false, errored: false) == false)
    }

    @Test func erroredRequestsStayUndecided() {
        #expect(UserNotificationPoster.decision(allowed: false, errored: true) == nil)
        #expect(UserNotificationPoster.decision(allowed: true, errored: true) == true)   // trust a grant
    }
}

@MainActor
@Suite struct AlertCenterTests {
    func makeCenter(threshold: Int = 90) -> (AlertCenter, Preferences, RecordingPoster) {
        let prefs = Preferences(defaults: makeTestDefaults(), legacy: nil)
        prefs.alertThreshold = threshold
        let poster = RecordingPoster()
        return (AlertCenter(prefs: prefs, poster: poster), prefs, poster)
    }

    func statuses(session: Double) -> [ProviderID: ProviderStatus] {
        [.claude: .live(Sample.snapshot(session: session))]
    }

    @Test func oneCrossingPostsOnceAndPersistsTheFiredState() {
        let (center, prefs, poster) = makeCenter()
        center.process(statuses: statuses(session: 93), order: [.claude])
        #expect(poster.posts.count == 1)
        #expect(poster.posts.first?.title == "Tokenly")
        #expect(poster.posts.first?.identifier == "claude.Current session.threshold")
        #expect(poster.posts.first?.body == "Claude session at 93%")
        // Persisted, so a relaunch does not re-announce a crossing the user has already seen.
        #expect(prefs.firedAlerts == ["claude.Current session": 90])
    }

    @Test func aSecondProcessOfTheSameCrossingPostsNothing() {
        let (center, _, poster) = makeCenter()
        center.process(statuses: statuses(session: 93), order: [.claude])
        center.process(statuses: statuses(session: 94), order: [.claude])
        #expect(poster.posts.count == 1)
    }

    @Test func reachingTheLimitPostsASecondTimeUnderItsOwnIdentifier() {
        let (center, prefs, poster) = makeCenter()
        center.process(statuses: statuses(session: 93), order: [.claude])
        center.process(statuses: statuses(session: 100), order: [.claude])
        #expect(poster.posts.map(\.identifier) == ["claude.Current session.threshold", "claude.Current session.full"])
        #expect(prefs.firedAlerts == ["claude.Current session": 100])
    }

    @Test func droppingBackBelowTheThresholdRearmsAndClearsTheFiredState() {
        let (center, prefs, poster) = makeCenter()
        center.process(statuses: statuses(session: 93), order: [.claude])
        center.process(statuses: statuses(session: 20), order: [.claude])     // window reset
        #expect(prefs.firedAlerts.isEmpty)
        center.process(statuses: statuses(session: 93), order: [.claude])
        #expect(poster.posts.count == 2)
    }

    @Test func aProviderLeftOutOfTheOrderIsNeverEvaluated() {
        let (center, prefs, poster) = makeCenter()
        center.process(statuses: statuses(session: 100), order: [])
        #expect(poster.posts.isEmpty)
        #expect(prefs.firedAlerts.isEmpty)
    }

    @Test func aStatusWithNoSnapshotIsSkipped() {
        let (center, _, poster) = makeCenter()
        center.process(statuses: [.claude: .loading], order: [.claude])
        center.process(statuses: [.claude: .disconnected(.network("offline"))], order: [.claude])
        #expect(poster.posts.isEmpty)
    }

    @Test func theCenterResumesFromThePersistedFiredState() {
        let defaults = makeTestDefaults()
        let prefs = Preferences(defaults: defaults, legacy: nil)
        prefs.alertThreshold = 90
        prefs.firedAlerts = ["claude.Current session": 90]
        let poster = RecordingPoster()
        // A fresh center over the same preferences: the crossing already fired last run.
        AlertCenter(prefs: prefs, poster: poster).process(statuses: statuses(session: 93), order: [.claude])
        #expect(poster.posts.isEmpty)
    }
}

@MainActor
@Suite struct AlertCenterWarmUpTests {
    @Test func warmUpReachesThePoster() {
        let poster = RecordingPoster()
        let center = AlertCenter(prefs: Preferences(defaults: makeTestDefaults(), legacy: nil), poster: poster)
        center.warmUp()
        #expect(poster.warmUps == 1)
        #expect(poster.posts.isEmpty)   // warming up must not post anything
    }
}

@MainActor
@Suite struct AlertBannerModelTests {
    @Test func alertsQueueInOrderAndAdvancePopsThem() {
        let model = AlertBannerModel()
        model.enqueue(BannerItem(title: "Tokenly", body: "first"))
        model.enqueue(BannerItem(title: "Tokenly", body: "second"))
        #expect(model.hasQueued)
        #expect(model.advance())
        #expect(model.current?.body == "first")
        #expect(model.advance())
        #expect(model.current?.body == "second")
        #expect(!model.hasQueued)
    }

    @Test func advanceOnAnEmptyQueueClearsCurrent() {
        let model = AlertBannerModel()
        model.enqueue(BannerItem(title: "Tokenly", body: "only"))
        #expect(model.advance())
        #expect(!model.advance())
        #expect(model.current == nil)
    }
}

@Suite struct CompositePosterTests {
    final class BannerRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _bodies: [String] = []
        var bodies: [String] { lock.withLock { _bodies } }
        func record(_ body: String) { lock.withLock { _bodies.append(body) } }
    }

    @Test func postReachesBothChannelsAndWarmUpOnlyTheSystem() {
        let system = RecordingPoster()
        let recorder = BannerRecorder()
        let poster = CompositePoster(system: system, banner: { _, body in recorder.record(body) })
        poster.post(title: "Tokenly", body: "Claude session at 93%", identifier: "claude.Current session.threshold")
        #expect(system.posts.count == 1)
        #expect(recorder.bodies == ["Claude session at 93%"])
        poster.warmUp()
        #expect(system.warmUps == 1)
        #expect(recorder.bodies.count == 1)   // warmUp never shows a banner
    }
}
