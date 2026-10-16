#import "../FYLearningModels.h"
@class FYLearningDatabaseSession;

// Internal synchronous operations: run only on the shared database session queue.
@interface FYLearningAnalysisCacheRepository : NSObject
- (instancetype)initWithSession:(FYLearningDatabaseSession *)session;
- (NSError *)saveAnalysisResult:(FYAnalysisResult *)result
    sentenceID:(NSString *)sentenceID
    version:(NSInteger)version
    textHash:(NSString *)textHash
    promptVersion:(NSInteger)promptVersion
    catalogVersion:(NSInteger)catalogVersion
    modelConfig:(NSString *)modelConfig;
- (FYAnalysisResult *)fetchAnalysisForSentence:(NSString *)sentenceID
    version:(NSInteger)version
    modelConfig:(NSString **)outModelConfig
    error:(NSError **)outError;
@end
