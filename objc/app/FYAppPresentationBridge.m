#import "FYAppDelegateInternal.h"

// Compatibility actions and aliases only; state belongs to the existing owners.
@interface AppDelegate (FYPresentationCompatibility)
@end

@implementation AppDelegate (FYPresentationCompatibility)
- (NSWindow *)mainWindow { return [self mainWindowController].mainWindow; }

- (void)setMainWindow:(NSWindow *)value { [self mainWindowController].mainWindow = value; }

- (NSStackView *)mainWorkspaceRoot { return [self mainWindowController].mainWorkspaceRoot; }

- (void)setMainWorkspaceRoot:(NSStackView *)value { [self mainWindowController].mainWorkspaceRoot = value; }

- (NSLayoutConstraint *)workspaceWidth { return [self mainWindowController].workspaceWidth; }

- (void)setWorkspaceWidth:(NSLayoutConstraint *)value { [self mainWindowController].workspaceWidth = value; }

- (NSLayoutConstraint *)mainChatWidth { return [self mainWindowController].mainChatWidth; }

- (void)setMainChatWidth:(NSLayoutConstraint *)value { [self mainWindowController].mainChatWidth = value; }

- (NSLayoutConstraint *)mainWindowContentWidth { return [self mainWindowController].mainWindowContentWidth; }

- (void)setMainWindowContentWidth:(NSLayoutConstraint *)value { [self mainWindowController].mainWindowContentWidth = value; }

- (NSLayoutConstraint *)mainWindowMinimumWidth { return [self mainWindowController].mainWindowMinimumWidth; }

- (void)setMainWindowMinimumWidth:(NSLayoutConstraint *)value { [self mainWindowController].mainWindowMinimumWidth = value; }

- (BOOL)mainChatWantsVisible { return [self mainWindowController].mainChatWantsVisible; }

- (void)setMainChatWantsVisible:(BOOL)value { [self mainWindowController].mainChatWantsVisible = value; }

- (NSButton *)mainChatToggle { return [self mainWindowController].mainChatToggle; }

- (void)setMainChatToggle:(NSButton *)value { [self mainWindowController].mainChatToggle = value; }

- (NSTextField *)liveChipRecognition { return [self mainWindowController].liveChipRecognition; }

- (void)setLiveChipRecognition:(NSTextField *)value { [self mainWindowController].liveChipRecognition = value; }

- (NSTextField *)liveChipAutoTranslate { return [self mainWindowController].liveChipAutoTranslate; }

- (void)setLiveChipAutoTranslate:(NSTextField *)value { [self mainWindowController].liveChipAutoTranslate = value; }

- (NSTextField *)liveChipPauseFollow { return [self mainWindowController].liveChipPauseFollow; }

- (void)setLiveChipPauseFollow:(NSTextField *)value { [self mainWindowController].liveChipPauseFollow = value; }

- (NSTextField *)liveScreenSpeakerLabel { return [self mainWindowController].liveScreenSpeakerLabel; }

- (void)setLiveScreenSpeakerLabel:(NSTextField *)value { [self mainWindowController].liveScreenSpeakerLabel = value; }

- (NSTextField *)liveScreenDialogueLabel { return [self mainWindowController].liveScreenDialogueLabel; }

- (void)setLiveScreenDialogueLabel:(NSTextField *)value { [self mainWindowController].liveScreenDialogueLabel = value; }

- (NSTextField *)liveLevelTag { return [self mainWindowController].liveLevelTag; }

- (void)setLiveLevelTag:(NSTextField *)value { [self mainWindowController].liveLevelTag = value; }

- (NSLayoutConstraint *)previewAspectConstraint { return [self mainWindowController].previewAspectConstraint; }

- (void)setPreviewAspectConstraint:(NSLayoutConstraint *)value { [self mainWindowController].previewAspectConstraint = value; }

- (NSTextField *)statusLabel { return [self mainWindowController].statusLabel; }

- (void)setStatusLabel:(NSTextField *)value { [self mainWindowController].statusLabel = value; }

- (NSTextField *)currentWindowLabel { return [self mainWindowController].currentWindowLabel; }

- (void)setCurrentWindowLabel:(NSTextField *)value { [self mainWindowController].currentWindowLabel = value; }

- (NSTextField *)translationCountLabel { return [self mainWindowController].translationCountLabel; }

- (void)setTranslationCountLabel:(NSTextField *)value { [self mainWindowController].translationCountLabel = value; }

- (NSButton *)runButton { return [self mainWindowController].runButton; }

- (void)setRunButton:(NSButton *)value { [self mainWindowController].runButton = value; }

- (NSTextField *)runStateLabel { return [self mainWindowController].runStateLabel; }

- (void)setRunStateLabel:(NSTextField *)value { [self mainWindowController].runStateLabel = value; }

- (NSTextField *)headerTitleLabel { return [self mainWindowController].headerTitleLabel; }

- (void)setHeaderTitleLabel:(NSTextField *)value { [self mainWindowController].headerTitleLabel = value; }

- (NSTextField *)ocrDurationLabel { return [self mainWindowController].ocrDurationLabel; }

- (void)setOcrDurationLabel:(NSTextField *)value { [self mainWindowController].ocrDurationLabel = value; }

- (NSTextField *)translationDurationLabel { return [self mainWindowController].translationDurationLabel; }

- (void)setTranslationDurationLabel:(NSTextField *)value { [self mainWindowController].translationDurationLabel = value; }

- (NSTextField *)latestTranslationLabel { return [self mainWindowController].latestTranslationLabel; }

- (void)setLatestTranslationLabel:(NSTextField *)value { [self mainWindowController].latestTranslationLabel = value; }

- (NSTextField *)latestSourceLabel { return [self mainWindowController].latestSourceLabel; }

- (void)setLatestSourceLabel:(NSTextField *)value { [self mainWindowController].latestSourceLabel = value; }

- (NSTextField *)liveErrorLabel { return [self mainWindowController].liveErrorLabel; }

- (void)setLiveErrorLabel:(NSTextField *)value { [self mainWindowController].liveErrorLabel = value; }

- (NSImageView *)framePreview { return [self mainWindowController].framePreview; }

- (void)setFramePreview:(NSImageView *)value { [self mainWindowController].framePreview = value; }

- (NSTextField *)previewPlaceholder { return [self mainWindowController].previewPlaceholder; }

- (void)setPreviewPlaceholder:(NSTextField *)value { [self mainWindowController].previewPlaceholder = value; }

- (NSArray<NSView *> *)pages { return [self mainWindowController].pages; }

- (void)setPages:(NSArray<NSView *> *)value { [self mainWindowController].pages = value; }

- (NSArray<NSButton *> *)pageButtons { return [self mainWindowController].pageButtons; }

- (void)setPageButtons:(NSArray<NSButton *> *)value { [self mainWindowController].pageButtons = value; }

- (NSInteger)selectedPage { return [self mainWindowController].selectedPage; }

- (void)setSelectedPage:(NSInteger)value { [self mainWindowController].selectedPage = value; }

- (BOOL)mainWindowVisibleBeforeRegionSelection { return [self mainWindowController].mainWindowVisibleBeforeRegionSelection; }

- (void)setMainWindowVisibleBeforeRegionSelection:(BOOL)value { [self mainWindowController].mainWindowVisibleBeforeRegionSelection = value; }

- (NSView *)inlineTranslationListCard { return [self mainWindowController].inlineTranslationListCard; }

- (void)setInlineTranslationListCard:(NSView *)value { [self mainWindowController].inlineTranslationListCard = value; }

- (NSStackView *)inlineTranslationListStack { return [self mainWindowController].inlineTranslationListStack; }

- (void)setInlineTranslationListStack:(NSStackView *)value { [self mainWindowController].inlineTranslationListStack = value; }

- (NSTextField *)inlineTranslationListCount { return [self mainWindowController].inlineTranslationListCount; }

- (void)setInlineTranslationListCount:(NSTextField *)value { [self mainWindowController].inlineTranslationListCount = value; }

- (NSArray<FYInlineBlockSnapshot *> *)inlineTranslationListSnapshots { return [self mainWindowController].inlineTranslationListSnapshots; }

- (void)setInlineTranslationListSnapshots:(NSArray<FYInlineBlockSnapshot *> *)value { [self mainWindowController].inlineTranslationListSnapshots = value; }

- (NSString *)inlineTranslationListSignature { return [self mainWindowController].inlineTranslationListSignature; }

- (void)setInlineTranslationListSignature:(NSString *)value { [self mainWindowController].inlineTranslationListSignature = value; }

