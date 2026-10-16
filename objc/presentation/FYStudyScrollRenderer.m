#import "FYStudyScrollRenderer.h"
#import "../learning/FYStudyChatView.h"
#import "../learning/FYStudyChatSession.h"
#import "../learning/FYStudyOverlayPanel.h"
#import "../learning/FYLearningViews.h"
#import "FYFlippedDocumentView.h"
#import "FYPresentationText.h"
#import <QuartzCore/QuartzCore.h>

@implementation FYStudyScrollRenderer
+ (NSScrollView *)quickSentenceScrollViewWithReceiver:(id<FYStudyScrollRenderSource>)receiver {
    if (!receiver.quickSentencePanel) { return nil; }
    for (NSView *view in receiver.quickSentencePanel.contentView.subviews) {
        if ([view isKindOfClass:NSScrollView.class]) { return (NSScrollView *)view; }
    }
    return nil;
}

+ (void)captureQuickSentenceScrollPositionWithReceiver:(id<FYStudyScrollRenderSource>)receiver {
    NSScrollView *scroll = [receiver quickSentenceScrollView];
    if (!scroll) { return; }
    receiver.quickSentenceScrollOffset = scroll.contentView.bounds.origin.y;
}

+ (void)restoreQuickSentenceScrollPositionWithReceiver:(id<FYStudyScrollRenderSource>)receiver {
    NSScrollView *scroll = [receiver quickSentenceScrollView];
    if (!scroll) { return; }
    [scroll.documentView layoutSubtreeIfNeeded];
    CGFloat maxY = MAX((CGFloat)0, NSHeight(scroll.documentView.frame) - NSHeight(scroll.contentView.bounds));
    CGFloat y = MIN(MAX((CGFloat)0, receiver.quickSentenceScrollOffset), maxY);
    [scroll.contentView scrollToPoint:NSMakePoint(0, y)];
    [scroll reflectScrolledClipView:scroll.contentView];
}
@end
