#pragma once
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "FYLearningCoordinator.h"

@protocol FYLearningCollectionWorkflowSource <NSObject>
@property(nonatomic, strong) FYLearningAnalyzer *analyzer;
@property(nonatomic, copy, nullable) NSString *currentSentenceID;
@property(nonatomic, copy) NSString *currentSourceText;
@property(nonatomic, copy, nullable) NSString *currentTranslation;
@property(nonatomic) NSInteger currentVersion;
@property(nonatomic, strong) FYLearningStore *store;
@property(nonatomic, strong) NSMutableArray *vocabularyOperations;
@property(nonatomic, strong) dispatch_queue_t vocabularyQueue;
- (void)startNextVocabularySave;
- (FYVocabularyEntry *)findDuplicateOf:(FYVocabularyEntry *)entry in:(NSArray<FYVocabularyEntry *> *)existing;
- (BOOL)mergeCompletionInto:(FYVocabularyEntry *)existing from:(FYVocabularyEntry *)incoming;
@end

// Sole owner of this workflow state; Source accesses are compatibility forwards.
@interface FYLearningCollectionWorkflow : NSObject
@property(nonatomic, strong) dispatch_queue_t vocabularyQueue;
@property(nonatomic, strong) NSMutableArray *vocabularyOperations;
- (void)completeVocabulary:(NSString *)surface
                   context:(NSString *)context
                completion:(void (^)(FYVocabularyEntry *, NSError *))completion receiver:(id<FYLearningCollectionWorkflowSource>)receiver;
- (void)bookmarkVocabulary:(FYVocabularyEntry *)entry selectedText:(NSString *)selectedText
                completion:(void (^)(FYVocabularyEntry *, BOOL, NSError *))completion receiver:(id<FYLearningCollectionWorkflowSource>)receiver;
- (void)startNextVocabularySaveWithReceiver:(id<FYLearningCollectionWorkflowSource>)receiver;
- (FYVocabularyEntry *)findDuplicateOf:(FYVocabularyEntry *)entry in:(NSArray<FYVocabularyEntry *> *)existing receiver:(id<FYLearningCollectionWorkflowSource>)receiver;
- (BOOL)mergeCompletionInto:(FYVocabularyEntry *)existing from:(FYVocabularyEntry *)incoming receiver:(id<FYLearningCollectionWorkflowSource>)receiver;
- (void)attachExampleForVocabulary:(NSString *)vocabularyID
                      selectedText:(NSString *)selectedText
                        sentenceID:(NSString *)sentenceID
                           version:(NSInteger)version
                         sourceText:(NSString *)sourceText
                        translation:(NSString *)translation
                        completion:(void (^)(NSError *))completion receiver:(id<FYLearningCollectionWorkflowSource>)receiver;
- (void)bookmarkGrammar:(FYGrammarItem *)item completion:(void (^)(NSError *))completion receiver:(id<FYLearningCollectionWorkflowSource>)receiver;
@end

#pragma clang diagnostic pop