- (FYSelectableSourceTextView *)learningSourceTextView { return [self mainWindowController].learningSourceTextView; }

- (void)setLearningSourceTextView:(FYSelectableSourceTextView *)value { [self mainWindowController].learningSourceTextView = value; }

- (NSTextField *)learningTranslationLabel { return [self mainWindowController].learningTranslationLabel; }

- (void)setLearningTranslationLabel:(NSTextField *)value { [self mainWindowController].learningTranslationLabel = value; }

- (NSTextField *)learningPinnedLabel { return [self mainWindowController].learningPinnedLabel; }

- (void)setLearningPinnedLabel:(NSTextField *)value { [self mainWindowController].learningPinnedLabel = value; }

- (NSButton *)pinSentenceButton { return [self mainWindowController].pinSentenceButton; }

- (void)setPinSentenceButton:(NSButton *)value { [self mainWindowController].pinSentenceButton = value; }

- (NSButton *)followLatestButton { return [self mainWindowController].followLatestButton; }

- (void)setFollowLatestButton:(NSButton *)value { [self mainWindowController].followLatestButton = value; }

- (NSTextField *)lemmaField { return [self mainWindowController].lemmaField; }

- (void)setLemmaField:(NSTextField *)value { [self mainWindowController].lemmaField = value; }

- (NSTextField *)readingField { return [self mainWindowController].readingField; }

- (void)setReadingField:(NSTextField *)value { [self mainWindowController].readingField = value; }

- (NSTextField *)meaningField { return [self mainWindowController].meaningField; }

- (void)setMeaningField:(NSTextField *)value { [self mainWindowController].meaningField = value; }

- (NSLayoutConstraint *)sourceReadingHeight { return [self mainWindowController].sourceReadingHeight; }

- (void)setSourceReadingHeight:(NSLayoutConstraint *)value { [self mainWindowController].sourceReadingHeight = value; }

- (NSLayoutConstraint *)translationReadingMinimumHeight { return [self mainWindowController].translationReadingMinimumHeight; }

- (void)setTranslationReadingMinimumHeight:(NSLayoutConstraint *)value { [self mainWindowController].translationReadingMinimumHeight = value; }

- (NSLayoutConstraint *)sourceReadingMinimumHeight { return [self mainWindowController].sourceReadingMinimumHeight; }

- (void)setSourceReadingMinimumHeight:(NSLayoutConstraint *)value { [self mainWindowController].sourceReadingMinimumHeight = value; }

- (NSTextField *)liveSourceEmptyLabel { return [self mainWindowController].liveSourceEmptyLabel; }

- (void)setLiveSourceEmptyLabel:(NSTextField *)value { [self mainWindowController].liveSourceEmptyLabel = value; }

- (NSTextField *)liveSourceSelectionHintLabel { return [self mainWindowController].liveSourceSelectionHintLabel; }

- (void)setLiveSourceSelectionHintLabel:(NSTextField *)value { [self mainWindowController].liveSourceSelectionHintLabel = value; }

- (NSTextField *)vocabularySelectionLabel { return [self mainWindowController].vocabularySelectionLabel; }

- (void)setVocabularySelectionLabel:(NSTextField *)value { [self mainWindowController].vocabularySelectionLabel = value; }

- (NSString *)displayedSentenceID { return [self mainWindowController].displayedSentenceID; }

- (void)setDisplayedSentenceID:(NSString *)value { [self mainWindowController].displayedSentenceID = value; }

- (NSInteger)displayedVersion { return [self mainWindowController].displayedVersion; }

- (void)setDisplayedVersion:(NSInteger)value { [self mainWindowController].displayedVersion = value; }

- (NSString *)displayedSourceText { return [self mainWindowController].displayedSourceText; }

- (void)setDisplayedSourceText:(NSString *)value { [self mainWindowController].displayedSourceText = value; }

- (NSString *)displayedTranslation { return [self mainWindowController].displayedTranslation; }

- (void)setDisplayedTranslation:(NSString *)value { [self mainWindowController].displayedTranslation = value; }

- (BOOL)vocabCompletionFromAI { return [self mainWindowController].vocabCompletionFromAI; }

- (void)setVocabCompletionFromAI:(BOOL)value { [self mainWindowController].vocabCompletionFromAI = value; }

- (NSInteger)vocabSelectionGeneration { return [self mainWindowController].vocabSelectionGeneration; }

- (void)setVocabSelectionGeneration:(NSInteger)value { [self mainWindowController].vocabSelectionGeneration = value; }

- (NSStackView *)wordPickArea { return [self mainWindowController].wordPickArea; }

- (void)setWordPickArea:(NSStackView *)value { [self mainWindowController].wordPickArea = value; }

- (NSTextField *)wordPickSurfaceLabel { return [self mainWindowController].wordPickSurfaceLabel; }

- (void)setWordPickSurfaceLabel:(NSTextField *)value { [self mainWindowController].wordPickSurfaceLabel = value; }

- (NSView *)learningPageHost { return [self mainWindowController].learningPageHost; }

- (void)setLearningPageHost:(NSView *)value { [self mainWindowController].learningPageHost = value; }

- (NSTextField *)headerDescriptionLabel { return [self mainWindowController].headerDescriptionLabel; }

- (void)setHeaderDescriptionLabel:(NSTextField *)value { [self mainWindowController].headerDescriptionLabel = value; }

- (BOOL)savingVocabulary { return [self mainWindowController].savingVocabulary; }

- (void)setSavingVocabulary:(BOOL)value { [self mainWindowController].savingVocabulary = value; }

- (void)createMainWindow { [[self mainWindowController] createMainWindow]; }

- (NSView *)makeSidebar { return [[self mainWindowController] makeSidebar]; }

- (NSView *)makeRunHeader { return [[self mainWindowController] makeRunHeader]; }

- (NSScrollView *)makePageScrollWithContent:(NSView *)content { return [[self mainWindowController] makePageScrollWithContent:content]; }

- (void)selectPage:(NSButton *)sender { [[self mainWindowController] selectPage:sender]; }

- (void)selectPageAtIndex:(NSInteger)index { [[self mainWindowController] selectPageAtIndex:index]; }

- (NSView *)makeLivePage { return [[self mainWindowController] makeLivePage]; }

- (NSView *)makeInlineTranslationListCard { return [[self mainWindowController] makeInlineTranslationListCard]; }

- (void)refreshInlineTranslationList { [[self mainWindowController] refreshInlineTranslationList]; }

- (void)openInlineTranslationRow:(NSButton *)sender { [[self mainWindowController] openInlineTranslationRow:sender]; }

- (void)toggleLearningPin:(id)sender { [[self mainWindowController] toggleLearningPin:sender]; }

- (void)vocabularyFormChanged:(id)sender { [[self mainWindowController] vocabularyFormChanged:sender]; }

- (void)freezeLearningSentenceForSelection { [[self mainWindowController] freezeLearningSentenceForSelection]; }

- (void)selectWordAtCharacterIndex:(NSUInteger)characterIndex { [[self mainWindowController] selectWordAtCharacterIndex:characterIndex]; }

- (void)updateWordPickForSelection { [[self mainWindowController] updateWordPickForSelection]; }

- (void)closeWordPick:(id)sender { [[self mainWindowController] closeWordPick:sender]; }

- (void)pinLearningSentence:(id)sender { [[self mainWindowController] pinLearningSentence:sender]; }

- (void)followLatestSentence:(id)sender { [[self mainWindowController] followLatestSentence:sender]; }

- (NSString *)selectedLearningText { return [[self mainWindowController] selectedLearningText]; }

- (void)bookmarkSelectedVocabulary:(id)sender { [[self mainWindowController] bookmarkSelectedVocabulary:sender]; }

- (void)completeSelectedVocabulary:(id)sender { [[self mainWindowController] completeSelectedVocabulary:sender]; }

- (NSAttributedString *)liveReadingText:(NSString *)text japanese:(BOOL)japanese { return [[self mainWindowController] liveReadingText:text japanese:japanese]; }

- (void)updateLiveSourceReadingHeight { [[self mainWindowController] updateLiveSourceReadingHeight]; }

- (void)refreshLearningSource { [[self mainWindowController] refreshLearningSource]; }

- (void)syncCoordinatorToDisplayed { [[self mainWindowController] syncCoordinatorToDisplayed]; }

- (void)splitSpeakerAndBody:(NSString *)text speaker:(NSString * _Nullable * _Nullable)outSpeaker body:(NSString * _Nullable * _Nullable)outBody { [[self mainWindowController] splitSpeakerAndBody:text speaker:outSpeaker body:outBody]; }

