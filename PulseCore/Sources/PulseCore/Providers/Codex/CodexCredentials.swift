import Foundation

public struct CodexCredentials: Sendable, Equatable {
    public static let filePath = ".codex/auth.json"
    public static let missingHint = "Run `codex` in Terminal and sign in with ChatGPT."

    public let accessToken: String
    public let accountId: String?

    private struct File: Decodable {
        struct Tokens: Decodable {
            let access_token: String
            let account_id: String?
        }
        let tokens: Tokens?
    }

    public static func load(home: URL) throws(ProviderError) -> CodexCredentials {
        let file = try CredentialFile.load(File.self, relativePath: filePath, home: home, hint: missingHint)
        guard let tokens = file.tokens else { throw .credentialsMissing(hint: missingHint) }
        return CodexCredentials(accessToken: tokens.access_token, accountId: tokens.account_id)
    }
}
