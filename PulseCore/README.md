# PulseCore

Foundation-only Swift package that reads real AI usage limits from the OAuth tokens
the official CLIs already store on your Mac. No UI, no network besides the providers.

| Provider | Credential read (never written) | Endpoint |
|---|---|---|
| Claude | `~/.claude/.credentials.json` or Keychain `Claude Code-credentials` | `api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/auth.json` | `chatgpt.com/backend-api/wham/usage` |
| Gemini | `~/.gemini/oauth_creds.json` (refreshed in memory only) | `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` |
| Gemini (token refresh) | same file's refresh token | `oauth2.googleapis.com/token` |

Claude: the credentials file is read first, and the Keychain item only if that file is missing, undecodable, or expired. Reading it shows a one-time macOS prompt (*"Pulse wants to access…"*) — choose **Always Allow**; if it is denied, Pulse stops asking for the rest of the session rather than prompting on every poll.

Gemini: consumer Google accounts (AI Pro/Ultra) are not entitled to the Code Assist quota API and show as *not available for this account*; only Standard/Enterprise Code Assist tiers report numbers.

## Try it

    swift run pulse-cli usage

## Test

    swift test

`Tests/PulseCoreTests/Fixtures/claude.json` and `codex.json` are redacted captures of real
responses. `gemini.json` and `gemini-load-code-assist.json` are **synthetic** — written by hand to
the documented shape, because the account these were developed against is not entitled to the Code
Assist quota API and so never returned a populated body.

`swift run pulse-cli capture` writes fresh `*.raw.json` captures into `PulseCore/.captures/`
when a provider changes its API. That directory and every `*.raw.json` file anywhere in the tree
are git-ignored, so an unredacted capture can never be committed; the capture command prints the
absolute destination when it starts. Redaction is a separate, deliberate step: scrub the raw file
by hand and copy the scrubbed version into `Tests/PulseCoreTests/Fixtures/<name>.json`, which is
what the tests load.

## Privacy

This package sends each token only to the provider that issued it. It never writes credential files,
never stores anything, and contains no telemetry.
