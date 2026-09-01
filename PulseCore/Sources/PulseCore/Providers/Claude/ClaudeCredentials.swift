import Foundation

public struct ClaudeCredentials: Sendable, Equatable {
    public static let filePath = ".claude/.credentials.json"
    public static let keychainService = "Claude Code-credentials"
    public static let missingHint = "Run `claude` in Terminal and sign in."
    public static let expiredHint = "Run `claude` in Terminal to refresh your session."

    public let accessToken: String
    public let scopes: [String]
    public let subscriptionType: String?
    /// nil when the credential source doesn't report an expiry (unknown → treated as not expired).
    public let expiresAt: Date?

    private struct File: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let scopes: [String]?
            let subscriptionType: String?
            /// Milliseconds since epoch.
            let expiresAt: Double?
        }
        let claudeAiOauth: OAuth
    }

    private init(accessToken: String, scopes: [String], subscriptionType: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.scopes = scopes
        self.subscriptionType = subscriptionType
        self.expiresAt = expiresAt
    }

    public func isExpired(at now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    private static func decode(_ data: Data?) -> ClaudeCredentials? {
        guard let data, let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        let oauth = file.claudeAiOauth
        return ClaudeCredentials(
            accessToken: oauth.accessToken,
            scopes: oauth.scopes ?? [],
            subscriptionType: oauth.subscriptionType,
            expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }

    /// File first: reading the Keychain item costs the user a macOS authorization prompt, so it is
    /// consulted only when the on-disk file cannot answer. A file that decodes and is unexpired is
    /// returned without touching the Keychain at all; a file that is missing, undecodable, or
    /// expired falls through to the Keychain, which Claude Code keeps current. The API's own
    /// 401/403 is the scope gate — this loader does not pre-check `scopes`.
    public static func load(home: URL, keychain: any KeychainReading, now: Date) throws(ProviderError) -> ClaudeCredentials {
        let fileCandidate = decode(FileManager.default.contents(atPath: home.appendingPathComponent(filePath).path))
        if let fileCandidate, !fileCandidate.isExpired(at: now) {
            return fileCandidate
        }

        let keychainCandidate = decode(keychain.genericPassword(service: keychainService))
        if let keychainCandidate, !keychainCandidate.isExpired(at: now) {
            return keychainCandidate
        }
        if fileCandidate != nil || keychainCandidate != nil {
            throw .credentialsExpired(hint: expiredHint)
        }
        throw .credentialsMissing(hint: missingHint)
    }
}
