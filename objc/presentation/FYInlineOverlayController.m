#import "FYInlineOverlayController.h"


@interface FYInlineOverlayController ()
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
@property(nonatomic) NSInteger inlineOCRPendingCount;
@property(nonatomic, copy) NSString *inlineOCRPendingText;
@property(nonatomic, copy) NSString *lastDisplayGeometryToken;
@end

@implementation FYInlineOverlayController

@synthesize cardRenderer = _cardRenderer;
- (FYInlineCardRenderer *)cardRenderer { if(!_cardRenderer){_cardRenderer=[FYInlineCardRenderer new];}return _cardRenderer; }
- (NSColor *)inlineCardInkColor { return FYAdventureColor(@"ink"); }
- (NSColor *)inlineCardMintColor { return FYAdventureColor(@"mint"); }
- (NSColor *)inlineCardRimColor { return FYAdventureColor(@"rim"); }
- (NSColor *)inlineCardLineColor { return FYAdventureColor(@"line"); }
- (NSString *)inlineCardTitleForBlockText:(NSString *)text { return [FYInlineLayoutEngine shortTitleForBlockText:text]; }
- (void)inlineCardWirePanelThroughHost:(NSPanel *)panel item:(OCRTextItem *)item translation:(NSString *)translation frame:(NSRect)frame stableBlockID:(NSString *)identity { [self.host wireInlineLongCardPanel:panel item:item translation:translation frame:frame stableBlockID:identity]; }
- (InlinePanelLayout)inlinePanelLayoutFromPlacement:(FYInlinePlacement *)placement { return [self.cardRenderer inlinePanelLayoutFromPlacement:placement]; }
- (NSParagraphStyle *)inlineLongCardBodyStyle { return [self.cardRenderer inlineLongCardBodyStyleWithSource:self]; }
- (NSFont *)inlineLongCardBodyFont { return [self.cardRenderer inlineLongCardBodyFontWithSource:self]; }
- (CGFloat)inlineLongCardBodyLineHeight { return [self.cardRenderer inlineLongCardBodyLineHeightWithSource:self]; }
- (CGFloat)inlineLongCardMinimumHeight { return [self.cardRenderer inlineLongCardMinimumHeightWithSource:self]; }
- (CGFloat)inlineLongCardBodyViewportForHeight:(CGFloat)cardHeight { return [self.cardRenderer inlineLongCardBodyViewportForHeight:cardHeight]; }
- (void)applyInlineLongCardBody:(NSString *)translation
                        toLabel:(NSTextField *)label
                       cardWidth:(CGFloat)cardWidth
                       placement:(FYInlinePlacement *)placement { [self.cardRenderer applyInlineLongCardBody:translation toLabel:label cardWidth:cardWidth placement:placement source:self]; }
- (NSView *)inlineLongCardContentForTranslation:(NSString *)translation
                                           size:(NSSize)size
                                       selected:(BOOL)selected
                                        compact:(BOOL)compact
                                      placement:(FYInlinePlacement *)placement { return [self.cardRenderer inlineLongCardContentForTranslation:translation size:size selected:selected compact:compact placement:placement source:self]; }
- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(NSRect)frame translation:(NSString *)translation expandedReading:(BOOL)expandedReading { return [self.cardRenderer inlinePlacementForLongCardFrame:frame translation:translation expandedReading:expandedReading source:self]; }
- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame placement:(FYInlinePlacement *)placement { return [self.cardRenderer inlineLongPanelForTranslation:translation item:item frame:frame placement:placement source:self]; }
- (void)updateInlineLongCard:(NSPanel *)panel
                 translation:(NSString *)translation
                        item:(OCRTextItem *)item
                       frame:(NSRect)frame
                     compact:(BOOL)compact
                   placement:(FYInlinePlacement *)placement { [self.cardRenderer updateInlineLongCard:panel translation:translation item:item frame:frame compact:compact placement:placement source:self]; }
- (void)updateInlinePanel:(NSPanel *)panel
              translation:(NSString *)translation
               sourceText:(NSString *)sourceText
              sourceFrame:(NSRect)sourceFrame
              windowFrame:(NSRect)windowFrame
                   layout:(InlinePanelLayout)layout { [self.cardRenderer updateInlinePanel:panel translation:translation sourceText:sourceText sourceFrame:sourceFrame windowFrame:windowFrame layout:layout source:self]; }
- (NSAttributedString *)inlinePanelAttributedText:(NSString *)translation font:(NSFont *)font { return [self.cardRenderer inlinePanelAttributedText:translation font:font source:self]; }
- (void)applyInlineChromeToContent:(NSView *)content cornerRadius:(CGFloat)cornerRadius { [self.cardRenderer applyInlineChromeToContent:content cornerRadius:cornerRadius source:self]; }
- (void)applyInlineCompactEntryChromeToContent:(NSView *)content cornerRadius:(CGFloat)cornerRadius { [self.cardRenderer applyInlineCompactEntryChromeToContent:content cornerRadius:cornerRadius source:self]; }
- (NSTextField *)inlineCompactEntryLabel:(NSString *)text font:(NSFont *)font color:(NSColor *)color { return [self.cardRenderer inlineCompactEntryLabel:text font:font color:color source:self]; }
- (NSPanel *)inlinePanelForTranslation:(NSString *)translation sourceText:(NSString *)sourceText sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame layout:(InlinePanelLayout)layout { return [self.cardRenderer inlinePanelForTranslation:translation sourceText:sourceText sourceFrame:sourceFrame windowFrame:windowFrame layout:layout source:self]; }
- (void)refreshInlinePanelAppearance { [self.cardRenderer refreshInlinePanelAppearanceWithSource:self]; }
- (void)applyInlineTextColor:(NSColor *)color toView:(NSView *)view { [self.cardRenderer applyInlineTextColor:color toView:view source:self]; }
- (void)refreshInlinePanelTextAppearance { [self.cardRenderer refreshInlinePanelTextAppearanceWithSource:self]; }


