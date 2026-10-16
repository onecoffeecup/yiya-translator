#pragma once
#import <Foundation/Foundation.h>
#import "../learning/FYLearningCoordinator.h"
#import "../learning/FYStudyChatSession.h"

// Values, existing services and purpose-specific native actions; no view dependency.
@protocol FYStudyChatContextSource <NSObject>
@property(nonatomic) NSInteger chatContextGeneration;
@property(nonatomic) BOOL chatResolvingSource;
- (FYStudyChatSession *)studyChatSession;
- (FYLearningCoordinator *)learningCoordinator;
- (FYLearningStore *)learningStore;
- (BOOL)running;
- (uint32_t)selectedWindowID;
- (BOOL)studyChatUsesDialogueMode;
- (NSInteger)studyChatLanguageSegment;
- (NSString *)studyChatFallbackSource;
- (NSString *)studyChatFallbackTranslation;
- (void)ensureStudyChatSession;
- (void)clearStudyChatReturnSnapshot;
- (void)configureStudyChatAnalyzer:(FYLearningAnalyzer *)analyzer;
- (void)restoreStudyChatDraftText:(NSString *)text;
- (void)refreshStudyChatViews;
- (void)showError:(NSString *)error;
- (void)captureLatestStudySentenceWithCompletion:(void (^)(NSString *,NSError *))completion;
- (void)resolveLatestStudyIdentity:(void (^)(FYRequestIdentity *))completion;
- (void)resolveLatestStudySentence:(void (^)(NSString *,NSString *))completion;
@end

// Owns only context resolution state. The existing session owns network cancellation.
@interface FYStudyChatContextCoordinator : NSObject
@property(nonatomic) NSInteger chatContextGeneration;
@property(nonatomic) BOOL chatResolvingSource;
- (void)referenceLatestWithReceiver:(id<FYStudyChatContextSource>)receiver;
- (void)resolveLatestIdentity:(void (^)(FYRequestIdentity *))completion receiver:(id<FYStudyChatContextSource>)receiver;
- (void)resolveLatestSentence:(void (^)(NSString *,NSString *))completion receiver:(id<FYStudyChatContextSource>)receiver;
- (void)send:(NSString *)text receiver:(id<FYStudyChatContextSource>)receiver;
@end
