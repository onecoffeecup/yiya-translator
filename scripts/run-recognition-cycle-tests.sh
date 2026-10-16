#!/usr/bin/env bash
# Production cycle gates and scheduler, without AppKit, devices or application state.
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/recognition-cycle-tests"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wextra \
  -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc/runtime" \
  "$ROOT_DIR/tests/RecognitionCycleTests.m" "${FY_RECOGNITION_CYCLE_SOURCES[@]}" \
  -framework Foundation -o "$OUT/RecognitionCycleTests"
"$OUT/RecognitionCycleTests"
