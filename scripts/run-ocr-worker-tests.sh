#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/ocr-worker-tests"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wextra \
  -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc/ocr" \
  "$ROOT_DIR/tests/OCRWorkerTests.m" "${FY_OCR_PURE_SOURCES[@]}" "${FY_OCR_WORKER_SOURCES[@]}" \
  -framework Foundation -framework CoreGraphics -o "$OUT/OCRWorkerTests"
"$OUT/OCRWorkerTests"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wextra \
  -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc/ocr" \
  "$ROOT_DIR/tests/OCRVisionEngineTests.m" "$ROOT_DIR/objc/ocr/FYOCRTextModels.m" "${FY_OCR_VISION_SOURCES[@]}" \
  -framework Foundation -framework CoreGraphics -framework Vision -o "$OUT/OCRVisionEngineTests"
"$OUT/OCRVisionEngineTests"
