#pragma once
#import "../app/FYAppSupport.h"
#import "FYInlineDisplayCoordinatorInternal.h"
#import "FYInlineManualPlacementCoordinator.h"
#import "FYInlineDragController.h"
#import "FYInlineSelectionCoordinator.h"
#import "FYInlineCardActionBinder.h"
#import "FYInlineExpandedReadingController.h"
#import "FYInlineOverflowController.h"
#import "FYInlineCardRenderer.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

// Explicit context and peer actions. Capture, OCR and translation stay with the host.
@protocol FYInlineOverlayControllerHost <NSObject>
@property(nonatomic, strong) NSSlider *batchFontSizeSlider;
@property(nonatomic, strong) NSSlider *batchHeightSlider;
@property(nonatomic, strong) NSColorWell *batchTextColorWell;
@property(nonatomic, strong) NSSegmentedControl *batchThemeControl;
@property(nonatomic, strong) NSSlider *batchWidthSlider;
@property(nonatomic, strong) NSSlider *captionOpacitySlider;
@property(nonatomic, strong) NSPanel *captionPanel;
@property(nonatomic, strong) FYCaptureCardInput *captureCardInput;
@property(nonatomic) NSInteger geometryGeneration;
@property(nonatomic, strong) FYInlineBlockSnapshot *inlineBlockSnapshot;
@property(nonatomic, strong) FYInlineOCRFrameStabilizer *inlineFrameStabilizer;
@property(nonatomic) BOOL inlineGeometryPending;
@property(nonatomic) NSInteger inlineOCRPendingCount;
@property(nonatomic, copy) NSString *inlineOCRPendingText;
@property(nonatomic, copy) NSString *lastDisplayGeometryToken;
- (void)refreshInlineTranslationList;
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSTextField *)mutedLabel:(NSString *)text;
- (void)refreshOverlayVisibility:(id)sender;
- (BOOL)captureCardInputEnabled;
- (FYInlineTextBlock *)inlineLayoutBlockForItem:(OCRTextItem *)item order:(NSInteger)order;
- (NSRect)appKitFrameForOCRItem:(OCRTextItem *)item inWindowFrame:(NSRect)windowFrame;
- (uint32_t)displayTargetWindowID;
- (WindowItem *)displayTargetWindowItem;
- (NSRect)appKitFrameForWindowItem:(WindowItem *)item;
- (BOOL)inlinePlacementRect:(NSRect *)outRect reason:(NSString **)outReason;
- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items;
- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items placementRect:(NSRect)windowFrame;
- (void)updateInlineOverflowEntryWithPlacements:(NSArray<FYInlinePlacement *> *)placements
                                          items:(NSDictionary<NSString *, OCRTextItem *> *)itemsByBlockID
                                       viewport:(NSRect)viewport
                                    unplaceable:(NSUInteger)unplaceable;
- (void)expireInlineOverflowEntryIfNeeded;
- (void)startInlineModifierMonitor;
- (BOOL)inlineBlockID:(NSString *)stableBlockID isSelectedForItem:(OCRTextItem *)item;
- (void)wireInlineLongCardPanel:(NSPanel *)panel item:(OCRTextItem *)item translation:(NSString *)translation frame:(NSRect)frame;
- (void)wireInlineLongCardPanel:(NSPanel *)panel
                           item:(OCRTextItem *)item
                    translation:(NSString *)translation
                          frame:(NSRect)frame
                  stableBlockID:(NSString *)stableBlockID;
@end

