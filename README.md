# Tokenly

A black dock that lives on the edge of your Mac's screen and shows, at a glance, how much of each AI subscription's usage limit you have used — one ring per provider, a hover callout with every limit window and when it resets, and a notification before you hit the wall.

Every number is real. Tokenly reads the OAuth token that the provider's own CLI already stores on your Mac and asks that provider's usage API. It never estimates, never scrapes a web page, and sends each token only to the provider that issued it.

| Ring | Reads | Talks to |
|---|---|---|
| Claude | `~/.claude/.credentials.json`, or the Keychain item Claude Code keeps | `api.anthropic.com` |
| Codex | `~/.codex/auth.json` | `chatgpt.com` |
| Gemini | `~/.gemini/oauth_creds.json` | `cloudcode-pa.googleapis.com`, `oauth2.googleapis.com` (token refresh) |

Sign in once with `claude`, `codex`, or `gemini` in Terminal and the ring lights up. Consumer Google accounts (AI Pro/Ultra) are not entitled to the Code Assist quota API and show as *not available for this account*.

## Install

Requires macOS 26 (Tahoe) or later, Apple silicon or Intel. Download `Tokenly-<version>.dmg` (about 2.5 MB) from the latest release and drag Tokenly to Applications.

macOS will refuse the first launch. It shows **"Tokenly" Not Opened** — *"Apple could not verify "Tokenly" is free of malware that may harm your Mac or compromise your privacy"* — and offers only *Move to Trash* and *Done*. Click **Done**; there is no "open anyway" in that dialog, and the old right-click → Open trick no longer works. Then either:

- **Terminal** (always works, nothing to authenticate):

      xattr -dr com.apple.quarantine /Applications/Tokenly.app

  and open Tokenly normally; or

- **System Settings → Privacy & Security**, scroll to *Security*, and click **Open Anyway** beside *"Tokenly" was blocked to protect your Mac.* It asks once more, then wants an administrator's Touch ID or password.

This is what an unsigned, anonymously published app looks like: there is no Apple Developer ID behind Tokenly and nothing notarized (see *Privacy*). It is a one-time step — updates arrive through Sparkle and do not repeat it.

Turning on **Launch at login** may need a second step: if the settings panel says so, approve Tokenly in System Settings → General → Login Items & Extensions.

## Use

- Hover a ring for the details; click to pin the callout.
- Drag the dock up or down. Right-click it, or click the gear, for settings: provider order and on/off, alert threshold (80/90/95 %), left or right edge, dock shape (Notch / Pill) and size (Small / Medium / Large), auto-hide, launch at login, and an **Automatic updates** toggle.
- Ring color is urgency, not brand: green → yellow → orange → red, and it breathes when you are within 10 % of a limit.

## Privacy

- No analytics, no crash reporting, no telemetry. The only hosts Tokenly contacts are the ones in the table above, plus the update feed on GitHub.
- Nothing is written to your credential files; a refreshed Gemini token lives only in memory.
- Tokenly is published anonymously and signed ad-hoc rather than with an Apple Developer ID, so macOS refuses the first launch until you clear the download flag — see *Install*.
- Reading the Claude Keychain item shows a macOS prompt; Tokenly asks only when the credentials file is missing or expired, and stops asking if you decline. It asks once per app version, because the ad-hoc signature changes with every build and macOS treats each new version as a different program — click *Always Allow*.

## Build from source

Needs Xcode 26 (Swift 6.2+; the code uses `isolated deinit`) and the macOS 26 SDK.

    brew install xcodegen
    cd Pulse && xcodegen generate
    xcodebuild build -project Pulse.xcodeproj -scheme Pulse -configuration Debug -derivedDataPath build/dd

The Xcode project, its scheme and the Swift package keep their original `Pulse` names — those are
code, not brand; the built product is `Tokenly.app`.

The data layer is the `PulseCore` Swift package (`swift test` inside it; `swift run pulse-cli usage` prints your numbers in the terminal).

## License

MIT — see `LICENSE`.
