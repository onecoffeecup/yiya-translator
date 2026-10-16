#import "../capture/FYDisplayTargetTracker.h"
#pragma once
#import "../app/FYAppSupport.h"
#import "FYLivePreviewScheduler.h"
#import "../capture/FYCaptureMappingCoordinator.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

// Original application receiver, constrained to the runtime context and peer actions.
@protocol FYCaptureRuntimeControllerHost <NSObject, FYLivePreviewTimerTarget>
@property(nonatomic, strong) NSPanel *captionDockPanel;
@property(nonatomic, strong) NSSlider *captionFontSizeSlider;
@property(nonatomic, strong) NSPanel *captionPanel;
@property(nonatomic) BOOL captionPanelVisibleBeforeRegionSelection;
@property(nonatomic, strong) NSTextField *captionTextLabel;
@property(nonatomic, strong) NSButton *captureCalibrateButton;
@property(nonatomic, strong) NSButton *captureCalibrateClearButton;
@property(nonatomic, strong) id captureCalibrationKeyMonitor;
@property(nonatomic, strong) NSTextField *captureCalibrationLabel;
@property(nonatomic, strong) NSPanel *captureCalibrationPanel;
@property(nonatomic, strong) NSView *captureCardControlsView;
@property(nonatomic, strong) FYCaptureCardInput *captureCardInput;
@property(nonatomic) BOOL captureDeviceListLoaded;
@property(nonatomic, strong) NSPopUpButton *captureDevicePopup;
@property(nonatomic, strong) NSButton *captureSettingsButton;
@property(nonatomic, strong) NSTextField *captureStatusLabel;
@property(nonatomic) BOOL captureUnavailable;
@property(nonatomic) BOOL displayTargetAmbiguous;
@property(nonatomic) BOOL displayTargetResolved;
@property(nonatomic, strong) NSImageView *framePreview;
@property(nonatomic) NSInteger geometryGeneration;
@property(nonatomic) BOOL inFlight;
@property(nonatomic, strong) NSPanel *inlineExpandedReadingPanel;
@property(nonatomic) BOOL inlineGeometryPending;
@property(nonatomic, strong) NSMutableArray<NSPanel *> *inlineLongCardPanels;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *inlineStableBlockIDs;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *inlineTranslationCache;
@property(nonatomic, strong) NSMutableArray<NSPanel *> *inlineTranslationPanels;
@property(nonatomic, strong) NSSegmentedControl *inputSourceControl;
@property(nonatomic, strong) NSTextField *inputSourceHintLabel;
@property(nonatomic) NSInteger inputSourceSegment;
@property(nonatomic, strong) NSSegmentedControl *languageControl;
@property(nonatomic, strong) NSDate *lastAutoLocateAttempt;
@property(nonatomic, copy) NSString *lastDisplayGeometryToken;
@property(nonatomic, strong) NSDate *lastDisplayTargetProbeDate;
@property(nonatomic, strong) FYInlineLayoutResult *lastInlineLayoutResult;
@property(nonatomic, copy) NSArray<OCRTextItem *> *lastInlineRenderedItems;
@property(nonatomic, copy) NSArray<NSString *> *lastInlineRenderedTranslations;
@property(nonatomic, copy) NSString *lastInlineTranslationKey;
@property(nonatomic, strong) NSDate *lastMappingValidationDate;
@property(nonatomic) uint64_t lastOCRedCaptureFrameIndex;
@property(nonatomic) uint64_t lastPreviewCaptureFrameIndex;
@property(nonatomic, strong) NSDate *lastPreviewDate;
@property(nonatomic, strong) NSDate *lastWindowRecoveryAttemptDate;
@property(nonatomic, strong) NSTextField *latestSourceLabel;
@property(nonatomic, strong) NSTextField *latestTranslationLabel;
@property(nonatomic, strong) NSWindow *mainWindow;
@property(nonatomic) BOOL mainWindowVisibleBeforeRegionSelection;
@property(nonatomic, strong) NSButton *manualOCRScopeCheckbox;
@property(nonatomic, strong) NSTextField *ocrPreviewLabel;
@property(nonatomic, strong) NSPanel *ocrPreviewPanel;
@property(nonatomic) BOOL ocrPreviewVisibleBeforeRegionSelection;
@property(nonatomic, strong) NSNumber *overlayOwnerPIDSnapshot;
@property(nonatomic, copy) NSArray<NSDictionary *> *overlayWindowSnapshot;
@property(nonatomic) BOOL previewInFlight;
@property(nonatomic, strong) NSTextField *previewPlaceholder;
@property(nonatomic, strong) dispatch_queue_t previewQueue;
@property(nonatomic) NSUInteger previewRenderSerial;
@property(nonatomic) NSUInteger previewRequestSerial;
@property(nonatomic, strong) NSTimer *previewTimer;
@property(nonatomic, strong) FYStudyOverlayPanel *quickSentencePanel;
@property(nonatomic, strong) FYSelectableSourceTextView *quickSourceTextView;
@property(nonatomic, strong) NSSlider *regionHeightSlider;
@property(nonatomic, strong) id regionSelectionKeyMonitor;
@property(nonatomic, strong) NSPanel *regionSelectionPanel;
@property(nonatomic, strong) NSSlider *regionWidthSlider;
@property(nonatomic, strong) NSSlider *regionXSlider;
@property(nonatomic, strong) NSSlider *regionYSlider;
@property(nonatomic) uint32_t resolvedDisplayTargetID;
@property(nonatomic) BOOL running;
@property(nonatomic) BOOL screenAccessRequestedDuringSession;
@property(nonatomic) BOOL selectOCRRegionAfterCaptureCalibration;
@property(nonatomic, copy, nullable) NSString *selectedCaptureDeviceID;
@property(nonatomic) BOOL selectingCaptureRegion;
@property(nonatomic) BOOL showAllWindowsInPicker;
@property(nonatomic, strong) FYStudyOverlayPanel *studyChatPanel;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) NSInteger translationGeneration;
@property(nonatomic, strong) NSTextField *windowCardHintLabel;
@property(nonatomic, strong) NSTextField *windowCardNoteLabel;
@property(nonatomic, strong) NSTextField *windowCardTitleLabel;
@property(nonatomic, copy) NSString *windowPickerPlaceholder;
@property(nonatomic, strong) NSPopUpButton *windowPopup;
@property(nonatomic, strong) NSButton *windowScopeButton;
@property(nonatomic) BOOL windowSelectionLost;
@property(nonatomic, strong) NSMutableArray<WindowItem *> *windows;
- (NSColor *)captionTextColor;
- (void)clearInlineTranslationPanels;
- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items;
- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items placementRect:(NSRect)windowFrame;
- (void)repositionExpandedInlineReadingCardInRect:(NSRect)viewport;
- (void)closeExpandedInlineReadingCard;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (void)advanceTranslationGeneration;
- (void)stop;
- (pid_t)selectedWindowOwnerPID;
- (NSArray<NSDictionary *> *)windowInfosIncludingWindow:(uint32_t)windowID;
- (NSArray<NSDictionary *> *)onScreenWindowInfos;
- (void)refreshOverlayVisibility:(id)sender;
- (void)timerFired:(NSTimer *)timer;
- (FYOCRManager *)ocrManager;
- (FYWindowManager *)windowManager;
- (NSArray<WindowItem *> *)availableWindowItems;
- (NSInteger)quickTimeCapturePriority:(WindowItem *)item;
- (NSArray<WindowItem *> *)displayedWindowItems;
- (BOOL)hasRecommendedWindowItems;
- (NSString *)windowBaseTitleForItem:(WindowItem *)item;
- (NSString *)windowMenuTitleForItem:(WindowItem *)item occurrence:(NSUInteger)occurrence;
- (void)rebuildWindowMenuPreservingSelection;
- (void)refreshWindows:(id)sender;
- (BOOL)selectWindowWithID:(uint32_t)windowID notifyChange:(BOOL)notify;
- (void)resetForSelectedWindowChange;
- (void)hideInlineTranslationPanelsForGeometryChange;
- (void)refreshDisplayGeometryIfNeeded:(BOOL)force;
- (void)updateWindowCardCopy;
- (BOOL)captureCardInputEnabled;
- (void)updateCaptureCardStatus;
- (void)ensureCaptureCardPermissionThen:(void (^)(BOOL granted))continuation;
- (nullable NSString *)captureDeviceIDFromPopup;
- (void)refreshCaptureDevices:(id)sender;
- (void)resetForInputSourceChange;
- (BOOL)startCaptureCardSessionIfPossible;
- (void)reconnectCaptureDevice:(id)sender;
- (void)controlValueChanged:(id)sender;
- (void)selectOCRRegion:(id)sender;
- (void)hideInterfaceForRegionSelection;
- (void)restoreInterfaceAfterRegionSelectionShowingOCRPreview:(BOOL)showOCRPreview;
- (void)updateOCRPreviewIfVisible;
- (void)requestScreenAccess:(id)sender;
- (void)saveSettings:(id)sender;
- (void)scheduleSettingsSave;
- (NSString *)dialogueTextFromItems:(NSArray<OCRTextItem *> *)items speakerLabelOnly:(BOOL *)speakerLabelOnly;
- (BOOL)livePreviewVisible;
- (void)refreshPreviewVisibility:(id)sender;
- (void)invalidatePreviewResults;
- (void)restartPreviewTimerIfRunning;
- (void)previewTimerFired:(NSTimer *)timer;
- (void)applyPreviewImage:(CGImageRef)image;
- (BOOL)hasScreenAccess;
- (BOOL)hasUsableScreenCaptureAccess;
- (BOOL)canCaptureSelectedWindowOnce;
- (uint32_t)selectedWindowID;
- (WindowItem *)windowItemForWindowID:(uint32_t)windowID;
- (WindowItem *)selectedWindowItem;
- (BOOL)liveBoundsForWindowID:(uint32_t)windowID outBounds:(CGRect *)outBounds;
- (uint32_t)resolveDisplayTargetWindowIDInWindowList:(NSArray<NSDictionary *> *)windowList
                                           ambiguous:(BOOL *)outAmbiguous
                                                note:(NSString **)outNote;