// Sole owner of inline panels and their presentation lifecycle.
@interface FYInlineOverlayController : FYInlineDisplayCoordinator <FYInlineDisplayNativeActions, FYInlineManualPlacementStateSource, FYInlineManualPlacementNativeActions, FYInlineDragStateSource, FYInlineDragTimerActions, FYInlineSnapshotInputSource, FYInlineSelectionStateSource, FYInlineCardActionSource, FYInlineExpandedReadingSource, FYInlineOverflowNativeSource, FYInlineCardRenderSource>
@property(nonatomic,strong,readonly) FYInlineCardRenderer *cardRenderer;
@property(nonatomic,strong,readonly) FYInlineOverflowController *overflowController;
@property(nonatomic,strong,readonly) FYInlineExpandedReadingController *expandedReadingController;
@property(nonatomic,strong,readonly) FYInlineSelectionCoordinator *selectionCoordinator;
@property(nonatomic,strong,readonly) FYInlineCardActionBinder *cardActionBinder;
@property(nonatomic,strong,readonly) FYInlineManualPlacementCoordinator *manualPlacementCoordinator;
@property(nonatomic,strong,readonly) FYInlineDragController *dragController;
@property(nonatomic, weak) id<FYInlineOverlayControllerHost> host;
- (instancetype)initWithHost:(id<FYInlineOverlayControllerHost>)host;
@property(nonatomic, strong) NSTimer *batchAppearanceTimer;
@property(nonatomic, weak) NSPanel *inlineDraggingPanel;
@property(nonatomic) NSUInteger inlineExpandedMissingFrames;
@property(nonatomic, copy) NSString *inlineExpandedReadingBlockID;
@property(nonatomic, strong) id inlineExpandedReadingKeyMonitor;
@property(nonatomic, strong) NSPanel *inlineExpandedReadingPanel;
@property(nonatomic, strong) FYInlineLayoutEngine *inlineLayoutEngine;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *inlineManualOffsetAge;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *inlineManualOffsets;
@property(nonatomic, strong) NSTimer *inlineModifierTimer;
@property(nonatomic) BOOL inlineOptionDragArmed;
@property(nonatomic) NSUInteger inlineOverflowCandidateCount;
@property(nonatomic) NSUInteger inlineOverflowCandidateFrames;
@property(nonatomic, strong) id inlineOverflowChoiceKeyMonitor;
@property(nonatomic, strong) NSPanel *inlineOverflowChoicePanel;
@property(nonatomic) NSUInteger inlineOverflowCount;
@property(nonatomic) NSTimeInterval inlineOverflowEmptySince;
@property(nonatomic, strong) NSArray<NSDictionary *> *inlineOverflowEntries;
@property(nonatomic, strong) NSPanel *inlineOverflowPanel;
@property(nonatomic) NSUInteger inlineOverflowPanelCount;
- (void)clearInlineTranslationPanels;
- (void)updateInlinePanel:(NSPanel *)panel
              translation:(NSString *)translation
               sourceText:(NSString *)sourceText
              sourceFrame:(NSRect)sourceFrame
              windowFrame:(NSRect)windowFrame
                   layout:(InlinePanelLayout)layout;
- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items;
- (void)recordInlineLayoutDebug:(FYInlineLayoutResult *)result previous:(FYInlineLayoutResult *)previous viewport:(NSRect)viewport reason:(NSString *)reason;
- (void)updateInlineOverflowEntryWithPlacements:(NSArray<FYInlinePlacement *> *)placements
                                          items:(NSDictionary<NSString *, OCRTextItem *> *)itemsByBlockID
                                       viewport:(NSRect)viewport
                                    unplaceable:(NSUInteger)unplaceable;
- (void)expireInlineOverflowEntryIfNeeded;
- (void)positionInlineOverflowEntryInViewport:(NSRect)viewport;
- (void)buildInlineOverflowEntryForViewport:(NSRect)viewport;
- (void)showInlineOverflowChooser;
- (void)closeInlineOverflowChoiceAction:(id)sender;
- (NSString *)overflowRowTitleForEntry:(NSDictionary *)entry;
- (void)openInlineOverflowRow:(NSButton *)sender;
- (void)closeInlineOverflowChoice;
- (NSString *)inlineManualOffsetKeyForText:(NSString *)text normalizedBox:(CGRect)box;
- (NSValue *)inlineManualOffsetForText:(NSString *)text normalizedBox:(CGRect)box;
- (void)recordInlineManualOffsetForPanel:(NSPanel *)panel;
- (void)wireInlinePanelDrag:(NSPanel *)panel placement:(FYInlinePlacement *)placement;
- (void)startInlineModifierMonitor;
- (void)stopInlineModifierMonitor;
- (void)inlineModifierTick:(NSTimer *)timer;
- (void)applyInlineDragMode:(BOOL)armed;
- (InlinePanelLayout)inlinePanelLayoutFromPlacement:(FYInlinePlacement *)placement;
- (BOOL)inlineBlockID:(NSString *)stableBlockID isSelectedForItem:(OCRTextItem *)item;
- (BOOL)inlineBlockIsSelectedForItem:(OCRTextItem *)item;
- (NSParagraphStyle *)inlineLongCardBodyStyle;
- (NSFont *)inlineLongCardBodyFont;
- (CGFloat)inlineLongCardBodyLineHeight;
- (CGFloat)inlineLongCardMinimumHeight;
- (CGFloat)inlineLongCardBodyViewportForHeight:(CGFloat)cardHeight;
- (void)applyInlineLongCardBody:(NSString *)translation toLabel:(NSTextField *)label cardWidth:(CGFloat)cardWidth;
- (void)applyInlineLongCardBody:(NSString *)translation
                        toLabel:(NSTextField *)label
                       cardWidth:(CGFloat)cardWidth
                       placement:(FYInlinePlacement *)placement;
- (NSView *)inlineLongCardContentForTranslation:(NSString *)translation size:(NSSize)size selected:(BOOL)selected compact:(BOOL)compact;
- (NSView *)inlineLongCardContentForTranslation:(NSString *)translation
                                           size:(NSSize)size
                                       selected:(BOOL)selected
                                        compact:(BOOL)compact
                                      placement:(FYInlinePlacement *)placement;
- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(NSRect)frame translation:(NSString *)translation;
- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(NSRect)frame translation:(NSString *)translation expandedReading:(BOOL)expandedReading;
- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame;
- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame placement:(FYInlinePlacement *)placement;
- (void)updateInlineLongCard:(NSPanel *)panel translation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame;
- (void)updateInlineLongCard:(NSPanel *)panel translation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame compact:(BOOL)compact;
- (void)updateInlineLongCard:(NSPanel *)panel
                 translation:(NSString *)translation
                        item:(OCRTextItem *)item
                       frame:(NSRect)frame
                     compact:(BOOL)compact
                   placement:(FYInlinePlacement *)placement;
- (NSString *)inlineBlockIdentityForItem:(OCRTextItem *)item;
- (FYInlineBlockSnapshot *)inlineSnapshotForItem:(OCRTextItem *)item translation:(NSString *)translation;
- (FYInlineBlockSnapshot *)inlineSnapshotForItem:(OCRTextItem *)item
                                     translation:(NSString *)translation
                                   stableBlockID:(NSString *)stableBlockID;
- (FYInlineBlockSnapshot *)inlineSnapshotForBlock:(FYInlineTextBlock *)block
                                      translation:(NSString *)translation
                                    stableBlockID:(NSString *)stableBlockID;
- (void)wireInlineLongCardPanel:(NSPanel *)panel item:(OCRTextItem *)item translation:(NSString *)translation frame:(NSRect)frame;
- (void)wireInlineLongCardPanel:(NSPanel *)panel
                           item:(OCRTextItem *)item
                    translation:(NSString *)translation
                          frame:(NSRect)frame
                  stableBlockID:(NSString *)stableBlockID;
- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item translation:(NSString *)translation;
- (NSSize)expandedInlineReadingSizeForTranslation:(NSString *)translation viewport:(NSRect)viewport;
- (void)refreshExpandedInlineReadingCardAppearanceInRect:(NSRect)viewport;
- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item
                             translation:(NSString *)translation
                           stableBlockID:(NSString *)stableBlockID;
- (void)repositionExpandedInlineReadingCardInRect:(NSRect)viewport;
- (void)advanceExpandedReadingState;
- (void)closeExpandedInlineReadingCard;
- (void)hideOtherInlinePanelsForExpandedReading:(NSPanel *)expandedPanel;
- (NSArray<NSPanel *> *)inlinePanelsPresentInCurrentLayout;
- (NSArray<NSPanel *> *)allInlineOverlayPanels;
- (void)restoreOtherInlinePanelsAfterExpandedReading;
- (FYInlineLayoutEngine *)inlineLayoutEngine;
- (void)applyBatchAppearanceToLayoutEngine;
- (CGFloat)inlinePanelFillAlpha;
- (NSColor *)inlinePanelFillColor;
- (void)refreshInlinePanelAppearance;
- (void)applyInlineTextColor:(NSColor *)color toView:(NSView *)view;
- (void)refreshInlinePanelTextAppearance;
- (NSColor *)inlinePanelBorderColor;
- (NSColor *)inlinePanelTextColor;
- (NSColor *)inlinePanelTitleColor;
- (NSFont *)inlinePanelFontOfSize:(CGFloat)size;
- (NSFont *)inlinePanelFontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
- (InlinePanelLayout)inlinePanelLayoutForTranslation:(NSString *)translation
                                          sourceText:(NSString *)sourceText
                                         sourceFrame:(NSRect)sourceFrame
                                         windowFrame:(NSRect)windowFrame;
- (InlinePanelLayout)inlinePanelLayoutForTranslation:(NSString *)translation
                                          sourceText:(NSString *)sourceText
                                         sourceFrame:(NSRect)sourceFrame
                                         windowFrame:(NSRect)windowFrame
                                       placedFrames:(NSArray<NSValue *> *)placedFrames
                                       hugTextWidth:(BOOL)hugTextWidth;
- (NSAttributedString *)inlinePanelAttributedText:(NSString *)translation font:(NSFont *)font;
- (void)applyInlineChromeToContent:(NSView *)content cornerRadius:(CGFloat)cornerRadius;
- (void)applyInlineCompactEntryChromeToContent:(NSView *)content cornerRadius:(CGFloat)cornerRadius;
- (NSTextField *)inlineCompactEntryLabel:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSPanel *)inlinePanelForTranslation:(NSString *)translation sourceText:(NSString *)sourceText sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame;
- (NSPanel *)inlinePanelForTranslation:(NSString *)translation sourceText:(NSString *)sourceText sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame layout:(InlinePanelLayout)layout;
- (NSInteger)inlineThemeIndex;
- (NSColor *)inlineThemeTextColor;
@end
#pragma clang diagnostic pop
