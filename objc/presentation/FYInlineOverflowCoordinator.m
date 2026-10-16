#import "FYInlineOverflowCoordinator.h"
#import "FYPresentationText.h"

@implementation FYInlineOverflowCoordinator
- (void)updateInlineOverflowEntryWithPlacements:(NSArray<FYInlinePlacement *> *)placements
                                          items:(NSDictionary<NSString *, OCRTextItem *> *)itemsByBlockID
                                       viewport:(NSRect)viewport
                                    unplaceable:(NSUInteger)unplaceable source:(id<FYInlineOverflowSource>)source {
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (FYInlinePlacement *placement in placements) {
        if (placement.mode != FYInlineDisplayModeUnplaceable) { continue; }
        if (Trim(placement.translation).length == 0) { continue; }
        OCRTextItem *item = itemsByBlockID[placement.sourceBlockID];
        NSString *title = [source inlineOverflowTitleForBlockText:placement.block.text ?: @""];
        if (title.length == 0) { title = [source inlineOverflowFallbackTitle] ?: @"这段译文"; }
        [entries addObject:@{@"blockID": placement.blockID ?: @"",
                             @"source": placement.block.text ?: @"",
                             @"translation": placement.translation ?: @"",
                             @"title": title,
                             @"item": item ?: (id)NSNull.null}];
    }
    // 选择列表打开期间保持按钮 tag、条目和面板不变，直到用户选择或关闭。
    BOOL chooserOpen = source.inlineOverflowChoicePanel != nil;
    if (chooserOpen) { return; }
    if (entries.count == 0) {
        // 单帧 OCR 漏块时保留入口；持续没有条目才由可见性轮询收掉。
        if (source.inlineOverflowEmptySince == 0) { source.inlineOverflowEmptySince = [source inlineOverflowTime]; }
        [source inlineHostExpireInlineOverflowEntryIfNeeded];
        return;
    }
    source.inlineOverflowEmptySince = 0;
    if (source.inlineExpandedReadingPanel) {
        [source hideInlineOverflowEntryForExpandedReading];
        return;
    }
    if (!source.inlineOverflowPanel) {
        source.inlineOverflowEntries = entries;
        source.inlineOverflowCount = entries.count;
        [source buildInlineOverflowEntryForViewport:viewport];
        source.inlineOverflowPanelCount = entries.count;
    } else if (source.inlineOverflowPanelCount == entries.count) {
        source.inlineOverflowEntries = entries;
        source.inlineOverflowCount = entries.count;
        source.inlineOverflowCandidateFrames = 0;
    } else {
        // N 和 N±1 交替时不改文案，也不销毁窗口；新条数连续出现两帧才采纳。
        if (source.inlineOverflowCandidateCount == entries.count) {
            source.inlineOverflowCandidateFrames++;
        } else {
            source.inlineOverflowCandidateCount = entries.count;
            source.inlineOverflowCandidateFrames = 1;
        }
        if (source.inlineOverflowCandidateFrames >= 2) {
            source.inlineOverflowEntries = entries;
            source.inlineOverflowCount = entries.count;
            source.inlineOverflowPanelCount = entries.count;
            source.inlineOverflowCandidateFrames = 0;
            NSString *title = [NSString stringWithFormat:@"还有 %lu 条译文 · 查看", (unsigned long)entries.count];
            [source resizeInlineOverflowEntryWithTitle:title viewport:viewport];
        }
    }
    if (!source.inlineOverflowPanel) { return; }
    [source positionInlineOverflowEntryInViewport:viewport];
    if (![source inlineOverflowEntryIsVisible]) { [source orderInlineOverflowEntryFront]; }
    [source setInlineOverflowEntryIgnoresMouseEvents:NO];
}

- (void)expireInlineOverflowEntryIfNeededWithSource:(id<FYInlineOverflowSource>)source {
    if (source.inlineOverflowEmptySince == 0 || source.inlineOverflowChoicePanel ||
        [source inlineOverflowTime] - source.inlineOverflowEmptySince < 1.5) { return; }
    [source closeInlineOverflowEntryPanel];
    source.inlineOverflowPanel = nil;
    source.inlineOverflowEntries = @[];
    source.inlineOverflowCount = 0;
    source.inlineOverflowPanelCount = 0;
    source.inlineOverflowCandidateFrames = 0;
    source.inlineOverflowEmptySince = 0;
}

- (void)showInlineOverflowChooserWithSource:(id<FYInlineOverflowSource>)source {
    [source closeInlineOverflowChoice];
    if (source.inlineOverflowEntries.count == 0) { return; }
    // 只有一条放不下时直接展开它，不再多一次"选择"步骤。
    if (source.inlineOverflowEntries.count == 1) {
        NSDictionary *only = source.inlineOverflowEntries.firstObject;
        OCRTextItem *item = [only[@"item"] isKindOfClass:OCRTextItem.class] ? only[@"item"] : nil;
        if (!item) {
            item = [[OCRTextItem alloc] init];
            item.text = only[@"source"] ?: @"";
            item.boundingBox = CGRectZero;
            item.lineBoxes = @[];
            item.blockKind = InlineBlockKindLong;
        }
        [source openFullInlineReadingCardForItem:item
                                   translation:only[@"translation"] ?: @""
                                 stableBlockID:only[@"blockID"] ?: @""];
        return;
    }
    [source showInlineOverflowList];
}

- (NSString *)overflowRowTitleForEntry:(NSDictionary *)entry {
    NSString *title = entry[@"title"] ?: @"";
    NSString *source = [entry[@"source"] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet].firstObject ?: @"";
    source = Shorten(source, 22);
    return source.length > 0 ? [NSString stringWithFormat:@"%@　（%@）", title, source] : title;
}

- (void)openInlineOverflowRowAtIndex:(NSInteger)index source:(id<FYInlineOverflowSource>)source {
    if (index < 0 || (NSUInteger)index >= source.inlineOverflowEntries.count) { return; }
    NSDictionary *entry = source.inlineOverflowEntries[index];
    id item = entry[@"item"];
    OCRTextItem *textItem = [item isKindOfClass:OCRTextItem.class] ? (OCRTextItem *)item : nil;
    if (!textItem) {
        textItem = [[OCRTextItem alloc] init];
        textItem.text = entry[@"source"] ?: @"";
        textItem.boundingBox = CGRectZero;
        textItem.lineBoxes = @[];
        textItem.blockKind = InlineBlockKindLong;
    }
    [source closeInlineOverflowChoice];
    [source openFullInlineReadingCardForItem:textItem
                               translation:entry[@"translation"] ?: @""
                             stableBlockID:entry[@"blockID"] ?: @""];
}
@end