- (nullable NSString *)currentSentenceLevelTag { return [[self mainWindowController] currentSentenceLevelTag]; }

- (void)refreshLiveDialoguePresentation:(NSString *)source { [[self mainWindowController] refreshLiveDialoguePresentation:source]; }

- (void)refreshLearningStatus { [[self mainWindowController] refreshLearningStatus]; }

- (void)toggleMainStudyChat:(id)sender { [[self mainWindowController] toggleMainStudyChat:sender]; }

- (void)updateMainChatForWindowWidth { [[self mainWindowController] updateMainChatForWindowWidth]; }

- (void)updateMainChatToggle { [[self mainWindowController] updateMainChatToggle]; }

- (void)windowDidResize:(NSNotification *)notification { [[self mainWindowController] windowDidResize:notification]; }

- (NSArray<FYRequestIdentity *> *)savedSentences { return [self collectionController].savedSentences; }

- (void)setSavedSentences:(NSArray<FYRequestIdentity *> *)value { [self collectionController].savedSentences = value; }

- (NSStackView *)savedSentenceStack { return [self collectionController].savedSentenceStack; }

- (void)setSavedSentenceStack:(NSStackView *)value { [self collectionController].savedSentenceStack = value; }

- (NSStackView *)learningCollectionHost { return [self collectionController].learningCollectionHost; }

- (void)setLearningCollectionHost:(NSStackView *)value { [self collectionController].learningCollectionHost = value; }

- (NSArray<NSView *> *)learningCollectionSections { return [self collectionController].learningCollectionSections; }

- (void)setLearningCollectionSections:(NSArray<NSView *> *)value { [self collectionController].learningCollectionSections = value; }

- (NSArray<NSButton *> *)learningCollectionTabs { return [self collectionController].learningCollectionTabs; }

- (void)setLearningCollectionTabs:(NSArray<NSButton *> *)value { [self collectionController].learningCollectionTabs = value; }

- (NSInteger)learningCollectionIndex { return [self collectionController].learningCollectionIndex; }

- (void)setLearningCollectionIndex:(NSInteger)value { [self collectionController].learningCollectionIndex = value; }

- (NSTextField *)learningCollectionTitle { return [self collectionController].learningCollectionTitle; }

- (void)setLearningCollectionTitle:(NSTextField *)value { [self collectionController].learningCollectionTitle = value; }

- (NSTextField *)learningCollectionCount { return [self collectionController].learningCollectionCount; }

- (void)setLearningCollectionCount:(NSTextField *)value { [self collectionController].learningCollectionCount = value; }

- (NSMutableSet<NSString *> *)expandedWordCards { return [self collectionController].expandedWordCards; }

- (void)setExpandedWordCards:(NSMutableSet<NSString *> *)value { [self collectionController].expandedWordCards = value; }

- (NSTextField *)vocabularyListLabel { return [self collectionController].vocabularyListLabel; }

- (void)setVocabularyListLabel:(NSTextField *)value { [self collectionController].vocabularyListLabel = value; }

- (NSTextField *)vocabularyStatusLabel { return [self collectionController].vocabularyStatusLabel; }

- (void)setVocabularyStatusLabel:(NSTextField *)value { [self collectionController].vocabularyStatusLabel = value; }

- (NSTextField *)reviewPromptLabel { return [self collectionController].reviewPromptLabel; }

- (void)setReviewPromptLabel:(NSTextField *)value { [self collectionController].reviewPromptLabel = value; }

- (NSTextField *)reviewWordLabel { return [self collectionController].reviewWordLabel; }

- (void)setReviewWordLabel:(NSTextField *)value { [self collectionController].reviewWordLabel = value; }

- (NSTextField *)reviewMeaningLabel { return [self collectionController].reviewMeaningLabel; }

- (void)setReviewMeaningLabel:(NSTextField *)value { [self collectionController].reviewMeaningLabel = value; }

- (NSButton *)revealButton { return [self collectionController].revealButton; }

- (void)setRevealButton:(NSButton *)value { [self collectionController].revealButton = value; }

- (NSButton *)knownButton { return [self collectionController].knownButton; }

- (void)setKnownButton:(NSButton *)value { [self collectionController].knownButton = value; }

- (NSButton *)notYetButton { return [self collectionController].notYetButton; }

- (void)setNotYetButton:(NSButton *)value { [self collectionController].notYetButton = value; }

- (FYVocabularyEntry *)reviewingEntry { return [self collectionController].reviewingEntry; }

- (void)setReviewingEntry:(FYVocabularyEntry *)value { [self collectionController].reviewingEntry = value; }

- (NSArray<FYVocabularyEntry *> *)reviewList { return [self collectionController].reviewList; }

- (void)setReviewList:(NSArray<FYVocabularyEntry *> *)value { [self collectionController].reviewList = value; }

- (NSInteger)reviewIndex { return [self collectionController].reviewIndex; }

- (void)setReviewIndex:(NSInteger)value { [self collectionController].reviewIndex = value; }

- (NSTextField *)vocabularyExamplesLabel { return [self collectionController].vocabularyExamplesLabel; }

- (void)setVocabularyExamplesLabel:(NSTextField *)value { [self collectionController].vocabularyExamplesLabel = value; }

- (NSPopUpButton *)vocabularyExamplesPopup { return [self collectionController].vocabularyExamplesPopup; }

- (void)setVocabularyExamplesPopup:(NSPopUpButton *)value { [self collectionController].vocabularyExamplesPopup = value; }

- (NSArray<FYVocabularyEntry *> *)vocabularyExamplesList { return [self collectionController].vocabularyExamplesList; }

- (void)setVocabularyExamplesList:(NSArray<FYVocabularyEntry *> *)value { [self collectionController].vocabularyExamplesList = value; }

- (NSStackView *)wordCardStack { return [self collectionController].wordCardStack; }

- (void)setWordCardStack:(NSStackView *)value { [self collectionController].wordCardStack = value; }

- (NSMutableDictionary<NSString *, NSNumber *> *)revealedMeanings { return [self collectionController].revealedMeanings; }

- (void)setRevealedMeanings:(NSMutableDictionary<NSString *, NSNumber *> *)value { [self collectionController].revealedMeanings = value; }

- (NSMutableDictionary<NSString *, NSNumber *> *)wordExampleIndices { return [self collectionController].wordExampleIndices; }

- (void)setWordExampleIndices:(NSMutableDictionary<NSString *, NSNumber *> *)value { [self collectionController].wordExampleIndices = value; }

- (NSInteger)wordCardsGeneration { return [self collectionController].wordCardsGeneration; }

- (void)setWordCardsGeneration:(NSInteger)value { [self collectionController].wordCardsGeneration = value; }

- (NSStackView *)grammarBookmarkStack { return [self collectionController].grammarBookmarkStack; }

- (void)setGrammarBookmarkStack:(NSStackView *)value { [self collectionController].grammarBookmarkStack = value; }

- (NSPopUpButton *)historyPopup { return [self collectionController].historyPopup; }

- (void)setHistoryPopup:(NSPopUpButton *)value { [self collectionController].historyPopup = value; }

- (NSArray<FYSentenceRecord *> *)historyRecords { return [self collectionController].historyRecords; }

- (void)setHistoryRecords:(NSArray<FYSentenceRecord *> *)value { [self collectionController].historyRecords = value; }

- (NSTextField *)grammarBookmarkListLabel { return [self collectionController].grammarBookmarkListLabel; }

- (void)setGrammarBookmarkListLabel:(NSTextField *)value { [self collectionController].grammarBookmarkListLabel = value; }

- (NSPopUpButton *)grammarBookmarkPopup { return [self collectionController].grammarBookmarkPopup; }

- (void)setGrammarBookmarkPopup:(NSPopUpButton *)value { [self collectionController].grammarBookmarkPopup = value; }

- (NSArray<FYGrammarBookmark *> *)grammarBookmarks { return [self collectionController].grammarBookmarks; }

- (void)setGrammarBookmarks:(NSArray<FYGrammarBookmark *> *)value { [self collectionController].grammarBookmarks = value; }

- (NSStackView *)historyListStack { return [self collectionController].historyListStack; }

- (void)setHistoryListStack:(NSStackView *)value { [self collectionController].historyListStack = value; }

- (NSView *)vocabularyEmptyCard { return [self collectionController].vocabularyEmptyCard; }

- (void)setVocabularyEmptyCard:(NSView *)value { [self collectionController].vocabularyEmptyCard = value; }

- (NSStackView *)savedGrammarCardStack { return [self collectionController].savedGrammarCardStack; }