@synthesize overflowController = _overflowController;
@dynamic inlineOverflowCandidateCount, inlineOverflowCandidateFrames, inlineOverflowChoiceKeyMonitor, inlineOverflowChoicePanel, inlineOverflowCount, inlineOverflowEmptySince, inlineOverflowEntries, inlineOverflowPanel, inlineOverflowPanelCount;
- (FYInlineOverflowController *)overflowController { if(!_overflowController){_overflowController=[FYInlineOverflowController new];}return _overflowController; }
- (NSUInteger)inlineOverflowCandidateCount { return self.overflowController.inlineOverflowCandidateCount; }
- (void)setInlineOverflowCandidateCount:(NSUInteger)value { self.overflowController.inlineOverflowCandidateCount=value; }
- (NSUInteger)inlineOverflowCandidateFrames { return self.overflowController.inlineOverflowCandidateFrames; }
- (void)setInlineOverflowCandidateFrames:(NSUInteger)value { self.overflowController.inlineOverflowCandidateFrames=value; }
- (id)inlineOverflowChoiceKeyMonitor { return self.overflowController.inlineOverflowChoiceKeyMonitor; }
- (void)setInlineOverflowChoiceKeyMonitor:(id)value { self.overflowController.inlineOverflowChoiceKeyMonitor=value; }
- (NSPanel *)inlineOverflowChoicePanel { return self.overflowController.inlineOverflowChoicePanel; }
- (void)setInlineOverflowChoicePanel:(NSPanel *)value { self.overflowController.inlineOverflowChoicePanel=value; }
- (NSUInteger)inlineOverflowCount { return self.overflowController.inlineOverflowCount; }
- (void)setInlineOverflowCount:(NSUInteger)value { self.overflowController.inlineOverflowCount=value; }
- (NSTimeInterval)inlineOverflowEmptySince { return self.overflowController.inlineOverflowEmptySince; }
- (void)setInlineOverflowEmptySince:(NSTimeInterval)value { self.overflowController.inlineOverflowEmptySince=value; }
- (NSArray<NSDictionary *> *)inlineOverflowEntries { return self.overflowController.inlineOverflowEntries; }
- (void)setInlineOverflowEntries:(NSArray<NSDictionary *> *)value { self.overflowController.inlineOverflowEntries=value; }
- (NSPanel *)inlineOverflowPanel { return self.overflowController.inlineOverflowPanel; }
- (void)setInlineOverflowPanel:(NSPanel *)value { self.overflowController.inlineOverflowPanel=value; }
- (NSUInteger)inlineOverflowPanelCount { return self.overflowController.inlineOverflowPanelCount; }
- (void)setInlineOverflowPanelCount:(NSUInteger)value { self.overflowController.inlineOverflowPanelCount=value; }
- (void)updateInlineOverflowEntryWithPlacements:(NSArray<FYInlinePlacement *> *)placements items:(NSDictionary<NSString *,OCRTextItem *> *)items viewport:(NSRect)viewport unplaceable:(NSUInteger)unplaceable { [self.overflowController updateInlineOverflowEntryWithPlacements:placements items:items viewport:viewport unplaceable:unplaceable source:self]; }
- (void)expireInlineOverflowEntryIfNeeded { [self.overflowController expireInlineOverflowEntryIfNeededWithSource:self]; }
- (void)positionInlineOverflowEntryInViewport:(NSRect)viewport { [self.overflowController positionInlineOverflowEntryInViewport:viewport source:self]; }
- (void)buildInlineOverflowEntryForViewport:(NSRect)viewport { [self.overflowController buildInlineOverflowEntryForViewport:viewport source:self]; }
- (void)showInlineOverflowChooser { [self.overflowController showInlineOverflowChooserWithSource:self]; }
- (void)showInlineOverflowList { [self.overflowController showInlineOverflowListWithSource:self]; }
- (NSString *)overflowRowTitleForEntry:(NSDictionary *)entry { return [self.overflowController overflowRowTitleForEntry:entry]; }
- (void)openInlineOverflowRow:(NSButton *)sender { NSInteger index=sender.tag;[self.overflowController openInlineOverflowRowAtIndex:index source:self]; }
- (void)closeInlineOverflowChoice { [self.overflowController closeInlineOverflowChoiceWithSource:self]; }
- (void)resizeInlineOverflowEntryWithTitle:(NSString *)title viewport:(NSRect)viewport { [self.overflowController resizeInlineOverflowEntryWithTitle:title viewport:viewport source:self]; }
- (NSString *)inlineOverflowTitleForBlockText:(NSString *)text { return [FYInlineLayoutEngine shortTitleForBlockText:text]; }
- (NSString *)inlineOverflowFallbackTitle { return self.inlineLayoutEngine.foldedEntryFallbackTitle; }
- (NSTimeInterval)inlineOverflowTime { return [NSDate timeIntervalSinceReferenceDate]; }
- (void)inlineHostExpireInlineOverflowEntryIfNeeded { [self.host expireInlineOverflowEntryIfNeeded]; }
- (void)hideInlineOverflowEntryForExpandedReading { [self.inlineOverflowPanel orderOut:nil];self.inlineOverflowPanel.ignoresMouseEvents=YES; }
- (BOOL)inlineOverflowEntryIsVisible { return self.inlineOverflowPanel.isVisible; }
- (void)orderInlineOverflowEntryFront { [self.inlineOverflowPanel orderFrontRegardless]; }
- (void)setInlineOverflowEntryIgnoresMouseEvents:(BOOL)value { self.inlineOverflowPanel.ignoresMouseEvents=value; }
- (void)closeInlineOverflowEntryPanel { [self.inlineOverflowPanel close]; }
- (id)inlineOverflowActionTarget { return self.host; }
- (NSColor *)inlineOverflowChooserInkColor { return FYAdventureColor(@"ink"); }
- (NSColor *)inlineOverflowChooserCreamColor { return FYAdventureColor(@"cream"); }
- (NSColor *)inlineOverflowChooserLineColor { return FYAdventureColor(@"line"); }
- (id)installInlineOverflowMonitorWithHandler:(NSEvent *(^)(NSEvent *))handler { return [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:handler]; }
- (void)removeInlineOverflowMonitor:(id)monitor { [NSEvent removeMonitor:monitor]; }


