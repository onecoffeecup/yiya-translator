#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib-test.sh"
fy_test_ui_gate

BIN="$ROOT_DIR/.build/release/InlineTranslationTests"
mkdir -p "$ROOT_DIR/.build/release"

# 改单文件大源码时留一份可回滚快照（曾因脚本切片写坏过源码）
mkdir -p "$ROOT_DIR/.build/src-backups"
cp "$ROOT_DIR/objc/LiveCaptionTranslator.m" \
   "$ROOT_DIR/.build/src-backups/LiveCaptionTranslator.m.$(date +%Y%m%d-%H%M%S)"

clang \
  -fobjc-arc \
  -fmodules \
  -fmodules-cache-path="$FY_TEST_MODULE_CACHE" \
  -mmacosx-version-min=13.0 \
  -Wall \
  -include "$ROOT_DIR/tests/FYTestIsolation.h" -DFY_TEST_REQUIRES_UI=1 \
  -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning" \
  "$ROOT_DIR/tests/InlineTranslationTests.m" \
  "$ROOT_DIR/tests/FYTestIsolation.m" \
  "$ROOT_DIR/tests/FYTestCaptureCardInput.m" \
  "$ROOT_DIR/objc/FYTranslationTrace.m" "$ROOT_DIR/objc/FYRuntimeDiagnostics.m" \
  "$ROOT_DIR/objc/FYInlineLayout.m" "$ROOT_DIR/objc/FYWindowManager.m" "$ROOT_DIR/objc/FYOCRManager.m" "$ROOT_DIR/objc/FYGeometryManager.m" "$ROOT_DIR/objc/FYTranslationManager.m" \
  "$ROOT_DIR/objc/FYCaptureCardInput.m" \
  "$ROOT_DIR/objc/learning/FYLearningModels.m" \
  "$ROOT_DIR/objc/learning/FYLearningStore.m" \
  "$ROOT_DIR/objc/learning/FYLearningAnalyzer.m" \
  "$ROOT_DIR/objc/learning/FYJapaneseTokenizer.m" \
  "$ROOT_DIR/objc/learning/FYGrammarCatalog.m" \
  "$ROOT_DIR/objc/learning/FYLearningCoordinator.m" \
  "$ROOT_DIR/objc/learning/FYLearningViews.m" \
  "$ROOT_DIR/objc/learning/FYStudyChatView.m" \
  "$ROOT_DIR/objc/learning/FYStudyChatSession.m" \
  "$ROOT_DIR/objc/learning/FYGlobalShortcuts.m" \
  "$ROOT_DIR/objc/learning/FYStudyOverlayPanel.m" \
  "$ROOT_DIR/objc/learning/FYReferenceDictionary.m" \
  "$ROOT_DIR/objc/learning/FYSavedWordReferenceView.m" \
  -o "$BIN" \
  -framework Cocoa -framework UniformTypeIdentifiers \
  -framework CoreGraphics \
  -framework QuartzCore \
  -framework Vision \
  -framework Carbon -framework NaturalLanguage \
  -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo \
  -lsqlite3

fy_test_run "$BIN"
