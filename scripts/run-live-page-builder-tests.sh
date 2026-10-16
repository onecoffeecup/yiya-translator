#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/live-page-builder-tests/${FY_OPT#-}"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wno-nullability-completeness -Wno-unused-function -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning")
clang "${COMMON[@]}" "$ROOT_DIR/tests/LivePageBuilderTests.m" "${FY_LIVE_PAGE_BUILDER_SOURCES[@]}" "$ROOT_DIR/objc/learning/FYLearningViews.m" -framework AppKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework CoreText -o "$OUT/LivePageBuilderTests"
"$OUT/LivePageBuilderTests"
clang "${COMMON[@]}" -DFY_LIVE_PAGE_EXTRACTED=1 -include "$ROOT_DIR/tests/FYTestIsolation.h" "$ROOT_DIR/tests/LivePageBuilderHostTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" "$ROOT_DIR/tests/FYTestCaptureCardInput.m" "${FY_APP_LINK_SOURCES[@]}" -framework Cocoa -framework Security -framework UniformTypeIdentifiers -framework CoreGraphics -framework QuartzCore -framework Vision -framework Carbon -framework NaturalLanguage -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo -lsqlite3 -o "$OUT/LivePageBuilderHostTests"
"$OUT/LivePageBuilderHostTests"
