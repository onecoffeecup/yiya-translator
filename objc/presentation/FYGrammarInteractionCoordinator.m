#import "FYGrammarInteractionCoordinator.h"
#import "FYPresentationText.h"

@implementation FYGrammarInteractionCoordinator
- (void)analyzeCurrentSentenceWithReceiver:(id<FYGrammarInteractionSource>)receiver {
    [receiver syncCoordinatorToDisplayed];
    if (receiver.learningCoordinator.currentSentenceID.length == 0) {
        [receiver setGrammarStatusText: @"当前没有可分析的句子，请先开始翻译。"];
        return;
    }
    [receiver clearAnalysisDisplay];
    // 分析开始时固定展示的身份，避免分析期间 OCR 换句导致结果串句。
    [receiver.learningCoordinator pinCurrent];
    [receiver refreshLearningStatus];
    NSString *analyzedSentenceID = receiver.learningCoordinator.currentSentenceID;
    NSInteger analyzedVersion = receiver.learningCoordinator.currentVersion;
    NSInteger requestGeneration = ++receiver.analysisRequestGeneration;
    [receiver selectPageAtIndex:0];
    [receiver setAnalyzeBusy:YES];
    [receiver.learningCoordinator analyzeCurrent:^(FYAnalysisResult *result, NSError *error) {
        if (![FYLearningCoordinator requestSentenceID:analyzedSentenceID version:analyzedVersion generation:requestGeneration
            matchesSentenceID:receiver.learningCoordinator.currentSentenceID version:receiver.learningCoordinator.currentVersion generation:receiver.analysisRequestGeneration]) { return; }
        [receiver setAnalyzeBusy:NO];
        if (error) {
            receiver.grammarAnalysisError = error.localizedDescription;
            [receiver setGrammarStatusText: [NSString stringWithFormat:@"分析失败：%@", error.localizedDescription]];
            [receiver setGrammarStatusToErrorColor];
            [receiver setGrammarDetailNameText: @"本次分析未完成"];
            [receiver setGrammarDetailBodyText: @"本次未能取得可核实的语法结果。请检查原句是否识别正确，再点击「分析此句」重试。"];
            [receiver applyGrammarTabSelection];
            return;
        }
        // 结果归属核对：仅当仍是分析时那一句才展示，防止旧分析串到新句。
        if (![FYLearningCoordinator requestSentenceID:result.sentenceID version:result.version generation:requestGeneration
            matchesSentenceID:analyzedSentenceID version:analyzedVersion generation:requestGeneration]) {
            return;
        }
        receiver.currentAnalysis = result;
        [receiver refreshGrammarResults];
    }];
}

- (void)requestGrammarFollowupExample:(BOOL)example receiver:(id<FYGrammarInteractionSource>)receiver {
    FYGrammarItem *item = [receiver selectedGrammarItem];
    if (!item || ![receiver analysisMatchesCurrentSentence]) { [receiver setGrammarFollowupText: @"请先分析当前句子。"]; return; }
    NSInteger generation = ++receiver.followupRequestGeneration;
    NSString *sentenceID = receiver.currentAnalysis.sentenceID;
    NSInteger version = receiver.currentAnalysis.version;
    [receiver setGrammarFollowupText: @"正在生成…"];
    void (^finish)(NSString *, NSError *) = ^(NSString *answer, NSError *error) {
        if (![FYLearningCoordinator followupBelongsToItem:[receiver selectedGrammarItem] requestedItem:item requestGeneration:generation currentGeneration:receiver.followupRequestGeneration
            sentenceID:sentenceID version:version currentSentenceID:receiver.learningCoordinator.currentSentenceID currentVersion:receiver.learningCoordinator.currentVersion]) { return; }
        [receiver setGrammarFollowupText: error ? [NSString stringWithFormat:@"生成失败：%@；可以点击上方按钮重试。", error.localizedDescription] : [NSString stringWithFormat:@"AI 建议\n%@", answer ?: @""]];
    };
    if (example) { [receiver.learningAnalyzer exampleSentenceForGrammar:item sentenceText:receiver.learningCoordinator.currentSourceText translation:receiver.learningCoordinator.currentTranslation completion:finish]; }
    else { [receiver.learningAnalyzer simplerExplanationForGrammar:item sentenceText:receiver.learningCoordinator.currentSourceText translation:receiver.learningCoordinator.currentTranslation completion:finish]; }
}