- (void)setSavedGrammarCardStack:(NSStackView *)value { [self collectionController].savedGrammarCardStack = value; }

- (NSView *)makeVocabularyPage { return [[self collectionController] makeVocabularyPage]; }

- (void)updateLearningCollectionSummary { [[self collectionController] updateLearningCollectionSummary]; }

- (void)selectLearningCollection:(NSButton *)sender { [[self collectionController] selectLearningCollection:sender]; }

- (void)openHistoryAnalysis:(NSButton *)sender { [[self collectionController] openHistoryAnalysis:sender]; }

- (void)refreshHistory { [[self collectionController] refreshHistory]; }

- (void)refreshHistoryAction:(id)sender { [[self collectionController] refreshHistoryAction:sender]; }

- (void)historyChanged:(id)sender { [[self collectionController] historyChanged:sender]; }

- (void)refreshVocabularyList { [[self collectionController] refreshVocabularyList]; }

- (void)rebuildWordCards { [[self collectionController] rebuildWordCards]; }

- (void)toggleSavedWordDetails:(NSButton *)sender { [[self collectionController] toggleSavedWordDetails:sender]; }

- (FYVocabularyEntry *)wordForCardButton:(NSButton *)sender { return [[self collectionController] wordForCardButton:sender]; }

- (void)nextWordExample:(NSButton *)sender { [[self collectionController] nextWordExample:sender]; }

- (void)toggleWordMeaning:(NSButton *)sender { [[self collectionController] toggleWordMeaning:sender]; }

- (void)toggleWordMastered:(NSButton *)sender { [[self collectionController] toggleWordMastered:sender]; }

- (void)removeWordCard:(NSButton *)sender { [[self collectionController] removeWordCard:sender]; }

- (void)nextReviewWord:(id)sender { [[self collectionController] nextReviewWord:sender]; }

- (void)revealReviewMeaning:(id)sender { [[self collectionController] revealReviewMeaning:sender]; }

- (void)markReviewKnown:(id)sender { [[self collectionController] markReviewKnown:sender]; }

- (void)markReviewLearning:(id)sender { [[self collectionController] markReviewLearning:sender]; }

- (void)setReviewStatus:(FYReviewStatus)status { [[self collectionController] setReviewStatus:status]; }

- (void)removeReviewWord:(id)sender { [[self collectionController] removeReviewWord:sender]; }

- (void)refreshGrammarBookmarks:(id)sender { [[self collectionController] refreshGrammarBookmarks:sender]; }

- (void)grammarBookmarkChanged:(id)sender { [[self collectionController] grammarBookmarkChanged:sender]; }

- (void)deleteGrammarBookmark:(NSButton *)sender { [[self collectionController] deleteGrammarBookmark:sender]; }

- (void)refreshVocabularyExamplesPopup { [[self collectionController] refreshVocabularyExamplesPopup]; }

- (void)vocabularyExamplesChanged:(id)sender { [[self collectionController] vocabularyExamplesChanged:sender]; }

- (void)showVocabularyExamples:(id)sender { [[self collectionController] showVocabularyExamples:sender]; }

- (NSView *)makeHistoryPage { return [[self collectionController] makeHistoryPage]; }

- (void)refreshSavedSentences { [[self collectionController] refreshSavedSentences]; }

- (FYRequestIdentity *)savedSentenceForButton:(NSButton *)sender { return [[self collectionController] savedSentenceForButton:sender]; }

- (void)openSavedSentence:(NSButton *)sender { [[self collectionController] openSavedSentence:sender]; }

- (void)removeSavedSentence:(NSButton *)sender { [[self collectionController] removeSavedSentence:sender]; }

- (NSArray<NSButton *> *)mainStructureButtons { return [self grammarPresentationController].mainStructureButtons; }

- (void)setMainStructureButtons:(NSArray<NSButton *> *)value { [self grammarPresentationController].mainStructureButtons = value; }

- (NSScrollView *)mainStructureScrollView { return [self grammarPresentationController].mainStructureScrollView; }

- (void)setMainStructureScrollView:(NSScrollView *)value { [self grammarPresentationController].mainStructureScrollView = value; }

- (NSStackView *)sentenceStructureStack { return [self grammarPresentationController].sentenceStructureStack; }

- (void)setSentenceStructureStack:(NSStackView *)value { [self grammarPresentationController].sentenceStructureStack = value; }

- (NSView *)grammarStructureCard { return [self grammarPresentationController].grammarStructureCard; }

- (void)setGrammarStructureCard:(NSView *)value { [self grammarPresentationController].grammarStructureCard = value; }

- (NSArray<NSButton *> *)grammarTabButtons { return [self grammarPresentationController].grammarTabButtons; }

- (void)setGrammarTabButtons:(NSArray<NSButton *> *)value { [self grammarPresentationController].grammarTabButtons = value; }

- (NSArray<NSView *> *)grammarTabUnderlines { return [self grammarPresentationController].grammarTabUnderlines; }

- (void)setGrammarTabUnderlines:(NSArray<NSView *> *)value { [self grammarPresentationController].grammarTabUnderlines = value; }

- (NSView *)grammarPointsPane { return [self grammarPresentationController].grammarPointsPane; }

- (void)setGrammarPointsPane:(NSView *)value { [self grammarPresentationController].grammarPointsPane = value; }

- (NSView *)grammarTabRow { return [self grammarPresentationController].grammarTabRow; }

- (void)setGrammarTabRow:(NSView *)value { [self grammarPresentationController].grammarTabRow = value; }

- (NSView *)grammarEmptyPane { return [self grammarPresentationController].grammarEmptyPane; }

- (void)setGrammarEmptyPane:(NSView *)value { [self grammarPresentationController].grammarEmptyPane = value; }

- (NSTextField *)grammarEmptyTitle { return [self grammarPresentationController].grammarEmptyTitle; }

- (void)setGrammarEmptyTitle:(NSTextField *)value { [self grammarPresentationController].grammarEmptyTitle = value; }

- (NSTextField *)grammarEmptyHint { return [self grammarPresentationController].grammarEmptyHint; }

- (void)setGrammarEmptyHint:(NSTextField *)value { [self grammarPresentationController].grammarEmptyHint = value; }

- (NSButton *)grammarEmptyAnalyzeButton { return [self grammarPresentationController].grammarEmptyAnalyzeButton; }

- (void)setGrammarEmptyAnalyzeButton:(NSButton *)value { [self grammarPresentationController].grammarEmptyAnalyzeButton = value; }

- (NSTextField *)grammarReferenceNote { return [self grammarPresentationController].grammarReferenceNote; }

- (void)setGrammarReferenceNote:(NSTextField *)value { [self grammarPresentationController].grammarReferenceNote = value; }

- (NSString *)grammarAnalysisError { return [self grammarPresentationController].grammarAnalysisError; }

- (void)setGrammarAnalysisError:(NSString *)value { [self grammarPresentationController].grammarAnalysisError = value; }

- (NSView *)grammarExamplesPane { return [self grammarPresentationController].grammarExamplesPane; }

- (void)setGrammarExamplesPane:(NSView *)value { [self grammarPresentationController].grammarExamplesPane = value; }

- (NSTextField *)grammarExampleLabel { return [self grammarPresentationController].grammarExampleLabel; }

- (void)setGrammarExampleLabel:(NSTextField *)value { [self grammarPresentationController].grammarExampleLabel = value; }

- (NSView *)grammarFollowupDisclosure { return [self grammarPresentationController].grammarFollowupDisclosure; }

- (void)setGrammarFollowupDisclosure:(NSView *)value { [self grammarPresentationController].grammarFollowupDisclosure = value; }

- (NSButton *)analyzeButton { return [self grammarPresentationController].analyzeButton; }

- (void)setAnalyzeButton:(NSButton *)value { [self grammarPresentationController].analyzeButton = value; }

- (NSTextField *)grammarStatusLabel { return [self grammarPresentationController].grammarStatusLabel; }

- (void)setGrammarStatusLabel:(NSTextField *)value { [self grammarPresentationController].grammarStatusLabel = value; }

- (NSTextField *)grammarResultsLabel { return [self grammarPresentationController].grammarResultsLabel; }

- (void)setGrammarResultsLabel:(NSTextField *)value { [self grammarPresentationController].grammarResultsLabel = value; }

- (NSPopUpButton *)grammarSelector { return [self grammarPresentationController].grammarSelector; }

- (void)setGrammarSelector:(NSPopUpButton *)value { [self grammarPresentationController].grammarSelector = value; }

- (NSTextField *)grammarSourceLabel { return [self grammarPresentationController].grammarSourceLabel; }

