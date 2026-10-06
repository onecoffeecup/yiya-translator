#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT_DIR/.build/translation-trace-tests"
mkdir -p "$OUT"
clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wextra \
  -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc" \
  "$ROOT_DIR/tests/TranslationTraceTests.m" "$ROOT_DIR/objc/FYTranslationTrace.m" \
  "$ROOT_DIR/objc/FYInlineLayout.m" \
  -framework Foundation -o "$OUT/TranslationTraceTests"
"$OUT/TranslationTraceTests"

# Headless integration with the real timer/cache/HTTP response code. The forced
# test isolation header replaces capture and rejects all unmocked networking.
cd "$ROOT_DIR"
clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -Wno-nullability-completeness -Wno-unused-function -Wno-nonnull \
  -fmodules-cache-path="$OUT/module-cache" -include "$ROOT_DIR/tests/FYTestIsolation.h" \
  -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning" \
  "$ROOT_DIR/tests/TranslationTracePipelineTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" \
  "$ROOT_DIR/tests/FYTestCaptureCardInput.m" \
  "$ROOT_DIR/objc/FYTranslationTrace.m" "$ROOT_DIR/objc/FYInlineLayout.m" "$ROOT_DIR/objc/FYCaptureCardInput.m" "$ROOT_DIR"/objc/learning/*.m \
  -framework Cocoa -framework CoreGraphics -framework QuartzCore -framework Vision \
  -framework Carbon -framework NaturalLanguage \
  -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo \
  -lsqlite3 -o "$OUT/TranslationTracePipelineTests"
"$OUT/TranslationTracePipelineTests"
