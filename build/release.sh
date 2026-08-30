#!/usr/bin/env bash
# Build, ad-hoc sign, package and Sparkle-sign one Pulse release. Performs no upload or push;
# on a fresh clone xcodebuild resolves Sparkle from GitHub.
# Usage: build/release.sh <version> ["one-line release note"]
#   e.g. build/release.sh 0.1.0 "First public release."
# Needs: build/release.env (PULSE_REPO=owner/repo), build/.sparkle_ed_private_key, a prior app build
# so SPM has resolved Sparkle, and build/.anonymity-blocklist for the gate.
set -euo pipefail
VERSION="${1:?usage: release.sh <version> [note]}"
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "release: version must be MAJOR.MINOR.PATCH (got '$VERSION')" >&2; exit 1; }
NOTE="${2:-Pulse ${VERSION}.}"
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
OUT="$ROOT/build/out"
DD="$ROOT/Pulse/build/dd"
PROJ="$ROOT/Pulse/Pulse.xcodeproj"
APP="$DD/Build/Products/Release/Pulse.app"
KEY="$ROOT/build/.sparkle_ed_private_key"
[ -f "$ROOT/build/release.env" ] || { echo "missing build/release.env (PULSE_REPO=owner/repo)" >&2; exit 1; }
# shellcheck disable=SC1091
. "$ROOT/build/release.env"
[ -n "${PULSE_REPO:-}" ] || { echo "PULSE_REPO not set in build/release.env" >&2; exit 1; }
[ -f "$KEY" ] || { echo "missing $KEY — run generate_keys -x once (Task 3)" >&2; exit 1; }
. "$ROOT/build/sparkle-tools.sh"
DL_PREFIX="https://github.com/${PULSE_REPO}/releases/download/v${VERSION}/"

# generate_appcast signs *every* DMG left in build/out/ and stamps them all with this run's
# --download-url-prefix, so one stale DMG from an abandoned run would be published with a URL that
# belongs to a different tag — and, if its build number is higher, would become the update Sparkle
# offers. Refuse to publish such a feed instead of deleting DMGs (deleting would silently reduce
# every feed to a single item and drop the history Sparkle needs for delta/skipped-version logic).
# Self-contained on purpose: takes everything it needs as arguments so it can be exercised alone.
# Usage: assert_appcast <appcast.xml> <version> <build> <download-url-prefix> <repo-url>
assert_appcast() {
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, version, build, prefix, repo_url = sys.argv[1:6]
SP = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"

items = ET.parse(path).getroot().findall("./channel/item")
if not items:
    sys.exit("appcast assertion failed for %s:\n  - no <item> in the feed" % path)

def sparkle(item, tag):
    el = item.find(SP + tag)
    return (el.text or "").strip() if el is not None else ""

def enclosure_url(item):
    el = item.find("enclosure")
    return (el.get("url") or "").strip() if el is not None else ""

bad, rows = [], []
for n, item in enumerate(items, 1):
    ver, short, url = sparkle(item, "version"), sparkle(item, "shortVersionString"), enclosure_url(item)
    label = "item %d (%s)" % (n, short or "no shortVersionString")
    if not ver.isdigit():
        bad.append("%s: sparkle:version %r is not a number" % (label, ver))
    rows.append((int(ver) if ver.isdigit() else -1, label, short, url))

# 2. every enclosure must resolve to its own release tag
for _, label, short, url in rows:
    want = "%s/releases/download/v%s/Pulse-%s.dmg" % (repo_url, short, short)
    if url != want:
        bad.append("%s: enclosure url\n      is   %s\n      want %s" % (label, url or "(missing)", want))

# 3. no two items may advertise the same download. Sparkle picks by sparkle:version, so a second
# item at the same URL is at best dead weight and at worst a stale edSignature that fails to verify
# the very file the winning item points at. (The seed step drops the version being re-released for
# exactly this reason; this is the assertion that proves it worked.)
by_url = {}
for _, label, _, url in rows:
    if url:
        by_url.setdefault(url, []).append(label)
for url, labels in by_url.items():
    if len(labels) > 1:
        bad.append("duplicate enclosure url %s\n      shared by %s" % (url, ", ".join(labels)))

# 1. the item Sparkle would offer (highest sparkle:version) must be the one this run built
ver, label, short, url = max(rows, key=lambda r: r[0])
if short != version:
    bad.append("newest %s: sparkle:shortVersionString is %r, want %r" % (label, short, version))
if str(ver) != build:
    bad.append("newest %s: sparkle:version is %s, want %s" % (label, ver, build))
want = prefix + "Pulse-" + version + ".dmg"
if url != want:
    bad.append("newest %s: enclosure url\n      is   %s\n      want %s" % (label, url or "(missing)", want))

if bad:
    print("appcast assertion failed for %s:" % path, file=sys.stderr)
    for line in bad:
        print("  - " + line, file=sys.stderr)
    print("  remedy: build/out/ must hold only the DMG being released — remove stale DMGs "
          "and re-run (feed history is re-seeded from the committed appcast.xml)", file=sys.stderr)
    sys.exit(1)
PY
}

