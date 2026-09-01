import Foundation

public struct ClaudeProvider: Provider {
    public let id = ProviderID.claude
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let expiredHint = ClaudeCredentials.expiredHint
    public static let unsupportedMessage = "This Claude account doesn't report usage limits."

    private let home: URL
    private let keychain: any KeychainReading
    private let userAgent: String

    public init(home: URL = CredentialFile.defaultHome(),
                keychain: any KeychainReading = SecKeychainReader(),
                userAgent: String? = nil) {
        self.home = home
        self.keychain = keychain
        self.userAgent = userAgent ?? ClaudeCLIVersion.userAgent(home: home)
    }

    // The live API nests undeclared fields inside each window (limit_dollars, locked_reason,
    // remaining_dollars, used_dollars) alongside top-level buckets with opaque names; `Decodable`
    // ignores all of that. Only the fields read below are declared.
    private struct Response: Decodable {
        struct Window: Decodable {
            let utilization: Double
            let resets_at: String?
        }

        /// One entry of the parallel `limits` array. The fixed `five_hour`/`seven_day` keys carry
        /// the plan-wide windows; `limits` is where per-model ("scoped") allowances appear.
        struct Limit: Decodable {
            struct Scope: Decodable {
                struct Model: Decodable { let display_name: String? }
                let model: Model?
            }
            let kind: String?
            let is_active: Bool?
            let percent: Double?
            let resets_at: String?
            let scope: Scope?
        }

        /// Presence marker only — the value is deliberately not decoded. Its shape is unstable and
        /// nothing here reads it; it exists so a body carrying it still counts as a known Claude
        /// usage shape rather than an unrecognized one.
        struct Present: Decodable {
            init(from decoder: Decoder) throws {}
        }

        let five_hour: Window?
        let seven_day: Window?
        let seven_day_opus: Window?
        let limits: [Limit]?
        let extra_usage: Present?
    }

    public func fetch(using http: any HTTPClient, clock: any PulseClock) async throws(ProviderError) -> UsageSnapshot {
        let creds = try ClaudeCredentials.load(home: home, keychain: keychain, now: clock.now)
        let request = HTTPRequest(method: .get, url: Self.endpoint, headers: [
            "Authorization": "Bearer \(creds.accessToken)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": userAgent,
            "Accept": "application/json",
        ])
        let response = try await HTTPStatus.send(request, via: http, expiredHint: Self.expiredHint)

        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: response.body)
        } catch {
            throw .unexpectedResponse("claude: body is not JSON")
        }

        var windows: [UsageWindow] = []
        if let w = decoded.five_hour {
            windows.append(UsageWindow(kind: .session, label: "Current session", usedPercent: w.utilization, resetsAt: ISO8601.date(from: w.resets_at)))
        }
        if let w = decoded.seven_day {
            windows.append(UsageWindow(kind: .weekly, label: "All models", usedPercent: w.utilization, resetsAt: ISO8601.date(from: w.resets_at)))
        }
        if let w = decoded.seven_day_opus {
            windows.append(UsageWindow(kind: .other("opus"), label: "Opus weekly", usedPercent: w.utilization, resetsAt: ISO8601.date(from: w.resets_at)))
        }
        // Per-model weekly allowances live in `limits` rather than under a fixed key, because the
        // model they apply to changes. Only active scoped entries are shown; the array also
        // restates the plan-wide session/weekly windows, which are already mapped above.
        for limit in decoded.limits ?? [] where limit.kind == "weekly_scoped" && limit.is_active == true {
            guard let percent = limit.percent else { continue }
            let name = limit.scope?.model?.display_name ?? "scoped"
            windows.append(UsageWindow(kind: .other(name), label: "\(name) weekly", usedPercent: percent,
                                       resetsAt: ISO8601.date(from: limit.resets_at)))
        }

        guard !windows.isEmpty else {
            // A body carrying none of the keys this provider knows about is a shape change worth
            // surfacing as such; one that carries them but yields no window is an account the API
            // simply doesn't report numbers for.
            let recognized = decoded.five_hour != nil || decoded.seven_day != nil || decoded.seven_day_opus != nil
                || decoded.limits != nil || decoded.extra_usage != nil
            throw recognized ? .unsupportedAccount(Self.unsupportedMessage)
                             : .unexpectedResponse("claude: no known usage windows")
        }
        return UsageSnapshot(windows: windows, fetchedAt: clock.now, plan: creds.subscriptionType)
    }
}