@synthesize expandedReadingController = _expandedReadingController;
@dynamic inlineExpandedReadingPanel, inlineExpandedReadingKeyMonitor, inlineExpandedReadingBlockID, inlineExpandedMissingFrames;
- (FYInlineExpandedReadingController *)expandedReadingController { if(!_expandedReadingController){_expandedReadingController=[FYInlineExpandedReadingController new];}return _expandedReadingController; }
- (NSPanel *)inlineExpandedReadingPanel { return self.expandedReadingController.inlineExpandedReadingPanel; }
- (void)setInlineExpandedReadingPanel:(NSPanel *)value { self.expandedReadingController.inlineExpandedReadingPanel=value; }
- (id)inlineExpandedReadingKeyMonitor { return self.expandedReadingController.inlineExpandedReadingKeyMonitor; }
- (void)setInlineExpandedReadingKeyMonitor:(id)value { self.expandedReadingController.inlineExpandedReadingKeyMonitor=value; }
- (NSString *)inlineExpandedReadingBlockID { return self.expandedReadingController.inlineExpandedReadingBlockID; }
- (void)setInlineExpandedReadingBlockID:(NSString *)value { self.expandedReadingController.inlineExpandedReadingBlockID=value; }
- (NSUInteger)inlineExpandedMissingFrames { return self.expandedReadingController.inlineExpandedMissingFrames; }
- (void)setInlineExpandedMissingFrames:(NSUInteger)value { self.expandedReadingController.inlineExpandedMissingFrames=value; }
- (NSSize)expandedInlineReadingSizeForTranslation:(NSString *)translation viewport:(NSRect)viewport { return [self.expandedReadingController expandedInlineReadingSizeForTranslation:translation viewport:viewport source:self]; }
- (void)refreshExpandedInlineReadingCardAppearanceInRect:(NSRect)viewport { [self.expandedReadingController refreshExpandedInlineReadingCardAppearanceInRect:viewport source:self]; }
- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item translation:(NSString *)translation stableBlockID:(NSString *)stableBlockID { [self.expandedReadingController openFullInlineReadingCardForItem:item translation:translation stableBlockID:stableBlockID source:self]; }
- (void)repositionExpandedInlineReadingCardInRect:(NSRect)viewport { [self.expandedReadingController repositionExpandedInlineReadingCardInRect:viewport source:self]; }
- (void)advanceExpandedReadingState { [self.expandedReadingController advanceExpandedReadingStateWithSource:self]; }
- (void)closeExpandedInlineReadingCard { [self.expandedReadingController closeExpandedInlineReadingCardWithSource:self]; }
- (id)installInlineExpandedReadingMonitorWithHandler:(NSEvent *(^)(NSEvent *))handler { return [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:handler]; }
- (void)removeInlineExpandedReadingMonitor:(id)monitor { [NSEvent removeMonitor:monitor]; }


@synthesize selectionCoordinator = _selectionCoordinator;
@synthesize cardActionBinder = _cardActionBinder;
- (FYInlineSelectionCoordinator *)selectionCoordinator { if(!_selectionCoordinator){_selectionCoordinator=[FYInlineSelectionCoordinator new];}return _selectionCoordinator; }
- (FYInlineCardActionBinder *)cardActionBinder { if(!_cardActionBinder){_cardActionBinder=[FYInlineCardActionBinder new];}return _cardActionBinder; }
- (NSUInteger)inlineSnapshotInputEpoch { return self.captureCardInput.sessionEpoch; }
- (NSString *)inlineBlockIdentityForItem:(OCRTextItem *)item { return [self.selectionCoordinator inlineBlockIdentityForItem:item]; }
- (BOOL)inlineBlockID:(NSString *)stableBlockID isSelectedForItem:(OCRTextItem *)item { return [self.selectionCoordinator inlineBlockID:stableBlockID isSelectedForItem:item stateSource:self]; }
- (BOOL)inlineBlockIsSelectedForItem:(OCRTextItem *)item { return [self.selectionCoordinator inlineBlockIsSelectedForItem:item stateSource:self]; }
- (BOOL)inlineHostBlockID:(NSString *)stableBlockID isSelectedForItem:(OCRTextItem *)item { return [self.host inlineBlockID:stableBlockID isSelectedForItem:item]; }
- (FYInlineBlockSnapshot *)inlineSnapshotForItem:(OCRTextItem *)item translation:(NSString *)translation stableBlockID:(NSString *)stableBlockID { return [self.selectionCoordinator inlineSnapshotForItem:item translation:translation stableBlockID:stableBlockID source:self]; }
- (FYInlineBlockSnapshot *)inlineSnapshotForBlock:(FYInlineTextBlock *)block translation:(NSString *)translation stableBlockID:(NSString *)stableBlockID { return [self.selectionCoordinator inlineSnapshotForBlock:block translation:translation stableBlockID:stableBlockID source:self]; }
- (void)wireInlineLongCardPanel:(NSPanel *)panel item:(OCRTextItem *)item translation:(NSString *)translation frame:(NSRect)frame stableBlockID:(NSString *)stableBlockID { [self.cardActionBinder wireInlineLongCardPanel:panel item:item translation:translation frame:frame stableBlockID:stableBlockID source:self]; }


