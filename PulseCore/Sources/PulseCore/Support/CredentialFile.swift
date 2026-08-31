import Foundation

/// Reads a CLI's credential file relative to `home`. Any failure — missing,
/// unreadable, malformed — is `credentialsMissing`, because from the user's
/// point of view the fix is the same: sign in with the CLI again.
public enum CredentialFile {
    public static func load<T: Decodable>(_ type: T.Type, relativePath: String, home: URL, hint: String) throws(ProviderError) -> T {
        let url = home.appendingPathComponent(relativePath)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw .credentialsMissing(hint: hint)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw .credentialsMissing(hint: hint)
        }
    }

    public static func defaultHome() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
    }
}
