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
