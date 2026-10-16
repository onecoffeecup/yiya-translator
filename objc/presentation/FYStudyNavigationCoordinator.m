#import "FYStudyNavigationCoordinator.h"
#import "FYPresentationText.h"

@implementation FYStudyNavigationCoordinator
- (void)askQuickSentence:(id)sender receiver:(id<FYStudyQuickNavigationSource>)receiver {
    ++receiver.chatContextGeneration;
    receiver.chatResolvingSource=NO;
    // 进入 AI 前保存语法卡滚动位置，返回时恢复。
    [receiver captureQuickSentenceScrollPosition];
    NSString *source=receiver.quickSentenceSource ?: @"";
    NSString *translation=receiver.quickSentenceTranslation ?: @"";
    // 同一快照往返只切换显示：不重新引用、不取消正在生成的回答。
    BOOL sameSource=[source isEqualToString:receiver.studyChatSession.source ?: @""] &&
                    [translation isEqualToString:receiver.studyChatSession.translation ?: @""];
    if(!sameSource){[receiver.studyChatSession referenceSource:source translation:translation];}
    [receiver showStudyChatOverlay:sender];
}

- (void)showQuickSentenceWithReceiver:(id<FYStudyQuickNavigationSource>)receiver {
    if(![receiver translationTargetIsForeground]){return;}
    // 对白查句走旧语义（标题/操作），清除贴译块标记。
    receiver.quickSentenceIsInlineBlock=NO;
    receiver.quickSentenceRequested=YES;NSInteger generation=++receiver.quickSentenceGeneration;
    [receiver resolveLatestStudyIdentity:^(FYRequestIdentity *identity){
        NSString *source=identity.sourceText ?: @"";NSString *translation=identity.translation ?: @"";
        if(!receiver.quickSentenceRequested || generation!=receiver.quickSentenceGeneration){return;}
        BOOL same=[source isEqualToString:receiver.quickSentenceAnalysisSource] &&
            [(translation ?: @"") isEqualToString:receiver.quickSentenceAnalysisTranslation];
        if(!same){[receiver cancelQuickSentenceAnalysis];receiver.quickSentenceAnalysis=nil;receiver.quickSentenceAnalysisError=nil;receiver.quickSelectedGrammarIndex=0;}
        receiver.quickSentenceSource=source;receiver.quickSentenceTranslation=translation;
        receiver.quickSentenceID=identity.sentenceID;receiver.quickSentenceVersion=identity.version;
        if(!receiver.quickSentenceAnalysis && !receiver.quickSentenceAnalyzing && [receiver analysisMatchesCurrentSentence] &&
           [source isEqualToString:receiver.learningCoordinator.currentSourceText] &&
           [(translation ?: @"") isEqualToString:(receiver.learningCoordinator.currentTranslation ?: @"")]){
            receiver.quickSentenceAnalysis=receiver.currentAnalysis;
            receiver.quickSentenceAnalysisSource=source;receiver.quickSentenceAnalysisTranslation=translation ?: @"";
        }
        receiver.studyChatOverlayRequested=NO;[receiver hideStudyChatPanel];
        BOOL firstPresentation=![receiver hasQuickSentencePanel];
        [receiver renderQuickSentence];[receiver refreshSavedSentences];if(firstPresentation){[receiver centerQuickSentencePanel];}
        if(!receiver.selectingCaptureRegion && [receiver translationTargetIsForeground]){[receiver focusQuickSentencePanel];}
        if(!receiver.quickSentenceAnalysis && !receiver.quickSentenceAnalyzing){[receiver analyzeQuickSentence:nil];}
    }];
}

- (void)openWorkspaceWithReceiver:(id<FYStudyWorkspaceNavigationSource>)receiver {
    [receiver activateStudyWorkspace];
    // Carry the exact displayed version, rather than whichever sentence OCR sees now.
    NSString *sentenceID=receiver.quickSentenceID;NSInteger version=receiver.quickSentenceVersion;
    NSString *source=receiver.quickSentenceSource;NSString *translation=receiver.quickSentenceTranslation;
    FYAnalysisResult *quickResult=[source isEqualToString:receiver.quickSentenceAnalysisSource]?receiver.quickSentenceAnalysis:nil;
    [receiver closeStudyOverlay:nil];
    if(!sentenceID.length || !source.length){return;}
    receiver.analysisRequestGeneration++;
    [receiver.learningCoordinator selectSentenceID:sentenceID version:version sourceText:source translation:translation];
    [receiver clearAnalysisDisplay];[receiver refreshLearningSource];[receiver refreshLearningStatus];
    if(quickResult){
        FYAnalysisResult *result=[FYAnalysisResult new];result.schemaVersion=quickResult.schemaVersion;
        result.grammar=quickResult.grammar;result.vocabulary=quickResult.vocabulary;result.sentenceNote=quickResult.sentenceNote;result.structureParts=quickResult.structureParts;result.structureTitle=quickResult.structureTitle;
        result.sentenceID=sentenceID;result.version=version;result.status=FYAnalysisStatusSuccess;
        receiver.currentAnalysis=result;receiver.selectedGrammarIndex=receiver.quickSelectedGrammarIndex;[receiver setAnalyzeBusy:NO];[receiver refreshGrammarResults];
    }else{[receiver analyzeCurrentSentence:nil];}
}

