#import "FYLiveReadingCoordinator.h"

@implementation FYLiveReadingCoordinator
- (void)refreshLearningSourceWithReceiver:(id<FYLiveReadingSource>)receiver {
    [receiver refreshHistory];
    NSString *source = receiver.learningCoordinator.currentSourceText ?: @"";
    NSString *translation = receiver.learningCoordinator.currentTranslation;
    BOOL changed = ![receiver.displayedSentenceID ?: @"" isEqualToString:receiver.learningCoordinator.currentSentenceID ?: @""] || receiver.displayedVersion != receiver.learningCoordinator.currentVersion;
    if (changed) {
        [receiver clearAnalysisDisplay];
        receiver.vocabSelectionGeneration += 1;
        [receiver setWordPickHidden:YES];
    }
    receiver.displayedSentenceID = receiver.learningCoordinator.currentSentenceID;
    receiver.displayedVersion = receiver.learningCoordinator.currentVersion;
    receiver.displayedSourceText = source;
    receiver.displayedTranslation = translation;
    BOOL sourceChanged=![[receiver currentLiveSourceText] isEqualToString:source];
    if (sourceChanged) { [receiver setLiveSourceReadingText:source]; }
    if (![[receiver currentLiveGrammarSourceText] isEqualToString:source]) { [receiver setLiveGrammarSourceText:source]; }
    BOOL hasSource = source.length > 0;
    [receiver setLiveSourceEmptyHidden:hasSource];
    [receiver setLiveSourceScrollHidden:!hasSource];
    [receiver setLiveSourceHintHidden:!hasSource];
    [receiver setLiveSourceMinimumHeight:hasSource ? 156 : 104];
    [receiver setLiveTranslationMinimumHeight:(hasSource || translation.length) ? 156 : 104];
    if (translation.length) {
        [receiver setLiveTranslationReadingText:translation];
    } else {
        NSString *hint = hasSource ? @"等待该句译文" : @"开始翻译后，译文会显示在这里。";
        [receiver setLiveTranslationWaitingHint:hint];
    }
    [receiver layoutLiveReadingWindow];
    [receiver updateLiveSourceReadingHeight];
    [receiver refreshLiveDialoguePresentation:source];
    [receiver setLiveGrammarTranslationHint:translation.length ? translation : (source.length ? @"暂无该句译文" : @"还没有选择要分析的句子。")];
    [receiver liveHostRefreshLearningStatus];
    if(changed || sourceChanged || receiver.sourceHoverSuspended){[receiver refreshSourceHoverTips];}
}

- (nullable NSString *)currentSentenceLevelTagWithReceiver:(id<FYLiveReadingStateSource>)receiver {
    for (FYGrammarItem *item in receiver.currentAnalysis.grammar) {
        if (item.referenceLevel.length > 0) { return item.referenceLevel; }
    }
    return nil;
}
@end
