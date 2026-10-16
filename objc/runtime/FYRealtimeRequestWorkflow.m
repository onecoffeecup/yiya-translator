#import "FYRealtimeRequestWorkflow.h"
#import "../app/FYAppSupport.h"

@implementation FYRealtimeRequestWorkflow
- (void)submitContent:(FYPreparedRealtimeContent *)prepared items:(NSArray<OCRTextItem *> *)ocrBlocks duration:(NSTimeInterval)ocrDuration frame:(FYRealtimeRecognitionFrame *)frame trace:(NSDictionary *)trace layoutDebug:(NSDictionary *)layoutDebug runtime:(id<FYRealtimeRequestRuntime>)runtime host:(id<FYRealtimeRequestHost>)runtimeHost {
    BOOL captureCard=frame.captureCard;
    NSInteger cycleGeneration=frame.generation;
    uint32_t windowID=frame.windowID;
    NSUInteger inputEpoch=frame.inputEpoch;
    NSDate *cycleStart=frame.cycleStart;
    NSString *normalized=prepared.normalized;
    NSArray<OCRTextItem *> *currentUIItems=prepared.items;
    FYRealtimeResultDelivery *delivery=runtime.resultDelivery;
    NSInteger frameMode = [runtimeHost effectiveModeSegment];
    NSUInteger contentRevision = frameMode == ContentModeUI
        ? [runtimeHost beginInlineContentTranslation:normalized items:currentUIItems trace:trace]
        : [runtimeHost beginContentTranslation:normalized mode:frameMode];
    NSUInteger inlineSerial = runtimeHost.inlineTranslationSerial;
    FYRealtimeDeliveryTicket *deliveryTicket = [[FYRealtimeDeliveryTicket alloc]
        initWithGeneration:cycleGeneration windowID:windowID inputEpoch:inputEpoch
        mode:(frameMode == ContentModeUI ? ContentModeUI : ContentModeDialogue)];

    if (frameMode == ContentModeUI) {
        [[FYInlineLayoutDebug shared] recordItems:currentUIItems stage:@"inline_stable" context:layoutDebug];
        NSMutableArray<OCRTextItem *> *uiItems = [currentUIItems mutableCopy];
        if (uiItems.count == 0) {
            [runtimeHost finishContentTranslation:contentRevision];
            FYTrace(trace, @"skip", @{@"reason": @"ui_no_translatable_items", @"route": @"ui"});
            if (captureCard) {
                // 采集卡模式本来就没有贴译面板；字幕窗保留上一条，只更新状态。
                [runtimeHost setCaptionPanelVisibleForUIMode:NO];
                [runtimeHost setStatus:[NSString stringWithFormat:@"采集卡模式：界面暂无可译文字 · OCR %.1fs", ocrDuration]];
                return;
            }
            // 读不到文字（例如被 QuickTime 录制控件挡住）时，**保留上一帧的贴译面板**。
            // 之前这里会 clearInlineTranslationPanels，于是控件一出现译文就消失、
            // 控件淡出又重新贴出来 —— 看起来就是“闪/消失”。译文并没有变，不该清掉。
            [runtimeHost setCaptionPanelVisibleForUIMode:YES];
            [runtimeHost setStatus:[NSString stringWithFormat:@"自动判别：界面（暂无可译文字） · OCR %.1fs", ocrDuration]];
            return;
        }

        FuyiDiagLog(@"  -> ROUTE INLINE(UI) items=%lu", (unsigned long)uiItems.count);
        NSString *uiStatus = [NSString stringWithFormat:@"翻译界面 · OCR %.1fs", ocrDuration];
        [runtimeHost setStatus:uiStatus];
        NSArray<OCRTextItem *> *uiItemsForRender = [uiItems copy];
        runtimeHost.contentTranslationUIItems = uiItemsForRender;
        NSDate *uiTranslateStart = [NSDate date];
        NSArray<FYRequestIdentity *> *uiIdentities = [runtimeHost.learningCoordinator recordItems:[runtimeHost textsFromItems:uiItemsForRender] kind:FYSentenceKindUI];
        [runtimeHost refreshLearningSource];
        [runtimeHost refreshLearningStatus];
        NSDictionary *uiTrace = [[FYTranslationTrace shared] requestContextForCycle:trace];
        FYInlineDebugTracePerform(uiTrace, layoutDebug, ^{
        [runtimeHost translateInlineTextItems:uiItemsForRender completion:^(NSArray<NSString *> *translations, NSError *translationError) {
        [delivery deliverInline:translations error:translationError items:uiItemsForRender identities:uiIdentities
        normalized:normalized started:uiTranslateStart revision:contentRevision serial:inlineSerial ticket:deliveryTicket
        captureCard:captureCard inputEpoch:inputEpoch trace:uiTrace layoutDebug:layoutDebug runtime:runtime host:(id<FYRealtimeResultHost>)runtimeHost];
        }];
        });
        return;
    }

    FYTrace(trace, @"dialogue", @{@"stage": @"route", @"route": @"dialogue"});
    [runtimeHost setCaptionPanelVisibleForUIMode:NO];
    // 对白模式：对白框照常进悬浮字幕窗，上方的选项单独贴到原选项旁边。
    // 街景招牌、公告牌这类环境文本不会进 band，所以不会被翻译。
    FuyiDiagLog(@"  -> ROUTE DIALOGUE(caption)");
    // Both capture paths contain only source pixels. Matching an existing
    // translation does not make an original date/name/kanji an overlay.
    NSArray<OCRTextItem *> *dialogueSource = ocrBlocks;

    // Preserve the existing mapping gate and dialogue/full-frame fallback.
    BOOL optionsCanPasteInline = ![runtimeHost captureCardInputEnabled] || [runtimeHost inlinePlacementRect:NULL reason:NULL];
    FYContentRoute *contentRoute = [FYContentRouter dialogueRouteForItems:dialogueSource
        optionsCanPasteInline:optionsCanPasteInline filterObserver:FYContentFilterDiagnosticObserver()];
    NSArray<OCRTextItem *> *optionItems = contentRoute.optionItems;
    if (optionsCanPasteInline && optionItems.count == 0) { [runtimeHost clearInlineTranslationPanels]; }
    BOOL speakerLabelOnlyFrame = contentRoute.speakerLabelOnly;
    NSString *dialogueText = contentRoute.dialogueText;

    // 选项：走贴译路线，贴在原选项文字旁边；有缓存时不会重复请求
    if (optionItems.count > 0) {
        [runtime.contentState addOperation];
        NSArray<OCRTextItem *> *optionsToRender = [optionItems copy];
        NSArray<FYRequestIdentity *> *optionIdentities = [runtimeHost.learningCoordinator recordItems:[runtimeHost textsFromItems:optionsToRender] kind:FYSentenceKindOption];
        [runtimeHost refreshLearningSource];
        [runtimeHost refreshLearningStatus];
        NSDictionary *optionTrace = [[FYTranslationTrace shared] requestContextForCycle:trace];
        FYInlineDebugTracePerform(optionTrace, layoutDebug, ^{
        [runtimeHost translateInlineTextItems:optionsToRender completion:^(NSArray<NSString *> *translations, NSError *translationError) {
        [delivery deliverOptions:translations error:translationError items:optionsToRender identities:optionIdentities
        revision:contentRevision ticket:deliveryTicket inputEpoch:inputEpoch trace:optionTrace layoutDebug:layoutDebug
        runtime:runtime host:(id<FYRealtimeResultHost>)runtimeHost];
        }];
        });
    }

    FYTrace(trace, @"dialogue", @{@"stage": @"extracted", @"source": dialogueText ?: @""});
    if (NormalizeForComparison(dialogueText).length < 2) {
        [runtimeHost finishContentTranslation:contentRevision];
        FYTrace(trace, @"skip", @{@"reason": @"dialogue_empty"});
        [runtimeHost setStatus:@"对白框暂无可译文字"];
        return;
    }

    NSString *translatingStatus = [NSString stringWithFormat:@"翻译对白 · 自动判别 · OCR %.1fs", ocrDuration];
    [runtimeHost setStatus:translatingStatus];
    NSDate *translationStart = [NSDate date];
    NSMutableArray<NSString *> *excludedSpeakerLabels=[NSMutableArray new];
    for (OCRTextItem *item in contentRoute.dialogueItems.count ? contentRoute.dialogueItems : dialogueSource) {
        if ([FYContentRouter isExcludedSpeakerLabelItem:item]) { [excludedSpeakerLabels addObject:item.text]; }
    }
    FYRequestIdentity *dialogueIdentity = speakerLabelOnlyFrame ? nil : [runtimeHost.learningCoordinator recordDialogueText:dialogueText excludingSpeakerLabels:excludedSpeakerLabels];
    // Reused identities retain the complete source. Never overwrite its
    // translation with one generated from a degraded OCR frame.
    if (dialogueIdentity.sourceText.length) { dialogueText = dialogueIdentity.sourceText; }
    [runtimeHost refreshLearningSource];
    [runtimeHost refreshLearningStatus];
    NSDictionary *dialogueTrace = [[FYTranslationTrace shared] requestContextForCycle:trace];
    FYTrace(dialogueTrace, @"dialogue", @{@"stage": @"identity_source", @"source": dialogueText ?: @"",
                                        @"sentence_id": dialogueIdentity.sentenceID ?: @"", @"version": @(dialogueIdentity.version),
                                        @"identity_request_id": dialogueIdentity.requestID ?: @""});
    FYInlineDebugTracePerform(dialogueTrace, layoutDebug, ^{
    [runtimeHost translateDialogueText:dialogueText identity:dialogueIdentity systemPrompt:[runtimeHost systemPrompt] completion:^(NSString *translated, NSError *translationError) {
        [delivery deliverDialogue:translated error:translationError text:dialogueText identity:dialogueIdentity
        normalized:normalized started:translationStart duration:ocrDuration revision:contentRevision ticket:deliveryTicket
        generation:cycleGeneration windowID:windowID inputEpoch:inputEpoch cycleStart:cycleStart trace:dialogueTrace runtime:runtime host:(id<FYRealtimeResultHost>)runtimeHost];
        }];
    });
}
@end
