#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT_DIR/.build/module-tests"
SANITIZER_FLAGS=()
if [[ "${FY_TEST_ASAN:-0}" == "1" ]]; then
  OUT="$ROOT_DIR/.build/module-tests-asan"
  SANITIZER_FLAGS=(-fsanitize=address -fno-omit-frame-pointer -g)
elif [[ "${FY_TEST_UBSAN:-0}" == "1" ]]; then
  OUT="$ROOT_DIR/.build/module-tests-ubsan"
  SANITIZER_FLAGS=(-fsanitize=undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer -g)
fi
mkdir -p "$OUT"
clang ${SANITIZER_FLAGS[@]+"${SANITIZER_FLAGS[@]}"} -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -fmodules-cache-path="$OUT/modulecache" -I "$ROOT_DIR/objc" \
  "$ROOT_DIR/tests/GeometryManagerTests.m" "$ROOT_DIR/objc/FYGeometryManager.m" "$ROOT_DIR/objc/FYOCRManager.m" \
  -framework Cocoa -framework Vision -o "$OUT/GeometryManagerTests"
"$OUT/GeometryManagerTests"
clang ${SANITIZER_FLAGS[@]+"${SANITIZER_FLAGS[@]}"} -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -fmodules-cache-path="$OUT/modulecache" -I "$ROOT_DIR/objc" \
  "$ROOT_DIR/tests/OCRPostprocessingTests.m" "$ROOT_DIR/objc/FYOCRManager.m" \
  -framework Cocoa -framework Vision -o "$OUT/OCRPostprocessingTests"
"$OUT/OCRPostprocessingTests"
clang ${SANITIZER_FLAGS[@]+"${SANITIZER_FLAGS[@]}"} -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -fmodules-cache-path="$OUT/modulecache" -I "$ROOT_DIR/objc" \
  "$ROOT_DIR/tests/TranslationManagerTests.m" "$ROOT_DIR/objc/FYTranslationManager.m" \
  -framework Foundation -o "$OUT/TranslationManagerTests"
"$OUT/TranslationManagerTests"
clang ${SANITIZER_FLAGS[@]+"${SANITIZER_FLAGS[@]}"} -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -fmodules-cache-path="$OUT/modulecache" -I "$ROOT_DIR/objc" \
  "$ROOT_DIR/tests/InlineTextPolicyTests.m" "$ROOT_DIR/objc/FYInlineLayout.m" \
  -framework Cocoa -o "$OUT/InlineTextPolicyTests"
"$OUT/InlineTextPolicyTests"
clang ${SANITIZER_FLAGS[@]+"${SANITIZER_FLAGS[@]}"} -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -fmodules-cache-path="$OUT/modulecache" -I "$ROOT_DIR/objc" \
  "$ROOT_DIR/tests/TranslationTaskTests.m" "$ROOT_DIR/objc/FYTranslationManager.m" \
  -framework Foundation -o "$OUT/TranslationTaskTests"
"$OUT/TranslationTaskTests"
clang ${SANITIZER_FLAGS[@]+"${SANITIZER_FLAGS[@]}"} -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -fmodules-cache-path="$OUT/modulecache" -I "$ROOT_DIR/objc" \
  "$ROOT_DIR/tests/WindowPolicyTests.m" "$ROOT_DIR/objc/FYWindowManager.m" \
  -framework Cocoa -o "$OUT/WindowPolicyTests"
"$OUT/WindowPolicyTests"
