#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/capture-mapping-coordinator-tests/${FY_OPT#-}"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc" \
  "$ROOT_DIR/tests/CaptureMappingCoordinatorTests.m" "${FY_CAPTURE_MAPPING_SOURCES[@]}" "${FY_CAPTURE_MAPPING_COORDINATION_SOURCES[@]}" \
  -framework Foundation -framework CoreGraphics -o "$OUT/CaptureMappingCoordinatorTests"
"$OUT/CaptureMappingCoordinatorTests"
