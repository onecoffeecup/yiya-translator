#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/inline-model-boundary-tests/${FY_OPT#-}"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc" \
  "$ROOT_DIR/tests/InlineModelBoundaryTests.m" "${FY_INLINE_GROUPING_SOURCES[@]}" \
  -framework Foundation -framework CoreGraphics -o "$OUT/InlineModelBoundaryTests"
"$OUT/InlineModelBoundaryTests"
