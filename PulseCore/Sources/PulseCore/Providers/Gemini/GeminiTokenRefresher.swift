import Foundation

/// Exchanges the CLI's refresh token for a new access token. The result lives
/// only in memory for this fetch; `oauth_creds.json` is never modified.
public enum GeminiTokenRefresher {
    public static let endpoint = URL(string: "https://oauth2.googleapis.com/token")!

    private struct Response: Decodable { let access_token: String }

    public static func refresh(_ creds: GeminiCredentials, secrets: GeminiClientSecrets, via http: any HTTPClient) async throws(ProviderError) -> String {
        guard let refreshToken = creds.refreshToken else { throw .credentialsExpired(hint: GeminiProvider.expiredHint) }
        // `.alphanumerics` would percent-encode '_' and '-', corrupting the literal
        // "refresh_token" grant value and any real client secret (which contains both). The
        // URL-unreserved set is the correct allowance: those characters pass through unescaped.
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        let form = [
            ("client_id", secrets.clientId), ("client_secret", secrets.clientSecret),
            ("refresh_token", refreshToken), ("grant_type", "refresh_token"),
        ].map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: unreserved) ?? $1)" }.joined(separator: "&")
        let request = HTTPRequest(method: .post, url: endpoint,
                                  headers: ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"],
                                  body: Data(form.utf8))
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch {
            throw .network(error.localizedDescription)
        }
        // A 5xx says Google is having trouble, not that the refresh token is bad — telling the
        // user to sign in again would be wrong, and the store should simply retry. A 4xx (or a
        // success that carries no access_token) is the credential answer.
        switch response.status {
        case 500...599:
            throw .network("HTTP \(response.status)")
        case 200...299:
            guard let decoded = try? JSONDecoder().decode(Response.self, from: response.body) else {
                throw .credentialsExpired(hint: GeminiProvider.expiredHint)
            }
            return decoded.access_token
        default:
            throw .credentialsExpired(hint: GeminiProvider.expiredHint)
        }
    }
}
