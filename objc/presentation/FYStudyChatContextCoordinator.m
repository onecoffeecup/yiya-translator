#import "FYStudyChatContextCoordinator.h"

@implementation FYStudyChatContextCoordinator
- (void)referenceLatestWithReceiver:(id<FYStudyChatContextSource>)receiver {
    [receiver ensureStudyChatSession];
    NSInteger generation=++receiver.chatContextGeneration;
    receiver.chatResolvingSource=YES;
    [receiver.studyChatSession startNewConversationWithSource:@"" translation:@""];
    // 引用最新句是显式重新识别，作废旧返回关系，避免返回入口指向旧块。
    [receiver clearStudyChatReturnSnapshot];
    [receiver resolveLatestStudySentence:^(NSString *source,NSString *translation){
        if(generation!=receiver.chatContextGeneration){return;}
        receiver.chatResolvingSource=NO;
        [receiver.studyChatSession referenceSource:source translation:translation];
    }];
}

- (void)resolveLatestIdentity:(void (^)(FYRequestIdentity *))completion receiver:(id<FYStudyChatContextSource>)receiver {
    NSString *latest=receiver.learningCoordinator.latestSentenceID;
    if(latest.length && ![latest isEqualToString:receiver.learningCoordinator.currentSentenceID]){
        [receiver.learningStore fetchSentence:latest completion:^(FYSentenceRecord *record,NSError *error){
            completion(record?[FYRequestIdentity identityWithSentenceID:record.sentenceID version:record.latestVersion requestID:NSUUID.UUID.UUIDString sourceText:record.latestText translation:record.latestTranslation]:nil);
        }];
    }else if(receiver.learningCoordinator.currentSentenceID.length){
        completion([FYRequestIdentity identityWithSentenceID:receiver.learningCoordinator.currentSentenceID version:receiver.learningCoordinator.currentVersion requestID:NSUUID.UUID.UUIDString sourceText:receiver.learningCoordinator.currentSourceText translation:receiver.learningCoordinator.currentTranslation]);
    }else{completion(nil);}
}

- (void)resolveLatestSentence:(void (^)(NSString *,NSString *))completion receiver:(id<FYStudyChatContextSource>)receiver {
    // The preview can already show the next line while the regular OCR cycle
    // is waiting for stability or translating the previous line. Capture at
    // the user's click, independently of that cycle and the pinned reader.
    if(receiver.running && [receiver selectedWindowID]){
        [receiver captureLatestStudySentenceWithCompletion:^(NSString *source,NSError *error){
            if(error){[receiver showError:error.localizedDescription];completion(@"",@"");return;}
            [receiver resolveLatestStudyIdentity:^(FYRequestIdentity *identity){
                BOOL sameSource=identity.sourceText.length && [FYDialogueComparisonKey(source) isEqualToString:FYDialogueComparisonKey(identity.sourceText)];
                BOOL anchoredFragment=[receiver studyChatUsesDialogueMode] && [receiver studyChatLanguageSegment]==0 &&
                    identity.sourceText.length && FYDialogueIsSpeakerAnchoredFragment(source,identity.sourceText);
                NSString *resolvedSource=anchoredFragment?identity.sourceText:source;
                NSString *translation=(sameSource || anchoredFragment)?identity.translation:@"";
                completion(resolvedSource,translation ?: @"");
            }];
        }];
        return;
    }
    [receiver resolveLatestStudyIdentity:^(FYRequestIdentity *identity){
        completion(identity.sourceText ?: [receiver studyChatFallbackSource] ?: @"",identity?identity.translation ?: @"":[receiver studyChatFallbackTranslation] ?: @"");
    }];
}

- (void)send:(NSString *)text receiver:(id<FYStudyChatContextSource>)receiver {
    [receiver ensureStudyChatSession];
    if(receiver.chatResolvingSource || receiver.studyChatSession.sending){return;}
    FYLearningAnalyzer *analyzer=receiver.studyChatSession.analyzer;
    [receiver configureStudyChatAnalyzer:analyzer];
    if(receiver.studyChatSession.source.length){[receiver.studyChatSession send:text];return;}
    receiver.chatResolvingSource=YES;[receiver refreshStudyChatViews];
    NSInteger generation=receiver.chatContextGeneration;
    [receiver resolveLatestStudySentence:^(NSString *source,NSString *translation){
        if(generation!=receiver.chatContextGeneration){
            [receiver refreshStudyChatViews];
            [receiver restoreStudyChatDraftText:text];return;
        }
        receiver.chatResolvingSource=NO;
        [receiver.studyChatSession referenceSource:source translation:translation];
        [receiver.studyChatSession send:text];[receiver refreshStudyChatViews];
    }];
}
@end
