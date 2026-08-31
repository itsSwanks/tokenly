import Foundation
import Testing
@testable import PulseCore

@Suite struct ClaudeCredentialsTests {
    let json = #"{"claudeAiOauth":{"accessToken":"tok-claude","refreshToken":"r","expiresAt":1756500000000,"scopes":["user:inference","user:profile"],"subscriptionType":"max"}}"#
    let now = Date(timeIntervalSince1970: 1_756_499_000)   // 1000s before `json`'s expiresAt

    @Test func loadsFromFile() throws {
        let home = TempHome(); defer { home.remove() }
        home.write(json, at: ".claude/.credentials.json")
        let creds = try ClaudeCredentials.load(home: home.url, keychain: FakeKeychain(), now: now)
        #expect(creds.accessToken == "tok-claude")
        #expect(creds.subscriptionType == "max")
        #expect(creds.scopes.contains("user:profile"))
    }

    @Test func fallsBackToKeychainWhenFileMissing() throws {
        let home = TempHome(); defer { home.remove() }
        let creds = try ClaudeCredentials.load(home: home.url, keychain: FakeKeychain(["Claude Code-credentials": json]), now: now)
        #expect(creds.accessToken == "tok-claude")
    }

    @Test func missingEverywhereIsCredentialsMissing() {
        let home = TempHome(); defer { home.remove() }
        #expect(throws: ProviderError.credentialsMissing(hint: "Run `claude` in Terminal and sign in.")) {
            _ = try ClaudeCredentials.load(home: home.url, keychain: FakeKeychain(), now: now)
        }
    }

    @Test func expiredFileFallsThroughToUnexpiredKeychain() throws {
        let home = TempHome(); defer { home.remove() }
        home.write(#"{"claudeAiOauth":{"accessToken":"tok-file","expiresAt":\#(Int((now.timeIntervalSince1970 - 1) * 1000))}}"#, at: ".claude/.credentials.json")
        let keychainJSON = #"{"claudeAiOauth":{"accessToken":"tok-keychain","expiresAt":\#(Int((now.timeIntervalSince1970 + 3600) * 1000))}}"#
        let creds = try ClaudeCredentials.load(home: home.url, keychain: FakeKeychain(["Claude Code-credentials": keychainJSON]), now: now)
        #expect(creds.accessToken == "tok-keychain")
    }

    // A Keychain read costs the user a macOS authorization prompt, so an unexpired file must
    // answer on its own. Asserting `reads == 0` is the point of the test; that the file token
    // wins over a *different* Keychain token only proves the Keychain wasn't preferred.
    @Test func unexpiredFileNeverTouchesKeychain() throws {
        let home = TempHome(); defer { home.remove() }
        home.write(#"{"claudeAiOauth":{"accessToken":"tok-file","expiresAt":\#(Int((now.timeIntervalSince1970 + 3600) * 1000))}}"#, at: ".claude/.credentials.json")
        let keychainJSON = #"{"claudeAiOauth":{"accessToken":"tok-keychain","expiresAt":\#(Int((now.timeIntervalSince1970 + 7200) * 1000))}}"#
        let keychain = FakeKeychain(["Claude Code-credentials": keychainJSON])
        let creds = try ClaudeCredentials.load(home: home.url, keychain: keychain, now: now)
        #expect(creds.accessToken == "tok-file")
        #expect(keychain.reads == 0)
    }

    @Test func undecodableFileFallsThroughToKeychain() throws {
        let home = TempHome(); defer { home.remove() }
        home.write("not json", at: ".claude/.credentials.json")
        let keychainJSON = #"{"claudeAiOauth":{"accessToken":"tok-keychain","expiresAt":\#(Int((now.timeIntervalSince1970 + 3600) * 1000))}}"#
        let keychain = FakeKeychain(["Claude Code-credentials": keychainJSON])
        let creds = try ClaudeCredentials.load(home: home.url, keychain: keychain, now: now)
        #expect(creds.accessToken == "tok-keychain")
        #expect(keychain.reads == 1)
    }

    @Test func allSourcesExpiredIsCredentialsExpired() {
        let home = TempHome(); defer { home.remove() }
        home.write(#"{"claudeAiOauth":{"accessToken":"tok-file","expiresAt":\#(Int((now.timeIntervalSince1970 - 1) * 1000))}}"#, at: ".claude/.credentials.json")
        let keychainJSON = #"{"claudeAiOauth":{"accessToken":"tok-keychain","expiresAt":\#(Int((now.timeIntervalSince1970 - 1) * 1000))}}"#
        #expect(throws: ProviderError.credentialsExpired(hint: ClaudeCredentials.expiredHint)) {
            _ = try ClaudeCredentials.load(home: home.url, keychain: FakeKeychain(["Claude Code-credentials": keychainJSON]), now: now)
        }
    }

    @Test func absentScopesStillLoads() throws {
        let home = TempHome(); defer { home.remove() }
        home.write(#"{"claudeAiOauth":{"accessToken":"tok-noscopes"}}"#, at: ".claude/.credentials.json")
        let creds = try ClaudeCredentials.load(home: home.url, keychain: FakeKeychain(), now: now)
        #expect(creds.scopes == [])
    }
}

@Suite struct ClaudeProviderTests {
    let clock = FakeClock()

    func makeHome() -> TempHome {
        let home = TempHome()
        home.write(#"{"claudeAiOauth":{"accessToken":"tok-claude","scopes":["user:inference","user:profile"],"subscriptionType":"max"}}"#, at: ".claude/.credentials.json")
        return home
    }

    // The fixture's `seven_day_opus` is null, so its three windows are the plan-wide session and
    // weekly pair plus the one active `weekly_scoped` entry from the `limits` array.
    @Test func decodesFixtureIntoThreeWindows() async throws {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 200, json: fixture("claude"))
        let provider = ClaudeProvider(home: home.url, keychain: FakeKeychain(), userAgent: "claude-code/test")
        let snap = try await provider.fetch(using: http, clock: clock)

        #expect(snap.plan == "max")
        #expect(snap.fetchedAt == clock.now)
        #expect(snap.windows.count == 3)

        // Expected dates are computed independently of ISO8601.date(from:) — comparing against
        // ISO8601.date(from: <the fixture's own string>) would pass even if parsing silently
        // returned nil on both sides. Fixtures/claude.json's resets_at strings are
        // "2026-08-29T23:59:59.595903+00:00", "2026-08-31T15:59:59.595925+00:00" and
        // "2026-08-31T15:59:59.596188+00:00"; by arithmetic from 2026-08-29T00:00:00Z ==
        // 1_787_961_600 those are exactly 1_788_047_999.595903, 1_788_191_999.595925 and
        // 1_788_191_999.596188. ISO8601DateFormatter's .withFractionalSeconds only carries
        // millisecond precision, though — it truncates (not rounds) the sub-millisecond digits,
        // so the values ISO8601.date(from:) actually produces are 1_788_047_999.595,
        // 1_788_191_999.595 and 1_788_191_999.596 (verified with a standalone
        // ISO8601DateFormatter probe). That's what we assert here.
        let sessionResetsAt = try #require(snap.windows[0].resetsAt)
        let weeklyResetsAt = try #require(snap.windows[1].resetsAt)
        let scopedResetsAt = try #require(snap.windows[2].resetsAt)
        #expect(sessionResetsAt == Date(timeIntervalSince1970: 1_788_047_999.595))
        #expect(weeklyResetsAt == Date(timeIntervalSince1970: 1_788_191_999.595))
        #expect(scopedResetsAt == Date(timeIntervalSince1970: 1_788_191_999.596))
        #expect(snap.windows[0] == UsageWindow(kind: .session, label: "Current session", usedPercent: 5, resetsAt: sessionResetsAt))
        #expect(snap.windows[1] == UsageWindow(kind: .weekly, label: "All models", usedPercent: 27, resetsAt: weeklyResetsAt))
        #expect(snap.windows[2] == UsageWindow(kind: .other("Fable"), label: "Fable weekly", usedPercent: 32, resetsAt: scopedResetsAt))
        #expect(snap.sessionWindow?.usedPercent == 5)
    }

    // Only active scoped entries become windows: the fixture's `limits` array also restates the
    // session and weekly windows (`is_active: false`), which must not be mapped twice.
    @Test func inactiveAndUnscopedLimitsAreIgnored() async throws {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: #"""
        {"five_hour":{"utilization":11.0,"resets_at":null},
         "limits":[{"kind":"weekly_scoped","is_active":false,"percent":80,"resets_at":null,"scope":{"model":{"display_name":"Inactive"}}},
                   {"kind":"weekly_all","is_active":true,"percent":90,"resets_at":null,"scope":null}]}
        """#)
        let snap = try await ClaudeProvider(home: home.url, keychain: FakeKeychain(), userAgent: "ua").fetch(using: http, clock: clock)
        #expect(snap.windows == [UsageWindow(kind: .session, label: "Current session", usedPercent: 11, resetsAt: nil)])
    }

    // A scoped limit with no model name still reports its number under a neutral label.
    @Test func scopedLimitWithoutModelNameFallsBackToScoped() async throws {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: #"{"limits":[{"kind":"weekly_scoped","is_active":true,"percent":42,"resets_at":null,"scope":null}]}"#)
        let snap = try await ClaudeProvider(home: home.url, keychain: FakeKeychain(), userAgent: "ua").fetch(using: http, clock: clock)
        #expect(snap.windows == [UsageWindow(kind: .other("scoped"), label: "scoped weekly", usedPercent: 42, resetsAt: nil)])
    }

    // The fixture's seven_day_opus is null, so this covers that branch with a synthetic body.
    @Test func decodesOpusWindowWhenPresent() async throws {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: #"{"five_hour":{"utilization":73.0,"resets_at":"2026-08-29T22:11:00.000000+00:00"},"seven_day":{"utilization":7.0,"resets_at":"2026-09-03T04:50:00.000000+00:00"},"seven_day_opus":{"utilization":3.5,"resets_at":"2026-09-03T04:50:00.000000+00:00"},"seven_day_sonnet":null}"#)
        let snap = try await ClaudeProvider(home: home.url, keychain: FakeKeychain(), userAgent: "claude-code/test").fetch(using: http, clock: clock)

        #expect(snap.windows.count == 3)
        // Independently computed: 2026-09-03T04:50:00 UTC is 5 days + 04:50:00 after
        // 2026-08-29T00:00:00Z (1_787_961_600) = 1_787_961_600 + 432_000 + 17_400.
        let opusResetsAt = try #require(snap.windows[2].resetsAt)
        #expect(opusResetsAt == Date(timeIntervalSince1970: 1_788_411_000))
        #expect(snap.windows[2] == UsageWindow(kind: .other("opus"), label: "Opus weekly", usedPercent: 3.5, resetsAt: opusResetsAt))
    }

    @Test func sendsExactlyTheRequiredHeaders() async throws {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 200, json: fixture("claude"))
        _ = try await ClaudeProvider(home: home.url, keychain: FakeKeychain(), userAgent: "claude-code/test").fetch(using: http, clock: clock)
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.headers["Authorization"] == "Bearer tok-claude")
        #expect(request.headers["anthropic-beta"] == "oauth-2025-04-20")
        #expect(request.headers["User-Agent"] == "claude-code/test")
    }

    @Test func unauthorizedIsCredentialsExpired() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 401, json: #"{"error":"unauthorized"}"#)
        await #expect(throws: ProviderError.credentialsExpired(hint: ClaudeProvider.expiredHint)) {
            _ = try await ClaudeProvider(home: home.url, keychain: FakeKeychain(), userAgent: "ua").fetch(using: http, clock: clock)
        }
    }

    @Test func tooManyRequestsHonorsRetryAfter() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient()
        http.enqueue(HTTPResponse(status: 429, headers: ["Retry-After": "90"], body: Data()))
        await #expect(throws: ProviderError.rateLimited(retryAfter: 90)) {
            _ = try await ClaudeProvider(home: home.url, keychain: FakeKeychain(), userAgent: "ua").fetch(using: http, clock: clock)
        }
    }

    @Test func serverErrorIsNetwork() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 503, json: "")
        await #expect(throws: ProviderError.network("HTTP 503")) {
            _ = try await ClaudeProvider(home: home.url, keychain: FakeKeychain(), userAgent: "ua").fetch(using: http, clock: clock)
        }
    }

    @Test func transportFailureIsNetwork() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(error: StubTransportError())
        // StubTransportError (not URLError) keeps this deterministic across OS/locale — see its
        // doc comment in Support/FakeHTTPClient.swift. This verifies HTTPStatus.send forwards
        // error.localizedDescription verbatim, without depending on Foundation's CFNetwork strings.
        await #expect(throws: ProviderError.network("stub transport failure")) {
            _ = try await ClaudeProvider(home: home.url, keychain: FakeKeychain(), userAgent: "ua").fetch(using: http, clock: clock)
        }
    }

    @Test func malformedBodyIsUnexpectedResponse() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 200, json: "<html>")
        await #expect(throws: ProviderError.unexpectedResponse("claude: body is not JSON")) {
            _ = try await ClaudeProvider(home: home.url, keychain: FakeKeychain(), userAgent: "ua").fetch(using: http, clock: clock)
        }
    }

    // JSON that carries none of the keys this provider knows about is a shape change, not an
    // account without limits — the two are scheduled differently by UsageStore.
    @Test func unknownShapeIsUnexpectedResponse() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 200, json: #"{"message":"Your organization manages usage."}"#)
        await #expect(throws: ProviderError.unexpectedResponse("claude: no known usage windows")) {
            _ = try await ClaudeProvider(home: home.url, keychain: FakeKeychain(), userAgent: "ua").fetch(using: http, clock: clock)
        }
    }

    @Test func knownShapeWithoutWindowsIsUnsupportedAccount() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 200, json: #"{"five_hour":null,"seven_day":null,"limits":[]}"#)
        await #expect(throws: ProviderError.unsupportedAccount("This Claude account doesn't report usage limits.")) {
            _ = try await ClaudeProvider(home: home.url, keychain: FakeKeychain(), userAgent: "ua").fetch(using: http, clock: clock)
        }
    }

    @Test func missingCredentialsPropagate() async {
        let home = TempHome(); defer { home.remove() }
        await #expect(throws: ProviderError.credentialsMissing(hint: ClaudeCredentials.missingHint)) {
            _ = try await ClaudeProvider(home: home.url, keychain: FakeKeychain(), userAgent: "ua").fetch(using: FakeHTTPClient(), clock: clock)
        }
    }

    @Test func cliVersionUserAgentHasExpectedShape() {
        let ua = ClaudeCLIVersion.userAgent(versionOutput: "2.1.251 (Claude Code)")
        #expect(ua == "claude-code/2.1.251")
        #expect(ClaudeCLIVersion.userAgent(versionOutput: nil) == "claude-code/\(ClaudeCLIVersion.fallbackVersion)")
    }

    // The token goes straight into a request header, so anything outside [0-9A-Za-z.-] is
    // stripped; a token that is entirely junk leaves nothing and falls back.
    @Test func userAgentSanitizesVersionToken() {
        #expect(ClaudeCLIVersion.userAgent(versionOutput: "2.1.251\r (Claude Code)") == "claude-code/2.1.251")
        #expect(ClaudeCLIVersion.userAgent(versionOutput: "???") == "claude-code/\(ClaudeCLIVersion.fallbackVersion)")
    }

    // `~/.local/bin/claude` is tried before the Homebrew paths, so a stub under a TempHome wins
    // over whatever real CLI is installed on the machine running the tests.
    @Test func userAgentFindsStubExecutableUnderHome() throws {
        let home = TempHome(); defer { home.remove() }
        let stub = home.write("#!/bin/sh\necho '9.9.9 (Claude Code)'\n", at: ".local/bin/claude")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        #expect(ClaudeCLIVersion.userAgent(home: home.url) == "claude-code/9.9.9")
    }
}
