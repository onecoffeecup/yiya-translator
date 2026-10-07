#pragma once
#import "learning/FYLearningAnalyzer.h"

// Per-surface, ephemeral detail cache. Never touches translation tasks or preferences.
@interface FYGrammarActionState : NSObject
@property(nonatomic, strong) FYLearningAnalyzer *analyzer;
@property(nonatomic, strong) FYGrammarItem *expandedItem;
@property(nonatomic, strong) NSMapTable<FYGrammarItem *, NSString *> *explanations;
@property(nonatomic, strong) NSMapTable<FYGrammarItem *, NSString *> *errors;
@property(nonatomic, strong) NSMutableSet<FYGrammarItem *> *pending;
@property(nonatomic, copy) NSString *context;
@property(nonatomic, copy) NSString *reviewStatus;
@property(nonatomic) BOOL reviewing;
@property(nonatomic) NSInteger generation;
- (void)reset;
@end

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
