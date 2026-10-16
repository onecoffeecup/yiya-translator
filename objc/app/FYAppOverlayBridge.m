#import "FYAppDelegateInternal.h"

// Compatibility actions and aliases only; state belongs to the existing owners.
@interface AppDelegate (FYOverlayCompatibility)
@end

@implementation AppDelegate (FYOverlayCompatibility)
- (NSPanel *)captionPanel { return [self subtitlePresenter].captionPanel; }

- (void)setCaptionPanel:(NSPanel *)value { [self subtitlePresenter].captionPanel = value; }

- (NSPanel *)captionAppearancePreviewPanel { return [self subtitlePresenter].captionAppearancePreviewPanel; }

- (void)setCaptionAppearancePreviewPanel:(NSPanel *)value { [self subtitlePresenter].captionAppearancePreviewPanel = value; }

- (FYAdventurePanel *)captionAppearancePreviewContainer { return [self subtitlePresenter].captionAppearancePreviewContainer; }

- (void)setCaptionAppearancePreviewContainer:(FYAdventurePanel *)value { [self subtitlePresenter].captionAppearancePreviewContainer = value; }

- (NSTextField *)captionAppearancePreviewText { return [self subtitlePresenter].captionAppearancePreviewText; }

- (void)setCaptionAppearancePreviewText:(NSTextField *)value { [self subtitlePresenter].captionAppearancePreviewText = value; }

- (NSTextField *)captionAppearancePreviewBrand { return [self subtitlePresenter].captionAppearancePreviewBrand; }

- (void)setCaptionAppearancePreviewBrand:(NSTextField *)value { [self subtitlePresenter].captionAppearancePreviewBrand = value; }

- (NSPanel *)captionDockPanel { return [self subtitlePresenter].captionDockPanel; }

- (void)setCaptionDockPanel:(NSPanel *)value { [self subtitlePresenter].captionDockPanel = value; }

- (BOOL)captionDockHasAnchor { return [self subtitlePresenter].captionDockHasAnchor; }

- (void)setCaptionDockHasAnchor:(BOOL)value { [self subtitlePresenter].captionDockHasAnchor = value; }

- (NSView *)captionContainer { return [self subtitlePresenter].captionContainer; }

- (void)setCaptionContainer:(NSView *)value { [self subtitlePresenter].captionContainer = value; }

- (NSTextField *)captionTextLabel { return [self subtitlePresenter].captionTextLabel; }

- (void)setCaptionTextLabel:(NSTextField *)value { [self subtitlePresenter].captionTextLabel = value; }

- (NSTextField *)captionBrandLabel { return [self subtitlePresenter].captionBrandLabel; }

- (void)setCaptionBrandLabel:(NSTextField *)value { [self subtitlePresenter].captionBrandLabel = value; }

- (NSButton *)captionHideButton { return [self subtitlePresenter].captionHideButton; }

- (void)setCaptionHideButton:(NSButton *)value { [self subtitlePresenter].captionHideButton = value; }

- (BOOL)captionPanelShownByUser { return [self subtitlePresenter].captionPanelShownByUser; }

- (void)setCaptionPanelShownByUser:(BOOL)value { [self subtitlePresenter].captionPanelShownByUser = value; }

- (BOOL)captionSuppressedForUIMode { return [self subtitlePresenter].captionSuppressedForUIMode; }

- (void)setCaptionSuppressedForUIMode:(BOOL)value { [self subtitlePresenter].captionSuppressedForUIMode = value; }

- (void)createCaptionWindow { [[self subtitlePresenter] createCaptionWindow]; }

- (void)showCaptionAppearancePreview:(id)sender { [[self subtitlePresenter] showCaptionAppearancePreview:sender]; }

- (void)updateCaptionAppearancePreview { [[self subtitlePresenter] updateCaptionAppearancePreview]; }

- (void)anchorCaptionDockToCaption { [[self subtitlePresenter] anchorCaptionDockToCaption]; }

- (void)hideCaptionPanel:(id)sender { [[self subtitlePresenter] hideCaptionPanel:sender]; }