- (void)setGrammarSourceLabel:(NSTextField *)value { [self grammarPresentationController].grammarSourceLabel = value; }

- (NSTextField *)grammarFollowupResultLabel { return [self grammarPresentationController].grammarFollowupResultLabel; }

- (void)setGrammarFollowupResultLabel:(NSTextField *)value { [self grammarPresentationController].grammarFollowupResultLabel = value; }

- (NSTextField *)grammarQuestionField { return [self grammarPresentationController].grammarQuestionField; }

- (void)setGrammarQuestionField:(NSTextField *)value { [self grammarPresentationController].grammarQuestionField = value; }

- (BOOL)learningAnalysisBusy { return [self grammarPresentationController].learningAnalysisBusy; }

- (void)setLearningAnalysisBusy:(BOOL)value { [self grammarPresentationController].learningAnalysisBusy = value; }

- (NSStackView *)sentenceInsightStack { return [self grammarPresentationController].sentenceInsightStack; }

- (void)setSentenceInsightStack:(NSStackView *)value { [self grammarPresentationController].sentenceInsightStack = value; }

- (NSTextField *)sentenceInsightLabel { return [self grammarPresentationController].sentenceInsightLabel; }

- (void)setSentenceInsightLabel:(NSTextField *)value { [self grammarPresentationController].sentenceInsightLabel = value; }

- (NSArray<NSControl *> *)grammarFollowupControls { return [self grammarPresentationController].grammarFollowupControls; }

- (void)setGrammarFollowupControls:(NSArray<NSControl *> *)value { [self grammarPresentationController].grammarFollowupControls = value; }

- (NSStackView *)grammarFollowupStack { return [self grammarPresentationController].grammarFollowupStack; }

- (void)setGrammarFollowupStack:(NSStackView *)value { [self grammarPresentationController].grammarFollowupStack = value; }

- (FYAnalysisResult *)currentAnalysis { return [self grammarPresentationController].currentAnalysis; }

- (void)setCurrentAnalysis:(FYAnalysisResult *)value { [self grammarPresentationController].currentAnalysis = value; }

- (NSButton *)grammarPageAnalyzeButton { return [self grammarPresentationController].grammarPageAnalyzeButton; }

- (void)setGrammarPageAnalyzeButton:(NSButton *)value { [self grammarPresentationController].grammarPageAnalyzeButton = value; }

- (NSTextField *)grammarDetailNameLabel { return [self grammarPresentationController].grammarDetailNameLabel; }

- (void)setGrammarDetailNameLabel:(NSTextField *)value { [self grammarPresentationController].grammarDetailNameLabel = value; }

- (NSTextField *)grammarDetailLevelLabel { return [self grammarPresentationController].grammarDetailLevelLabel; }

- (void)setGrammarDetailLevelLabel:(NSTextField *)value { [self grammarPresentationController].grammarDetailLevelLabel = value; }

- (NSTextField *)grammarDetailBodyLabel { return [self grammarPresentationController].grammarDetailBodyLabel; }

- (void)setGrammarDetailBodyLabel:(NSTextField *)value { [self grammarPresentationController].grammarDetailBodyLabel = value; }

- (NSButton *)grammarDetailBookmarkButton { return [self grammarPresentationController].grammarDetailBookmarkButton; }

- (void)setGrammarDetailBookmarkButton:(NSButton *)value { [self grammarPresentationController].grammarDetailBookmarkButton = value; }

- (FYGrammarActionState *)grammarActions { return [self grammarPresentationController].grammarActions; }

- (void)setGrammarActions:(FYGrammarActionState *)value { [self grammarPresentationController].grammarActions = value; }

- (NSButton *)grammarExpandButton { return [self grammarPresentationController].grammarExpandButton; }

- (void)setGrammarExpandButton:(NSButton *)value { [self grammarPresentationController].grammarExpandButton = value; }

- (NSButton *)grammarReviewButton { return [self grammarPresentationController].grammarReviewButton; }

- (void)setGrammarReviewButton:(NSButton *)value { [self grammarPresentationController].grammarReviewButton = value; }

- (NSTextField *)grammarExpandedLabel { return [self grammarPresentationController].grammarExpandedLabel; }

- (void)setGrammarExpandedLabel:(NSTextField *)value { [self grammarPresentationController].grammarExpandedLabel = value; }

- (NSStackView *)grammarOtherStack { return [self grammarPresentationController].grammarOtherStack; }

- (void)setGrammarOtherStack:(NSStackView *)value { [self grammarPresentationController].grammarOtherStack = value; }

- (NSTextField *)grammarOtherEmptyLabel { return [self grammarPresentationController].grammarOtherEmptyLabel; }

- (void)setGrammarOtherEmptyLabel:(NSTextField *)value { [self grammarPresentationController].grammarOtherEmptyLabel = value; }

- (NSInteger)selectedGrammarIndex { return [self grammarPresentationController].selectedGrammarIndex; }

- (void)setSelectedGrammarIndex:(NSInteger)value { [self grammarPresentationController].selectedGrammarIndex = value; }

- (NSTextView *)grammarSourceTextView { return [self grammarPresentationController].grammarSourceTextView; }

- (void)setGrammarSourceTextView:(NSTextView *)value { [self grammarPresentationController].grammarSourceTextView = value; }

- (NSButton *)grammarBackToSourceButton { return [self grammarPresentationController].grammarBackToSourceButton; }

- (void)setGrammarBackToSourceButton:(NSButton *)value { [self grammarPresentationController].grammarBackToSourceButton = value; }

- (NSTextField *)grammarPinnedLabel { return [self grammarPresentationController].grammarPinnedLabel; }

- (void)setGrammarPinnedLabel:(NSTextField *)value { [self grammarPresentationController].grammarPinnedLabel = value; }

- (NSInteger)analysisRequestGeneration { return [self grammarPresentationController].analysisRequestGeneration; }

- (void)setAnalysisRequestGeneration:(NSInteger)value { [self grammarPresentationController].analysisRequestGeneration = value; }

- (NSInteger)followupRequestGeneration { return [self grammarPresentationController].followupRequestGeneration; }

- (void)setFollowupRequestGeneration:(NSInteger)value { [self grammarPresentationController].followupRequestGeneration = value; }

- (NSStackView *)grammarDetailFields { return [self grammarPresentationController].grammarDetailFields; }

- (void)setGrammarDetailFields:(NSStackView *)value { [self grammarPresentationController].grammarDetailFields = value; }

- (NSStackView *)grammarUsageBlock { return [self grammarPresentationController].grammarUsageBlock; }

- (void)setGrammarUsageBlock:(NSStackView *)value { [self grammarPresentationController].grammarUsageBlock = value; }

- (NSButton *)grammarFollowupToggle { return [self grammarPresentationController].grammarFollowupToggle; }

- (void)setGrammarFollowupToggle:(NSButton *)value { [self grammarPresentationController].grammarFollowupToggle = value; }

- (NSButton *)grammarSourceLinkButton { return [self grammarPresentationController].grammarSourceLinkButton; }

- (void)setGrammarSourceLinkButton:(NSButton *)value { [self grammarPresentationController].grammarSourceLinkButton = value; }

- (FYGrammarActionState *)quickGrammarActions { return [self grammarPresentationController].quickGrammarActions; }

- (void)setQuickGrammarActions:(FYGrammarActionState *)value { [self grammarPresentationController].quickGrammarActions = value; }

- (NSInteger)selectedGrammarTab { return [self grammarPresentationController].selectedGrammarTab; }

- (void)setSelectedGrammarTab:(NSInteger)value { [self grammarPresentationController].selectedGrammarTab = value; }

- (void)grammarSelectorChanged:(id)sender { [[self grammarPresentationController] grammarSelectorChanged:sender]; }

- (void)setAnalyzeBusy:(BOOL)busy { [[self grammarPresentationController] setAnalyzeBusy:busy]; }

- (void)analyzeCurrentSentence:(id)sender { [[self grammarPresentationController] analyzeCurrentSentence:sender]; }

- (void)refreshGrammarResults { [[self grammarPresentationController] refreshGrammarResults]; }

- (void)renderGrammarDetailAtIndex:(NSInteger)index { [[self grammarPresentationController] renderGrammarDetailAtIndex:index]; }

- (void)openGrammarSource:(id)sender { [[self grammarPresentationController] openGrammarSource:sender]; }

- (FYGrammarBookmark *)bookmarkForCurrentGrammar { return [[self grammarPresentationController] bookmarkForCurrentGrammar]; }

- (BOOL)analysisMatchesCurrentSentence { return [[self grammarPresentationController] analysisMatchesCurrentSentence]; }

