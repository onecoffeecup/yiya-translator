#pragma once
#import <AppKit/AppKit.h>
#import "FYInlineTranslationListCoordinator.h"
@protocol FYInlineTranslationListViews <NSObject>
@property(nonatomic,strong) NSView *inlineTranslationListCard;
@property(nonatomic,strong) NSTextField *inlineTranslationListCount;
@property(nonatomic,strong) NSStackView *inlineTranslationListStack;
@end
@protocol FYInlineTranslationListFactories <NSObject>
- (NSStackView *)verticalStack;
- (NSStackView *)horizontalStack;
- (NSTextField *)mutedLabel:(NSString *)text;
- (NSView *)spacer;
- (NSScrollView *)makePageScrollWithContent:(NSView *)content;
- (void)pinFullWidth:(NSView *)view toStack:(NSStackView *)stack;
- (NSView *)cardWithStack:(NSStackView *)stack;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
- (NSFont *)inlineTranslationListFontOfSize:(CGFloat)size;
- (NSColor *)uiInk;
- (NSColor *)uiMuted;
@end
@protocol FYInlineTranslationListRenderSource <FYInlineTranslationListStateSource,FYInlineTranslationListViews,FYInlineTranslationListFactories>
@end
@interface FYInlineTranslationListRenderer : NSObject
- (NSView *)makeCardWithReceiver:(id<FYInlineTranslationListRenderSource>)receiver;
- (void)appendRowForPlacement:(FYInlinePlacement *)placement currentSnapshots:(NSArray<FYInlineBlockSnapshot *> *)snapshots receiver:(id<FYInlineTranslationListRenderSource>)receiver;
@end
