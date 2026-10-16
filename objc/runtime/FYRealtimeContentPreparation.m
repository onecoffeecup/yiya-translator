#import "FYRealtimeContentPreparation.h"
#import "../app/FYAppSupport.h"

@implementation FYRealtimeContentPreparation
- (FYPreparedRealtimeContent *)prepareText:(NSString *)ocrText items:(NSArray<OCRTextItem *> *)ocrBlocks modalItems:(NSArray<OCRTextItem *> *)modalScopedBlocks duration:(NSTimeInterval)ocrDuration language:(NSInteger)languageSegment trace:(NSDictionary *)trace layoutDebug:(NSDictionary *)layoutDebug host:(id<FYRealtimeContentPreparationHost>)runtimeHost {
    NSString *normalized = NormalizeForComparison(ocrText);
    if (normalized.length < 2) {
        if ([runtimeHost effectiveModeSegment] == ContentModeUI) { [runtimeHost.inlineFrameStabilizer observeItems:@[]]; }
        [[runtimeHost stabilityOwner] reset];
        FYTrace(trace, @"skip", @{@"reason": @"ocr_empty"});
        [runtimeHost setStatus:[NSString stringWithFormat:@"等待识别字幕 · OCR %.1fs", ocrDuration]];
        return nil;
    }

    // 自动判别必须在这里、也就是**所有去重闸门之前**跑。
    // 之前它被放在闸门后面，而闸门一命中就 return —— 结果模式永远提交不了，
    // 一直卡在初始的「对白」，整屏新闻条目就被塞进字幕窗。
    // 判别本来就是用来决定“该不该翻译、走哪条路”的，不能依赖“这一帧要不要翻译”。
    NSInteger tracePreviousMode = runtimeHost.detectedModeSegment;
    {
        NSInteger previousMode = runtimeHost.detectedModeSegment;
        // Keep the user's chooser/reading card alive during OCR dropouts.
        NSInteger committedMode = (runtimeHost.inlineOverflowChoicePanel || runtimeHost.inlineExpandedReadingPanel)
            ? previousMode : [runtimeHost stableContentModeForBlocks:ocrBlocks];
        if (previousMode != committedMode) {
            [runtimeHost invalidateContentTranslation];
            // Follow the new mode's cadence without creating a timer
            // in headless/manual single-frame callers.
            if (runtimeHost.timer) { [runtimeHost restartTimerIfRunning]; }
            FYTrace(trace, @"caption_drop", @{@"reason": @"mode_changed", @"previous_mode": @(previousMode), @"mode": @(committedMode)});
            NSString *switched = committedMode == ContentModeUI ? @"自动判别：功能界面 → 切换为贴译" : @"自动判别：剧情对白 → 切换为字幕";
            [runtimeHost setStatus:switched];
            // 模式切换会改变译文的呈现方式（字幕窗 ↔ 贴译面板），必须清掉旧模式的产物，
            // 并让当前文本重新翻一次。实测漏了这一步的后果：
            // 从界面切到对白时，前一帧已经把整段对白贴成了 INLINE 面板；
            // 切过来后对白分支因为“文本已翻译过”而跳过，面板又没人清 —— 屏幕上一直挂着那张贴译。
            [runtimeHost clearInlineTranslationPanels];
            runtimeHost.lastTranslatedNormalizedText = nil;
            runtimeHost.lastSubmittedNormalizedText = nil;
            [[runtimeHost stabilityOwner] reset];
            runtimeHost.latestTranslationLabel.stringValue = @"等待译文";
            runtimeHost.latestSourceLabel.stringValue = @"";
        }
    }

    FYTrace(trace, @"mode", @{@"auto_mode": @YES, @"previous_mode": @(tracePreviousMode),
                             @"mode": @([runtimeHost effectiveModeSegment]), @"candidate_mode": @(runtimeHost.candidateModeSegment),
                             @"candidate_hits": @(runtimeHost.candidateModeHits)});
    NSInteger currentFrameMode = [runtimeHost effectiveModeSegment];
    if (currentFrameMode == ContentModeDialogue) {
        NSMutableArray<NSString *> *comparisonLines = [NSMutableArray array];
        for (OCRTextItem *item in ocrBlocks) {
            if (![FYContentRouter isExcludedSpeakerLabelItem:item]) { [comparisonLines addObject:item.text]; }
        }
        // Use the same plate/body distinction before stability,
        // pending-request matching and rendered-frame dedup.
        NSString *comparisonText = [comparisonLines componentsJoinedByString:@"\n"];
        // Normalize Japanese dialogue while line boundaries
        // still exist. Flattening first hides later-line
        // prefixes from the shared history/frame identity key.
        normalized = languageSegment == 0 ? FYDialogueComparisonKey(comparisonText)
            : NormalizeForComparison(comparisonText);
    }
    NSArray<OCRTextItem *> *observedUIItems = currentFrameMode == ContentModeUI
        ? [runtimeHost filteredInlineTextItems:[runtimeHost mergedInlineTextItemsFromItems:modalScopedBlocks] strict:NO]
        : nil;
    NSArray<OCRTextItem *> *currentUIItems = nil;
    if (currentFrameMode == ContentModeUI) {
        FYTrace(trace, @"ocr", @{@"stage": @"inline_grouped", @"ocr_lines": FYTraceOCRLines(observedUIItems),
                                 @"blocks": @(observedUIItems.count)});
        [[FYInlineLayoutDebug shared] recordItems:observedUIItems stage:@"inline_grouped" context:layoutDebug];
        currentUIItems = [runtimeHost.inlineFrameStabilizer observeItems:observedUIItems];
        [[FYInlineLayoutDebug shared] recordItems:currentUIItems stage:@"inline_stable" context:layoutDebug];
        if (!runtimeHost.inlineFrameStabilizer.ready) {
            FYTrace(trace, @"stable", @{@"reason": @"inline_frame_confirming", @"stable_count": @1});
            [runtimeHost setStatus:@"正在确认界面文字"];
            return nil;
        }
        FYTrace(trace, @"ocr", @{@"stage": @"inline_stable", @"ocr_lines": FYTraceOCRLines(currentUIItems),
                                 @"blocks": @(currentUIItems.count)});
        normalized = NormalizeForComparison([[currentUIItems valueForKey:@"text"] componentsJoinedByString:@"\n"]);
    }
    return [[FYPreparedRealtimeContent alloc] initWithNormalized:normalized items:currentUIItems mode:currentFrameMode];
}
@end