@synthesize manualPlacementCoordinator = _manualPlacementCoordinator;
@synthesize dragController = _dragController;
@dynamic inlineManualOffsets, inlineManualOffsetAge, inlineDraggingPanel, inlineModifierTimer, inlineOptionDragArmed;
- (FYInlineManualPlacementCoordinator *)manualPlacementCoordinator { if(!_manualPlacementCoordinator){_manualPlacementCoordinator=[FYInlineManualPlacementCoordinator new];}return _manualPlacementCoordinator; }
- (FYInlineDragController *)dragController { if(!_dragController){_dragController=[FYInlineDragController new];}return _dragController; }
- (NSMutableDictionary<NSString *,NSValue *> *)inlineManualOffsets { return self.manualPlacementCoordinator.inlineManualOffsets; }
- (void)setInlineManualOffsets:(NSMutableDictionary<NSString *,NSValue *> *)value { self.manualPlacementCoordinator.inlineManualOffsets=value; }
- (NSMutableDictionary<NSString *,NSNumber *> *)inlineManualOffsetAge { return self.manualPlacementCoordinator.inlineManualOffsetAge; }
- (void)setInlineManualOffsetAge:(NSMutableDictionary<NSString *,NSNumber *> *)value { self.manualPlacementCoordinator.inlineManualOffsetAge=value; }
- (NSPanel *)inlineDraggingPanel { return self.dragController.inlineDraggingPanel; }
- (void)setInlineDraggingPanel:(NSPanel *)value { self.dragController.inlineDraggingPanel=value; }
- (NSTimer *)inlineModifierTimer { return self.dragController.inlineModifierTimer; }
- (void)setInlineModifierTimer:(NSTimer *)value { self.dragController.inlineModifierTimer=value; }
- (BOOL)inlineOptionDragArmed { return self.dragController.inlineOptionDragArmed; }
- (void)setInlineOptionDragArmed:(BOOL)value { self.dragController.inlineOptionDragArmed=value; }
- (NSString *)inlineManualOffsetKeyForText:(NSString *)text normalizedBox:(CGRect)box { return [self.manualPlacementCoordinator inlineManualOffsetKeyForText:text normalizedBox:box]; }
- (NSValue *)inlineManualOffsetForText:(NSString *)text normalizedBox:(CGRect)box { return [self.manualPlacementCoordinator inlineManualOffsetForText:text normalizedBox:box stateSource:self]; }
- (void)recordInlineManualOffsetForPanel:(NSPanel *)panel { [self.manualPlacementCoordinator recordInlineManualOffsetForPanel:panel stateSource:self nativeActions:self]; }
- (void)maintainInlineManualOffsetsForPlacements:(NSArray<FYInlinePlacement *> *)placements { [self.manualPlacementCoordinator maintainOffsetsForPlacements:placements stateSource:self]; }
- (void)clearInlineDraggingPanel { self.inlineDraggingPanel=nil; }
- (NSString *)identifierForManualInlinePanel:(NSPanel *)panel { return panel.identifier; }
- (CGRect)frameForManualInlinePanel:(NSPanel *)panel { return panel.frame; }
- (void)setManualInlinePanel:(NSPanel *)panel frame:(CGRect)frame display:(BOOL)display { [panel setFrame:frame display:display]; }
- (FYInlineLayoutResult *)currentLayoutForManualPlacement { return self.lastInlineLayoutResult; }
- (void)recordInlineManualDiagnosticText:(NSString *)text offset:(CGSize)offset { FuyiDiagLog(@"    INLINE-MANUAL <%@> offset=(%.0f,%.0f)", FYDiagTextLength(text), offset.width, offset.height); }
- (void)wireInlinePanelDrag:(NSPanel *)panel placement:(FYInlinePlacement *)placement { [self.dragController wireInlinePanelDrag:panel placement:placement stateSource:self]; }
- (void)startInlineModifierMonitor { [self.dragController startInlineModifierMonitorWithSource:self timerActions:self]; }
- (void)stopInlineModifierMonitor { [self.dragController stopInlineModifierMonitorWithSource:self]; }
- (void)applyInlineDragMode:(BOOL)armed { [self.dragController applyInlineDragMode:armed stateSource:self]; }
- (NSTimer *)scheduledInlineModifierTimer { return [NSTimer scheduledTimerWithTimeInterval:0.1
                                                               target:self.host
                                                             selector:@selector(inlineModifierTick:)
                                                             userInfo:nil
                                                              repeats:YES]; }


