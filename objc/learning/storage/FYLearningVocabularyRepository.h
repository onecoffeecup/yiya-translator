#import "../FYLearningModels.h"
@class FYLearningDatabaseSession;

// Internal synchronous operations: run only on the shared database session queue.
@interface FYLearningVocabularyRepository : NSObject
- (instancetype)initWithSession:(FYLearningDatabaseSession *)session;
- (NSError *)upsertVocabulary:(FYVocabularyEntry *)entry;
- (NSError *)attachExample:(FYVocabularyExample *)example;
- (NSError *)saveVocabulary:(FYVocabularyEntry *)entry withExample:(FYVocabularyExample *)example;
- (NSArray<FYVocabularyEntry *> *)fetchVocabularyListWithError:(NSError **)outError;
- (NSError *)updateReviewStatus:(FYReviewStatus)status forVocabulary:(NSString *)vocabularyID;
- (NSError *)deleteVocabulary:(NSString *)vocabularyID;
- (NSArray<FYVocabularyExample *> *)fetchExamplesForVocabulary:(NSString *)vocabularyID error:(NSError **)outError;
@end
