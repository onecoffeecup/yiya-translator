#!/usr/bin/env bash
# Minimal production preview dependencies: no AppKit host, hardware or HTTP.
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/live-preview-tests"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wextra \
  -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc/runtime" \
  "$ROOT_DIR/tests/LivePreviewSchedulerTests.m" "${FY_PREVIEW_SOURCES[@]}" \
  -framework Foundation -framework CoreGraphics -o "$OUT/LivePreviewSchedulerTests"
"$OUT/LivePreviewSchedulerTests"
