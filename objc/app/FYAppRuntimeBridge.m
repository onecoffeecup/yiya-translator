#import "FYAppDelegateInternal.h"

// Compatibility actions and aliases only; state belongs to the existing owners.
@interface AppDelegate (FYRuntimeCompatibility)
@end

@implementation AppDelegate (FYRuntimeCompatibility)
- (NSTimer *)timer { return [self translationRuntimeController].timer; }

- (void)setTimer:(NSTimer *)value { [self translationRuntimeController].timer = value; }

- (FYTranslationTaskOwner *)translationTaskOwner { return [self translationRuntimeController].translationTaskOwner; }

- (void)setTranslationTaskOwner:(FYTranslationTaskOwner *)value { [self translationRuntimeController].translationTaskOwner = value; }

- (NSInteger)translationGeneration { return [self translationRuntimeController].translationGeneration; }

- (void)setTranslationGeneration:(NSInteger)value { [self translationRuntimeController].translationGeneration = value; }

- (BOOL)running { return [self translationRuntimeController].running; }

- (void)setRunning:(BOOL)value { [self translationRuntimeController].running = value; }

- (BOOL)inFlight { return [self translationRuntimeController].inFlight; }

- (void)setInFlight:(BOOL)value { [self translationRuntimeController].inFlight = value; }

- (NSUInteger)contentTranslationRevision { return [self translationRuntimeController].contentTranslationRevision; }

- (void)setContentTranslationRevision:(NSUInteger)value { [self translationRuntimeController].contentTranslationRevision = value; }

- (NSUInteger)contentTranslationOperations { return [self translationRuntimeController].contentTranslationOperations; }

- (void)setContentTranslationOperations:(NSUInteger)value { [self translationRuntimeController].contentTranslationOperations = value; }

- (NSString *)contentTranslationText { return [self translationRuntimeController].contentTranslationText; }

- (void)setContentTranslationText:(NSString *)value { [self translationRuntimeController].contentTranslationText = value; }

- (NSInteger)contentTranslationMode { return [self translationRuntimeController].contentTranslationMode; }

- (void)setContentTranslationMode:(NSInteger)value { [self translationRuntimeController].contentTranslationMode = value; }

- (NSArray<OCRTextItem *> *)contentTranslationUIItems { return [self translationRuntimeController].contentTranslationUIItems; }

- (void)setContentTranslationUIItems:(NSArray<OCRTextItem *> *)value { [self translationRuntimeController].contentTranslationUIItems = value; }

- (NSInteger)contentTranslationGeometryGeneration { return [self translationRuntimeController].contentTranslationGeometryGeneration; }

- (void)setContentTranslationGeometryGeneration:(NSInteger)value { [self translationRuntimeController].contentTranslationGeometryGeneration = value; }

- (uint32_t)contentTranslationDisplayTarget { return [self translationRuntimeController].contentTranslationDisplayTarget; }

- (void)setContentTranslationDisplayTarget:(uint32_t)value { [self translationRuntimeController].contentTranslationDisplayTarget = value; }

- (NSUInteger)inlineTranslationSerial { return [self translationRuntimeController].inlineTranslationSerial; }

- (void)setInlineTranslationSerial:(NSUInteger)value { [self translationRuntimeController].inlineTranslationSerial = value; }

- (FYInlinePendingLongBatch *)pendingInlineLongBatch { return [self translationRuntimeController].pendingInlineLongBatch; }

- (void)setPendingInlineLongBatch:(FYInlinePendingLongBatch *)value { [self translationRuntimeController].pendingInlineLongBatch = value; }

- (FYTranslationRunState *)translationRunState { return [self translationRuntimeController].translationRunState; }

- (void)setTranslationRunState:(FYTranslationRunState *)value { [self translationRuntimeController].translationRunState = value; }

- (FYTranslationCache *)dialogueTranslationCache { return [self translationRuntimeController].dialogueTranslationCache; }

- (void)setDialogueTranslationCache:(FYTranslationCache *)value { [self translationRuntimeController].dialogueTranslationCache = value; }

- (FYOCRStabilityOwner *)ocrStabilityOwner { return [self translationRuntimeController].ocrStabilityOwner; }

- (void)setOcrStabilityOwner:(FYOCRStabilityOwner *)value { [self translationRuntimeController].ocrStabilityOwner = value; }

- (FYInlineTranslationCache *)inlineCacheOwner { return [self translationRuntimeController].inlineCacheOwner; }

- (void)setInlineCacheOwner:(FYInlineTranslationCache *)value { [self translationRuntimeController].inlineCacheOwner = value; }

- (void)setContentRouter:(FYContentRouter *)value { [self translationRuntimeController].contentRouter = value; }

- (void)setInlineFrameStabilizer:(FYInlineOCRFrameStabilizer *)value { [self translationRuntimeController].inlineFrameStabilizer = value; }

- (FYOCRRefinementStabilizer *)ocrRefinementStabilizer { return [self translationRuntimeController].ocrRefinementStabilizer; }

- (void)setOcrRefinementStabilizer:(FYOCRRefinementStabilizer *)value { [self translationRuntimeController].ocrRefinementStabilizer = value; }

- (NSDictionary *)ocrRefinementContext { return [self translationRuntimeController].ocrRefinementContext; }

- (void)setOcrRefinementContext:(NSDictionary *)value { [self translationRuntimeController].ocrRefinementContext = value; }

- (NSArray<NSString *> *)inlinePendingGroupedTexts { return [self translationRuntimeController].inlinePendingGroupedTexts; }

- (void)setInlinePendingGroupedTexts:(NSArray<NSString *> *)value { [self translationRuntimeController].inlinePendingGroupedTexts = value; }

- (NSInteger)inlinePendingGroupedCount { return [self translationRuntimeController].inlinePendingGroupedCount; }

- (void)setInlinePendingGroupedCount:(NSInteger)value { [self translationRuntimeController].inlinePendingGroupedCount = value; }

- (void)setInlineGrouper:(FYInlineGrouper *)value { [self translationRuntimeController].inlineGrouper = value; }