- (void)requestGrammarQuestion:(NSString *)question receiver:(id<FYGrammarInteractionSource>)receiver {
    FYGrammarItem *item = [receiver selectedGrammarItem];
    if (!item || ![receiver analysisMatchesCurrentSentence]) {
        [receiver setGrammarFollowupText: @"请先分析当前句子，再选择语法点。"]; return;
    }
    NSInteger generation = ++receiver.followupRequestGeneration;
    NSString *sentenceID = receiver.currentAnalysis.sentenceID;
    NSInteger version = receiver.currentAnalysis.version;
    [receiver setGrammarFollowupText: @"正在生成…"];
    [receiver.learningAnalyzer answerQuestion:question grammar:item sentenceText:receiver.learningCoordinator.currentSourceText translation:receiver.learningCoordinator.currentTranslation completion:^(NSString *answer, NSError *error) {
        if (generation != receiver.followupRequestGeneration || item != [receiver selectedGrammarItem] ||
            ![sentenceID isEqualToString:receiver.learningCoordinator.currentSentenceID] || version != receiver.learningCoordinator.currentVersion) { return; }
        [receiver setGrammarFollowupText: error ? [NSString stringWithFormat:@"生成失败：%@；可以重新提问。", error.localizedDescription] : [NSString stringWithFormat:@"AI 建议\n%@", answer ?: @""]];
    }];
}

- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick receiver:(id<FYGrammarInteractionSource>)receiver {
    FYGrammarActionState *state = quick ? receiver.quickGrammarActions : receiver.grammarActions;
    if (!state) {
        state = [FYGrammarActionState new];
        if (quick) { receiver.quickGrammarActions = state; } else { receiver.grammarActions = state; }
    }
    NSString *source = quick ? receiver.quickSentenceSource : receiver.learningCoordinator.currentSourceText;
    NSString *translation = quick ? receiver.quickSentenceTranslation : receiver.learningCoordinator.currentTranslation;
    NSString *sentenceID = quick ? receiver.quickSentenceID : receiver.learningCoordinator.currentSentenceID;
    NSInteger version = quick ? receiver.quickSentenceVersion : receiver.learningCoordinator.currentVersion;
    FYGrammarServiceConfiguration *configuration = [receiver grammarServiceConfiguration];
    NSString *model = configuration.model;
    NSString *base = configuration.baseURL, *key = configuration.apiKey;
    NSArray *identity = @[sentenceID ?: @"", @(version), source ?: @"", translation ?: @"", base, model];
    NSString *context = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:identity options:0 error:NULL] encoding:NSUTF8StringEncoding];
    if (![state.context isEqualToString:context] || ![state.analyzer.apiKey isEqualToString:key]) {
        [state reset]; state.context = context;
    }
    state.analyzer.baseURL = base; state.analyzer.model = model; state.analyzer.apiKey = key;
    state.analyzer.catalog = receiver.grammarCatalog;
    if (!state.analyzer.transport) { state.analyzer.transport = (quick ? receiver.quickSentenceAnalyzer : receiver.learningAnalyzer).transport; }
    return state;
}

- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick receiver:(id<FYGrammarInteractionSource>)receiver {
    if (quick) {
        if (![receiver.quickSentenceSource isEqualToString:receiver.quickSentenceAnalysisSource]) { return nil; }
        return [FYLearningCoordinator grammarItemInList:receiver.quickSentenceAnalysis.grammar index:receiver.quickSelectedGrammarIndex fallbackToFirst:NO];
    }
    return [receiver analysisMatchesCurrentSentence] ? [receiver selectedGrammarItem] : nil;
}

- (void)toggleGrammarExplanationForQuick:(BOOL)quick receiver:(id<FYGrammarInteractionSource>)receiver {
    FYGrammarItem *item = [receiver grammarActionItemForQuick:quick];
    if (!item) { return; }
    FYGrammarActionState *state = [receiver grammarActionsForQuick:quick];
    if ([state.pending containsObject:item]) { return; }
    if (state.expandedItem == item && ![state.errors objectForKey:item]) {
        state.expandedItem = nil;
    } else {
        state.expandedItem = item;
        if (![state.explanations objectForKey:item]) {
            [state.errors removeObjectForKey:item]; [state.pending addObject:item];
            NSInteger generation = state.generation;
            NSString *source = quick ? receiver.quickSentenceSource : receiver.learningCoordinator.currentSourceText;
            NSString *translation = quick ? receiver.quickSentenceTranslation : receiver.learningCoordinator.currentTranslation;
            [state.analyzer expandedExplanationForGrammar:item sentenceText:source translation:translation completion:^(NSString *answer, NSError *error) {
                if (generation != state.generation) { return; }
                if ([receiver grammarActionsForQuick:quick] != state || generation != state.generation) { return; }
                [state.pending removeObject:item];
                if (error || !Trim(answer).length) {
                    [state.errors setObject:[NSString stringWithFormat:@"解释未完成：%@；点击重试。", error.localizedDescription ?: @"返回内容为空"] forKey:item];
                } else { [state.explanations setObject:answer forKey:item]; }
                if (quick) { [receiver refreshQuickGrammarActionDetail]; }
                [receiver updateGrammarActionControlsForQuick:quick];
            }];
        }
    }
    if (quick) { [receiver refreshQuickGrammarActionDetail]; }
    [receiver updateGrammarActionControlsForQuick:quick];
}

