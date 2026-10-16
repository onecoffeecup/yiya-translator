#!/usr/bin/env bash
# Foundation-only production policies. Synthetic transport/observations, no host or UI.
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/translation-coordination-tests"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/runtime" \
  "$ROOT_DIR/tests/TranslationCoordinationTests.m" "${FY_TRANSLATION_CORE_SOURCES[@]}" \
  "${FY_INLINE_COORDINATION_SOURCES[@]}" "${FY_CONTENT_STATE_SOURCES[@]}" \
  "$ROOT_DIR/objc/settings/FYSettingsStore.m" \
  -framework Foundation -o "$OUT/TranslationCoordinationTests"
"$OUT/TranslationCoordinationTests"
