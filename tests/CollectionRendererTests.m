#import "presentation/FYCollectionController.h"
#import "FYCollectionRendererTestFacts.h"
@interface CollectionRenderFixture : NSObject <FYCollectionRenderSource,FYCollectionQuerySource,FYCollectionCardSource,CollectionRendererDriver>
@property(nonatomic,strong) CollectionWorkflowFacts *facts;
@property(nonatomic,strong) NSObject *actionTarget;
@property(nonatomic,strong) FYCollectionQueryCoordinator *queryCoordinator;
@property(nonatomic,strong) FYCollectionCardCoordinator *cardCoordinator;
@property(nonatomic,weak) id host;
@property(nonatomic, strong) NSTextField *grammarBookmarkListLabel;
@property(nonatomic, strong) NSPopUpButton *grammarBookmarkPopup;
@property(nonatomic, strong) NSStackView *grammarBookmarkStack;
@property(nonatomic, strong) NSStackView *historyListStack;
@property(nonatomic, strong) NSPopUpButton *historyPopup;
@property(nonatomic, strong) NSButton *knownButton;
@property(nonatomic, strong) NSTextField *learningCollectionCount;
@property(nonatomic, strong) NSStackView *learningCollectionHost;
@property(nonatomic) NSInteger learningCollectionIndex;
@property(nonatomic, copy) NSArray<NSView *> *learningCollectionSections;
@property(nonatomic, copy) NSArray<NSButton *> *learningCollectionTabs;
@property(nonatomic, strong) NSTextField *learningCollectionTitle;
@property(nonatomic, strong) NSButton *notYetButton;
@property(nonatomic, strong) NSButton *revealButton;
@property(nonatomic) NSInteger reviewIndex;
@property(nonatomic, strong) NSArray<FYVocabularyEntry *> *reviewList;
@property(nonatomic, strong) NSTextField *reviewMeaningLabel;
@property(nonatomic, strong) NSTextField *reviewPromptLabel;
@property(nonatomic, strong) NSTextField *reviewWordLabel;
@property(nonatomic, strong) FYVocabularyEntry *reviewingEntry;
@property(nonatomic, strong) NSStackView *savedGrammarCardStack;
@property(nonatomic, strong) NSStackView *savedSentenceStack;
@property(nonatomic, strong) NSView *vocabularyEmptyCard;
@property(nonatomic, strong) NSTextField *vocabularyExamplesLabel;
@property(nonatomic, strong) NSPopUpButton *vocabularyExamplesPopup;
@property(nonatomic, strong) NSTextField *vocabularyListLabel;
@property(nonatomic, strong) NSTextField *vocabularyStatusLabel;
@property(nonatomic, strong) NSStackView *wordCardStack;
@property(nonatomic) NSInteger wordCardsGeneration;
@end
@implementation CollectionRenderFixture
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
- (NSStackView*)verticalStack{return (NSStackView*)Node();}
- (NSStackView*)horizontalStack{return (NSStackView*)Node();}
- (NSTextField*)label:(NSString*)text font:(NSFont*)font color:(NSColor*)color{return (NSTextField*)Label(text,font,color);}
- (NSTextField*)mutedLabel:(NSString*)text{return (NSTextField*)Label(text,[NSFont systemFontOfSize:12],[NSColor grayColor]);}
- (NSTextField*)cardTitle:(NSString*)text{return (NSTextField*)Label(text,[NSFont boldSystemFontOfSize:15],[NSColor brownColor]);}
- (NSView*)spacer{return (NSView*)Node();}
- (NSView*)separator{return (NSView*)Node();}
- (NSView*)cardWithStack:(NSStackView*)stack{CollectionNodeFact*n=Node();[n addArrangedSubview:(id)stack];return(NSView*)n;}
- (NSButton*)workspaceButton:(NSString*)title action:(SEL)action primary:(BOOL)primary{return ButtonFactory(nil,NULL,title,self.actionTarget,action);}
- (NSColor*)uiInk{return NSColor.brownColor;}
- (NSColor*)uiMuted{return NSColor.grayColor;}
- (FYGrammarCatalog*)grammarCatalog{return nil;}
- (void)clearArrangedSubviews:(NSStackView*)stack{for(CollectionNodeFact*n in [(id)stack arrangedSubviews])n.superview=nil;[((CollectionNodeFact*)stack).arrangedSubviews removeAllObjects];}
- (NSButton*)grammarDetailBookmarkButton{return(NSButton*)self.facts.mainButton;}
- (NSButton*)quickSentenceBookmarkButton{return(NSButton*)self.facts.quickButton;}
- (id)collectionActionTarget { return self.host; }
- (void)clearHistoryRows { [self clearArrangedSubviews:self.historyListStack]; }
- (void)appendHistoryMessage:(NSString *)text { [self.historyListStack addArrangedSubview:[self mutedLabel:text]]; }
- (void)renderHistoryRows { [FYCollectionRenderer renderHistoryRowsWithReceiver:self]; }
- (void)clearSavedGrammarRows { [self clearArrangedSubviews:self.savedGrammarCardStack]; }
- (void)renderSavedGrammarRows { [FYCollectionRenderer renderGrammarRowsWithReceiver:self]; }
- (void)clearSavedSentenceRows { [self clearArrangedSubviews:self.savedSentenceStack]; }
- (void)renderSavedSentenceRows:(NSArray<FYRequestIdentity *> *)identities { [FYCollectionRenderer renderSentenceRows:identities receiver:self]; }
- (void)setGrammarBookmarkListText:(NSString *)text { self.grammarBookmarkListLabel.stringValue=text; }
- (void)setGrammarBookmarkListHidden:(BOOL)hidden { self.grammarBookmarkListLabel.hidden=hidden; }
- (void)setMainGrammarBookmarkTitle:(NSString *)text { self.grammarDetailBookmarkButton.title=text; }
- (void)setQuickSentenceBookmarkTitle:(NSString *)text { self.quickSentenceBookmarkButton.title=text; }
- (void)setQuickSentenceBookmarkEnabled:(BOOL)enabled { self.quickSentenceBookmarkButton.enabled=enabled; }
- (void)setVocabularyStatusText:(NSString *)text { self.vocabularyStatusLabel.stringValue=text; }
- (void)clearVocabularyExampleChoices { [self.vocabularyExamplesPopup removeAllItems]; }
- (void)addVocabularyExampleChoice:(NSString *)text { [self.vocabularyExamplesPopup addItemWithTitle:text]; }
- (NSInteger)selectedVocabularyExampleIndex { return self.vocabularyExamplesPopup.indexOfSelectedItem; }
- (void)setVocabularyExamplesText:(NSString *)text { self.vocabularyExamplesLabel.stringValue=text; }
- (void)loadExamplesForWord:(NSString *)word generation:(NSInteger)generation sourceLabel:(NSTextField *)label exampleButton:(NSButton *)button {
    [self.queryCoordinator loadCardExamplesForWord:word generation:generation receiver:self text:^(NSString *text){label.stringValue=text;} hidden:^(BOOL hidden){button.hidden=hidden;}];
}

