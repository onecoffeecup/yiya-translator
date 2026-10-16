#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/inline-renderer-boundary-tests/${FY_OPT#-}"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc")
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineRenderingGeometryTests.m" "${FY_INLINE_RENDERING_GEOMETRY_SOURCES[@]}" -framework Foundation -framework CoreGraphics -o "$OUT/InlineRenderingGeometryTests"
"$OUT/InlineRenderingGeometryTests"
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineCardPressStateTests.m" "${FY_INLINE_PRESS_STATE_SOURCES[@]}" -framework Foundation -framework CoreGraphics -o "$OUT/InlineCardPressStateTests"
"$OUT/InlineCardPressStateTests"
NATIVE_SOURCES=("${FY_INLINE_RENDERING_SOURCES[@]}" "${FY_LAYOUT_MEASUREMENT_SOURCES[@]}" "${FY_INLINE_TEXT_UTILITY_SOURCES[@]}")
NATIVE=(-framework Foundation -framework CoreGraphics -framework AppKit -framework CoreText)
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineRendererBoundaryTests.m" "${NATIVE_SOURCES[@]}" "${NATIVE[@]}" -o "$OUT/InlineRendererBoundaryTests"
"$OUT/InlineRendererBoundaryTests"
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineCardPressUITests.m" "${NATIVE_SOURCES[@]}" "${NATIVE[@]}" -o "$OUT/InlineCardPressUITests"
printf 'COMPILED_ONLY: %s\n' "$OUT/InlineCardPressUITests"
