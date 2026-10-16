#pragma once
#import <Foundation/Foundation.h>
#import "../FYGrammarActionState.h"
#import "../learning/FYLearningStore.h"

@protocol FYQuickSentenceAnalysisSource <NSObject>
@property(nonatomic) NSInteger quickAnalysisGeneration;
@property(nonatomic) BOOL quickSentenceAnalyzing;
@property(nonatomic,strong) FYAnalysisResult *quickSentenceAnalysis;
@property(nonatomic,copy) NSString *quickSentenceAnalysisError;
@property(nonatomic,copy) NSString *quickSentenceAnalysisSource;
@property(nonatomic,copy) NSString *quickSentenceAnalysisTranslation;
@property(nonatomic,strong) FYLearningAnalyzer *quickSentenceAnalyzer;
@property(nonatomic) NSInteger quickSelectedGrammarIndex;
- (BOOL)quickSentenceRequested;
- (NSString *)quickSentenceSource;
- (NSString *)quickSentenceTranslation;
- (FYGrammarActionState *)quickGrammarActions;
- (void)cancelQuickSentenceAnalysis;
- (void)configureQuickSentenceAnalyzer:(FYLearningAnalyzer *)analyzer;
- (void)renderQuickSentence;
@end

@protocol FYQuickSentenceBookmarkSource <NSObject>
@property(nonatomic) BOOL sentenceBookmarkPending;
@property(nonatomic) BOOL quickGrammarBookmarkPending;
- (NSString *)quickSentenceID;
- (NSInteger)quickSentenceVersion;
- (NSString *)quickSentenceSource;
- (NSString *)quickSentenceTranslation;
- (NSInteger)quickSelectedGrammarIndex;
- (FYAnalysisResult *)quickSentenceAnalysis;
- (NSArray<FYRequestIdentity *> *)savedSentences;
- (NSArray<FYGrammarBookmark *> *)grammarBookmarks;
- (FYLearningStore *)learningStore;
- (void)disableQuickSentenceBookmarkAction;
- (void)setQuickBookmarkStatusText:(NSString *)text;
- (void)refreshSavedSentences;
- (void)refreshGrammarBookmarks:(id)sender;
- (void)updateQuickGrammarBookmark;
@end

// Original analysis and bookmark workflow; no native controls, idle receiver or store.
@interface FYQuickSentenceCoordinator : NSObject
@property(nonatomic) NSInteger quickAnalysisGeneration;
@property(nonatomic) BOOL quickSentenceAnalyzing;
@property(nonatomic, strong) FYAnalysisResult * quickSentenceAnalysis;
@property(nonatomic, copy) NSString * quickSentenceAnalysisError;
@property(nonatomic, copy) NSString * quickSentenceAnalysisSource;
@property(nonatomic, copy) NSString * quickSentenceAnalysisTranslation;
@property(nonatomic, strong) FYLearningAnalyzer * quickSentenceAnalyzer;
@property(nonatomic) BOOL sentenceBookmarkPending;
@property(nonatomic) BOOL quickGrammarBookmarkPending;
- (void)cancelAnalysisWithReceiver:(id<FYQuickSentenceAnalysisSource>)receiver;
- (void)analyzeWithReceiver:(id<FYQuickSentenceAnalysisSource>)receiver;
- (BOOL)sentenceIsBookmarkedWithReceiver:(id<FYQuickSentenceBookmarkSource>)receiver;
- (void)bookmarkSentenceWithReceiver:(id<FYQuickSentenceBookmarkSource>)receiver;
- (FYGrammarBookmark *)grammarBookmarkWithReceiver:(id<FYQuickSentenceBookmarkSource>)receiver;
- (void)bookmarkGrammarWithReceiver:(id<FYQuickSentenceBookmarkSource>)receiver;
@end
