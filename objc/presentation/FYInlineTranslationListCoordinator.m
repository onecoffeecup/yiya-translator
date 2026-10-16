#import "FYInlineTranslationListCoordinator.h"
#import "FYPresentationText.h"

@implementation FYInlineTranslationListCoordinator
- (void)refreshWithReceiver:(id<FYInlineTranslationListSource>)receiver {
    if (![receiver isInlineTranslationListReady]) { return; }
    NSMutableArray<FYInlinePlacement *> *degraded = [NSMutableArray array];
    NSUInteger unplaceable = 0;
    for (FYInlinePlacement *placement in receiver.lastInlineLayoutResult.placements) {
        if (Trim(placement.translation).length == 0) { continue; }
        BOOL isUnplaceable = placement.mode == FYInlineDisplayModeUnplaceable;
        BOOL isCompact = placement.mode == FYInlineDisplayModeCompactEntry;
        if (!isUnplaceable && !isCompact) { continue; }
        if (isUnplaceable) { unplaceable += 1; }
        [degraded addObject:placement];
    }
    NSMutableString *signature = [NSMutableString string];
    for (FYInlinePlacement *placement in degraded) {
        [signature appendFormat:@"%@|%ld|%@\n", placement.blockID, (long)placement.mode, placement.translation];
    }
    [receiver setInlineTranslationListHidden:degraded.count == 0];
    if (degraded.count == 0) {
        if (receiver.inlineTranslationListSignature.length == 0) { return; }
        receiver.inlineTranslationListSignature = @"";
        receiver.inlineTranslationListSnapshots = @[];
        [receiver clearInlineTranslationListRows];
        return;
    }
    if ([receiver.inlineTranslationListSignature isEqualToString:signature]) { return; }
    receiver.inlineTranslationListSignature = [signature copy];
    [receiver clearInlineTranslationListRows];
    [receiver updateInlineTranslationListCountText:unplaceable > 0
        ? [NSString stringWithFormat:@"%lu 条暂不可放置 · %lu 条用入口", (unsigned long)unplaceable,
           (unsigned long)(degraded.count - unplaceable)]
        : [NSString stringWithFormat:@"%lu 条改用「查看译文」入口", (unsigned long)degraded.count]];

    NSMutableArray<FYInlineBlockSnapshot *> *snapshots = [NSMutableArray array];
    for (FYInlinePlacement *placement in degraded) {
        [receiver appendInlineTranslationListRowForPlacement:placement currentSnapshots:snapshots];
        [snapshots addObject:[receiver inlineSnapshotForBlock:placement.block
                                              translation:placement.translation
                                            stableBlockID:placement.blockID]];
    }
    receiver.inlineTranslationListSnapshots = snapshots;
}

- (void)openRowAtIndex:(NSInteger)index receiver:(id<FYInlineTranslationListSource>)receiver {
    if (index < 0 || index >= (NSInteger)receiver.inlineTranslationListSnapshots.count) { return; }
    [receiver openInlineLearningWithSnapshot:receiver.inlineTranslationListSnapshots[(NSUInteger)index]];
}
@end
