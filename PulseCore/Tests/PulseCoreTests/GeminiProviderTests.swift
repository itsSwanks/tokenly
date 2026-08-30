import Foundation
import Testing
@testable import PulseCore

@Suite struct GeminiCredentialsTests {
    @Test func loadsAndComputesExpiry() throws {
        let home = TempHome(); defer { home.remove() }
        home.write(#"{"access_token":"tok-gem","refresh_token":"ref","scope":"s","token_type":"Bearer","id_token":"i","expiry_date":1756500000000}"#, at: ".gemini/oauth_creds.json")
        let creds = try GeminiCredentials.load(home: home.url)
        #expect(creds.accessToken == "tok-gem")
        #expect(creds.refreshToken == "ref")
        #expect(creds.expiryDate == Date(timeIntervalSince1970: 1_756_500_000))
        #expect(creds.isExpired(at: Date(timeIntervalSince1970: 1_756_499_000)) == false)
        #expect(creds.isExpired(at: Date(timeIntervalSince1970: 1_756_499_950)) == true)   // inside 60 s margin
        #expect(creds.isExpired(at: Date(timeIntervalSince1970: 1_756_600_000)) == true)
    }

    @Test func missingExpiryMeansNeverExpired() throws {
        let home = TempHome(); defer { home.remove() }
        home.write(#"{"access_token":"tok-gem"}"#, at: ".gemini/oauth_creds.json")
        let creds = try GeminiCredentials.load(home: home.url)
        #expect(creds.isExpired(at: .distantFuture) == false)
    }

    @Test func missingFileIsCredentialsMissing() {
        let home = TempHome(); defer { home.remove() }
        #expect(throws: ProviderError.credentialsMissing(hint: "Run `gemini` in Terminal and sign in with Google.")) {
            _ = try GeminiCredentials.load(home: home.url)
        }
    }
}

@Suite struct GeminiClientSecretsTests {
    @Test func locatesIdAndSecretInBundleChunks() {
        let dir = TempHome(); defer { dir.remove() }
        dir.write("var a=1;", at: "chunk-A.js")
        dir.write(#"const ID="123456789012-abcdefghijklmnop.apps.googleusercontent.com",S="GOCSPX-abcDEF123_-xyz";"#, at: "chunk-B.js")
        let secrets = GeminiClientSecrets.locate(in: [dir.url])
        #expect(secrets == GeminiClientSecrets(clientId: "123456789012-abcdefghijklmnop.apps.googleusercontent.com", clientSecret: "GOCSPX-abcDEF123_-xyz"))
    }

    @Test func returnsNilWhenNothingMatches() {
        let dir = TempHome(); defer { dir.remove() }
        dir.write("nothing here", at: "chunk-A.js")
        #expect(GeminiClientSecrets.locate(in: [dir.url]) == nil)
        #expect(GeminiClientSecrets.locate(in: [dir.url.appendingPathComponent("missing")]) == nil)
    }

    // Mirrors the real gemini-cli bundle (chunk-3AIAY5PD.js and 3 duplicates), which embeds
    // gcloud's unrelated CLOUD_SDK_CLIENT_ID far earlier in the file than the CLI's own
    // OAUTH_CLIENT_ID, declared immediately next to OAUTH_CLIENT_SECRET. Fake values only.
    @Test func picksTheClientIdNearestTheSecret() {
        let dir = TempHome(); defer { dir.remove() }
        let filler = String(repeating: "x", count: 2000)
        let contents = #"var UNRELATED_ID="111111111111-aaaaaaaaaaaaaaaa.apps.googleusercontent.com";"#
            + filler
            + #"var OAUTH_CLIENT_ID="222222222222-bbbbbbbbbbbbbbbb.apps.googleusercontent.com";var OAUTH_CLIENT_SECRET="GOCSPX-realsecret123456789";"#
        dir.write(contents, at: "chunk-C.js")
        let secrets = GeminiClientSecrets.locate(in: [dir.url])
        #expect(secrets == GeminiClientSecrets(clientId: "222222222222-bbbbbbbbbbbbbbbb.apps.googleusercontent.com", clientSecret: "GOCSPX-realsecret123456789"))
    }
}

@Suite struct GeminiTokenRefresherTests {
    let secrets = GeminiClientSecrets(clientId: "cid", clientSecret: "sec")
    let creds = GeminiCredentials(accessToken: "old", refreshToken: "ref", expiryDate: .distantPast)