- (NSInteger)ocrGeometryGeneration { return [self translationRuntimeController].ocrGeometryGeneration; }

- (void)setOcrGeometryGeneration:(NSInteger)value { [self translationRuntimeController].ocrGeometryGeneration = value; }

- (uint32_t)ocrDisplayTargetWindowID { return [self translationRuntimeController].ocrDisplayTargetWindowID; }

- (void)setOcrDisplayTargetWindowID:(uint32_t)value { [self translationRuntimeController].ocrDisplayTargetWindowID = value; }

- (NSString *)inlineOCRPendingText { return [self translationRuntimeController].inlineOCRPendingText; }

- (void)setInlineOCRPendingText:(NSString *)value { [self translationRuntimeController].inlineOCRPendingText = value; }

- (NSInteger)inlineOCRPendingCount { return [self translationRuntimeController].inlineOCRPendingCount; }

- (void)setInlineOCRPendingCount:(NSInteger)value { [self translationRuntimeController].inlineOCRPendingCount = value; }

- (NSInteger)translationCount { return [self translationRuntimeController].translationCount; }

- (void)setTranslationCount:(NSInteger)value { [self translationRuntimeController].translationCount = value; }

- (NSURLSessionDataTask *)activeTranslationTask { return [[self translationRuntimeController] activeTranslationTask]; }

- (void)setActiveTranslationTask:(NSURLSessionDataTask *)task { [[self translationRuntimeController] setActiveTranslationTask:task]; }

- (void)invalidateContentTranslation { [[self translationRuntimeController] invalidateContentTranslation]; }

- (BOOL)pendingContentMatchesText:(NSString *)text mode:(NSInteger)mode { return [[self translationRuntimeController] pendingContentMatchesText:text mode:mode]; }

- (BOOL)pendingInlineMatchesItems:(NSArray<OCRTextItem *> *)items { return [[self translationRuntimeController] pendingInlineMatchesItems:items]; }

- (NSUInteger)beginContentTranslation:(NSString *)text mode:(NSInteger)mode { return [[self translationRuntimeController] beginContentTranslation:text mode:mode]; }

- (NSArray<NSString *> *)longInlineKeysForItems:(NSArray<OCRTextItem *> *)items { return [[self translationRuntimeController] longInlineKeysForItems:items]; }

- (NSUInteger)beginInlineContentTranslation:(NSString *)text items:(NSArray<OCRTextItem *> *)items trace:(NSDictionary *)trace { return [[self translationRuntimeController] beginInlineContentTranslation:text items:items trace:trace]; }

- (void)finishContentTranslation:(NSUInteger)revision { [[self translationRuntimeController] finishContentTranslation:revision]; }

- (void)advanceTranslationGeneration { [[self translationRuntimeController] advanceTranslationGeneration]; }

- (void)toggleRunning:(id)sender { [[self translationRuntimeController] toggleRunning:sender]; }

- (void)start { [[self translationRuntimeController] start]; }

- (void)stop { [[self translationRuntimeController] stop]; }

- (void)handleInlineTranslationResult:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items error:(NSError *)translationError failureStatus:(NSString *)failureStatus successPrefix:(NSString *)successPrefix { [[self translationRuntimeController] handleInlineTranslationResult:translations forItems:items error:translationError failureStatus:failureStatus successPrefix:successPrefix]; }

- (void)timerFired:(NSTimer *)timer { [[self translationRuntimeController] timerFired:timer]; }

- (void)translateCurrentInterface:(id)sender { [[self translationRuntimeController] translateCurrentInterface:sender]; }

- (NSArray<OCRTextItem *> *)mergedInlineTextItemsFromItems:(NSArray<OCRTextItem *> *)items { return [[self translationRuntimeController] mergedInlineTextItemsFromItems:items]; }

- (FYInlineTextBlock *)inlineLayoutBlockForItem:(OCRTextItem *)item order:(NSInteger)order { return [[self translationRuntimeController] inlineLayoutBlockForItem:item order:order]; }

- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items { return [[self translationRuntimeController] filteredInlineTextItems:items]; }

- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items strict:(BOOL)strict { return [[self translationRuntimeController] filteredInlineTextItems:items strict:strict]; }

- (NSString *)dialogueTextFromItems:(NSArray<OCRTextItem *> *)items speakerLabelOnly:(BOOL *)speakerLabelOnly { return [[self translationRuntimeController] dialogueTextFromItems:items speakerLabelOnly:speakerLabelOnly]; }

- (BOOL)shouldIgnoreInlineText:(NSString *)text normalized:(NSString *)normalized boundingBox:(CGRect)box strict:(BOOL)strict { return [[self translationRuntimeController] shouldIgnoreInlineText:text normalized:normalized boundingBox:box strict:strict]; }

- (BOOL)isButtonLikeInlineText:(NSString *)normalized { return [[self translationRuntimeController] isButtonLikeInlineText:normalized]; }

- (double)inlinePriorityForText:(NSString *)text normalized:(NSString *)normalized boundingBox:(CGRect)box { return [[self translationRuntimeController] inlinePriorityForText:text normalized:normalized boundingBox:box]; }

- (NSString *)inlineTranslationCacheKeyForItem:(OCRTextItem *)item { return [[self translationRuntimeController] inlineTranslationCacheKeyForItem:item]; }

- (void)translateInlineTextItems:(NSArray<OCRTextItem *> *)items completion:(void (^)(NSArray<NSString *> *translations, NSError *error))completion { [[self translationRuntimeController] translateInlineTextItems:items completion:completion]; }

- (void)translateInlineLongItems:(NSArray<OCRTextItem *> *)items indexes:(NSArray<NSNumber *> *)indexes
    keys:(NSArray<NSString *> *)keys translations:(NSMutableArray<NSString *> *)translations
    completion:(void (^)(NSError *))completion { [[self translationRuntimeController] translateInlineLongItems:items indexes:indexes keys:keys translations:translations completion:completion]; }