- (void)openInlineText:(NSString *)source translation:(NSString *)translation receiver:(id<FYStudyInlineTextSource>)receiver {
    NSString *src = Trim(source);
    if (src.length < 2) { return; }
    FYInlineBlockSnapshot *snapshot = [FYInlineBlockSnapshot new];
    snapshot.sourceText = src;
    snapshot.translation = translation ?: @"";
    // 没有原始行框时，至少按真实分行保留行结构（几何为按行的高度的近似，不是伪造内容）。
    NSMutableArray<NSValue *> *lineBoxes = [NSMutableArray array];
    NSArray<NSString *> *lines = [src componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSUInteger kept = 0;
    for (NSString *line in lines) {
        if (Trim(line).length == 0) { continue; }
        [lineBoxes addObject:[NSValue valueWithRect:CGRectMake(0, MAX(0.0, 0.9 - kept * 0.05), 1, 0.05)]];
        kept += 1;
    }
    snapshot.lineBoxes = lineBoxes;
    snapshot.inputSource = [receiver captureCardInputEnabled] ? 1 : 0;
    snapshot.inputEpoch = [receiver studyInlineInputEpoch];
    snapshot.blockID = NormalizeForComparison(src);
    [receiver openInlineLearningWithSnapshot:snapshot];
}

- (void)openInlineSnapshot:(FYInlineBlockSnapshot *)snapshot receiver:(id<FYStudyInlineNavigationSource>)receiver {
    if (!snapshot || snapshot.sourceText.length < 2) { return; }
    NSString *src = Trim(snapshot.sourceText);
    NSString *translation = snapshot.translation ?: @"";
    BOOL sameBlock = receiver.inlineBlockSnapshot != nil && [receiver.inlineBlockSnapshot.blockID isEqualToString:snapshot.blockID];
    // 记录 Snapshot 类型句子以获得真实 ID/version 供「收藏语法／收藏这段」绑定；
    // 同一界面文字在历史中折叠，不写进对白。
    if (snapshot.sentenceID.length == 0) {
        FYRequestIdentity *identity = [receiver.learningCoordinator recordText:src kind:FYSentenceKindSnapshot];
        snapshot.sentenceID = identity.sentenceID ?: @"";
        snapshot.version = identity.version;
    }
    snapshot.sourceText = src;
    snapshot.translation = translation;
    receiver.inlineBlockSnapshot = snapshot;
    receiver.inlineReturnSnapshot = snapshot;
    receiver.inlineReturnSourceText = src;
    receiver.quickSentenceIsInlineBlock = YES;

    receiver.quickSentenceRequested = YES;
    receiver.quickSentenceGeneration += 1;
    receiver.studyChatOverlayRequested = NO;
    [receiver hideStudyChatPanel];
    receiver.quickSentenceSource = src;
    receiver.quickSentenceTranslation = translation;
    receiver.quickSentenceID = snapshot.sentenceID;
    receiver.quickSentenceVersion = snapshot.version;
    if (!sameBlock) {
        // 换成另一块：清掉上一块的分析、选中项、聊天与草稿，避免串块。
        [receiver cancelQuickSentenceAnalysis];
        receiver.quickSentenceAnalysis = nil;
        receiver.quickSentenceAnalysisError = nil;
        receiver.quickSelectedGrammarIndex = 0;
        receiver.quickSentenceAnalysisSource = @"";
        receiver.quickSentenceAnalysisTranslation = @"";
        [receiver bindInlineStudyChatToSource:src translation:translation];
        receiver.quickSentenceScrollOffset = 0;
    }
    BOOL first = ![receiver hasQuickSentencePanel];
    [receiver renderQuickSentence];
    [receiver refreshSavedSentences];
    if (first) { [receiver centerQuickSentencePanel]; }
    if (!receiver.selectingCaptureRegion && [receiver translationTargetIsForeground]) {
        [receiver focusQuickSentencePanel];
    }
    if (!receiver.quickSentenceAnalysis && !receiver.quickSentenceAnalyzing) { [receiver analyzeQuickSentence:nil]; }
}

- (void)bindInlineChatToSource:(NSString *)source translation:(NSString *)translation receiver:(id<FYStudyChatBindingSource>)receiver {
    [receiver ensureStudyChatSession];
    [receiver.studyChatSession startNewConversationWithSource:source translation:translation];
    [receiver clearStudyChatDrafts];
    [receiver refreshStudyChatViews];
}

- (void)returnFromChatWithReceiver:(id<FYStudyInlineNavigationSource>)receiver {
    FYInlineBlockSnapshot *snapshot = receiver.inlineReturnSnapshot;
    if (!snapshot || snapshot.sourceText.length == 0) { return; }
    receiver.studyChatOverlayRequested = NO;
    [receiver hideStudyChatPanel];
    receiver.quickSentenceRequested = YES;
    BOOL sameBlock = receiver.inlineBlockSnapshot != nil && [receiver.inlineBlockSnapshot.blockID isEqualToString:snapshot.blockID] &&
                     [snapshot.sourceText isEqualToString:receiver.quickSentenceAnalysisSource];
    receiver.quickSentenceSource = snapshot.sourceText;
    receiver.quickSentenceTranslation = snapshot.translation ?: @"";
    receiver.quickSentenceID = snapshot.sentenceID ?: @"";
    receiver.quickSentenceVersion = snapshot.version;
    if (!sameBlock) {
        receiver.quickSentenceAnalysis = nil;
        receiver.quickSentenceAnalysisError = nil;
        receiver.quickSelectedGrammarIndex = 0;
    }
    [receiver renderQuickSentence];
    [receiver restoreQuickSentenceScrollPosition];
    if (!receiver.selectingCaptureRegion && [receiver translationTargetIsForeground]) {
        [receiver focusQuickSentencePanel];
    }
    if (!receiver.quickSentenceAnalysis && !receiver.quickSentenceAnalyzing) {
        [receiver analyzeQuickSentence:nil];
    }
}
@end
