#import "presentation/FYStudyPresentationController.h"
#import "FYQuickSentenceTestFacts.h"
@interface QuickSentenceHostFixture : FYStudyPresentationController <QuickSentenceDriver>
@property(nonatomic,strong) QuickSentenceFacts *facts;
@end
@implementation QuickSentenceHostFixture

- (BOOL)quickSentenceRequested{return self.facts.requested;}
- (NSString *)quickSentenceSource{return self.facts.source;}
- (NSString *)quickSentenceTranslation{return self.facts.translation;}
- (NSString *)quickSentenceID{return self.facts.sentenceID;}
- (NSInteger)quickSentenceVersion{return self.facts.version;}
- (NSInteger)quickSelectedGrammarIndex{return self.facts.index;}
- (void)setQuickSelectedGrammarIndex:(NSInteger)value{self.facts.index=value;}
- (NSArray *)savedSentences{return self.facts.saved;}
- (NSArray *)grammarBookmarks{return self.facts.bookmarks;}
- (FYLearningStore *)learningStore{return (FYLearningStore *)self.facts.store;}
- (FYGrammarActionState *)quickGrammarActions{return self.facts.actions;}
- (FYGrammarCatalog *)grammarCatalog{[self.facts.events addObject:@"catalog-get"];return self.facts.catalog;}
- (void)renderQuickSentence{self.facts.renders++;[self.facts.events addObject:@"render"];}
- (void)refreshSavedSentences{self.facts.savedRefreshes++;[self.facts.events addObject:@"saved-refresh"];}
- (void)refreshGrammarBookmarks:(id)sender{self.facts.grammarRefreshes++;[self.facts.events addObject:@"grammar-refresh"];}
- (void)updateQuickGrammarBookmark{self.facts.buttonUpdates++;[self.facts.events addObject:@"button-update"];}

- (NSTextField *)baseURLField{return (NSTextField *)self.facts.base;}
- (NSSecureTextField *)apiKeyField{return (NSSecureTextField *)self.facts.key;}
- (NSTextField *)learningModelField{return (NSTextField *)self.facts.model;}
- (NSTextField *)modelField{return (NSTextField *)self.facts.fallbackModel;}
- (NSTextField *)quickGrammarBookmarkStatus{return (NSTextField *)self.facts.status;}
- (NSButton *)quickSentenceBookmarkButton{return (NSButton *)self.facts.button;}
@end
static id<QuickSentenceDriver> Source(QuickSentenceFacts*f){QuickSentenceHostFixture*s=[[QuickSentenceHostFixture alloc]initWithHost:nil];s.facts=f;return s;}
int main(void){@autoreleasepool{Check(NSApp==nil,@"actual native quick fixture creates no UI/application");QuickSentenceFacts*f=[QuickSentenceFacts new];RunQuickSentenceFixture(Source(f),f);RunQuickSentenceLeases(^id<QuickSentenceDriver>(QuickSentenceFacts*f){return Source(f);});Check(NSApp==nil,@"native config/BOOL/text adapters remain headless");printf("PASS QuickSentenceWorkflowHostTests: %lu checks; actual original/new controller same fixture and strong task leases\n",(unsigned long)checks);}return 0;}
