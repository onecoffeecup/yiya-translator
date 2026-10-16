#pragma once
#import <AppKit/AppKit.h>
#import "../FYGrammarActionState.h"
#import "FYInlineBlockSnapshot.h"
@class FYStudyChatView,FYStudyOverlayPanel,FYSelectableSourceTextView,FYStudyChatSession;
@protocol FYStudyChatRenderSource <NSObject>
- (BOOL)chatResolvingSource;
- (NSButton *)inlineReturnButton;
- (void)setInlineReturnButton:(NSButton *)value;
- (FYInlineBlockSnapshot *)inlineReturnSnapshot;
- (FYStudyChatView *)mainStudyChatView;
- (FYStudyChatView *)overlayStudyChatView;
- (FYStudyChatSession *)studyChatSession;
- (NSColor *)uiSurface;
- (void)closeStudyOverlay:(id)sender;
- (void)ensureStudyChatSession;
- (void)referenceLatestStudySentence:(id)sender;
- (void)returnFromStudyChatToInlineLearning:(id)sender;
- (void)sendStudyChat:(NSString *)text;
@end

// Stateless native renderer; the original Study receiver owns every view.
@interface FYStudyChatRenderer : NSObject
+ (FYStudyChatView *)makeStudyChatViewForOverlay:(BOOL)overlay receiver:(id<FYStudyChatRenderSource>)receiver;
+ (void)refreshStudyChatViewsWithReceiver:(id<FYStudyChatRenderSource>)receiver;
+ (void)configureStudyOverlay:(NSPanel *)panel receiver:(id<FYStudyChatRenderSource>)receiver;
+ (void)updateInlineReturnButtonVisibilityWithReceiver:(id<FYStudyChatRenderSource>)receiver;
@end
