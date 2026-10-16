#import "presentation/FYCollectionController.h"
#import "FYCollectionReviewTestFacts.h"
@interface CollectionReviewHostFixture : FYCollectionController <CollectionReviewDriver>
@property(nonatomic,strong) CollectionReviewFacts *facts;
@end
@implementation CollectionReviewHostFixture
- (FYLearningStore *)learningStore { return (FYLearningStore *)self.facts.store; }
- (void)updateLearningCollectionSummary { self.facts.summaries++;[self.facts.events addObject:@"summary"];if(self.facts.onSummary)self.facts.onSummary(); }
- (void)rebuildWordCards { self.facts.rebuilds++;[self.facts.events addObject:@"cards"];if(self.facts.onRebuild)self.facts.onRebuild(); }
- (void)refreshGrammarBookmarks:(id)sender { self.facts.grammarRefreshes++;[self.facts.events addObject:@"grammar"]; }
- (NSTextField *)reviewWordLabel { return (NSTextField *)self.facts.word; }
- (NSTextField *)reviewMeaningLabel { return (NSTextField *)self.facts.meaning; }
- (NSTextField *)reviewPromptLabel { return (NSTextField *)self.facts.prompt; }
- (NSTextField *)vocabularyListLabel { return (NSTextField *)self.facts.list; }
- (NSView *)vocabularyEmptyCard { return (NSView *)self.facts.empty; }
@end
static id<CollectionReviewDriver> Source(CollectionReviewFacts*f){CollectionReviewHostFixture*s=[[CollectionReviewHostFixture alloc]initWithHost:nil];s.facts=f;return s;}
int main(void){@autoreleasepool{Check(NSApp==nil,@"cold native review has no application/windows");CollectionReviewFacts*f=[CollectionReviewFacts new];RunReview(Source(f),f);RunLeases(^id<CollectionReviewDriver>(CollectionReviewFacts*f){return Source(f);});Check(NSApp==nil,@"native adapters remain headless");printf("PASS CollectionReviewHostTests: %lu checks; actual old/new native same fixture\n",(unsigned long)checks);}return 0;}
