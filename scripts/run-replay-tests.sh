#!/usr/bin/env bash
# Headless, isolated production pipeline. No FY_TEST_ALLOW_UI required.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
cd "$ROOT_DIR"
OUT="$ROOT_DIR/.build/replay"
mkdir -p "$OUT"
clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -Wno-nullability-completeness -Wno-unused-function -Wno-nonnull \
  -fmodules-cache-path="$OUT/module-cache" -include "$ROOT_DIR/tests/FYTestIsolation.h" \
  -I objc -I objc/learning \
  tests/ReplayTests.m tests/FYTestIsolation.m tests/FYTestCaptureCardInput.m \
  "${FY_APP_LINK_SOURCES[@]}" \
  -framework Cocoa -framework Security -framework UniformTypeIdentifiers \
  -framework CoreGraphics -framework QuartzCore -framework Vision -framework Carbon \
  -framework NaturalLanguage -framework AVFoundation -framework CoreImage \
  -framework CoreMedia -framework CoreVideo -lsqlite3 -o "$OUT/ReplayTests"
if [[ "${1:-}" == "--build-only" ]]; then exit 0; fi
if [[ $# != 2 ]]; then
  echo 'Usage: bash scripts/run-replay-tests.sh scenario.json result.json' >&2
  exit 2
fi
"$OUT/ReplayTests" "$@"
