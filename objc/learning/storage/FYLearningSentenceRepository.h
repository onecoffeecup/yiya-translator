#import "../FYLearningModels.h"
@class FYLearningDatabaseSession;

// Internal synchronous operations: run only on the shared database session queue.
@interface FYLearningSentenceRepository : NSObject
- (instancetype)initWithSession:(FYLearningDatabaseSession *)session;
// Kept reachable through the Store's existing internal KVC compatibility accessor.
@property(nonatomic) NSUInteger historyRetentionLimit;
- (NSError *)configureHistoryRetentionWithLimit:(NSUInteger)limit;
- (NSError *)preserveSentenceForHistory:(NSString *)sentenceID;
- (NSError *)ensureSessionWithID:(NSString *)sessionID displayName:(NSString *)displayName language:(NSString *)language;
- (NSError *)insertSentenceWithID:(NSString *)sentenceID
    sessionID:(NSString *)sessionID
    kind:(FYSentenceKind)kind
    originalText:(NSString *)originalText
    occurredAt:(NSDate *)occurredAt;
- (NSError *)updateTranslation:(NSString *)translation forSentence:(NSString *)sentenceID version:(NSInteger)version;
- (NSInteger)appendVersionForSentence:(NSString *)sentenceID
    text:(NSString *)text
    translation:(NSString *)translation
    error:(NSError **)outError;
- (NSError *)recordExcludedSpeakerJSON:(NSString *)json
    sentenceID:(NSString *)sentenceID
    source:(NSString *)source
    version:(NSInteger)version;
- (FYSentenceRecord *)fetchSentence:(NSString *)sentenceID error:(NSError **)outError;
- (NSArray<FYSentenceRecord *> *)fetchRecentSentencesWithLimit:(NSUInteger)limit error:(NSError **)outError;
- (NSArray<FYSentenceVersion *> *)fetchVersionsForSentence:(NSString *)sentenceID error:(NSError **)outError;
@end