- (NSDictionary *)currentInlineLayoutDebugContext { return FYCurrentLayoutDebug(); }
- (BOOL)inlineLayoutDiagnosticsActive { return [FYInlineLayoutDebug shared].isActive; }
- (BOOL)inlinePanelHasLongCardContent:(NSPanel *)panel { return [panel.contentView isKindOfClass:FYInlineLongCardView.class]; }
- (void)closeInlinePanel:(NSPanel *)panel { [panel close]; }
- (void)setInlinePanel:(NSPanel *)panel identifier:(NSString *)identity { panel.identifier=identity; }
- (void)updateInlineLongCardSelectedBadgeForPanel:(NSPanel *)panel {
                FYInlineLongCardView *card = [panel.contentView isKindOfClass:FYInlineLongCardView.class]
                    ? (FYInlineLongCardView *)panel.contentView : nil;
                if (card) { card.showsSelectedBadge = [self.inlineBlockSnapshot.blockID isEqualToString:panel.identifier]; }
}
- (void)recordInlineRenderInputCount:(NSUInteger)count { FuyiDiagLog(@"  RENDER in=%lu panels", (unsigned long)count); }
- (void)recordInlineUnplaceableDiagnosticForItem:(OCRTextItem *)item placement:(FYInlinePlacement *)placement viewport:(NSRect)windowFrame {
FuyiDiagLog(@"    UNPLACEABLE <%@> srcFrame=(%.0f,%.0f,%.0f,%.0f) longCard=(%.0fx%.0f) compactEntry=(%.0fx%.0f) viewport=(%.0f,%.0f,%.0f,%.0f) reason=<%@> rejected=[%@]",
                        Shorten(item.text, 24),
                        placement.sourceFrame.origin.x, placement.sourceFrame.origin.y,
                        placement.sourceFrame.size.width, placement.sourceFrame.size.height,
                        placement.longCardSize.width, placement.longCardSize.height,
                        placement.compactEntrySize.width, placement.compactEntrySize.height,
                        windowFrame.origin.x, windowFrame.origin.y, NSWidth(windowFrame), NSHeight(windowFrame),
                        placement.reason,
                        [placement.rejectedCandidates componentsJoinedByString:@" | "] ?: @"");
}
- (void)recordInlinePlacedPanelDiagnostics:(NSPanel *)panel item:(OCRTextItem *)item placement:(FYInlinePlacement *)placement {
        if (placement.mode == FYInlineDisplayModeCompactEntry) {
            FuyiDiagLog(@"    COMPACT-ENTRY src=<%@> longCard=(%.0fx%.0f) entry=(%.0fx%.0f) anchor=%ld panel=(%.0f,%.0f,%.0f,%.0f) reason=%@",
                        Shorten(item.text, 24),
                        placement.longCardSize.width, placement.longCardSize.height,
                        placement.compactEntrySize.width, placement.compactEntrySize.height,
                        (long)placement.anchor,
                        panel.frame.origin.x, panel.frame.origin.y, NSWidth(panel.frame), NSHeight(panel.frame),
                        placement.reason);
        }
        FuyiDiagLog(@"    PANEL src=<%@> box=(%.3f,%.3f,%.3f,%.3f) srcFrame=(%.0f,%.0f,%.0f,%.0f) mode=%ld font=%.2f anchor=%ld panel=(%.0f,%.0f,%.0f,%.0f) reason=%@",
                    Shorten(item.text, 24),
                    item.boundingBox.origin.x, item.boundingBox.origin.y,
                    item.boundingBox.size.width, item.boundingBox.size.height,
                    placement.sourceFrame.origin.x, placement.sourceFrame.origin.y,
                    placement.sourceFrame.size.width, placement.sourceFrame.size.height,
                    (long)placement.mode, placement.font.pointSize, (long)placement.anchor,
                    panel.frame.origin.x, panel.frame.origin.y, NSWidth(panel.frame), NSHeight(panel.frame),
                    placement.reason);
}
- (void)recordInlineCardVariantDiagnostic:(FYInlinePlacement *)placement {
FuyiDiagLog(@"    CARD-VARIANTS <%@> 块=%@",
                    Shorten([placement.block.text stringByReplacingOccurrencesOfString:@"\n" withString:@" "], 20),
                    [placement.variantDiagnostics componentsJoinedByString:@" | "]);
}
- (void)startInlineModifierMonitorThroughHost { [self.host startInlineModifierMonitor]; }
- (void)updateInlineOverflowEntryThroughHostWithPlacements:(NSArray<FYInlinePlacement *> *)placements items:(NSDictionary<NSString *,OCRTextItem *> *)items viewport:(NSRect)viewport unplaceable:(NSUInteger)unplaceable {
    [self.host updateInlineOverflowEntryWithPlacements:placements items:items viewport:viewport unplaceable:unplaceable];
}

- (instancetype)initWithHost:(id<FYInlineOverlayControllerHost>)host {
    if ((self = [super init])) { _host = host; }
    return self;
}

// Peer adapters preserve a single source of state and injectable host boundaries.
- (NSSlider *)batchFontSizeSlider { return self.host.batchFontSizeSlider; }
- (void)setBatchFontSizeSlider:(NSSlider *)value { self.host.batchFontSizeSlider = value; }
- (NSSlider *)batchHeightSlider { return self.host.batchHeightSlider; }
- (void)setBatchHeightSlider:(NSSlider *)value { self.host.batchHeightSlider = value; }
- (NSColorWell *)batchTextColorWell { return self.host.batchTextColorWell; }
- (void)setBatchTextColorWell:(NSColorWell *)value { self.host.batchTextColorWell = value; }
- (NSSegmentedControl *)batchThemeControl { return self.host.batchThemeControl; }
- (void)setBatchThemeControl:(NSSegmentedControl *)value { self.host.batchThemeControl = value; }
- (NSSlider *)batchWidthSlider { return self.host.batchWidthSlider; }
- (void)setBatchWidthSlider:(NSSlider *)value { self.host.batchWidthSlider = value; }
- (NSSlider *)captionOpacitySlider { return self.host.captionOpacitySlider; }
- (void)setCaptionOpacitySlider:(NSSlider *)value { self.host.captionOpacitySlider = value; }
- (NSPanel *)captionPanel { return self.host.captionPanel; }
- (void)setCaptionPanel:(NSPanel *)value { self.host.captionPanel = value; }
- (FYCaptureCardInput *)captureCardInput { return self.host.captureCardInput; }
- (void)setCaptureCardInput:(FYCaptureCardInput *)value { self.host.captureCardInput = value; }
- (NSInteger)geometryGeneration { return self.host.geometryGeneration; }
- (void)setGeometryGeneration:(NSInteger)value { self.host.geometryGeneration = value; }
- (FYInlineBlockSnapshot *)inlineBlockSnapshot { return self.host.inlineBlockSnapshot; }
- (void)setInlineBlockSnapshot:(FYInlineBlockSnapshot *)value { self.host.inlineBlockSnapshot = value; }
- (FYInlineOCRFrameStabilizer *)inlineFrameStabilizer { return self.host.inlineFrameStabilizer; }
- (void)setInlineFrameStabilizer:(FYInlineOCRFrameStabilizer *)value { self.host.inlineFrameStabilizer = value; }
- (BOOL)inlineGeometryPending { return self.host.inlineGeometryPending; }
- (void)setInlineGeometryPending:(BOOL)value { self.host.inlineGeometryPending = value; }
- (NSInteger)inlineOCRPendingCount { return self.host.inlineOCRPendingCount; }
- (void)setInlineOCRPendingCount:(NSInteger)value { self.host.inlineOCRPendingCount = value; }
- (NSString *)inlineOCRPendingText { return self.host.inlineOCRPendingText; }
- (void)setInlineOCRPendingText:(NSString *)value { self.host.inlineOCRPendingText = value; }
- (NSString *)lastDisplayGeometryToken { return self.host.lastDisplayGeometryToken; }
- (void)setLastDisplayGeometryToken:(NSString *)value { self.host.lastDisplayGeometryToken = value; }

