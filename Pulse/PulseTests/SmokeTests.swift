import Testing
import PulseCore
@testable import Pulse

@Suite struct SmokeTests {
    @Test func appModuleAndCoreLink() {
        #expect(ProviderID.allCases.count == 3)
    }
}
