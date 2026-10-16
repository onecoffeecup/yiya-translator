#import "FYContentPolicy.h"
@implementation FYContentPolicy
+ (double)similarityRatio:(NSString *)left comparedTo:(NSString *)right { return [FYDialogueStability similarityRatio:left comparedTo:right]; }

+ (BOOL)isSameSubtitleText:(NSString *)text comparedTo:(NSString *)previous mode:(NSInteger)mode japanese:(BOOL)japanese comparisonKey:(FYContentComparisonKey)key { return [FYDialogueStability isSameSubtitleText:text comparedTo:previous mode:mode japanese:japanese comparisonKey:key]; }

+ (BOOL)isStableText:(NSString *)text owner:(FYOCRStabilityOwner *)owner mode:(NSInteger)mode japanese:(BOOL)japanese renderedText:(NSString *)rendered comparisonKey:(FYContentComparisonKey)key { return [FYDialogueStability isStableText:text owner:owner mode:mode japanese:japanese renderedText:rendered comparisonKey:key]; }


@end