- (void)refreshInlineTranslationList { [self.host refreshInlineTranslationList]; }
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot { [self.host openInlineLearningWithSnapshot:snapshot]; }
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color { return [self.host label:text font:font color:color]; }
- (NSTextField *)mutedLabel:(NSString *)text { return [self.host mutedLabel:text]; }
- (void)refreshOverlayVisibility:(id)sender { [self.host refreshOverlayVisibility:sender]; }
- (BOOL)captureCardInputEnabled { return [self.host captureCardInputEnabled]; }
- (FYInlineTextBlock *)inlineLayoutBlockForItem:(OCRTextItem *)item order:(NSInteger)order { return [self.host inlineLayoutBlockForItem:item order:order]; }
- (NSRect)appKitFrameForOCRItem:(OCRTextItem *)item inWindowFrame:(NSRect)windowFrame { return [self.host appKitFrameForOCRItem:item inWindowFrame:windowFrame]; }
- (uint32_t)displayTargetWindowID { return [self.host displayTargetWindowID]; }
- (WindowItem *)displayTargetWindowItem { return [self.host displayTargetWindowItem]; }
- (NSRect)appKitFrameForWindowItem:(WindowItem *)item { return [self.host appKitFrameForWindowItem:item]; }
- (BOOL)inlinePlacementRect:(NSRect *)outRect reason:(NSString **)outReason { return [self.host inlinePlacementRect:outRect reason:outReason]; }
- (void)clearInlineTranslationPanels {
    [[FYInlineLayoutDebug shared] clearOverlay];
    self.lastInlineLayoutDebugContext=nil;
    [self.batchAppearanceTimer invalidate];
    self.batchAppearanceTimer = nil;
    [self closeExpandedInlineReadingCard];
    for (NSPanel *panel in self.inlineTranslationPanels) {
        [panel close];
    }
    for (NSPanel *panel in self.inlineLongCardPanels) {
        [panel close];
    }
    [self.inlineTranslationPanels removeAllObjects];
    [self.inlineLongCardPanels removeAllObjects];
    [self.inlinePanelsByBlockID removeAllObjects];
    // 面板已经清掉，"上一帧渲染过的内容"也一起作废：否则几何复核会拿旧窗口/旧页面的
    // 译文按新几何重排出来（换窗口后闪现上一条译文）。
    self.lastInlineRenderedTranslations = nil;
    self.lastInlineRenderedItems = nil;
    [self.inlineFrameStabilizer reset];
    self.lastInlineLayoutBoxes = nil;
    self.lastInlineLayoutContentKey = nil;
    self.lastInlineLayoutGeometryKey = nil;
    self.inlineOCRPendingText = nil;
    self.inlineOCRPendingCount = 0;
    self.lastInlineRenderGeometryToken = nil;
    // 边缘入口「还有 N 条译文」属于上一帧的场景，一起收掉。
    [self.inlineOverflowPanel close];
    self.inlineOverflowPanel = nil;
    self.inlineOverflowEntries = @[];
    self.inlineOverflowCount = 0;
    self.inlineOverflowPanelCount = 0;
    self.inlineOverflowCandidateFrames = 0;
    self.inlineOverflowEmptySince = 0;
    [self closeInlineOverflowChoice];
    // 画面换页/停止/切换窗口时清掉手动位置：绝不把偏移继承给其它块或下一场景。
    [self.inlineManualOffsets removeAllObjects];
    [self.inlineManualOffsetAge removeAllObjects];
    [self.inlineStableBlockIDs removeAllObjects];
    self.inlineDraggingPanel = nil;
    [self stopInlineModifierMonitor];
    self.lastInlineLayoutResult = nil;
    self.lastInlineUnplaceableCount = 0;
    self.lastInlineCompactEntryCount = 0;
    self.lastInlineTranslationKey = nil;
    [self closeExpandedInlineReadingCard];
    [self refreshInlineTranslationList];
}





- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items {
    WindowItem *window = [self displayTargetWindowItem];
    if (!window) { return; }
    [self.host showInlineTranslations:translations forItems:items placementRect:[self appKitFrameForWindowItem:window]];
}

- (void)recordInlineLayoutDebug:(FYInlineLayoutResult *)result previous:(FYInlineLayoutResult *)previous viewport:(NSRect)viewport reason:(NSString *)reason {
    FYInlineLayoutDebug *debug=[FYInlineLayoutDebug shared];
    NSDictionary *context=FYCurrentLayoutDebug() ?: self.lastInlineLayoutDebugContext;
    if (!context || !debug.isActive || !result || NSWidth(viewport)<2) return;
    NSMutableDictionary *rendered=[NSMutableDictionary dictionary];
    NSMutableDictionary *renderImages=[NSMutableDictionary dictionary];
    for (FYInlinePlacement *p in result.visiblePlacements) {
        NSPanel *panel=self.inlinePanelsByBlockID[p.blockID]; if(!panel) continue;
        [panel.contentView layoutSubtreeIfNeeded];
        NSBitmapImageRep *bitmap=[panel.contentView bitmapImageRepForCachingDisplayInRect:panel.contentView.bounds];
        if (bitmap) {
            [panel.contentView cacheDisplayInRect:panel.contentView.bounds toBitmapImageRep:bitmap];
            NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            if(png) renderImages[p.blockID]=png;
        }
        NSMutableDictionary *actual=[@{@"panel_frame":FYLayoutDebugRect(panel.frame),
            @"content_size":@[@(NSWidth(panel.contentView.bounds)),@(NSHeight(panel.contentView.bounds))],
            @"backing_scale":@(panel.backingScaleFactor), @"visible":@(panel.isVisible), @"pixels_captured":@(renderImages[p.blockID]!=nil)} mutableCopy];
        for (NSView *child in panel.contentView.subviews) {
            NSTextField *label=nil;
            if ([child isKindOfClass:NSScrollView.class]) {
                NSScrollView *scroll=(NSScrollView *)child;
                actual[@"body_viewport"]=FYLayoutDebugRect(scroll.frame);
                if ([scroll.documentView isKindOfClass:NSTextField.class]) label=(NSTextField *)scroll.documentView;
            } else if ([child isKindOfClass:NSTextField.class] && p.mode==FYInlineDisplayModeShortLabel) label=(NSTextField *)child;
            if(label) {
                NSSize measured=[label.cell cellSizeForBounds:NSMakeRect(0,0,NSWidth(label.bounds),CGFLOAT_MAX)];
                actual[@"label_frame"]=FYLayoutDebugRect(label.frame);
                actual[@"cell_size"]=@[@(measured.width),@(measured.height)];
                actual[@"font_size"]=@(label.font.pointSize);
                actual[@"font_name"]=label.font.fontName ?: @"";
            }
        }
        rendered[p.blockID]=actual;
    }
    NSMutableDictionary *snapshot=[FYLayoutDebugSnapshot(result,previous,viewport,rendered,reason) mutableCopy];
    snapshot[@"layout_geometry_generation"]=@(self.geometryGeneration);
    snapshot[@"layout_target_id"]=@([self displayTargetWindowID]);
    [debug recordLayout:snapshot context:context renderedImages:renderImages];
}