- (uint32_t)displayTargetWindowID;
- (WindowItem *)displayTargetWindowItem;
- (WindowItem *)windowItemForResolvedTargetID:(uint32_t)windowID;
- (NSScreen *)screenForWindowItem:(WindowItem *)item;
- (NSRect)appKitFrameForWindowItem:(WindowItem *)item;
- (BOOL)buildCaptureGridsWithFrame:(double **)outTempl templateW:(size_t *)outTW templateH:(size_t *)outTH
                             scene:(double **)outScene sceneW:(size_t *)outWW sceneH:(size_t *)outWH
                       videoAspect:(CGFloat *)outAspect
                        sceneWidth:(size_t)sceneWidth
                         forWindow:(WindowItem *)window
                            reason:(NSString **)outReason;
- (BOOL)autoDetectCaptureCardVideoRectForWindow:(WindowItem *)window reason:(NSString **)outReason;
- (void)resetInlineLayoutCacheAfterMappingChange;
- (double)captureCardMappingScoreForWindow:(WindowItem *)window entry:(NSDictionary *)entry;
- (void)storeCaptureCardMapping:(NSRect)screenRect
                     windowFrame:(NSRect)windowFrame
                     videoAspect:(CGFloat)videoAspect
                        deviceID:(NSString *)deviceID
                          source:(NSString *)source
                      confidence:(CGFloat)confidence
                     forWindowID:(uint32_t)windowID;
