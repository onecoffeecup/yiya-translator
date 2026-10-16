#!/usr/bin/env bash
# Headless production-pipeline regressions: no capture, network, preferences or user DB.
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
cd "$ROOT_DIR"
OUT="$ROOT_DIR/.build/dialogue-grammar-tests"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wno-nullability-completeness
  -Wno-unused-function -Wno-nonnull -fmodules-cache-path="$OUT/module-cache"
  -include "$ROOT_DIR/tests/FYTestIsolation.h" -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning")
clang "${COMMON[@]}" tests/GrammarCoverageTests.m tests/FYTestIsolation.m \
  "${FY_LEARNING_ANALYZER_SOURCES[@]}" objc/learning/FYLearningModels.m objc/learning/FYGrammarCatalog.m \
  "${FY_LEARNING_STORAGE_SOURCES[@]}" "${FY_TRANSLATION_CORE_SOURCES[@]}" \
  -framework Foundation -framework CoreGraphics -framework NaturalLanguage -lsqlite3 -o "$OUT/GrammarCoverageTests"
"$OUT/GrammarCoverageTests"
clang "${COMMON[@]}" tests/DialogueDriftDiagnosticTests.m tests/FYTestIsolation.m tests/FYTestCaptureCardInput.m \
  "${FY_APP_LINK_SOURCES[@]}" \
  -framework Cocoa -framework Security -framework UniformTypeIdentifiers -framework CoreGraphics -framework QuartzCore \
  -framework Vision -framework Carbon -framework NaturalLanguage -framework AVFoundation -framework CoreImage \
  -framework CoreMedia -framework CoreVideo -lsqlite3 -o "$OUT/DialogueDriftDiagnosticTests"
"$OUT/DialogueDriftDiagnosticTests"