- (void)translateInlineBatch:(NSArray<OCRTextItem *> *)items
                     indexes:(NSArray<NSNumber *> *)indexes
                        keys:(NSArray<NSString *> *)keys
                translations:(NSMutableArray<NSString *> *)translations
                        long:(BOOL)isLong
                  completion:(void (^)(NSError *error))completion { [[self translationRuntimeController] translateInlineBatch:items indexes:indexes keys:keys translations:translations long:isLong completion:completion]; }

- (void)cacheInlineTranslation:(NSString *)value forKey:(NSString *)key { [[self translationRuntimeController] cacheInlineTranslation:value forKey:key]; }

- (NSArray<NSString *> *)parseNumberedTranslations:(NSString *)text expectedCount:(NSUInteger)count { return [[self translationRuntimeController] parseNumberedTranslations:text expectedCount:count]; }

- (FYInlineOCRFrameStabilizer *)inlineFrameStabilizer { return [[self translationRuntimeController] inlineFrameStabilizer]; }

- (FYInlineGrouper *)inlineGrouper { return [[self translationRuntimeController] inlineGrouper]; }

- (void)translateText:(NSString *)text completion:(void (^)(NSString *translated, NSError *error))completion { [[self translationRuntimeController] translateText:text completion:completion]; }

- (void)translateText:(NSString *)text systemPrompt:(NSString *)systemPrompt maxTokens:(NSInteger)maxTokens completion:(void (^)(NSString *translated, NSError *error))completion { [[self translationRuntimeController] translateText:text systemPrompt:systemPrompt maxTokens:maxTokens completion:completion]; }

- (void)translateDialogueText:(NSString *)text
                     identity:(FYRequestIdentity *)identity
                 systemPrompt:(NSString *)systemPrompt
                   completion:(void (^)(NSString *translated, NSError *error))completion { [[self translationRuntimeController] translateDialogueText:text identity:identity systemPrompt:systemPrompt completion:completion]; }

- (void)translateTextRealtime:(NSString *)text
                 systemPrompt:(NSString *)systemPrompt
                    maxTokens:(NSInteger)maxTokens
                   completion:(void (^)(NSString *translated, NSError *error))completion { [[self translationRuntimeController] translateTextRealtime:text systemPrompt:systemPrompt maxTokens:maxTokens completion:completion]; }

- (void)translateText:(NSString *)text
          systemPrompt:(NSString *)systemPrompt
             maxTokens:(NSInteger)maxTokens
         modelOverride:(NSString *)modelOverride
            completion:(void (^)(NSString *translated, NSError *error))completion { [[self translationRuntimeController] translateText:text systemPrompt:systemPrompt maxTokens:maxTokens modelOverride:modelOverride completion:completion]; }

- (void)translateText:(NSString *)text systemPrompt:(NSString *)systemPrompt maxTokens:(NSInteger)maxTokens
        modelOverride:(NSString *)modelOverride longText:(BOOL)longText serviceTest:(BOOL)serviceTest
        completion:(void (^)(NSString *, NSError *))completion { [[self translationRuntimeController] translateText:text systemPrompt:systemPrompt maxTokens:maxTokens modelOverride:modelOverride longText:longText serviceTest:serviceTest completion:completion]; }

- (NSURL *)chatCompletionsURL { return [[self translationRuntimeController] chatCompletionsURL]; }

- (NSString *)systemPrompt { return [[self translationRuntimeController] systemPrompt]; }

- (BOOL)autoContentModeEnabled { return [[self translationRuntimeController] autoContentModeEnabled]; }

- (NSTimeInterval)translationAttemptThrottleForMode:(NSInteger)modeSegment { return [[self translationRuntimeController] translationAttemptThrottleForMode:modeSegment]; }

- (NSArray<OCRTextItem *> *)blocksInsideModalIfPresent:(NSArray<OCRTextItem *> *)blocks
                                              inImage:(CGImageRef)image
                                    normalizedExclusions:(NSArray<NSValue *> *)exclusionValues { return [[self translationRuntimeController] blocksInsideModalIfPresent:blocks inImage:image normalizedExclusions:exclusionValues]; }

- (NSInteger)effectiveModeSegment { return [[self translationRuntimeController] effectiveModeSegment]; }

- (NSInteger)stableContentModeForBlocks:(NSArray<OCRTextItem *> *)blocks { return [[self translationRuntimeController] stableContentModeForBlocks:blocks]; }

- (NSString *)systemPromptForMode:(NSInteger)modeSegment { return [[self translationRuntimeController] systemPromptForMode:modeSegment]; }

- (FYInlineTranslationCache *)inlineCache { return [[self translationRuntimeController] inlineCache]; }

- (NSMutableDictionary *)inlineTranslationCache { return [[self translationRuntimeController] inlineTranslationCache]; }

- (void)setInlineTranslationCache:(NSMutableDictionary<NSString *, NSString *> *)value { [[self translationRuntimeController] setInlineTranslationCache:value]; }

- (FYContentRouter *)contentRouter { return [[self translationRuntimeController] contentRouter]; }

- (FYContentModeStability *)modeStability { return [[self translationRuntimeController] modeStability]; }

- (NSInteger)detectedModeSegment { return [[self translationRuntimeController] detectedModeSegment]; }

- (void)setDetectedModeSegment:(NSInteger)value { [[self translationRuntimeController] setDetectedModeSegment:value]; }

- (NSInteger)candidateModeSegment { return [[self translationRuntimeController] candidateModeSegment]; }

- (void)setCandidateModeSegment:(NSInteger)value { [[self translationRuntimeController] setCandidateModeSegment:value]; }

- (NSInteger)candidateModeHits { return [[self translationRuntimeController] candidateModeHits]; }

- (void)setCandidateModeHits:(NSInteger)value { [[self translationRuntimeController] setCandidateModeHits:value]; }

- (FYTranslationRunState *)translationState { return [[self translationRuntimeController] translationState]; }

- (NSDate *)translationProcessingDate { return [[self translationRuntimeController] translationProcessingDate]; }

- (NSString *)lastTranslatedNormalizedText { return [[self translationRuntimeController] lastTranslatedNormalizedText]; }

