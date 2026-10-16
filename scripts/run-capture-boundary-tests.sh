#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/capture-boundary-tests/${FY_OPT#-}"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc" \
  "$ROOT_DIR/tests/CaptureBoundaryTests.m" "${FY_DISPLAY_TARGET_CORE_SOURCES[@]}" "${FY_CAPTURE_MAPPING_SOURCES[@]}" \
  -framework Foundation -framework CoreGraphics -o "$OUT/CaptureBoundaryTests"
"$OUT/CaptureBoundaryTests"
# Reuse all original geometry behavior assertions with canonical minimal sources.
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc" \
  "$ROOT_DIR/tests/GeometryManagerTests.m" "${FY_CAPTURE_MAPPING_SOURCES[@]}" \
  "$ROOT_DIR/objc/ocr/FYOCRTextModels.m" "${FY_DELIVERY_SOURCES[@]}" \
  -framework Foundation -framework CoreGraphics -o "$OUT/GeometryManagerTests"
"$OUT/GeometryManagerTests"
