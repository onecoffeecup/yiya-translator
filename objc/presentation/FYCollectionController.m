#import "FYCollectionController.h"
#import "../app/FYAppSupport.h"

@interface FYCollectionController ()
@property(nonatomic,strong,readwrite) FYCollectionQueryCoordinator *queryCoordinator;
@property(nonatomic,strong,readwrite) FYCollectionCardCoordinator *cardCoordinator;
@property(nonatomic, strong, readwrite) FYCollectionReviewCoordinator *reviewCoordinator;
@property(nonatomic, strong) FYAnalysisResult *currentAnalysis;
@property(nonatomic, strong) FYGrammarCatalog *grammarCatalog;
@property(nonatomic, strong) NSButton *grammarDetailBookmarkButton;
@property(nonatomic, strong) FYLearningCoordinator *learningCoordinator;
@property(nonatomic, strong) FYLearningStore *learningStore;
@property(nonatomic, strong) NSButton *quickSentenceBookmarkButton;
@property(nonatomic, copy) NSString *quickSentenceID;
@property(nonatomic) BOOL sentenceBookmarkPending;
@end

@implementation FYCollectionController
- (instancetype)initWithHost:(id<FYCollectionControllerHost>)host {
    if ((self = [super init])) { _host = host; _reviewCoordinator = [FYCollectionReviewCoordinator new]; _queryCoordinator=[FYCollectionQueryCoordinator new]; _cardCoordinator=[FYCollectionCardCoordinator new]; }
    return self;
}



// Each persisted-list snapshot and card interaction container has one owner.
- (NSArray<FYSentenceRecord *> *)historyRecords { return self.queryCoordinator.historyRecords; }
- (void)setHistoryRecords:(NSArray<FYSentenceRecord *> *)value { self.queryCoordinator.historyRecords=value; }
- (NSArray<FYGrammarBookmark *> *)grammarBookmarks { return self.queryCoordinator.grammarBookmarks; }
- (void)setGrammarBookmarks:(NSArray<FYGrammarBookmark *> *)value { self.queryCoordinator.grammarBookmarks=value; }
- (NSArray<FYVocabularyEntry *> *)vocabularyExamplesList { return self.queryCoordinator.vocabularyExamplesList; }
- (void)setVocabularyExamplesList:(NSArray<FYVocabularyEntry *> *)value { self.queryCoordinator.vocabularyExamplesList=value; }
- (NSArray<FYRequestIdentity *> *)savedSentences { return self.queryCoordinator.savedSentences; }
- (void)setSavedSentences:(NSArray<FYRequestIdentity *> *)value { self.queryCoordinator.savedSentences=value; }
- (NSMutableSet<NSString *> *)expandedWordCards { return self.cardCoordinator.expandedWordCards; }
- (void)setExpandedWordCards:(NSMutableSet<NSString *> *)value { self.cardCoordinator.expandedWordCards=value; }
- (NSMutableDictionary<NSString *, NSNumber *> *)revealedMeanings { return self.cardCoordinator.revealedMeanings; }
- (void)setRevealedMeanings:(NSMutableDictionary<NSString *, NSNumber *> *)value { self.cardCoordinator.revealedMeanings=value; }
- (NSMutableDictionary<NSString *, NSNumber *> *)wordExampleIndices { return self.cardCoordinator.wordExampleIndices; }
- (void)setWordExampleIndices:(NSMutableDictionary<NSString *, NSNumber *> *)value { self.cardCoordinator.wordExampleIndices=value; }
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

// Review fields have one physical owner; existing callers retain their accessors.
- (NSArray<FYVocabularyEntry *> *)reviewList { return self.reviewCoordinator.reviewList; }
- (void)setReviewList:(NSArray<FYVocabularyEntry *> *)value { self.reviewCoordinator.reviewList = value; }
- (NSInteger)reviewIndex { return self.reviewCoordinator.reviewIndex; }
- (void)setReviewIndex:(NSInteger)value { self.reviewCoordinator.reviewIndex = value; }
- (FYVocabularyEntry *)reviewingEntry { return self.reviewCoordinator.reviewingEntry; }
- (void)setReviewingEntry:(FYVocabularyEntry *)value { self.reviewCoordinator.reviewingEntry = value; }