- (void)showCaptionPanel:(id)sender { [[self subtitlePresenter] showCaptionPanel:sender]; }

- (void)setCaptionPanelVisibleForUIMode:(BOOL)uiMode { [[self subtitlePresenter] setCaptionPanelVisibleForUIMode:uiMode]; }

- (BOOL)captionPanelShouldBeHidden { return [[self subtitlePresenter] captionPanelShouldBeHidden]; }

- (NSInteger)captionThemeIndex { return [[self subtitlePresenter] captionThemeIndex]; }

- (NSColor *)captionBackgroundColorWithAlpha:(CGFloat)alpha { return [[self subtitlePresenter] captionBackgroundColorWithAlpha:alpha]; }

- (NSColor *)captionThemeTextColor { return [[self subtitlePresenter] captionThemeTextColor]; }

- (NSColor *)captionTextColor { return [[self subtitlePresenter] captionTextColor]; }

- (NSColor *)captionSecondaryTextColor { return [[self subtitlePresenter] captionSecondaryTextColor]; }

- (NSColor *)captionBorderColor { return [[self subtitlePresenter] captionBorderColor]; }

- (void)updateCaptionWindowWithText:(NSString *)text status:(NSString *)status { [[self subtitlePresenter] updateCaptionWindowWithText:text status:status]; }

- (void)setCaptionDisplayText:(NSString *)text { [[self subtitlePresenter] setCaptionDisplayText:text]; }

- (void)updateCaptionAppearance { [[self subtitlePresenter] updateCaptionAppearance]; }

- (void)resizeCaptionWindowForText:(NSString *)text { [[self subtitlePresenter] resizeCaptionWindowForText:text]; }

- (void)toggleCaptionCollapsed:(id)sender { [[self subtitlePresenter] toggleCaptionCollapsed:sender]; }

- (void)createCaptionDock { [[self subtitlePresenter] createCaptionDock]; }

- (NSMutableArray<NSPanel *> *)inlineTranslationPanels { return [self inlineOverlayController].inlineTranslationPanels; }

- (void)setInlineTranslationPanels:(NSMutableArray<NSPanel *> *)value { [self inlineOverlayController].inlineTranslationPanels = value; }

- (NSMutableArray<NSPanel *> *)inlineLongCardPanels { return [self inlineOverlayController].inlineLongCardPanels; }

- (void)setInlineLongCardPanels:(NSMutableArray<NSPanel *> *)value { [self inlineOverlayController].inlineLongCardPanels = value; }

- (NSMutableDictionary<NSString *, NSPanel *> *)inlinePanelsByBlockID { return [self inlineOverlayController].inlinePanelsByBlockID; }

- (void)setInlinePanelsByBlockID:(NSMutableDictionary<NSString *, NSPanel *> *)value { [self inlineOverlayController].inlinePanelsByBlockID = value; }

- (NSMutableDictionary<NSString *, NSValue *> *)inlineManualOffsets { return [self inlineOverlayController].inlineManualOffsets; }

- (void)setInlineManualOffsets:(NSMutableDictionary<NSString *, NSValue *> *)value { [self inlineOverlayController].inlineManualOffsets = value; }

- (NSMutableDictionary<NSString *, NSNumber *> *)inlineManualOffsetAge { return [self inlineOverlayController].inlineManualOffsetAge; }

- (void)setInlineManualOffsetAge:(NSMutableDictionary<NSString *, NSNumber *> *)value { [self inlineOverlayController].inlineManualOffsetAge = value; }

- (NSMutableDictionary<NSString *, NSString *> *)inlineStableBlockIDs { return [self inlineOverlayController].inlineStableBlockIDs; }

- (void)setInlineStableBlockIDs:(NSMutableDictionary<NSString *, NSString *> *)value { [self inlineOverlayController].inlineStableBlockIDs = value; }

- (FYInlineLayoutEngine *)inlineLayoutEngine { return [self inlineOverlayController].inlineLayoutEngine; }

