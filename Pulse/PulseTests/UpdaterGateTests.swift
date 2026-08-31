import Testing
@testable import Pulse

@Suite struct UpdaterGateTests {
    @Test func emptyOrMissingFeedDisablesTheUpdater() {
        #expect(UpdaterGate.feedURL(in: [:]) == nil)
        #expect(UpdaterGate.feedURL(in: ["SUFeedURL": ""]) == nil)
        #expect(UpdaterGate.feedURL(in: ["SUFeedURL": "not a url"]) == nil)
    }

    @Test func httpsFeedIsAccepted() {
        #expect(UpdaterGate.feedURL(in: ["SUFeedURL": "https://raw.githubusercontent.com/example/pulse/main/appcast.xml"])?.host == "raw.githubusercontent.com")
        #expect(UpdaterGate.feedURL(in: ["SUFeedURL": "http://example.com/appcast.xml"]) == nil)   // https only
    }
}
