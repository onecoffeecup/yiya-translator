#pragma once
#import <Cocoa/Cocoa.h>
#import "../FYCaptureCardInput.h"
#import "../FYContentRouter.h"
#import "../FYTranslationManager.h"
#import "../FYInlineLayout.h"
#import "../learning/FYLearningCoordinator.h"
#import "../ocr/FYOCRRecognitionWorker.h"
#import "FYContentTranslationState.h"
#import "FYRecognitionCycleScheduler.h"
#import "FYRuntimeDeliveryChecks.h"
#import "FYRealtimeRecognitionFrame.h"
#import "FYPreparedRealtimeContent.h"
@class FYInlineOCRFrameStabilizer;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

// Ephemeral original host receiver; this contract stores no state.
@protocol FYRealtimeContentAdmissionHost <NSObject>
@property(nonatomic) uint32_t contentTranslationDisplayTarget;
@property(nonatomic) NSInteger contentTranslationGeometryGeneration;
@property(nonatomic) NSUInteger contentTranslationOperations;
@property(nonatomic, copy) NSArray<OCRTextItem *> *contentTranslationUIItems;
@property(nonatomic) NSInteger detectedModeSegment;
@property(nonatomic) NSInteger inlineOCRPendingCount;
@property(nonatomic, copy) NSString *inlineOCRPendingText;
@property(nonatomic) NSInteger inlinePendingGroupedCount;
@property(nonatomic, copy) NSArray<NSString *> *inlinePendingGroupedTexts;
@property(nonatomic, copy) NSString *lastDisplayGeometryToken;
@property(nonatomic) NSRect lastInlineLayoutDebugViewport;
@property(nonatomic, strong) FYInlineLayoutResult *lastInlineLayoutResult;
@property(nonatomic, copy) NSString *lastInlineRenderGeometryToken;
@property(nonatomic, copy) NSArray<OCRTextItem *> *lastInlineRenderedItems;
@property(nonatomic, copy) NSString *lastSubmittedNormalizedText;
@property(nonatomic, copy) NSString *lastTranslatedNormalizedText;
@property(nonatomic) uint32_t ocrDisplayTargetWindowID;
@property(nonatomic) NSInteger ocrGeometryGeneration;
@property(nonatomic) NSInteger stableCandidateCount;
@property(nonatomic, strong) NSButton *stableTextCheckbox;
- (void)recordInlineLayoutDebug:(FYInlineLayoutResult *)result previous:(FYInlineLayoutResult *)previous viewport:(NSRect)viewport reason:(NSString *)reason;
- (void)advanceExpandedReadingState;
- (BOOL)pendingContentMatchesText:(NSString *)text mode:(NSInteger)mode;
- (BOOL)pendingInlineMatchesItems:(NSArray<OCRTextItem *> *)items;
- (NSTimeInterval)translationAttemptThrottleForMode:(NSInteger)modeSegment;
- (FYTranslationRunState *)translationState;
- (NSDate *)translationProcessingDate;
- (FYOCRStabilityOwner *)stabilityOwner;
- (BOOL)isStableText:(NSString *)normalized;
- (BOOL)isSameSubtitleText:(NSString *)text comparedTo:(NSString *)previous;
- (void)setStatus:(NSString *)status;
@end
#pragma clang diagnostic pop
