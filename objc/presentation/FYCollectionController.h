#pragma once
#import <AppKit/AppKit.h>
#import "FYCollectionQueryCoordinator.h"
#import "FYCollectionCardCoordinator.h"
#import "FYCollectionRenderer.h"
#import "FYCollectionReviewCoordinator.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

// Explicit context, peer actions and view factories; no application type dependency.
@protocol FYCollectionControllerHost <NSObject, NSWindowDelegate, NSTextFieldDelegate>
@property(nonatomic, strong) FYAnalysisResult *currentAnalysis;
@property(nonatomic, strong) FYGrammarCatalog *grammarCatalog;
@property(nonatomic, strong) NSButton *grammarDetailBookmarkButton;
@property(nonatomic, strong) FYLearningCoordinator *learningCoordinator;
@property(nonatomic, strong) FYLearningStore *learningStore;
@property(nonatomic, strong) NSButton *quickSentenceBookmarkButton;
@property(nonatomic, copy) NSString *quickSentenceID;
@property(nonatomic) BOOL sentenceBookmarkPending;
- (void)selectPageAtIndex:(NSInteger)index;
- (void)analyzeCurrentSentence:(id)sender;
- (FYGrammarBookmark *)bookmarkForCurrentGrammar;
- (BOOL)analysisMatchesCurrentSentence;
- (void)clearAnalysisDisplay;
- (void)refreshLearningSource;
- (void)refreshLearningStatus;
- (void)clearArrangedSubviews:(NSStackView *)stack;
- (NSStackView *)verticalStack;
- (NSStackView *)horizontalStack;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSView *)spacer;
- (NSView *)separator;
- (NSColor *)uiInk;
- (NSColor *)uiMuted;
- (NSView *)cardWithStack:(NSStackView *)stack;
- (NSTextField *)cardTitle:(NSString *)text;
- (NSTextField *)mutedLabel:(NSString *)text;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
- (BOOL)quickSentenceIsBookmarked;
- (void)updateQuickGrammarBookmark;
@end

// Owns collection views and ephemeral state. Persistence remains in learning services.
@interface FYCollectionController : NSObject <FYCollectionReviewSource,FYCollectionQuerySource,FYCollectionCardSource,FYCollectionRenderSource>
@property(nonatomic, strong, readonly) FYCollectionReviewCoordinator *reviewCoordinator;
@property(nonatomic,strong,readonly) FYCollectionQueryCoordinator *queryCoordinator;
@property(nonatomic,strong,readonly) FYCollectionCardCoordinator *cardCoordinator;
@property(nonatomic, weak) id<FYCollectionControllerHost> host;
- (instancetype)initWithHost:(id<FYCollectionControllerHost>)host;
@property(nonatomic, strong) NSMutableSet<NSString *> *expandedWordCards;
@property(nonatomic, strong) NSTextField *grammarBookmarkListLabel;
@property(nonatomic, strong) NSPopUpButton *grammarBookmarkPopup;
@property(nonatomic, strong) NSStackView *grammarBookmarkStack;
@property(nonatomic, strong) NSArray<FYGrammarBookmark *> *grammarBookmarks;
@property(nonatomic, strong) NSStackView *historyListStack;
@property(nonatomic, strong) NSPopUpButton *historyPopup;
@property(nonatomic, strong) NSArray<FYSentenceRecord *> *historyRecords;
@property(nonatomic, strong) NSButton *knownButton;
@property(nonatomic, strong) NSTextField *learningCollectionCount;
@property(nonatomic, strong) NSStackView *learningCollectionHost;
@property(nonatomic) NSInteger learningCollectionIndex;
@property(nonatomic, copy) NSArray<NSView *> *learningCollectionSections;
@property(nonatomic, copy) NSArray<NSButton *> *learningCollectionTabs;
@property(nonatomic, strong) NSTextField *learningCollectionTitle;
@property(nonatomic, strong) NSButton *notYetButton;
@property(nonatomic, strong) NSButton *revealButton;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *revealedMeanings;
@property(nonatomic) NSInteger reviewIndex;
@property(nonatomic, strong) NSArray<FYVocabularyEntry *> *reviewList;
@property(nonatomic, strong) NSTextField *reviewMeaningLabel;
@property(nonatomic, strong) NSTextField *reviewPromptLabel;
@property(nonatomic, strong) NSTextField *reviewWordLabel;
@property(nonatomic, strong) FYVocabularyEntry *reviewingEntry;
@property(nonatomic, strong) NSStackView *savedGrammarCardStack;
@property(nonatomic, strong) NSStackView *savedSentenceStack;
@property(nonatomic, copy) NSArray<FYRequestIdentity *> *savedSentences;
@property(nonatomic, strong) NSView *vocabularyEmptyCard;
@property(nonatomic, strong) NSTextField *vocabularyExamplesLabel;
@property(nonatomic, strong) NSArray<FYVocabularyEntry *> *vocabularyExamplesList;
@property(nonatomic, strong) NSPopUpButton *vocabularyExamplesPopup;
@property(nonatomic, strong) NSTextField *vocabularyListLabel;
@property(nonatomic, strong) NSTextField *vocabularyStatusLabel;
@property(nonatomic, strong) NSStackView *wordCardStack;
@property(nonatomic) NSInteger wordCardsGeneration;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *wordExampleIndices;
- (NSView *)makeVocabularyPage;
- (void)updateLearningCollectionSummary;
- (void)selectLearningCollection:(NSButton *)sender;
- (void)openHistoryAnalysis:(NSButton *)sender;
- (void)refreshHistory;
- (void)refreshHistoryAction:(id)sender;
- (void)historyChanged:(id)sender;
- (void)refreshVocabularyList;
- (void)rebuildWordCards;
- (void)toggleSavedWordDetails:(NSButton *)sender;
- (FYVocabularyEntry *)wordForCardButton:(NSButton *)sender;
- (void)nextWordExample:(NSButton *)sender;
- (void)toggleWordMeaning:(NSButton *)sender;
- (void)toggleWordMastered:(NSButton *)sender;
- (void)removeWordCard:(NSButton *)sender;
- (void)nextReviewWord:(id)sender;
- (void)revealReviewMeaning:(id)sender;
- (void)markReviewKnown:(id)sender;
- (void)markReviewLearning:(id)sender;
- (void)setReviewStatus:(FYReviewStatus)status;
- (void)removeReviewWord:(id)sender;
- (void)refreshGrammarBookmarks:(id)sender;
- (void)grammarBookmarkChanged:(id)sender;
- (void)deleteGrammarBookmark:(NSButton *)sender;
- (void)refreshVocabularyExamplesPopup;
- (void)vocabularyExamplesChanged:(id)sender;
- (void)showVocabularyExamples:(id)sender;
- (NSView *)makeHistoryPage;
- (void)refreshSavedSentences;
- (FYRequestIdentity *)savedSentenceForButton:(NSButton *)sender;
- (void)openSavedSentence:(NSButton *)sender;
- (void)removeSavedSentence:(NSButton *)sender;
@end
#pragma clang diagnostic pop
