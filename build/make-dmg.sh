#!/usr/bin/env bash
# Plain DMG: the app + an Applications symlink. No background art, no notarization.
# Usage: build/make-dmg.sh <path/to/Pulse.app> <out.dmg>
set -euo pipefail
APP="${1:?app path}"; OUT="${2:?dmg path}"
[ -d "$APP" ] || { echo "app not found: $APP" >&2; exit 1; }
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT          # never leak the staging copy of the app, even on failure
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -volname "Pulse" -srcfolder "$STAGE" -ov -format UDZO -quiet "$OUT"
echo "wrote $OUT"
