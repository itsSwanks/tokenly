import Foundation
import Testing
@testable import PulseCore

/// Exercises the real login keychain through `/usr/bin/security`, the way the app does. Each item
/// is created by that same tool — exactly how Claude Code creates its own — so the read must
/// complete without any authorization prompt. Every test uses a unique service name and removes
/// its item afterwards, so nothing of the user's is touched and nothing is left behind.
struct SecurityToolKeychainReaderTests {
    @discardableResult
    private static func security(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test func readsItemCreatedByTheSecurityToolWithoutPrompt() throws {
        let service = "tokenly-test-\(UUID().uuidString)"
        let secret = #"{"claudeAiOauth":{"accessToken":"tok-keychain"}}"#
        let hex = secret.utf8.map { String(format: "%02x", $0) }.joined()
        try #require(Self.security(["add-generic-password", "-U", "-a", "tokenly-test", "-s", service, "-X", hex]) == 0)
        defer { _ = try? Self.security(["delete-generic-password", "-s", service]) }

        // Byte-exact: the tool terminates the secret with a newline that is not part of it.
        #expect(SecurityToolKeychainReader().genericPassword(service: service) == Data(secret.utf8))
    }

    @Test func missingItemIsNil() {
        let service = "tokenly-test-missing-\(UUID().uuidString)"
        #expect(SecurityToolKeychainReader().genericPassword(service: service) == nil)
    }

    /// A tool that never returns (a keychain-unlock dialog nobody answers) must not wedge the
    /// poll: the read gives up as nil after the timeout instead of blocking the fetch forever.
    @Test func hungToolIsAbandonedAfterTimeout() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let stub = dir.appendingPathComponent("security")
        try "#!/bin/sh\nexec sleep 30\n".write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)

        let started = Date()
        let reader = SecurityToolKeychainReader(tool: stub, timeout: 0.5)
        #expect(reader.genericPassword(service: "irrelevant") == nil)
        #expect(Date().timeIntervalSince(started) < 5)
    }
}