- (void)setInlineLayoutEngine:(FYInlineLayoutEngine *)value { [self inlineOverlayController].inlineLayoutEngine = value; }

- (FYInlineLayoutResult *)lastInlineLayoutResult { return [self inlineOverlayController].lastInlineLayoutResult; }

- (void)setLastInlineLayoutResult:(FYInlineLayoutResult *)value { [self inlineOverlayController].lastInlineLayoutResult = value; }

- (NSDictionary *)lastInlineLayoutDebugContext { return [self inlineOverlayController].lastInlineLayoutDebugContext; }

- (void)setLastInlineLayoutDebugContext:(NSDictionary *)value { [self inlineOverlayController].lastInlineLayoutDebugContext = value; }

- (NSRect)lastInlineLayoutDebugViewport { return [self inlineOverlayController].lastInlineLayoutDebugViewport; }

- (void)setLastInlineLayoutDebugViewport:(NSRect)value { [self inlineOverlayController].lastInlineLayoutDebugViewport = value; }

- (NSUInteger)lastInlineUnplaceableCount { return [self inlineOverlayController].lastInlineUnplaceableCount; }

- (void)setLastInlineUnplaceableCount:(NSUInteger)value { [self inlineOverlayController].lastInlineUnplaceableCount = value; }

- (NSUInteger)lastInlineCompactEntryCount { return [self inlineOverlayController].lastInlineCompactEntryCount; }

- (void)setLastInlineCompactEntryCount:(NSUInteger)value { [self inlineOverlayController].lastInlineCompactEntryCount = value; }

- (NSPanel *)inlineExpandedReadingPanel { return [self inlineOverlayController].inlineExpandedReadingPanel; }

- (void)setInlineExpandedReadingPanel:(NSPanel *)value { [self inlineOverlayController].inlineExpandedReadingPanel = value; }

- (NSString *)inlineExpandedReadingBlockID { return [self inlineOverlayController].inlineExpandedReadingBlockID; }

- (void)setInlineExpandedReadingBlockID:(NSString *)value { [self inlineOverlayController].inlineExpandedReadingBlockID = value; }

- (NSUInteger)inlineExpandedMissingFrames { return [self inlineOverlayController].inlineExpandedMissingFrames; }

- (void)setInlineExpandedMissingFrames:(NSUInteger)value { [self inlineOverlayController].inlineExpandedMissingFrames = value; }

- (id)inlineExpandedReadingKeyMonitor { return [self inlineOverlayController].inlineExpandedReadingKeyMonitor; }

- (void)setInlineExpandedReadingKeyMonitor:(id)value { [self inlineOverlayController].inlineExpandedReadingKeyMonitor = value; }

- (NSPanel *)inlineOverflowPanel { return [self inlineOverlayController].inlineOverflowPanel; }

- (void)setInlineOverflowPanel:(NSPanel *)value { [self inlineOverlayController].inlineOverflowPanel = value; }

- (NSPanel *)inlineOverflowChoicePanel { return [self inlineOverlayController].inlineOverflowChoicePanel; }

- (void)setInlineOverflowChoicePanel:(NSPanel *)value { [self inlineOverlayController].inlineOverflowChoicePanel = value; }

- (NSUInteger)inlineOverflowCount { return [self inlineOverlayController].inlineOverflowCount; }

- (void)setInlineOverflowCount:(NSUInteger)value { [self inlineOverlayController].inlineOverflowCount = value; }

- (NSUInteger)inlineOverflowPanelCount { return [self inlineOverlayController].inlineOverflowPanelCount; }

- (void)setInlineOverflowPanelCount:(NSUInteger)value { [self inlineOverlayController].inlineOverflowPanelCount = value; }

- (NSArray<NSDictionary *> *)inlineOverflowEntries { return [self inlineOverlayController].inlineOverflowEntries; }

- (void)setInlineOverflowEntries:(NSArray<NSDictionary *> *)value { [self inlineOverlayController].inlineOverflowEntries = value; }

- (NSUInteger)inlineOverflowCandidateCount { return [self inlineOverlayController].inlineOverflowCandidateCount; }

