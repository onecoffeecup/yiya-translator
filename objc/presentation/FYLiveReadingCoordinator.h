#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "FYDisplayedSentenceState.h"
#import "../learning/FYLearningCoordinator.h"
@protocol FYLiveReadingStateSource <NSObject>
@property(nonatomic,copy) NSString *displayedSentenceID;
@property(nonatomic,copy) NSString *displayedSourceText;
@property(nonatomic,copy,nullable) NSString *displayedTranslation;
@property(nonatomic) NSInteger displayedVersion;
@property(nonatomic) NSInteger vocabSelectionGeneration;
@property(nonatomic,readonly) BOOL sourceHoverSuspended;
@property(nonatomic,strong,readonly) FYAnalysisResult *currentAnalysis;
@end
@protocol FYLiveReadingServices <NSObject>
@property(nonatomic,strong,readonly) FYLearningCoordinator *learningCoordinator;
@property(nonatomic,readonly) BOOL learningAnalysisBusy;
@end
@protocol FYLiveReadingTextSource <NSObject>
- (NSString *)currentLiveSourceText;
- (NSString *)currentLiveGrammarSourceText;
@end
@protocol FYLiveReadingNativeActions <NSObject>
- (void)setWordPickHidden:(BOOL)hidden;
- (void)setLiveSourceReadingText:(NSString *)text;
- (void)setLiveGrammarSourceText:(NSString *)text;
- (void)setLiveSourceEmptyHidden:(BOOL)hidden;
- (void)setLiveSourceScrollHidden:(BOOL)hidden;
- (void)setLiveSourceHintHidden:(BOOL)hidden;
- (void)setLiveSourceMinimumHeight:(CGFloat)height;
- (void)setLiveTranslationMinimumHeight:(CGFloat)height;
- (void)setLiveTranslationReadingText:(NSString *)text;
- (void)setLiveTranslationWaitingHint:(NSString *)text;
- (void)layoutLiveReadingWindow;
- (void)updateLiveSourceReadingHeight;
- (void)refreshLiveDialoguePresentation:(NSString *)source;
- (void)setLiveGrammarTranslationHint:(NSString *)text;
@end
@protocol FYLiveReadingPeerActions <NSObject>
- (void)refreshHistory;
- (void)clearAnalysisDisplay;
- (void)liveHostRefreshLearningStatus;
- (void)refreshSourceHoverTips;
@end
@protocol FYLiveReadingSource <FYLiveReadingStateSource,FYLiveReadingServices,FYLiveReadingTextSource,FYLiveReadingNativeActions,FYLiveReadingPeerActions>
@end
@interface FYLiveReadingCoordinator : NSObject
- (void)refreshLearningSourceWithReceiver:(id<FYLiveReadingSource>)receiver;
- (nullable NSString *)currentSentenceLevelTagWithReceiver:(id<FYLiveReadingStateSource>)receiver;
@end
