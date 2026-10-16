#import "FYLearningAnalysisWorkflow.h"
#import "FYLearningWorkflowUtilities.h"

@implementation FYLearningAnalysisWorkflow
- (void)invalidateAnalysisWithReceiver:(id<FYLearningAnalysisWorkflowSource>)receiver {
    receiver.analysisGeneration += 1;
    [receiver.analyzer cancelAll];
    [receiver.reviewAnalyzer cancelAll];
}

- (void)analyzeCurrent:(void (^)(FYAnalysisResult *, NSError *))completion receiver:(id<FYLearningAnalysisWorkflowSource>)receiver {
    NSString *sentenceID = receiver.currentSentenceID;
    NSInteger version = receiver.currentVersion;
    NSString *text = receiver.currentSourceText;
    NSString *translation = receiver.currentTranslation;
    if (sentenceID.length == 0 || text.length == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"FYLearningCoordinator" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"当前没有可分析的句子。"}]);
        }
        return;
    }
    NSInteger generation = ++receiver.analysisGeneration;
    NSString *hash = FYTextHash(text);
    NSInteger promptVersion = 8; // Non-thinking compact analysis; only invalid anchors trigger one repair.
    NSInteger catalogVersion = receiver.catalog.catalogVersion;
    NSString *modelConfig = [NSString stringWithFormat:@"%@|%@|%ld|%ld",
                             receiver.analyzer.baseURL ?: @"", receiver.analyzer.model ?: @"",
                             (long)promptVersion, (long)catalogVersion];

    [receiver.store fetchAnalysisForSentence:sentenceID version:version completion:^(FYAnalysisResult *cached, NSString *model, NSError *error) {
        if (generation != receiver.analysisGeneration || ![receiver currentMatches:sentenceID version:version]) {
            completion(nil, [NSError errorWithDomain:@"FYLearningCoordinator" code:2 userInfo:@{NSLocalizedDescriptionKey: @"分析已被取消或句子已切换。"}]); return;
        }
        if (error) { completion(nil, error); return; }
        BOOL cacheHit = cached && (cached.status == FYAnalysisStatusSuccess || cached.status == FYAnalysisStatusNoResult) &&
                        [model isEqualToString:modelConfig];
        if (cacheHit) {
            if (generation != receiver.analysisGeneration || ![receiver currentMatches:sentenceID version:version]) {
                completion(nil, [NSError errorWithDomain:@"FYLearningCoordinator" code:2
                                                userInfo:@{NSLocalizedDescriptionKey: @"分析已被取消或句子已切换。"}]);
                return;
            }
            cached.sentenceID = sentenceID;
            cached.version = version;
            completion(cached, nil);
            return;
        }
        [receiver.analyzer analyzeSentence:text translation:translation completion:^(FYAnalysisResult *result, NSError *analyzeError) {
            if (generation != receiver.analysisGeneration || ![receiver currentMatches:sentenceID version:version]) {
                completion(nil, [NSError errorWithDomain:@"FYLearningCoordinator" code:2
                                                userInfo:@{NSLocalizedDescriptionKey: @"分析已被取消或句子已切换。"}]);
                return;
            }
            if (analyzeError) {
                completion(nil, analyzeError);
                return;
            }
            result.sentenceID = sentenceID;
            result.version = version;
            [receiver.store saveAnalysisResult:result sentenceID:sentenceID version:version textHash:hash
                             promptVersion:promptVersion catalogVersion:catalogVersion modelConfig:modelConfig completion:^(NSError *e) { if (e && receiver.persistenceErrorHandler) { receiver.persistenceErrorHandler(e); } }];
            completion(result, nil);
        }];
    }];
}

- (void)reviewCurrentAnalysis:(FYAnalysisResult *)existing
                  completion:(void (^)(FYAnalysisResult *, NSError *))completion receiver:(id<FYLearningAnalysisWorkflowSource>)receiver {
    NSString *sentenceID = receiver.currentSentenceID, *text = receiver.currentSourceText;
    NSString *translation = receiver.currentTranslation;
    NSInteger version = receiver.currentVersion;
    if (!sentenceID.length || ![FYLearningCoordinator analysisMatchesSentenceID:existing.sentenceID version:existing.version
        currentSentenceID:sentenceID currentVersion:version]) {
        completion(nil, [NSError errorWithDomain:@"FYLearningCoordinator" code:2 userInfo:@{NSLocalizedDescriptionKey:@"请先分析当前句子。"}]); return;
    }
    [receiver.reviewAnalyzer cancelAll];
    FYLearningAnalyzer *reviewer = [FYLearningAnalyzer new];
    reviewer.baseURL = receiver.analyzer.baseURL; reviewer.model = receiver.analyzer.model; reviewer.apiKey = receiver.analyzer.apiKey;
    reviewer.catalog = receiver.catalog; reviewer.transport = receiver.analyzer.transport;
    receiver.reviewAnalyzer = reviewer;
    NSInteger generation = receiver.analysisGeneration;
    NSInteger catalogVersion = receiver.catalog.catalogVersion;
    NSString *modelConfig = [NSString stringWithFormat:@"%@|%@|8|%ld", reviewer.baseURL ?: @"", reviewer.model ?: @"", (long)catalogVersion];
    [reviewer reviewSentence:text translation:translation existingResult:existing completion:^(FYAnalysisResult *result, NSError *error) {
        if (receiver.reviewAnalyzer != reviewer || generation != receiver.analysisGeneration || ![receiver currentMatches:sentenceID version:version]) {
            completion(nil, [NSError errorWithDomain:@"FYLearningCoordinator" code:2 userInfo:@{NSLocalizedDescriptionKey:@"复核已取消或句子已切换。"}]); return;
        }
        if (error) { completion(nil, error); return; }
        result.sentenceID = sentenceID; result.version = version;
        [receiver.store saveAnalysisResult:result sentenceID:sentenceID version:version textHash:FYTextHash(text)
            promptVersion:8 catalogVersion:catalogVersion modelConfig:modelConfig completion:^(NSError *saveError) {
                if (saveError && receiver.persistenceErrorHandler) { receiver.persistenceErrorHandler(saveError); }
            }];
        completion(result, nil);
    }];
}

@end
