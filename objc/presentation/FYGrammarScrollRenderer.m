#import "FYGrammarScrollRenderer.h"
#import "../learning/FYStudyOverlayPanel.h"
@implementation FYGrammarScrollRenderer

+ (CGFloat)structureScrollOffsetForQuick:(BOOL)quick source:(id<FYGrammarScrollSource>)source {
    NSScrollView *scroll = quick ? source.quickStructureScrollView : source.mainStructureScrollView;
    return scroll ? scroll.contentView.bounds.origin.x : 0;
}

+ (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick source:(id<FYGrammarScrollSource>)source {
    if (offset <= 0.5) { return; }
    NSScrollView *scroll = quick ? source.quickStructureScrollView : source.mainStructureScrollView;
    if (!scroll) { return; }
    // 立即在布局完成后恢复（不用延时跳回，避免闪动）。
    [scroll.documentView layoutSubtreeIfNeeded];
    [scroll layoutSubtreeIfNeeded];
    CGFloat maxX = MAX(0, NSWidth(scroll.documentView.frame) - NSWidth(scroll.contentView.bounds));
    CGFloat x = MIN(MAX(offset, 0), maxX);
    [scroll.contentView scrollToPoint:NSMakePoint(x, scroll.contentView.bounds.origin.y)];
    [scroll reflectScrolledClipView:scroll.contentView];
}

+ (void)refreshQuickGrammarActionDetailWithSource:(id<FYGrammarScrollSource>)source {
    FYGrammarItem *item = [source grammarActionItemForQuick:YES];
    if (!item || !source.quickGrammarStack) { return; }
    NSScrollView *scroll = source.quickGrammarStack.enclosingScrollView;
    NSPoint position = scroll.contentView.bounds.origin;
    [source.quickGrammarStack removeArrangedSubview:source.quickGrammarDetailCard];
    [source.quickGrammarDetailCard removeFromSuperview];
    source.quickGrammarDetailCard = [source quickGrammarDetailForItem:item];
    [source.quickGrammarStack addArrangedSubview:source.quickGrammarDetailCard];
    [source.quickSentencePanel.contentView layoutSubtreeIfNeeded];
    position.y = MIN(position.y, MAX(0, NSHeight(scroll.documentView.frame)-NSHeight(scroll.contentView.bounds)));
    [scroll.contentView scrollToPoint:position]; [scroll reflectScrolledClipView:scroll.contentView];
}

+ (void)updateGrammarReviewDisplayForQuick:(BOOL)quick preservingPosition:(void (^)(void))updates source:(id<FYGrammarScrollSource>)source {
    NSScrollView *before = quick ? [source quickSentenceScrollView] : source.grammarReviewButton.enclosingScrollView;
    NSPoint position = before.contentView.bounds.origin;
    updates();
    // Quick reading replaces its entire document on success. Restore into the
    // new scroll view after layout, using the position at this update, not the
    // request's starting position (the reader may have scrolled while waiting).
    NSScrollView *after = quick ? [source quickSentenceScrollView] : source.grammarReviewButton.enclosingScrollView;
    if (!before || !after) { return; }
    [after.window.contentView layoutSubtreeIfNeeded];
    [after.superview layoutSubtreeIfNeeded];
    [after.documentView layoutSubtreeIfNeeded];
    CGFloat maxY = MAX(0, NSHeight(after.documentView.frame)-NSHeight(after.contentView.bounds));
    CGFloat maxX = MAX(0, NSWidth(after.documentView.frame)-NSWidth(after.contentView.bounds));
    [after.contentView scrollToPoint:NSMakePoint(MIN(MAX(0,position.x),maxX), MIN(MAX(0,position.y),maxY))];
    [after reflectScrolledClipView:after.contentView];
}
@end
