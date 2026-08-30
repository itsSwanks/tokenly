# Pulse — AI usage edge dock for macOS · Design spec

**Date:** 2026-08-29 · **Status:** approved design, pre-implementation
**Pixel source of truth:** `design/prototype/README.md` + `design/prototype/screenshots/` + `design/reference-mockup.png`

## 1. What it is

Pulse is a free, open-source macOS utility. A black dock grows out of the edge of the screen and shows one progress ring per AI provider — how much of that subscription's usage limit you have consumed, with the ring's color encoding urgency. Hovering a ring opens a callout with every limit window and its reset time. The dock never steals focus, works over full-screen apps and across Spaces, can auto-hide to a sliver, and posts a system notification when a limit gets close.

Every number Pulse shows is **real**, read from the provider's own usage API using OAuth tokens that the provider's official CLI has already stored on the Mac. Pulse never estimates, never scrapes a web page, and never sends anything anywhere except to the provider that owns the token.

### v1 scope

| Ring | What it measures | Credential on disk | Endpoint |
|---|---|---|---|
| Claude | Claude Pro/Max plan usage (shared by claude.ai + Claude Code) | `~/.claude/.credentials.json` → fallback Keychain item `Claude Code-credentials` | `GET https://api.anthropic.com/api/oauth/usage` |
| Codex | ChatGPT plan's Codex quota | `~/.codex/auth.json` | `GET https://chatgpt.com/backend-api/wham/usage` |
| Gemini | Gemini CLI (Code Assist) quota | `~/.gemini/oauth_creds.json` | `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` |

### Explicitly out of v1 (planned v1.1+)

- **Grok** — only reachable via grok.com's internal rate-limit endpoint with browser cookies (Arc/Brave/Safari); needs Full Disk Access and breaks when grok.com changes.
- **Gemini web app (AI Pro/Ultra) limits** — Google removed consumer tiers from the CLI quota API in June 2026; the web limits are only on `gemini.google.com/usage`, again cookies.
- **ChatGPT chat limits** — text chat has been unlimited on all plans since 2026-08-06; nothing to show.
- **Windows** — separate UI later. `PulseCore` is Foundation-only so its fetchers port cleanly.
- **Menu-bar icon** — the dock is the whole UI in v1.

### Decisions

1. All rings are real data; no "estimated" state ships in v1.
2. The ring shows the **session** window (5-hour / primary). The weekly window lives in the callout and still triggers alerts.
3. Dock is **always visible** by default; auto-hide is a setting.
4. Native Swift (SwiftUI inside AppKit `NSPanel`s), own fetchers — not a shell over CodexBar, not Tauri.
5. Public GitHub release, **ad-hoc signed, not notarized**, so no personal identity is embedded anywhere.
6. Name "Pulse" is provisional; nothing in the code depends on it beyond the bundle display name.

## 2. Architecture

```
ai-model-usage/
├── Pulse.xcodeproj                 macOS app target (macOS 14+, Swift 6, strict concurrency)
├── Pulse/                          app sources
│   ├── App/            PulseApp, AppDelegate (no main window, no dock icon: LSUIElement = YES)
│   ├── Dock/           DockPanel (NSPanel), DockView, DockShape, RingView, SliverView
│   ├── Callout/        CalloutPanel, CalloutView, WindowBarView
│   ├── Settings/       SettingsPanel, SettingsView, ProviderRow, SegmentedControl
│   ├── Behavior/       EdgeTracker, DragController, ScreenObserver
│   ├── Alerts/         AlertCenter
│   ├── Persistence/    Preferences (UserDefaults wrapper)
│   └── Theme/          Tokens (colors, sizes, durations, easing)
├── PulseCore/                      local Swift package · Foundation only · no AppKit/SwiftUI
│   ├── Sources/PulseCore/
│   │   ├── Provider.swift          protocol + ProviderID
│   │   ├── UsageModel.swift        UsageSnapshot, UsageWindow, ProviderStatus
│   │   ├── UsageStore.swift        polling, back-off, staleness, publishing
│   │   ├── Providers/Claude/       ClaudeProvider, ClaudeCredentials, ClaudeUsageResponse
│   │   ├── Providers/Codex/        CodexProvider, CodexCredentials, CodexUsageResponse
│   │   ├── Providers/Gemini/       GeminiProvider, GeminiCredentials, GeminiQuotaResponse, GeminiTokenRefresher
│   │   └── Support/                HTTPClient (protocol + URLSession impl), Clock (protocol), Keychain reader
│   └── Tests/PulseCoreTests/       + Fixtures/*.json (redacted captures)
├── build/                          release.sh, make-dmg.sh, check-anonymity.sh, appcast tooling
├── design/                         mockup, prompt, HTML prototype, screenshots
└── docs/                           design notes and release runbook
```

