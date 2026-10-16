#!/usr/bin/env bash
# Same production OCR pass selection/context, with Foundation/CoreGraphics only.
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/ocr-refinement-boundary-tests"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wextra \
  -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc/ocr" \
  "$ROOT_DIR/tests/OCRRefinementBoundaryTests.m" "${FY_OCR_PURE_SOURCES[@]}" \
  -framework Foundation -framework CoreGraphics -o "$OUT/OCRRefinementBoundaryTests"
"$OUT/OCRRefinementBoundaryTests"
