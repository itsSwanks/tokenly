import Testing
import Foundation
import ServiceManagement
@testable import Pulse

@MainActor
@Suite struct RepositoryURLTests {
    @Test func anAbsentOrEmptyValueIsNoLink() {
        #expect(SettingsWindowController.repositoryURL(from: nil) == nil)
        #expect(SettingsWindowController.repositoryURL(from: [:]) == nil)
        #expect(SettingsWindowController.repositoryURL(from: ["PulseRepositoryURL": ""]) == nil)
        #expect(SettingsWindowController.repositoryURL(from: ["PulseRepositoryURL": "   "]) == nil)
    }

    @Test func plainHTTPIsRejected() {
        // Anything but https is "not set": the About link is the one place Pulse sends a user
        // out to the network, and it is not going to do that in the clear.
        #expect(SettingsWindowController.repositoryURL(from: ["PulseRepositoryURL": "http://example.com/pulse"]) == nil)
        #expect(SettingsWindowController.repositoryURL(from: ["PulseRepositoryURL": "https:///no-host"]) == nil)
    }

    @Test func aValidHTTPSURLIsReturned() {
        let url = SettingsWindowController.repositoryURL(from: ["PulseRepositoryURL": " https://example.com/pulse "])
        #expect(url == URL(string: "https://example.com/pulse"))
    }
}

@Suite struct LoginItemTests {
    /// `.requiresApproval` is its own answer, not "off": the registration succeeded and macOS
    /// is only waiting for the user to allow it, so the toggle stays on and the panel explains.
    @Test func statusMapsToTheThreeAnswersTheToggleNeeds() {
        #expect(LoginItem.outcome(for: .enabled) == .on)
        #expect(LoginItem.outcome(for: .requiresApproval) == .needsApproval)
        #expect(LoginItem.outcome(for: .notRegistered) == .off)
        #expect(LoginItem.outcome(for: .notFound) == .off)
    }
}
