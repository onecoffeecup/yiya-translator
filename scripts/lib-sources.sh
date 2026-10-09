#!/usr/bin/env bash
# Shared production sources. Callers set ROOT_DIR and retain their own test
# entry points, isolation flags and framework choices.
FY_LAYOUT_SOURCES=(
  "$ROOT_DIR/objc/FYInlineLayout.m"
  "$ROOT_DIR/objc/FYInlineLayoutDebug.m"
)
FY_OCR_SOURCES=("$ROOT_DIR/objc/FYOCRManager.m" "${FY_LAYOUT_SOURCES[@]}")
FY_RUNTIME_BASE_SOURCES=(
  "$ROOT_DIR/objc/FYTranslationTrace.m" "$ROOT_DIR/objc/FYRuntimeDiagnostics.m"
  "${FY_LAYOUT_SOURCES[@]}"
  "$ROOT_DIR/objc/FYWindowManager.m" "$ROOT_DIR/objc/FYOCRManager.m"
  "$ROOT_DIR/objc/FYGeometryManager.m" "$ROOT_DIR/objc/FYTranslationManager.m"
)
FY_RUNTIME_SOURCES=("${FY_RUNTIME_BASE_SOURCES[@]}" "$ROOT_DIR/objc/FYCaptureCardInput.m")
FY_LEARNING_CORE_SOURCES=(
  "$ROOT_DIR/objc/learning/FYLearningModels.m"
  "$ROOT_DIR/objc/learning/FYLearningStore.m"
  "$ROOT_DIR/objc/learning/FYLearningAnalyzer.m"
  "$ROOT_DIR/objc/learning/FYJapaneseTokenizer.m"
  "$ROOT_DIR/objc/learning/FYGrammarCatalog.m"
  "$ROOT_DIR/objc/learning/FYLearningCoordinator.m"
)
FY_LEARNING_UI_SOURCES=(
  "$ROOT_DIR/objc/learning/FYLearningViews.m"
  "$ROOT_DIR/objc/learning/FYStudyChatView.m"
  "$ROOT_DIR/objc/learning/FYStudyChatSession.m"
  "$ROOT_DIR/objc/learning/FYGlobalShortcuts.m"
  "$ROOT_DIR/objc/learning/FYStudyOverlayPanel.m"
  "$ROOT_DIR/objc/learning/FYReferenceDictionary.m"
  "$ROOT_DIR/objc/learning/FYSavedWordReferenceView.m"
)
FY_APP_LINK_SOURCES=("${FY_RUNTIME_SOURCES[@]}" "${FY_LEARNING_CORE_SOURCES[@]}" "${FY_LEARNING_UI_SOURCES[@]}")
FY_APP_SOURCES=("$ROOT_DIR/objc/LiveCaptionTranslator.m" "$ROOT_DIR/objc/FYAppUpdater.m" "${FY_APP_LINK_SOURCES[@]}")
