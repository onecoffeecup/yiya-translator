#pragma once
#import <AppKit/AppKit.h>
#import "../inline/FYInlineTextModels.h"
#import "../ocr/FYOCRTextModels.h"
#import "FYInlinePanelLayoutTypes.h"
@class FYInlineLayoutEngine;
@protocol FYInlineCardEngineSource <NSObject>
@property(nonatomic,strong,readonly) FYInlineLayoutEngine *inlineLayoutEngine;
@end
@protocol FYInlineCardStyleSource <NSObject>
- (NSParagraphStyle *)inlineLongCardBodyStyle;
- (NSFont *)inlineLongCardBodyFont;
- (CGFloat)inlineLongCardBodyLineHeight;
- (NSColor *)inlinePanelTextColor;
- (NSColor *)inlinePanelTitleColor;
- (NSColor *)inlinePanelFillColor;
- (NSColor *)inlinePanelBorderColor;
- (NSFont *)inlinePanelFontOfSize:(CGFloat)size;
- (NSFont *)inlinePanelFontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
- (NSColor *)inlineCardInkColor;
- (NSColor *)inlineCardMintColor;
- (NSColor *)inlineCardRimColor;
- (NSColor *)inlineCardLineColor;
- (NSString *)inlineCardTitleForBlockText:(NSString *)text;
@end
@protocol FYInlineCardViewActions <NSObject>
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSTextField *)inlineCompactEntryLabel:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (void)applyInlineChromeToContent:(NSView *)content cornerRadius:(CGFloat)radius;
- (void)applyInlineCompactEntryChromeToContent:(NSView *)content cornerRadius:(CGFloat)radius;
- (void)applyInlineLongCardBody:(NSString *)translation toLabel:(NSTextField *)label cardWidth:(CGFloat)width placement:(FYInlinePlacement *)placement;
- (NSView *)inlineLongCardContentForTranslation:(NSString *)translation size:(NSSize)size selected:(BOOL)selected compact:(BOOL)compact placement:(FYInlinePlacement *)placement;
- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(NSRect)frame translation:(NSString *)translation;
- (NSAttributedString *)inlinePanelAttributedText:(NSString *)translation font:(NSFont *)font;
- (void)applyInlineTextColor:(NSColor *)color toView:(NSView *)view;
@end
@protocol FYInlineCardPeerActions <NSObject>
- (BOOL)inlineHostBlockID:(NSString *)identity isSelectedForItem:(OCRTextItem *)item;
- (void)inlineCardWirePanelThroughHost:(NSPanel *)panel item:(OCRTextItem *)item translation:(NSString *)translation frame:(NSRect)frame stableBlockID:(NSString *)stableBlockID;
@end
@protocol FYInlineCardPanelSource <NSObject>
@property(nonatomic,strong,readonly) NSMutableArray<NSPanel *> *inlineTranslationPanels;
@property(nonatomic,strong,readonly) NSMutableArray<NSPanel *> *inlineLongCardPanels;
@property(nonatomic,strong,readonly) NSPanel *inlineExpandedReadingPanel;
@property(nonatomic,strong,readonly) NSPanel *inlineOverflowPanel;
@end
@protocol FYInlineCardRenderSource <FYInlineCardEngineSource,FYInlineCardStyleSource,FYInlineCardViewActions,FYInlineCardPeerActions,FYInlineCardPanelSource>
@end
@interface FYInlineCardRenderer : NSObject
- (InlinePanelLayout)inlinePanelLayoutFromPlacement:(FYInlinePlacement *)placement;
- (NSParagraphStyle *)inlineLongCardBodyStyleWithSource:(id<FYInlineCardRenderSource>)source;
- (NSFont *)inlineLongCardBodyFontWithSource:(id<FYInlineCardRenderSource>)source;
- (CGFloat)inlineLongCardBodyLineHeightWithSource:(id<FYInlineCardRenderSource>)source;
- (CGFloat)inlineLongCardMinimumHeightWithSource:(id<FYInlineCardRenderSource>)source;
- (CGFloat)inlineLongCardBodyViewportForHeight:(CGFloat)cardHeight;
- (void)applyInlineLongCardBody:(NSString *)translation
                        toLabel:(NSTextField *)label
                       cardWidth:(CGFloat)cardWidth
                       placement:(FYInlinePlacement *)placement source:(id<FYInlineCardRenderSource>)source;
- (NSView *)inlineLongCardContentForTranslation:(NSString *)translation
                                           size:(NSSize)size
                                       selected:(BOOL)selected
                                        compact:(BOOL)compact
                                      placement:(FYInlinePlacement *)placement source:(id<FYInlineCardRenderSource>)source;
- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(NSRect)frame translation:(NSString *)translation expandedReading:(BOOL)expandedReading source:(id<FYInlineCardRenderSource>)source;
- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame placement:(FYInlinePlacement *)placement source:(id<FYInlineCardRenderSource>)source;
- (void)updateInlineLongCard:(NSPanel *)panel
                 translation:(NSString *)translation
                        item:(OCRTextItem *)item
                       frame:(NSRect)frame
                     compact:(BOOL)compact
                   placement:(FYInlinePlacement *)placement source:(id<FYInlineCardRenderSource>)source;
- (void)updateInlinePanel:(NSPanel *)panel
              translation:(NSString *)translation
               sourceText:(NSString *)sourceText
              sourceFrame:(NSRect)sourceFrame
              windowFrame:(NSRect)windowFrame
                   layout:(InlinePanelLayout)layout source:(id<FYInlineCardRenderSource>)source;
- (NSAttributedString *)inlinePanelAttributedText:(NSString *)translation font:(NSFont *)font source:(id<FYInlineCardRenderSource>)source;
- (void)applyInlineChromeToContent:(NSView *)content cornerRadius:(CGFloat)cornerRadius source:(id<FYInlineCardRenderSource>)source;
- (void)applyInlineCompactEntryChromeToContent:(NSView *)content cornerRadius:(CGFloat)cornerRadius source:(id<FYInlineCardRenderSource>)source;
- (NSTextField *)inlineCompactEntryLabel:(NSString *)text font:(NSFont *)font color:(NSColor *)color source:(id<FYInlineCardRenderSource>)source;
- (NSPanel *)inlinePanelForTranslation:(NSString *)translation sourceText:(NSString *)sourceText sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame layout:(InlinePanelLayout)layout source:(id<FYInlineCardRenderSource>)source;
- (void)refreshInlinePanelAppearanceWithSource:(id<FYInlineCardRenderSource>)source;
- (void)applyInlineTextColor:(NSColor *)color toView:(NSView *)view source:(id<FYInlineCardRenderSource>)source;
- (void)refreshInlinePanelTextAppearanceWithSource:(id<FYInlineCardRenderSource>)source;
@end
