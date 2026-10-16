#pragma once
#import "../app/FYAppSupport.h"
#import "FYContentTranslationState.h"
#import "FYRecognitionCycleScheduler.h"
#import "../ocr/FYOCRRefinementSession.h"
#import "../ocr/FYOCRRecognitionWorker.h"
#import "FYRuntimeDeliveryChecks.h"
#import "FYInlineTranslationCoordinator.h"
#import "FYTranslationRequestCoordinator.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

// Original application receiver, constrained to the runtime context and peer actions.
@protocol FYTranslationRuntimeControllerHost <NSObject, FYRecognitionTimerTarget>
#ifdef FY_TEST_ISOLATED_CREDENTIAL_STORE
@property(nonatomic, strong) NSButton *autoFitRegionCheckbox;
#endif
@property(nonatomic, strong) NSTextField *baseURLField;
@property(nonatomic) NSInteger candidateModeHits;
@property(nonatomic) NSInteger candidateModeSegment;
@property(nonatomic, strong) NSPanel *captionPanel;
@property(nonatomic, strong) FYCaptureCardInput *captureCardInput;
@property(nonatomic, strong) dispatch_queue_t captureQueue;
@property(nonatomic) BOOL captureUnavailable;
@property(nonatomic, strong) FYContentRouter *contentRouter;
@property(nonatomic) uint32_t contentTranslationDisplayTarget;
@property(nonatomic) NSInteger contentTranslationGeometryGeneration;
@property(nonatomic) NSInteger contentTranslationMode;
@property(nonatomic) NSUInteger contentTranslationOperations;
@property(nonatomic) NSUInteger contentTranslationRevision;
@property(nonatomic, copy) NSString *contentTranslationText;
@property(nonatomic, copy) NSArray<OCRTextItem *> *contentTranslationUIItems;
@property(nonatomic) NSInteger detectedModeSegment;
@property(nonatomic, strong) FYTranslationCache *dialogueTranslationCache;
@property(nonatomic) NSInteger geometryGeneration;
@property(nonatomic) BOOL inFlight;
@property(nonatomic, strong) NSPanel *inlineExpandedReadingPanel;
@property(nonatomic, strong) FYInlineOCRFrameStabilizer *inlineFrameStabilizer;
@property(nonatomic, strong) FYInlineGrouper *inlineGrouper;
@property(nonatomic) NSInteger inlineOCRPendingCount;
@property(nonatomic, copy) NSString *inlineOCRPendingText;
@property(nonatomic, strong) NSPanel *inlineOverflowChoicePanel;
@property(nonatomic) NSInteger inlinePendingGroupedCount;
@property(nonatomic, copy) NSArray<NSString *> *inlinePendingGroupedTexts;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *inlineTranslationCache;
@property(nonatomic) NSUInteger inlineTranslationSerial;
@property(nonatomic, strong) NSSegmentedControl *languageControl;
@property(nonatomic, strong) NSDate *lastDiagnosticCheckDate;
@property(nonatomic, copy) NSString *lastDisplayGeometryToken;
@property(nonatomic) NSUInteger lastInlineCompactEntryCount;
@property(nonatomic) NSRect lastInlineLayoutDebugViewport;
@property(nonatomic, strong) FYInlineLayoutResult *lastInlineLayoutResult;
@property(nonatomic, copy) NSString *lastInlineRenderGeometryToken;
@property(nonatomic, copy) NSArray<OCRTextItem *> *lastInlineRenderedItems;
@property(nonatomic, copy) NSString *lastInlineTranslationKey;
@property(nonatomic) NSUInteger lastInlineUnplaceableCount;
@property(nonatomic) uint64_t lastOCRedCaptureFrameIndex;
@property(nonatomic) uint64_t lastPreviewCaptureFrameIndex;
@property(nonatomic, copy) NSString *lastSubmittedNormalizedText;
@property(nonatomic, copy) NSString *lastTranslatedNormalizedText;
@property(nonatomic, strong) NSDate *lastTranslationAttemptDate;
@property(nonatomic, strong) NSTextField *latestSourceLabel;
@property(nonatomic, strong) NSTextField *latestTranslationLabel;
@property(nonatomic, strong) FYLearningCoordinator *learningCoordinator;
@property(nonatomic) uint32_t ocrDisplayTargetWindowID;
@property(nonatomic, strong) NSTextField *ocrDurationLabel;
@property(nonatomic) NSInteger ocrGeometryGeneration;
@property(nonatomic, copy) NSDictionary *ocrRefinementContext;
@property(nonatomic, strong) FYOCRRefinementStabilizer *ocrRefinementStabilizer;
@property(nonatomic, strong) FYInlinePendingLongBatch *pendingInlineLongBatch;
@property(nonatomic) NSUInteger previewRenderSerial;
@property(nonatomic) NSUInteger previewRequestSerial;
@property(nonatomic, strong) NSTimer *previewTimer;
@property(nonatomic, strong) NSButton *runButton;
@property(nonatomic) BOOL running;
@property(nonatomic) NSInteger serviceTestGeneration;
@property(nonatomic, strong) FYTranslationTaskOwner *serviceTestTaskOwner;
@property(nonatomic) NSInteger stableCandidateCount;
#ifdef FY_TEST_ISOLATED_CREDENTIAL_STORE
@property(nonatomic, strong) NSButton *stableTextCheckbox;
#endif
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) NSInteger translationCount;
@property(nonatomic, strong) NSTextField *translationDurationLabel;
@property(nonatomic) NSInteger translationGeneration;
@property(nonatomic, strong) FYTranslationTaskOwner *translationTaskOwner;
- (void)setCaptionPanelVisibleForUIMode:(BOOL)uiMode;
- (void)updateCaptionWindowWithText:(NSString *)text status:(NSString *)status;
- (void)clearInlineTranslationPanels;
- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items;
- (void)recordInlineLayoutDebug:(FYInlineLayoutResult *)result previous:(FYInlineLayoutResult *)previous viewport:(NSRect)viewport reason:(NSString *)reason;
- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items placementRect:(NSRect)windowFrame;
- (NSString *)inlineBlockIdentityForItem:(OCRTextItem *)item;
- (void)advanceExpandedReadingState;
- (void)refreshInlineTranslationList;
- (void)refreshLearningSource;
- (void)refreshLearningStatus;
- (FYTranslationConfiguration *)translationConfiguration;
- (NSArray<NSString *> *)textsFromItems:(NSArray<OCRTextItem *> *)items;
- (void)bindTranslations:(NSArray<NSString *> *)translations toIdentities:(NSArray<FYRequestIdentity *> *)identities;
- (void)invalidateContentTranslation;
- (BOOL)pendingContentMatchesText:(NSString *)text mode:(NSInteger)mode;
- (BOOL)pendingInlineMatchesItems:(NSArray<OCRTextItem *> *)items;
- (NSUInteger)beginContentTranslation:(NSString *)text mode:(NSInteger)mode;
- (NSArray<NSString *> *)longInlineKeysForItems:(NSArray<OCRTextItem *> *)items;
- (NSUInteger)beginInlineContentTranslation:(NSString *)text items:(NSArray<OCRTextItem *> *)items trace:(NSDictionary *)trace;
- (void)finishContentTranslation:(NSUInteger)revision;
- (void)advanceTranslationGeneration;
- (void)start;
- (void)stop;
- (void)handleInlineTranslationResult:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items error:(NSError *)translationError failureStatus:(NSString *)failureStatus successPrefix:(NSString *)successPrefix;
- (pid_t)selectedWindowOwnerPID;
- (void)timerFired:(NSTimer *)timer;
- (BOOL)recoverWindowSelectionIfRecreated;
- (void)hideInlineTranslationPanelsForGeometryChange;
- (void)refreshDisplayGeometryIfNeeded:(BOOL)force;
- (BOOL)captureCardInputEnabled;
- (void)updateCaptureCardStatus;
- (void)ensureCaptureCardPermissionThen:(void (^)(BOOL granted))continuation;
- (BOOL)startCaptureCardSessionIfPossible;
- (CGRect)selectedOCRScope;
- (void)translateCurrentInterface:(id)sender;
- (NSArray<OCRTextItem *> *)mergedInlineTextItemsFromItems:(NSArray<OCRTextItem *> *)items;
- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items;
- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items strict:(BOOL)strict;
- (BOOL)shouldIgnoreInlineText:(NSString *)text normalized:(NSString *)normalized boundingBox:(CGRect)box strict:(BOOL)strict;
- (BOOL)isButtonLikeInlineText:(NSString *)normalized;
- (NSString *)inlineTranslationCacheKeyForItem:(OCRTextItem *)item;
- (void)translateInlineTextItems:(NSArray<OCRTextItem *> *)items completion:(void (^)(NSArray<NSString *> *translations, NSError *error))completion;
- (void)translateInlineLongItems:(NSArray<OCRTextItem *> *)items indexes:(NSArray<NSNumber *> *)indexes
    keys:(NSArray<NSString *> *)keys translations:(NSMutableArray<NSString *> *)translations
    completion:(void (^)(NSError *))completion;