**Dependency direction:** `Pulse` → `PulseCore` → Foundation. `PulseCore` has no knowledge of rings, colors, or panels. The one third-party dependency is **Sparkle 2** (SwiftPM) in the app target.

## 3. PulseCore — data layer

### 3.1 Model

```swift
public enum ProviderID: String, CaseIterable, Codable { case claude, codex, gemini }

public struct UsageWindow: Equatable, Sendable {
    public enum Kind: Sendable { case session, weekly, other(String) }
    public let kind: Kind
    public let label: String          // "Current session", "All models", "Opus weekly", "gemini-2.5-pro"
    public let usedPercent: Double    // 0…100, clamped
    public let resetsAt: Date?        // nil when the provider gives no reset
}

public struct UsageSnapshot: Equatable, Sendable {
    public let windows: [UsageWindow] // order = display order; first `.session` drives the ring
    public let fetchedAt: Date
    public let plan: String?          // "max", "plus", "standard-tier" — display only
    public var sessionWindow: UsageWindow? { windows.first { $0.kind == .session } ?? windows.first }
}

public enum ProviderStatus: Equatable, Sendable {
    case loading
    case live(UsageSnapshot)
    case stale(UsageSnapshot, lastError: ProviderError)
    case disconnected(ProviderError)
}

public enum ProviderError: Error, Equatable, Sendable {
    case credentialsMissing(hint: String)     // "Run `codex login` in Terminal"
    case credentialsExpired(hint: String)     // "Run `claude` to refresh your session"
    case network(String)
    case rateLimited(retryAfter: TimeInterval?)
    case unexpectedResponse(String)           // decode failure → "Pulse needs an update for Gemini"
    case unsupportedAccount(String)           // Gemini consumer tier, org plans without numeric quota
}
```

### 3.2 `Provider` protocol

```swift
public protocol Provider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    func fetch(using http: HTTPClient, now: Date) async throws(ProviderError) -> UsageSnapshot
}
```

Each provider does exactly three things: **locate credentials → build request → decode + normalize.** Credentials are read fresh on every fetch (the CLIs rotate them). A provider **never writes** to a credential file. If a token is expired, the provider throws `.credentialsExpired` and the owning CLI is the only thing that refreshes it — except Gemini, whose refresh is a plain Google OAuth call; `GeminiTokenRefresher` refreshes **in memory only** and the result is never persisted.

### 3.3 Per-provider mapping

**Claude**
- Credentials: `~/.claude/.credentials.json` → `claudeAiOauth.accessToken`; if absent, Keychain generic password, service `Claude Code-credentials` (same JSON in the password field). Token needs `user:profile` scope — Claude Code login grants it.
- Request headers: `Authorization: Bearer …`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/<version read from the installed claude CLI, fallback "claude-code/2.0.0">`. The User-Agent is required: without it the API routes to an aggressively rate-limited bucket (persistent 429s).
- Response → windows: `five_hour` → `.session` "Current session"; `seven_day` → `.weekly` "All models"; `seven_day_opus` (if present) → `.other("opus")` "Opus weekly". Each has `utilization` (0–100) and `resets_at` (ISO-8601).
- Org subscriptions that return no numeric fields → `.unsupportedAccount`.

**Codex**
- Credentials: `~/.codex/auth.json` → `tokens.access_token`, `tokens.account_id`.
- Request: `Authorization: Bearer …`, `ChatGPT-Account-Id: <account_id>` when present.
- Response → windows: `rate_limit.primary_window` → `.session` "Current session"; `rate_limit.secondary_window` → `.weekly` "Weekly". Each has a used-percent and a reset (seconds-from-now or timestamp — the day-1 spike captures the exact field names into the fixture and the decoder is written against that fixture). `plan_type` → `plan`.
- 401 → `.credentialsExpired(hint: "Run `codex` to refresh")`.

**Gemini**
- Credentials: `~/.gemini/oauth_creds.json` → `access_token`, `refresh_token`, `expiry_date`. If expired and `refresh_token` present → `POST https://oauth2.googleapis.com/token` with the Gemini CLI's own `client_id`/`client_secret` (read from the installed CLI's `oauth2.js`; if the CLI can't be found, skip refresh and throw `.credentialsExpired(hint: "Run `gemini` to refresh")`).
- Request: `POST …:retrieveUserQuota`, body `{}` (or `{ "project": id }` when `~/.gemini/projects.json` has one), `Authorization: Bearer …`.
- Response → windows: one bucket per `modelId` with `remainingFraction` and `resetTime`. Ring window = bucket with the **lowest** `remainingFraction`, emitted as `.session` with label "Gemini CLI quota"; up to two more buckets (next-lowest) emitted as `.other(modelId)` for the callout. `usedPercent = (1 − remainingFraction) × 100`.
- Empty bucket list (consumer AI Pro/Ultra account) → `.unsupportedAccount("Gemini CLI quota isn't available for this account")`.