    @Test func postsFormAndReturnsNewToken() async throws {
        let http = FakeHTTPClient(); http.enqueue(status: 200, json: #"{"access_token":"new-tok","expires_in":3599,"token_type":"Bearer"}"#)
        let token = try await GeminiTokenRefresher.refresh(creds, secrets: secrets, via: http)
        #expect(token == "new-tok")
        let request = try #require(http.requests.first)
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
        let body = String(decoding: request.body ?? Data(), as: UTF8.self)
        #expect(body.contains("client_id=cid") && body.contains("client_secret=sec") && body.contains("refresh_token=ref") && body.contains("grant_type=refresh_token"))
    }

    @Test func rejectedRefreshIsCredentialsExpired() async {
        let http = FakeHTTPClient(); http.enqueue(status: 400, json: #"{"error":"invalid_grant"}"#)
        await #expect(throws: ProviderError.credentialsExpired(hint: GeminiProvider.expiredHint)) {
            _ = try await GeminiTokenRefresher.refresh(creds, secrets: secrets, via: http)
        }
    }

    // Google being down says nothing about the refresh token, so this must not tell the user to
    // sign in again — it is a retryable network failure.
    @Test func serverErrorDuringRefreshIsNetwork() async {
        let http = FakeHTTPClient(); http.enqueue(status: 503, json: #"{"error":"backend unavailable"}"#)
        await #expect(throws: ProviderError.network("HTTP 503")) {
            _ = try await GeminiTokenRefresher.refresh(creds, secrets: secrets, via: http)
        }
    }

    @Test func successWithoutAccessTokenIsCredentialsExpired() async {
        let http = FakeHTTPClient(); http.enqueue(status: 200, json: #"{"expires_in":3599}"#)
        await #expect(throws: ProviderError.credentialsExpired(hint: GeminiProvider.expiredHint)) {
            _ = try await GeminiTokenRefresher.refresh(creds, secrets: secrets, via: http)
        }
    }
}

@Suite struct GeminiProviderTests {
    let clock = FakeClock()
    let secrets = GeminiClientSecrets(clientId: "cid", clientSecret: "sec")

    // The default expiry must sit after FakeClock()'s default `now` (1_788_038_400 s); an earlier
    // value would silently send every "not expired" case down the expired/refresh path instead.
    func makeHome(expiryMs: Double = 1_788_042_000_000, refresh: Bool = true) -> TempHome {
        let home = TempHome()
        let r = refresh ? #","refresh_token":"ref""# : ""
        home.write(#"{"access_token":"tok-gem"\#(r),"expiry_date":\#(expiryMs)}"#, at: ".gemini/oauth_creds.json")
        return home
    }

    @Test func lowestRemainingBucketDrivesTheRing() async throws {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 200, json: fixture("gemini"))
        let snap = try await GeminiProvider(home: home.url, secrets: secrets).fetch(using: http, clock: clock)

        // Expected date computed independently of ISO8601.date(from:) (the function under
        // test) — comparing against ISO8601.date(from: <the fixture's own string>) would pass
        // even if parsing silently returned nil on both sides. Fixtures/gemini.json's
        // resetTime is "2026-08-30T07:00:00Z"; by arithmetic from 2026-08-29T00:00:00Z ==
        // 1_787_961_600, that's 1_787_961_600 + 86_400 (1 day) + 7 * 3_600 (7 hours) =
        // 1_788_073_200.
        let expectedReset = Date(timeIntervalSince1970: 1_788_073_200)
        let sessionResetsAt = try #require(snap.windows[0].resetsAt)
        let flashResetsAt = try #require(snap.windows[1].resetsAt)
        let liteResetsAt = try #require(snap.windows[2].resetsAt)
        #expect(sessionResetsAt == expectedReset)
        #expect(flashResetsAt == expectedReset)
        #expect(liteResetsAt == expectedReset)

        #expect(snap.windows == [
            UsageWindow(kind: .session, label: "Gemini CLI quota", usedPercent: 18, resetsAt: sessionResetsAt),
            UsageWindow(kind: .other("gemini-2.5-flash"), label: "gemini-2.5-flash", usedPercent: 3, resetsAt: flashResetsAt),
            UsageWindow(kind: .other("gemini-2.5-flash-lite"), label: "gemini-2.5-flash-lite", usedPercent: 0, resetsAt: liteResetsAt),
        ])
        let request = try #require(http.requests.first)
        #expect(request.url.absoluteString == "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")
        #expect(request.headers["Authorization"] == "Bearer tok-gem")
        #expect(String(decoding: request.body ?? Data(), as: UTF8.self) == "{}")
    }

