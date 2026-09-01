import Foundation
import Testing
@testable import PulseCore

private struct Creds: Decodable, Equatable { let token: String }

@Suite struct CredentialFileTests {
    @Test func loadsAndDecodesJSON() throws {
        let home = TempHome(); defer { home.remove() }
        home.write(#"{"token":"abc"}"#, at: ".x/creds.json")
        let creds: Creds = try CredentialFile.load(Creds.self, relativePath: ".x/creds.json", home: home.url, hint: "Run x")
        #expect(creds == Creds(token: "abc"))
    }

    @Test func missingFileIsCredentialsMissingWithHint() {
        let home = TempHome(); defer { home.remove() }
        #expect(throws: ProviderError.credentialsMissing(hint: "Run x")) {
            let _: Creds = try CredentialFile.load(Creds.self, relativePath: ".x/creds.json", home: home.url, hint: "Run x")
        }
    }

    @Test func malformedFileIsCredentialsMissingWithHint() {
        let home = TempHome(); defer { home.remove() }
        home.write("not json", at: ".x/creds.json")
        #expect(throws: ProviderError.credentialsMissing(hint: "Run x")) {
            let _: Creds = try CredentialFile.load(Creds.self, relativePath: ".x/creds.json", home: home.url, hint: "Run x")
        }
    }

    @Test func fakeKeychainReturnsBytes() {
        let kc = FakeKeychain(["svc": "secret"])
        #expect(kc.genericPassword(service: "svc") == Data("secret".utf8))
        #expect(kc.genericPassword(service: "other") == nil)
    }

    @Test func iso8601ParsesWithAndWithoutFractionalSeconds() {
        #expect(ISO8601.date(from: "2026-08-29T22:00:00Z") == Date(timeIntervalSince1970: 1_788_040_800))
        #expect(ISO8601.date(from: "2026-08-29T22:00:00.000000+00:00") == Date(timeIntervalSince1970: 1_788_040_800))
        #expect(ISO8601.date(from: "2026-08-29T22:00:00.5Z") == Date(timeIntervalSince1970: 1_788_040_800.5))
        #expect(ISO8601.date(from: "garbage") == nil)
        #expect(ISO8601.date(from: nil) == nil)
    }
}
