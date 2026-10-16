#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "FYInlineBlockSnapshot.h"
#import "../learning/FYLearningCoordinator.h"
#import "../learning/FYStudyChatSession.h"

@protocol FYStudyNavigationStateSource <NSObject>
@property(nonatomic, strong) FYInlineBlockSnapshot * inlineBlockSnapshot;
@property(nonatomic, strong) FYInlineBlockSnapshot * inlineReturnSnapshot;
@property(nonatomic, copy) NSString * inlineReturnSourceText;
@property(nonatomic, copy) NSString * quickSentenceID;
@property(nonatomic, copy) NSString * quickSentenceSource;
@property(nonatomic, copy) NSString * quickSentenceTranslation;
@property(nonatomic) NSInteger quickSentenceVersion;
@property(nonatomic) BOOL quickSentenceRequested;
@property(nonatomic) NSInteger quickSentenceGeneration;
@property(nonatomic) BOOL quickSentenceIsInlineBlock;
@property(nonatomic) BOOL studyChatOverlayRequested;
@property(nonatomic) NSInteger quickSelectedGrammarIndex;
@end

@protocol FYStudyNavigationPresentationSource <FYStudyNavigationStateSource>
@property(nonatomic,strong) FYAnalysisResult *quickSentenceAnalysis;
@property(nonatomic,copy) NSString *quickSentenceAnalysisError;
@property(nonatomic,copy) NSString *quickSentenceAnalysisSource;
@property(nonatomic,copy) NSString *quickSentenceAnalysisTranslation;
- (BOOL)quickSentenceAnalyzing;
- (BOOL)selectingCaptureRegion;
- (BOOL)translationTargetIsForeground;
- (FYLearningCoordinator *)learningCoordinator;
- (void)cancelQuickSentenceAnalysis;
- (void)renderQuickSentence;
- (void)refreshSavedSentences;
- (void)analyzeQuickSentence:(id)sender;
- (void)hideStudyChatPanel;
- (BOOL)hasQuickSentencePanel;
- (void)centerQuickSentencePanel;
- (void)focusQuickSentencePanel;
@end

@protocol FYStudyQuickNavigationSource <FYStudyNavigationPresentationSource>
@property(nonatomic) NSInteger chatContextGeneration;
@property(nonatomic) BOOL chatResolvingSource;
- (FYStudyChatSession *)studyChatSession;
- (FYAnalysisResult *)currentAnalysis;
- (BOOL)analysisMatchesCurrentSentence;
- (void)captureQuickSentenceScrollPosition;
- (void)showStudyChatOverlay:(id)sender;
- (void)resolveLatestStudyIdentity:(void (^)(FYRequestIdentity *))completion;
@end

@protocol FYStudyInlineNavigationSource <FYStudyNavigationPresentationSource>
@property(nonatomic) CGFloat quickSentenceScrollOffset;
- (void)bindInlineStudyChatToSource:(NSString *)source translation:(NSString *)translation;
- (void)restoreQuickSentenceScrollPosition;
@end

@protocol FYStudyInlineTextSource <NSObject>
- (BOOL)captureCardInputEnabled;
- (NSUInteger)studyInlineInputEpoch;
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot;
@end

@protocol FYStudyChatBindingSource <NSObject>
- (void)ensureStudyChatSession;
- (FYStudyChatSession *)studyChatSession;
- (void)clearStudyChatDrafts;
- (void)refreshStudyChatViews;
@end

@protocol FYStudyWorkspaceNavigationSource <FYStudyNavigationStateSource>
@property(nonatomic) NSInteger analysisRequestGeneration;
@property(nonatomic,strong) FYAnalysisResult *currentAnalysis;
@property(nonatomic) NSInteger selectedGrammarIndex;
- (NSString *)quickSentenceAnalysisSource;
- (FYAnalysisResult *)quickSentenceAnalysis;
- (FYLearningCoordinator *)learningCoordinator;
- (void)activateStudyWorkspace;
- (void)closeStudyOverlay:(id)sender;
- (void)clearAnalysisDisplay;
- (void)refreshLearningSource;
- (void)refreshLearningStatus;
- (void)setAnalyzeBusy:(BOOL)busy;
- (void)refreshGrammarResults;
- (void)analyzeCurrentSentence:(id)sender;
@end

// Owns only original navigation state. Views, analysis and chat tasks keep their owners.
@interface FYStudyNavigationCoordinator : NSObject
@property(nonatomic, strong) FYInlineBlockSnapshot * inlineBlockSnapshot;
@property(nonatomic, strong) FYInlineBlockSnapshot * inlineReturnSnapshot;
@property(nonatomic, copy) NSString * inlineReturnSourceText;
@property(nonatomic, copy) NSString * quickSentenceID;
@property(nonatomic, copy) NSString * quickSentenceSource;
@property(nonatomic, copy) NSString * quickSentenceTranslation;
@property(nonatomic) NSInteger quickSentenceVersion;
@property(nonatomic) BOOL quickSentenceRequested;
@property(nonatomic) NSInteger quickSentenceGeneration;
@property(nonatomic) BOOL quickSentenceIsInlineBlock;
@property(nonatomic) BOOL studyChatOverlayRequested;
@property(nonatomic) NSInteger quickSelectedGrammarIndex;
- (void)askQuickSentence:(id)sender receiver:(id<FYStudyQuickNavigationSource>)receiver;
- (void)showQuickSentenceWithReceiver:(id<FYStudyQuickNavigationSource>)receiver;
- (void)openWorkspaceWithReceiver:(id<FYStudyWorkspaceNavigationSource>)receiver;
- (void)openInlineText:(NSString *)source translation:(NSString *)translation receiver:(id<FYStudyInlineTextSource>)receiver;
- (void)openInlineSnapshot:(FYInlineBlockSnapshot *)snapshot receiver:(id<FYStudyInlineNavigationSource>)receiver;
- (void)bindInlineChatToSource:(NSString *)source translation:(NSString *)translation receiver:(id<FYStudyChatBindingSource>)receiver;
- (void)returnFromChatWithReceiver:(id<FYStudyInlineNavigationSource>)receiver;
@end
