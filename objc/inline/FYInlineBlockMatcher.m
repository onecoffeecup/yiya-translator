#import "FYInlineLayoutInternal.h"

#pragma mark - FYInlineBlockMatcher

@implementation FYInlineBlockMatcher

+ (NSString *)blockIDForText:(NSString *)text lineBoxes:(NSArray<NSValue *> *)lineBoxes {
    NSMutableString *key = [NSMutableString stringWithString:FYInlineNormalize(text)];
    for (NSValue *value in lineBoxes) {
        CGRect rect = value.rectValue;
        [key appendFormat:@"|%.3f,%.3f,%.3f,%.3f", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
    }
    return [key copy];
}

+ (NSString *)normalizedForSimilarity:(NSString *)text {
    return FYInlineNormalize(text);
}

+ (CGFloat)textSimilarity:(NSString *)left right:(NSString *)right {
    NSString *a = FYInlineNormalize(left);
    NSString *b = FYInlineNormalize(right);
    if (a.length == 0 || b.length == 0) { return 0; }
    if ([a isEqualToString:b]) { return 1.0; }
    if (a.length < 2 || b.length < 2) { return 0; }
    NSMutableDictionary<NSString *, NSNumber *> *bigrams = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index + 1 < a.length; index++) {
        NSString *gram = [a substringWithRange:NSMakeRange(index, 2)];
        bigrams[gram] = @(bigrams[gram].integerValue + 1);
    }
    NSUInteger matches = 0;
    for (NSUInteger index = 0; index + 1 < b.length; index++) {
        NSString *gram = [b substringWithRange:NSMakeRange(index, 2)];
        NSInteger count = bigrams[gram].integerValue;
        if (count > 0) {
            matches += 1;
            bigrams[gram] = @(count - 1);
        }
    }
    return (CGFloat)(2.0 * matches) / (CGFloat)((a.length - 1) + (b.length - 1));
}

+ (CGFloat)overlapRatio:(CGRect)left right:(CGRect)right {
    CGRect hit = CGRectIntersection(left, right);
    if (CGRectIsNull(hit) || CGRectIsEmpty(hit)) { return 0; }
    CGFloat hitArea = hit.size.width * hit.size.height;
    CGFloat smaller = MIN(left.size.width * left.size.height, right.size.height * right.size.width);
    if (smaller <= 0) { return 0; }
    return hitArea / smaller;
}

+ (NSString *)stableBlockIDForBlock:(FYInlineTextBlock *)block
                               text:(NSString *)text
                        sourceFrame:(CGRect)sourceFrame
                     previousResult:(FYInlineLayoutResult *)previous {
    if (!previous || previous.placements.count == 0) { return nil; }
    NSString *normalized = FYInlineNormalize(text);
    FYInlinePlacement *best = nil;
    CGFloat bestScore = 0;
    for (FYInlinePlacement *placement in previous.placements) {
        if (placement.blockID.length == 0) { continue; }
        CGFloat similarity = [self textSimilarity:normalized right:placement.block.text ?: placement.translation];
        BOOL sameText = similarity >= 0.999;
        if (similarity < 0.62) { continue; }
        CGFloat overlap = [self overlapRatio:sourceFrame right:placement.sourceFrame];
        if (overlap < 0.20) { continue; }
        CGFloat sizeRatio = MIN(NSWidth(sourceFrame), NSWidth(placement.sourceFrame)) /
                            MAX((CGFloat)0.001, MAX(NSWidth(sourceFrame), NSWidth(placement.sourceFrame)));
        if (sizeRatio < 0.55) { continue; }
        CGFloat score = overlap * (sameText ? 2.0 : 1.0) + similarity;
        if (score > bestScore) { bestScore = score; best = placement; }
    }
    return best.blockID;
}

@end