- (void)setLastTranslatedNormalizedText:(NSString *)value { [[self translationRuntimeController] setLastTranslatedNormalizedText:value]; }

- (NSString *)lastSubmittedNormalizedText { return [[self translationRuntimeController] lastSubmittedNormalizedText]; }

- (void)setLastSubmittedNormalizedText:(NSString *)value { [[self translationRuntimeController] setLastSubmittedNormalizedText:value]; }

- (NSDate *)lastTranslationAttemptDate { return [[self translationRuntimeController] lastTranslationAttemptDate]; }

- (void)setLastTranslationAttemptDate:(NSDate *)value { [[self translationRuntimeController] setLastTranslationAttemptDate:value]; }

- (NSTimeInterval)recognitionPollingInterval { return [[self translationRuntimeController] recognitionPollingInterval]; }

- (void)restartTimerIfRunning { [[self translationRuntimeController] restartTimerIfRunning]; }

- (FYOCRStabilityOwner *)stabilityOwner { return [[self translationRuntimeController] stabilityOwner]; }

- (NSString *)stableCandidate { return [[self translationRuntimeController] stableCandidate]; }

- (void)setStableCandidate:(NSString *)value { [[self translationRuntimeController] setStableCandidate:value]; }

- (NSInteger)stableCandidateCount { return [[self translationRuntimeController] stableCandidateCount]; }

- (void)setStableCandidateCount:(NSInteger)value { [[self translationRuntimeController] setStableCandidateCount:value]; }

- (BOOL)isStableText:(NSString *)normalized { return [[self translationRuntimeController] isStableText:normalized]; }

- (BOOL)shouldAcceptInlineOCRCorrection:(NSString *)text comparedTo:(NSString *)rendered { return [[self translationRuntimeController] shouldAcceptInlineOCRCorrection:text comparedTo:rendered]; }

- (BOOL)isSameSubtitleText:(NSString *)text comparedTo:(NSString *)previous { return [[self translationRuntimeController] isSameSubtitleText:text comparedTo:previous]; }

- (NSString *)displayableTranslation:(NSString *)translated sourceText:(NSString *)sourceText { return [[self translationRuntimeController] displayableTranslation:translated sourceText:sourceText]; }

- (void)setWindowManager:(FYWindowManager *)value { [self captureRuntimeController].windowManager = value; }

- (void)setOcrManager:(FYOCRManager *)value { [self captureRuntimeController].ocrManager = value; }

- (dispatch_queue_t)captureQueue { return [self captureRuntimeController].captureQueue; }

- (void)setCaptureQueue:(dispatch_queue_t)value { [self captureRuntimeController].captureQueue = value; }

- (dispatch_queue_t)previewQueue { return [self captureRuntimeController].previewQueue; }

- (void)setPreviewQueue:(dispatch_queue_t)value { [self captureRuntimeController].previewQueue = value; }

- (NSTimer *)previewTimer { return [self captureRuntimeController].previewTimer; }

- (void)setPreviewTimer:(NSTimer *)value { [self captureRuntimeController].previewTimer = value; }

- (BOOL)previewInFlight { return [self captureRuntimeController].previewInFlight; }

- (void)setPreviewInFlight:(BOOL)value { [self captureRuntimeController].previewInFlight = value; }

- (NSUInteger)previewRequestSerial { return [self captureRuntimeController].previewRequestSerial; }

- (void)setPreviewRequestSerial:(NSUInteger)value { [self captureRuntimeController].previewRequestSerial = value; }

- (NSUInteger)previewRenderSerial { return [self captureRuntimeController].previewRenderSerial; }

- (void)setPreviewRenderSerial:(NSUInteger)value { [self captureRuntimeController].previewRenderSerial = value; }

- (uint64_t)lastPreviewCaptureFrameIndex { return [self captureRuntimeController].lastPreviewCaptureFrameIndex; }

- (void)setLastPreviewCaptureFrameIndex:(uint64_t)value { [self captureRuntimeController].lastPreviewCaptureFrameIndex = value; }

- (NSMutableArray<WindowItem *> *)windows { return [self captureRuntimeController].windows; }

- (void)setWindows:(NSMutableArray<WindowItem *> *)value { [self captureRuntimeController].windows = value; }

- (BOOL)showAllWindowsInPicker { return [self captureRuntimeController].showAllWindowsInPicker; }

- (void)setShowAllWindowsInPicker:(BOOL)value { [self captureRuntimeController].showAllWindowsInPicker = value; }

- (NSString *)windowPickerPlaceholder { return [self captureRuntimeController].windowPickerPlaceholder; }

- (void)setWindowPickerPlaceholder:(NSString *)value { [self captureRuntimeController].windowPickerPlaceholder = value; }

- (BOOL)windowSelectionLost { return [self captureRuntimeController].windowSelectionLost; }

- (void)setWindowSelectionLost:(BOOL)value { [self captureRuntimeController].windowSelectionLost = value; }

- (BOOL)displayTargetResolved { return [self captureRuntimeController].displayTargetResolved; }

- (void)setDisplayTargetResolved:(BOOL)value { [self captureRuntimeController].displayTargetResolved = value; }

- (BOOL)displayTargetAmbiguous { return [self captureRuntimeController].displayTargetAmbiguous; }

- (void)setDisplayTargetAmbiguous:(BOOL)value { [self captureRuntimeController].displayTargetAmbiguous = value; }

- (uint32_t)resolvedDisplayTargetID { return [self captureRuntimeController].resolvedDisplayTargetID; }

- (void)setResolvedDisplayTargetID:(uint32_t)value { [self captureRuntimeController].resolvedDisplayTargetID = value; }

- (NSDate *)lastDisplayTargetProbeDate { return [self captureRuntimeController].lastDisplayTargetProbeDate; }

- (void)setLastDisplayTargetProbeDate:(NSDate *)value { [self captureRuntimeController].lastDisplayTargetProbeDate = value; }

- (NSInteger)geometryGeneration { return [self captureRuntimeController].geometryGeneration; }