- (void)setInlineOverflowCandidateCount:(NSUInteger)value { [self inlineOverlayController].inlineOverflowCandidateCount = value; }

- (NSUInteger)inlineOverflowCandidateFrames { return [self inlineOverlayController].inlineOverflowCandidateFrames; }

- (void)setInlineOverflowCandidateFrames:(NSUInteger)value { [self inlineOverlayController].inlineOverflowCandidateFrames = value; }

- (NSTimeInterval)inlineOverflowEmptySince { return [self inlineOverlayController].inlineOverflowEmptySince; }

- (void)setInlineOverflowEmptySince:(NSTimeInterval)value { [self inlineOverlayController].inlineOverflowEmptySince = value; }

- (id)inlineOverflowChoiceKeyMonitor { return [self inlineOverlayController].inlineOverflowChoiceKeyMonitor; }

- (void)setInlineOverflowChoiceKeyMonitor:(id)value { [self inlineOverlayController].inlineOverflowChoiceKeyMonitor = value; }

- (NSTimer *)inlineModifierTimer { return [self inlineOverlayController].inlineModifierTimer; }

- (void)setInlineModifierTimer:(NSTimer *)value { [self inlineOverlayController].inlineModifierTimer = value; }

- (BOOL)inlineOptionDragArmed { return [self inlineOverlayController].inlineOptionDragArmed; }

- (void)setInlineOptionDragArmed:(BOOL)value { [self inlineOverlayController].inlineOptionDragArmed = value; }

- (NSPanel *)inlineDraggingPanel { return [self inlineOverlayController].inlineDraggingPanel; }

- (void)setInlineDraggingPanel:(NSPanel *)value { [self inlineOverlayController].inlineDraggingPanel = value; }

- (NSArray<NSString *> *)lastInlineRenderedTranslations { return [self inlineOverlayController].lastInlineRenderedTranslations; }

- (void)setLastInlineRenderedTranslations:(NSArray<NSString *> *)value { [self inlineOverlayController].lastInlineRenderedTranslations = value; }

- (NSArray<OCRTextItem *> *)lastInlineRenderedItems { return [self inlineOverlayController].lastInlineRenderedItems; }

- (void)setLastInlineRenderedItems:(NSArray<OCRTextItem *> *)value { [self inlineOverlayController].lastInlineRenderedItems = value; }

- (NSArray<NSValue *> *)lastInlineLayoutBoxes { return [self inlineOverlayController].lastInlineLayoutBoxes; }

- (void)setLastInlineLayoutBoxes:(NSArray<NSValue *> *)value { [self inlineOverlayController].lastInlineLayoutBoxes = value; }

- (NSString *)lastInlineLayoutContentKey { return [self inlineOverlayController].lastInlineLayoutContentKey; }

- (void)setLastInlineLayoutContentKey:(NSString *)value { [self inlineOverlayController].lastInlineLayoutContentKey = value; }

- (NSString *)lastInlineLayoutGeometryKey { return [self inlineOverlayController].lastInlineLayoutGeometryKey; }

- (void)setLastInlineLayoutGeometryKey:(NSString *)value { [self inlineOverlayController].lastInlineLayoutGeometryKey = value; }

- (NSString *)lastInlineRenderGeometryToken { return [self inlineOverlayController].lastInlineRenderGeometryToken; }

- (void)setLastInlineRenderGeometryToken:(NSString *)value { [self inlineOverlayController].lastInlineRenderGeometryToken = value; }

- (NSString *)lastInlineTranslationKey { return [self inlineOverlayController].lastInlineTranslationKey; }

- (void)setLastInlineTranslationKey:(NSString *)value { [self inlineOverlayController].lastInlineTranslationKey = value; }

- (NSTimer *)batchAppearanceTimer { return [self inlineOverlayController].batchAppearanceTimer; }

- (void)setBatchAppearanceTimer:(NSTimer *)value { [self inlineOverlayController].batchAppearanceTimer = value; }

- (void)clearInlineTranslationPanels { [[self inlineOverlayController] clearInlineTranslationPanels]; }

