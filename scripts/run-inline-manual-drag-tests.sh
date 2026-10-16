#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/inline-manual-drag-tests/${FY_OPT#-}"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc")
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineManualPlacementTests.m" "${FY_INLINE_MANUAL_PLACEMENT_SOURCES[@]}" "${FY_PRESENTATION_TEXT_SOURCES[@]}" "$ROOT_DIR/objc/ocr/FYOCRTextModels.m" "${FY_INLINE_MODEL_SOURCES[@]}" -framework Foundation -framework CoreGraphics -o "$OUT/InlineManualPlacementTests"
"$OUT/InlineManualPlacementTests"
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineDragControllerTests.m" "${FY_INLINE_DRAG_SOURCES[@]}" "${FY_INLINE_RENDERING_SOURCES[@]}" "${FY_LAYOUT_MEASUREMENT_SOURCES[@]}" "${FY_INLINE_MODEL_SOURCES[@]}" "${FY_INLINE_TEXT_UTILITY_SOURCES[@]}" -framework Foundation -framework CoreGraphics -framework AppKit -framework CoreText -o "$OUT/InlineDragControllerTests"
"$OUT/InlineDragControllerTests"
clang "${COMMON[@]}" -Wno-nullability-completeness -Wno-unused-function -include "$ROOT_DIR/tests/FYTestIsolation.h" -I "$ROOT_DIR/objc/learning" "$ROOT_DIR/tests/InlineManualDragHostTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" "$ROOT_DIR/tests/FYTestCaptureCardInput.m" "${FY_APP_LINK_SOURCES[@]}" -framework Cocoa -framework Security -framework UniformTypeIdentifiers -framework CoreGraphics -framework QuartzCore -framework Vision -framework Carbon -framework NaturalLanguage -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo -lsqlite3 -o "$OUT/InlineManualDragHostTests"
"$OUT/InlineManualDragHostTests"
