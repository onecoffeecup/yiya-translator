#import "FYDialogueStability.h"

@implementation FYOCRStabilityOwner
- (BOOL)observe:(NSString *)normalized equivalent:(BOOL (^)(NSString *, NSString *))equivalent {
    if (equivalent(normalized,self.candidate)) self.count++;
    else { self.candidate=normalized; self.count=1; }
    return self.count>=2;
}
- (void)reset { self.candidate=@""; self.count=0; }
@end


static NSUInteger LevenshteinDistance(NSString *left, NSString *right) {
    NSUInteger leftLength = left.length;
    NSUInteger rightLength = right.length;
    if (leftLength == 0) { return rightLength; }
    if (rightLength == 0) { return leftLength; }

    NSMutableArray<NSNumber *> *previous = [NSMutableArray arrayWithCapacity:rightLength + 1];
    NSMutableArray<NSNumber *> *current = [NSMutableArray arrayWithCapacity:rightLength + 1];
    for (NSUInteger column = 0; column <= rightLength; column++) {
        [previous addObject:@(column)];
        [current addObject:@0];
    }

    for (NSUInteger row = 1; row <= leftLength; row++) {
        current[0] = @(row);
        unichar leftCharacter = [left characterAtIndex:row - 1];
        for (NSUInteger column = 1; column <= rightLength; column++) {
            unichar rightCharacter = [right characterAtIndex:column - 1];
            NSUInteger cost = leftCharacter == rightCharacter ? 0 : 1;
            NSUInteger deletion = previous[column].unsignedIntegerValue + 1;
            NSUInteger insertion = current[column - 1].unsignedIntegerValue + 1;
            NSUInteger substitution = previous[column - 1].unsignedIntegerValue + cost;
            current[column] = @(MIN(MIN(deletion, insertion), substitution));
        }
        NSMutableArray<NSNumber *> *swap = previous;
        previous = current;
        current = swap;
    }

    return previous[rightLength].unsignedIntegerValue;
}

@implementation FYDialogueStability
+ (double)similarityRatio:(NSString *)left comparedTo:(NSString *)right {
    NSUInteger maxLength = MAX(left.length, right.length);
    if (maxLength == 0) { return 1.0; }
    NSUInteger distance = LevenshteinDistance(left, right);
    return 1.0 - ((double)distance / (double)maxLength);
}

+ (BOOL)isSameSubtitleText:(NSString *)text comparedTo:(NSString *)previous
                     mode:(NSInteger)mode japanese:(BOOL)japanese comparisonKey:(FYContentComparisonKey)key {
    NSString *left = text ?: @"";
    NSString *right = previous ?: @"";
    if (mode == FYContentModeDialogue && japanese) {
        // A long sentence with one changed negation/number can still be >90%
        // similar. Only harmless OCR punctuation shares the frame identity;
        // clipped frames are checked directionally against the complete source
        // by the learning coordinator, after consecutive-frame confirmation.
        NSString *leftKey = key(left), *rightKey = key(right);
        // Removing a leading ellipsis can leave a valid one-character reply;
        // pure punctuation has no identity and cannot confirm a dialogue.
        return leftKey.length && rightKey.length && [leftKey isEqualToString:rightKey];
    }
    if (left.length < 2 || right.length < 2) { return NO; }
    if ([left isEqualToString:right]) { return YES; }

    NSUInteger maxLength = MAX(left.length, right.length);
    NSUInteger lengthDelta = left.length > right.length ? left.length - right.length : right.length - left.length;
    if (maxLength <= 6) {
        return lengthDelta == 0 && [self similarityRatio:left comparedTo:right] >= 0.84;
    }

    return [self similarityRatio:left comparedTo:right] >= 0.90;
}

+ (BOOL)isStableText:(NSString *)normalized owner:(FYOCRStabilityOwner *)owner
               mode:(NSInteger)mode japanese:(BOOL)japanese renderedText:(NSString *)rendered
      comparisonKey:(FYContentComparisonKey)key {
    BOOL stable = [owner observe:normalized equivalent:^BOOL(NSString *current, NSString *previous) {
        return [self isSameSubtitleText:current comparedTo:previous mode:mode japanese:japanese comparisonKey:key];
    }];
    // Small real corrections must eventually translate, while one/two-frame
    // substitutions caused by compression need not replace a complete caption.
    if (stable && mode == FYContentModeDialogue && japanese &&
        rendered.length &&
        [self similarityRatio:normalized comparedTo:rendered] >= 0.85 &&
        ![self isSameSubtitleText:normalized comparedTo:rendered mode:mode japanese:japanese comparisonKey:key]) {
        return owner.count >= 3;
    }
    return stable;
}
@end
