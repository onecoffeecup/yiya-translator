#!/usr/bin/env bash
# Shared production sources. Callers set ROOT_DIR and retain their own test
# entry points, isolation flags and framework choices.
FY_INLINE_MODEL_SOURCES=("$ROOT_DIR/objc/inline/FYInlineTextModels.m")
FY_INLINE_TEXT_UTILITY_SOURCES=("$ROOT_DIR/objc/inline/FYInlineLayoutUtilities.m")
FY_INLINE_GROUPING_SOURCES=("${FY_INLINE_MODEL_SOURCES[@]}" "${FY_INLINE_TEXT_UTILITY_SOURCES[@]}" "$ROOT_DIR/objc/inline/FYInlineGrouping.m" "$ROOT_DIR/objc/inline/FYInlineBlockMatcher.m")
FY_LAYOUT_MEASUREMENT_SOURCES=("$ROOT_DIR/objc/inline/FYInlineTextMeasurer.m")
FY_LAYOUT_CALCULATION_SOURCES=("$ROOT_DIR/objc/inline/FYInlineLayoutCalculator.m")
FY_INLINE_RENDERING_GEOMETRY_SOURCES=("$ROOT_DIR/objc/inline/FYInlineRenderingGeometry.m")
FY_INLINE_PRESS_STATE_SOURCES=("$ROOT_DIR/objc/inline/FYInlineCardPressState.m")
FY_INLINE_RENDERING_SOURCES=("${FY_INLINE_RENDERING_GEOMETRY_SOURCES[@]}" "${FY_INLINE_PRESS_STATE_SOURCES[@]}" "$ROOT_DIR/objc/inline/FYInlineOverlayViews.m")
FY_LAYOUT_CORE_SOURCES=(
  "${FY_INLINE_GROUPING_SOURCES[@]}"
  "${FY_LAYOUT_MEASUREMENT_SOURCES[@]}"
  "${FY_LAYOUT_CALCULATION_SOURCES[@]}"
  "${FY_INLINE_RENDERING_SOURCES[@]}"
  "$ROOT_DIR/objc/FYInlineLayout.m"
)
FY_LAYOUT_SOURCES=("${FY_LAYOUT_CORE_SOURCES[@]}" "$ROOT_DIR/objc/FYInlineLayoutDebug.m")
FY_CONTENT_ROUTER_SOURCES=("$ROOT_DIR/objc/FYContentRouter.m")
FY_CONTENT_STABILITY_SOURCES=("$ROOT_DIR/objc/ocr/FYDialogueStability.m" "$ROOT_DIR/objc/ocr/FYContentModeState.m" "$ROOT_DIR/objc/ocr/FYInlineOCRFrameStabilizer.m")
FY_CONTENT_POLICY_SOURCES=("$ROOT_DIR/objc/ocr/FYContentPolicy.m" "$ROOT_DIR/objc/ocr/FYContentTextFilter.m" "$ROOT_DIR/objc/ocr/FYContentClassifier.m" "$ROOT_DIR/objc/ocr/FYDialogueContentRouting.m")
FY_OCR_PIXEL_SOURCES=("$ROOT_DIR/objc/ocr/FYOCRPixelAnalysis.m" "$ROOT_DIR/objc/ocr/FYOCRTextProcessing.m")
FY_OCR_PURE_SOURCES=("${FY_CONTENT_STABILITY_SOURCES[@]}" "$ROOT_DIR/objc/ocr/FYOCRTextModels.m" "$ROOT_DIR/objc/ocr/FYOCRRefinement.m" "$ROOT_DIR/objc/ocr/FYOCRRefinementSession.m")
FY_OCR_WORKER_SOURCES=("$ROOT_DIR/objc/ocr/FYOCRImageGeometry.m" "$ROOT_DIR/objc/ocr/FYOCRRecognitionWorker.m")
FY_OCR_VISION_SOURCES=("$ROOT_DIR/objc/ocr/FYOCRVisionEngine.m")
FY_OCR_ENGINE_SOURCES=("${FY_CONTENT_POLICY_SOURCES[@]}" "${FY_OCR_PIXEL_SOURCES[@]}" "$ROOT_DIR/objc/FYOCRManager.m" "${FY_OCR_PURE_SOURCES[@]}" "${FY_OCR_WORKER_SOURCES[@]}" "${FY_OCR_VISION_SOURCES[@]}")
FY_OCR_SOURCES=("${FY_OCR_ENGINE_SOURCES[@]}" "${FY_CONTENT_ROUTER_SOURCES[@]}" "${FY_LAYOUT_SOURCES[@]}")
FY_PREVIEW_SOURCES=("$ROOT_DIR/objc/runtime/FYPreviewImage.m" "$ROOT_DIR/objc/runtime/FYLivePreviewScheduler.m")
FY_DELIVERY_SOURCES=("$ROOT_DIR/objc/runtime/FYRuntimeDeliveryChecks.m")
FY_RECOGNITION_CYCLE_SOURCES=("$ROOT_DIR/objc/runtime/FYRecognitionCycleScheduler.m")
FY_CONTENT_STATE_SOURCES=("$ROOT_DIR/objc/runtime/FYContentTranslationState.m")
FY_CACHE_PLANNER_SOURCES=("$ROOT_DIR/objc/runtime/FYTranslationCachePlanner.m")
FY_REQUEST_COORDINATION_SOURCES=("$ROOT_DIR/objc/runtime/FYTranslationRequestCoordinator.m")
FY_INLINE_COORDINATION_SOURCES=("$ROOT_DIR/objc/runtime/FYInlineTranslationCoordinator.m")
FY_TRANSLATION_CORE_SOURCES=("$ROOT_DIR/objc/FYTranslationManager.m" "${FY_DELIVERY_SOURCES[@]}" "${FY_CACHE_PLANNER_SOURCES[@]}" "${FY_REQUEST_COORDINATION_SOURCES[@]}")
FY_DISPLAY_TARGET_CORE_SOURCES=("$ROOT_DIR/objc/capture/FYDisplayTargetTracker.m" "$ROOT_DIR/objc/capture/FYDisplayTargetResolver.m")
FY_CAPTURE_MAPPING_SOURCES=("$ROOT_DIR/objc/capture/FYCaptureMappingState.m" "$ROOT_DIR/objc/capture/FYCaptureMappingAlgorithms.m" "$ROOT_DIR/objc/capture/FYCoordinateConversions.m")
FY_CAPTURE_MAPPING_COORDINATION_SOURCES=("$ROOT_DIR/objc/capture/FYCaptureMappingCoordinator.m")
FY_WINDOW_SOURCES=("$ROOT_DIR/objc/FYWindowManager.m" "${FY_DISPLAY_TARGET_CORE_SOURCES[@]}")
FY_GEOMETRY_SOURCES=("$ROOT_DIR/objc/FYGeometryManager.m" "${FY_CAPTURE_MAPPING_SOURCES[@]}")
FY_RUNTIME_BASE_SOURCES=(
  "${FY_RECOGNITION_CYCLE_SOURCES[@]}"
  "${FY_CONTENT_STATE_SOURCES[@]}"
  "$ROOT_DIR/objc/runtime/FYPreviewImage.m"
  "$ROOT_DIR/objc/FYTranslationTrace.m" "$ROOT_DIR/objc/FYRuntimeDiagnostics.m"
  "${FY_LAYOUT_SOURCES[@]}"
  "${FY_WINDOW_SOURCES[@]}" "${FY_OCR_ENGINE_SOURCES[@]}"
  "${FY_CONTENT_ROUTER_SOURCES[@]}"
  "${FY_GEOMETRY_SOURCES[@]}" "${FY_CAPTURE_MAPPING_COORDINATION_SOURCES[@]}" "${FY_TRANSLATION_CORE_SOURCES[@]}"
  "$ROOT_DIR/objc/FYTranslationServiceSettings.m"
)
FY_CAPTURE_PURE_SOURCES=("$ROOT_DIR/objc/capture/FYCaptureCardModels.m" "$ROOT_DIR/objc/capture/FYCaptureCardFrameSlot.m")
FY_CAPTURE_SESSION_SOURCES=("$ROOT_DIR/objc/capture/FYCaptureSessionController.m")
FY_CAPTURE_SOURCES=("$ROOT_DIR/objc/FYCaptureCardInput.m" "${FY_CAPTURE_PURE_SOURCES[@]}" "${FY_CAPTURE_SESSION_SOURCES[@]}")
FY_RUNTIME_SOURCES=("${FY_RUNTIME_BASE_SOURCES[@]}" "${FY_CAPTURE_SOURCES[@]}")
FY_LEARNING_STORAGE_SOURCES=(
  "$ROOT_DIR/objc/learning/FYLearningStore.m"
  "$ROOT_DIR/objc/learning/storage/FYLearningDatabaseSession.m"
  "$ROOT_DIR/objc/learning/storage/FYLearningSchema.m"
  "$ROOT_DIR/objc/learning/storage/FYLearningSentenceRepository.m"
  "$ROOT_DIR/objc/learning/storage/FYLearningVocabularyRepository.m"
  "$ROOT_DIR/objc/learning/storage/FYLearningBookmarkRepository.m"
  "$ROOT_DIR/objc/learning/storage/FYLearningAnalysisCacheRepository.m"
)
FY_LEARNING_ANALYZER_SOURCES=(
  "$ROOT_DIR/objc/learning/FYLearningAnalyzer.m"
  "$ROOT_DIR/objc/learning/analysis/FYLearningRequestBuilder.m"
  "$ROOT_DIR/objc/learning/analysis/FYLearningRequestState.m"
  "$ROOT_DIR/objc/learning/analysis/FYLearningResponseDecoder.m"
  "$ROOT_DIR/objc/learning/analysis/FYLearningGrammarMatcher.m"
  "$ROOT_DIR/objc/learning/analysis/FYLearningPromptBuilder.m"
  "$ROOT_DIR/objc/learning/analysis/FYLearningAnalysisParser.m"
)
FY_LEARNING_WORKFLOW_SOURCES=(
  "$ROOT_DIR/objc/learning/FYLearningCoordinator.m"
  "$ROOT_DIR/objc/learning/FYLearningSentenceWorkflow.m"
  "$ROOT_DIR/objc/learning/FYLearningAnalysisWorkflow.m"
  "$ROOT_DIR/objc/learning/FYLearningCollectionWorkflow.m"
  "$ROOT_DIR/objc/learning/FYLearningProjection.m"
)
FY_LEARNING_CORE_SOURCES=(
  "$ROOT_DIR/objc/learning/FYLearningModels.m"
  "${FY_LEARNING_STORAGE_SOURCES[@]}"
  "${FY_LEARNING_ANALYZER_SOURCES[@]}"
  "$ROOT_DIR/objc/learning/FYJapaneseTokenizer.m"
  "$ROOT_DIR/objc/learning/FYGrammarCatalog.m"
  "${FY_LEARNING_WORKFLOW_SOURCES[@]}"
)
FY_STUDY_CHAT_SESSION_SOURCES=("$ROOT_DIR/objc/learning/FYStudyChatSession.m")
FY_LEARNING_UI_SOURCES=(
  "$ROOT_DIR/objc/FYTranslationServiceView.m"
  "$ROOT_DIR/objc/learning/FYLearningViews.m"
  "$ROOT_DIR/objc/learning/FYStudyChatView.m"
  "${FY_STUDY_CHAT_SESSION_SOURCES[@]}"
  "$ROOT_DIR/objc/learning/FYGlobalShortcuts.m"
  "$ROOT_DIR/objc/learning/FYStudyOverlayPanel.m"
  "$ROOT_DIR/objc/learning/FYReferenceDictionary.m"
  "$ROOT_DIR/objc/learning/FYSavedWordReferenceView.m"
)
FY_SETTINGS_SOURCES=(
  "$ROOT_DIR/objc/settings/FYSettingsStore.m"
  "$ROOT_DIR/objc/settings/FYServiceTestController.m"
)
FY_DIAGNOSTICS_UI_SOURCES=("$ROOT_DIR/objc/diagnostics/FYDiagnosticsController.m")
FY_PRESENTATION_TEXT_SOURCES=("$ROOT_DIR/objc/presentation/FYPresentationText.m")
FY_INLINE_MANUAL_PLACEMENT_SOURCES=("$ROOT_DIR/objc/presentation/FYInlineManualPlacementCoordinator.m")
FY_INLINE_DRAG_SOURCES=("$ROOT_DIR/objc/presentation/FYInlineDragController.m")
FY_INLINE_DISPLAY_SOURCES=("${FY_PRESENTATION_TEXT_SOURCES[@]}" "${FY_INLINE_MANUAL_PLACEMENT_SOURCES[@]}" "$ROOT_DIR/objc/presentation/FYInlineDisplayCoordinator.m")
FY_INLINE_SNAPSHOT_SOURCES=("$ROOT_DIR/objc/presentation/FYInlineBlockSnapshot.m")
FY_INLINE_SELECTION_SOURCES=("${FY_INLINE_SNAPSHOT_SOURCES[@]}" "$ROOT_DIR/objc/presentation/FYInlineSelectionCoordinator.m")
FY_INLINE_CARD_ACTION_SOURCES=("$ROOT_DIR/objc/presentation/FYInlineCardActionBinder.m")
FY_INLINE_EXPANDED_READING_SOURCES=("$ROOT_DIR/objc/presentation/FYInlineExpandedReadingController.m")
FY_INLINE_OVERFLOW_POLICY_SOURCES=("$ROOT_DIR/objc/presentation/FYInlineOverflowCoordinator.m")
FY_INLINE_OVERFLOW_NATIVE_SOURCES=("$ROOT_DIR/objc/presentation/FYInlineOverflowController.m" "$ROOT_DIR/objc/presentation/FYFlippedDocumentView.m")
FY_INLINE_CARD_RENDERER_SOURCES=("$ROOT_DIR/objc/presentation/FYInlineCardRenderer.m")
FY_WORD_SELECTION_SOURCES=("$ROOT_DIR/objc/presentation/FYDisplayedSentenceState.m" "$ROOT_DIR/objc/presentation/FYWordSelectionController.m")
FY_LIVE_READING_COORDINATION_SOURCES=("$ROOT_DIR/objc/presentation/FYLiveReadingCoordinator.m")
FY_LIVE_READING_RENDERING_SOURCES=("$ROOT_DIR/objc/presentation/FYLiveReadingRenderer.m")
FY_INLINE_TRANSLATION_LIST_COORDINATION_SOURCES=("$ROOT_DIR/objc/presentation/FYInlineTranslationListCoordinator.m")
FY_INLINE_TRANSLATION_LIST_RENDERING_SOURCES=("$ROOT_DIR/objc/presentation/FYInlineTranslationListRenderer.m")
FY_LIVE_PAGE_BUILDER_SOURCES=("$ROOT_DIR/objc/presentation/FYLivePageBuilder.m")
FY_FRAME_DRIVEN_VIEW_SOURCES=("$ROOT_DIR/objc/presentation/FYFrameDrivenContentView.m")
FY_GRAMMAR_INTERACTION_SOURCES=("$ROOT_DIR/objc/presentation/FYGrammarServiceConfiguration.m" "$ROOT_DIR/objc/presentation/FYGrammarInteractionCoordinator.m")
FY_GRAMMAR_SCROLL_SOURCES=("$ROOT_DIR/objc/presentation/FYGrammarScrollRenderer.m")
FY_GRAMMAR_DETAIL_SOURCES=("$ROOT_DIR/objc/presentation/FYGrammarDetailRenderer.m")
FY_GRAMMAR_RESULTS_SOURCES=("$ROOT_DIR/objc/presentation/FYGrammarResultsRenderer.m")
FY_GRAMMAR_PAGE_BUILDER_SOURCES=("$ROOT_DIR/objc/presentation/FYGrammarPageBuilder.m")
FY_STUDY_CHAT_CONTEXT_SOURCES=("$ROOT_DIR/objc/presentation/FYStudyChatContextCoordinator.m")
FY_QUICK_SENTENCE_SOURCES=("$ROOT_DIR/objc/presentation/FYQuickSentenceCoordinator.m")
FY_STUDY_NAVIGATION_SOURCES=("$ROOT_DIR/objc/presentation/FYStudyNavigationCoordinator.m")
FY_STUDY_NATIVE_RENDERING_SOURCES=("$ROOT_DIR/objc/presentation/FYStudyChatRenderer.m" "$ROOT_DIR/objc/presentation/FYQuickSentenceRenderer.m" "$ROOT_DIR/objc/presentation/FYStudyScrollRenderer.m")
FY_COLLECTION_REVIEW_SOURCES=("$ROOT_DIR/objc/presentation/FYCollectionReviewCoordinator.m")
FY_COLLECTION_WORKFLOW_SOURCES=("$ROOT_DIR/objc/presentation/FYCollectionQueryCoordinator.m" "$ROOT_DIR/objc/presentation/FYCollectionCardCoordinator.m")
FY_COLLECTION_NATIVE_RENDERING_SOURCES=("$ROOT_DIR/objc/presentation/FYCollectionRenderer.m")
FY_REFERENCE_WORKFLOW_SOURCES=("$ROOT_DIR/objc/presentation/FYReferenceQueryCoordinator.m" "$ROOT_DIR/objc/presentation/FYSourceHoverCoordinator.m")
FY_REFERENCE_NATIVE_RENDERING_SOURCES=("$ROOT_DIR/objc/presentation/FYReferenceRenderer.m")
FY_PRESENTATION_SOURCES=(
  "${FY_REFERENCE_WORKFLOW_SOURCES[@]}"
  "${FY_REFERENCE_NATIVE_RENDERING_SOURCES[@]}"
  "${FY_COLLECTION_WORKFLOW_SOURCES[@]}"
  "${FY_COLLECTION_NATIVE_RENDERING_SOURCES[@]}"
  "${FY_COLLECTION_REVIEW_SOURCES[@]}"
  "${FY_STUDY_NATIVE_RENDERING_SOURCES[@]}"
  "${FY_STUDY_NAVIGATION_SOURCES[@]}"
  "${FY_QUICK_SENTENCE_SOURCES[@]}"
  "${FY_STUDY_CHAT_CONTEXT_SOURCES[@]}"
  "${FY_INLINE_DISPLAY_SOURCES[@]}"
  "${FY_INLINE_DRAG_SOURCES[@]}"
  "${FY_INLINE_SELECTION_SOURCES[@]}"
  "${FY_INLINE_CARD_ACTION_SOURCES[@]}"
  "${FY_INLINE_EXPANDED_READING_SOURCES[@]}"
  "${FY_INLINE_OVERFLOW_POLICY_SOURCES[@]}"
  "${FY_INLINE_OVERFLOW_NATIVE_SOURCES[@]}"
  "${FY_INLINE_CARD_RENDERER_SOURCES[@]}"
  "${FY_WORD_SELECTION_SOURCES[@]}"
  "${FY_LIVE_READING_COORDINATION_SOURCES[@]}"
  "${FY_LIVE_READING_RENDERING_SOURCES[@]}"
  "${FY_INLINE_TRANSLATION_LIST_COORDINATION_SOURCES[@]}"
  "${FY_INLINE_TRANSLATION_LIST_RENDERING_SOURCES[@]}"
  "${FY_LIVE_PAGE_BUILDER_SOURCES[@]}"
  "${FY_FRAME_DRIVEN_VIEW_SOURCES[@]}"
  "${FY_GRAMMAR_INTERACTION_SOURCES[@]}"
  "${FY_GRAMMAR_PAGE_BUILDER_SOURCES[@]}"
  "${FY_GRAMMAR_RESULTS_SOURCES[@]}"
  "${FY_GRAMMAR_DETAIL_SOURCES[@]}"
  "${FY_GRAMMAR_SCROLL_SOURCES[@]}"
  "$ROOT_DIR/objc/presentation/FYSubtitlePresenter.m"
  "$ROOT_DIR/objc/presentation/FYInlineOverlayController.m"
  "$ROOT_DIR/objc/presentation/FYMainWindowController.m"
  "$ROOT_DIR/objc/presentation/FYCollectionController.m"
  "$ROOT_DIR/objc/presentation/FYGrammarPresentationController.m"
  "$ROOT_DIR/objc/presentation/FYStudyPresentationController.m"
  "$ROOT_DIR/objc/presentation/FYReferencePresentationController.m"
)
FY_REALTIME_WORKFLOW_SOURCES=(
  "$ROOT_DIR/objc/runtime/FYRealtimeRecognitionFrame.m"
  "$ROOT_DIR/objc/runtime/FYPreparedRealtimeContent.m"
  "$ROOT_DIR/objc/runtime/FYRealtimeRecognitionWorkflow.m"
  "$ROOT_DIR/objc/runtime/FYRealtimeContentPreparation.m"
  "$ROOT_DIR/objc/runtime/FYRealtimeContentAdmission.m"
  "$ROOT_DIR/objc/runtime/FYRealtimeRequestWorkflow.m"
  "$ROOT_DIR/objc/runtime/FYRealtimeResultDelivery.m"
)
FY_APP_RUNTIME_SOURCES=(
  "${FY_REALTIME_WORKFLOW_SOURCES[@]}"
  "${FY_INLINE_COORDINATION_SOURCES[@]}"
  "$ROOT_DIR/objc/runtime/FYLivePreviewScheduler.m"
  "$ROOT_DIR/objc/runtime/FYTranslationRuntimeController.m"
  "$ROOT_DIR/objc/runtime/FYCaptureRuntimeController.m"
)
FY_APP_HOST_SOURCES=(
  "$ROOT_DIR/objc/app/FYAppRuntimeBridge.m"
  "$ROOT_DIR/objc/app/FYAppOverlayBridge.m"
  "$ROOT_DIR/objc/app/FYAppPresentationBridge.m"
  "$ROOT_DIR/objc/app/FYAppSettingsBridge.m"
  "$ROOT_DIR/objc/app/FYAppSupport.m"
  "${FY_APP_RUNTIME_SOURCES[@]}"
  "${FY_PRESENTATION_SOURCES[@]}"
  "${FY_SETTINGS_SOURCES[@]}" "${FY_DIAGNOSTICS_UI_SOURCES[@]}"
  "$ROOT_DIR/objc/app/FYAppDelegate.m"
  "$ROOT_DIR/objc/FYAppDiagnostics.m"
  "$ROOT_DIR/objc/FYGrammarActionState.m"
)
FY_APP_LINK_SOURCES=("${FY_APP_HOST_SOURCES[@]}" "${FY_RUNTIME_SOURCES[@]}" "${FY_LEARNING_CORE_SOURCES[@]}" "${FY_LEARNING_UI_SOURCES[@]}")
FY_APP_SOURCES=("$ROOT_DIR/objc/LiveCaptionTranslator.m" "$ROOT_DIR/objc/FYAppUpdater.m" "${FY_APP_LINK_SOURCES[@]}")
