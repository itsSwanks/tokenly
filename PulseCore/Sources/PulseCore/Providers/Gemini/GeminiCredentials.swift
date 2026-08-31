import Foundation

public struct GeminiCredentials: Sendable, Equatable {
    public static let filePath = ".gemini/oauth_creds.json"
    public static let missingHint = "Run `gemini` in Terminal and sign in with Google."
    /// Treat tokens that expire within this many seconds as already expired.
    public static let expiryMargin: TimeInterval = 60

    public let accessToken: String
    public let refreshToken: String?
    public let expiryDate: Date?

    private struct File: Decodable {
        let access_token: String
        let refresh_token: String?
        let expiry_date: Double?
    }

    public init(accessToken: String, refreshToken: String?, expiryDate: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiryDate = expiryDate
    }

    public static func load(home: URL) throws(ProviderError) -> GeminiCredentials {
        let file = try CredentialFile.load(File.self, relativePath: filePath, home: home, hint: missingHint)
        return GeminiCredentials(
            accessToken: file.access_token,
            refreshToken: file.refresh_token,
            expiryDate: file.expiry_date.map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }

    public func isExpired(at now: Date) -> Bool {
        guard let expiryDate else { return false }
        return expiryDate.timeIntervalSince(now) <= Self.expiryMargin
    }
}
