#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
cd "$ROOT_DIR"
OUT="$ROOT_DIR/.build/learning-workflow-tests"
mkdir -p "$OUT"
clang "$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall \
  -fmodules-cache-path="$OUT/module-cache" -include "$ROOT_DIR/tests/FYTestIsolation.h" \
  -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning" \
  "$ROOT_DIR/tests/LearningWorkflowBoundaryTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" \
  "${FY_LEARNING_CORE_SOURCES[@]}" "${FY_TRANSLATION_CORE_SOURCES[@]}" \
  -framework Foundation -framework CoreGraphics -framework Carbon -framework NaturalLanguage \
  -lsqlite3 -o "$OUT/LearningWorkflowBoundaryTests"
"$OUT/LearningWorkflowBoundaryTests"
