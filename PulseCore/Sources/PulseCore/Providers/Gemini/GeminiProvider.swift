import Foundation

public struct GeminiProvider: Provider {
    public let id = ProviderID.gemini
    public static let quotaEndpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!
    public static let loadEndpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    public static let expiredHint = "Run `gemini` in Terminal to refresh your Google sign-in."
    public static let unsupportedMessage = "Gemini CLI quota isn't available for this account."
    public static let ringLabel = "Gemini CLI quota"
    /// Ring window plus at most this many extra buckets in the callout.
    public static let extraBuckets = 2

    private let home: URL
    private let secrets: GeminiClientSecrets?
    private let locateSecrets: @Sendable (URL) -> GeminiClientSecrets?

    /// `secrets` wins when given; otherwise `locateSecrets(home)` runs only when a refresh is needed.
    public init(home: URL = CredentialFile.defaultHome(),
                secrets: GeminiClientSecrets? = nil,
                locateSecrets: @escaping @Sendable (URL) -> GeminiClientSecrets? = { GeminiClientSecrets.locateInstalled(home: $0) }) {
        self.home = home
        self.secrets = secrets
        self.locateSecrets = locateSecrets
    }

    private struct QuotaResponse: Decodable {
        struct Bucket: Decodable {
            let modelId: String?
            let remainingFraction: Double?
            let resetTime: String?
        }
        let buckets: [Bucket]?
        let quotaBuckets: [Bucket]?
        var all: [Bucket] { buckets ?? quotaBuckets ?? [] }
    }

    private struct LoadResponse: Decodable {
        struct Tier: Decodable { let id: String? }
        struct Project: Decodable { let id: String? }
        let cloudaicompanionProject: ProjectRef?
        let currentTier: Tier?

        enum ProjectRef: Decodable {
            case id(String)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) { self = .id(s); return }
                let p = try c.decode(Project.self)
                self = .id(p.id ?? "")
            }
            var value: String { switch self { case .id(let s): return s } }
        }
    }

    public func fetch(using http: any HTTPClient, clock: any PulseClock) async throws(ProviderError) -> UsageSnapshot {
        let creds = try GeminiCredentials.load(home: home)
        var token = creds.accessToken
        if creds.isExpired(at: clock.now) {
            guard let secrets = secrets ?? locateSecrets(home) else {
                throw .credentialsExpired(hint: Self.expiredHint)
            }
            token = try await GeminiTokenRefresher.refresh(creds, secrets: secrets, via: http)
        }
        let headers = ["Authorization": "Bearer \(token)", "Content-Type": "application/json", "Accept": "application/json"]

        var plan: String? = nil
        var response = try await sendQuota(body: Data("{}".utf8), headers: headers, via: http)
        if response.status == 400, String(decoding: response.body, as: UTF8.self).localizedCaseInsensitiveContains("project") {
            let load = HTTPRequest(method: .post, url: Self.loadEndpoint, headers: headers,
                                   body: Data(#"{"metadata":{"ideType":"GEMINI_CLI","pluginType":"GEMINI"}}"#.utf8))
            let loaded = try await HTTPStatus.send(load, via: http, expiredHint: Self.expiredHint)
            guard let decoded = try? JSONDecoder().decode(LoadResponse.self, from: loaded.body),
                  let project = decoded.cloudaicompanionProject?.value, !project.isEmpty else {
                throw .unsupportedAccount(Self.unsupportedMessage)
            }
            plan = decoded.currentTier?.id
            // Built by the serializer rather than interpolated: the project id comes from a
            // response body, and a quote or backslash in it would otherwise produce broken JSON.
            guard let body = try? JSONSerialization.data(withJSONObject: ["project": project]) else {
                throw .unexpectedResponse("gemini: project id is not encodable")
            }
            response = try await sendQuota(body: body, headers: headers, via: http)
        }
        guard (200...299).contains(response.status) else { throw .network("HTTP \(response.status)") }

        let decoded: QuotaResponse
        do {
            decoded = try JSONDecoder().decode(QuotaResponse.self, from: response.body)
        } catch {
            throw .unexpectedResponse("gemini: body is not JSON")
        }
        let buckets = decoded.all
            .compactMap { b -> (model: String, used: Double, reset: Date?)? in
                guard let remaining = b.remainingFraction else { return nil }
                let used = (((1 - remaining) * 100) * 10).rounded() / 10   // one decimal; avoids 18.000000000000004
                return (b.modelId ?? "model", used, ISO8601.date(from: b.resetTime))
            }
            .sorted { $0.used > $1.used }
        guard let ring = buckets.first else { throw .unsupportedAccount(Self.unsupportedMessage) }

        var windows = [UsageWindow(kind: .session, label: Self.ringLabel, usedPercent: ring.used, resetsAt: ring.reset)]
        for b in buckets.dropFirst().prefix(Self.extraBuckets) {
            windows.append(UsageWindow(kind: .other(b.model), label: b.model, usedPercent: b.used, resetsAt: b.reset))
        }
        return UsageSnapshot(windows: windows, fetchedAt: clock.now, plan: plan)
    }

    /// Like `HTTPStatus.send` but lets a 400 through so the caller can inspect it.
    private func sendQuota(body: Data, headers: [String: String], via http: any HTTPClient) async throws(ProviderError) -> HTTPResponse {
        let request = HTTPRequest(method: .post, url: Self.quotaEndpoint, headers: headers, body: body)
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch {
            throw .network(error.localizedDescription)
        }
        switch response.status {
        case 401: throw .credentialsExpired(hint: Self.expiredHint)
        // Google returns 403 SUBSCRIPTION_REQUIRED for accounts without Code Assist
        // entitlement — an account-type problem, not an expired or invalid credential, so it
        // maps to unsupportedAccount instead.
        case 403: throw .unsupportedAccount(Self.unsupportedMessage)
        case 429: throw .rateLimited(retryAfter: response.header("Retry-After").flatMap(TimeInterval.init))
        default: return response
        }
    }
}