### 3.4 `UsageStore`

`@MainActor @Observable final class UsageStore` with `statuses: [ProviderID: ProviderStatus]` and `order: [ProviderID]`.

- **Poll cadence:** every 60 s per enabled provider; also immediately on launch, on `NSWorkspace.didWakeNotification`, on network path change to satisfied (`NWPathMonitor`), on the provider being enabled, and on manual refresh from the callout.
- **Concurrency:** one `Task` per provider, structured, cancelled on disable. A failing provider never delays another.
- **Back-off:** on error, next attempt at 60 s × 2^n capped at 300 s; `rateLimited(retryAfter)` honors the server value; reset to 60 s on success.
- **Staleness:** a `.live` snapshot older than 300 s (because fetches keep failing) becomes `.stale(snapshot, lastError)`. The UI keeps showing the number, dimmed, with "Last updated N min ago".
- **First fetch** shows `.loading`; a first-fetch failure goes straight to `.disconnected`.
- Injected `Clock` and `HTTPClient` protocols make every behavior above testable with fakes.

## 4. The dock

### 4.1 Window

`DockPanel: NSPanel` — `styleMask [.borderless, .nonactivatingPanel]`, `level .floating`, `collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `isOpaque false`, `backgroundColor .clear`, `hasShadow false`, `isMovableByWindowBackground false` (drag is handled by `DragController` so it's vertical-only), `hidesOnDeactivate false`. `LSUIElement = YES` so there is no Dock icon and no menu bar. The panel never becomes key; hover and click handling use `NSTrackingArea` + `NSEvent` local/global monitors.

### 4.2 Geometry & tokens (from the prototype README — authoritative)

| Token | Value |
|---|---|
| Panel fill | `#0A0A0A`, opaque, no gradient, no blur |
| Panel width · padding | 110 pt · 26 top / 14 bottom / centered |
| Inner-edge radius | 30 pt (the side facing the screen); 0 on the screen edge |
| Concave flares | 26 pt quarter-circle cutouts above and below where the panel meets the edge — drawn as part of `DockShape`'s single path |
| Cell gap | 34 pt |
| Ring | 68 pt ⌀, radius 31.5, stroke 5, round caps, track `#2C2C2E`, arc from 12 o'clock clockwise |
| Inner well | r 23, `#1C1C1E`, white monochrome glyph ~26 pt |
| Percentage | 26 pt, weight 500, white, tabular numerals, 9 pt below the ring |
| Semantic colors | 0–39 `#32D74B` · 40–69 `#E4FF1A` · 70–89 `#FF4F1F` · 90–100 `#FF3B30` |
| Pulse | 90 ≤ pct < 100: opacity 1 → 0.4 → 1, 2 s ease-in-out, loop. At 100: solid, no pulse |
| Ring sweep animation | 700 ms, easing `cubic-bezier(0.32, 0.72, 0, 1)` |
| Dock slide | 260 ms same easing; translate 104 pt |
| Sliver (auto-hide rest state) | 6 pt wide; one 3 × 28 pt bar per provider in its semantic color |
| Gear | 14 pt gray glyph at the foot of the dock, opens settings |
| Type | System font (SF Pro), sizes 26 / 22 / 17 / 16 / 15 / 14 / 13 / 12 as listed in the README |

Glyphs are Pulse's own monochrome marks (starburst, knot, sparkle) drawn as SwiftUI `Path`s — **not** the providers' trademarked logos. Provider names appear as plain text.

### 4.3 Per-ring visual states

| Status | Ring | Label |
|---|---|---|
| `.loading` | gray indeterminate arc (dasharray 46/151.92), 1.1 s linear spin | none |
| `.live`, pct < 100 | semantic color, sweep = pct | `73%` |
| `.live`, pct ≥ 100 | solid red | `Limit reached` (14 pt) |
| `.stale` | as live but whole cell at 60 % opacity | pct + callout footer "Last updated N min ago" |
| `.disconnected` | gray `#5A5A5E` dashed track (3.4 / 4.6) | `—` |

### 4.4 Placement & behavior

- **Edge:** Left or Right (setting; default Right). Positioned on the screen that contains the mouse at launch; thereafter on the screen the user last dragged it on (persisted by `NSScreen.localizedName` + edge + Y fraction). On `NSApplication.didChangeScreenParametersNotification` the panel re-clamps into the current screen's `visibleFrame` (so it never sits under the menu bar or the system Dock).
- **Drag:** vertical only; 5 pt movement threshold so clicks still register; clamped to `visibleFrame`; Y fraction persisted on mouse-up.
- **Hover-peek (auto-hide on):** `EdgeTracker` uses a global mouse-moved monitor throttled to ~30 Hz. Cursor within 44 pt of the edge → expand (260 ms). Cursor more than 200 pt from the edge → collapse after a 400 ms grace, unless a callout is pinned or settings are open. State machine: `collapsed → expanding → expanded → collapsing`, tested with an injected clock.
- **Right-click** anywhere on the dock → settings panel.

