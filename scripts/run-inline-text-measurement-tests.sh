#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/inline-text-measurement-tests/${FY_OPT#-}"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc")
NATIVE=(-framework Foundation -framework CoreGraphics -framework AppKit -framework CoreText)
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineTextMeasurementTests.m" "${FY_LAYOUT_MEASUREMENT_SOURCES[@]}" "${NATIVE[@]}" -o "$OUT/InlineTextMeasurementTests"
"$OUT/InlineTextMeasurementTests"
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineMeasurementLifecycleTests.m" "$ROOT_DIR/objc/FYInlineLayout.m" "${FY_LAYOUT_CALCULATION_SOURCES[@]}" "${FY_INLINE_GROUPING_SOURCES[@]}" "${FY_LAYOUT_MEASUREMENT_SOURCES[@]}" "${NATIVE[@]}" -o "$OUT/InlineMeasurementLifecycleTests"
"$OUT/InlineMeasurementLifecycleTests"