- (void)translateInlineBatch:(NSArray<OCRTextItem *> *)items
                     indexes:(NSArray<NSNumber *> *)indexes
                        keys:(NSArray<NSString *> *)keys
                translations:(NSMutableArray<NSString *> *)translations
                        long:(BOOL)isLong
                  completion:(void (^)(NSError *error))completion;
- (void)cacheInlineTranslation:(NSString *)value forKey:(NSString *)key;
- (NSArray<NSString *> *)parseNumberedTranslations:(NSString *)text expectedCount:(NSUInteger)count;
- (void)invalidatePreviewResults;
- (void)restartPreviewTimerIfRunning;
- (BOOL)hasScreenAccess;
- (BOOL)hasUsableScreenCaptureAccess;
- (void)handleMissingScreenAccessForStart;
- (uint32_t)selectedWindowID;
- (WindowItem *)selectedWindowItem;
- (uint32_t)displayTargetWindowID;
- (BOOL)inlinePlacementRect:(NSRect *)outRect reason:(NSString **)outReason;
- (void)showInlineMappingUnavailableNotice:(NSString *)reason;
- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)windowID;
- (NSString *)recognizeEnlargedRegionOfImage:(CGImageRef)image
                                    regionX:(double)x
                                    regionY:(double)y
                                regionWidth:(double)width
                               regionHeight:(double)height
                                     fastOCR:(BOOL)fastOCR
                             languageSegment:(NSInteger)languageSegment
                                      blocks:(NSArray<OCRTextItem *> **)outBlocks
                                       error:(NSError **)error;