- (void)reviewGrammarSentenceForQuick:(BOOL)quick receiver:(id<FYGrammarInteractionSource>)receiver {
    FYAnalysisResult *existing = quick ? receiver.quickSentenceAnalysis : receiver.currentAnalysis;
    if (!existing || (!quick && ![receiver analysisMatchesCurrentSentence]) || (quick && ![receiver.quickSentenceSource isEqualToString:receiver.quickSentenceAnalysisSource])) { return; }
    FYGrammarActionState *state = [receiver grammarActionsForQuick:quick];
    if (state.reviewing || (quick ? receiver.quickSentenceAnalyzing : receiver.learningAnalysisBusy)) { return; }
    state.reviewing = YES; state.reviewStatus = @"正在补查遗漏与疑点，已有解释仍可阅读。";
    NSInteger generation = state.generation;
    [receiver updateGrammarReviewDisplayForQuick:quick preservingPosition:^{
        if (!quick) { [receiver.learningCoordinator pinCurrent]; [receiver refreshLearningStatus]; [receiver setGrammarStatusText: state.reviewStatus]; }
        [receiver updateGrammarActionControlsForQuick:quick];
    }];
    void (^finish)(FYAnalysisResult *, NSError *) = ^(FYAnalysisResult *result, NSError *error) {
        if (generation != state.generation) { return; }
        if ([receiver grammarActionsForQuick:quick] != state || generation != state.generation) { return; }
        state.reviewing = NO;
        [receiver updateGrammarReviewDisplayForQuick:quick preservingPosition:^{
            if (error) { state.reviewStatus = [NSString stringWithFormat:@"复核失败：%@；已有结果已保留，可重试。", error.localizedDescription]; }
            else {
                NSUInteger added = result.grammar.count > existing.grammar.count ? result.grammar.count-existing.grammar.count : 0;
                state.reviewStatus = added ? [NSString stringWithFormat:@"复核完成 · 补充了 %lu 条语法", (unsigned long)added] : @"复核完成 · 本次没有新增语法";
                if (quick) { [receiver setGrammarQuickAnalysisResult:result]; [receiver renderQuickSentence]; }
                else { receiver.currentAnalysis = result; [receiver refreshGrammarResults]; }
            }
            if (!quick) { [receiver setGrammarStatusText: state.reviewStatus]; }
            [receiver updateGrammarActionControlsForQuick:quick];
        }];
    };
    if (quick) {
        [state.analyzer reviewSentence:receiver.quickSentenceSource translation:receiver.quickSentenceTranslation existingResult:existing completion:finish];
    } else { [receiver syncLearningAnalyzerConfig]; [receiver.learningCoordinator reviewCurrentAnalysis:existing completion:finish]; }
}


+ (void)bookmarkGrammarItemWithIndexProvider:(FYGrammarBookmarkIndexProvider)indexProvider receiver:(id<FYGrammarBookmarkSource>)receiver {
    if (![receiver analysisMatchesCurrentSentence]) { return; }
    FYGrammarItem *item = [FYLearningCoordinator grammarItemInList:receiver.currentAnalysis.grammar index:indexProvider() fallbackToFirst:NO];
    if (!item) { return; }
    [receiver.learningCoordinator bookmarkGrammar:item completion:^(NSError *error) {
        if (error) {
            [receiver setGrammarStatusText:[NSString stringWithFormat:@"收藏失败：%@", error.localizedDescription]];
        } else {
            [receiver setGrammarStatusText:[NSString stringWithFormat:@"已收藏语法「%@」。", item.name]];
            [receiver refreshGrammarBookmarks:nil];
        }
    }];
}

+ (void)bookmarkSelectedGrammarWithReceiver:(id<FYGrammarBookmarkSource>)receiver {
    if (![receiver analysisMatchesCurrentSentence] || ![receiver selectedGrammarItem] || !receiver.grammarBookmarkActionEnabled) { return; }
    FYGrammarItem *item = [receiver selectedGrammarItem];
    FYGrammarBookmark *existing = [receiver bookmarkForCurrentGrammar];
    [receiver setGrammarBookmarkActionEnabled:NO];
    void (^finish)(NSError *) = ^(NSError *error) {
        if (item != [receiver selectedGrammarItem] || ![receiver analysisMatchesCurrentSentence]) { [receiver refreshGrammarBookmarks:nil]; return; }
        [receiver setGrammarBookmarkActionEnabled:YES];
        [receiver setGrammarStatusText:error ? [NSString stringWithFormat:@"收藏操作失败：%@", error.localizedDescription] : (existing ? @"已取消语法收藏。" : @"语法与原句已收藏。")];
        [receiver refreshGrammarBookmarks:nil];
    };
    if (existing) { [receiver.learningStore deleteGrammarBookmark:existing.bookmarkID completion:finish]; }
    else { [receiver.learningCoordinator bookmarkGrammar:item completion:finish]; }
}
@end
