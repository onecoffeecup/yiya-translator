#import "FYContentRouter.h"

@interface FYContentRouter ()
@property(nonatomic, strong) FYContentModeStability *modeStability;
@property(nonatomic, strong) FYContentModeDecision *lastModeDecision;
@end

@implementation FYContentRouter
@dynamic modeStability, lastModeDecision;
- (FYContentModeStability *)modeStability { return self.modeCoordinator.stability; }
- (void)setModeStability:(FYContentModeStability *)value { self.modeCoordinator.stability = value; }
- (FYContentModeDecision *)lastModeDecision { return self.modeCoordinator.lastDecision; }
- (void)setLastModeDecision:(FYContentModeDecision *)value { self.modeCoordinator.lastDecision = value; }

- (instancetype)init {
    if ((self = [super init])) { _modeCoordinator = [FYContentModeCoordinator new]; }
    return self;
}
- (NSInteger)observeModeForItems:(NSArray<OCRTextItem *> *)items locked:(BOOL)locked {
    return [self.modeCoordinator observeLocked:locked classifier:^FYContentModeDecision *(NSInteger fallback) {
        return [self.class modeDecisionForItems:items fallback:fallback];
    }];
}

+ (double)similarityRatio:(NSString *)left comparedTo:(NSString *)right { return [FYDialogueStability similarityRatio:left comparedTo:right]; }

+ (BOOL)isSameSubtitleText:(NSString *)text comparedTo:(NSString *)previous mode:(NSInteger)mode japanese:(BOOL)japanese comparisonKey:(FYContentComparisonKey)key { return [FYDialogueStability isSameSubtitleText:text comparedTo:previous mode:mode japanese:japanese comparisonKey:key]; }

+ (BOOL)isStableText:(NSString *)text owner:(FYOCRStabilityOwner *)owner mode:(NSInteger)mode japanese:(BOOL)japanese renderedText:(NSString *)rendered comparisonKey:(FYContentComparisonKey)key { return [FYDialogueStability isStableText:text owner:owner mode:mode japanese:japanese renderedText:rendered comparisonKey:key]; }
@end
