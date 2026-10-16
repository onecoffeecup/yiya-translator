#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/live-reading-tests/${FY_OPT#-}"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wno-nullability-completeness -Wno-unused-function -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning")
PURE=("${FY_LIVE_READING_COORDINATION_SOURCES[@]}" "$ROOT_DIR/objc/presentation/FYDisplayedSentenceState.m" "$ROOT_DIR/objc/learning/FYLearningModels.m")
clang "${COMMON[@]}" "$ROOT_DIR/tests/LiveReadingCoordinatorTests.m" "${PURE[@]}" -framework Foundation -framework CoreGraphics -o "$OUT/LiveReadingCoordinatorTests"
"$OUT/LiveReadingCoordinatorTests"
clang "${COMMON[@]}" "$ROOT_DIR/tests/LiveReadingRendererTests.m" "${PURE[@]}" "${FY_LIVE_READING_RENDERING_SOURCES[@]}" -framework Foundation -framework CoreGraphics -framework AppKit -framework CoreText -o "$OUT/LiveReadingRendererTests"
"$OUT/LiveReadingRendererTests"
clang "${COMMON[@]}" -include "$ROOT_DIR/tests/FYTestIsolation.h" "$ROOT_DIR/tests/LiveReadingHostTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" "$ROOT_DIR/tests/FYTestCaptureCardInput.m" "${FY_APP_LINK_SOURCES[@]}" -framework Cocoa -framework Security -framework UniformTypeIdentifiers -framework CoreGraphics -framework QuartzCore -framework Vision -framework Carbon -framework NaturalLanguage -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo -lsqlite3 -o "$OUT/LiveReadingHostTests"
"$OUT/LiveReadingHostTests"