- (NSString *)inlineTranslationIdentityForTranslations:(NSArray<NSString *> *)translations
                                              forItems:(NSArray<OCRTextItem *> *)items { return [[self inlineOverlayController] inlineTranslationIdentityForTranslations:translations forItems:items]; }

- (void)updateInlinePanel:(NSPanel *)panel
              translation:(NSString *)translation
               sourceText:(NSString *)sourceText
              sourceFrame:(NSRect)sourceFrame
              windowFrame:(NSRect)windowFrame
                   layout:(InlinePanelLayout)layout { [[self inlineOverlayController] updateInlinePanel:panel translation:translation sourceText:sourceText sourceFrame:sourceFrame windowFrame:windowFrame layout:layout]; }

- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items { [[self inlineOverlayController] showInlineTranslations:translations forItems:items]; }

- (void)recordInlineLayoutDebug:(FYInlineLayoutResult *)result previous:(FYInlineLayoutResult *)previous viewport:(NSRect)viewport reason:(NSString *)reason { [[self inlineOverlayController] recordInlineLayoutDebug:result previous:previous viewport:viewport reason:reason]; }

- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items placementRect:(NSRect)windowFrame { [[self inlineOverlayController] showInlineTranslations:translations forItems:items placementRect:windowFrame]; }

- (void)updateInlineOverflowEntryWithPlacements:(NSArray<FYInlinePlacement *> *)placements
                                          items:(NSDictionary<NSString *, OCRTextItem *> *)itemsByBlockID
                                       viewport:(NSRect)viewport
                                    unplaceable:(NSUInteger)unplaceable { [[self inlineOverlayController] updateInlineOverflowEntryWithPlacements:placements items:itemsByBlockID viewport:viewport unplaceable:unplaceable]; }

- (void)expireInlineOverflowEntryIfNeeded { [[self inlineOverlayController] expireInlineOverflowEntryIfNeeded]; }

- (void)positionInlineOverflowEntryInViewport:(NSRect)viewport { [[self inlineOverlayController] positionInlineOverflowEntryInViewport:viewport]; }

- (void)buildInlineOverflowEntryForViewport:(NSRect)viewport { [[self inlineOverlayController] buildInlineOverflowEntryForViewport:viewport]; }

- (void)showInlineOverflowChooser { [[self inlineOverlayController] showInlineOverflowChooser]; }

- (void)closeInlineOverflowChoiceAction:(id)sender { [[self inlineOverlayController] closeInlineOverflowChoiceAction:sender]; }

- (NSString *)overflowRowTitleForEntry:(NSDictionary *)entry { return [[self inlineOverlayController] overflowRowTitleForEntry:entry]; }

- (void)openInlineOverflowRow:(NSButton *)sender { [[self inlineOverlayController] openInlineOverflowRow:sender]; }

- (void)closeInlineOverflowChoice { [[self inlineOverlayController] closeInlineOverflowChoice]; }

- (NSString *)inlineManualOffsetKeyForText:(NSString *)text normalizedBox:(CGRect)box { return [[self inlineOverlayController] inlineManualOffsetKeyForText:text normalizedBox:box]; }

- (NSValue *)inlineManualOffsetForText:(NSString *)text normalizedBox:(CGRect)box { return [[self inlineOverlayController] inlineManualOffsetForText:text normalizedBox:box]; }

- (void)recordInlineManualOffsetForPanel:(NSPanel *)panel { [[self inlineOverlayController] recordInlineManualOffsetForPanel:panel]; }

- (void)wireInlinePanelDrag:(NSPanel *)panel placement:(FYInlinePlacement *)placement { [[self inlineOverlayController] wireInlinePanelDrag:panel placement:placement]; }

- (void)startInlineModifierMonitor { [[self inlineOverlayController] startInlineModifierMonitor]; }

- (void)stopInlineModifierMonitor { [[self inlineOverlayController] stopInlineModifierMonitor]; }

- (void)inlineModifierTick:(NSTimer *)timer { [[self inlineOverlayController] inlineModifierTick:timer]; }

