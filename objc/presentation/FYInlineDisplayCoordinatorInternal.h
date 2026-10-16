#pragma once
#import "FYInlineDisplayCoordinator.h"
#import "FYInlinePanelLayoutTypes.h"
// Native compatibility actions have explicit purposes and no storage. The
// concrete native subclass implements them; the core keeps the original self.
@protocol FYInlineDisplayGeometrySource <NSObject>
@property(nonatomic,weak,readonly) NSPanel *inlineDraggingPanel;
@property(nonatomic) BOOL inlineGeometryPending;
@property(nonatomic,copy,readonly) NSString *lastDisplayGeometryToken;
- (FYInlineLayoutCalculator *)inlineLayoutEngine;
- (uint32_t)displayTargetWindowID;
@end
@protocol FYInlineDisplayInputSource <NSObject>
- (FYInlineTextBlock *)inlineLayoutBlockForItem:(OCRTextItem *)item order:(NSInteger)order;
- (NSRect)appKitFrameForOCRItem:(OCRTextItem *)item inWindowFrame:(NSRect)windowFrame;
- (void)maintainInlineManualOffsetsForPlacements:(NSArray<FYInlinePlacement *> *)placements;
- (NSValue *)inlineManualOffsetForText:(NSString *)text normalizedBox:(CGRect)box;
- (NSString *)inlineManualOffsetKeyForText:(NSString *)text normalizedBox:(CGRect)box;
@end
@protocol FYInlineDisplayPanelActions <NSObject>
- (void)updateInlineLongCardSelectedBadgeForPanel:(NSPanel *)panel;
- (BOOL)inlinePanelHasLongCardContent:(NSPanel *)panel;
- (void)closeInlinePanel:(NSPanel *)panel;
- (void)setInlinePanel:(NSPanel *)panel identifier:(NSString *)identity;
- (void)updateInlineLongCard:(NSPanel *)panel translation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame compact:(BOOL)compact placement:(FYInlinePlacement *)placement;
- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame placement:(FYInlinePlacement *)placement;
- (InlinePanelLayout)inlinePanelLayoutFromPlacement:(FYInlinePlacement *)placement;
- (void)updateInlinePanel:(NSPanel *)panel translation:(NSString *)translation sourceText:(NSString *)sourceText sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame layout:(InlinePanelLayout)layout;
- (NSPanel *)inlinePanelForTranslation:(NSString *)translation sourceText:(NSString *)sourceText sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame layout:(InlinePanelLayout)layout;
- (void)wireInlinePanelDrag:(NSPanel *)panel placement:(FYInlinePlacement *)placement;
@end
@protocol FYInlineDisplayDiagnosticActions <NSObject>
- (NSDictionary *)currentInlineLayoutDebugContext;
- (BOOL)inlineLayoutDiagnosticsActive;
- (void)recordInlineLayoutDebug:(FYInlineLayoutResult *)result previous:(FYInlineLayoutResult *)previous viewport:(NSRect)viewport reason:(NSString *)reason;
- (void)recordInlineRenderInputCount:(NSUInteger)count;
- (void)recordInlineUnplaceableDiagnosticForItem:(OCRTextItem *)item placement:(FYInlinePlacement *)placement viewport:(NSRect)windowFrame;
- (void)recordInlinePlacedPanelDiagnostics:(NSPanel *)panel item:(OCRTextItem *)item placement:(FYInlinePlacement *)placement;
- (void)recordInlineCardVariantDiagnostic:(FYInlinePlacement *)placement;
@end
@protocol FYInlineDisplayCompletionActions <NSObject>
- (void)advanceExpandedReadingState;
- (void)refreshOverlayVisibility:(id)sender;
- (void)refreshInlineTranslationList;
- (void)startInlineModifierMonitorThroughHost;
- (void)updateInlineOverflowEntryThroughHostWithPlacements:(NSArray<FYInlinePlacement *> *)placements items:(NSDictionary<NSString *,OCRTextItem *> *)items viewport:(NSRect)viewport unplaceable:(NSUInteger)unplaceable;
@end
@protocol FYInlineDisplayNativeActions <FYInlineDisplayGeometrySource, FYInlineDisplayInputSource, FYInlineDisplayPanelActions, FYInlineDisplayDiagnosticActions, FYInlineDisplayCompletionActions>
@end
@interface FYInlineDisplayCoordinator (NativeActions) <FYInlineDisplayNativeActions>
@end