- (NSString *)recognizeTextBlocksInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment blocks:(NSArray<OCRTextItem *> **)outBlocks error:(NSError **)error;
- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment error:(NSError **)error;
- (void)translateText:(NSString *)text completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateText:(NSString *)text systemPrompt:(NSString *)systemPrompt maxTokens:(NSInteger)maxTokens completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateDialogueText:(NSString *)text
                     identity:(FYRequestIdentity *)identity
                 systemPrompt:(NSString *)systemPrompt
                   completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateTextRealtime:(NSString *)text
                 systemPrompt:(NSString *)systemPrompt
                    maxTokens:(NSInteger)maxTokens
                   completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateText:(NSString *)text
          systemPrompt:(NSString *)systemPrompt
             maxTokens:(NSInteger)maxTokens
         modelOverride:(NSString *)modelOverride
            completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateText:(NSString *)text systemPrompt:(NSString *)systemPrompt maxTokens:(NSInteger)maxTokens
        modelOverride:(NSString *)modelOverride longText:(BOOL)longText serviceTest:(BOOL)serviceTest
        completion:(void (^)(NSString *, NSError *))completion;
- (NSString *)systemPrompt;
- (NSTimeInterval)translationAttemptThrottleForMode:(NSInteger)modeSegment;
- (NSArray<OCRTextItem *> *)blocksInsideModalIfPresent:(NSArray<OCRTextItem *> *)blocks
                                              inImage:(CGImageRef)image
                                    normalizedExclusions:(NSArray<NSValue *> *)exclusionValues;