# Copy the tracked feed into $OUT as generate_appcast's starting point, minus any item that already
# claims this run's version. Re-releasing a version is a normal thing to do (the release plan itself
# re-runs `release.sh 0.1.0` on the merged main), and generate_appcast would keep the old item beside
# the new one: two items, the same enclosure URL, and the older one carrying an edSignature for a DMG
# that no longer exists there. Sparkle only ever offers the highest sparkle:version, but the phantom
# is still a signed claim about a live download, so drop it here rather than publish it.
# Self-contained like assert_appcast, so it can be exercised alone.
# Usage: seed_appcast <tracked appcast.xml> <destination> <version>
seed_appcast() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
import xml.etree.ElementTree as ET

src, dst, version = sys.argv[1:4]
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SP = "{%s}" % SPARKLE_NS
# Without this the sparkle: prefix is rewritten to ns0: — still valid XML, but generate_appcast
# would then merge into a feed that reads nothing like the one that is committed.
ET.register_namespace("sparkle", SPARKLE_NS)

tree = ET.parse(src)
dropped = 0
for channel in tree.getroot().findall("channel"):
    for item in list(channel.findall("item")):
        el = item.find(SP + "shortVersionString")
        if el is not None and (el.text or "").strip() == version:
            channel.remove(item)
            dropped += 1
# ElementTree only declares a namespace that something still uses, so stripping the *only* item
# would otherwise hand generate_appcast an <rss> with no sparkle declaration at all. Put it back by
# hand in exactly that case — doing it unconditionally would emit the attribute twice.
if not tree.getroot().findall("./channel/item"):
    tree.getroot().set("xmlns:sparkle", SPARKLE_NS)
tree.write(dst, encoding="utf-8", xml_declaration=True)
if dropped:
    print("seed: dropped %d existing item(s) for %s from the seeded feed" % (dropped, version))
PY
}