- (void)highlightGrammarMatches { [[self grammarPresentationController] highlightGrammarMatches]; }

- (void)applyHighlight:(NSColor *)color toTextView:(NSTextView *)textView { [[self grammarPresentationController] applyHighlight:color toTextView:textView]; }

- (void)clearGrammarHighlight { [[self grammarPresentationController] clearGrammarHighlight]; }

- (void)clearAnalysisDisplay { [[self grammarPresentationController] clearAnalysisDisplay]; }

- (void)bookmarkGrammarItem:(NSButton *)sender { [[self grammarPresentationController] bookmarkGrammarItem:sender]; }

- (void)bookmarkSelectedGrammar:(id)sender { [[self grammarPresentationController] bookmarkSelectedGrammar:sender]; }

- (void)selectGrammarItem:(NSButton *)sender { [[self grammarPresentationController] selectGrammarItem:sender]; }

- (void)applyGrammarSelectionLocally { [[self grammarPresentationController] applyGrammarSelectionLocally]; }

- (CGFloat)structureScrollOffsetForQuick:(BOOL)quick { return [[self grammarPresentationController] structureScrollOffsetForQuick:quick]; }

- (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick { [[self grammarPresentationController] restoreStructureScrollOffset:offset quick:quick]; }

- (FYGrammarItem *)selectedGrammarItem { return [[self grammarPresentationController] selectedGrammarItem]; }

- (void)backToSourcePage:(id)sender { [[self grammarPresentationController] backToSourcePage:sender]; }

- (void)simplerExplanationForGrammar:(id)sender { [[self grammarPresentationController] simplerExplanationForGrammar:sender]; }

- (void)exampleSentenceForGrammar:(id)sender { [[self grammarPresentationController] exampleSentenceForGrammar:sender]; }

- (void)requestGrammarFollowupExample:(BOOL)example { [[self grammarPresentationController] requestGrammarFollowupExample:example]; }

- (NSView *)structureViewForAnalysis:(FYAnalysisResult *)analysis source:(NSString *)source quick:(BOOL)quick { return [[self grammarPresentationController] structureViewForAnalysis:analysis source:source quick:quick]; }

- (void)selectMainStructure:(NSButton *)sender { [[self grammarPresentationController] selectMainStructure:sender]; }

- (NSView *)grammarInfoCellWithLabel:(NSString *)labelText value:(NSString *)valueText { return [[self grammarPresentationController] grammarInfoCellWithLabel:labelText value:valueText]; }

- (void)selectGrammarTab:(NSButton *)sender { [[self grammarPresentationController] selectGrammarTab:sender]; }

- (void)applyGrammarTabSelection { [[self grammarPresentationController] applyGrammarTabSelection]; }

- (NSView *)makeIntegratedGrammarCard { return [[self grammarPresentationController] makeIntegratedGrammarCard]; }

- (void)toggleGrammarFollowup:(id)sender { [[self grammarPresentationController] toggleGrammarFollowup:sender]; }

- (void)askGrammarTone:(id)sender { [[self grammarPresentationController] askGrammarTone:sender]; }

- (void)askGrammarQuestion:(id)sender { [[self grammarPresentationController] askGrammarQuestion:sender]; }

- (void)requestGrammarQuestion:(NSString *)question { [[self grammarPresentationController] requestGrammarQuestion:question]; }

- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick { return [[self grammarPresentationController] grammarActionsForQuick:quick]; }

- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick { return [[self grammarPresentationController] grammarActionItemForQuick:quick]; }

- (void)updateGrammarActionControlsForQuick:(BOOL)quick { [[self grammarPresentationController] updateGrammarActionControlsForQuick:quick]; }

- (void)refreshQuickGrammarActionDetail { [[self grammarPresentationController] refreshQuickGrammarActionDetail]; }

- (void)toggleGrammarExplanation:(NSButton *)sender { [[self grammarPresentationController] toggleGrammarExplanation:sender]; }

- (void)updateGrammarReviewDisplayForQuick:(BOOL)quick preservingPosition:(void (^)(void))updates { [[self grammarPresentationController] updateGrammarReviewDisplayForQuick:quick preservingPosition:updates]; }

- (void)reviewGrammarSentence:(NSButton *)sender { [[self grammarPresentationController] reviewGrammarSentence:sender]; }

- (FYStudyChatSession *)studyChatSession { return [self studyPresentationController].studyChatSession; }

- (void)setStudyChatSession:(FYStudyChatSession *)value { [self studyPresentationController].studyChatSession = value; }

- (FYStudyChatView *)mainStudyChatView { return [self studyPresentationController].mainStudyChatView; }

- (void)setMainStudyChatView:(FYStudyChatView *)value { [self studyPresentationController].mainStudyChatView = value; }

- (FYStudyChatView *)overlayStudyChatView { return [self studyPresentationController].overlayStudyChatView; }

- (void)setOverlayStudyChatView:(FYStudyChatView *)value { [self studyPresentationController].overlayStudyChatView = value; }

- (FYStudyOverlayPanel *)studyChatPanel { return [self studyPresentationController].studyChatPanel; }

- (void)setStudyChatPanel:(FYStudyOverlayPanel *)value { [self studyPresentationController].studyChatPanel = value; }

- (FYStudyOverlayPanel *)quickSentencePanel { return [self studyPresentationController].quickSentencePanel; }

- (void)setQuickSentencePanel:(FYStudyOverlayPanel *)value { [self studyPresentationController].quickSentencePanel = value; }

- (BOOL)studyChatOverlayRequested { return [self studyPresentationController].studyChatOverlayRequested; }

- (void)setStudyChatOverlayRequested:(BOOL)value { [self studyPresentationController].studyChatOverlayRequested = value; }

- (BOOL)quickSentenceRequested { return [self studyPresentationController].quickSentenceRequested; }

- (void)setQuickSentenceRequested:(BOOL)value { [self studyPresentationController].quickSentenceRequested = value; }

- (NSInteger)chatContextGeneration { return [self studyPresentationController].chatContextGeneration; }

- (void)setChatContextGeneration:(NSInteger)value { [self studyPresentationController].chatContextGeneration = value; }

- (BOOL)chatResolvingSource { return [self studyPresentationController].chatResolvingSource; }

- (void)setChatResolvingSource:(BOOL)value { [self studyPresentationController].chatResolvingSource = value; }

- (NSInteger)quickSentenceGeneration { return [self studyPresentationController].quickSentenceGeneration; }

- (void)setQuickSentenceGeneration:(NSInteger)value { [self studyPresentationController].quickSentenceGeneration = value; }

- (NSString *)quickSentenceSource { return [self studyPresentationController].quickSentenceSource; }

- (void)setQuickSentenceSource:(NSString *)value { [self studyPresentationController].quickSentenceSource = value; }

- (FYSelectableSourceTextView *)quickSourceTextView { return [self studyPresentationController].quickSourceTextView; }

- (void)setQuickSourceTextView:(FYSelectableSourceTextView *)value { [self studyPresentationController].quickSourceTextView = value; }

- (NSString *)quickSentenceTranslation { return [self studyPresentationController].quickSentenceTranslation; }

- (void)setQuickSentenceTranslation:(NSString *)value { [self studyPresentationController].quickSentenceTranslation = value; }

- (NSString *)quickSentenceID { return [self studyPresentationController].quickSentenceID; }

- (void)setQuickSentenceID:(NSString *)value { [self studyPresentationController].quickSentenceID = value; }

- (NSInteger)quickSentenceVersion { return [self studyPresentationController].quickSentenceVersion; }

- (void)setQuickSentenceVersion:(NSInteger)value { [self studyPresentationController].quickSentenceVersion = value; }

- (FYInlineBlockSnapshot *)inlineBlockSnapshot { return [self studyPresentationController].inlineBlockSnapshot; }

- (void)setInlineBlockSnapshot:(FYInlineBlockSnapshot *)value { [self studyPresentationController].inlineBlockSnapshot = value; }

- (FYInlineBlockSnapshot *)inlineReturnSnapshot { return [self studyPresentationController].inlineReturnSnapshot; }

- (void)setInlineReturnSnapshot:(FYInlineBlockSnapshot *)value { [self studyPresentationController].inlineReturnSnapshot = value; }

- (NSString *)inlineReturnSourceText { return [self studyPresentationController].inlineReturnSourceText; }

- (void)setInlineReturnSourceText:(NSString *)value { [self studyPresentationController].inlineReturnSourceText = value; }

- (NSButton *)inlineReturnButton { return [self studyPresentationController].inlineReturnButton; }

- (void)setInlineReturnButton:(NSButton *)value { [self studyPresentationController].inlineReturnButton = value; }

- (BOOL)quickSentenceIsInlineBlock { return [self studyPresentationController].quickSentenceIsInlineBlock; }

- (void)setQuickSentenceIsInlineBlock:(BOOL)value { [self studyPresentationController].quickSentenceIsInlineBlock = value; }

- (CGFloat)quickSentenceScrollOffset { return [self studyPresentationController].quickSentenceScrollOffset; }

- (void)setQuickSentenceScrollOffset:(CGFloat)value { [self studyPresentationController].quickSentenceScrollOffset = value; }

- (NSInteger)quickSelectedGrammarIndex { return [self studyPresentationController].quickSelectedGrammarIndex; }

- (void)setQuickSelectedGrammarIndex:(NSInteger)value { [self studyPresentationController].quickSelectedGrammarIndex = value; }

- (NSButton *)quickSelectedGrammarButton { return [self studyPresentationController].quickSelectedGrammarButton; }

- (void)setQuickSelectedGrammarButton:(NSButton *)value { [self studyPresentationController].quickSelectedGrammarButton = value; }

- (NSButton *)quickSentenceBookmarkButton { return [self studyPresentationController].quickSentenceBookmarkButton; }

- (void)setQuickSentenceBookmarkButton:(NSButton *)value { [self studyPresentationController].quickSentenceBookmarkButton = value; }

- (NSArray<NSButton *> *)quickStructureButtons { return [self studyPresentationController].quickStructureButtons; }

- (void)setQuickStructureButtons:(NSArray<NSButton *> *)value { [self studyPresentationController].quickStructureButtons = value; }

- (NSScrollView *)quickStructureScrollView { return [self studyPresentationController].quickStructureScrollView; }

- (void)setQuickStructureScrollView:(NSScrollView *)value { [self studyPresentationController].quickStructureScrollView = value; }

- (NSButton *)quickGrammarBookmarkButton { return [self studyPresentationController].quickGrammarBookmarkButton; }

- (void)setQuickGrammarBookmarkButton:(NSButton *)value { [self studyPresentationController].quickGrammarBookmarkButton = value; }

- (NSTextField *)quickGrammarBookmarkStatus { return [self studyPresentationController].quickGrammarBookmarkStatus; }

- (void)setQuickGrammarBookmarkStatus:(NSTextField *)value { [self studyPresentationController].quickGrammarBookmarkStatus = value; }

- (BOOL)quickGrammarBookmarkPending { return [self studyPresentationController].quickGrammarBookmarkPending; }

- (void)setQuickGrammarBookmarkPending:(BOOL)value { [self studyPresentationController].quickGrammarBookmarkPending = value; }

- (NSStackView *)quickGrammarStack { return [self studyPresentationController].quickGrammarStack; }

- (void)setQuickGrammarStack:(NSStackView *)value { [self studyPresentationController].quickGrammarStack = value; }

- (NSView *)quickGrammarDetailCard { return [self studyPresentationController].quickGrammarDetailCard; }

- (void)setQuickGrammarDetailCard:(NSView *)value { [self studyPresentationController].quickGrammarDetailCard = value; }

- (NSArray<NSButton *> *)quickGrammarChoices { return [self studyPresentationController].quickGrammarChoices; }

- (void)setQuickGrammarChoices:(NSArray<NSButton *> *)value { [self studyPresentationController].quickGrammarChoices = value; }

- (FYLearningAnalyzer *)quickSentenceAnalyzer { return [self studyPresentationController].quickSentenceAnalyzer; }

- (void)setQuickSentenceAnalyzer:(FYLearningAnalyzer *)value { [self studyPresentationController].quickSentenceAnalyzer = value; }

- (FYAnalysisResult *)quickSentenceAnalysis { return [self studyPresentationController].quickSentenceAnalysis; }

- (void)setQuickSentenceAnalysis:(FYAnalysisResult *)value { [self studyPresentationController].quickSentenceAnalysis = value; }

- (NSString *)quickSentenceAnalysisSource { return [self studyPresentationController].quickSentenceAnalysisSource; }

- (void)setQuickSentenceAnalysisSource:(NSString *)value { [self studyPresentationController].quickSentenceAnalysisSource = value; }

- (NSString *)quickSentenceAnalysisTranslation { return [self studyPresentationController].quickSentenceAnalysisTranslation; }

- (void)setQuickSentenceAnalysisTranslation:(NSString *)value { [self studyPresentationController].quickSentenceAnalysisTranslation = value; }

- (NSString *)quickSentenceAnalysisError { return [self studyPresentationController].quickSentenceAnalysisError; }

- (void)setQuickSentenceAnalysisError:(NSString *)value { [self studyPresentationController].quickSentenceAnalysisError = value; }

- (BOOL)quickSentenceAnalyzing { return [self studyPresentationController].quickSentenceAnalyzing; }

- (void)setQuickSentenceAnalyzing:(BOOL)value { [self studyPresentationController].quickSentenceAnalyzing = value; }

- (NSInteger)quickAnalysisGeneration { return [self studyPresentationController].quickAnalysisGeneration; }

- (void)setQuickAnalysisGeneration:(NSInteger)value { [self studyPresentationController].quickAnalysisGeneration = value; }

- (NSButton *)quickGrammarExpandButton { return [self studyPresentationController].quickGrammarExpandButton; }

- (void)setQuickGrammarExpandButton:(NSButton *)value { [self studyPresentationController].quickGrammarExpandButton = value; }

- (NSButton *)quickGrammarReviewButton { return [self studyPresentationController].quickGrammarReviewButton; }

- (void)setQuickGrammarReviewButton:(NSButton *)value { [self studyPresentationController].quickGrammarReviewButton = value; }

- (NSTextField *)quickGrammarReviewStatus { return [self studyPresentationController].quickGrammarReviewStatus; }

- (void)setQuickGrammarReviewStatus:(NSTextField *)value { [self studyPresentationController].quickGrammarReviewStatus = value; }

- (BOOL)sentenceBookmarkPending { return [self studyPresentationController].sentenceBookmarkPending; }

- (void)setSentenceBookmarkPending:(BOOL)value { [self studyPresentationController].sentenceBookmarkPending = value; }

- (void)ensureStudyChatSession { [[self studyPresentationController] ensureStudyChatSession]; }

- (FYStudyChatView *)makeStudyChatViewForOverlay:(BOOL)overlay { return [[self studyPresentationController] makeStudyChatViewForOverlay:overlay]; }

- (void)referenceLatestStudySentence:(id)sender { [[self studyPresentationController] referenceLatestStudySentence:sender]; }

- (void)resolveLatestStudyIdentity:(void (^)(FYRequestIdentity *))completion { [[self studyPresentationController] resolveLatestStudyIdentity:completion]; }

- (void)resolveLatestStudySentence:(void (^)(NSString *,NSString *))completion { [[self studyPresentationController] resolveLatestStudySentence:completion]; }

- (void)askQuickSentence:(id)sender { [[self studyPresentationController] askQuickSentence:sender]; }

- (void)refreshStudyChatViews { [[self studyPresentationController] refreshStudyChatViews]; }

- (void)sendStudyChat:(NSString *)text { [[self studyPresentationController] sendStudyChat:text]; }

- (void)configureStudyOverlay:(NSPanel *)panel { [[self studyPresentationController] configureStudyOverlay:panel]; }

- (void)showStudyChatOverlay:(id)sender { [[self studyPresentationController] showStudyChatOverlay:sender]; }

- (void)closeStudyOverlay:(id)sender { [[self studyPresentationController] closeStudyOverlay:sender]; }

- (void)cancelQuickSentenceAnalysis { [[self studyPresentationController] cancelQuickSentenceAnalysis]; }

- (void)analyzeQuickSentence:(id)sender { [[self studyPresentationController] analyzeQuickSentence:sender]; }

- (void)showQuickSentence:(id)sender { [[self studyPresentationController] showQuickSentence:sender]; }

- (void)selectQuickStructure:(NSButton *)sender { [[self studyPresentationController] selectQuickStructure:sender]; }

- (BOOL)quickSentenceIsBookmarked { return [[self studyPresentationController] quickSentenceIsBookmarked]; }

- (void)bookmarkQuickSentence:(id)sender { [[self studyPresentationController] bookmarkQuickSentence:sender]; }

- (FYGrammarBookmark *)quickGrammarBookmark { return [[self studyPresentationController] quickGrammarBookmark]; }

- (void)updateQuickGrammarBookmark { [[self studyPresentationController] updateQuickGrammarBookmark]; }

- (void)bookmarkQuickGrammar:(id)sender { [[self studyPresentationController] bookmarkQuickGrammar:sender]; }

- (NSView *)quickGrammarDetailForItem:(FYGrammarItem *)item { return [[self studyPresentationController] quickGrammarDetailForItem:item]; }

- (void)selectQuickGrammar:(NSButton *)sender { [[self studyPresentationController] selectQuickGrammar:sender]; }

- (NSTextField *)quickReadingLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color { return [[self studyPresentationController] quickReadingLabel:text size:size weight:weight color:color]; }

- (NSView *)quickReadingCard:(NSStackView *)stack tinted:(BOOL)tinted { return [[self studyPresentationController] quickReadingCard:stack tinted:tinted]; }

- (void)renderQuickSentence { [[self studyPresentationController] renderQuickSentence]; }

- (void)openStudyWorkspace:(id)sender { [[self studyPresentationController] openStudyWorkspace:sender]; }

- (void)openInlineLearningForBlockText:(NSString *)source translation:(NSString *)translation { [[self studyPresentationController] openInlineLearningForBlockText:source translation:translation]; }

- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot { [[self studyPresentationController] openInlineLearningWithSnapshot:snapshot]; }

- (void)bindInlineStudyChatToSource:(NSString *)source translation:(NSString *)translation { [[self studyPresentationController] bindInlineStudyChatToSource:source translation:translation]; }

- (void)returnFromStudyChatToInlineLearning:(id)sender { [[self studyPresentationController] returnFromStudyChatToInlineLearning:sender]; }

- (NSScrollView *)quickSentenceScrollView { return [[self studyPresentationController] quickSentenceScrollView]; }

- (void)captureQuickSentenceScrollPosition { [[self studyPresentationController] captureQuickSentenceScrollPosition]; }

- (void)restoreQuickSentenceScrollPosition { [[self studyPresentationController] restoreQuickSentenceScrollPosition]; }

- (void)updateInlineReturnButtonVisibility { [[self studyPresentationController] updateInlineReturnButtonVisibility]; }

- (NSUInteger)quickSourceHoverGeneration { return [self referencePresentationController].quickSourceHoverGeneration; }

- (void)setQuickSourceHoverGeneration:(NSUInteger)value { [self referencePresentationController].quickSourceHoverGeneration = value; }

- (FYReferenceDictionary *)referenceDictionary { return [self referencePresentationController].referenceDictionary; }

- (void)setReferenceDictionary:(FYReferenceDictionary *)value { [self referencePresentationController].referenceDictionary = value; }

- (NSUInteger)sourceHoverGeneration { return [self referencePresentationController].sourceHoverGeneration; }

- (void)setSourceHoverGeneration:(NSUInteger)value { [self referencePresentationController].sourceHoverGeneration = value; }

- (BOOL)sourceHoverSuspended { return [self referencePresentationController].sourceHoverSuspended; }

- (void)setSourceHoverSuspended:(BOOL)value { [self referencePresentationController].sourceHoverSuspended = value; }

- (NSCache<NSString *,NSString *> *)sourceHoverCache { return [self referencePresentationController].sourceHoverCache; }

- (void)setSourceHoverCache:(NSCache<NSString *,NSString *> *)value { [self referencePresentationController].sourceHoverCache = value; }

- (NSView *)referenceCard { return [self referencePresentationController].referenceCard; }

- (void)setReferenceCard:(NSView *)value { [self referencePresentationController].referenceCard = value; }

- (NSTextField *)referenceSearchField { return [self referencePresentationController].referenceSearchField; }

- (void)setReferenceSearchField:(NSTextField *)value { [self referencePresentationController].referenceSearchField = value; }

- (NSSegmentedControl *)referenceTabs { return [self referencePresentationController].referenceTabs; }

- (void)setReferenceTabs:(NSSegmentedControl *)value { [self referencePresentationController].referenceTabs = value; }

- (NSPopUpButton *)referenceSensePopup { return [self referencePresentationController].referenceSensePopup; }

- (void)setReferenceSensePopup:(NSPopUpButton *)value { [self referencePresentationController].referenceSensePopup = value; }

- (NSStackView *)referenceDetailStack { return [self referencePresentationController].referenceDetailStack; }

- (void)setReferenceDetailStack:(NSStackView *)value { [self referencePresentationController].referenceDetailStack = value; }

- (NSStackView *)referenceMoreExamples { return [self referencePresentationController].referenceMoreExamples; }

- (void)setReferenceMoreExamples:(NSStackView *)value { [self referencePresentationController].referenceMoreExamples = value; }

- (NSString *)referenceActiveWord { return [self referencePresentationController].referenceActiveWord; }

- (void)setReferenceActiveWord:(NSString *)value { [self referencePresentationController].referenceActiveWord = value; }

- (NSStackView *)referenceStack { return [self referencePresentationController].referenceStack; }

- (void)setReferenceStack:(NSStackView *)value { [self referencePresentationController].referenceStack = value; }

- (NSPopUpButton *)referenceEntryPopup { return [self referencePresentationController].referenceEntryPopup; }

- (void)setReferenceEntryPopup:(NSPopUpButton *)value { [self referencePresentationController].referenceEntryPopup = value; }

- (NSArray<NSDictionary *> *)referenceRecords { return [self referencePresentationController].referenceRecords; }

- (void)setReferenceRecords:(NSArray<NSDictionary *> *)value { [self referencePresentationController].referenceRecords = value; }

- (NSInteger)referenceRequestGeneration { return [self referencePresentationController].referenceRequestGeneration; }

- (void)setReferenceRequestGeneration:(NSInteger)value { [self referencePresentationController].referenceRequestGeneration = value; }

- (NSURL *)referenceResourceURL:(NSString *)file { return [[self referencePresentationController] referenceResourceURL:file]; }

- (NSView *)makeIntegratedReferenceCard { return [[self referencePresentationController] makeIntegratedReferenceCard]; }

- (NSButton *)referenceLink:(NSString *)title URL:(NSString *)url { return [[self referencePresentationController] referenceLink:title URL:url]; }

- (void)openReferenceLink:(NSButton *)sender { [[self referencePresentationController] openReferenceLink:sender]; }

- (void)revealReferenceCard { [[self referencePresentationController] revealReferenceCard]; }

- (void)searchReferenceWord:(id)sender { [[self referencePresentationController] searchReferenceWord:sender]; }

- (void)lookupReferenceWord:(NSString *)word reading:(NSString *)reading { [[self referencePresentationController] lookupReferenceWord:word reading:reading]; }

- (void)showSelectedWordReference:(id)sender { [[self referencePresentationController] showSelectedWordReference:sender]; }

- (void)showSavedWordReference:(NSButton *)sender { [[self referencePresentationController] showSavedWordReference:sender]; }

- (void)referenceEntryChanged:(id)sender { [[self referencePresentationController] referenceEntryChanged:sender]; }

- (void)referenceTabChanged:(id)sender { [[self referencePresentationController] referenceTabChanged:sender]; }

- (void)addReferenceDisclosure:(NSString *)title content:(NSView *)content { [[self referencePresentationController] addReferenceDisclosure:title content:content]; }

- (void)toggleReferenceExtra:(NSButton *)sender { [[self referencePresentationController] toggleReferenceExtra:sender]; }

- (void)showReferenceLicenses:(id)sender { [[self referencePresentationController] showReferenceLicenses:sender]; }

- (BOOL)openReferenceLicensesDirectory:(NSURL *)directory { return [[self referencePresentationController] openReferenceLicensesDirectory:directory]; }

- (void)setSourceHoverTip:(NSString *)tip range:(NSRange)range source:(NSString *)source views:(NSArray *)views { [[self referencePresentationController] setSourceHoverTip:tip range:range source:source views:views]; }

- (void)applyAnalysisHoverTips:(FYAnalysisResult *)analysis source:(NSString *)source views:(NSArray *)views { [[self referencePresentationController] applyAnalysisHoverTips:analysis source:source views:views]; }

- (void)populateSourceHoverTips:(NSString *)source views:(NSArray *)views analysis:(FYAnalysisResult *)analysis fallback:(NSString *)fallback isCurrent:(BOOL (^)(void))isCurrent { [[self referencePresentationController] populateSourceHoverTips:source views:views analysis:analysis fallback:fallback isCurrent:isCurrent]; }

- (void)refreshSourceHoverTips { [[self referencePresentationController] refreshSourceHoverTips]; }

- (void)refreshQuickSentenceHoverTips { [[self referencePresentationController] refreshQuickSentenceHoverTips]; }
@end