## 5. The callout

`CalloutPanel` is a second non-activating floating panel, shown to the screen-inward side of the dock with a 26 pt gap and a solid triangular tail (13 pt half-height, 16 pt long) aligned to the hovered ring's center.

- Size 560 pt wide, 26 pt padding, radius 26 pt, fill `#0A0A0A`, shadow `0 18 50 rgba(0,0,0,0.45)`.
- Header: 24 pt glyph + "`<Provider>` Usage" (22 pt, weight 500) + plan badge (12 pt gray) when known.
- One block per `UsageWindow` (20 pt apart): label (17 pt white) left, reset text (17 pt `#8E8E93`, tabular) right; 7 pt bar, fully rounded, track `#2C2C2E`, fill in that window's own semantic color, `scaleX` animation 700 ms; "`N% Used`" (16 pt) beneath. The session window's row carries a small 12 pt gray "● ring" tick after its label so it's clear which window drives the dock.
- Reset text: `Resets in 51 min` · `Resets in 2 h 05 min` · `Resets in <1 min` · absolute `Resets Thu 04:50` when more than 24 h away · `—` when unknown. Recomputed every second from `resetsAt`.
- Exhausted: "Resets in 12 min" in red 20 pt semibold directly under the header.
- Stale: footer 14 pt gray "Last updated 7 min ago · tap to retry". Disconnected: body "Not signed in. Run `codex login` in Terminal." + a `Retry` pill (`#2C2C2E`, hover `#3A3A3D`).
- Open on hover (160 ms, scale 0.96 → 1, 10 pt travel toward the cursor, fade in); close 110 ms; when the hovered ring changes the panel **slides** to the new ring (220 ms) rather than re-opening. 140 ms hover grace so the cursor can travel dock → callout. Click on a ring pins; click-away or re-click unpins.

## 6. Settings

`SettingsPanel`: third floating panel, 300 pt wide, radius 22, `#0A0A0A`, 20 pt padding, anchored next to the dock. Closes on click-away, Esc, or the × button.

- **Providers** — one row each: drag handle (reorder), 18 pt glyph, name (15 pt), iOS-style toggle (38 × 23, knob 19, `#32D74B` on).
- **Alert threshold** — segmented 80 % / 90 % / 95 % (default 90).
- **Screen edge** — segmented Left / Right.
- **Auto-hide** — toggle (default off).
- **Launch at login** — toggle via `SMAppService.mainApp` (default off; the app asks nothing at first launch).
- **Check for updates automatically** — toggle (default on) + "Check now" (Sparkle).
- **About** — version, "Pulse reads usage from your local Claude / Codex / Gemini CLI sign-ins. It talks only to those providers and to GitHub for updates. No analytics." + link to the repo.
- **Quit Pulse**.

Section labels 12 pt uppercase gray, 0.6 pt tracking.

## 7. Alerts

`AlertCenter` observes `UsageStore`. For every `(provider, window)` pair it tracks the last percent seen and fires exactly once when the value crosses **upward** through the threshold, and once more when it reaches 100. It re-arms when the window's percent drops (the window reset).

- Delivered via `UNUserNotificationCenter` so Focus modes and Notification Center settings apply. Permission is requested lazily, the first time an alert would fire.
- Copy: `Claude session at 91%` · `Codex weekly limit reached — resets Thu 04:50` · `Gemini CLI quota at 95%`. Title is always "Pulse".
- Fired-state persisted (`[providerID.windowLabel: lastFiredPercent]`) so a relaunch doesn't re-fire.

## 8. Persistence

`UserDefaults.standard` only: `providerOrder`, `enabledProviders`, `edge`, `dockYFraction`, `dockScreenName`, `alertThreshold`, `autoHide`, `launchAtLogin` (mirrors `SMAppService` status), `autoUpdate`, `firedAlerts`. Nothing written elsewhere; nothing synced.

## 9. Error handling (end-to-end)