- (void)setGeometryGeneration:(NSInteger)value { [self captureRuntimeController].geometryGeneration = value; }

- (NSString *)lastDisplayGeometryToken { return [self captureRuntimeController].lastDisplayGeometryToken; }

- (void)setLastDisplayGeometryToken:(NSString *)value { [self captureRuntimeController].lastDisplayGeometryToken = value; }

- (BOOL)inlineGeometryPending { return [self captureRuntimeController].inlineGeometryPending; }

- (void)setInlineGeometryPending:(BOOL)value { [self captureRuntimeController].inlineGeometryPending = value; }

- (void)setCaptureCardInput:(FYCaptureCardInput *)value { [self captureRuntimeController].captureCardInput = value; }

- (FYCaptureMappingCache *)captureMappingCache { return [self captureRuntimeController].captureMappingCache; }

- (void)setCaptureMappingCache:(FYCaptureMappingCache *)value { [self captureRuntimeController].captureMappingCache = value; }

- (FYMappingValidationSchedule *)mappingValidationSchedule { return [self captureRuntimeController].mappingValidationSchedule; }

- (void)setMappingValidationSchedule:(FYMappingValidationSchedule *)value { [self captureRuntimeController].mappingValidationSchedule = value; }

- (FYAutoLocateSchedule *)autoLocateSchedule { return [self captureRuntimeController].autoLocateSchedule; }

- (void)setAutoLocateSchedule:(FYAutoLocateSchedule *)value { [self captureRuntimeController].autoLocateSchedule = value; }

- (NSInteger)inputSourceSegment { return [self captureRuntimeController].inputSourceSegment; }

- (void)setInputSourceSegment:(NSInteger)value { [self captureRuntimeController].inputSourceSegment = value; }

- (NSString *)selectedCaptureDeviceID { return [self captureRuntimeController].selectedCaptureDeviceID; }

- (void)setSelectedCaptureDeviceID:(NSString *)value { [self captureRuntimeController].selectedCaptureDeviceID = value; }

- (BOOL)captureDeviceListLoaded { return [self captureRuntimeController].captureDeviceListLoaded; }

- (void)setCaptureDeviceListLoaded:(BOOL)value { [self captureRuntimeController].captureDeviceListLoaded = value; }

- (uint64_t)lastOCRedCaptureFrameIndex { return [self translationRuntimeController].lastOCRedCaptureFrameIndex; }

- (void)setLastOCRedCaptureFrameIndex:(uint64_t)value { [self translationRuntimeController].lastOCRedCaptureFrameIndex = value; }

- (NSDate *)lastPreviewDate { return [self captureRuntimeController].lastPreviewDate; }

- (void)setLastPreviewDate:(NSDate *)value { [self captureRuntimeController].lastPreviewDate = value; }

- (NSDate *)lastWindowRecoveryAttemptDate { return [self captureRuntimeController].lastWindowRecoveryAttemptDate; }

- (void)setLastWindowRecoveryAttemptDate:(NSDate *)value { [self captureRuntimeController].lastWindowRecoveryAttemptDate = value; }

- (BOOL)captureUnavailable { return [self captureRuntimeController].captureUnavailable; }

- (void)setCaptureUnavailable:(BOOL)value { [self captureRuntimeController].captureUnavailable = value; }

- (BOOL)screenAccessRequestedDuringSession { return [self captureRuntimeController].screenAccessRequestedDuringSession; }

- (void)setScreenAccessRequestedDuringSession:(BOOL)value { [self captureRuntimeController].screenAccessRequestedDuringSession = value; }

- (BOOL)captionPanelVisibleBeforeRegionSelection { return [self captureRuntimeController].captionPanelVisibleBeforeRegionSelection; }

- (void)setCaptionPanelVisibleBeforeRegionSelection:(BOOL)value { [self captureRuntimeController].captionPanelVisibleBeforeRegionSelection = value; }

- (BOOL)ocrPreviewVisibleBeforeRegionSelection { return [self captureRuntimeController].ocrPreviewVisibleBeforeRegionSelection; }

- (void)setOcrPreviewVisibleBeforeRegionSelection:(BOOL)value { [self captureRuntimeController].ocrPreviewVisibleBeforeRegionSelection = value; }

- (NSPanel *)regionSelectionPanel { return [self captureRuntimeController].regionSelectionPanel; }

- (void)setRegionSelectionPanel:(NSPanel *)value { [self captureRuntimeController].regionSelectionPanel = value; }

- (id)regionSelectionKeyMonitor { return [self captureRuntimeController].regionSelectionKeyMonitor; }

- (void)setRegionSelectionKeyMonitor:(id)value { [self captureRuntimeController].regionSelectionKeyMonitor = value; }

- (BOOL)selectingCaptureRegion { return [self captureRuntimeController].selectingCaptureRegion; }

- (void)setSelectingCaptureRegion:(BOOL)value { [self captureRuntimeController].selectingCaptureRegion = value; }

- (BOOL)selectOCRRegionAfterCaptureCalibration { return [self captureRuntimeController].selectOCRRegionAfterCaptureCalibration; }

- (void)setSelectOCRRegionAfterCaptureCalibration:(BOOL)value { [self captureRuntimeController].selectOCRRegionAfterCaptureCalibration = value; }

- (NSPanel *)captureCalibrationPanel { return [self captureRuntimeController].captureCalibrationPanel; }

- (void)setCaptureCalibrationPanel:(NSPanel *)value { [self captureRuntimeController].captureCalibrationPanel = value; }

- (id)captureCalibrationKeyMonitor { return [self captureRuntimeController].captureCalibrationKeyMonitor; }

- (void)setCaptureCalibrationKeyMonitor:(id)value { [self captureRuntimeController].captureCalibrationKeyMonitor = value; }

- (NSPanel *)ocrPreviewPanel { return [self captureRuntimeController].ocrPreviewPanel; }

- (void)setOcrPreviewPanel:(NSPanel *)value { [self captureRuntimeController].ocrPreviewPanel = value; }

- (NSTextField *)ocrPreviewLabel { return [self captureRuntimeController].ocrPreviewLabel; }

