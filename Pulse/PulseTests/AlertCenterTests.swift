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
}

@MainActor
@Suite struct AlertCenterTests {
    func makeCenter(threshold: Int = 90) -> (AlertCenter, Preferences, RecordingPoster) {
        let prefs = Preferences(defaults: makeTestDefaults())
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
        #expect(poster.posts.first?.title == "Pulse")
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
        let prefs = Preferences(defaults: defaults)
        prefs.alertThreshold = 90
        prefs.firedAlerts = ["claude.Current session": 90]
        let poster = RecordingPoster()
        // A fresh center over the same preferences: the crossing already fired last run.
        AlertCenter(prefs: prefs, poster: poster).process(statuses: statuses(session: 93), order: [.claude])
        #expect(poster.posts.isEmpty)
    }
}