- (void)applyInlineDragMode:(BOOL)armed { [[self inlineOverlayController] applyInlineDragMode:armed]; }

- (InlinePanelLayout)inlinePanelLayoutFromPlacement:(FYInlinePlacement *)placement { return [[self inlineOverlayController] inlinePanelLayoutFromPlacement:placement]; }

- (BOOL)inlineBlockID:(NSString *)stableBlockID isSelectedForItem:(OCRTextItem *)item { return [[self inlineOverlayController] inlineBlockID:stableBlockID isSelectedForItem:item]; }

- (BOOL)inlineBlockIsSelectedForItem:(OCRTextItem *)item { return [[self inlineOverlayController] inlineBlockIsSelectedForItem:item]; }

- (NSParagraphStyle *)inlineLongCardBodyStyle { return [[self inlineOverlayController] inlineLongCardBodyStyle]; }

- (NSFont *)inlineLongCardBodyFont { return [[self inlineOverlayController] inlineLongCardBodyFont]; }

- (CGFloat)inlineLongCardBodyLineHeight { return [[self inlineOverlayController] inlineLongCardBodyLineHeight]; }

- (CGFloat)inlineLongCardMinimumHeight { return [[self inlineOverlayController] inlineLongCardMinimumHeight]; }

- (CGFloat)inlineLongCardBodyViewportForHeight:(CGFloat)cardHeight { return [[self inlineOverlayController] inlineLongCardBodyViewportForHeight:cardHeight]; }

- (void)applyInlineLongCardBody:(NSString *)translation toLabel:(NSTextField *)label cardWidth:(CGFloat)cardWidth { [[self inlineOverlayController] applyInlineLongCardBody:translation toLabel:label cardWidth:cardWidth]; }

- (void)applyInlineLongCardBody:(NSString *)translation
                        toLabel:(NSTextField *)label
                       cardWidth:(CGFloat)cardWidth
                       placement:(FYInlinePlacement *)placement { [[self inlineOverlayController] applyInlineLongCardBody:translation toLabel:label cardWidth:cardWidth placement:placement]; }

- (NSView *)inlineLongCardContentForTranslation:(NSString *)translation size:(NSSize)size selected:(BOOL)selected compact:(BOOL)compact { return [[self inlineOverlayController] inlineLongCardContentForTranslation:translation size:size selected:selected compact:compact]; }

- (NSView *)inlineLongCardContentForTranslation:(NSString *)translation
                                           size:(NSSize)size
                                       selected:(BOOL)selected
                                        compact:(BOOL)compact
                                      placement:(FYInlinePlacement *)placement { return [[self inlineOverlayController] inlineLongCardContentForTranslation:translation size:size selected:selected compact:compact placement:placement]; }

- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(NSRect)frame translation:(NSString *)translation { return [[self inlineOverlayController] inlinePlacementForLongCardFrame:frame translation:translation]; }

- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(NSRect)frame translation:(NSString *)translation expandedReading:(BOOL)expandedReading { return [[self inlineOverlayController] inlinePlacementForLongCardFrame:frame translation:translation expandedReading:expandedReading]; }

- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame { return [[self inlineOverlayController] inlineLongPanelForTranslation:translation item:item frame:frame]; }

- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame placement:(FYInlinePlacement *)placement { return [[self inlineOverlayController] inlineLongPanelForTranslation:translation item:item frame:frame placement:placement]; }

- (void)updateInlineLongCard:(NSPanel *)panel translation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame { [[self inlineOverlayController] updateInlineLongCard:panel translation:translation item:item frame:frame]; }

- (void)updateInlineLongCard:(NSPanel *)panel translation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame compact:(BOOL)compact { [[self inlineOverlayController] updateInlineLongCard:panel translation:translation item:item frame:frame compact:compact]; }

