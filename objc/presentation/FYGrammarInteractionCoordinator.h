#pragma once
#import <Foundation/Foundation.h>
#import "FYGrammarServiceConfiguration.h"
#import "../FYGrammarActionState.h"
#import "../learning/FYLearningCoordinator.h"
@protocol FYGrammarInteractionStateSource <NSObject>
@property(nonatomic) NSInteger analysisRequestGeneration;
@property(nonatomic) NSInteger followupRequestGeneration;
@property(nonatomic) BOOL learningAnalysisBusy;
@property(nonatomic, copy) NSString *grammarAnalysisError;
@property(nonatomic, strong) FYAnalysisResult *currentAnalysis;
@property(nonatomic, strong) FYGrammarActionState *grammarActions;
@property(nonatomic, strong) FYGrammarActionState *quickGrammarActions;
@end
@protocol FYGrammarInteractionSentenceSource <NSObject>
@property(nonatomic,strong,readonly) FYAnalysisResult *quickSentenceAnalysis;
@property(nonatomic,copy,readonly) NSString *quickSentenceAnalysisSource;
@property(nonatomic,copy,readonly) NSString *quickSentenceSource;
@property(nonatomic,copy,readonly) NSString *quickSentenceTranslation;
@property(nonatomic,copy,readonly) NSString *quickSentenceID;
@property(nonatomic,readonly) NSInteger quickSentenceVersion;
@property(nonatomic,readonly) NSInteger quickSelectedGrammarIndex;
@property(nonatomic,readonly) BOOL quickSentenceAnalyzing;
- (FYGrammarItem *)selectedGrammarItem;
- (BOOL)analysisMatchesCurrentSentence;
@end
@protocol FYGrammarInteractionServices <NSObject>
@property(nonatomic,strong,readonly) FYLearningCoordinator *learningCoordinator;
@property(nonatomic,strong,readonly) FYLearningAnalyzer *learningAnalyzer;
@property(nonatomic,strong,readonly) FYLearningAnalyzer *quickSentenceAnalyzer;
@property(nonatomic,strong,readonly) FYGrammarCatalog *grammarCatalog;
- (FYGrammarServiceConfiguration *)grammarServiceConfiguration;
@end
@protocol FYGrammarInteractionNativeActions <NSObject>
- (void)setAnalyzeBusy:(BOOL)busy;
- (void)setGrammarStatusText:(NSString *)text;
- (void)setGrammarStatusToErrorColor;
- (void)setGrammarDetailNameText:(NSString *)text;
- (void)setGrammarDetailBodyText:(NSString *)text;
- (void)setGrammarFollowupText:(NSString *)text;
- (void)setGrammarQuickAnalysisResult:(FYAnalysisResult *)result;
- (void)applyGrammarTabSelection;
- (void)refreshGrammarResults;
- (void)updateGrammarActionControlsForQuick:(BOOL)quick;
- (void)refreshQuickGrammarActionDetail;
- (void)renderQuickSentence;
- (void)updateGrammarReviewDisplayForQuick:(BOOL)quick preservingPosition:(void (^)(void))updates;
@end
@protocol FYGrammarInteractionPeerActions <NSObject>
- (void)syncCoordinatorToDisplayed;
- (void)clearAnalysisDisplay;
- (void)refreshLearningStatus;
- (void)selectPageAtIndex:(NSInteger)index;
- (void)syncLearningAnalyzerConfig;
@end
@protocol FYGrammarInteractionSource <FYGrammarInteractionStateSource,FYGrammarInteractionSentenceSource,FYGrammarInteractionServices,FYGrammarInteractionNativeActions,FYGrammarInteractionPeerActions>
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick;
- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick;
@end

// Deferred native index read preserves the original gate and argument-evaluation point.
// It is consumed synchronously and is never captured by the asynchronous completion.
typedef NSInteger (^FYGrammarBookmarkIndexProvider)(void);
@protocol FYGrammarBookmarkSource <NSObject>
- (BOOL)analysisMatchesCurrentSentence;
- (FYAnalysisResult *)currentAnalysis;
- (FYGrammarItem *)selectedGrammarItem;
- (FYGrammarBookmark *)bookmarkForCurrentGrammar;
- (FYLearningCoordinator *)learningCoordinator;
- (FYLearningStore *)learningStore;
- (BOOL)grammarBookmarkActionEnabled;
- (void)setGrammarBookmarkActionEnabled:(BOOL)enabled;
- (void)setGrammarStatusText:(NSString *)text;
- (void)refreshGrammarBookmarks:(id)sender;
@end

@interface FYGrammarInteractionCoordinator : NSObject
@property(nonatomic) NSInteger analysisRequestGeneration;
@property(nonatomic) NSInteger followupRequestGeneration;
@property(nonatomic) BOOL learningAnalysisBusy;
@property(nonatomic, copy) NSString *grammarAnalysisError;
@property(nonatomic, strong) FYAnalysisResult *currentAnalysis;
@property(nonatomic, strong) FYGrammarActionState *grammarActions;
@property(nonatomic, strong) FYGrammarActionState *quickGrammarActions;
- (void)analyzeCurrentSentenceWithReceiver:(id<FYGrammarInteractionSource>)receiver;
- (void)requestGrammarFollowupExample:(BOOL)example receiver:(id<FYGrammarInteractionSource>)receiver;
- (void)requestGrammarQuestion:(NSString *)question receiver:(id<FYGrammarInteractionSource>)receiver;
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick receiver:(id<FYGrammarInteractionSource>)receiver;
- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick receiver:(id<FYGrammarInteractionSource>)receiver;
- (void)toggleGrammarExplanationForQuick:(BOOL)quick receiver:(id<FYGrammarInteractionSource>)receiver;
- (void)reviewGrammarSentenceForQuick:(BOOL)quick receiver:(id<FYGrammarInteractionSource>)receiver;

+ (void)bookmarkGrammarItemWithIndexProvider:(FYGrammarBookmarkIndexProvider)indexProvider receiver:(id<FYGrammarBookmarkSource>)receiver;
+ (void)bookmarkSelectedGrammarWithReceiver:(id<FYGrammarBookmarkSource>)receiver;
@end
