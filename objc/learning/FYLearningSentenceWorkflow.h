#pragma once
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "FYLearningCoordinator.h"

@protocol FYLearningSentenceWorkflowSource <NSObject>
@property(nonatomic, copy, nullable) NSString *currentSentenceID;
@property(nonatomic, copy) NSString *currentSourceText;
@property(nonatomic, copy, nullable) NSString *currentTranslation;
@property(nonatomic) NSInteger currentVersion;
@property(nonatomic) BOOL isPinned;
@property(nonatomic) BOOL japaneseMode;
@property(nonatomic, copy, nullable) NSSet<NSString *> *lastDialogueExcludedSpeakerKeys;
@property(nonatomic, strong, nullable) FYRequestIdentity *lastDialogueIdentity;
@property(nonatomic, copy, nullable) NSString *lastDialogueKey;
@property(nonatomic, strong, nullable) FYRequestIdentity *lastIdentity;
@property(nonatomic, copy) NSArray<FYRequestIdentity *> *lastItemIdentities;
@property(nonatomic) FYSentenceKind lastItemKind;
@property(nonatomic, copy) NSArray<NSString *> *lastItemTexts;
@property(nonatomic) FYSentenceKind lastKind;
@property(nonatomic, copy, nullable) NSString *lastText;
@property(nonatomic, copy, nullable) NSString *latestSentenceID;
@property(nonatomic) BOOL learningEnabled;
@property(nonatomic, copy, nullable) void (^persistenceErrorHandler)(NSError *error);
@property(nonatomic) NSUInteger recordsSinceLastDialogue;
@property(nonatomic) NSInteger selectionGeneration;
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic, strong) FYLearningStore *store;
- (void)ensureSession;
- (FYRequestIdentity *)recordSingleText:(NSString *)rawText kind:(FYSentenceKind)kind;
- (FYRequestIdentity *)recordText:(NSString *)text kind:(FYSentenceKind)kind;
- (void)invalidateAnalysis;
- (BOOL)currentMatches:(NSString *)sentenceID version:(NSInteger)version;
- (void)preserveHistorySentence:(NSString *)sentenceID;
- (void)followLatestWithCompletion:(void (^)(void))completion;
- (void)correctCurrentSentenceText:(NSString *)newText completion:(void (^)(NSError *))completion;
- (void)correctCurrentSentenceText:(NSString *)newText;
@end

// Sole owner of this workflow state; Source accesses are compatibility forwards.
@interface FYLearningSentenceWorkflow : NSObject
@property(nonatomic) BOOL learningEnabled;
@property(nonatomic) BOOL japaneseMode;
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic, copy, nullable) NSString *lastText;
@property(nonatomic) FYSentenceKind lastKind;
@property(nonatomic, strong, nullable) FYRequestIdentity *lastIdentity;
@property(nonatomic, copy, nullable) NSString *lastDialogueKey;
@property(nonatomic, strong, nullable) FYRequestIdentity *lastDialogueIdentity;
@property(nonatomic, copy, nullable) NSSet<NSString *> *lastDialogueExcludedSpeakerKeys;
@property(nonatomic) NSUInteger recordsSinceLastDialogue;
@property(nonatomic, copy) NSArray<NSString *> *lastItemTexts;
@property(nonatomic, copy) NSArray<FYRequestIdentity *> *lastItemIdentities;
@property(nonatomic) FYSentenceKind lastItemKind;
@property(nonatomic) BOOL isPinned;
@property(nonatomic, copy, nullable) NSString *currentSentenceID;
@property(nonatomic) NSInteger currentVersion;
@property(nonatomic, copy) NSString *currentSourceText;
@property(nonatomic, copy, nullable) NSString *currentTranslation;
@property(nonatomic, copy, nullable) NSString *latestSentenceID;
@property(nonatomic) NSInteger selectionGeneration;
- (BOOL)hasNewerSentenceWithReceiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (void)ensureSessionWithReceiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (FYRequestIdentity *)recordSingleText:(NSString *)rawText kind:(FYSentenceKind)kind receiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (FYRequestIdentity *)recordDialogueText:(NSString *)text excludingSpeakerLabels:(NSArray<NSString *> *)labels receiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (FYRequestIdentity *)recordText:(NSString *)text kind:(FYSentenceKind)kind receiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (NSArray<FYRequestIdentity *> *)recordItems:(NSArray<NSString *> *)texts kind:(FYSentenceKind)kind receiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (void)setTranslation:(NSString *)translation forIdentity:(FYRequestIdentity *)identity receiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (BOOL)currentMatches:(NSString *)sentenceID version:(NSInteger)version receiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (void)preserveHistorySentence:(NSString *)sentenceID receiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (void)pinCurrentWithReceiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (void)followLatestWithCompletion:(void (^)(void))completion receiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (void)followLatestWithReceiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (void)selectHistorySentence:(FYSentenceRecord *)record receiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (void)selectSentenceID:(NSString *)sentenceID
                 version:(NSInteger)version
              sourceText:(NSString *)sourceText
             translation:(NSString *)translation receiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (void)correctCurrentSentenceText:(NSString *)newText completion:(void (^)(NSError *))completion receiver:(id<FYLearningSentenceWorkflowSource>)receiver;
- (void)correctCurrentSentenceText:(NSString *)newText receiver:(id<FYLearningSentenceWorkflowSource>)receiver;
@end

#pragma clang diagnostic pop
