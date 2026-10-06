#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib-test.sh"
fy_test_ui_gate
python3 scripts/reference-data.py check
python3 tests/DistributionTests.py
scripts/run-tests.sh
scripts/run-learning-tests.sh
for suite in EllipsisDialogueTests InlineAdaptiveLayoutTests InlineAdaptiveAcceptanceTests LearningAppTests CaptureCardInputTests HistoryDedupTests DialogueStabilityTests DialogueCompletenessTests HistoryRetentionTests ReferenceDictionaryTests CollectionLayoutTests WorkspaceFollowupTests WorkspaceStressTests PreviewLayoutTests CaptionVisibilityTests SettingsInteractionTests QuickSentenceAnalysisTests ImmersiveLearningTests LatestStudyReferenceTests DragSelectionTests SourceHoverTests PrototypeAuditTests NativeUIAcceptance PixelAdventureUITests ChatPresentationTests ChatClipboardTests; do
  echo "==> $suite"
  scripts/run-learning-app-tests.sh "$suite"
done
if [ "${FY_TEST_COMPILE_ONLY:-0}" = 1 ]; then
  echo "编译检查完成；原生测试未运行，不能视为回归通过。"
else
  echo "全部本机回归通过。实际下载与另一台 Mac 的首次安装另见 docs/首次安装验收.md。"
fi