- (void)setOcrPreviewLabel:(NSTextField *)value { [self captureRuntimeController].ocrPreviewLabel = value; }

- (NSArray<NSDictionary *> *)overlayWindowSnapshot { return [self captureRuntimeController].overlayWindowSnapshot; }

- (void)setOverlayWindowSnapshot:(NSArray<NSDictionary *> *)value { [self captureRuntimeController].overlayWindowSnapshot = value; }

- (NSNumber *)overlayOwnerPIDSnapshot { return [self captureRuntimeController].overlayOwnerPIDSnapshot; }

- (void)setOverlayOwnerPIDSnapshot:(NSNumber *)value { [self captureRuntimeController].overlayOwnerPIDSnapshot = value; }

- (pid_t)selectedWindowOwnerPID { return [[self captureRuntimeController] selectedWindowOwnerPID]; }

- (NSArray<NSDictionary *> *)windowInfosIncludingWindow:(uint32_t)windowID { return [[self captureRuntimeController] windowInfosIncludingWindow:windowID]; }

- (NSArray<NSDictionary *> *)onScreenWindowInfos { return [[self captureRuntimeController] onScreenWindowInfos]; }

- (FYOCRManager *)ocrManager { return [[self captureRuntimeController] ocrManager]; }

- (FYWindowManager *)windowManager { return [[self captureRuntimeController] windowManager]; }

- (NSArray<WindowItem *> *)availableWindowItems { return [[self captureRuntimeController] availableWindowItems]; }

- (NSInteger)quickTimeCapturePriority:(WindowItem *)item { return [[self captureRuntimeController] quickTimeCapturePriority:item]; }

- (NSArray<WindowItem *> *)displayedWindowItems { return [[self captureRuntimeController] displayedWindowItems]; }

- (BOOL)hasRecommendedWindowItems { return [[self captureRuntimeController] hasRecommendedWindowItems]; }

- (NSString *)windowBaseTitleForItem:(WindowItem *)item { return [[self captureRuntimeController] windowBaseTitleForItem:item]; }

- (NSString *)windowMenuTitleForItem:(WindowItem *)item occurrence:(NSUInteger)occurrence { return [[self captureRuntimeController] windowMenuTitleForItem:item occurrence:occurrence]; }

- (void)rebuildWindowMenuPreservingSelection { [[self captureRuntimeController] rebuildWindowMenuPreservingSelection]; }

- (void)refreshWindows:(id)sender { [[self captureRuntimeController] refreshWindows:sender]; }

- (void)toggleWindowListScope:(id)sender { [[self captureRuntimeController] toggleWindowListScope:sender]; }

- (BOOL)selectWindowWithID:(uint32_t)windowID notifyChange:(BOOL)notify { return [[self captureRuntimeController] selectWindowWithID:windowID notifyChange:notify]; }

- (BOOL)recoverWindowSelectionIfRecreated { return [[self captureRuntimeController] recoverWindowSelectionIfRecreated]; }

- (void)windowSelectionChanged:(id)sender { [[self captureRuntimeController] windowSelectionChanged:sender]; }

- (void)resetForSelectedWindowChange { [[self captureRuntimeController] resetForSelectedWindowChange]; }

- (void)hideInlineTranslationPanelsForGeometryChange { [[self captureRuntimeController] hideInlineTranslationPanelsForGeometryChange]; }

- (void)refreshDisplayGeometryIfNeeded:(BOOL)force { [[self captureRuntimeController] refreshDisplayGeometryIfNeeded:force]; }

- (void)updateWindowCardCopy { [[self captureRuntimeController] updateWindowCardCopy]; }

- (FYCaptureCardInput *)captureCardInput { return [[self captureRuntimeController] captureCardInput]; }

- (BOOL)captureCardInputEnabled { return [[self captureRuntimeController] captureCardInputEnabled]; }

- (void)updateCaptureCardStatus { [[self captureRuntimeController] updateCaptureCardStatus]; }

- (void)ensureCaptureCardPermissionThen:(void (^)(BOOL granted))continuation { [[self captureRuntimeController] ensureCaptureCardPermissionThen:continuation]; }

- (NSString *)captionLinesFromTranslations:(NSArray<NSString *> *)translations { return [[self captureRuntimeController] captionLinesFromTranslations:translations]; }

- (nullable NSString *)captureDeviceIDFromPopup { return [[self captureRuntimeController] captureDeviceIDFromPopup]; }

- (void)refreshCaptureDevices:(id)sender { [[self captureRuntimeController] refreshCaptureDevices:sender]; }

- (void)captureDeviceChanged:(id)sender { [[self captureRuntimeController] captureDeviceChanged:sender]; }

- (void)inputSourceChanged:(id)sender { [[self captureRuntimeController] inputSourceChanged:sender]; }

- (void)resetForInputSourceChange { [[self captureRuntimeController] resetForInputSourceChange]; }

- (BOOL)startCaptureCardSessionIfPossible { return [[self captureRuntimeController] startCaptureCardSessionIfPossible]; }

- (void)reconnectCaptureDevice:(id)sender { [[self captureRuntimeController] reconnectCaptureDevice:sender]; }

- (void)openCameraAccessSettings:(id)sender { [[self captureRuntimeController] openCameraAccessSettings:sender]; }

- (CGRect)selectedOCRScope { return [[self captureRuntimeController] selectedOCRScope]; }

- (void)selectOCRRegion:(id)sender { [[self captureRuntimeController] selectOCRRegion:sender]; }

- (void)hideInterfaceForRegionSelection { [[self captureRuntimeController] hideInterfaceForRegionSelection]; }

- (void)restoreInterfaceAfterRegionSelectionShowingOCRPreview:(BOOL)showOCRPreview { [[self captureRuntimeController] restoreInterfaceAfterRegionSelectionShowingOCRPreview:showOCRPreview]; }

- (void)showOCRPreview:(id)sender { [[self captureRuntimeController] showOCRPreview:sender]; }

- (void)hideOCRPreview:(id)sender { [[self captureRuntimeController] hideOCRPreview:sender]; }

