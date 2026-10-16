#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib-sources.sh"
source "$ROOT_DIR/scripts/lib-test.sh"
mkdir -p .build/release
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -fmodules-cache-path="$FY_TEST_MODULE_CACHE" \
  -I objc -I objc/learning -include tests/FYTestIsolation.h \
  tests/TestIsolationTests.m tests/FYTestIsolation.m \
  "${FY_LEARNING_STORAGE_SOURCES[@]}" objc/learning/FYLearningModels.m \
  "${FY_LEARNING_ANALYZER_SOURCES[@]}" objc/learning/FYGrammarCatalog.m \
  "${FY_TRANSLATION_CORE_SOURCES[@]}" \
  -framework Foundation -framework CoreGraphics -framework NaturalLanguage -lsqlite3 \
  -o .build/release/TestIsolationTests
fy_test_run "$ROOT_DIR/.build/release/TestIsolationTests"
