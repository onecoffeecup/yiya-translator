#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib-test.sh"

BIN="$ROOT_DIR/.build/release/LearningTests"
mkdir -p "$ROOT_DIR/.build/release"

clang \
  -fobjc-arc \
  -fmodules \
  -fmodules-cache-path="$FY_TEST_MODULE_CACHE" \
  -mmacosx-version-min=13.0 \
  -Wall \
  -include "$ROOT_DIR/tests/FYTestIsolation.h" \
  -I "$ROOT_DIR/objc/learning" \
  "$ROOT_DIR/tests/LearningTests.m" \
  "$ROOT_DIR/tests/FYTestIsolation.m" \
  "$ROOT_DIR/objc/learning/FYLearningModels.m" \
  "$ROOT_DIR/objc/learning/FYLearningStore.m" \
  "$ROOT_DIR/objc/learning/FYLearningAnalyzer.m" \
  "$ROOT_DIR/objc/learning/FYJapaneseTokenizer.m" \
  "$ROOT_DIR/objc/learning/FYGrammarCatalog.m" \
  "$ROOT_DIR/objc/learning/FYLearningCoordinator.m" \
  -o "$BIN" \
  -framework Foundation -framework CoreGraphics \
  -framework Carbon -framework NaturalLanguage \
  -lsqlite3

fy_test_run "$BIN"
