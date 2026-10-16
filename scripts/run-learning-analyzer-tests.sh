#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/learning-analyzer-tests"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wno-nonnull \
  -fmodules-cache-path="$OUT/module-cache" -include "$ROOT_DIR/tests/FYTestIsolation.h" \
  -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning" \
  "$ROOT_DIR/tests/LearningAnalyzerBoundaryTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" \
  "$ROOT_DIR/objc/learning/FYLearningModels.m" "${FY_LEARNING_ANALYZER_SOURCES[@]}" \
  "$ROOT_DIR/objc/learning/FYGrammarCatalog.m" "${FY_LEARNING_STORAGE_SOURCES[@]}" "${FY_TRANSLATION_CORE_SOURCES[@]}" \
  -framework Foundation -framework CoreGraphics -framework NaturalLanguage -lsqlite3 -o "$OUT/LearningAnalyzerBoundaryTests"
"$OUT/LearningAnalyzerBoundaryTests"