- (void)updateOCRPreviewIfVisible { [[self captureRuntimeController] updateOCRPreviewIfVisible]; }

- (BOOL)livePreviewVisible { return [[self captureRuntimeController] livePreviewVisible]; }

- (void)refreshPreviewVisibility:(id)sender { [[self captureRuntimeController] refreshPreviewVisibility:sender]; }

- (void)windowDidChangeOcclusionState:(NSNotification *)notification { [[self captureRuntimeController] windowDidChangeOcclusionState:notification]; }

- (void)windowDidMiniaturize:(NSNotification *)notification { [[self captureRuntimeController] windowDidMiniaturize:notification]; }

- (void)windowDidDeminiaturize:(NSNotification *)notification { [[self captureRuntimeController] windowDidDeminiaturize:notification]; }

- (void)invalidatePreviewResults { [[self captureRuntimeController] invalidatePreviewResults]; }

- (void)restartPreviewTimerIfRunning { [[self captureRuntimeController] restartPreviewTimerIfRunning]; }

- (void)previewTimerFired:(NSTimer *)timer { [[self captureRuntimeController] previewTimerFired:timer]; }

- (void)applyPreviewImage:(CGImageRef)image { [[self captureRuntimeController] applyPreviewImage:image]; }

- (BOOL)hasScreenAccess { return [[self captureRuntimeController] hasScreenAccess]; }

- (BOOL)hasUsableScreenCaptureAccess { return [[self captureRuntimeController] hasUsableScreenCaptureAccess]; }

- (BOOL)canCaptureSelectedWindowOnce { return [[self captureRuntimeController] canCaptureSelectedWindowOnce]; }

- (void)handleMissingScreenAccessForStart { [[self captureRuntimeController] handleMissingScreenAccessForStart]; }

- (uint32_t)selectedWindowID { return [[self captureRuntimeController] selectedWindowID]; }

- (WindowItem *)windowItemForWindowID:(uint32_t)windowID { return [[self captureRuntimeController] windowItemForWindowID:windowID]; }

- (WindowItem *)selectedWindowItem { return [[self captureRuntimeController] selectedWindowItem]; }

- (BOOL)liveBoundsForWindowID:(uint32_t)windowID outBounds:(CGRect *)outBounds { return [[self captureRuntimeController] liveBoundsForWindowID:windowID outBounds:outBounds]; }

- (uint32_t)resolveDisplayTargetWindowIDInWindowList:(NSArray<NSDictionary *> *)windowList
                                           ambiguous:(BOOL *)outAmbiguous
                                                note:(NSString **)outNote { return [[self captureRuntimeController] resolveDisplayTargetWindowIDInWindowList:windowList ambiguous:outAmbiguous note:outNote]; }

- (uint32_t)displayTargetWindowID { return [[self captureRuntimeController] displayTargetWindowID]; }

- (WindowItem *)displayTargetWindowItem { return [[self captureRuntimeController] displayTargetWindowItem]; }

- (WindowItem *)windowItemForResolvedTargetID:(uint32_t)windowID { return [[self captureRuntimeController] windowItemForResolvedTargetID:windowID]; }

- (NSScreen *)screenForWindowItem:(WindowItem *)item { return [[self captureRuntimeController] screenForWindowItem:item]; }

- (NSRect)appKitFrameForWindowItem:(WindowItem *)item { return [[self captureRuntimeController] appKitFrameForWindowItem:item]; }

- (BOOL)buildCaptureGridsWithFrame:(double **)outTempl templateW:(size_t *)outTW templateH:(size_t *)outTH
                             scene:(double **)outScene sceneW:(size_t *)outWW sceneH:(size_t *)outWH
                       videoAspect:(CGFloat *)outAspect
                        sceneWidth:(size_t)sceneWidth
                         forWindow:(WindowItem *)window
                            reason:(NSString **)outReason { return [[self captureRuntimeController] buildCaptureGridsWithFrame:outTempl templateW:outTW templateH:outTH scene:outScene sceneW:outWW sceneH:outWH videoAspect:outAspect sceneWidth:sceneWidth forWindow:window reason:outReason]; }

- (BOOL)autoDetectCaptureCardVideoRectForWindow:(WindowItem *)window reason:(NSString **)outReason { return [[self captureRuntimeController] autoDetectCaptureCardVideoRectForWindow:window reason:outReason]; }

- (void)resetInlineLayoutCacheAfterMappingChange { [[self captureRuntimeController] resetInlineLayoutCacheAfterMappingChange]; }

- (double)captureCardMappingScoreForWindow:(WindowItem *)window entry:(NSDictionary *)entry { return [[self captureRuntimeController] captureCardMappingScoreForWindow:window entry:entry]; }

- (void)storeCaptureCardMapping:(NSRect)screenRect
                     windowFrame:(NSRect)windowFrame
                     videoAspect:(CGFloat)videoAspect
                        deviceID:(NSString *)deviceID
                          source:(NSString *)source
                      confidence:(CGFloat)confidence
                     forWindowID:(uint32_t)windowID { [[self captureRuntimeController] storeCaptureCardMapping:screenRect windowFrame:windowFrame videoAspect:videoAspect deviceID:deviceID source:source confidence:confidence forWindowID:windowID]; }

- (void)calibrateCaptureCardVideoRect:(NSRect)screenRect
                          windowFrame:(NSRect)windowFrame
                          videoAspect:(CGFloat)videoAspect
                             deviceID:(NSString *)deviceID
                          forWindowID:(uint32_t)windowID { [[self captureRuntimeController] calibrateCaptureCardVideoRect:screenRect windowFrame:windowFrame videoAspect:videoAspect deviceID:deviceID forWindowID:windowID]; }

- (void)clearCaptureCardCalibrationForWindowID:(uint32_t)windowID { [[self captureRuntimeController] clearCaptureCardCalibrationForWindowID:windowID]; }

- (BOOL)captureCardHasCalibratedVideoRectForWindow:(WindowItem *)window { return [[self captureRuntimeController] captureCardHasCalibratedVideoRectForWindow:window]; }