- (void)calibrateCaptureCardVideoRect:(NSRect)screenRect
                          windowFrame:(NSRect)windowFrame
                          videoAspect:(CGFloat)videoAspect
                             deviceID:(NSString *)deviceID
                          forWindowID:(uint32_t)windowID;
- (void)clearCaptureCardCalibrationForWindowID:(uint32_t)windowID;
- (NSString *)captureCardCalibrationSummaryForWindow:(WindowItem *)window;
- (BOOL)captureCardEstimatedDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect;
- (BOOL)captureCardDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect;
- (BOOL)captureCardDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect reason:(NSString **)outReason;
- (void)updateCaptureCalibrationStatus;
- (void)beginCaptureCardCalibration:(id)sender;
- (void)endCaptureCardCalibration;
- (void)finishCaptureCardCalibration:(NSRect)screenRect
                         windowFrame:(NSRect)windowFrame
                         videoAspect:(CGFloat)videoAspect
                            deviceID:(NSString *)deviceID
                          windowID:(uint32_t)windowID;
- (NSString *)inlineTargetUnavailableReasonWithFallback:(NSString *)fallback;
- (BOOL)inlinePlacementRect:(NSRect *)outRect reason:(NSString **)outReason;
- (void)showInlineMappingUnavailableNotice:(NSString *)reason;
- (CGRect)quartzRectFromSelectionRect:(CGRect)selectionRect panelFrame:(NSRect)panelFrame;
- (NSRect)appKitOCRPreviewFrameForWindowItem:(WindowItem *)item;
- (BOOL)updateOCRPreviewPanel;
- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)windowID;
- (CGImageRef)copyCapturedImageForWindow:(uint32_t)windowID regionX:(double)x regionY:(double)y regionWidth:(double)width regionHeight:(double)height;
- (NSString *)recognizeTextBlocksInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment blocks:(NSArray<OCRTextItem *> **)outBlocks error:(NSError **)error;
- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment error:(NSError **)error;
- (NSInteger)effectiveModeSegment;
- (FYInlineTranslationCache *)inlineCache;
- (FYAutoLocateSchedule *)locateSchedule;
- (FYCaptureMappingCache *)mappingCache;
- (FYMappingValidationSchedule *)validationSchedule;
- (FYTranslationRunState *)translationState;
- (FYOCRStabilityOwner *)stabilityOwner;
- (void)setStatus:(NSString *)status;
- (void)updateRunState;
- (void)showPreviewUnavailable:(NSString *)message;
- (void)updatePreviewFromImage:(CGImageRef)image generation:(NSInteger)generation;
- (void)updateCurrentWindowLabel;
- (NSArray<NSDictionary *> *)updateRuntimeDiagnostics;
@end

