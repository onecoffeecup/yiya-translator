#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib-test.sh"
fy_test_ui_gate

BIN="$ROOT_DIR/.build/release/InlineTranslationTests"
mkdir -p "$ROOT_DIR/.build/release"

clang \
  -fobjc-arc \
  -fmodules \
  -fmodules-cache-path="$FY_TEST_MODULE_CACHE" \
  -mmacosx-version-min=13.0 \
  -Wall \
  -include "$ROOT_DIR/tests/FYTestIsolation.h" -DFY_TEST_REQUIRES_UI=1 \
  -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning" \
  "$ROOT_DIR/tests/InlineTranslationTests.m" \
  "$ROOT_DIR/tests/FYTestIsolation.m" \
  "$ROOT_DIR/tests/FYTestCaptureCardInput.m" \
  "${FY_APP_LINK_SOURCES[@]}" \
  -o "$BIN" \
  -framework Cocoa -framework Security -framework UniformTypeIdentifiers \
  -framework CoreGraphics \
  -framework QuartzCore \
  -framework Vision \
  -framework Carbon -framework NaturalLanguage \
  -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo \
  -lsqlite3

fy_test_run "$BIN"