    @Test func refreshesExpiredTokenInMemoryAndUsesIt() async throws {
        let home = makeHome(expiryMs: 1_000); defer { home.remove() }
        let http = FakeHTTPClient()
        // The new token must not be a substring of anything already on disk: the
        // never-persisted assertion below searches the credential file for it, and the file
        // already contains "refresh_token" — so a token like "fresh" would match spuriously.
        http.enqueue(status: 200, json: #"{"access_token":"brandnew","expires_in":3599}"#)
        http.enqueue(status: 200, json: fixture("gemini"))
        _ = try await GeminiProvider(home: home.url, secrets: secrets).fetch(using: http, clock: clock)
        #expect(http.requests.count == 2)
        #expect(http.requests[1].headers["Authorization"] == "Bearer brandnew")
        let onDisk = try String(contentsOf: home.url.appendingPathComponent(".gemini/oauth_creds.json"), encoding: .utf8)
        #expect(onDisk.contains("tok-gem") && !onDisk.contains("brandnew"))   // never persisted
    }

    @Test func expiredWithoutRefreshTokenIsCredentialsExpired() async {
        let home = makeHome(expiryMs: 1_000, refresh: false); defer { home.remove() }
        await #expect(throws: ProviderError.credentialsExpired(hint: GeminiProvider.expiredHint)) {
            _ = try await GeminiProvider(home: home.url, secrets: secrets).fetch(using: FakeHTTPClient(), clock: clock)
        }
    }

    @Test func expiredWithoutClientSecretsIsCredentialsExpired() async {
        let home = makeHome(expiryMs: 1_000); defer { home.remove() }
        await #expect(throws: ProviderError.credentialsExpired(hint: GeminiProvider.expiredHint)) {
            _ = try await GeminiProvider(home: home.url, secrets: nil, locateSecrets: { _ in nil }).fetch(using: FakeHTTPClient(), clock: clock)
        }
    }

    @Test func projectRequiredTriggersLoadCodeAssistAndRetry() async throws {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient()
        http.enqueue(status: 400, json: #"{"error":{"message":"project is required"}}"#)
        http.enqueue(status: 200, json: #"{"cloudaicompanionProject":"proj-1","currentTier":{"id":"free-tier"}}"#)
        http.enqueue(status: 200, json: fixture("gemini"))
        let snap = try await GeminiProvider(home: home.url, secrets: secrets).fetch(using: http, clock: clock)
        #expect(http.requests.count == 3)
        #expect(http.requests[1].url.absoluteString == "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")
        #expect(String(decoding: http.requests[2].body ?? Data(), as: UTF8.self) == #"{"project":"proj-1"}"#)
        #expect(snap.plan == "free-tier")
    }

    @Test func emptyBucketsIsUnsupportedAccount() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 200, json: #"{"buckets":[]}"#)
        await #expect(throws: ProviderError.unsupportedAccount(GeminiProvider.unsupportedMessage)) {
            _ = try await GeminiProvider(home: home.url, secrets: secrets).fetch(using: http, clock: clock)
        }
    }

    @Test func malformedBodyIsUnexpectedResponse() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 200, json: "<!doctype html>")
        await #expect(throws: ProviderError.unexpectedResponse("gemini: body is not JSON")) {
            _ = try await GeminiProvider(home: home.url, secrets: secrets).fetch(using: http, clock: clock)
        }
    }

    // Google returns 403 SUBSCRIPTION_REQUIRED on retrieveUserQuota for accounts without Code
    // Assist entitlement (Fixtures/gemini-forbidden.json is a redacted capture of that response).
    // That's an account-type problem, not an expired or invalid credential.
    @Test func forbiddenQuotaIsUnsupportedAccount() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 403, json: fixture("gemini-forbidden"))
        await #expect(throws: ProviderError.unsupportedAccount(GeminiProvider.unsupportedMessage)) {
            _ = try await GeminiProvider(home: home.url, secrets: secrets).fetch(using: http, clock: clock)
        }
    }

    @Test func unauthorizedQuotaIsCredentialsExpired() async {
        let home = makeHome(); defer { home.remove() }
        let http = FakeHTTPClient(); http.enqueue(status: 401, json: "{}")
        await #expect(throws: ProviderError.credentialsExpired(hint: GeminiProvider.expiredHint)) {
            _ = try await GeminiProvider(home: home.url, secrets: secrets).fetch(using: http, clock: clock)
        }
    }
}
