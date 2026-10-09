#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib-test.sh"
bash scripts/run-headless-checks.sh
if [ "${FY_TEST_ALLOW_UI:-0}" != 1 ] && [ "${FY_TEST_COMPILE_ONLY:-0}" != 1 ]; then
  echo "无界面基线检查完成；桌面测试未运行。安排桌面时段后使用 FY_TEST_ALLOW_UI=1，或用 FY_TEST_COMPILE_ONLY=1 只编译 UI 套件。"
  exit 0
fi
fy_test_ui_gate
python3 scripts/reference-data.py check
python3 scripts/run-update-tests.py
scripts/run-tests.sh
for suite in BatchAppearanceTests ModalOverlayRegressionTests DiagnosticsInteractionTests CaptureMappingTests EllipsisDialogueTests InlineAdaptiveLayoutTests InlineLayoutDebugUITests InlineAdaptiveAcceptanceTests InlineLongBodyEntryTests InlineFieldRetentionTests LocalAPIKeyStoreTests LocalCredentialSettingsTests DialogueDriftDiagnosticTests InlineFoldReadTests FoldAcceptanceTests ReviewFixesTests InlineReviewProbe IndependentInlineProbe DisplayTargetFollowTests WindowPickerTests LearningAppTests LearningPageNavigationTests CaptureCardInputTests HistoryDedupTests DialogueStabilityTests DialogueCompletenessTests InlineTranslationPipelineTests HistoryRetentionTests ReferenceDictionaryTests CollectionLayoutTests WorkspaceFollowupTests WorkspaceStressTests PreviewLayoutTests CaptionVisibilityTests CaptionSelectionTests SettingsInteractionTests QuickSentenceAnalysisTests GrammarActionsAppTests ImmersiveLearningTests LatestStudyReferenceTests DragSelectionTests SourceHoverTests PrototypeAuditTests NativeUIAcceptance PixelAdventureUITests ChatPresentationTests ChatClipboardTests; do
  echo "==> $suite"
  scripts/run-learning-app-tests.sh "$suite"
done
if [ "${FY_TEST_COMPILE_ONLY:-0}" = 1 ]; then
  echo "编译检查完成；原生测试未运行，不能视为回归通过。"
else
  echo "既有本机回归执行通过；Debug 报告单列尚未修复的产品缺口。实际下载与另一台 Mac 的首次安装另见 docs/首次安装验收.md。"
fi
