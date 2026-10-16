#pragma once
#import <Foundation/Foundation.h>
#import "../learning/FYLearningCoordinator.h"

@protocol FYCollectionQuerySource <NSObject>
@property(nonatomic, strong) NSArray<FYSentenceRecord *> * historyRecords;
@property(nonatomic, strong) NSArray<FYGrammarBookmark *> * grammarBookmarks;
@property(nonatomic, strong) NSArray<FYVocabularyEntry *> * vocabularyExamplesList;
@property(nonatomic, copy) NSArray<FYRequestIdentity *> * savedSentences;
- (NSArray<FYVocabularyEntry *> *)reviewList;
- (FYLearningStore *)learningStore;
- (FYLearningCoordinator *)learningCoordinator;
- (FYAnalysisResult *)currentAnalysis;
- (NSString *)quickSentenceID;
- (BOOL)sentenceBookmarkPending;
- (void)setSentenceBookmarkPending:(BOOL)value;
- (BOOL)analysisMatchesCurrentSentence;
- (FYGrammarBookmark *)bookmarkForCurrentGrammar;
- (BOOL)quickSentenceIsBookmarked;
- (void)updateQuickGrammarBookmark;
- (void)refreshSavedSentences;
- (void)refreshGrammarBookmarks:(id)sender;
- (void)updateLearningCollectionSummary;
- (void)refreshLearningSource;
- (void)refreshLearningStatus;
- (void)clearAnalysisDisplay;
- (void)selectPageAtIndex:(NSInteger)index;
- (void)analyzeCurrentSentence:(id)sender;
- (void)clearHistoryRows;
- (void)appendHistoryMessage:(NSString *)text;
- (void)renderHistoryRows;
- (void)clearSavedGrammarRows;
- (void)renderSavedGrammarRows;
- (void)clearSavedSentenceRows;
- (void)renderSavedSentenceRows:(NSArray<FYRequestIdentity *> *)identities;
- (void)setGrammarBookmarkListText:(NSString *)text;
- (void)setGrammarBookmarkListHidden:(BOOL)hidden;
- (void)setMainGrammarBookmarkTitle:(NSString *)text;
- (void)setQuickSentenceBookmarkTitle:(NSString *)text;
- (void)setQuickSentenceBookmarkEnabled:(BOOL)enabled;
- (void)setVocabularyStatusText:(NSString *)text;
- (void)clearVocabularyExampleChoices;
- (void)addVocabularyExampleChoice:(NSString *)text;
- (NSInteger)selectedVocabularyExampleIndex;
- (void)setVocabularyExamplesText:(NSString *)text;
- (NSInteger)wordCardsGeneration;
- (NSMutableDictionary<NSString *, NSNumber *> *)wordExampleIndices;
@end

// Original state and algorithms, with synchronous input providers; no idle receiver/store.
@interface FYCollectionQueryCoordinator : NSObject
@property(nonatomic, strong) NSArray<FYSentenceRecord *> * historyRecords;
@property(nonatomic, strong) NSArray<FYGrammarBookmark *> * grammarBookmarks;
@property(nonatomic, strong) NSArray<FYVocabularyEntry *> * vocabularyExamplesList;
@property(nonatomic, copy) NSArray<FYRequestIdentity *> * savedSentences;
- (void)openHistoryWithReceiver:(id<FYCollectionQuerySource>)receiver tag:(NSInteger(^)(void))tag identifier:(NSString *(^)(void))identifier;
- (void)refreshHistoryWithReceiver:(id<FYCollectionQuerySource>)receiver;
- (void)refreshGrammarWithReceiver:(id<FYCollectionQuerySource>)receiver;
- (void)deleteGrammarWithReceiver:(id<FYCollectionQuerySource>)receiver identifier:(NSString *(^)(void))identifier;
- (void)refreshExampleChoicesWithReceiver:(id<FYCollectionQuerySource>)receiver;
- (void)showExamplesWithReceiver:(id<FYCollectionQuerySource>)receiver;
- (void)refreshSentencesWithReceiver:(id<FYCollectionQuerySource>)receiver;
- (FYRequestIdentity *)sentenceWithReceiver:(id<FYCollectionQuerySource>)receiver identifier:(NSString *(^)(void))identifier;
- (void)openSentenceWithReceiver:(id<FYCollectionQuerySource>)receiver identity:(FYRequestIdentity *(^)(void))identityProvider;
- (void)removeSentenceWithReceiver:(id<FYCollectionQuerySource>)receiver identity:(FYRequestIdentity *(^)(void))identityProvider disable:(void(^)(void))disable;
- (void)loadCardExamplesForWord:(NSString *)vocabularyID generation:(NSInteger)generation receiver:(id<FYCollectionQuerySource>)receiver text:(void(^)(NSString *))text hidden:(void(^)(BOOL))hidden;
@end
