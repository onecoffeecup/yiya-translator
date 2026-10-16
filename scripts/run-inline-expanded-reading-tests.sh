#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/inline-expanded-reading-tests/${FY_OPT#-}"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc")
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineExpandedReadingTests.m" "${FY_INLINE_EXPANDED_READING_SOURCES[@]}" "$ROOT_DIR/objc/ocr/FYOCRTextModels.m" "${FY_LAYOUT_SOURCES[@]}" -framework Foundation -framework CoreGraphics -framework AppKit -framework CoreText -framework QuartzCore -o "$OUT/InlineExpandedReadingTests"
"$OUT/InlineExpandedReadingTests"
clang "${COMMON[@]}" -Wno-nullability-completeness -Wno-unused-function -include "$ROOT_DIR/tests/FYTestIsolation.h" -I "$ROOT_DIR/objc/learning" "$ROOT_DIR/tests/InlineExpandedReadingHostTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" "$ROOT_DIR/tests/FYTestCaptureCardInput.m" "${FY_APP_LINK_SOURCES[@]}" -framework Cocoa -framework Security -framework UniformTypeIdentifiers -framework CoreGraphics -framework QuartzCore -framework Vision -framework Carbon -framework NaturalLanguage -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo -lsqlite3 -o "$OUT/InlineExpandedReadingHostTests"
"$OUT/InlineExpandedReadingHostTests"