// Owns capture runtime state; no devices, timers or requests start during construction.
@interface FYCaptureRuntimeController : NSObject <FYLivePreviewSource>
@property(nonatomic, strong, readonly) FYDisplayTargetTracker *displayTargetTracker;
@property(nonatomic, strong, readonly) FYLivePreviewScheduler *previewScheduler;
@property(nonatomic, weak) id<FYCaptureRuntimeControllerHost> host;
- (instancetype)initWithHost:(id<FYCaptureRuntimeControllerHost>)host;
@property(nonatomic, strong, readonly) FYCaptureMappingCoordinator *mappingCoordinator;
@property(nonatomic, strong) FYAutoLocateSchedule *autoLocateSchedule;
@property(nonatomic) BOOL captionPanelVisibleBeforeRegionSelection;
@property(nonatomic, strong) id captureCalibrationKeyMonitor;
@property(nonatomic, strong) NSPanel *captureCalibrationPanel;
@property(nonatomic, strong) FYCaptureCardInput *captureCardInput;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *captureCardVideoRects;
@property(nonatomic) BOOL captureDeviceListLoaded;
@property(nonatomic, strong) FYCaptureMappingCache *captureMappingCache;
@property(nonatomic, strong) dispatch_queue_t captureQueue;
@property(nonatomic) BOOL captureUnavailable;
@property(nonatomic) BOOL displayTargetAmbiguous;
@property(nonatomic) BOOL displayTargetResolved;
@property(nonatomic) NSInteger geometryGeneration;
@property(nonatomic) BOOL inlineGeometryPending;
@property(nonatomic) NSInteger inputSourceSegment;
@property(nonatomic, strong) NSDate *lastAutoLocateAttempt;
@property(nonatomic, copy) NSString *lastDisplayGeometryToken;
@property(nonatomic, strong) NSDate *lastDisplayTargetProbeDate;
@property(nonatomic, strong) NSDate *lastMappingValidationDate;
@property(nonatomic) uint64_t lastOCRedCaptureFrameIndex;
@property(nonatomic) uint64_t lastPreviewCaptureFrameIndex;
@property(nonatomic, strong) NSDate *lastPreviewDate;
@property(nonatomic, strong) NSDate *lastWindowRecoveryAttemptDate;
@property(nonatomic, strong) FYMappingValidationSchedule *mappingValidationSchedule;
@property(nonatomic, strong) FYOCRManager *ocrManager;
@property(nonatomic, strong) NSTextField *ocrPreviewLabel;
@property(nonatomic, strong) NSPanel *ocrPreviewPanel;
@property(nonatomic) BOOL ocrPreviewVisibleBeforeRegionSelection;
@property(nonatomic, strong) NSNumber *overlayOwnerPIDSnapshot;
@property(nonatomic, copy) NSArray<NSDictionary *> *overlayWindowSnapshot;
@property(nonatomic) BOOL previewInFlight;
@property(nonatomic, strong) dispatch_queue_t previewQueue;
@property(nonatomic) NSUInteger previewRenderSerial;
@property(nonatomic) NSUInteger previewRequestSerial;
@property(nonatomic, strong) NSTimer *previewTimer;
@property(nonatomic, strong) id regionSelectionKeyMonitor;
@property(nonatomic, strong) NSPanel *regionSelectionPanel;
@property(nonatomic) uint32_t resolvedDisplayTargetID;
@property(nonatomic) BOOL screenAccessRequestedDuringSession;
@property(nonatomic) BOOL selectOCRRegionAfterCaptureCalibration;
@property(nonatomic, copy, nullable) NSString *selectedCaptureDeviceID;
@property(nonatomic) BOOL selectingCaptureRegion;
@property(nonatomic) BOOL showAllWindowsInPicker;
@property(nonatomic, strong) FYWindowManager *windowManager;
@property(nonatomic, copy) NSString *windowPickerPlaceholder;
@property(nonatomic) BOOL windowSelectionLost;
@property(nonatomic, strong) NSMutableArray<WindowItem *> *windows;
- (pid_t)selectedWindowOwnerPID;
- (NSArray<NSDictionary *> *)windowInfosIncludingWindow:(uint32_t)windowID;
- (NSArray<NSDictionary *> *)onScreenWindowInfos;
- (FYOCRManager *)ocrManager;
- (FYWindowManager *)windowManager;
- (NSArray<WindowItem *> *)availableWindowItems;
- (NSInteger)quickTimeCapturePriority:(WindowItem *)item;
- (NSArray<WindowItem *> *)displayedWindowItems;
- (BOOL)hasRecommendedWindowItems;
- (NSString *)windowBaseTitleForItem:(WindowItem *)item;
- (NSString *)windowMenuTitleForItem:(WindowItem *)item occurrence:(NSUInteger)occurrence;
- (void)rebuildWindowMenuPreservingSelection;
- (void)refreshWindows:(id)sender;
- (void)toggleWindowListScope:(id)sender;
- (BOOL)selectWindowWithID:(uint32_t)windowID notifyChange:(BOOL)notify;
- (BOOL)recoverWindowSelectionIfRecreated;
- (void)windowSelectionChanged:(id)sender;
- (void)resetForSelectedWindowChange;
- (void)hideInlineTranslationPanelsForGeometryChange;
- (void)refreshDisplayGeometryIfNeeded:(BOOL)force;
- (void)updateWindowCardCopy;
- (FYCaptureCardInput *)captureCardInput;
- (BOOL)captureCardInputEnabled;
- (void)updateCaptureCardStatus;
- (void)ensureCaptureCardPermissionThen:(void (^)(BOOL granted))continuation;
- (NSString *)captionLinesFromTranslations:(NSArray<NSString *> *)translations;
- (nullable NSString *)captureDeviceIDFromPopup;
- (void)refreshCaptureDevices:(id)sender;
- (void)captureDeviceChanged:(id)sender;
- (void)inputSourceChanged:(id)sender;
- (void)resetForInputSourceChange;
- (BOOL)startCaptureCardSessionIfPossible;
- (void)reconnectCaptureDevice:(id)sender;
- (void)openCameraAccessSettings:(id)sender;
- (CGRect)selectedOCRScope;
- (void)selectOCRRegion:(id)sender;
- (void)hideInterfaceForRegionSelection;
- (void)restoreInterfaceAfterRegionSelectionShowingOCRPreview:(BOOL)showOCRPreview;
- (void)showOCRPreview:(id)sender;
- (void)hideOCRPreview:(id)sender;
- (void)updateOCRPreviewIfVisible;
- (BOOL)livePreviewVisible;
- (void)refreshPreviewVisibility:(id)sender;
- (void)windowDidChangeOcclusionState:(NSNotification *)notification;
- (void)windowDidMiniaturize:(NSNotification *)notification;
- (void)windowDidDeminiaturize:(NSNotification *)notification;
- (void)invalidatePreviewResults;
- (void)restartPreviewTimerIfRunning;
- (void)previewTimerFired:(NSTimer *)timer;
- (void)applyPreviewImage:(CGImageRef)image;
- (BOOL)hasScreenAccess;
- (BOOL)hasUsableScreenCaptureAccess;
- (BOOL)canCaptureSelectedWindowOnce;
- (void)handleMissingScreenAccessForStart;
- (uint32_t)selectedWindowID;
- (WindowItem *)windowItemForWindowID:(uint32_t)windowID;
- (WindowItem *)selectedWindowItem;
- (BOOL)liveBoundsForWindowID:(uint32_t)windowID outBounds:(CGRect *)outBounds;
- (uint32_t)resolveDisplayTargetWindowIDInWindowList:(NSArray<NSDictionary *> *)windowList
                                           ambiguous:(BOOL *)outAmbiguous
                                                note:(NSString **)outNote;
