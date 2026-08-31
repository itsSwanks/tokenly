import Foundation
import Testing
@testable import PulseCore

@Suite struct CodexCredentialsTests {
    @Test func loadsTokenAndAccountId() throws {
        let home = TempHome(); defer { home.remove() }
        home.write(#"{"OPENAI_API_KEY":null,"tokens":{"id_token":"i","access_token":"tok-codex","refresh_token":"r","account_id":"acct-1"},"last_refresh":"2026-08-29T00:00:00Z"}"#, at: ".codex/auth.json")
        let creds = try CodexCredentials.load(home: home.url)
        #expect(creds.accessToken == "tok-codex")
        #expect(creds.accountId == "acct-1")
    }

    @Test func accountIdIsOptional() throws {
        let home = TempHome(); defer { home.remove() }
        home.write(#"{"tokens":{"access_token":"tok-codex"}}"#, at: ".codex/auth.json")
        #expect(try CodexCredentials.load(home: home.url).accountId == nil)
    }

    @Test func missingTokensBlockIsCredentialsMissing() {
        let home = TempHome(); defer { home.remove() }
        home.write(#"{"OPENAI_API_KEY":"sk-only"}"#, at: ".codex/auth.json")
        #expect(throws: ProviderError.credentialsMissing(hint: "Run `codex` in Terminal and sign in with ChatGPT.")) {
            _ = try CodexCredentials.load(home: home.url)
        }
    }
}

@Suite struct CodexProviderTests {
    let clock = FakeClock()

    func makeHome(accountId: Bool = true) -> TempHome {
        let home = TempHome()
        let account = accountId ? #","account_id":"acct-1""# : ""
        home.write(#"{"tokens":{"access_token":"tok-codex"\#(account)}}"#, at: ".codex/auth.json")
        return home
    }

    // Fixtures/codex.json carries plan_type "plus", rate_limit.primary_window
    // { used_percent: 0, reset_at: 1788048119 } and secondary_window
    // { used_percent: 50, reset_at: 1788495873 } — those are the numbers asserted below.
    @Test func decodesPrimaryAndSecondaryWindows() async throws {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 200, json: fixture("codex"))
        let snap = try await CodexProvider(home: home.url).fetch(using: http, clock: clock)
        #expect(snap.plan == "plus")
        #expect(snap.windows == [
            UsageWindow(kind: .session, label: "Current session", usedPercent: 0, resetsAt: Date(timeIntervalSince1970: 1_788_048_119)),
            UsageWindow(kind: .weekly, label: "Weekly", usedPercent: 50, resetsAt: Date(timeIntervalSince1970: 1_788_495_873)),
        ])
    }

    @Test func fallsBackToResetAfterSecondsWhenResetAtMissing() async throws {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: #"{"rate_limit":{"primary_window":{"used_percent":50,"reset_after_seconds":120}}}"#)
        let snap = try await CodexProvider(home: home.url).fetch(using: http, clock: clock)
        #expect(snap.windows == [UsageWindow(kind: .session, label: "Current session", usedPercent: 50, resetsAt: clock.now.addingTimeInterval(120))])
        #expect(snap.plan == nil)
    }

    @Test func sendsAccountHeaderOnlyWhenKnown() async throws {
        let withAccount = makeHome(); defer { withAccount.remove() }
        let http1 = FakeHTTPClient(); http1.enqueue(status: 200, json: fixture("codex"))
        _ = try await CodexProvider(home: withAccount.url).fetch(using: http1, clock: clock)
        let r1 = try #require(http1.requests.first)
        #expect(r1.url.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(r1.headers["Authorization"] == "Bearer tok-codex")
        #expect(r1.headers["ChatGPT-Account-Id"] == "acct-1")

        let without = makeHome(accountId: false); defer { without.remove() }
        let http2 = FakeHTTPClient(); http2.enqueue(status: 200, json: fixture("codex"))
        _ = try await CodexProvider(home: without.url).fetch(using: http2, clock: clock)
        #expect(http2.requests.first?.headers["ChatGPT-Account-Id"] == nil)
    }

    @Test func unauthorizedIsCredentialsExpired() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 401, json: "{}")
        await #expect(throws: ProviderError.credentialsExpired(hint: "Run `codex` in Terminal to refresh your session.")) {
            _ = try await CodexProvider(home: home.url).fetch(using: http, clock: clock)
        }
    }

    @Test func noRateLimitBlockIsUnsupportedAccount() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 200, json: #"{"plan_type":"free"}"#)
        await #expect(throws: ProviderError.unsupportedAccount("This ChatGPT account doesn't report Codex limits.")) {
            _ = try await CodexProvider(home: home.url).fetch(using: http, clock: clock)
        }
    }

    // Valid JSON with neither rate_limit nor plan_type isn't a usage body at all — that is a
    // shape change, which UsageStore retries far sooner than an unsupported account.
    @Test func unknownShapeIsUnexpectedResponse() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 200, json: #"{"foo":1}"#)
        await #expect(throws: ProviderError.unexpectedResponse("codex: no known usage windows")) {
            _ = try await CodexProvider(home: home.url).fetch(using: http, clock: clock)
        }
    }

    @Test func malformedBodyIsUnexpectedResponse() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 200, json: "nope")
        await #expect(throws: ProviderError.unexpectedResponse("codex: body is not JSON")) {
            _ = try await CodexProvider(home: home.url).fetch(using: http, clock: clock)
        }
    }
}
