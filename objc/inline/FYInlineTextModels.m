#import "FYInlineTextModelsInternal.h"

#pragma mark - FYInlineTextLine

@implementation FYInlineTextLine
+ (instancetype)lineWithText:(NSString *)text rect:(CGRect)rect confidence:(CGFloat)confidence sourceIndex:(NSInteger)sourceIndex {
    FYInlineTextLine *line = [FYInlineTextLine new];
    line.text = text ?: @"";
    line.rect = rect;
    line.confidence = confidence;
    line.sourceIndex = sourceIndex;
    return line;
}
@end

#pragma mark - FYInlineTextBlock

@implementation FYInlineTextBlock
- (NSInteger)lineCount { return (NSInteger)self.lineTexts.count; }
- (instancetype)init {
    self = [super init];
    if (self) {
        _text = @"";
        _lineTexts = @[];
        _lineBoxes = @[];
        _lineConfidences = @[];
        _sourceIndices = @[];
        _groupingConfidence = 1.0;
    }
    return self;
}
@end

#pragma mark - FYInlineLayoutRequest

@implementation FYInlineLayoutRequest
+ (instancetype)requestWithBlock:(FYInlineTextBlock *)block translation:(NSString *)translation sourceFrame:(CGRect)sourceFrame {
    FYInlineLayoutRequest *request = [FYInlineLayoutRequest new];
    request.block = block;
    request.translation = translation ?: @"";
    request.sourceFrame = sourceFrame;
    return request;
}
@end

#pragma mark - FYInlinePlacement

@implementation FYInlinePlacement
- (instancetype)init {
    self = [super init];
    if (self) {
        _blockID = @"";
        _sourceBlockID = @"";
        _translation = @"";
        _reason = @"";
        _rejectedCandidates = @[];
    }
    return self;
}
@end

#pragma mark - FYInlineLayoutResult

@interface FYInlineLayoutResult ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, FYInlinePlacement *> *byBlockID;
@end

@implementation FYInlineLayoutResult
- (instancetype)init {
    self = [super init];
    if (self) {
        _placements = @[];
        _visiblePlacements = @[];
        _unplaceableBlockIDs = @[];
        _compactEntryBlockIDs = @[];
        _byBlockID = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)setPlacements:(NSArray<FYInlinePlacement *> *)placements {
    _placements = [placements copy] ?: @[];
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    NSMutableArray *visible = [NSMutableArray array];
    NSMutableArray *unplaceable = [NSMutableArray array];
    NSMutableArray *compact = [NSMutableArray array];
    for (FYInlinePlacement *placement in _placements) {
        if (placement.blockID.length > 0) { map[placement.blockID] = placement; }
        if (placement.mode == FYInlineDisplayModeUnplaceable) {
            [unplaceable addObject:placement.blockID];
        } else {
            [visible addObject:placement];
        }
        if (placement.mode == FYInlineDisplayModeCompactEntry) { [compact addObject:placement.blockID]; }
    }
    self.byBlockID = map;
    _visiblePlacements = visible;
    _unplaceableBlockIDs = unplaceable;
    _compactEntryBlockIDs = compact;
}
- (FYInlinePlacement *)placementForBlockID:(NSString *)blockID {
    if (blockID.length == 0) { return nil; }
    return self.byBlockID[blockID];
}
@end