- (void)closeInlineOverflowChoiceAction:(id)sender {
    [self closeInlineOverflowChoice];
}



















- (void)inlineModifierTick:(NSTimer *)timer {
    BOOL option = (NSEvent.modifierFlags & NSEventModifierFlagOption) != 0;
    [self applyInlineDragMode:option];
}



















- (void)applyInlineLongCardBody:(NSString *)translation toLabel:(NSTextField *)label cardWidth:(CGFloat)cardWidth {
    [self applyInlineLongCardBody:translation toLabel:label cardWidth:cardWidth placement:nil];
}



- (NSView *)inlineLongCardContentForTranslation:(NSString *)translation size:(NSSize)size selected:(BOOL)selected compact:(BOOL)compact {
    return [self inlineLongCardContentForTranslation:translation size:size selected:selected compact:compact placement:nil];
}



- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(NSRect)frame translation:(NSString *)translation {
    return [self inlinePlacementForLongCardFrame:frame translation:translation expandedReading:NO];
}



- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame {
    return [self inlineLongPanelForTranslation:translation item:item frame:frame
                                     placement:[self inlinePlacementForLongCardFrame:frame translation:translation]];
}



- (void)updateInlineLongCard:(NSPanel *)panel translation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame {
    [self updateInlineLongCard:panel translation:translation item:item frame:frame compact:NO placement:nil];
}

- (void)updateInlineLongCard:(NSPanel *)panel translation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame compact:(BOOL)compact {
    [self updateInlineLongCard:panel translation:translation item:item frame:frame compact:compact placement:nil];
}





- (FYInlineBlockSnapshot *)inlineSnapshotForItem:(OCRTextItem *)item translation:(NSString *)translation {
    return [self inlineSnapshotForItem:item translation:translation stableBlockID:nil];
}





- (void)wireInlineLongCardPanel:(NSPanel *)panel item:(OCRTextItem *)item translation:(NSString *)translation frame:(NSRect)frame {
    [self.host wireInlineLongCardPanel:panel item:item translation:translation frame:frame stableBlockID:nil];
}



- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item translation:(NSString *)translation {
    [self openFullInlineReadingCardForItem:item translation:translation stableBlockID:nil];
}













- (void)hideOtherInlinePanelsForExpandedReading:(NSPanel *)expandedPanel {
    for (NSPanel *panel in [self allInlineOverlayPanels]) {
        if (panel == expandedPanel) { continue; }
        if (panel.isVisible) { [panel orderOut:nil]; }
        panel.ignoresMouseEvents = YES;
    }
}

- (NSArray<NSPanel *> *)inlinePanelsPresentInCurrentLayout {
    NSMutableSet<NSString *> *liveIDs = [NSMutableSet set];
    for (FYInlinePlacement *placement in self.lastInlineLayoutResult.placements) {
        if (placement.mode == FYInlineDisplayModeUnplaceable) { continue; }
        if (placement.translationFrame.size.width < 2) { continue; }
        if (placement.blockID.length > 0) { [liveIDs addObject:placement.blockID]; }
    }
    NSMutableArray<NSPanel *> *panels = [NSMutableArray array];
    for (NSPanel *panel in [self allInlineOverlayPanels]) {
        if (panel == self.inlineExpandedReadingPanel) { continue; }
        if (panel.identifier.length > 0 && [liveIDs containsObject:panel.identifier]) { [panels addObject:panel]; }
    }
    return panels;
}

- (NSArray<NSPanel *> *)allInlineOverlayPanels {
    NSMutableArray<NSPanel *> *panels = [[self.inlineTranslationPanels arrayByAddingObjectsFromArray:self.inlineLongCardPanels] mutableCopy];
    if (self.inlineOverflowPanel) { [panels addObject:self.inlineOverflowPanel]; }
    if (self.inlineOverflowChoicePanel) { [panels addObject:self.inlineOverflowChoicePanel]; }
    return panels;
}

- (void)restoreOtherInlinePanelsAfterExpandedReading {
    for (NSPanel *panel in [self inlinePanelsPresentInCurrentLayout]) {
        panel.ignoresMouseEvents = NO;
    }
    if (self.inlineOverflowPanel) {
        self.inlineOverflowPanel.ignoresMouseEvents = NO;
        if (self.inlineOverflowCount > 0) { [self.inlineOverflowPanel orderFrontRegardless]; }
    }
    [self refreshOverlayVisibility:nil];
}

- (FYInlineLayoutEngine *)inlineLayoutEngine {
    if (!_inlineLayoutEngine) {
        FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
        engine.fontProvider = ^NSFont *(CGFloat size, NSFontWeight weight) {
            return FYUIFont(size, weight);
        };
        _inlineLayoutEngine = engine;
    }
    return _inlineLayoutEngine;
}

