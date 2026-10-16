#pragma once
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "FYLearningCoordinator.h"
@interface FYLearningProjection : NSObject
+ (NSArray<FYSentenceRecord *> *)displayHistoryRecords:(NSArray<FYSentenceRecord *> *)records;
+ (NSString *)vocabularyExampleText:(NSArray<FYVocabularyExample *> *)examples requestedIndex:(NSUInteger)index;
+ (FYSentenceRecord *)historyRecordInList:(NSArray<FYSentenceRecord *> *)records index:(NSInteger)index identifier:(NSString *)identifier;
+ (FYGrammarBookmark *)bookmarkInList:(NSArray<FYGrammarBookmark *> *)bookmarks grammarName:(NSString *)name sentenceID:(NSString *)sentenceID version:(NSInteger)version;
+ (FYGrammarItem *)grammarItemInList:(NSArray<FYGrammarItem *> *)items index:(NSInteger)index fallbackToFirst:(BOOL)fallback;
+ (BOOL)analysisMatchesSentenceID:(NSString *)analysisSentenceID version:(NSInteger)analysisVersion currentSentenceID:(NSString *)currentSentenceID currentVersion:(NSInteger)currentVersion;
+ (NSArray<FYGrammarItem *> *)applicableGrammarItems:(NSArray<FYGrammarItem *> *)items text:(NSString *)text;
+ (BOOL)followupBelongsToItem:(id)item requestedItem:(id)requestedItem requestGeneration:(NSInteger)requestGeneration currentGeneration:(NSInteger)currentGeneration
        sentenceID:(NSString *)sentenceID version:(NSInteger)version currentSentenceID:(NSString *)currentSentenceID currentVersion:(NSInteger)currentVersion;
+ (BOOL)requestSentenceID:(NSString *)sentenceID version:(NSInteger)version generation:(NSInteger)generation
        matchesSentenceID:(NSString *)currentSentenceID version:(NSInteger)currentVersion generation:(NSInteger)currentGeneration;
+ (BOOL)selectionRange:(NSRange)range appliesToText:(NSString *)text sentenceID:(NSString *)sentenceID
              version:(NSInteger)version generation:(NSInteger)generation currentText:(NSString *)currentText
    currentSentenceID:(NSString *)currentSentenceID currentVersion:(NSInteger)currentVersion currentGeneration:(NSInteger)currentGeneration;
+ (FYVocabularyEntry *)nextReviewVocabularyInList:(NSArray<FYVocabularyEntry *> *)list index:(NSInteger)index nextIndex:(NSInteger *)nextIndex;
+ (FYVocabularyEntry *)vocabularyInList:(NSArray<FYVocabularyEntry *> *)list identifier:(NSString *)identifier fallbackIndex:(NSInteger)index;
@end

#pragma clang diagnostic pop
