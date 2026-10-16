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
@protocol FYRealtimeResultHost <NSObject>
@property(nonatomic, strong) NSPanel *captionPanel;
@property(nonatomic, strong) FYCaptureCardInput *captureCardInput;
@property(nonatomic) NSUInteger contentTranslationRevision;
@property(nonatomic, copy) NSArray<OCRTextItem *> *contentTranslationUIItems;
@property(nonatomic) NSUInteger inlineTranslationSerial;
@property(nonatomic) NSUInteger lastInlineCompactEntryCount;
@property(nonatomic, strong) FYInlineLayoutResult *lastInlineLayoutResult;
@property(nonatomic) NSUInteger lastInlineUnplaceableCount;
@property(nonatomic, copy) NSString *lastSubmittedNormalizedText;
@property(nonatomic, copy) NSString *lastTranslatedNormalizedText;
@property(nonatomic, strong) NSTextField *latestSourceLabel;
@property(nonatomic, strong) NSTextField *latestTranslationLabel;
@property(nonatomic, strong) FYLearningCoordinator *learningCoordinator;
@property(nonatomic) uint32_t ocrDisplayTargetWindowID;
@property(nonatomic) NSInteger ocrGeometryGeneration;
@property(nonatomic) NSInteger translationCount;
@property(nonatomic, strong) NSTextField *translationDurationLabel;
@property(nonatomic) NSInteger translationGeneration;
- (void)setCaptionPanelVisibleForUIMode:(BOOL)uiMode;
- (void)updateCaptionWindowWithText:(NSString *)text status:(NSString *)status;
- (void)clearInlineTranslationPanels;
- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items;
- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items placementRect:(NSRect)windowFrame;
- (void)refreshInlineTranslationList;
- (void)refreshLearningSource;
- (void)refreshLearningStatus;
- (void)bindTranslations:(NSArray<NSString *> *)translations toIdentities:(NSArray<FYRequestIdentity *> *)identities;
- (void)finishContentTranslation:(NSUInteger)revision;
- (void)handleInlineTranslationResult:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items error:(NSError *)translationError failureStatus:(NSString *)failureStatus successPrefix:(NSString *)successPrefix;
- (BOOL)inlinePlacementRect:(NSRect *)outRect reason:(NSString **)outReason;
- (void)showInlineMappingUnavailableNotice:(NSString *)reason;
- (NSInteger)effectiveModeSegment;
- (NSString *)displayableTranslation:(NSString *)translated sourceText:(NSString *)sourceText;
- (void)setStatus:(NSString *)status;
- (void)updateTranslationCount;
- (void)showError:(NSString *)error;
@end
#pragma clang diagnostic pop
