#import "FYGrammarActionState.h"

@implementation FYGrammarActionState
- (instancetype)init {
    if ((self = [super init])) {
        _analyzer = [FYLearningAnalyzer new];
        _explanations = [NSMapTable strongToStrongObjectsMapTable];
        _errors = [NSMapTable strongToStrongObjectsMapTable];
        _pending = [NSMutableSet new];
    }
    return self;
}
- (void)reset {
    self.generation++; self.expandedItem = nil; self.reviewing = NO; self.reviewStatus = nil; self.context = nil;
    [self.explanations removeAllObjects]; [self.errors removeAllObjects]; [self.pending removeAllObjects];
    [self.analyzer cancelAll];
}
@end
