#pragma once
#import <AppKit/AppKit.h>
#import "FYInlineOverflowCoordinator.h"
@class FYInlineLayoutEngine;
@protocol FYInlineOverflowLayoutSource <NSObject>
@property(nonatomic,strong,readonly) FYInlineLayoutEngine *inlineLayoutEngine;
@property(nonatomic,strong,readonly) NSPanel *captionPanel;
@property(nonatomic,strong,readonly) FYInlineLayoutResult *lastInlineLayoutResult;
- (NSArray<NSPanel *> *)allInlineOverlayPanels;
- (BOOL)inlinePlacementRect:(NSRect *)outRect reason:(NSString **)outReason;
@end
@protocol FYInlineOverflowViewActions <NSObject>
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSTextField *)mutedLabel:(NSString *)text;
- (void)applyInlineChromeToContent:(NSView *)content cornerRadius:(CGFloat)radius;
- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame placement:(FYInlinePlacement *)placement;
- (NSString *)overflowRowTitleForEntry:(NSDictionary *)entry;
- (id)inlineOverflowActionTarget;
- (void)showInlineOverflowChooser;
@end
@protocol FYInlineOverflowThemeActions <NSObject>
- (NSColor *)inlineOverflowChooserInkColor;
- (NSColor *)inlineOverflowChooserCreamColor;
- (NSColor *)inlineOverflowChooserLineColor;
@end
@protocol FYInlineOverflowMonitorActions <NSObject>
- (id)installInlineOverflowMonitorWithHandler:(NSEvent *(^)(NSEvent *))handler;
- (void)removeInlineOverflowMonitor:(id)monitor;
@end
@protocol FYInlineOverflowNativeSource <FYInlineOverflowSource,FYInlineOverflowLayoutSource,FYInlineOverflowViewActions,FYInlineOverflowThemeActions,FYInlineOverflowMonitorActions>
@end
@interface FYInlineOverflowController : FYInlineOverflowCoordinator
@property(nonatomic,strong) NSPanel *inlineOverflowPanel;
@property(nonatomic,strong) NSPanel *inlineOverflowChoicePanel;
@property(nonatomic,strong) id inlineOverflowChoiceKeyMonitor;
- (void)positionInlineOverflowEntryInViewport:(NSRect)viewport source:(id<FYInlineOverflowNativeSource>)source;
- (void)buildInlineOverflowEntryForViewport:(NSRect)viewport source:(id<FYInlineOverflowNativeSource>)source;
- (void)showInlineOverflowListWithSource:(id<FYInlineOverflowNativeSource>)source;
- (void)resizeInlineOverflowEntryWithTitle:(NSString *)title viewport:(NSRect)viewport source:(id<FYInlineOverflowNativeSource>)source;
- (void)closeInlineOverflowChoiceWithSource:(id<FYInlineOverflowNativeSource>)source;
@end
