#pragma once
#import <AppKit/AppKit.h>
#import "../FYGrammarActionState.h"
#import "FYInlineBlockSnapshot.h"
@class FYStudyChatView,FYStudyOverlayPanel,FYSelectableSourceTextView,FYStudyChatSession;
@protocol FYStudyScrollRenderSource <NSObject>
- (FYStudyOverlayPanel *)quickSentencePanel;
- (CGFloat)quickSentenceScrollOffset;
- (void)setQuickSentenceScrollOffset:(CGFloat)value;
- (NSScrollView *)quickSentenceScrollView;
@end

// Stateless native renderer; the original Study receiver owns every view.
@interface FYStudyScrollRenderer : NSObject
+ (NSScrollView *)quickSentenceScrollViewWithReceiver:(id<FYStudyScrollRenderSource>)receiver;
+ (void)captureQuickSentenceScrollPositionWithReceiver:(id<FYStudyScrollRenderSource>)receiver;
+ (void)restoreQuickSentenceScrollPositionWithReceiver:(id<FYStudyScrollRenderSource>)receiver;
@end
