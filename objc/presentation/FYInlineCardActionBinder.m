#import "FYInlineCardActionBinder.h"
#import "../inline/FYInlineOverlayViews.h"

@implementation FYInlineCardActionBinder
- (void)wireInlineLongCardPanel:(NSPanel *)panel
                           item:(OCRTextItem *)item
                    translation:(NSString *)translation
                          frame:(NSRect)frame
                  stableBlockID:(NSString *)stableBlockID source:(id<FYInlineCardActionSource>)source {
    FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
    if (![card isKindOfClass:FYInlineLongCardView.class]) { return; }
    __weak id<FYInlineCardActionSource> weakSelf = source;
    __weak FYInlineLongCardView *weakCard = card;
    FYInlineBlockSnapshot *snapshot = [source inlineSnapshotForItem:item translation:translation stableBlockID:stableBlockID];
    card.stableBlockID = stableBlockID;
    card.onClick = ^{
        // 用 weakCard 读状态：block 被 card.onClick 持有，捕获 card 会成环（关闭面板也不释放）。
        if (weakCard.compactEntry) {
            // 已经是这块的展开卡 → 再点一次收起（不需要去找 Esc）。
            NSString *openBlockID = weakSelf.inlineExpandedReadingBlockID;
            NSString *thisBlockID = stableBlockID.length > 0 ? stableBlockID : snapshot.blockID;
            if (weakSelf.inlineExpandedReadingPanel && openBlockID.length > 0 &&
                [openBlockID isEqualToString:thisBlockID]) {
                [weakSelf closeExpandedInlineReadingCard];
                return;
            }
            [weakSelf openFullInlineReadingCardForItem:item translation:translation stableBlockID:stableBlockID];
            return;
        }
        [weakSelf openInlineLearningWithSnapshot:snapshot];
    };
    card.onHover = ^(BOOL inside) {
        weakCard.layer.borderWidth = inside ? 2 : 1;
        weakCard.toolTip = inside ? @"点击查看原文和语法" : nil;
    };
}
@end
