#import "presentation/FYGrammarPresentationController.h"
#import "FYGrammarBookmarkTestFacts.h"
@interface GrammarBookmarkHostFixture : FYGrammarPresentationController <GrammarBookmarkDriver>
@property(nonatomic,strong) GrammarBookmarkFacts *facts;
@end
@implementation GrammarBookmarkHostFixture
- (FYAnalysisResult *)currentAnalysis{return [self.facts currentAnalysis];}
- (BOOL)analysisMatchesCurrentSentence{return [self.facts analysisMatchesCurrentSentence];}
- (FYGrammarItem *)selectedGrammarItem{return [self.facts selectedGrammarItem];}
- (FYGrammarBookmark *)bookmarkForCurrentGrammar{return [self.facts bookmarkForCurrentGrammar];}
- (FYLearningCoordinator *)learningCoordinator{return (FYLearningCoordinator *)self.facts.learning;}
- (FYLearningStore *)learningStore{return (FYLearningStore *)self.facts.store;}
- (NSTextField *)grammarStatusLabel{return (NSTextField *)self.facts.field;}
- (NSButton *)grammarDetailBookmarkButton{return (NSButton *)self.facts.button;}
- (void)refreshGrammarBookmarks:(id)sender{[self.facts refreshGrammarBookmarks:sender];}
- (void)performItem:(BookmarkSenderFact *)sender{[self bookmarkGrammarItem:(NSButton *)sender];}
- (void)performSelected{[self bookmarkSelectedGrammar:nil];}
@end
static id<GrammarBookmarkDriver> Source(GrammarBookmarkFacts *facts){GrammarBookmarkHostFixture *s=[[GrammarBookmarkHostFixture alloc]initWithHost:nil];s.facts=facts;return s;}
int main(void){@autoreleasepool{Check(NSApp==nil,@"actual native bookmark fixture creates no controls/window/app");GrammarBookmarkFacts *f=[GrammarBookmarkFacts new];RunGrammarBookmarkFixture(Source(f),f);RunGrammarBookmarkLeases(^id<GrammarBookmarkDriver>(GrammarBookmarkFacts *facts){return Source(facts);});Check(NSApp==nil,@"native adapters and both algorithms remain headless");printf("PASS GrammarBookmarkHostTests: %lu checks; actual original/new controller same fixture and strong task leases\n",(unsigned long)checks);}return 0;}