- (uint32_t)displayTargetWindowID;
- (WindowItem *)displayTargetWindowItem;
- (WindowItem *)windowItemForResolvedTargetID:(uint32_t)windowID;
- (NSScreen *)screenForWindowItem:(WindowItem *)item;
- (NSRect)appKitFrameForWindowItem:(WindowItem *)item;
- (BOOL)buildCaptureGridsWithFrame:(double **)outTempl templateW:(size_t *)outTW templateH:(size_t *)outTH
                             scene:(double **)outScene sceneW:(size_t *)outWW sceneH:(size_t *)outWH
                       videoAspect:(CGFloat *)outAspect
                        sceneWidth:(size_t)sceneWidth
                         forWindow:(WindowItem *)window
                            reason:(NSString **)outReason;
- (BOOL)autoDetectCaptureCardVideoRectForWindow:(WindowItem *)window reason:(NSString **)outReason;
- (void)resetInlineLayoutCacheAfterMappingChange;
- (double)captureCardMappingScoreForWindow:(WindowItem *)window entry:(NSDictionary *)entry;
- (void)storeCaptureCardMapping:(NSRect)screenRect
                     windowFrame:(NSRect)windowFrame
                     videoAspect:(CGFloat)videoAspect
                        deviceID:(NSString *)deviceID
                          source:(NSString *)source
                      confidence:(CGFloat)confidence
                     forWindowID:(uint32_t)windowID;
