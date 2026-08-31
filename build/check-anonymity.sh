#!/usr/bin/env bash
# Fails if any artifact carries personal data. Two layers:
#   1. built-in patterns that identify *any* maintainer (home paths, team IDs in signatures)
#   2. the maintainer's own strings from the git-ignored build/.anonymity-blocklist (one per line)
# Usage: build/check-anonymity.sh <file-or-dir>...   (an .app, a .dmg, appcast.xml, Info.plist, …)
#
# Bash pitfalls this file deliberately avoids — do not reintroduce them:
#   1. pipefail + `grep -q` SIGPIPE: piping a producer straight into `grep -q`
#      under `set -o pipefail` lets grep exit the instant it finds a match,
#      which can SIGPIPE-kill the still-writing producer; pipefail then
#      reports the pipeline as failed even though grep matched. Capture the
#      producer's output into a variable first, then grep the captured text
#      via a here-string (`<<<`) instead of a live pipe.
#   2. pipeline subshell scoping: `producer | some_function` runs
#      some_function in a subshell, so any shell variable it sets (e.g. this
#      script's `status`) never reaches the parent shell — a violation gets
#      printed but the exit code silently stays 0. Feed functions that mutate
#      shell state via a captured here-string, never via a live pipe.
#   3. `read` silently dropping a final line with no trailing newline: plain
#      `while read -r line; do …; done < file` skips the last line of a file
#      that doesn't end in \n (blocklists are hand-edited and easy to save
#      without one). Use `while IFS= read -r line || [ -n "$line" ]`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
BLOCKLIST="${PULSE_BLOCKLIST:-$ROOT/build/.anonymity-blocklist}"
status=0
violation() { echo "ANONYMITY VIOLATION: $1 in $2" >&2; status=1; }

scan_text() {                          # $1 = label, stdin = text
  local label="$1" text; text="$(cat)"
  local home_hits
  home_hits="$(grep -oE '/Users/[A-Za-z0-9._-]+' <<<"$text" || true)"
  if [ -n "$home_hits" ] && grep -qv '^/Users/Shared$' <<<"$home_hits"; then
    violation "home directory path" "$label"
  fi
  if [ -f "$BLOCKLIST" ]; then
    while IFS= read -r needle || [ -n "$needle" ]; do
      needle="${needle%$'\r'}"
      needle="${needle%"${needle##*[![:space:]]}"}"
      [ -z "$needle" ] && continue
      if grep -qiF -- "$needle" <<<"$text"; then
        if [ "${#needle}" -gt 4 ]; then
          violation "blocklisted string '${needle:0:3}…'" "$label"
        else
          violation "blocklisted string [short entry]" "$label"
        fi
      fi
    done < "$BLOCKLIST"
  fi
}

scan_dmg() {
  local p="$1" mnt
  mnt="$(mktemp -d)"
  hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$p" >/dev/null
  # Safety net for a crash mid-scan: on bash's RETURN trap, a function's own
  # trap is NOT auto-cleared when it returns (verified on macOS's stock
  # /bin/bash 3.2.57 — it stays registered and fires on the *next* function
  # return anywhere in the script, tripping `set -u` on `$mnt` there). So the
  # trap below is explicitly unregistered on the normal-completion path;
  # it only ever fires for real if something errors out before reaching that.
  trap 'hdiutil detach "$mnt" -quiet 2>/dev/null || true; rm -rf "$mnt"' RETURN
  scan_path "$mnt"
  hdiutil detach "$mnt" -quiet
  scan_text "$p (raw image)" <<<"$(strings -n 8 "$p")"
  trap - RETURN
}

scan_path() {
  local p="$1"
  if [ -d "$p" ]; then
    while IFS= read -r -d '' f; do scan_path "$f"; done < <(find "$p" -type f -print0)
    return
  fi
  case "$p" in
    *.dmg)
      scan_dmg "$p"
      ;;
    *.plist|*.xml|*.txt|*.md|*.json|*.html)
      scan_text "$p" < "$p"
      ;;
    *)
      local kind; kind="$(file "$p")"
      if grep -qE 'Mach-O' <<<"$kind"; then
        scan_text "$p" <<<"$(strings -n 6 "$p")"
        local sig; sig="$(codesign -dv "$p" 2>&1 || true)"
        if grep -qE 'TeamIdentifier=[A-Z0-9]{10}' <<<"$sig"; then violation "TeamIdentifier in code signature" "$p"; fi
        if ! grep -q 'Signature=adhoc' <<<"$sig"; then violation "non-ad-hoc signature" "$p"; fi
      else
        scan_text "$p" <<<"$(strings -n 8 "$p")"
      fi
      ;;
  esac
}

[ $# -gt 0 ] || { echo "usage: $0 <path>..." >&2; exit 2; }
[ -f "$BLOCKLIST" ] || echo "note: $BLOCKLIST not found — only built-in patterns are checked" >&2
for p in "$@"; do scan_path "$p"; done
[ $status -eq 0 ] && echo "anonymity check passed"
exit $status
