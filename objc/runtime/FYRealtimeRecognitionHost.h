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
@protocol FYRealtimeRecognitionHost <NSObject>
@property(nonatomic, strong) NSButton *autoFitRegionCheckbox;
@property(nonatomic, strong) FYCaptureCardInput *captureCardInput;
@property(nonatomic, strong) dispatch_queue_t captureQueue;
@property(nonatomic) BOOL captureUnavailable;
@property(nonatomic) NSInteger geometryGeneration;
@property(nonatomic) BOOL inFlight;
@property(nonatomic, strong) NSSegmentedControl *languageControl;
@property(nonatomic, strong) NSDate *lastDiagnosticCheckDate;
@property(nonatomic) uint64_t lastOCRedCaptureFrameIndex;
@property(nonatomic, strong) FYLearningCoordinator *learningCoordinator;
@property(nonatomic) uint32_t ocrDisplayTargetWindowID;
@property(nonatomic, strong) NSTextField *ocrDurationLabel;
@property(nonatomic) NSInteger ocrGeometryGeneration;
@property(nonatomic, copy) NSDictionary *ocrRefinementContext;
@property(nonatomic, strong) FYOCRRefinementStabilizer *ocrRefinementStabilizer;
@property(nonatomic) BOOL running;
@property(nonatomic) NSInteger translationGeneration;
- (BOOL)recoverWindowSelectionIfRecreated;
- (void)hideInlineTranslationPanelsForGeometryChange;
- (void)refreshDisplayGeometryIfNeeded:(BOOL)force;
- (BOOL)captureCardInputEnabled;
- (void)updateCaptureCardStatus;
- (CGRect)selectedOCRScope;
- (uint32_t)displayTargetWindowID;
- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)windowID;
- (void)setStatus:(NSString *)status;
- (void)updateRunState;
- (void)showPreviewUnavailable:(NSString *)message;
- (void)updatePreviewFromImage:(CGImageRef)image generation:(NSInteger)generation;
- (void)showError:(NSString *)error;
- (NSArray<NSDictionary *> *)updateRuntimeDiagnostics;
@end
#pragma clang diagnostic pop