- (void)updateInlineLongCard:(NSPanel *)panel
                 translation:(NSString *)translation
                        item:(OCRTextItem *)item
                       frame:(NSRect)frame
                     compact:(BOOL)compact
                   placement:(FYInlinePlacement *)placement { [[self inlineOverlayController] updateInlineLongCard:panel translation:translation item:item frame:frame compact:compact placement:placement]; }

- (NSString *)inlineBlockIdentityForItem:(OCRTextItem *)item { return [[self inlineOverlayController] inlineBlockIdentityForItem:item]; }

- (FYInlineBlockSnapshot *)inlineSnapshotForItem:(OCRTextItem *)item translation:(NSString *)translation { return [[self inlineOverlayController] inlineSnapshotForItem:item translation:translation]; }

- (FYInlineBlockSnapshot *)inlineSnapshotForItem:(OCRTextItem *)item
                                     translation:(NSString *)translation
                                   stableBlockID:(NSString *)stableBlockID { return [[self inlineOverlayController] inlineSnapshotForItem:item translation:translation stableBlockID:stableBlockID]; }

- (FYInlineBlockSnapshot *)inlineSnapshotForBlock:(FYInlineTextBlock *)block
                                      translation:(NSString *)translation
                                    stableBlockID:(NSString *)stableBlockID { return [[self inlineOverlayController] inlineSnapshotForBlock:block translation:translation stableBlockID:stableBlockID]; }

- (void)wireInlineLongCardPanel:(NSPanel *)panel item:(OCRTextItem *)item translation:(NSString *)translation frame:(NSRect)frame { [[self inlineOverlayController] wireInlineLongCardPanel:panel item:item translation:translation frame:frame]; }

- (void)wireInlineLongCardPanel:(NSPanel *)panel
                           item:(OCRTextItem *)item
                    translation:(NSString *)translation
                          frame:(NSRect)frame
                  stableBlockID:(NSString *)stableBlockID { [[self inlineOverlayController] wireInlineLongCardPanel:panel item:item translation:translation frame:frame stableBlockID:stableBlockID]; }

- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item translation:(NSString *)translation { [[self inlineOverlayController] openFullInlineReadingCardForItem:item translation:translation]; }

- (NSSize)expandedInlineReadingSizeForTranslation:(NSString *)translation viewport:(NSRect)viewport { return [[self inlineOverlayController] expandedInlineReadingSizeForTranslation:translation viewport:viewport]; }

- (void)refreshExpandedInlineReadingCardAppearanceInRect:(NSRect)viewport { [[self inlineOverlayController] refreshExpandedInlineReadingCardAppearanceInRect:viewport]; }

- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item
                             translation:(NSString *)translation
                           stableBlockID:(NSString *)stableBlockID { [[self inlineOverlayController] openFullInlineReadingCardForItem:item translation:translation stableBlockID:stableBlockID]; }

- (void)repositionExpandedInlineReadingCardInRect:(NSRect)viewport { [[self inlineOverlayController] repositionExpandedInlineReadingCardInRect:viewport]; }

- (void)advanceExpandedReadingState { [[self inlineOverlayController] advanceExpandedReadingState]; }

- (void)closeExpandedInlineReadingCard { [[self inlineOverlayController] closeExpandedInlineReadingCard]; }

- (void)hideOtherInlinePanelsForExpandedReading:(NSPanel *)expandedPanel { [[self inlineOverlayController] hideOtherInlinePanelsForExpandedReading:expandedPanel]; }

- (NSArray<NSPanel *> *)inlinePanelsPresentInCurrentLayout { return [[self inlineOverlayController] inlinePanelsPresentInCurrentLayout]; }

- (NSArray<NSPanel *> *)allInlineOverlayPanels { return [[self inlineOverlayController] allInlineOverlayPanels]; }

- (void)restoreOtherInlinePanelsAfterExpandedReading { [[self inlineOverlayController] restoreOtherInlinePanelsAfterExpandedReading]; }

- (void)applyBatchAppearanceToLayoutEngine { [[self inlineOverlayController] applyBatchAppearanceToLayoutEngine]; }

- (CGFloat)inlinePanelFillAlpha { return [[self inlineOverlayController] inlinePanelFillAlpha]; }

