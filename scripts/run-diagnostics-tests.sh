#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT_DIR/.build/diagnostics-tests"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wextra \
  -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc" \
  "$ROOT_DIR/tests/RuntimeDiagnosticsTests.m" "$ROOT_DIR/objc/FYRuntimeDiagnostics.m" \
  -framework Foundation -o "$OUT/RuntimeDiagnosticsTests"
"$OUT/RuntimeDiagnosticsTests"