// Explicit native effects; business code does not read controls.
- (void)setReviewPromptText:(NSString *)value { self.reviewPromptLabel.stringValue = value; }
- (void)setReviewWordText:(NSString *)value { self.reviewWordLabel.stringValue = value; }
- (void)setReviewMeaningText:(NSString *)value { self.reviewMeaningLabel.stringValue = value; }
- (void)setReviewWordHidden:(BOOL)value { self.reviewWordLabel.hidden = value; }
- (void)setReviewMeaningHidden:(BOOL)value { self.reviewMeaningLabel.hidden = value; }
- (void)setVocabularyEmptyHidden:(BOOL)value { self.vocabularyEmptyCard.hidden = value; }
- (void)setVocabularyListHidden:(BOOL)value { self.vocabularyListLabel.hidden = value; }
- (void)setVocabularyListText:(NSString *)value { self.vocabularyListLabel.stringValue = value; }

// Explicit peer adapters. Every property has one owning controller.
- (FYAnalysisResult *)currentAnalysis { return self.host.currentAnalysis; }
- (void)setCurrentAnalysis:(FYAnalysisResult *)value { self.host.currentAnalysis = value; }
- (FYGrammarCatalog *)grammarCatalog { return self.host.grammarCatalog; }
- (void)setGrammarCatalog:(FYGrammarCatalog *)value { self.host.grammarCatalog = value; }
- (NSButton *)grammarDetailBookmarkButton { return self.host.grammarDetailBookmarkButton; }
- (void)setGrammarDetailBookmarkButton:(NSButton *)value { self.host.grammarDetailBookmarkButton = value; }
- (FYLearningCoordinator *)learningCoordinator { return self.host.learningCoordinator; }
- (void)setLearningCoordinator:(FYLearningCoordinator *)value { self.host.learningCoordinator = value; }
- (FYLearningStore *)learningStore { return self.host.learningStore; }
- (void)setLearningStore:(FYLearningStore *)value { self.host.learningStore = value; }
- (NSButton *)quickSentenceBookmarkButton { return self.host.quickSentenceBookmarkButton; }
- (void)setQuickSentenceBookmarkButton:(NSButton *)value { self.host.quickSentenceBookmarkButton = value; }
- (NSString *)quickSentenceID { return self.host.quickSentenceID; }
- (void)setQuickSentenceID:(NSString *)value { self.host.quickSentenceID = value; }
- (BOOL)sentenceBookmarkPending { return self.host.sentenceBookmarkPending; }
- (void)setSentenceBookmarkPending:(BOOL)value { self.host.sentenceBookmarkPending = value; }

- (void)selectPageAtIndex:(NSInteger)index { [self.host selectPageAtIndex:index]; }
- (void)analyzeCurrentSentence:(id)sender { [self.host analyzeCurrentSentence:sender]; }
- (FYGrammarBookmark *)bookmarkForCurrentGrammar { return [self.host bookmarkForCurrentGrammar]; }
- (BOOL)analysisMatchesCurrentSentence { return [self.host analysisMatchesCurrentSentence]; }
- (void)clearAnalysisDisplay { [self.host clearAnalysisDisplay]; }
- (void)refreshLearningSource { [self.host refreshLearningSource]; }
- (void)refreshLearningStatus { [self.host refreshLearningStatus]; }
- (void)clearArrangedSubviews:(NSStackView *)stack { [self.host clearArrangedSubviews:stack]; }
- (NSStackView *)verticalStack { return [self.host verticalStack]; }
- (NSStackView *)horizontalStack { return [self.host horizontalStack]; }
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color { return [self.host label:text font:font color:color]; }
- (NSView *)spacer { return [self.host spacer]; }
- (NSView *)separator { return [self.host separator]; }
- (NSColor *)uiInk { return [self.host uiInk]; }
- (NSColor *)uiMuted { return [self.host uiMuted]; }
- (NSView *)cardWithStack:(NSStackView *)stack { return [self.host cardWithStack:stack]; }
- (NSTextField *)cardTitle:(NSString *)text { return [self.host cardTitle:text]; }
- (NSTextField *)mutedLabel:(NSString *)text { return [self.host mutedLabel:text]; }
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary { return [self.host workspaceButton:title action:action primary:primary]; }
- (BOOL)quickSentenceIsBookmarked { return [self.host quickSentenceIsBookmarked]; }
- (void)updateQuickGrammarBookmark { [self.host updateQuickGrammarBookmark]; }

- (NSView *)makeVocabularyPage { return [FYCollectionRenderer makeVocabularyPageWithReceiver:self]; }

- (void)updateLearningCollectionSummary { [FYCollectionRenderer updateSummaryWithReceiver:self]; }

- (void)selectLearningCollection:(NSButton *)sender { [FYCollectionRenderer selectCollection:sender receiver:self]; }

