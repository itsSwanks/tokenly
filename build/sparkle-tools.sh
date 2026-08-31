#!/usr/bin/env bash
# Locates Sparkle's CLI tools from the SPM artifacts the app build resolved.
# Source this: `. build/sparkle-tools.sh` → $SPARKLE_BIN
# This file is *sourced*, so every variable it sets lands in the caller's scope: use a
# namespaced name for the repo root, never a bare `ROOT` that would clobber the sourcer's.
SPARKLE_TOOLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [ -z "${SPARKLE_BIN:-}" ]; then
  # `-print -quit` rather than `… | head -1 | xargs`: the callers run under `set -o pipefail`, where
  # head exiting on the first line can SIGPIPE the still-searching find and fail the whole pipeline
  # even though the match succeeded. `|| true` because find still exits non-zero when one of the two
  # search roots does not exist (a fresh clone has no DerivedData yet) — the emptiness check below
  # is what decides whether the search actually worked.
  SPARKLE_TOOLS_FOUND="$(find "$SPARKLE_TOOLS_ROOT/Pulse/build/dd/SourcePackages/artifacts" "$HOME/Library/Developer/Xcode/DerivedData" \
    -type f -name generate_appcast -path '*artifacts/sparkle/Sparkle/bin/*' -print -quit 2>/dev/null || true)"
  if [ -n "$SPARKLE_TOOLS_FOUND" ]; then SPARKLE_BIN="$(dirname "$SPARKLE_TOOLS_FOUND")"; fi
  unset SPARKLE_TOOLS_FOUND
fi
if [ -z "${SPARKLE_BIN:-}" ] || [ ! -x "$SPARKLE_BIN/sign_update" ]; then
  echo "Sparkle tools not found — build the app once so SPM resolves Sparkle, or set SPARKLE_BIN" >&2
  return 1 2>/dev/null || exit 1
fi
export SPARKLE_BIN