- (void)openHistoryAnalysis:(NSButton *)sender { [self.queryCoordinator openHistoryWithReceiver:self tag:^NSInteger{return sender.tag;} identifier:^NSString *{return sender.identifier;}]; }
- (void)refreshHistory { [self.queryCoordinator refreshHistoryWithReceiver:self]; }
- (void)refreshGrammarBookmarks:(id)sender { [self.queryCoordinator refreshGrammarWithReceiver:self]; }
- (void)deleteGrammarBookmark:(NSButton *)sender { [self.queryCoordinator deleteGrammarWithReceiver:self identifier:^NSString *{return sender.identifier;}]; }
- (void)refreshVocabularyExamplesPopup { [self.queryCoordinator refreshExampleChoicesWithReceiver:self]; }
- (void)showVocabularyExamples:(id)sender { [self.queryCoordinator showExamplesWithReceiver:self]; }
- (void)refreshSavedSentences { [self.queryCoordinator refreshSentencesWithReceiver:self]; }
- (FYRequestIdentity *)savedSentenceForButton:(NSButton *)sender { return [self.queryCoordinator sentenceWithReceiver:self identifier:^NSString *{return sender.identifier;}]; }
- (void)openSavedSentence:(NSButton *)sender { [self.queryCoordinator openSentenceWithReceiver:self identity:^FYRequestIdentity *{return [self savedSentenceForButton:sender];}]; }
- (void)removeSavedSentence:(NSButton *)sender { [self.queryCoordinator removeSentenceWithReceiver:self identity:^FYRequestIdentity *{return [self savedSentenceForButton:sender];} disable:^{sender.enabled=NO;}]; }
- (FYVocabularyEntry *)wordForCardButton:(NSButton *)sender { return [self.cardCoordinator wordWithReceiver:self identifier:^NSString *{return sender.identifier;} tag:^NSInteger{return sender.tag;}]; }
- (void)nextWordExample:(NSButton *)sender { [self.cardCoordinator nextExampleWithReceiver:self identifier:^NSString *{return sender.identifier;}]; }
- (void)toggleSavedWordDetails:(NSButton *)sender { [self.cardCoordinator toggleDetailsWithReceiver:self word:^FYVocabularyEntry *{return [self wordForCardButton:sender];} update:^(BOOL expanded){[FYCollectionRenderer updateDetailsButton:sender expanded:expanded];}]; }
- (void)toggleWordMeaning:(NSButton *)sender { [self.cardCoordinator toggleMeaningWithReceiver:self word:^FYVocabularyEntry *{return [self wordForCardButton:sender];} update:^(FYVocabularyEntry *entry,BOOL revealed){[FYCollectionRenderer updateMeaningButton:sender entry:entry revealed:revealed];}]; }
- (void)toggleWordMastered:(NSButton *)sender { [self.cardCoordinator toggleMasteredWithReceiver:self word:^FYVocabularyEntry *{return [self wordForCardButton:sender];}]; }
- (void)removeWordCard:(NSButton *)sender { [self.cardCoordinator removeWordWithReceiver:self word:^FYVocabularyEntry *{return [self wordForCardButton:sender];}]; }
- (NSView *)makeVocabularyPage { return [FYCollectionRenderer makeVocabularyPageWithReceiver:self]; }
- (NSView *)makeHistoryPage { return [FYCollectionRenderer makeHistoryPageWithReceiver:self]; }
- (void)updateLearningCollectionSummary { [FYCollectionRenderer updateSummaryWithReceiver:self]; }
- (void)selectLearningCollection:(NSButton *)sender { [FYCollectionRenderer selectCollection:sender receiver:self]; }
- (void)rebuildWordCards { [FYCollectionRenderer rebuildWordCardsWithReceiver:self]; }
- (void)setReviewPromptText:(NSString*)text{self.reviewPromptLabel.stringValue=text;}
@end
static void Setup(id s,CollectionWorkflowFacts*f){[s setValue:f forKey:@"facts"];[s setValue:[NSObject new] forKey:@"actionTarget"];for(NSString*name in @[@"historyListStack",@"savedGrammarCardStack",@"savedSentenceStack",@"wordCardStack",@"learningCollectionHost"]){[s setValue:Node() forKey:name];}[s setValue:f.grammarLabel forKey:@"grammarBookmarkListLabel"];[s setValue:f.statusLabel forKey:@"vocabularyStatusLabel"];[s setValue:f.examplesLabel forKey:@"vocabularyExamplesLabel"];[s setValue:f.popup forKey:@"vocabularyExamplesPopup"];[s setValue:f.prompt forKey:@"reviewPromptLabel"];}
static id<CollectionRendererDriver> Source(CollectionWorkflowFacts*f){CollectionRenderFixture*s=[CollectionRenderFixture new];Setup(s,f);s.host=(id)s.actionTarget;return s;}
int main(void){@autoreleasepool{FYCollectionRenderer*r=[FYCollectionRenderer new];unsigned n=0;Ivar*v=class_copyIvarList(r.class,&n);free(v);Check(n==0,@"native renderer has zero stored state");InstallFactories();CollectionWorkflowFacts*f=[CollectionWorkflowFacts new];RunRenderer(Source(f),f);RestoreFactories();printf("PASS CollectionRendererTests: %lu checks\n",(unsigned long)checks);}return 0;}
