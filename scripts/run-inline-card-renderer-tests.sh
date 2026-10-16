#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/inline-card-renderer-tests/${FY_OPT#-}"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -fmodules-cache-path="$OUT/module-cache" -Wno-unused-function -I "$ROOT_DIR/objc")
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineCardRendererTests.m" "${FY_INLINE_CARD_RENDERER_SOURCES[@]}" "$ROOT_DIR/objc/ocr/FYOCRTextModels.m" "${FY_LAYOUT_CORE_SOURCES[@]}" -framework Foundation -framework CoreGraphics -framework AppKit -framework CoreText -framework QuartzCore -o "$OUT/InlineCardRendererTests"
"$OUT/InlineCardRendererTests"
clang "${COMMON[@]}" -Wno-nullability-completeness -include "$ROOT_DIR/tests/FYTestIsolation.h" -I "$ROOT_DIR/objc/learning" "$ROOT_DIR/tests/InlineCardRendererHostTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" "$ROOT_DIR/tests/FYTestCaptureCardInput.m" "${FY_APP_LINK_SOURCES[@]}" -framework Cocoa -framework Security -framework UniformTypeIdentifiers -framework CoreGraphics -framework QuartzCore -framework Vision -framework Carbon -framework NaturalLanguage -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo -lsqlite3 -o "$OUT/InlineCardRendererHostTests"
"$OUT/InlineCardRendererHostTests"