- (NSColor *)inlinePanelFillColor { return [[self inlineOverlayController] inlinePanelFillColor]; }

- (void)refreshInlinePanelAppearance { [[self inlineOverlayController] refreshInlinePanelAppearance]; }

- (void)applyInlineTextColor:(NSColor *)color toView:(NSView *)view { [[self inlineOverlayController] applyInlineTextColor:color toView:view]; }

- (void)refreshInlinePanelTextAppearance { [[self inlineOverlayController] refreshInlinePanelTextAppearance]; }

- (NSColor *)inlinePanelBorderColor { return [[self inlineOverlayController] inlinePanelBorderColor]; }

- (NSColor *)inlinePanelTextColor { return [[self inlineOverlayController] inlinePanelTextColor]; }

- (NSColor *)inlinePanelTitleColor { return [[self inlineOverlayController] inlinePanelTitleColor]; }

- (NSFont *)inlinePanelFontOfSize:(CGFloat)size { return [[self inlineOverlayController] inlinePanelFontOfSize:size]; }

- (NSFont *)inlinePanelFontOfSize:(CGFloat)size weight:(NSFontWeight)weight { return [[self inlineOverlayController] inlinePanelFontOfSize:size weight:weight]; }

- (InlinePanelLayout)inlinePanelLayoutForTranslation:(NSString *)translation
                                          sourceText:(NSString *)sourceText
                                         sourceFrame:(NSRect)sourceFrame
                                         windowFrame:(NSRect)windowFrame { return [[self inlineOverlayController] inlinePanelLayoutForTranslation:translation sourceText:sourceText sourceFrame:sourceFrame windowFrame:windowFrame]; }

- (InlinePanelLayout)inlinePanelLayoutForTranslation:(NSString *)translation
                                          sourceText:(NSString *)sourceText
                                         sourceFrame:(NSRect)sourceFrame
                                         windowFrame:(NSRect)windowFrame
                                       placedFrames:(NSArray<NSValue *> *)placedFrames
                                       hugTextWidth:(BOOL)hugTextWidth { return [[self inlineOverlayController] inlinePanelLayoutForTranslation:translation sourceText:sourceText sourceFrame:sourceFrame windowFrame:windowFrame placedFrames:placedFrames hugTextWidth:hugTextWidth]; }

- (NSAttributedString *)inlinePanelAttributedText:(NSString *)translation font:(NSFont *)font { return [[self inlineOverlayController] inlinePanelAttributedText:translation font:font]; }

- (void)applyInlineChromeToContent:(NSView *)content cornerRadius:(CGFloat)cornerRadius { [[self inlineOverlayController] applyInlineChromeToContent:content cornerRadius:cornerRadius]; }

- (void)applyInlineCompactEntryChromeToContent:(NSView *)content cornerRadius:(CGFloat)cornerRadius { [[self inlineOverlayController] applyInlineCompactEntryChromeToContent:content cornerRadius:cornerRadius]; }

- (NSTextField *)inlineCompactEntryLabel:(NSString *)text font:(NSFont *)font color:(NSColor *)color { return [[self inlineOverlayController] inlineCompactEntryLabel:text font:font color:color]; }

- (NSPanel *)inlinePanelForTranslation:(NSString *)translation sourceText:(NSString *)sourceText sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame { return [[self inlineOverlayController] inlinePanelForTranslation:translation sourceText:sourceText sourceFrame:sourceFrame windowFrame:windowFrame]; }

- (NSPanel *)inlinePanelForTranslation:(NSString *)translation sourceText:(NSString *)sourceText sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame layout:(InlinePanelLayout)layout { return [[self inlineOverlayController] inlinePanelForTranslation:translation sourceText:sourceText sourceFrame:sourceFrame windowFrame:windowFrame layout:layout]; }

- (NSInteger)inlineThemeIndex { return [[self inlineOverlayController] inlineThemeIndex]; }

- (NSColor *)inlineThemeTextColor { return [[self inlineOverlayController] inlineThemeTextColor]; }
@end