- (void)calibrateCaptureCardVideoRect:(NSRect)screenRect
                          windowFrame:(NSRect)windowFrame
                          videoAspect:(CGFloat)videoAspect
                             deviceID:(NSString *)deviceID
                          forWindowID:(uint32_t)windowID;
- (void)clearCaptureCardCalibrationForWindowID:(uint32_t)windowID;
- (BOOL)captureCardHasCalibratedVideoRectForWindow:(WindowItem *)window;
- (NSString *)captureCardCalibrationSummaryForWindow:(WindowItem *)window;
- (BOOL)captureCardEstimatedDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect;
- (BOOL)captureCardDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect;
- (BOOL)captureCardDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect reason:(NSString **)outReason;
- (void)updateCaptureCalibrationStatus;
- (void)beginCaptureCardCalibration:(id)sender;
- (void)endCaptureCardCalibration;
- (void)finishCaptureCardCalibration:(NSRect)screenRect
                         windowFrame:(NSRect)windowFrame
                         videoAspect:(CGFloat)videoAspect
                            deviceID:(NSString *)deviceID
                          windowID:(uint32_t)windowID;
- (void)clearCaptureCardCalibration:(id)sender;
- (NSString *)inlineTargetUnavailableReasonWithFallback:(NSString *)fallback;
- (BOOL)inlinePlacementRect:(NSRect *)outRect reason:(NSString **)outReason;
- (void)showInlineMappingUnavailableNotice:(NSString *)reason;
- (CGRect)quartzRectFromSelectionRect:(CGRect)selectionRect panelFrame:(NSRect)panelFrame;
- (NSRect)appKitOCRPreviewFrameForWindowItem:(WindowItem *)item;
- (BOOL)updateOCRPreviewPanel;
- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)windowID;
- (CGImageRef)copyCapturedImageForWindow:(uint32_t)windowID regionX:(double)x regionY:(double)y regionWidth:(double)width regionHeight:(double)height;
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
- (FYAutoLocateSchedule *)locateSchedule;
- (NSDate *)lastAutoLocateAttempt;
- (void)setLastAutoLocateAttempt:(NSDate *)value;
- (FYCaptureMappingCache *)mappingCache;
- (NSMutableDictionary *)captureCardVideoRects;
- (void)setCaptureCardVideoRects:(NSMutableDictionary<NSString *, NSDictionary *> *)value;
- (FYMappingValidationSchedule *)validationSchedule;
- (NSDate *)lastMappingValidationDate;
- (void)setLastMappingValidationDate:(NSDate *)value;
- (void)showPreviewUnavailable:(NSString *)message;
- (void)updatePreviewFromImage:(CGImageRef)image generation:(NSInteger)generation;
- (void)clampRegionSliders;
- (void)captureLatestStudySentenceWithCompletion:(void (^)(NSString *,NSError *))completion;
@end
#pragma clang diagnostic pop
