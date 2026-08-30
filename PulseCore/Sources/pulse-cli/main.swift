import Foundation
import PulseCore

// pulse-cli capture   — dump raw usage responses to <package root>/.captures/*.raw.json
// pulse-cli usage     — print decoded usage for every provider

/// `<package root>/.captures`, derived from this file's own location so the destination never
/// depends on the working directory the binary happens to be launched from:
/// main.swift → pulse-cli → Sources → package root.
let capturesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent(".captures", isDirectory: true)

/// Keys whose values are personal/account identifiers — never shown in the terminal preview,
/// even though the raw file on disk (consumed by the redaction script) keeps them.
let previewRedactKeys: Set<String> = [
    "email", "account_id", "accountId", "org_id", "organization_id",
    "user_id", "userId", "project", "cloudaicompanionProject",
    "name", "displayName", "id", "sub",
]

func redactedForPreview(_ value: Any) -> Any {
    if let dict = value as? [String: Any] {
        var result: [String: Any] = [:]
        for (key, v) in dict {
            result[key] = previewRedactKeys.contains(key) ? "REDACTED" : redactedForPreview(v)
        }
        return result
    }
    if let array = value as? [Any] {
        return array.map(redactedForPreview)
    }
    return value
}

func write(_ name: String, _ response: HTTPResponse) {
    let url = capturesDir.appendingPathComponent("\(name).raw.json")
    let object = try? JSONSerialization.jsonObject(with: response.body)

    // Serialization and write failures are reported, never swallowed: a silently missing capture
    // reads exactly like a provider that returned nothing. A body that simply isn't JSON is not a
    // failure — it is stored verbatim. Either way the remaining providers still run.
    let pretty: Data
    do {
        pretty = try object.map { try JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys]) } ?? response.body
        try FileManager.default.createDirectory(at: capturesDir, withIntermediateDirectories: true)
        try pretty.write(to: url)
    } catch {
        FileHandle.standardError.write(Data("[\(name)] FAILED to write \(url.path): \(error)\n".utf8))
        return
    }

    // A non-JSON body must never fall back to printing raw bytes — that would bypass the
    // redaction above. The raw file on disk (written just above) is unaffected either way.
    let preview: String
    if let object, let data = try? JSONSerialization.data(withJSONObject: redactedForPreview(object), options: [.prettyPrinted, .sortedKeys]) {
        preview = String(decoding: data.prefix(600), as: UTF8.self)
    } else {
        preview = "(non-JSON body, \(response.body.count) bytes — not previewed)"
    }
    print("[\(name)] HTTP \(response.status) → \(url.lastPathComponent) (\(pretty.count) bytes)\n\(preview)\n")
}

func capture() async {
    print("captures → \(capturesDir.path)\n")
    let http = URLSessionHTTPClient()
    let home = CredentialFile.defaultHome()

    // Claude
    do {
        let creds = try ClaudeCredentials.load(home: home, keychain: SecKeychainReader(), now: Date())
        let request = HTTPRequest(method: .get, url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, headers: [
            "Authorization": "Bearer \(creds.accessToken)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-code/2.1.251",
            "Accept": "application/json",
        ])
        write("claude", try await http.send(request))
    } catch { print("[claude] \(error)\n") }

    // Codex
    do {
        let creds = try CodexCredentials.load(home: home)
        var headers = ["Authorization": "Bearer \(creds.accessToken)", "Accept": "application/json"]
        if let account = creds.accountId { headers["ChatGPT-Account-Id"] = account }
        let request = HTTPRequest(method: .get, url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, headers: headers)
        write("codex", try await http.send(request))
    } catch { print("[codex] \(error)\n") }

    // Gemini — refresh the token in memory if expired (never persisted to oauth_creds.json),
    // then quota first with an empty body, then loadCodeAssist for the project/tier.
    do {
        let creds = try GeminiCredentials.load(home: home)
        var accessToken = creds.accessToken
        if creds.isExpired(at: Date()), creds.refreshToken != nil {
            guard let secrets = GeminiClientSecrets.locateInstalled() else {
                throw ProviderError.credentialsMissing(hint: "gemini: CLI OAuth client not found")
            }
            accessToken = try await GeminiTokenRefresher.refresh(creds, secrets: secrets, via: http)
        }
        let headers = ["Authorization": "Bearer \(accessToken)", "Content-Type": "application/json", "Accept": "application/json"]
        let quota = HTTPRequest(method: .post, url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!,
                                headers: headers, body: Data("{}".utf8))
        write("gemini", try await http.send(quota))
        let load = HTTPRequest(method: .post, url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!,
                               headers: headers, body: Data(#"{"metadata":{"ideType":"GEMINI_CLI","pluginType":"GEMINI"}}"#.utf8))
        write("gemini-load-code-assist", try await http.send(load))
    } catch { print("[gemini] \(error)\n") }
}

func usage() async {
    let http = URLSessionHTTPClient()
    let clock = SystemClock()
    let providers: [any Provider] = [ClaudeProvider(), CodexProvider(), GeminiProvider()]
    for provider in providers {
        let name = provider.id.displayName.padding(toLength: 8, withPad: " ", startingAt: 0)
        do {
            let snap = try await provider.fetch(using: http, clock: clock)
            let plan = (snap.plan ?? "—").padding(toLength: 14, withPad: " ", startingAt: 0)
            for (i, w) in snap.windows.enumerated() {
                let prefix = i == 0 ? "\(name) \(plan)" : String(repeating: " ", count: 23)
                let pct = String(format: "%5.1f%%", w.usedPercent)
                let level = String(describing: UsageLevel(percent: w.usedPercent)).padding(toLength: 7, withPad: " ", startingAt: 0)
                let ring = w.kind == .session ? "●" : " "
                print("\(prefix) \(ring) \(w.label.padding(toLength: 22, withPad: " ", startingAt: 0)) \(pct)  \(level) \(ResetFormatter.text(resetsAt: w.resetsAt, now: clock.now))")
            }
        } catch {
            print("\(name) disconnected: \(error)")
        }
    }
}

switch CommandLine.arguments.dropFirst().first {
case "capture": await capture()
case "usage": await usage()
default: print("usage: pulse-cli capture | usage")
}
