#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib-test.sh"
mkdir -p .build/release
clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -fmodules-cache-path="$FY_TEST_MODULE_CACHE" \
  -I objc -I objc/learning -include tests/FYTestIsolation.h \
  tests/TestIsolationTests.m tests/FYTestIsolation.m \
  objc/learning/FYLearningStore.m objc/learning/FYLearningModels.m \
  objc/learning/FYLearningAnalyzer.m objc/learning/FYGrammarCatalog.m \
  objc/FYTranslationManager.m \
  -framework Foundation -framework CoreGraphics -framework NaturalLanguage -lsqlite3 \
  -o .build/release/TestIsolationTests
fy_test_run "$ROOT_DIR/.build/release/TestIsolationTests"
