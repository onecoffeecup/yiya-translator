#!/usr/bin/env bash
# Headless production-host ownership checks; capture and networking are isolated.
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
cd "$ROOT_DIR"
OUT="$ROOT_DIR/.build/runtime-ownership-tests"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -Wno-nullability-completeness -Wno-unused-function \
  -fmodules-cache-path="$OUT/module-cache" -include "$ROOT_DIR/tests/FYTestIsolation.h" \
  -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning" \
  "$ROOT_DIR/tests/RuntimeOwnershipTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" \
  "$ROOT_DIR/tests/FYTestCaptureCardInput.m" "${FY_APP_LINK_SOURCES[@]}" \
  -framework Cocoa -framework Security -framework UniformTypeIdentifiers \
  -framework CoreGraphics -framework QuartzCore -framework Vision -framework Carbon -framework NaturalLanguage \
  -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo \
  -lsqlite3 -o "$OUT/RuntimeOwnershipTests"
"$OUT/RuntimeOwnershipTests"
