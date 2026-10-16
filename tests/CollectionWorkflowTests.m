#import "FYCollectionWorkflowTestFacts.h"
@interface CollectionWorkflowFixture : NSObject <FYCollectionQuerySource,FYCollectionCardSource,CollectionWorkflowDriver>
@property(nonatomic,strong) CollectionWorkflowFacts *facts;
@property(nonatomic,strong) NSObject *actionTarget;
@property(nonatomic,strong) FYCollectionQueryCoordinator *queryCoordinator;
@property(nonatomic,strong) FYCollectionCardCoordinator *cardCoordinator;
@property(nonatomic,strong) NSArray *reviewList;
@property(nonatomic) NSInteger wordCardsGeneration;
@end
@implementation CollectionWorkflowFixture
- (instancetype)init{if((self=[super init])){_queryCoordinator=[FYCollectionQueryCoordinator new];_cardCoordinator=[FYCollectionCardCoordinator new];}return self;}
- (NSArray<FYSentenceRecord *> *)historyRecords{return self.queryCoordinator.historyRecords;}
- (void)setHistoryRecords:(NSArray<FYSentenceRecord *> *)value{self.queryCoordinator.historyRecords=value;}
- (NSArray<FYGrammarBookmark *> *)grammarBookmarks{return self.queryCoordinator.grammarBookmarks;}
- (void)setGrammarBookmarks:(NSArray<FYGrammarBookmark *> *)value{self.queryCoordinator.grammarBookmarks=value;}
- (NSArray<FYVocabularyEntry *> *)vocabularyExamplesList{return self.queryCoordinator.vocabularyExamplesList;}
- (void)setVocabularyExamplesList:(NSArray<FYVocabularyEntry *> *)value{self.queryCoordinator.vocabularyExamplesList=value;}
- (NSArray<FYRequestIdentity *> *)savedSentences{return self.queryCoordinator.savedSentences;}
- (void)setSavedSentences:(NSArray<FYRequestIdentity *> *)value{self.queryCoordinator.savedSentences=value;}
- (NSMutableSet<NSString *> *)expandedWordCards{return self.cardCoordinator.expandedWordCards;}
- (void)setExpandedWordCards:(NSMutableSet<NSString *> *)value{self.cardCoordinator.expandedWordCards=value;}
- (NSMutableDictionary<NSString *, NSNumber *> *)revealedMeanings{return self.cardCoordinator.revealedMeanings;}
- (void)setRevealedMeanings:(NSMutableDictionary<NSString *, NSNumber *> *)value{self.cardCoordinator.revealedMeanings=value;}
- (NSMutableDictionary<NSString *, NSNumber *> *)wordExampleIndices{return self.cardCoordinator.wordExampleIndices;}
- (void)setWordExampleIndices:(NSMutableDictionary<NSString *, NSNumber *> *)value{self.cardCoordinator.wordExampleIndices=value;}
- (FYLearningStore*)learningStore{return (FYLearningStore*)self.facts.store;}
- (FYLearningCoordinator*)learningCoordinator{return (FYLearningCoordinator*)self.facts.learning;}
- (FYAnalysisResult*)currentAnalysis{return self.facts.analysis;}
- (NSString*)quickSentenceID{return self.facts.quickID;}
- (BOOL)sentenceBookmarkPending{return self.facts.pending;}
- (void)setSentenceBookmarkPending:(BOOL)value{self.facts.pending=value;}
- (BOOL)analysisMatchesCurrentSentence{return self.facts.matches;}
- (FYGrammarBookmark*)bookmarkForCurrentGrammar{return self.facts.mainBookmark;}
- (BOOL)quickSentenceIsBookmarked{return self.facts.bookmarked;}
- (void)updateQuickGrammarBookmark{self.facts.quickUpdates++;}
- (void)refreshLearningSource{[self.facts.events addObject:@"source"];}
- (void)refreshLearningStatus{[self.facts.events addObject:@"status"];}
- (void)clearAnalysisDisplay{[self.facts.events addObject:@"clear-analysis"];}
- (void)selectPageAtIndex:(NSInteger)index{[self.facts.events addObject:[NSString stringWithFormat:@"page%ld",(long)index]];}
- (void)analyzeCurrentSentence:(id)sender{[self.facts.events addObject:@"analyze"];}
- (void)refreshVocabularyList{self.facts.vocabularyRefreshes++;}
- (void)updateLearningCollectionSummary{self.facts.summaries++;if(self.facts.onSummary)self.facts.onSummary();}
- (void)rebuildWordCards{self.facts.rebuilds++;}
- (void)clearHistoryRows{}
- (void)appendHistoryMessage:(NSString*)text{}
- (void)renderHistoryRows{}
- (void)clearSavedGrammarRows{}
- (void)renderSavedGrammarRows{}
- (void)clearSavedSentenceRows{}
- (void)renderSavedSentenceRows:(NSArray*)identities{self.facts.rawRendered=identities;}
- (void)setGrammarBookmarkListText:(NSString*)text{self.facts.grammarLabel.stringValue=text;}
- (void)setGrammarBookmarkListHidden:(BOOL)value{self.facts.grammarLabel.hidden=value;}
- (void)setMainGrammarBookmarkTitle:(NSString*)text{self.facts.mainButton.title=text;}
- (void)setQuickSentenceBookmarkTitle:(NSString*)text{self.facts.quickButton.title=text;}
- (void)setQuickSentenceBookmarkEnabled:(BOOL)value{self.facts.quickButton.enabled=value;}
- (void)setVocabularyStatusText:(NSString*)text{self.facts.statusLabel.stringValue=text;}
- (void)clearVocabularyExampleChoices{[self.facts.popup removeAllItems];}
- (void)addVocabularyExampleChoice:(NSString*)text{[self.facts.popup addItemWithTitle:text];}
- (NSInteger)selectedVocabularyExampleIndex{return self.facts.popup.indexOfSelectedItem;}
- (void)setVocabularyExamplesText:(NSString*)text{self.facts.examplesLabel.stringValue=text;}
- (void)setReviewPromptText:(NSString*)text{self.facts.prompt.stringValue=text;}
- (void)openHistoryAnalysis:(CollectionValueFact *)sender { [self.queryCoordinator openHistoryWithReceiver:self tag:^NSInteger{return sender.tag;} identifier:^NSString *{return sender.identifier;}]; }
- (void)refreshHistory { [self.queryCoordinator refreshHistoryWithReceiver:self]; }
- (void)refreshGrammarBookmarks:(id)sender { [self.queryCoordinator refreshGrammarWithReceiver:self]; }
- (void)deleteGrammarBookmark:(CollectionValueFact *)sender { [self.queryCoordinator deleteGrammarWithReceiver:self identifier:^NSString *{return sender.identifier;}]; }
- (void)refreshVocabularyExamplesPopup { [self.queryCoordinator refreshExampleChoicesWithReceiver:self]; }
- (void)showVocabularyExamples:(id)sender { [self.queryCoordinator showExamplesWithReceiver:self]; }
- (void)refreshSavedSentences { [self.queryCoordinator refreshSentencesWithReceiver:self]; }
- (FYRequestIdentity *)savedSentenceForButton:(CollectionValueFact *)sender { return [self.queryCoordinator sentenceWithReceiver:self identifier:^NSString *{return sender.identifier;}]; }
- (void)openSavedSentence:(CollectionValueFact *)sender { [self.queryCoordinator openSentenceWithReceiver:self identity:^FYRequestIdentity *{return [self savedSentenceForButton:sender];}]; }
- (void)removeSavedSentence:(CollectionValueFact *)sender { [self.queryCoordinator removeSentenceWithReceiver:self identity:^FYRequestIdentity *{return [self savedSentenceForButton:sender];} disable:^{sender.enabled=NO;}]; }
- (FYVocabularyEntry *)wordForCardButton:(CollectionValueFact *)sender { return [self.cardCoordinator wordWithReceiver:self identifier:^NSString *{return sender.identifier;} tag:^NSInteger{return sender.tag;}]; }
- (void)nextWordExample:(CollectionValueFact *)sender { [self.cardCoordinator nextExampleWithReceiver:self identifier:^NSString *{return sender.identifier;}]; }
- (void)toggleSavedWordDetails:(CollectionValueFact *)sender { [self.cardCoordinator toggleDetailsWithReceiver:self word:^FYVocabularyEntry *{return [self wordForCardButton:sender];} update:^(BOOL expanded){(void)expanded;}]; }
- (void)toggleWordMeaning:(CollectionValueFact *)sender { [self.cardCoordinator toggleMeaningWithReceiver:self word:^FYVocabularyEntry *{return [self wordForCardButton:sender];} update:^(FYVocabularyEntry *entry,BOOL revealed){(void)entry;(void)revealed;}]; }
- (void)toggleWordMastered:(CollectionValueFact *)sender { [self.cardCoordinator toggleMasteredWithReceiver:self word:^FYVocabularyEntry *{return [self wordForCardButton:sender];}]; }
- (void)removeWordCard:(CollectionValueFact *)sender { [self.cardCoordinator removeWordWithReceiver:self word:^FYVocabularyEntry *{return [self wordForCardButton:sender];}]; }
@end
static id<CollectionWorkflowDriver> Source(CollectionWorkflowFacts*f){CollectionWorkflowFixture*s=[CollectionWorkflowFixture new];s.facts=f;return s;}
int main(void){@autoreleasepool{FYCollectionQueryCoordinator*q=[FYCollectionQueryCoordinator new];FYCollectionCardCoordinator*c=[FYCollectionCardCoordinator new];unsigned n=0;Ivar*v=class_copyIvarList(q.class,&n);free(v);Check(n==4&&!class_getInstanceVariable(q.class,"_receiver"),@"query has exactly original four state fields and no idle receiver");v=class_copyIvarList(c.class,&n);free(v);Check(n==3&&!class_getInstanceVariable(c.class,"_store"),@"card operations have exactly original three containers, no store");CollectionWorkflowFacts*f=[CollectionWorkflowFacts new];RunWorkflow(Source(f),f);RunWorkflowLeases(^id<CollectionWorkflowDriver>(CollectionWorkflowFacts*f){return Source(f);});printf("PASS CollectionWorkflowTests: %lu checks\n",(unsigned long)checks);}return 0;}
