#import "FYInlineTranslationListRenderer.h"

@implementation FYInlineTranslationListRenderer
- (NSView *)makeCardWithReceiver:(id<FYInlineTranslationListRenderSource>)receiver {
    NSStackView *block = [receiver verticalStack];
    block.spacing = 10;
    NSStackView *titleRow = [receiver horizontalStack];
    [titleRow addArrangedSubview:[receiver mutedLabel:@"界面译文"]];
    [titleRow addArrangedSubview:[receiver spacer]];
    receiver.inlineTranslationListCount = [receiver mutedLabel:@""];
    [titleRow addArrangedSubview:receiver.inlineTranslationListCount];
    [block addArrangedSubview:titleRow];

    receiver.inlineTranslationListStack = [receiver verticalStack];
    receiver.inlineTranslationListStack.spacing = 10;
    NSScrollView *listScroll = [receiver makePageScrollWithContent:receiver.inlineTranslationListStack];
    [listScroll.heightAnchor constraintEqualToConstant:220].active = YES;
    [block addArrangedSubview:listScroll];
    [receiver pinFullWidth:listScroll toStack:block];

    NSView *card = [receiver cardWithStack:block];
    card.hidden = YES;
    receiver.inlineTranslationListCard = card;
    receiver.inlineTranslationListSnapshots = @[];
    receiver.inlineTranslationListSignature = @"";
    return card;
}

- (void)appendRowForPlacement:(FYInlinePlacement *)placement currentSnapshots:(NSArray<FYInlineBlockSnapshot *> *)snapshots receiver:(id<FYInlineTranslationListRenderSource>)receiver {
        NSStackView *row = [receiver verticalStack];
        row.spacing = 6;
        NSTextField *sourceLabel = [receiver label:placement.block.text font:[receiver inlineTranslationListFontOfSize:13] color:receiver.uiMuted];
        sourceLabel.maximumNumberOfLines = 3;
        [row addArrangedSubview:sourceLabel];
        NSTextField *translationLabel = [receiver label:placement.translation font:[receiver inlineTranslationListFontOfSize:15] color:receiver.uiInk];
        translationLabel.selectable = YES;
        translationLabel.maximumNumberOfLines = 6;
        [row addArrangedSubview:translationLabel];

        NSStackView *footer = [receiver horizontalStack];
        NSString *tag = placement.mode == FYInlineDisplayModeUnplaceable ? @"暂不可放置" : @"已改为「查看译文」入口";
        [footer addArrangedSubview:[receiver mutedLabel:[NSString stringWithFormat:@"%@ · 原因：%@", tag, placement.reason ?: @""]]];
        [footer addArrangedSubview:[receiver spacer]];
        NSButton *open = [receiver workspaceButton:@"查看原文和语法" action:@selector(openInlineTranslationRow:) primary:NO];
        open.tag = (NSInteger)snapshots.count;
        [footer addArrangedSubview:open];
        [row addArrangedSubview:footer];

        NSView *rowCard = [receiver cardWithStack:row];
        [receiver.inlineTranslationListStack addArrangedSubview:rowCard];
        [receiver pinFullWidth:rowCard toStack:receiver.inlineTranslationListStack];
}
@end
