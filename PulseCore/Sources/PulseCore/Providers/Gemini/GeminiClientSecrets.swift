import Foundation

/// The Gemini CLI's own OAuth client, scraped from its installed bundle so we can
/// refresh *its* token. Never hard-code these; they belong to Google's CLI.
public struct GeminiClientSecrets: Sendable, Equatable {
    public let clientId: String
    public let clientSecret: String

    public init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }

    private static let idPattern = try! NSRegularExpression(pattern: #"[0-9]{6,}-[a-z0-9]{8,}\.apps\.googleusercontent\.com"#)
    private static let secretPattern = try! NSRegularExpression(pattern: #"GOCSPX-[A-Za-z0-9_\-]{10,}"#)

    /// Scans every `*.js` file directly inside each directory; first file with both an id and a
    /// secret wins.
    ///
    /// The installed bundle (gemini-cli 0.45.x) embeds more than one `…apps.googleusercontent.com`
    /// id in the same chunk — gcloud's unrelated `CLOUD_SDK_CLIENT_ID`, for instance, appears
    /// earlier in the file than the CLI's own `OAUTH_CLIENT_ID`. Taking the regex's first id match
    /// silently pairs the wrong id with the real secret, and Google's token endpoint rejects that
    /// as `invalid_client`. Real pairs are always declared adjacently in source, so pick the id
    /// nearest the secret instead.
    public static func locate(in directories: [URL]) -> GeminiClientSecrets? {
        let fm = FileManager.default
        for dir in directories {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names.sorted() where name.hasSuffix(".js") {
                guard let text = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) else { continue }
                let range = NSRange(text.startIndex..., in: text)
                let idMatches = idPattern.matches(in: text, range: range)
                guard let secretMatch = secretPattern.firstMatch(in: text, range: range),
                      let nearestId = idMatches.min(by: { abs($0.range.location - secretMatch.range.location) < abs($1.range.location - secretMatch.range.location) }),
                      let idRange = Range(nearestId.range, in: text), let secretRange = Range(secretMatch.range, in: text)
                else { continue }
                return GeminiClientSecrets(clientId: String(text[idRange]), clientSecret: String(text[secretRange]))
            }
        }
        return nil
    }

    /// Directories that hold the resolved `gemini` binary's JS bundle.
    public static func defaultSearchDirectories(home: URL = CredentialFile.defaultHome()) -> [URL] {
        var candidates: [String] = ["/opt/homebrew/bin/gemini", "/usr/local/bin/gemini"]
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm.path) {
            candidates += versions.sorted().reversed().map { nvm.appendingPathComponent("\($0)/bin/gemini").path }
        }
        return candidates.compactMap { path in
            guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            return resolved.deletingLastPathComponent()
        }
    }

    public static func locateInstalled(home: URL = CredentialFile.defaultHome()) -> GeminiClientSecrets? {
        locate(in: defaultSearchDirectories(home: home))
    }
}
