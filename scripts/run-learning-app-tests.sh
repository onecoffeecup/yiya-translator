#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib-test.sh"
fy_test_ui_gate
TEST_SOURCE="${1:-LearningAppTests}"
if [[ ! "$TEST_SOURCE" =~ ^[A-Za-z][A-Za-z0-9]*$ ]]; then
  echo "Invalid test suite name" >&2; exit 2
fi
TEST_OUTPUT="${2:-$ROOT_DIR/.build/test-results/$TEST_SOURCE}"
mkdir -p "$ROOT_DIR/.build/release" "$TEST_OUTPUT"
clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wno-nullability-completeness -Wno-unused-function \
  -fmodules-cache-path="$FY_TEST_MODULE_CACHE" \
  -DFY_TEST_REQUIRES_UI=1 -include "$ROOT_DIR/tests/FYTestIsolation.h" \
  -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning" \
  "$ROOT_DIR/tests/$TEST_SOURCE.m" "$ROOT_DIR/tests/FYTestIsolation.m" \
  "$ROOT_DIR/tests/FYTestCaptureCardInput.m" \
  "${FY_APP_LINK_SOURCES[@]}" \
  -framework Cocoa -framework Security -framework UniformTypeIdentifiers -framework CoreGraphics -framework QuartzCore -framework Vision \
  -framework Carbon -framework NaturalLanguage \
  -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo \
  -lsqlite3 -o "$ROOT_DIR/.build/release/$TEST_SOURCE"
fy_test_run "$ROOT_DIR/.build/release/$TEST_SOURCE" "$TEST_OUTPUT"