- (void)applyBatchAppearanceToLayoutEngine {
    FYInlineLayoutEngine *engine = [self inlineLayoutEngine];
    CGFloat size = self.batchFontSizeSlider ? self.batchFontSizeSlider.doubleValue : 16;
    CGFloat width = self.batchWidthSlider ? self.batchWidthSlider.doubleValue : 560;
    CGFloat height = self.batchHeightSlider ? self.batchHeightSlider.doubleValue : 330;
    engine.shortFontSize = size;
    engine.coverFontSize = size + 1;
    engine.longBodyFontSize = size + 3;
    engine.minimumLongBodyFontSize = MAX((CGFloat)12, size - 1);
    engine.longTitleFontSize = MAX((CGFloat)12, size - 2);
    engine.compactEntryFontSize = MAX((CGFloat)11, size - 3);
    engine.cardMaxWidth = width;
    engine.shortMaxWidth = width * 360.0 / 560.0;
    engine.cardMaxHeight = height;
}

- (CGFloat)inlinePanelFillAlpha {
    NSSlider *slider = self.captionOpacitySlider;
    if (!slider) { return 0.58; }   // 与设置里的默认值一致（测试/极早期调用）
    return MIN(MAX((CGFloat)slider.doubleValue, (CGFloat)0), (CGFloat)1);
}

- (NSColor *)inlinePanelFillColor {
    return FYSubtitleThemeBackground([self inlineThemeIndex], [self inlinePanelFillAlpha]);
}







- (NSColor *)inlinePanelBorderColor {
    return FYSubtitleThemeBorder([self inlineThemeIndex]);
}

- (NSColor *)inlinePanelTextColor {
    return self.batchTextColorWell ? self.batchTextColorWell.color : [self inlineThemeTextColor];
}

- (NSColor *)inlinePanelTitleColor {
    return [[self inlinePanelTextColor] colorWithAlphaComponent:0.82];
}

- (NSFont *)inlinePanelFontOfSize:(CGFloat)size {
    return FYUIFont(size, NSFontWeightRegular);
}

- (NSFont *)inlinePanelFontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
    return FYUIFont(size, weight);
}

- (InlinePanelLayout)inlinePanelLayoutForTranslation:(NSString *)translation
                                          sourceText:(NSString *)sourceText
                                         sourceFrame:(NSRect)sourceFrame
                                         windowFrame:(NSRect)windowFrame {
    return [self inlinePanelLayoutForTranslation:translation
                                      sourceText:sourceText
                                     sourceFrame:sourceFrame
                                     windowFrame:windowFrame
                                   placedFrames:nil
                                   hugTextWidth:NO];
}

- (InlinePanelLayout)inlinePanelLayoutForTranslation:(NSString *)translation
                                          sourceText:(NSString *)sourceText
                                         sourceFrame:(NSRect)sourceFrame
                                         windowFrame:(NSRect)windowFrame
                                       placedFrames:(NSArray<NSValue *> *)placedFrames
                                       hugTextWidth:(BOOL)hugTextWidth {
    // 单块短贴片也走同一个布局引擎：同一份字体/段落样式、同一套候选顺序与边界判定，
    // 不再维护第二套“到处找空位”的算法。
    // placedFrames / hugTextWidth 保留签名兼容；本帧面板之间的冲突由
    // showInlineTranslations: 的统一安排负责（单块调用没有其它障碍物）。
    (void)placedFrames;
    (void)hugTextWidth;
    FYInlineTextBlock *block = [FYInlineTextBlock new];
    block.text = sourceText ?: @"";
    block.kind = FYInlineBlockKindShort;
    block.lineBoxes = @[[NSValue valueWithRect:CGRectMake(0, 0, 1, 1)]];
    block.lineTexts = @[block.text ?: @""];
    block.boundingBox = CGRectMake(0, 0, 1, 1);
    block.blockID = [FYInlineBlockMatcher blockIDForText:block.text lineBoxes:block.lineBoxes];
    FYInlineLayoutRequest *request = [FYInlineLayoutRequest requestWithBlock:block
                                                                translation:translation
                                                                sourceFrame:sourceFrame];
    FYInlineLayoutResult *result = [self.inlineLayoutEngine layoutRequests:@[request]
                                                                  viewport:windowFrame
                                                                  previous:nil];
    FYInlinePlacement *placement = result.placements.firstObject;
    if (placement && placement.mode != FYInlineDisplayModeUnplaceable) {
        return [self inlinePanelLayoutFromPlacement:placement];
    }
    // 极端情况（画面比贴片还小）：退回最小可用排版，不返回空帧。
    InlinePanelLayout layout;
    CGFloat width = MAX((CGFloat)80, MIN(NSWidth(windowFrame) - 16, 240));
    CGFloat height = 28;
    layout.font = [self.inlineLayoutEngine shortBodyFontForCover:NO];
    layout.cornerRadius = 7;
    layout.frame = NSMakeRect(NSMinX(sourceFrame), NSMinY(sourceFrame), width, height);
    layout.labelFrame = NSMakeRect(10, 5, MAX((CGFloat)20, width - 20), MAX((CGFloat)18, height - 10));
    return layout;
}









- (NSPanel *)inlinePanelForTranslation:(NSString *)translation sourceText:(NSString *)sourceText sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame {
    return [self inlinePanelForTranslation:translation
                                sourceText:sourceText
                               sourceFrame:sourceFrame
                               windowFrame:windowFrame
                                    layout:[self inlinePanelLayoutForTranslation:translation
                                                                      sourceText:sourceText
                                                                     sourceFrame:sourceFrame
                                                                     windowFrame:windowFrame]];
}



- (NSInteger)inlineThemeIndex {
    NSInteger index = self.batchThemeControl ? self.batchThemeControl.selectedSegment : 3;
    return index>=0 && index<=3 ? index : 3;
}

- (NSColor *)inlineThemeTextColor { return FYSubtitleThemeText([self inlineThemeIndex]); }

@end
