# Releasing Tokenly

Tokenly is published anonymously: ad-hoc signed, no notarization, no Developer ID, no telemetry.
Nothing in this process uploads or pushes anything — you do that by hand. (The build itself is not
strictly offline: on a fresh clone `xcodebuild` resolves Sparkle from GitHub.)

## One-time setup (this machine only, never committed)

- `build/release.env` — `PULSE_REPO=owner/repo`, the GitHub repo that hosts releases. Use an account
  that is not connected to your identity; the URL ends up inside every copy of the app.
- `build/.sparkle_ed_private_key` — created once with `generate_keys -x`. Back it up somewhere private.
  Losing it means existing installs can never accept another update.
- `build/.anonymity-blocklist` — one line per string that must never appear in an artifact
  (your name, handles, e-mail, team ID, macOS username).

All three are git-ignored. Never read them into a terminal that is being recorded or transcribed.

Run every release and snapshot command with `TZ=UTC` (`export TZ=UTC` once in the release shell) so
commit timestamps and feed dates do not carry your timezone: an author date at `+0400` narrows a
"published anonymously" repo to one part of the world. `release.sh` already forces it for the
appcast's `pubDate`; git's own timestamps are up to the shell you commit from.

## Each release

Before you start, clear `build/out/` down to nothing (or to the DMG you are about to replace). The
script signs and re-stamps **every** DMG it finds there with this release's download URL, so a stale
one from an abandoned run would be published under the wrong tag. Prior versions do not need their
DMGs on disk: the feed's history is re-seeded from the committed `appcast.xml` on every run.

1. `build/release.sh <version> "<one-line note>"` — bumps `project.yml`, builds a universal Release,
   ad-hoc signs Sparkle's nested bundles and the app, packages `build/out/Tokenly-<version>.dmg`
   (about 2.5 MB), runs the anonymity gate, signs the appcast with EdDSA, and copies `appcast.xml`
   to the repo root. It stops there and prints what to upload. If it fails after the version bump it
   restores `project.yml` itself, so a failed run leaves nothing half-done.

2. Commit the version bump and push `main`:

       git add Pulse/project.yml Pulse/Pulse.xcodeproj Pulse/Pulse/Info.plist
       git commit -m "chore(release): <version>"
       git push

3. Create the GitHub release `v<version>` **on that commit** and upload `build/out/Tokenly-<version>.dmg`
   (web UI, or `gh release create v<version> build/out/Tokenly-<version>.dmg`).

4. Only once that download actually exists, publish the feed:

       git add appcast.xml
       git commit -m "chore(release): appcast <version>"
       git push

   The order matters because the feed URL baked into every installed copy is
   `https://raw.githubusercontent.com/<repo>/main/appcast.xml`: pushing the appcast before the DMG
   exists advertises an enclosure that 404s, and every installed copy fails its update check until
   the upload lands. `build/release.sh` prints these same three steps when it finishes — if you
   change one, change the other so they never disagree.

5. Existing installs pick the update up within a day (`SUScheduledCheckInterval`), or immediately on
   *Check now* in settings.

6. Update the website: in the tokenly.site source, point the download section's button at
   `…/releases/download/v<version>/Tokenly-<version>.dmg`, refresh the size and version in the meta
   line beneath it, and redeploy. The button links a pinned version on purpose — `releases/latest`
   cannot name an asset whose filename changes every release.

From 0.2.0 on the feed carries `<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>`
without anyone typing it: `generate_appcast` reads `LSMinimumSystemVersion` out of the app inside
the DMG, and that is now 26.0. The 0.1.0 item keeps its own 14.0, so a 0.1.0 install on macOS 14 or
15 stays on 0.1.0 instead of being offered an update it cannot run.

### The rename (before 0.2.0)

The product and the repository were renamed `pulse` → `tokenly` before 0.2.0. `raw.githubusercontent`
feed URLs do **not** redirect across a repository rename, so the briefly-public 0.1.0 (Pulse) installs
are orphaned from updates: their baked-in `SUFeedURL` still points at the old path and will never see
another item. Accepted — near-zero installs, and 0.2.0 requires macOS 26 anyway, so most of them
could not take the update even if they saw it.

The 0.1.0 item stays in `appcast.xml` (dropping it would cost Sparkle the history it uses for
skipped-version logic), so its enclosure still reads `…/itsSwanks/pulse/…/Pulse-0.1.0.dmg`.
`assert_appcast` grandfathers exactly that one pre-rename shape in its per-item URL check; the item
being released is still held to the exact current `…/itsSwanks/tokenly/…/Tokenly-<version>.dmg`.

## First publish

1. **Build the release from the tree you are about to publish.** On the merged, tested `main`, run
   *Each release* step 1 (`build/release.sh <version> "<one-line note>"`) before cutting the snapshot
   below. **The DMG you upload must come from the tree you snapshot** — a DMG already sitting in
   `build/out/` from an earlier run predates every app change that landed since, so publishing it
   would ship a binary that does not match the published source.

2. **Scan the whole history.** The working tree can be clean while the history is not: an early
   planning document carried the maintainer's own home-directory paths and search terms, and the
   later scrub commit removed them from the tree but not from the commits that introduced them.
   Before anything leaves this machine, scan every commit on every branch:

       git log -p --all | grep -nE '/Users/[A-Za-z0-9._-]+/' | head -5
       while IFS= read -r needle || [ -n "$needle" ]; do
         [ -n "$needle" ] && git log -p --all | grep -qiF -- "$needle" && echo "HISTORY HIT: ${needle:0:3}…"
       done < build/.anonymity-blocklist

   The `|| [ -n "$needle" ]` is not decoration: a hand-edited blocklist saved without a trailing
   newline would otherwise have its last line silently skipped (`check-anonymity.sh` reads it the
   same way).

   If **both** print nothing, the existing history can be published as-is. If **either** prints
   anything — as it does for Tokenly's development history — the public repository is cut as a single
   squashed snapshot instead, so the leak never leaves this machine.