- (NSString *)captureCardCalibrationSummaryForWindow:(WindowItem *)window { return [[self captureRuntimeController] captureCardCalibrationSummaryForWindow:window]; }

- (BOOL)captureCardEstimatedDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect { return [[self captureRuntimeController] captureCardEstimatedDisplayRectForWindow:window outRect:outRect]; }

- (BOOL)captureCardDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect { return [[self captureRuntimeController] captureCardDisplayRectForWindow:window outRect:outRect]; }

- (BOOL)captureCardDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect reason:(NSString **)outReason { return [[self captureRuntimeController] captureCardDisplayRectForWindow:window outRect:outRect reason:outReason]; }

- (void)updateCaptureCalibrationStatus { [[self captureRuntimeController] updateCaptureCalibrationStatus]; }

- (void)beginCaptureCardCalibration:(id)sender { [[self captureRuntimeController] beginCaptureCardCalibration:sender]; }

- (void)endCaptureCardCalibration { [[self captureRuntimeController] endCaptureCardCalibration]; }

- (void)finishCaptureCardCalibration:(NSRect)screenRect
                         windowFrame:(NSRect)windowFrame
                         videoAspect:(CGFloat)videoAspect
                            deviceID:(NSString *)deviceID
                          windowID:(uint32_t)windowID { [[self captureRuntimeController] finishCaptureCardCalibration:screenRect windowFrame:windowFrame videoAspect:videoAspect deviceID:deviceID windowID:windowID]; }

- (void)clearCaptureCardCalibration:(id)sender { [[self captureRuntimeController] clearCaptureCardCalibration:sender]; }

- (NSString *)inlineTargetUnavailableReasonWithFallback:(NSString *)fallback { return [[self captureRuntimeController] inlineTargetUnavailableReasonWithFallback:fallback]; }

- (BOOL)inlinePlacementRect:(NSRect *)outRect reason:(NSString **)outReason { return [[self captureRuntimeController] inlinePlacementRect:outRect reason:outReason]; }

- (void)showInlineMappingUnavailableNotice:(NSString *)reason { [[self captureRuntimeController] showInlineMappingUnavailableNotice:reason]; }

- (CGRect)quartzRectFromSelectionRect:(CGRect)selectionRect panelFrame:(NSRect)panelFrame { return [[self captureRuntimeController] quartzRectFromSelectionRect:selectionRect panelFrame:panelFrame]; }

- (NSRect)appKitOCRPreviewFrameForWindowItem:(WindowItem *)item { return [[self captureRuntimeController] appKitOCRPreviewFrameForWindowItem:item]; }

- (BOOL)updateOCRPreviewPanel { return [[self captureRuntimeController] updateOCRPreviewPanel]; }

- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)windowID { return [[self captureRuntimeController] copyFullCapturedImageForWindow:windowID]; }

- (CGImageRef)copyCapturedImageForWindow:(uint32_t)windowID regionX:(double)x regionY:(double)y regionWidth:(double)width regionHeight:(double)height { return [[self captureRuntimeController] copyCapturedImageForWindow:windowID regionX:x regionY:y regionWidth:width regionHeight:height]; }

- (NSString *)recognizeEnlargedRegionOfImage:(CGImageRef)image
                                    regionX:(double)x
                                    regionY:(double)y
                                regionWidth:(double)width
                               regionHeight:(double)height
                                     fastOCR:(BOOL)fastOCR
                             languageSegment:(NSInteger)languageSegment
                                      blocks:(NSArray<OCRTextItem *> **)outBlocks
                                       error:(NSError **)error { return [[self captureRuntimeController] recognizeEnlargedRegionOfImage:image regionX:x regionY:y regionWidth:width regionHeight:height fastOCR:fastOCR languageSegment:languageSegment blocks:outBlocks error:error]; }

- (NSString *)recognizeTextBlocksInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment blocks:(NSArray<OCRTextItem *> **)outBlocks error:(NSError **)error { return [[self captureRuntimeController] recognizeTextBlocksInImage:image fastOCR:fastOCR languageSegment:languageSegment blocks:outBlocks error:error]; }

- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment error:(NSError **)error { return [[self captureRuntimeController] recognizeTextItemsInImage:image fastOCR:fastOCR languageSegment:languageSegment error:error]; }

- (FYAutoLocateSchedule *)locateSchedule { return [[self captureRuntimeController] locateSchedule]; }

- (NSDate *)lastAutoLocateAttempt { return [[self captureRuntimeController] lastAutoLocateAttempt]; }

- (void)setLastAutoLocateAttempt:(NSDate *)value { [[self captureRuntimeController] setLastAutoLocateAttempt:value]; }

- (FYCaptureMappingCache *)mappingCache { return [[self captureRuntimeController] mappingCache]; }

- (NSMutableDictionary *)captureCardVideoRects { return [[self captureRuntimeController] captureCardVideoRects]; }

- (void)setCaptureCardVideoRects:(NSMutableDictionary<NSString *, NSDictionary *> *)value { [[self captureRuntimeController] setCaptureCardVideoRects:value]; }

- (FYMappingValidationSchedule *)validationSchedule { return [[self captureRuntimeController] validationSchedule]; }

- (NSDate *)lastMappingValidationDate { return [[self captureRuntimeController] lastMappingValidationDate]; }

- (void)setLastMappingValidationDate:(NSDate *)value { [[self captureRuntimeController] setLastMappingValidationDate:value]; }

- (void)showPreviewUnavailable:(NSString *)message { [[self captureRuntimeController] showPreviewUnavailable:message]; }

- (void)updatePreviewFromImage:(CGImageRef)image generation:(NSInteger)generation { [[self captureRuntimeController] updatePreviewFromImage:image generation:generation]; }

- (void)clampRegionSliders { [[self captureRuntimeController] clampRegionSliders]; }

- (void)captureLatestStudySentenceWithCompletion:(void (^)(NSString *,NSError *))completion { [[self captureRuntimeController] captureLatestStudySentenceWithCompletion:completion]; }
@end