echo "==> bump version to $VERSION"
YML="$ROOT/Pulse/project.yml"
SHORT_LINE="$(grep -E '^[[:space:]]*CFBundleShortVersionString:' "$YML" || true)"
BUILD_LINE="$(grep -E '^[[:space:]]*CFBundleVersion:' "$YML" || true)"
PREV_SHORT="$(sed -E 's/^[^:]*:[[:space:]]*"?([^"[:space:]]*)"?.*$/\1/' <<<"$SHORT_LINE")"
PREV_BUILD="$(sed -E 's/^[^:]*:[[:space:]]*"?([^"[:space:]]*)"?.*$/\1/' <<<"$BUILD_LINE")"
[ -n "$PREV_SHORT" ] || { echo "release: could not read CFBundleShortVersionString from Pulse/project.yml — expected a line like 'CFBundleShortVersionString: \"0.1.0\"'" >&2; exit 1; }
[[ $PREV_BUILD =~ ^[0-9]+$ ]] || { echo "release: could not read CFBundleVersion from Pulse/project.yml — expected a line like 'CFBundleVersion: \"2\"', got '${BUILD_LINE:-<no such line>}'" >&2; exit 1; }
BUILD_NUMBER="$(( PREV_BUILD + 1 ))"

# The bump happens before the build, so any later failure would leave the tree bumped and the next
# run would bump again (0.1.0 build 3, 4, …). Undo it on every non-zero exit after this point.
BUMPED=0
restore_version() {
  local rc=$?
  if [ "$rc" -eq 0 ] || [ "$BUMPED" -eq 0 ]; then return 0; fi
  # Restore *before* saying so: when the run died because stdout closed (`… | head`), writing the
  # explanation first would SIGPIPE this handler and the tree would stay bumped. Ignore SIGPIPE
  # here for the same reason, and let every step fail soft so one failure cannot skip the rest.
  trap '' PIPE
  sed -i '' -E "s/^([[:space:]]*CFBundleShortVersionString:).*/\1 \"${PREV_SHORT}\"/" "$YML" || true
  sed -i '' -E "s/^([[:space:]]*CFBundleVersion:).*/\1 \"${PREV_BUILD}\"/" "$YML" || true
  ( cd "$ROOT/Pulse" && xcodegen generate -q >/dev/null 2>&1 ) || true
  echo "release: failed (exit $rc) after the version bump — restored Pulse/project.yml to ${PREV_SHORT} (${PREV_BUILD}) and regenerated the project" >&2 || true
  return 0
}
trap restore_version EXIT
# A death by signal skips the EXIT trap entirely and would leave the tree bumped — and the likeliest
# one is mundane: piping this script into `head` closes stdout and SIGPIPEs it mid-run. Turn those
# into ordinary exits so the restore above still runs.
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 141' PIPE

BUMPED=1
sed -i '' -E "s/^([[:space:]]*CFBundleShortVersionString:).*/\1 \"${VERSION}\"/" "$YML"
sed -i '' -E "s/^([[:space:]]*CFBundleVersion:).*/\1 \"${BUILD_NUMBER}\"/" "$YML"
( cd "$ROOT/Pulse" && xcodegen generate -q )

echo "==> release build (arm64 + x86_64, ad-hoc)"
rm -rf "$DD/Build/Products/Release"
# Filter the log for diagnostics but gate on xcodebuild's own status: a failed build can still
# leave a stale/partial bundle behind, and `| grep … || true` would happily sign that.
# (grep reads to EOF here, so there is no SIGPIPE hazard — unlike the `-q` probes below.)
set +e
( cd "$ROOT/Pulse" && xcodebuild build -project "$PROJ" -scheme Pulse -configuration Release -derivedDataPath "$DD" \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" -quiet ) 2>&1 | grep -E "error|warning:"
rc=${PIPESTATUS[0]}
set -e
[ "$rc" -eq 0 ] || { echo "release: xcodebuild failed ($rc)" >&2; exit 1; }
[ -d "$APP" ] || { echo "build failed: $APP missing" >&2; exit 1; }
# Capture-then-here-string, never `producer | grep -q`: under `set -o pipefail` grep exits the
# instant it matches, SIGPIPE-killing the still-writing producer, and pipefail then reports the
# whole pipeline as failed even though the match succeeded. (Same pitfall as check-anonymity.sh.)
ARCHS="$(lipo -archs "$APP/Contents/MacOS/Pulse")"
grep -q "x86_64 arm64\|arm64 x86_64" <<<"$ARCHS" || { echo "not universal: $ARCHS" >&2; exit 1; }

echo "==> ad-hoc sign Sparkle's nested bundles, then the app"
SPK="$APP/Contents/Frameworks/Sparkle.framework"
# Every one of these four must be re-signed. A silently skipped bundle (a moved path after a
# Sparkle upgrade) keeps Sparkle's own Developer-ID signature — which the top-level
# `TeamIdentifier=not set` assertion below would NOT catch, because it only inspects the outer
# bundle. So count what was signed and fail loudly if the layout changed.
NESTED_EXPECTED=4
NESTED_SIGNED=0
for inner in \
  "$SPK/Versions/B/XPCServices/Installer.xpc" \
  "$SPK/Versions/B/XPCServices/Downloader.xpc" \
  "$SPK/Versions/B/Autoupdate" \
  "$SPK/Versions/B/Updater.app"; do
  if [ -e "$inner" ]; then
    codesign --force --sign - --timestamp=none "$inner"
    NESTED_SIGNED=$(( NESTED_SIGNED + 1 ))
  else
    echo "release: nested Sparkle bundle not found: ${inner#"$ROOT/"}" >&2
  fi
done
[ "$NESTED_SIGNED" -eq "$NESTED_EXPECTED" ] || {
  echo "release: signed $NESTED_SIGNED of $NESTED_EXPECTED nested Sparkle bundles — Sparkle's layout changed; an unsigned one would ship with its vendor Developer-ID signature. Update the paths above and re-run." >&2
  exit 1; }
codesign --force --sign - --timestamp=none "$SPK"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"
SIG="$(codesign -dv "$APP" 2>&1)"
grep -q "Signature=adhoc" <<<"$SIG" || { echo "not ad-hoc:" >&2; echo "$SIG" >&2; exit 1; }
grep -q "TeamIdentifier=not set" <<<"$SIG" || { echo "TeamIdentifier leaked:" >&2; echo "$SIG" >&2; exit 1; }

echo "==> DMG"
mkdir -p "$OUT"
DMG="$OUT/Pulse-${VERSION}.dmg"
"$ROOT/build/make-dmg.sh" "$APP" "$DMG"

echo "==> anonymity gate"
"$ROOT/build/check-anonymity.sh" "$APP" "$DMG" "$APP/Contents/Info.plist"

echo "==> release note + signed appcast"
# The note is embedded in HTML, so it must be escaped (& first, or it would double-escape).
NOTE_HTML="$(sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<<"$NOTE")"
cat > "$OUT/Pulse-${VERSION}.html" <<HTML
<style>.n{font:13px/1.55 -apple-system,system-ui,sans-serif;padding:2px 2px 6px}.n h2{font-size:17px;margin:0 0 10px}.n p{margin:0 0 8px;opacity:.85}</style>
<div class="n"><h2>Pulse ${VERSION}</h2><p>${NOTE_HTML}</p></div>
HTML
# generate_appcast merges into whatever appcast.xml it finds in $OUT, and it *rewrites* an older
# item's enclosure URL to this run's --download-url-prefix whenever that item's DMG is still on disk
# — and the wrong URL then stays frozen in build/out/appcast.xml even after the stale DMG is
# deleted. Seed the feed from the committed appcast.xml every run instead: the published history
# becomes a function of the tracked file, so deleting the stale DMG really is the whole remedy, and
# a release cut from a fresh clone still keeps every prior item.
# Written as an `if`, not `[ -f … ] && seed_appcast …`: a bare AND-list whose test fails leaves the
# line's exit status non-zero, which is exactly the shape that trips `set -e` in the wrong reading.
if [ -f "$ROOT/appcast.xml" ]; then seed_appcast "$ROOT/appcast.xml" "$OUT/appcast.xml" "$VERSION"; fi
# --maximum-deltas 0: a 2.4 MB app gains nothing from binary deltas, and an advertised .delta that
# nobody uploads to the release would 404 for every updater that tried it.
# TZ=UTC: generate_appcast stamps each item's <pubDate> in the local zone, which would otherwise
# publish the maintainer's offset in every feed.
TZ=UTC "$SPARKLE_BIN/generate_appcast" --embed-release-notes --maximum-deltas 0 --ed-key-file "$KEY" --download-url-prefix "$DL_PREFIX" "$OUT"
"$ROOT/build/check-anonymity.sh" "$OUT/appcast.xml"
assert_appcast "$OUT/appcast.xml" "$VERSION" "$BUILD_NUMBER" "$DL_PREFIX" "https://github.com/${PULSE_REPO}"
cp -f "$OUT/appcast.xml" "$ROOT/appcast.xml"

cat <<EOS

Release $VERSION is staged. Nothing has been uploaded.
Next steps (nothing below is done by this script):
  1. Commit the version bump and push main:
       git add Pulse/project.yml Pulse/Pulse.xcodeproj Pulse/Pulse/Info.plist
       git commit -m "chore(release): $VERSION" && git push
  2. Create the GitHub release v$VERSION on that commit and upload $DMG:
       (web UI, or: gh release create v$VERSION $DMG --title "Pulse $VERSION" --notes "$NOTE")
  3. Only after the download exists, publish the feed:
       git add appcast.xml && git commit -m "chore(release): appcast $VERSION" && git push
  The feed flips only in step 3, so no installed copy ever sees an enclosure that does not exist yet.
EOS
