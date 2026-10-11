#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
cd "$ROOT_DIR"
OUT="$ROOT_DIR/.build/subtitle-appearance-tests"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wno-nullability-completeness -Wno-unused-function -Wno-nonnull \
  -fmodules-cache-path="$ROOT_DIR/.build/test-module-cache" -include "$ROOT_DIR/tests/FYTestIsolation.h" -I objc -I objc/learning \
  tests/SubtitleAppearanceTests.m tests/FYTestIsolation.m tests/FYTestCaptureCardInput.m "${FY_APP_LINK_SOURCES[@]}" \
  -framework Cocoa -framework Security -framework UniformTypeIdentifiers -framework CoreGraphics -framework QuartzCore \
  -framework Vision -framework Carbon -framework NaturalLanguage -framework AVFoundation -framework CoreImage \
  -framework CoreMedia -framework CoreVideo -lsqlite3 -o "$OUT/SubtitleAppearanceTests"
"$OUT/SubtitleAppearanceTests"
