import Foundation

/// Anthropic routes requests without a `claude-code/<version>` User-Agent to a
/// heavily rate-limited bucket, so we mirror the installed CLI's version.
public enum ClaudeCLIVersion {
    public static let fallbackVersion = "2.1.251"

    /// Characters a version token may contain. Anything else in the CLI's output — a stray `\r`,
    /// ANSI escapes, quotes — is dropped rather than pasted into a request header.
    private static let allowed = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.-")

    static func userAgent(versionOutput: String?) -> String {
        let token = versionOutput?
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .first
            .map { String($0.unicodeScalars.filter(allowed.contains)) }
        guard let token, !token.isEmpty else { return "claude-code/\(fallbackVersion)" }
        return "claude-code/\(token)"
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: [String: String] = [:]

    /// The User-Agent to send for this `home`, running `claude --version` at most once per home
    /// for the life of the process: spawning a subprocess on every poll would be wasteful, and the
    /// installed CLI cannot change version underneath a running app in any way that matters here.
    /// Keyed by home path so an alternate home (tests) is resolved independently.
    public static func userAgent(home: URL = CredentialFile.defaultHome()) -> String {
        let key = home.path
        if let hit = lock.withLock({ cached[key] }) { return hit }
        let value = uncachedUserAgent(home: home)
        lock.withLock { cached[key] = value }
        return value
    }

    /// Runs `claude --version` from the usual install locations, falling back to
    /// `fallbackVersion` when no installed CLI answers.
    static func uncachedUserAgent(home: URL) -> String {
        let candidates = [
            home.appendingPathComponent(".local/bin/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["--version"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { continue }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0, let output = String(data: data, encoding: .utf8), !output.isEmpty {
                return userAgent(versionOutput: output)
            }
        }
        return userAgent(versionOutput: nil)
    }
}
