#!/usr/bin/env bash
# Pure state/lifecycle checks. No windows, real preferences, credentials or API.
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/host-extraction-tests"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wno-unused-function \
  -fmodules-cache-path="$OUT/module-cache" -include "$ROOT_DIR/tests/FYTestIsolation.h" \
  -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning" \
  "$ROOT_DIR/tests/HostExtractionTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" \
  "${FY_SETTINGS_SOURCES[@]}" "${FY_DIAGNOSTICS_UI_SOURCES[@]}" \
  "${FY_WINDOW_SOURCES[@]}" "$ROOT_DIR/objc/FYRuntimeDiagnostics.m" \
  "${FY_TRANSLATION_CORE_SOURCES[@]}" \
  "${FY_LEARNING_STORAGE_SOURCES[@]}" "$ROOT_DIR/objc/learning/FYLearningModels.m" \
  -framework Cocoa -framework UniformTypeIdentifiers -lsqlite3 -o "$OUT/HostExtractionTests"
"$OUT/HostExtractionTests"
