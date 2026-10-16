#pragma once
#import "FYContentModeState.h"

// Pure comparison normalization shared with the coordinator; whitespace only.
@interface FYOCRStabilityOwner : NSObject
@property(nonatomic, copy) NSString *candidate;
@property(nonatomic) NSInteger count;
- (BOOL)observe:(NSString *)normalized equivalent:(BOOL (^)(NSString *current, NSString *previous))equivalent;
- (void)reset;
@end
typedef NSString *(^FYContentComparisonKey)(NSString *text);
// Original string comparison/consecutive-frame policies, no learning store.
@interface FYDialogueStability : NSObject
+ (double)similarityRatio:(NSString *)left comparedTo:(NSString *)right;
+ (BOOL)isSameSubtitleText:(NSString *)text comparedTo:(NSString *)previous mode:(NSInteger)mode japanese:(BOOL)japanese comparisonKey:(FYContentComparisonKey)key;
+ (BOOL)isStableText:(NSString *)text owner:(FYOCRStabilityOwner *)owner mode:(NSInteger)mode japanese:(BOOL)japanese renderedText:(NSString *)rendered comparisonKey:(FYContentComparisonKey)key;
@end
