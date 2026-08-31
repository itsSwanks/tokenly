import Testing
import Security
@testable import PulseCore

/// The latch exists so a Deny never re-prompts a polling app — but only an explicit user
/// refusal may latch. Transient statuses (the keychain briefly unable to show UI around
/// sleep/wake or the lock screen) must stay retryable, or one bad tick disconnects Claude
/// until relaunch (the post-sleep bug).
struct KeychainLatchTests {
    @Test func onlyExplicitUserRefusalLatches() {
        #expect(SecKeychainReader.latches(errSecAuthFailed))
        #expect(SecKeychainReader.latches(errSecUserCanceled))
    }

    @Test func transientAndNormalStatusesDoNotLatch() {
        #expect(!SecKeychainReader.latches(errSecInteractionNotAllowed))   // sleep/wake, lock screen
        #expect(!SecKeychainReader.latches(errSecItemNotFound))            // no such item — normal
        #expect(!SecKeychainReader.latches(errSecSuccess))
        #expect(!SecKeychainReader.latches(errSecNotAvailable))
        #expect(!SecKeychainReader.latches(OSStatus(-1)))                  // unknown → retry next tick
    }
}
