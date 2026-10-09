#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT_DIR/.build/learning-resilience-tests"
mkdir -p "$OUT"
clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wno-nonnull \
  -fmodules-cache-path="$OUT/module-cache" -include "$ROOT_DIR/tests/FYTestIsolation.h" \
  -I "$ROOT_DIR/objc/learning" "$ROOT_DIR/tests/LearningStoreResilienceTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" \
  "$ROOT_DIR/objc/learning/FYLearningModels.m" "$ROOT_DIR/objc/learning/FYLearningStore.m" "$ROOT_DIR/objc/learning/FYReferenceDictionary.m" \
  -framework Foundation -framework CoreGraphics -lsqlite3 -o "$OUT/LearningStoreResilienceTests"
"$OUT/LearningStoreResilienceTests" "$@"