3. **Cut and push the snapshot.** Cut it from the merged, tested `main` *after* the last change meant
   for the first release has landed, and push it in the same DMG-before-appcast order as any release
   (see *Each release*): the snapshot must not carry an `appcast.xml` that points at a download which
   does not exist yet.

       git checkout main                          # the merged, tested tree
       git checkout --orphan public
       git rm -r --cached . -q && git add -A      # stage the snapshot from a clean index (.gitignore applies)
       git rm --cached -q appcast.xml             # the feed is committed only after the DMG exists
       git commit -m "Tokenly <version>"
       git push -u origin public:main             # a. the snapshot becomes the public main

       # b. create the GitHub release v<version> on that commit and upload build/out/Tokenly-<version>.dmg

       git add appcast.xml
       git commit -m "chore(release): appcast <version>"
       git push origin HEAD:main                  # c. the feed goes live (plain `git push` is refused
                                                  #    here: the branch is still named `public`)

4. **Retire the private history** so nothing pushes it by accident:

       git branch -m main private-history         # keep it local; never push it
       git branch -m public main                  # from here on, plain `git push` works

Only now switch the GitHub repository to public. Every later release commits on top of the snapshot
as normal, and `private-history` can be deleted once nothing in it is still needed. Tokenly's first
release follows this path: its public `main` starts as a squashed snapshot, and the full development
history stays private and local.

## What users see the first time

macOS refuses the first launch of a downloaded copy — double-click, right-click → Open and `open`
from Terminal all end the same way, and the right-click → Open bypass no longer exists. The dialog
reads:

> **"Tokenly" Not Opened**
> Apple could not verify "Tokenly" is free of malware that may harm your Mac or compromise your privacy.

with only *Move to Trash* (the default button) and *Done*. There is no "open anyway" in that dialog.
Two ways past it, both documented in the README:

- `xattr -dr com.apple.quarantine /Applications/Tokenly.app`, then open Tokenly normally. Always works,
  no authentication.
- System Settings → Privacy & Security → **Security**, where a row appears after the refused launch:
  *"Tokenly" was blocked to protect your Mac.* with an **Open Anyway** button. It asks to confirm
  ("Open "Tokenly"? Apple is not able to verify that it is free from malware…") and then requires an
  administrator's Touch ID or password. The row disappears again if the launch is not completed.

Sparkle-installed updates do not repeat any of this — the updater replaces the bundle in place and
no quarantine flag is attached.

Separately, reading the Claude Keychain item prompts once per app version, because the ad-hoc
signature changes with every build and macOS treats each version as a different program. *Always
Allow* answers it for that version.

## Testing an update locally

`UpdaterGate` only starts Sparkle when `SUFeedURL` is an `https` URL, so this needs a throwaway build
that is never committed: widen that guard to accept `http://localhost` too, add
`NSAllowsLocalNetworking` to the App Transport Security dictionary in `Pulse/project.yml`, and set
`SUFeedURL` to `http://localhost:8765/appcast.xml`. `release.sh` hard-codes the GitHub
`--download-url-prefix`, so the feed it writes points at github.com whatever directory it is served
from — build both versions with it, then sign a local feed by hand in a staging directory of its own:

    rm -f build/out/*.dmg build/out/*.html      # release.sh re-stamps every DMG it finds, staged ones included
    build/release.sh 0.9.0 "Update test base."
    mv build/out/Tokenly-0.9.0.* /tmp/          # keep the installer, out of the next run's way
    build/release.sh 0.9.1 "Update test."
    mkdir -p /tmp/TokenlyFeed && cp build/out/Tokenly-0.9.1.dmg build/out/Tokenly-0.9.1.html /tmp/TokenlyFeed/
    . build/sparkle-tools.sh
    "$SPARKLE_BIN/generate_appcast" --embed-release-notes --ed-key-file build/.sparkle_ed_private_key \
      --download-url-prefix "http://localhost:8765/" --maximum-deltas 0 /tmp/TokenlyFeed
    ( cd /tmp/TokenlyFeed && python3 -m http.server 8765 )

The `mv` matters: a 0.9.0 DMG still in `build/out/` when 0.9.1 is built gets its enclosure URL
re-stamped with the v0.9.1 tag, and `assert_appcast` refuses that feed.

Install `/tmp/Tokenly-0.9.0.dmg` somewhere ad-hoc-signed and hit *Check now*: Sparkle should offer
0.9.1, install it and relaunch into it. Afterwards throw all of it away —
`git checkout -- Pulse appcast.xml`, re-run `xcodegen generate`, `rm -rf /tmp/TokenlyFeed /tmp/Tokenly-0.9.0.*`,
and clear the throwaway DMGs out of `build/out/`. `appcast.xml` is in that list because `release.sh`
copies every run's feed over the tracked file, and the next real release seeds its history from it.
Never commit a build that trusts a plaintext feed.

## Manual checklist before tagging (`docs/DESIGN.md` §12)

Both edges · two displays if available · over a full-screen app · Spaces switch · sleep/wake ·
Light and Dark mode · Reduce Transparency on · Reduce Motion on · all three dock sizes · both
shapes · turn Wi-Fi off for 6 minutes and confirm the rings show stale · delete
`~/.codex/auth.json` → disconnected copy, restore → live · Sparkle update from the previous
release on an ad-hoc-signed install · `build/check-anonymity.sh` clean on the .app and the DMG.
