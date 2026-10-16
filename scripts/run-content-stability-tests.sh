#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/content-stability-tests/${FY_OPT#-}"
mkdir -p "$OUT"
for suite in ContentStabilityTests InlineOCRFrameStabilizerTests; do
  clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wextra \
    -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/ocr" \
    "$ROOT_DIR/tests/$suite.m" "$ROOT_DIR/objc/ocr/FYOCRTextModels.m" "${FY_CONTENT_STABILITY_SOURCES[@]}" \
    -framework Foundation -framework CoreGraphics -o "$OUT/$suite"
  "$OUT/$suite"
done
