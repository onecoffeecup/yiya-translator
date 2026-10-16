#import "FYGrammarBookmarkTestFacts.h"
#import <objc/runtime.h>
@interface GrammarBookmarkSourceFixture : NSObject <FYGrammarBookmarkSource,GrammarBookmarkDriver>
@property(nonatomic,strong) GrammarBookmarkFacts *facts;
@end
@implementation GrammarBookmarkSourceFixture
- (FYAnalysisResult *)currentAnalysis{return [self.facts currentAnalysis];}
- (BOOL)analysisMatchesCurrentSentence{return [self.facts analysisMatchesCurrentSentence];}
- (FYGrammarItem *)selectedGrammarItem{return [self.facts selectedGrammarItem];}
- (FYGrammarBookmark *)bookmarkForCurrentGrammar{return [self.facts bookmarkForCurrentGrammar];}
- (FYLearningCoordinator *)learningCoordinator{return (FYLearningCoordinator *)self.facts.learning;}
- (FYLearningStore *)learningStore{return (FYLearningStore *)self.facts.store;}
- (BOOL)grammarBookmarkActionEnabled{return self.facts.button.isEnabled;}
- (void)setGrammarBookmarkActionEnabled:(BOOL)enabled{self.facts.button.enabled=enabled;}
- (void)setGrammarStatusText:(NSString *)text{self.facts.field.stringValue=text;}
- (void)refreshGrammarBookmarks:(id)sender{[self.facts refreshGrammarBookmarks:sender];}
- (void)performItem:(BookmarkSenderFact *)sender{[FYGrammarInteractionCoordinator bookmarkGrammarItemWithIndexProvider:^NSInteger{return sender.tag;} receiver:self];}
- (void)performSelected{[FYGrammarInteractionCoordinator bookmarkSelectedGrammarWithReceiver:self];}
@end
static id<GrammarBookmarkDriver> Source(GrammarBookmarkFacts *facts){GrammarBookmarkSourceFixture *s=[GrammarBookmarkSourceFixture new];s.facts=facts;return s;}
int main(void){@autoreleasepool{unsigned int count=0;Ivar *v=class_copyIvarList(FYGrammarInteractionCoordinator.class,&count);free(v);Check(count==7&&!class_getInstanceVariable(FYGrammarInteractionCoordinator.class,"_receiver")&&!class_getInstanceVariable(FYGrammarInteractionCoordinator.class,"_store"),@"bookmark operations add no state/idle source or store to original Core7");GrammarBookmarkFacts *f=[GrammarBookmarkFacts new];RunGrammarBookmarkFixture(Source(f),f);RunGrammarBookmarkLeases(^id<GrammarBookmarkDriver>(GrammarBookmarkFacts *facts){return Source(facts);});printf("PASS GrammarBookmarkTests: %lu checks; Foundation actual two algorithms/canonical gates and synthetic services\n",(unsigned long)checks);}return 0;}
