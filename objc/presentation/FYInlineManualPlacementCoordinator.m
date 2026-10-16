#import "FYInlineManualPlacementCoordinator.h"
#import "FYPresentationText.h"

static const CGFloat kInlineManualOffsetBucket = 0.01;

@implementation FYInlineManualPlacementCoordinator
- (NSString *)inlineManualOffsetKeyForText:(NSString *)text normalizedBox:(CGRect)box {
    NSInteger bucketX = (NSInteger)floor(CGRectGetMidX(box) / kInlineManualOffsetBucket);
    NSInteger bucketY = (NSInteger)floor(CGRectGetMidY(box) / kInlineManualOffsetBucket);
    return [NSString stringWithFormat:@"%@|%ld,%ld", NormalizeForComparison(text ?: @""), (long)bucketX, (long)bucketY];
}

- (NSValue *)inlineManualOffsetForText:(NSString *)text normalizedBox:(CGRect)box stateSource:(id<FYInlineManualPlacementStateSource>)source {
    for (NSInteger dx = -1; dx <= 1; dx++) {
        for (NSInteger dy = -1; dy <= 1; dy++) {
            NSInteger bucketX = (NSInteger)floor(CGRectGetMidX(box) / kInlineManualOffsetBucket) + dx;
            NSInteger bucketY = (NSInteger)floor(CGRectGetMidY(box) / kInlineManualOffsetBucket) + dy;
            NSString *key = [NSString stringWithFormat:@"%@|%ld,%ld", NormalizeForComparison(text ?: @""), (long)bucketX, (long)bucketY];
            NSValue *value = source.inlineManualOffsets[key];
            if (value) { return value; }
        }
    }
    return nil;
}

- (void)recordInlineManualOffsetForPanel:(NSPanel *)panel stateSource:(id<FYInlineManualPlacementStateSource>)source nativeActions:(id<FYInlineManualPlacementNativeActions>)actions {
    [actions clearInlineDraggingPanel];
    if (!panel || [actions identifierForManualInlinePanel:panel].length == 0) { return; }
    FYInlinePlacement *placement = [[actions currentLayoutForManualPlacement] placementForBlockID:[actions identifierForManualInlinePanel:panel]];
    if (!placement) { return; }
    NSRect frame = [actions frameForManualInlinePanel:panel];
    NSRect viewport = NSZeroRect;
    if ([actions inlinePlacementRect:&viewport reason:NULL]) {
        CGRect clamped = frame;
        clamped.origin.x = MIN(MAX(clamped.origin.x, NSMinX(viewport) + 4),
                               MAX(NSMinX(viewport) + 4, NSMaxX(viewport) - 4 - NSWidth(clamped)));
        clamped.origin.y = MIN(MAX(clamped.origin.y, NSMinY(viewport) + 4),
                               MAX(NSMinY(viewport) + 4, NSMaxY(viewport) - 4 - NSHeight(clamped)));
        frame = NSIntegralRect(clamped);
    }
    if (!NSEqualRects(frame, [actions frameForManualInlinePanel:panel])) { [actions setManualInlinePanel:panel frame:frame display:YES]; }
    CGSize offset = CGSizeMake(NSMinX(frame) - NSMinX(placement.sourceFrame),
                               NSMinY(frame) - NSMinY(placement.sourceFrame));
    NSString *text = placement.block.text ?: @"";
    NSString *key = [source inlineManualOffsetKeyForText:text normalizedBox:placement.block.boundingBox];
    source.inlineManualOffsets[key] = [NSValue valueWithSize:offset];
    source.inlineManualOffsetAge[key] = @0;
    [actions recordInlineManualDiagnosticText:text offset:offset];
}

- (void)maintainOffsetsForPlacements:(NSArray<FYInlinePlacement *> *)placements stateSource:(id<FYInlineManualPlacementStateSource>)source {
    NSMutableSet<NSString *> *seenKeys = [NSMutableSet set];
    for (FYInlinePlacement *placement in placements) {
        if (!placement.manuallyPlaced || placement.block.text.length == 0) { continue; }
        CGSize offset = CGSizeMake(NSMinX(placement.translationFrame) - NSMinX(placement.sourceFrame),
                                   NSMinY(placement.translationFrame) - NSMinY(placement.sourceFrame));
        NSString *key = [source inlineManualOffsetKeyForText:placement.block.text normalizedBox:placement.block.boundingBox];
        source.inlineManualOffsets[key] = [NSValue valueWithSize:offset];
        source.inlineManualOffsetAge[key] = @0;
        [seenKeys addObject:key];
    }
    for (NSString *key in source.inlineManualOffsets.allKeys) {
        if ([seenKeys containsObject:key]) { continue; }
        NSInteger age = [source.inlineManualOffsetAge[key] integerValue] + 1;
        if (age > 2) {
            [source.inlineManualOffsets removeObjectForKey:key];
            [source.inlineManualOffsetAge removeObjectForKey:key];
        } else {
            source.inlineManualOffsetAge[key] = @(age);
        }
    }
}
@end
