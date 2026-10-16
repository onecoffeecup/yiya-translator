#import "FYCollectionReviewTestFacts.h"
@interface CollectionReviewFixture : NSObject <FYCollectionReviewSource,CollectionReviewDriver>
@property(nonatomic,strong) CollectionReviewFacts *facts;
@property(nonatomic,strong) FYCollectionReviewCoordinator *core;
@end
@implementation CollectionReviewFixture
- (instancetype)init{if((self=[super init]))_core=[FYCollectionReviewCoordinator new];return self;}
- (FYLearningStore *)learningStore { return (FYLearningStore *)self.facts.store; }
- (void)updateLearningCollectionSummary { self.facts.summaries++;[self.facts.events addObject:@"summary"];if(self.facts.onSummary)self.facts.onSummary(); }
- (void)rebuildWordCards { self.facts.rebuilds++;[self.facts.events addObject:@"cards"];if(self.facts.onRebuild)self.facts.onRebuild(); }
- (void)refreshGrammarBookmarks:(id)sender { self.facts.grammarRefreshes++;[self.facts.events addObject:@"grammar"]; }
- (NSArray<FYVocabularyEntry *> *)reviewList { return self.core.reviewList; }
- (void)setReviewList:(NSArray<FYVocabularyEntry *> *)value { self.core.reviewList=value; }
- (NSInteger)reviewIndex { return self.core.reviewIndex; }
- (void)setReviewIndex:(NSInteger)value { self.core.reviewIndex=value; }
- (FYVocabularyEntry *)reviewingEntry { return self.core.reviewingEntry; }
- (void)setReviewingEntry:(FYVocabularyEntry *)value { self.core.reviewingEntry=value; }
- (void)setReviewPromptText:(NSString *)value { self.facts.prompt.stringValue=value; }
- (void)setReviewWordText:(NSString *)value { self.facts.word.stringValue=value; }
- (void)setReviewMeaningText:(NSString *)value { self.facts.meaning.stringValue=value; }
- (void)setReviewWordHidden:(BOOL)value { self.facts.word.hidden=value; }
- (void)setReviewMeaningHidden:(BOOL)value { self.facts.meaning.hidden=value; }
- (void)setVocabularyEmptyHidden:(BOOL)value { self.facts.empty.hidden=value; }
- (void)setVocabularyListHidden:(BOOL)value { self.facts.list.hidden=value; }
- (void)setVocabularyListText:(NSString *)value { self.facts.list.stringValue=value; }
- (void)refreshVocabularyList { [self.core refreshVocabularyWithReceiver:self]; }
- (void)nextReviewWord:(id)sender { [self.core nextWordWithReceiver:self]; }
- (void)revealReviewMeaning:(id)sender { [self.core revealMeaningWithReceiver:self]; }
- (void)markReviewKnown:(id)sender { [self.core markKnownWithReceiver:self]; }
- (void)markReviewLearning:(id)sender { [self.core markLearningWithReceiver:self]; }
- (void)setReviewStatus:(FYReviewStatus)status { [self.core setStatus:status receiver:self]; }
- (void)removeReviewWord:(id)sender { [self.core removeWordWithReceiver:self]; }
@end
static id<CollectionReviewDriver> Source(CollectionReviewFacts*f){CollectionReviewFixture*s=[CollectionReviewFixture new];s.facts=f;return s;}
int main(void){@autoreleasepool{FYCollectionReviewCoordinator*c=[FYCollectionReviewCoordinator new];unsigned count=0;Ivar*v=class_copyIvarList(c.class,&count);free(v);Check(count==3&&!class_getInstanceVariable(c.class,"_receiver")&&!class_getInstanceVariable(c.class,"_store"),@"review owns exactly original three fields without native/source/store");CollectionReviewFacts*f=[CollectionReviewFacts new];RunReview(Source(f),f);RunLeases(^id<CollectionReviewDriver>(CollectionReviewFacts*f){return Source(f);});printf("PASS CollectionReviewTests: %lu checks; seven real Foundation workflows/canonical selection\n",(unsigned long)checks);}return 0;}
