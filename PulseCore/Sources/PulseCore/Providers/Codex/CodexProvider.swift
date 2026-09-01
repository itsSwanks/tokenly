import Foundation

public struct CodexProvider: Provider {
    public let id = ProviderID.codex
    public static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    public static let expiredHint = "Run `codex` in Terminal to refresh your session."
    public static let unsupportedMessage = "This ChatGPT account doesn't report Codex limits."

    private let home: URL

    public init(home: URL = CredentialFile.defaultHome()) {
        self.home = home
    }

    private struct Response: Decodable {
        struct Window: Decodable {
            let used_percent: Double
            let reset_at: Double?
            let reset_after_seconds: Double?
        }
        struct RateLimit: Decodable {
            let primary_window: Window?
            let secondary_window: Window?
        }
        let plan_type: String?
        let rate_limit: RateLimit?
    }

    public func fetch(using http: any HTTPClient, clock: any PulseClock) async throws(ProviderError) -> UsageSnapshot {
        let creds = try CodexCredentials.load(home: home)
        var headers = ["Authorization": "Bearer \(creds.accessToken)", "Accept": "application/json"]
        if let account = creds.accountId { headers["ChatGPT-Account-Id"] = account }
        let response = try await HTTPStatus.send(HTTPRequest(method: .get, url: Self.endpoint, headers: headers), via: http, expiredHint: Self.expiredHint)

        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: response.body)
        } catch {
            throw .unexpectedResponse("codex: body is not JSON")
        }
        // No `rate_limit` but a `plan_type` is a recognizable usage body for an account that
        // doesn't report limits; neither key means the endpoint returned something else entirely.
        guard let limits = decoded.rate_limit else {
            throw decoded.plan_type != nil ? .unsupportedAccount(Self.unsupportedMessage)
                                           : .unexpectedResponse("codex: no known usage windows")
        }

        let now = clock.now
        func resetDate(_ w: Response.Window) -> Date? {
            if let at = w.reset_at { return Date(timeIntervalSince1970: at) }
            if let after = w.reset_after_seconds { return now.addingTimeInterval(after) }
            return nil
        }

        var windows: [UsageWindow] = []
        if let w = limits.primary_window {
            windows.append(UsageWindow(kind: .session, label: "Current session", usedPercent: w.used_percent, resetsAt: resetDate(w)))
        }
        if let w = limits.secondary_window {
            windows.append(UsageWindow(kind: .weekly, label: "Weekly", usedPercent: w.used_percent, resetsAt: resetDate(w)))
        }
        guard !windows.isEmpty else { throw .unsupportedAccount(Self.unsupportedMessage) }
        return UsageSnapshot(windows: windows, fetchedAt: now, plan: decoded.plan_type)
    }
}
