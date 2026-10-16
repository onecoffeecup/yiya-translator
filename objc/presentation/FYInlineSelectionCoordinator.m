#import "FYInlineSelectionCoordinator.h"
#import "FYPresentationText.h"

@implementation FYInlineSelectionCoordinator
- (NSString *)inlineBlockIdentityForItem:(OCRTextItem *)item {
    NSArray<NSValue *> *boxes = item.lineBoxes.count ? item.lineBoxes : (item.boundingBox.size.width > 0 ? @[[NSValue valueWithRect:item.boundingBox]] : @[]);
    NSMutableString *key = [NSMutableString stringWithString:NormalizeForComparison(item.text ?: @"")];
    for (NSValue *value in boxes) {
        CGRect r = value.rectValue;
        [key appendFormat:@"|%.3f,%.3f,%.3f,%.3f", r.origin.x, r.origin.y, r.size.width, r.size.height];
    }
    return [key copy];
}

- (BOOL)inlineBlockID:(NSString *)stableBlockID isSelectedForItem:(OCRTextItem *)item stateSource:(id<FYInlineSelectionStateSource>)source {
    FYInlineBlockSnapshot *current = source.inlineBlockSnapshot;
    if (!current || current.blockID.length == 0) { return NO; }
    if (stableBlockID.length > 0 && [current.blockID isEqualToString:stableBlockID]) { return YES; }
    return [current.blockID isEqualToString:[source inlineBlockIdentityForItem:item]];
}

- (BOOL)inlineBlockIsSelectedForItem:(OCRTextItem *)item stateSource:(id<FYInlineSelectionStateSource>)source {
    // 任何调用点都要能识别「上一帧匹配出来的稳定身份」：先查本帧映射，再退回原始身份。
    NSString *raw = [source inlineBlockIdentityForItem:item];
    NSString *stable = source.inlineStableBlockIDs[raw];
    return [source inlineHostBlockID:stable isSelectedForItem:item];
}

- (FYInlineBlockSnapshot *)inlineSnapshotForItem:(OCRTextItem *)item
                                     translation:(NSString *)translation
                                   stableBlockID:(NSString *)stableBlockID source:(id<FYInlineSnapshotInputSource>)source {
    FYInlineBlockSnapshot *snapshot = [FYInlineBlockSnapshot new];
    snapshot.sourceText = [item.text copy] ?: @"";
    snapshot.translation = [translation copy] ?: @"";
    NSArray<NSValue *> *boxes = item.lineBoxes.count ? item.lineBoxes : (item.boundingBox.size.width > 0 ? @[[NSValue valueWithRect:item.boundingBox]] : @[]);
    snapshot.lineBoxes = boxes;
    snapshot.inputSource = [source captureCardInputEnabled] ? 1 : 0;
    snapshot.inputEpoch = [source inlineSnapshotInputEpoch];
    snapshot.blockID = stableBlockID.length > 0 ? [stableBlockID copy] : [source inlineBlockIdentityForItem:item];
    return snapshot;
}

- (FYInlineBlockSnapshot *)inlineSnapshotForBlock:(FYInlineTextBlock *)block
                                      translation:(NSString *)translation
                                    stableBlockID:(NSString *)stableBlockID source:(id<FYInlineSnapshotInputSource>)source {
    FYInlineBlockSnapshot *snapshot = [FYInlineBlockSnapshot new];
    snapshot.sourceText = [block.text copy] ?: @"";
    snapshot.translation = [translation copy] ?: @"";
    snapshot.lineBoxes = block.lineBoxes.count > 0 ? block.lineBoxes : @[];
    snapshot.inputSource = [source captureCardInputEnabled] ? 1 : 0;
    snapshot.inputEpoch = [source inlineSnapshotInputEpoch];
    snapshot.blockID = stableBlockID.length > 0 ? [stableBlockID copy]
        : [FYInlineBlockMatcher blockIDForText:block.text lineBoxes:block.lineBoxes];
    return snapshot;
}
@end