- (NSInteger)effectiveModeSegment;
- (NSInteger)stableContentModeForBlocks:(NSArray<OCRTextItem *> *)blocks;
- (NSString *)systemPromptForMode:(NSInteger)modeSegment;
- (FYInlineTranslationCache *)inlineCache;
- (FYContentModeStability *)modeStability;
- (FYTranslationRunState *)translationState;
- (NSDate *)translationProcessingDate;
- (NSTimeInterval)recognitionPollingInterval;
- (void)restartTimerIfRunning;
- (FYOCRStabilityOwner *)stabilityOwner;
- (BOOL)isStableText:(NSString *)normalized;
- (BOOL)isSameSubtitleText:(NSString *)text comparedTo:(NSString *)previous;
- (NSString *)displayableTranslation:(NSString *)translated sourceText:(NSString *)sourceText;
- (void)setStatus:(NSString *)status;
- (void)updateRunState;
- (void)updateTranslationCount;
- (void)showPreviewUnavailable:(NSString *)message;
- (void)updatePreviewFromImage:(CGImageRef)image generation:(NSInteger)generation;
- (void)showError:(NSString *)error;
- (NSArray<NSDictionary *> *)updateRuntimeDiagnostics;
@end

// Owns translation runtime state; no devices, timers or requests start during construction.
@interface FYTranslationRuntimeController : NSObject <FYInlinePlacementDeliverySource>
@property(nonatomic, strong, readonly) FYRecognitionCycleScheduler *recognitionScheduler;
@property(nonatomic, strong, readonly) FYOCRRefinementSession *refinementSession;
@property(nonatomic, strong, readonly) FYOCRRecognitionWorker *ocrWorker;
@property(nonatomic) uint64_t lastOCRedCaptureFrameIndex;
@property(nonatomic, strong, readonly) FYContentTranslationState *contentState;
@property(nonatomic, strong, readonly) FYInlineTranslationCoordinator *inlineCoordinator;
@property(nonatomic, strong, readonly) FYTranslationRequestCoordinator *requestCoordinator;
@property(nonatomic, weak) id<FYTranslationRuntimeControllerHost> host;
- (instancetype)initWithHost:(id<FYTranslationRuntimeControllerHost>)host;
@property(nonatomic, strong) NSURLSessionDataTask *activeTranslationTask;
@property(nonatomic) NSInteger candidateModeHits;
@property(nonatomic) NSInteger candidateModeSegment;
@property(nonatomic, strong) FYContentRouter *contentRouter;
@property(nonatomic) uint32_t contentTranslationDisplayTarget;
@property(nonatomic) NSInteger contentTranslationGeometryGeneration;
@property(nonatomic) NSInteger contentTranslationMode;
@property(nonatomic) NSUInteger contentTranslationOperations;
@property(nonatomic) NSUInteger contentTranslationRevision;
@property(nonatomic, copy) NSString *contentTranslationText;
@property(nonatomic, copy) NSArray<OCRTextItem *> *contentTranslationUIItems;
@property(nonatomic) NSInteger detectedModeSegment;
@property(nonatomic, strong) FYTranslationCache *dialogueTranslationCache;
@property(nonatomic) BOOL inFlight;
@property(nonatomic, strong) FYInlineTranslationCache *inlineCacheOwner;
@property(nonatomic, strong) FYInlineOCRFrameStabilizer *inlineFrameStabilizer;
@property(nonatomic, strong) FYInlineGrouper *inlineGrouper;
@property(nonatomic) NSInteger inlineOCRPendingCount;
@property(nonatomic, copy) NSString *inlineOCRPendingText;
@property(nonatomic) NSInteger inlinePendingGroupedCount;
@property(nonatomic, copy) NSArray<NSString *> *inlinePendingGroupedTexts;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *inlineTranslationCache;
@property(nonatomic) NSUInteger inlineTranslationSerial;
@property(nonatomic, copy) NSString *lastSubmittedNormalizedText;
@property(nonatomic, copy) NSString *lastTranslatedNormalizedText;
@property(nonatomic, strong) NSDate *lastTranslationAttemptDate;
@property(nonatomic) uint32_t ocrDisplayTargetWindowID;
@property(nonatomic) NSInteger ocrGeometryGeneration;
@property(nonatomic, copy) NSDictionary *ocrRefinementContext;
@property(nonatomic, strong) FYOCRRefinementStabilizer *ocrRefinementStabilizer;
@property(nonatomic, strong) FYOCRStabilityOwner *ocrStabilityOwner;
@property(nonatomic, strong) FYInlinePendingLongBatch *pendingInlineLongBatch;
@property(nonatomic) BOOL running;
@property(nonatomic, copy) NSString *stableCandidate;
@property(nonatomic) NSInteger stableCandidateCount;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) NSInteger translationCount;
@property(nonatomic) NSInteger translationGeneration;
@property(nonatomic, strong) FYTranslationRunState *translationRunState;
@property(nonatomic, strong) FYTranslationTaskOwner *translationTaskOwner;
- (NSURLSessionDataTask *)activeTranslationTask;
- (void)setActiveTranslationTask:(NSURLSessionDataTask *)task;
- (void)invalidateContentTranslation;
- (BOOL)pendingContentMatchesText:(NSString *)text mode:(NSInteger)mode;
- (BOOL)pendingInlineMatchesItems:(NSArray<OCRTextItem *> *)items;
- (NSUInteger)beginContentTranslation:(NSString *)text mode:(NSInteger)mode;
- (NSArray<NSString *> *)longInlineKeysForItems:(NSArray<OCRTextItem *> *)items;
- (NSUInteger)beginInlineContentTranslation:(NSString *)text items:(NSArray<OCRTextItem *> *)items trace:(NSDictionary *)trace;
- (void)finishContentTranslation:(NSUInteger)revision;
- (void)advanceTranslationGeneration;
- (void)toggleRunning:(id)sender;
- (void)start;
- (void)stop;
- (void)handleInlineTranslationResult:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items error:(NSError *)translationError failureStatus:(NSString *)failureStatus successPrefix:(NSString *)successPrefix;
- (void)timerFired:(NSTimer *)timer;
- (void)translateCurrentInterface:(id)sender;
- (NSArray<OCRTextItem *> *)mergedInlineTextItemsFromItems:(NSArray<OCRTextItem *> *)items;
- (FYInlineTextBlock *)inlineLayoutBlockForItem:(OCRTextItem *)item order:(NSInteger)order;
- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items;
- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items strict:(BOOL)strict;
- (NSString *)dialogueTextFromItems:(NSArray<OCRTextItem *> *)items speakerLabelOnly:(BOOL *)speakerLabelOnly;
- (BOOL)shouldIgnoreInlineText:(NSString *)text normalized:(NSString *)normalized boundingBox:(CGRect)box strict:(BOOL)strict;
- (BOOL)isButtonLikeInlineText:(NSString *)normalized;
- (double)inlinePriorityForText:(NSString *)text normalized:(NSString *)normalized boundingBox:(CGRect)box;
- (NSString *)inlineTranslationCacheKeyForItem:(OCRTextItem *)item;
- (void)translateInlineTextItems:(NSArray<OCRTextItem *> *)items completion:(void (^)(NSArray<NSString *> *translations, NSError *error))completion;
- (void)translateInlineLongItems:(NSArray<OCRTextItem *> *)items indexes:(NSArray<NSNumber *> *)indexes
    keys:(NSArray<NSString *> *)keys translations:(NSMutableArray<NSString *> *)translations
    completion:(void (^)(NSError *))completion;