- (void)openHistoryAnalysis:(NSButton *)sender { [self.queryCoordinator openHistoryWithReceiver:self tag:^NSInteger{return sender.tag;} identifier:^NSString *{return sender.identifier;}]; }

- (void)refreshHistory { [self.queryCoordinator refreshHistoryWithReceiver:self]; }

- (void)refreshHistoryAction:(id)sender {
    [self refreshHistory];
}

- (void)historyChanged:(id)sender {
    // 历史列表已改为行式入口，见 refreshHistory / openHistoryAnalysis:。
}

- (void)refreshVocabularyList { [self.reviewCoordinator refreshVocabularyWithReceiver:self]; }

- (void)rebuildWordCards { [FYCollectionRenderer rebuildWordCardsWithReceiver:self]; }

- (void)toggleSavedWordDetails:(NSButton *)sender { [self.cardCoordinator toggleDetailsWithReceiver:self word:^FYVocabularyEntry *{return [self wordForCardButton:sender];} update:^(BOOL expanded){[FYCollectionRenderer updateDetailsButton:sender expanded:expanded];}]; }

- (FYVocabularyEntry *)wordForCardButton:(NSButton *)sender { return [self.cardCoordinator wordWithReceiver:self identifier:^NSString *{return sender.identifier;} tag:^NSInteger{return sender.tag;}]; }

- (void)nextWordExample:(NSButton *)sender { [self.cardCoordinator nextExampleWithReceiver:self identifier:^NSString *{return sender.identifier;}]; }

- (void)toggleWordMeaning:(NSButton *)sender { [self.cardCoordinator toggleMeaningWithReceiver:self word:^FYVocabularyEntry *{return [self wordForCardButton:sender];} update:^(FYVocabularyEntry *entry,BOOL revealed){[FYCollectionRenderer updateMeaningButton:sender entry:entry revealed:revealed];}]; }

- (void)toggleWordMastered:(NSButton *)sender { [self.cardCoordinator toggleMasteredWithReceiver:self word:^FYVocabularyEntry *{return [self wordForCardButton:sender];}]; }

- (void)removeWordCard:(NSButton *)sender { [self.cardCoordinator removeWordWithReceiver:self word:^FYVocabularyEntry *{return [self wordForCardButton:sender];}]; }

- (void)nextReviewWord:(id)sender { [self.reviewCoordinator nextWordWithReceiver:self]; }

- (void)revealReviewMeaning:(id)sender { [self.reviewCoordinator revealMeaningWithReceiver:self]; }

- (void)markReviewKnown:(id)sender { [self.reviewCoordinator markKnownWithReceiver:self]; }

- (void)markReviewLearning:(id)sender { [self.reviewCoordinator markLearningWithReceiver:self]; }

- (void)setReviewStatus:(FYReviewStatus)status { [self.reviewCoordinator setStatus:status receiver:self]; }

- (void)removeReviewWord:(id)sender { [self.reviewCoordinator removeWordWithReceiver:self]; }

- (void)refreshGrammarBookmarks:(id)sender { [self.queryCoordinator refreshGrammarWithReceiver:self]; }

- (void)grammarBookmarkChanged:(id)sender {
    // 删除按 popup 当前选中项执行。
}

- (void)deleteGrammarBookmark:(NSButton *)sender { [self.queryCoordinator deleteGrammarWithReceiver:self identifier:^NSString *{return sender.identifier;}]; }

- (void)refreshVocabularyExamplesPopup { [self.queryCoordinator refreshExampleChoicesWithReceiver:self]; }

- (void)vocabularyExamplesChanged:(id)sender {
    // 例句按 popup 当前选中项读取。
}

- (void)showVocabularyExamples:(id)sender { [self.queryCoordinator showExamplesWithReceiver:self]; }

- (NSView *)makeHistoryPage { return [FYCollectionRenderer makeHistoryPageWithReceiver:self]; }

- (void)refreshSavedSentences { [self.queryCoordinator refreshSentencesWithReceiver:self]; }

- (FYRequestIdentity *)savedSentenceForButton:(NSButton *)sender { return [self.queryCoordinator sentenceWithReceiver:self identifier:^NSString *{return sender.identifier;}]; }

- (void)openSavedSentence:(NSButton *)sender { [self.queryCoordinator openSentenceWithReceiver:self identity:^FYRequestIdentity *{return [self savedSentenceForButton:sender];}]; }

- (void)removeSavedSentence:(NSButton *)sender { [self.queryCoordinator removeSentenceWithReceiver:self identity:^FYRequestIdentity *{return [self savedSentenceForButton:sender];} disable:^{sender.enabled=NO;}]; }

@end
