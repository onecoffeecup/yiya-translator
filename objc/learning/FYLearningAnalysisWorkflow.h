#pragma once
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "FYLearningCoordinator.h"

@protocol FYLearningAnalysisWorkflowSource <NSObject>
@property(nonatomic) NSInteger analysisGeneration;
@property(nonatomic, strong) FYLearningAnalyzer *analyzer;
@property(nonatomic, strong) FYGrammarCatalog *catalog;
@property(nonatomic, copy, nullable) NSString *currentSentenceID;
@property(nonatomic, copy) NSString *currentSourceText;
@property(nonatomic, copy, nullable) NSString *currentTranslation;
@property(nonatomic) NSInteger currentVersion;
@property(nonatomic, copy, nullable) void (^persistenceErrorHandler)(NSError *error);
@property(nonatomic, strong) FYLearningAnalyzer *reviewAnalyzer;
@property(nonatomic, strong) FYLearningStore *store;
- (BOOL)currentMatches:(NSString *)sentenceID version:(NSInteger)version;
@end

// Sole owner of this workflow state; Source accesses are compatibility forwards.
@interface FYLearningAnalysisWorkflow : NSObject
@property(nonatomic) NSInteger analysisGeneration;
@property(nonatomic, strong) FYLearningAnalyzer *reviewAnalyzer;
- (void)invalidateAnalysisWithReceiver:(id<FYLearningAnalysisWorkflowSource>)receiver;
- (void)analyzeCurrent:(void (^)(FYAnalysisResult *, NSError *))completion receiver:(id<FYLearningAnalysisWorkflowSource>)receiver;
- (void)reviewCurrentAnalysis:(FYAnalysisResult *)existing
                  completion:(void (^)(FYAnalysisResult *, NSError *))completion receiver:(id<FYLearningAnalysisWorkflowSource>)receiver;
@end

#pragma clang diagnostic pop
