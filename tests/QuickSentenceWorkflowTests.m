#import "FYQuickSentenceTestFacts.h"
#import "presentation/FYPresentationText.h"
@interface QuickSentenceSourceFixture : NSObject <FYQuickSentenceAnalysisSource,FYQuickSentenceBookmarkSource,QuickSentenceDriver>
@property(nonatomic,strong) QuickSentenceFacts *facts;
@property(nonatomic,strong) FYQuickSentenceCoordinator *core;
@end
@implementation QuickSentenceSourceFixture
- (instancetype)init{if((self=[super init]))_core=[FYQuickSentenceCoordinator new];return self;}
- (NSInteger)quickAnalysisGeneration { return self.core.quickAnalysisGeneration; }
- (void)setQuickAnalysisGeneration:(NSInteger)value { self.core.quickAnalysisGeneration=value; }
- (BOOL)quickSentenceAnalyzing { return self.core.quickSentenceAnalyzing; }
- (void)setQuickSentenceAnalyzing:(BOOL)value { self.core.quickSentenceAnalyzing=value; }
- (FYAnalysisResult *)quickSentenceAnalysis { return self.core.quickSentenceAnalysis; }
- (void)setQuickSentenceAnalysis:(FYAnalysisResult *)value { self.core.quickSentenceAnalysis=value; }
- (NSString *)quickSentenceAnalysisError { return self.core.quickSentenceAnalysisError; }
- (void)setQuickSentenceAnalysisError:(NSString *)value { self.core.quickSentenceAnalysisError=value; }
- (NSString *)quickSentenceAnalysisSource { return self.core.quickSentenceAnalysisSource; }
- (void)setQuickSentenceAnalysisSource:(NSString *)value { self.core.quickSentenceAnalysisSource=value; }
- (NSString *)quickSentenceAnalysisTranslation { return self.core.quickSentenceAnalysisTranslation; }
- (void)setQuickSentenceAnalysisTranslation:(NSString *)value { self.core.quickSentenceAnalysisTranslation=value; }
- (FYLearningAnalyzer *)quickSentenceAnalyzer { return self.core.quickSentenceAnalyzer; }
- (void)setQuickSentenceAnalyzer:(FYLearningAnalyzer *)value { self.core.quickSentenceAnalyzer=value; }
- (BOOL)sentenceBookmarkPending { return self.core.sentenceBookmarkPending; }
- (void)setSentenceBookmarkPending:(BOOL)value { self.core.sentenceBookmarkPending=value; }
- (BOOL)quickGrammarBookmarkPending { return self.core.quickGrammarBookmarkPending; }
- (void)setQuickGrammarBookmarkPending:(BOOL)value { self.core.quickGrammarBookmarkPending=value; }
- (void)disableQuickSentenceBookmarkAction{self.facts.button.enabled=NO;}
- (void)setQuickBookmarkStatusText:(NSString *)text{self.facts.status.stringValue=text;}
- (void)configureQuickSentenceAnalyzer:(FYLearningAnalyzer *)analyzer {
    analyzer.baseURL=self.facts.base.stringValue ?: @"";analyzer.apiKey=self.facts.key.stringValue ?: @"";
    NSString *model=Trim(self.facts.model.stringValue);
    analyzer.model=model.length?model:self.facts.fallbackModel.stringValue;analyzer.catalog=self.grammarCatalog;
}

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
- (void)cancelQuickSentenceAnalysis { [self.core cancelAnalysisWithReceiver:self]; }
- (void)analyzeQuickSentence:(id)sender { [self.core analyzeWithReceiver:self]; }
- (BOOL)quickSentenceIsBookmarked { return [self.core sentenceIsBookmarkedWithReceiver:self]; }
- (void)bookmarkQuickSentence:(id)sender { [self.core bookmarkSentenceWithReceiver:self]; }
- (FYGrammarBookmark *)quickGrammarBookmark { return [self.core grammarBookmarkWithReceiver:self]; }
- (void)bookmarkQuickGrammar:(id)sender { [self.core bookmarkGrammarWithReceiver:self]; }
@end
static id<QuickSentenceDriver> Source(QuickSentenceFacts*f){QuickSentenceSourceFixture*s=[QuickSentenceSourceFixture new];s.facts=f;return s;}
int main(void){@autoreleasepool{FYQuickSentenceCoordinator*c=[FYQuickSentenceCoordinator new];unsigned count=0;Ivar*v=class_copyIvarList(c.class,&count);free(v);Check(count==9&&!class_getInstanceVariable(c.class,"_receiver")&&!class_getInstanceVariable(c.class,"_store"),@"Foundation quick workflow owns only original nine fields without idle receiver/store");QuickSentenceFacts*f=[QuickSentenceFacts new];RunQuickSentenceFixture(Source(f),f);RunQuickSentenceLeases(^id<QuickSentenceDriver>(QuickSentenceFacts*f){return Source(f);});printf("PASS QuickSentenceWorkflowTests: %lu checks; six real Foundation algorithms/canonical identity/ActionState with held services\n",(unsigned long)checks);}return 0;}
