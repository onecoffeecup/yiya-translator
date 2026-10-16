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
@protocol FYRealtimeContentPreparationHost <NSObject>
@property(nonatomic) NSInteger candidateModeHits;
@property(nonatomic) NSInteger candidateModeSegment;
@property(nonatomic) NSInteger detectedModeSegment;
@property(nonatomic, strong) NSPanel *inlineExpandedReadingPanel;
@property(nonatomic, strong) FYInlineOCRFrameStabilizer *inlineFrameStabilizer;
@property(nonatomic, strong) NSPanel *inlineOverflowChoicePanel;
@property(nonatomic, copy) NSString *lastSubmittedNormalizedText;
@property(nonatomic, copy) NSString *lastTranslatedNormalizedText;
@property(nonatomic, strong) NSTextField *latestSourceLabel;
@property(nonatomic, strong) NSTextField *latestTranslationLabel;
@property(nonatomic, strong) NSTimer *timer;
- (void)clearInlineTranslationPanels;
- (void)invalidateContentTranslation;
- (NSArray<OCRTextItem *> *)mergedInlineTextItemsFromItems:(NSArray<OCRTextItem *> *)items;
- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items;
- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items strict:(BOOL)strict;
- (NSInteger)effectiveModeSegment;
- (NSInteger)stableContentModeForBlocks:(NSArray<OCRTextItem *> *)blocks;
- (void)restartTimerIfRunning;
- (FYOCRStabilityOwner *)stabilityOwner;
- (void)setStatus:(NSString *)status;
@end
#pragma clang diagnostic pop
