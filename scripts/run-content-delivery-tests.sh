#!/usr/bin/env bash
# Production content and delivery policies, with Foundation-only fixture inputs.
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/content-delivery-tests"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wextra \
  -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc/runtime" \
  "$ROOT_DIR/tests/ContentDeliveryTests.m" "${FY_CONTENT_STATE_SOURCES[@]}" "${FY_DELIVERY_SOURCES[@]}" \
  -framework Foundation -o "$OUT/ContentDeliveryTests"
"$OUT/ContentDeliveryTests"