| Situation | PulseCore | UI |
|---|---|---|
| Credential file missing | `.credentialsMissing(hint)` | gray dashed ring, `—`, callout shows the exact CLI command |
| 401 / expired token (non-Gemini) | `.credentialsExpired(hint)` | same, hint says "run `claude`/`codex`" |
| Gemini expired, refresh succeeds | transparent | — |
| Gemini expired, refresh fails | `.credentialsExpired` | as above |
| Network down / DNS / timeout | `.network` | keep last snapshot; stale after 5 min; retry with back-off |
| 429 | `.rateLimited(retryAfter)` | keep last snapshot; wait `retryAfter` |
| 5xx | `.network` | same as network down |
| JSON shape changed | `.unexpectedResponse(detail)` | "Pulse needs an update for Codex"; detail in `os_log` (privacy: public only for the field path, never the payload) |
| Org / unsupported plan | `.unsupportedAccount(msg)` | disconnected with the message |
| One provider throws | contained | other rings unaffected |

Nothing in this table crashes, shows a modal, or writes to disk.

## 10. Privacy & anonymity (hard requirements)

Pulse is published anonymously on GitHub. Therefore:

1. **No personal data in the artifact.** Bundle ID `com.pulsedock.mac`. `NSHumanReadableCopyright` = "© Pulse contributors". No author name in `Info.plist`, About panel, or source headers. Git commits use a neutral identity configured per-repo (`Pulse Contributors <pulse-contributors@noreply.invalid>`).
2. **No absolute home paths** in source; every path goes through `FileManager.default.homeDirectoryForCurrentUser`.
3. **No Developer ID signature.** Ad-hoc `codesign -s -` only (see §11). Nothing in the binary carries a Team ID or certificate Common Name.
4. **`build/check-anonymity.sh`** runs after every build: greps the `.app`, the DMG, and the appcast for each line of `build/.anonymity-blocklist` (a **git-ignored, local-only** file holding the maintainer's name, email, team ID, and machine username) and fails the release if any match.
5. **Network allow-list** is documented in README and Settings → About: `api.anthropic.com`, `chatgpt.com`, `cloudcode-pa.googleapis.com`, `oauth2.googleapis.com`, `github.com` (Sparkle). No analytics, no crash reporter, no telemetry of any kind.
6. **Fixtures** committed to the repo are redacted copies (`*.json`); raw captures (`*.raw.json`) are git-ignored.
7. **Sparkle key** is generated fresh for Pulse (not reused from any other project) and lives in the git-ignored `build/.sparkle_ed_private_key`; only the public key goes in `Info.plist`.

## 11. Distribution

- **Build:** `build/release.sh <version>` — `xcodebuild archive` (Release, `CODE_SIGN_IDENTITY="-"`, `CODE_SIGNING_ALLOWED=YES`, hardened runtime off), `codesign -s - --force --deep --timestamp=none`, `build/make-dmg.sh` (`hdiutil`, app + Applications symlink, custom background off — keep it plain), `sign_update` for Sparkle, `check-anonymity.sh`, then prints the appcast `<item>`.
- **Release:** DMG + `appcast.xml` uploaded as GitHub Release assets. `SUFeedURL` points at the raw `appcast.xml` on the `main` branch of the same public repo so the URL is stable across releases.
- **Gatekeeper:** because the app is unsigned by Apple's standards, README documents the one-time bypass: *right-click → Open*, or `xattr -d com.apple.quarantine /Applications/Pulse.app`. Sparkle-delivered updates are EdDSA-verified and don't re-trigger the warning.
- **Requirements:** macOS 14 Sonoma or later, Apple silicon and Intel (universal binary).
- **License:** MIT.

## 12. Testing

**PulseCore (unit, offline, fast):**
- Each provider: decode fixture → expected `UsageSnapshot`; missing file → `.credentialsMissing`; 401 → `.credentialsExpired`; malformed JSON → `.unexpectedResponse`; Claude Keychain fallback; Gemini refresh path (fake HTTP returning a new token) and refresh-failure path; Gemini lowest-bucket selection; Codex `ChatGPT-Account-Id` header present/absent.
- `UsageStore` with `FakeClock` + `FakeHTTPClient`: initial `.loading`; success → `.live`; error keeps snapshot; stale after 300 s; back-off sequence 60/120/240/300/300; `retryAfter` honored; wake/network triggers cause immediate fetch; disabling cancels the task.
- Reset-text formatter: all branches in §5.

**App (unit where logic exists):**
- `DockShape` path bounding box and flare cutout points for left and right edges.
- `EdgeTracker` state machine with injected clock: expand on proximity, grace period, no-collapse while pinned.
- `AlertCenter`: fires once per upward crossing, again at 100, re-arms after reset, survives relaunch via persisted state.
- Semantic-color mapping at every boundary (39/40, 69/70, 89/90, 99/100).

**Manual release checklist:** both edges; two displays; over a full-screen app; Spaces switch; sleep/wake; disconnect Wi-Fi for 6 min and confirm stale; delete `~/.codex/auth.json` and confirm disconnected copy; Sparkle update from the previous release on an ad-hoc-signed install; `check-anonymity.sh` clean.

## 13. Day-1 spike (before any UI code)

Run once from a scratch script on this Mac, then commit only the redacted fixtures:

1. Claude: confirm the token in `~/.claude/.credentials.json` has `user:profile` scope and that `GET /api/oauth/usage` with the three headers returns `five_hour` / `seven_day`; record the exact JSON.
2. Codex: confirm `wham/usage` works with the `auth.json` token; record exact window field names and whether `ChatGPT-Account-Id` is required.
3. Gemini: confirm `retrieveUserQuota` returns buckets for this account; if it returns none, the Gemini ring ships as `.unsupportedAccount` for consumer accounts and the README says so.
4. Sparkle: verify that an ad-hoc-signed build updates from a previous ad-hoc-signed build without a Gatekeeper prompt.

Findings feed straight into the fixtures and, if needed, a one-line amendment to §3.3.

## 14. Risks

- **Unofficial endpoints.** All three usage APIs are undocumented; a change breaks a ring. Mitigation: decoders are tolerant (optional fields), failures degrade to `.unexpectedResponse` not crashes, and fixtures make the fix a one-file change.
- **Claude 429 bucket** if the User-Agent drifts from what Anthropic expects. Mitigation: read the real installed CLI version; honor `Retry-After`.
- **Gemini consumer accounts** may show nothing. Mitigation: clear copy; v1.1 cookie path.
- **Name collision** — "Pulse" is common. Nothing depends on it; rename is a display-string change before the first public release.
- **Keychain fallback prompt.** If `~/.claude/.credentials.json` is absent and Pulse falls back to the `Claude Code-credentials` Keychain item, macOS shows a one-time "Pulse wants to access…" prompt; the callout hint tells the user to choose *Always Allow*. The file path is tried first precisely so most users never see this.

## 15. Amendments (2026-08-30)

Changes made during implementation that this design did not anticipate:

- **Claude credentials are file-first.** An unexpired `~/.claude/.credentials.json` is returned without reading the Keychain at all; the Keychain is consulted only when the file is missing, undecodable, or expired, and a denied or otherwise unavailable Keychain latches off for the life of the process so a polling app never re-prompts.
- **Credential-class failures are scheduled by kind.** `credentialsMissing` retries at the normal interval (a sign-in fixes it at any moment), `credentialsExpired` backs off exponentially to `maxBackoff`, and `unsupportedAccount` re-checks every 30 minutes (`PollPolicy.unsupportedInterval`).
- **Shape drift and unsupported accounts are distinguished.** A body carrying none of a provider's known usage keys is `.unexpectedResponse("<provider>: no known usage windows")`; a body that carries them but yields no window is `.unsupportedAccount`.
- **Claude's `limits[]` array is mapped.** Each entry with `kind: "weekly_scoped"` and `is_active: true` becomes an extra window labeled `"<model display name> weekly"`, since per-model weekly allowances appear there rather than under a fixed top-level key.
- **Captures land in `PulseCore/.captures/`.** `pulse-cli capture` derives that directory from `#filePath` instead of the working directory; it and every `*.raw.json` in the tree are git-ignored, and redaction copies a scrubbed file into `Tests/PulseCoreTests/Fixtures/`.
- **Settings toggles keep AppKit's switch metrics.** §6 asks for 38 × 23 switches; SwiftUI's `.toggleStyle(.switch)` renders the system size and offers no way to change it. Custom-drawing one to hit the spec's 38 × 23 would cost the accessibility, keyboard focus, Reduce Motion and Increase Contrast behavior AppKit gives for free, for two points of width — so the switches stay stock, tinted `Palette.green`, and the number in §6 is historical.

Release decisions (2026-08-30), the operational ones being spelled out in `docs/RELEASING.md`:

- **Publish order is DMG before feed.** The feed is fetched from `main`, so the version-bump commit is pushed first, the tagged release and DMG are created second, and `appcast.xml` is committed and pushed only once the download exists. `build/release.sh` prints the same three steps.
- **The committed `appcast.xml` is the feed's history.** `release.sh` seeds `build/out/appcast.xml` from the tracked file on every run (dropping any item for the version being built, so a re-release cannot leave a phantom item with a stale signature), generates with `--maximum-deltas 0` under `TZ=UTC`, and asserts before copying back that the newest item is this run, every enclosure resolves to its own tag, and no two items share a URL. `build/out/` is expected to hold only the DMG being released.
- **The public repository starts as a squashed snapshot.** Development history carries the maintainer's home path and search terms in early commits, so the first publish cuts an orphan snapshot from the merged `main` (excluding `appcast.xml` until the DMG is uploaded) and the full history stays local as `private-history`.
- **Gatekeeper wording is observed, not guessed.** On macOS 26 a quarantined ad-hoc app shows *"Pulse" Not Opened — Apple could not verify "Pulse" is free of malware…* with only *Move to Trash* / *Done*; right-click → Open no longer bypasses it. The README leads with `xattr -dr com.apple.quarantine` and documents Settings → Privacy & Security → *Open Anyway* (admin credentials).
- **The updater gate stays https-only.** Local end-to-end update tests temporarily widen `UpdaterGate` to `http://localhost` in an uncommitted throwaway build; the shipped gate is covered by `UpdaterGateTests`.
- **`DockWindowController.show()` never orders a parked dock front.** A slide-parked dock sits at its hidden frame, which is another display's desktop when one abuts the edge, so `show()` (now used on screen-parameter changes) re-orders the panel only while not collapsed.

## 16. UI v2 (2026-08-30)

The designer's revised handoff in `design/v2/` slims the dock and re-materializes the callout;
`design/v2/` (README, `CHANGES.md`, prototype, screenshots) now supersedes `design/prototype/`
as the pixel source, and §4.2 and §5 above are historical for every value the table below
restates. The dock shrinks by roughly a third — 78 pt wide with 48 pt rings and a 16 pt
percentage — so it reads as an edge accessory rather than a second Dock, and the callout
compacts to 320 pt to match. The callout stops being an opaque black card: it becomes frosted
glass over the desktop, and its entry animation changes from a scale-and-slide to "glass
frost", a de-blur that replays every time hover moves to another ring. Everything else —
colors, semantic thresholds, timings, settings, banner, behaviors — is unchanged.

### 16.1 Tokens (old → new)

| Token | v1 | v2 |
|---|---|---|
| Panel width | 110 | **78** |
| Padding top / bottom | 26 / 14 | **18 / 10** |
| Cell gap | 34 | **22** |
| Inner-edge radius | 30 | **22** |
| Concave flares | 26 | **20** |
| Ring ⌀ · stroke | 68 · 5 | **48 · 3.5** (circumference 138.23) |
| Inner well radius · glyph | 23 · 26 | **16.5 · 18** |
| Percentage · gap below ring | 26 pt · 9 | **16 pt · 7** ("Limit reached" 14 → **11**) |
| Label row height | 31 | **20** |
| Cell height | 108 | **75** |
| Gear row · glyph | 24 · 14 | **20 · 13** |
| Dock slide distance | 104 | **72** (panel width − sliver) |
| Sliver bar | 3 × 28 | **3 × 22** |
| Callout width · radius | 560 · 26 | **320 · 16** |
| Callout padding | 26 | **16 vertical / 18 horizontal** |
| Callout gap from dock | 26 | **24** |
| Tail half-height · length | 13 · 16 | **9 · 11** |
| Callout header glyph · title | 24 · 22 medium | **17 · 15 semibold** |
| Callout blocks apart | 20 | **14** |
| Row label · reset | 17 · 17 | **13 · 12** ("● ring" tick 12 → **10**) |
| Bar height | 7 | **5** |
| "N% Used" | 16 white | **12 gray**, 6 pt above |
| Exhausted reset line | 20 | **14** semibold red |
| Disconnected body · Retry | 17 · 15 | **13 · 12** |
| Stale footer · plan badge | 14 · 12 | **11 · 10** |

Three cells therefore measure 18 + 3 × 75 + 2 × 22 + 20 + 10 = **317 pt** tall in a **78 pt**
panel, and the window adds a 20 pt flare margin at each end. `DockLayout.flareInset` now reads
`Metrics.flareRadius` so the two can no longer drift apart.

### 16.2 Callout material — frosted glass

The card is `rgba(16,16,18,.55)` over live vibrancy, with a 1 pt `rgba(255,255,255,.14)`
border, a 1 pt `rgba(255,255,255,.12)` top inset highlight, and a `0 12 18 rgba(0,0,0,.32)`
shadow; the tail turns translucent `rgba(20,20,23,.72)` to match.

The vibrancy is an `NSVisualEffectView` (`.hudWindow`, `blendingMode .behindWindow`,
`state .active`) rather than a SwiftUI material: SwiftUI's materials blur what is *inside* the
window, and the callout's window is transparent, so only the AppKit view samples the desktop
behind it. It lives inside `CalloutContainerView` as a sibling *behind* the SwiftUI hosting
view — not as its superview — because it is rectangular: the hosting view spans the whole
window while the effect view is inset by `tailLength` on whichever side the tail points, so the
glass covers the card only and never draws a square block around the triangle. Its layer takes
the 16 pt corner radius and the border. The panel keeps `hasShadow = false`.

### 16.3 Entry animation — "glass frost"

`CalloutModel` carries `isPresented` and `frostKey`. `isPresented` fades the card in over
300 ms ease-out. `frostKey` is incremented on every `show` **and** every `move`; the card snaps
to `blur(14)` + `opacity(0)` without animation, then de-blurs over 600 ms on the house easing
`cubic-bezier(0.32, 0.72, 0, 1)`, with the opacity leg running at 40 % of that (240 ms) so the
text is legible well before the blur has finished. Because the replay is keyed rather than
triggered on appear, sliding between rings re-frosts while the window glides its existing
220 ms, which reads as a fresh callout instead of a card whose text swapped mid-flight. The
110 ms fade-out on `hide` is unchanged.

## 17. UI v3 (2026-08-30)

`design/v3/` adds two things on top of v2 and changes nothing else: the auto-hide resting
state becomes a frosted **glass handle with glow dots** (with the dock retracting fully
off-screen behind it), and the dock's material becomes a **user setting** — Notch, the
original opaque slab, or Glass, a flare-less frosted one. `design/v3/CHANGES.md` §5 and §6 are
the pixel source; §1–§4 of that file are v2 and are already recorded in §16 above.

### 17.1 Auto-hide — glass handle, dock fully off-screen

The v2 collapsed sliver is gone. Hiding the dock is now a pure translation: the panel keeps
its one size and slides to `x = screen.frame.maxX` on the right edge (`minX − width` on the
left) over the house 260 ms `cubic-bezier(0.32, 0.72, 0, 1)`, then orders out. Parking it past
the *physical* display rather than past `visibleFrame` matters on a screen whose macOS Dock
occupies the same edge, where `visibleFrame` stops short of the bezel and a panel left there
would still be on screen. Because the window no longer resizes as it hides, `DockLayout` lost
its `collapsed` variant entirely: one geometry, `windowSize` always carrying the flare margin.

The resting UI is a second window. `HandleLayout` is its pure geometry — 9 pt wide, 14 pt
padding at each end, one 5 pt dot per enabled provider with 13 pt gaps, so three dots measure
69 pt — and `DockPositioner.frame` places it flush to the edge at the dock's own `yFraction`,
which keeps it where the dock will come back. `HandlePanel`'s content view *is* an
`NSVisualEffectView` (`.hudWindow`, `.behindWindow`, `state .active`, appearance pinned to
`.darkAqua`), masked by a `CAShapeLayer` to `EdgeSlabPath` — a rounded rectangle rounded on one
vertical side only, 6 pt on the two inward corners, square against the edge. The 1 pt
`rgba(255,255,255,.16)` border is a second `CAShapeLayer` following that same path, because a
layer-level `borderWidth` would trace the full rectangle including the corners the mask cuts.
`HandleView` draws only the dots — each in its `UsageLevel` color, or `#5A5A5E` while loading
or disconnected, with a `radius 4.5` shadow at 90 % alpha standing in for
`box-shadow: 0 0 9px` — so the frost is never painted twice.

The two crossfade: handle alpha 1 → 0 over `Motion.handleFade` (250 ms) as the dock slides in,
0 → 1 as it slides out, and the handle is shown only while auto-hide is on. It sits inside the
44 pt proximity band, so hovering it expands the dock like any other edge touch.

### 17.2 Dock style — Notch / Glass

`DockStyle` (`notch` | `glass`) persists under `dockStyle`, defaults to `notch`, and falls back
to `notch` for anything unrecognised. A "Dock style" segmented control sits under "Screen edge"
in settings. (`design/v3/README.md` lists it *above* "Screen edge"; the two controls are
adjacent either way and the implementation follows the handoff brief's ordering.)

| | Notch | Glass |
|---|---|---|
| Fill | `#0A0A0A` opaque | `rgba(16,16,18,.55)` over live vibrancy |
| Flares | 20 pt concave quarter-circles | none — bounding box is the panel rect |
| Inward radius | 22 pt | 22 pt |
| Border | none | 1 pt `rgba(255,255,255,.14)` along the same path |
| Highlight | none | 1 pt `rgba(255,255,255,.12)` inset at the top, clipped to the silhouette |
| Shadow | none | `0 12 18 rgba(0,0,0,.30)`, spilling into the flare margin |

`DockShape` takes the style and switches paths; the flare margin is kept in both, since Glass
needs it for the shadow. The vibrancy is an `NSVisualEffectView` sibling *behind* the hosting
view in `DockInteractionView`, configured exactly like the callout's and masked to the glass
path, hidden outright in Notch. It is updated from the `layout`/`style` setters and
`setFrameSize(_:)` rather than a `layout()` override, which cannot be declared while a stored
property of the same name exists. The handle is style-independent: always glass.

Measured on a live run, the Notch panel samples `(10, 10, 10)` and the Glass panel
`(23, 25, 31)` over a `(34, 39, 51)` desktop — the tint and vibrancy both doing their work.
