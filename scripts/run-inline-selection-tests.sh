#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/inline-selection-tests/${FY_OPT#-}"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc")
PURE=("${FY_INLINE_SELECTION_SOURCES[@]}" "${FY_PRESENTATION_TEXT_SOURCES[@]}" "$ROOT_DIR/objc/ocr/FYOCRTextModels.m" "${FY_INLINE_GROUPING_SOURCES[@]}")
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineSelectionTests.m" "${PURE[@]}" -framework Foundation -framework CoreGraphics -o "$OUT/InlineSelectionTests"
"$OUT/InlineSelectionTests"
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineCardActionBinderTests.m" "${FY_INLINE_CARD_ACTION_SOURCES[@]}" "${PURE[@]}" "${FY_INLINE_RENDERING_SOURCES[@]}" "${FY_LAYOUT_MEASUREMENT_SOURCES[@]}" -framework Foundation -framework CoreGraphics -framework AppKit -framework CoreText -o "$OUT/InlineCardActionBinderTests"
"$OUT/InlineCardActionBinderTests"
clang "${COMMON[@]}" -Wno-nullability-completeness -Wno-unused-function -include "$ROOT_DIR/tests/FYTestIsolation.h" -I "$ROOT_DIR/objc/learning" "$ROOT_DIR/tests/InlineSelectionHostTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" "$ROOT_DIR/tests/FYTestCaptureCardInput.m" "${FY_APP_LINK_SOURCES[@]}" -framework Cocoa -framework Security -framework UniformTypeIdentifiers -framework CoreGraphics -framework QuartzCore -framework Vision -framework Carbon -framework NaturalLanguage -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo -lsqlite3 -o "$OUT/InlineSelectionHostTests"
"$OUT/InlineSelectionHostTests"
