#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/inline-layout-calculation-tests/${FY_OPT#-}"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc")
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineLayoutCalculationTests.m" "${FY_LAYOUT_CALCULATION_SOURCES[@]}" "${FY_INLINE_GROUPING_SOURCES[@]}" -framework Foundation -framework CoreGraphics -o "$OUT/InlineLayoutCalculationTests"
"$OUT/InlineLayoutCalculationTests"
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineLayoutReceiverTests.m" "$ROOT_DIR/objc/FYInlineLayout.m" "${FY_LAYOUT_CALCULATION_SOURCES[@]}" "${FY_INLINE_GROUPING_SOURCES[@]}" "${FY_LAYOUT_MEASUREMENT_SOURCES[@]}" -framework Foundation -framework CoreGraphics -framework AppKit -framework CoreText -o "$OUT/InlineLayoutReceiverTests"
"$OUT/InlineLayoutReceiverTests"
