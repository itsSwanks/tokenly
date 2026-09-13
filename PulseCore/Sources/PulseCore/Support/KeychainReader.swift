import Foundation

public protocol KeychainReading: Sendable {
    /// Password bytes of the generic-password item with this service name, or nil.
    func genericPassword(service: String) -> Data?
}

/// Reads another app's generic-password item by running `/usr/bin/security`, the tool Claude Code
/// itself uses to write and read its item. An item created by that tool carries the tool on its
/// access list, so the read completes with no authorization prompt.
///
/// Calling the Security framework directly from this process used to raise macOS's "wants to use
/// your confidential information" password dialog instead. The app is ad-hoc signed, so its
/// identity is the cdhash of one exact build: *Always Allow* bound to that build and every update
/// or rebuild asked again, *Allow* asked again on the next poll, and *Deny* left the loader with
/// nothing but an expired credentials file — reported as an expired session that running
/// `claude` could never refresh.
///
/// This reader never writes, updates, or deletes. A tool that does not return (a keychain-unlock
/// dialog nobody answers) is abandoned after `timeout` so a poll can never wedge on it.
public struct SecurityToolKeychainReader: KeychainReading {
    private let tool: URL
    private let timeout: TimeInterval

    public init(tool: URL = URL(fileURLWithPath: "/usr/bin/security"), timeout: TimeInterval = 10) {
        self.tool = tool
        self.timeout = timeout
    }

    public func genericPassword(service: String) -> Data? {
        let process = Process()
        process.executableURL = tool
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        // Drain before waiting: a pipe left unread fills and blocks the child.
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        // `-w` terminates the secret with a newline that is not part of it.
        return output.last == UInt8(ascii: "\n") ? output.dropLast() : output
    }
}