- (void)translateInlineBatch:(NSArray<OCRTextItem *> *)items
                     indexes:(NSArray<NSNumber *> *)indexes
                        keys:(NSArray<NSString *> *)keys
                translations:(NSMutableArray<NSString *> *)translations
                        long:(BOOL)isLong
                  completion:(void (^)(NSError *error))completion;
- (void)cacheInlineTranslation:(NSString *)value forKey:(NSString *)key;
- (NSArray<NSString *> *)parseNumberedTranslations:(NSString *)text expectedCount:(NSUInteger)count;
- (FYInlineOCRFrameStabilizer *)inlineFrameStabilizer;
- (FYInlineGrouper *)inlineGrouper;
- (void)translateText:(NSString *)text completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateText:(NSString *)text systemPrompt:(NSString *)systemPrompt maxTokens:(NSInteger)maxTokens completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateDialogueText:(NSString *)text
                     identity:(FYRequestIdentity *)identity
                 systemPrompt:(NSString *)systemPrompt
                   completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateTextRealtime:(NSString *)text
                 systemPrompt:(NSString *)systemPrompt
                    maxTokens:(NSInteger)maxTokens
                   completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateText:(NSString *)text
          systemPrompt:(NSString *)systemPrompt
             maxTokens:(NSInteger)maxTokens
         modelOverride:(NSString *)modelOverride
            completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateText:(NSString *)text systemPrompt:(NSString *)systemPrompt maxTokens:(NSInteger)maxTokens
        modelOverride:(NSString *)modelOverride longText:(BOOL)longText serviceTest:(BOOL)serviceTest
        completion:(void (^)(NSString *, NSError *))completion;
