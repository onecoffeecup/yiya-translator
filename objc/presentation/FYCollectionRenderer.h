#pragma once
#import <AppKit/AppKit.h>
#import "../learning/FYLearningModels.h"
@class FYGrammarCatalog,FYLearningStore;

@protocol FYCollectionRenderSource <NSObject>
@property(nonatomic, strong) NSTextField *grammarBookmarkListLabel;
@property(nonatomic, strong) NSPopUpButton *grammarBookmarkPopup;
@property(nonatomic, strong) NSStackView *grammarBookmarkStack;
@property(nonatomic, strong) NSStackView *historyListStack;
@property(nonatomic, strong) NSPopUpButton *historyPopup;
@property(nonatomic, strong) NSButton *knownButton;
@property(nonatomic, strong) NSTextField *learningCollectionCount;
@property(nonatomic, strong) NSStackView *learningCollectionHost;
@property(nonatomic, copy) NSArray<NSView *> *learningCollectionSections;
@property(nonatomic, copy) NSArray<NSButton *> *learningCollectionTabs;
@property(nonatomic, strong) NSTextField *learningCollectionTitle;
@property(nonatomic, strong) NSButton *notYetButton;
@property(nonatomic, strong) NSButton *revealButton;
@property(nonatomic, strong) NSTextField *reviewMeaningLabel;
@property(nonatomic, strong) NSTextField *reviewPromptLabel;
@property(nonatomic, strong) NSTextField *reviewWordLabel;
@property(nonatomic, strong) NSStackView *savedGrammarCardStack;
@property(nonatomic, strong) NSStackView *savedSentenceStack;
@property(nonatomic, strong) NSView *vocabularyEmptyCard;
@property(nonatomic, strong) NSTextField *vocabularyExamplesLabel;
@property(nonatomic, strong) NSPopUpButton *vocabularyExamplesPopup;
@property(nonatomic, strong) NSTextField *vocabularyListLabel;
@property(nonatomic, strong) NSTextField *vocabularyStatusLabel;
@property(nonatomic, strong) NSStackView *wordCardStack;
- (FYGrammarCatalog *)grammarCatalog;
- (FYLearningStore *)learningStore;
- (NSArray<FYVocabularyEntry *> *)reviewList;
- (NSArray<FYGrammarBookmark *> *)grammarBookmarks;
- (NSArray<FYSentenceRecord *> *)historyRecords;
- (NSArray<FYRequestIdentity *> *)savedSentences;
- (NSMutableSet<NSString *> *)expandedWordCards;
- (NSMutableDictionary<NSString *,NSNumber *> *)revealedMeanings;
- (void)setRevealedMeanings:(NSMutableDictionary<NSString *,NSNumber *> *)value;
- (NSMutableDictionary<NSString *,NSNumber *> *)wordExampleIndices;
@property(nonatomic) NSInteger wordCardsGeneration;
@property(nonatomic) NSInteger learningCollectionIndex;
- (id)collectionActionTarget;
- (void)loadExamplesForWord:(NSString *)word generation:(NSInteger)generation sourceLabel:(NSTextField *)label exampleButton:(NSButton *)button;
- (void)selectLearningCollection:(NSButton *)sender;
- (void)updateLearningCollectionSummary;
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
@end

// Stateless native factories, rows and in-place updates; views remain with Collection.
@interface FYCollectionRenderer : NSObject
+ (NSView *)makeVocabularyPageWithReceiver:(id<FYCollectionRenderSource>)receiver;
+ (NSView *)makeHistoryPageWithReceiver:(id<FYCollectionRenderSource>)receiver;
+ (void)updateSummaryWithReceiver:(id<FYCollectionRenderSource>)receiver;
+ (void)selectCollection:(NSButton *)sender receiver:(id<FYCollectionRenderSource>)receiver;
+ (void)rebuildWordCardsWithReceiver:(id<FYCollectionRenderSource>)receiver;
+ (void)renderHistoryRowsWithReceiver:(id<FYCollectionRenderSource>)receiver;
+ (void)renderGrammarRowsWithReceiver:(id<FYCollectionRenderSource>)receiver;
+ (void)renderSentenceRows:(NSArray<FYRequestIdentity *> *)identities receiver:(id<FYCollectionRenderSource>)receiver;
+ (void)updateDetailsButton:(NSButton *)sender expanded:(BOOL)expanded;
+ (void)updateMeaningButton:(NSButton *)sender entry:(FYVocabularyEntry *)entry revealed:(BOOL)revealed;
@end
