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
@protocol FYRealtimeRequestHost <NSObject>
@property(nonatomic, copy) NSArray<OCRTextItem *> *contentTranslationUIItems;
@property(nonatomic) NSUInteger inlineTranslationSerial;
@property(nonatomic, strong) FYLearningCoordinator *learningCoordinator;
- (void)setCaptionPanelVisibleForUIMode:(BOOL)uiMode;
- (void)clearInlineTranslationPanels;
- (void)refreshLearningSource;
- (void)refreshLearningStatus;
- (NSArray<NSString *> *)textsFromItems:(NSArray<OCRTextItem *> *)items;
- (NSUInteger)beginContentTranslation:(NSString *)text mode:(NSInteger)mode;
- (NSUInteger)beginInlineContentTranslation:(NSString *)text items:(NSArray<OCRTextItem *> *)items trace:(NSDictionary *)trace;
- (void)finishContentTranslation:(NSUInteger)revision;
- (BOOL)captureCardInputEnabled;
- (void)translateInlineTextItems:(NSArray<OCRTextItem *> *)items completion:(void (^)(NSArray<NSString *> *translations, NSError *error))completion;
- (BOOL)inlinePlacementRect:(NSRect *)outRect reason:(NSString **)outReason;
- (void)translateDialogueText:(NSString *)text
                     identity:(FYRequestIdentity *)identity
                 systemPrompt:(NSString *)systemPrompt
                   completion:(void (^)(NSString *translated, NSError *error))completion;
- (NSString *)systemPrompt;
- (NSInteger)effectiveModeSegment;
- (void)setStatus:(NSString *)status;
@end
#pragma clang diagnostic pop