- (NSURL *)chatCompletionsURL;
- (NSString *)systemPrompt;
- (BOOL)autoContentModeEnabled;
- (NSTimeInterval)translationAttemptThrottleForMode:(NSInteger)modeSegment;
- (NSArray<OCRTextItem *> *)blocksInsideModalIfPresent:(NSArray<OCRTextItem *> *)blocks
                                              inImage:(CGImageRef)image
                                    normalizedExclusions:(NSArray<NSValue *> *)exclusionValues;
- (NSInteger)effectiveModeSegment;
- (NSInteger)stableContentModeForBlocks:(NSArray<OCRTextItem *> *)blocks;
- (NSString *)systemPromptForMode:(NSInteger)modeSegment;
- (FYInlineTranslationCache *)inlineCache;
- (NSMutableDictionary *)inlineTranslationCache;
- (void)setInlineTranslationCache:(NSMutableDictionary<NSString *, NSString *> *)value;
- (FYContentRouter *)contentRouter;
- (FYContentModeStability *)modeStability;
- (NSInteger)detectedModeSegment;
- (void)setDetectedModeSegment:(NSInteger)value;
- (NSInteger)candidateModeSegment;
- (void)setCandidateModeSegment:(NSInteger)value;
- (NSInteger)candidateModeHits;
- (void)setCandidateModeHits:(NSInteger)value;
- (FYTranslationRunState *)translationState;
- (NSDate *)translationProcessingDate;
- (NSString *)lastTranslatedNormalizedText;
- (void)setLastTranslatedNormalizedText:(NSString *)value;
- (NSString *)lastSubmittedNormalizedText;
- (void)setLastSubmittedNormalizedText:(NSString *)value;
- (NSDate *)lastTranslationAttemptDate;
- (void)setLastTranslationAttemptDate:(NSDate *)value;
- (NSTimeInterval)recognitionPollingInterval;
- (void)restartTimerIfRunning;
- (FYOCRStabilityOwner *)stabilityOwner;
- (NSString *)stableCandidate;
- (void)setStableCandidate:(NSString *)value;
- (NSInteger)stableCandidateCount;
- (void)setStableCandidateCount:(NSInteger)value;
- (BOOL)isStableText:(NSString *)normalized;
- (BOOL)shouldAcceptInlineOCRCorrection:(NSString *)text comparedTo:(NSString *)rendered;
- (BOOL)isSameSubtitleText:(NSString *)text comparedTo:(NSString *)previous;
- (NSString *)displayableTranslation:(NSString *)translated sourceText:(NSString *)sourceText;
@end
#pragma clang diagnostic pop
