#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/capture-session-boundary-tests/${FY_OPT#-}"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc")
NATIVE=(-framework Foundation -framework CoreGraphics -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo)
if [[ "${1:-}" == "--known-gap" ]]; then
  clang "${COMMON[@]}" "$ROOT_DIR/tests/CaptureStartOrderKnownGapProbe.m" "${FY_CAPTURE_SOURCES[@]}" "${NATIVE[@]}" -o "$OUT/CaptureStartOrderKnownGapProbe"
  # This checks the desired Running outcome; exit 2 reproduces the existing
  # queued teardown / pending-device gap. Never convert that result into pass.
  exec "$OUT/CaptureStartOrderKnownGapProbe"
fi
clang "${COMMON[@]}" "$ROOT_DIR/tests/CaptureFrameBoundaryTests.m" "${FY_CAPTURE_PURE_SOURCES[@]}" \
  -framework Foundation -framework CoreGraphics -o "$OUT/CaptureFrameBoundaryTests"
"$OUT/CaptureFrameBoundaryTests"
clang "${COMMON[@]}" "$ROOT_DIR/tests/CaptureSessionBoundaryTests.m" "${FY_CAPTURE_PURE_SOURCES[@]}" "${FY_CAPTURE_SESSION_SOURCES[@]}" \
  "${NATIVE[@]}" -o "$OUT/CaptureSessionBoundaryTests"
"$OUT/CaptureSessionBoundaryTests"
