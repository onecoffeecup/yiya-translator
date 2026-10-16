#import "FYRealtimeResultDelivery.h"
#import "../app/FYAppSupport.h"

@implementation FYRealtimeResultDelivery
- (void)deliverInline:(NSArray<NSString *> *)translations error:(NSError *)translationError items:(NSArray<OCRTextItem *> *)uiItemsForRender identities:(NSArray<FYRequestIdentity *> *)uiIdentities normalized:(NSString *)normalized started:(NSDate *)uiTranslateStart revision:(NSUInteger)contentRevision serial:(NSUInteger)inlineSerial ticket:(FYRealtimeDeliveryTicket *)deliveryTicket captureCard:(BOOL)captureCard inputEpoch:(NSUInteger)inputEpoch trace:(NSDictionary *)uiTrace layoutDebug:(NSDictionary *)layoutDebug runtime:(id<FYRealtimeResultRuntime>)runtime host:(id<FYRealtimeResultHost>)runtimeHost {
    if (!FYInlinePlanIsCurrent(contentRevision, runtimeHost.contentTranslationRevision, inlineSerial, runtimeHost.inlineTranslationSerial)) {
        FYTrace(uiTrace, @"inline_drop", @{@"reason": @"content_changed"});
        return;
    }
    NSArray<OCRTextItem *> *renderItems = runtimeHost.contentTranslationUIItems ?: uiItemsForRender;
    NSString *reason = [deliveryTicket dropReasonWithSource:runtime];
    if (reason) {
        FYTrace(uiTrace, @"inline_drop", @{@"reason": reason, @"route": @"ui", @"input_epoch": @(inputEpoch)});
        [runtimeHost finishContentTranslation:contentRevision];
        return;
    }
    runtimeHost.translationDurationLabel.stringValue = [NSString stringWithFormat:@"翻译耗时  %.2f 秒", [[NSDate date] timeIntervalSinceDate:uiTranslateStart]];
    FuyiDiagLog(@"  TRANSLATE(items=%lu) took %.2fs err=<%@>",
                (unsigned long)uiItemsForRender.count,
                [[NSDate date] timeIntervalSinceDate:uiTranslateStart],
                [NSString stringWithFormat:@"code:%ld", (long)translationError.code]);
    [runtimeHost bindTranslations:translations toIdentities:uiIdentities];
    [runtimeHost refreshLearningSource];
    [runtimeHost refreshLearningStatus];
    if (captureCard) {
        // 采集卡与窗口截图走同一条界面贴译流程：
        // 先建立"视频画面 → 显示区域"的坐标映射（inlinePlacementRect:）；
        // 有映射就原位贴译，没有映射由 handleInlineTranslationResult 给出明确提示，
        // 绝不静默把界面译文当成对白塞进字幕窗。
        [runtimeHost setCaptionPanelVisibleForUIMode:YES];
        FYInlineDebugTracePerform(uiTrace, layoutDebug, ^{
            [runtimeHost handleInlineTranslationResult:translations forItems:renderItems error:translationError failureStatus:@"采集卡：界面翻译出错" successPrefix:@"采集卡界面译文已更新"];
        });
        if (!translationError) {
            runtimeHost.lastTranslatedNormalizedText = normalized;
            runtimeHost.translationCount += 1;
            [runtimeHost updateTranslationCount];
        }
        [runtimeHost finishContentTranslation:contentRevision];
        return;
    }
    FYInlineDebugTracePerform(uiTrace, layoutDebug, ^{
        [runtimeHost handleInlineTranslationResult:translations forItems:renderItems error:translationError failureStatus:@"界面翻译出错" successPrefix:@"界面译文已更新"];
    });
    if (!translationError) {
        runtimeHost.lastTranslatedNormalizedText = normalized;
        runtimeHost.translationCount += 1;
        [runtimeHost updateTranslationCount];
    }
    // 界面模式下字幕窗默认收起；映射不可用时由提示逻辑重新显示它。
    [runtimeHost setCaptionPanelVisibleForUIMode:YES];
    [runtimeHost finishContentTranslation:contentRevision];
}

- (void)deliverOptions:(NSArray<NSString *> *)translations error:(NSError *)translationError items:(NSArray<OCRTextItem *> *)optionsToRender identities:(NSArray<FYRequestIdentity *> *)optionIdentities revision:(NSUInteger)contentRevision ticket:(FYRealtimeDeliveryTicket *)deliveryTicket inputEpoch:(NSUInteger)inputEpoch trace:(NSDictionary *)optionTrace layoutDebug:(NSDictionary *)layoutDebug runtime:(id<FYRealtimeResultRuntime>)runtime host:(id<FYRealtimeResultHost>)runtimeHost {
    if (!FYContentRevisionIsCurrent(contentRevision, runtimeHost.contentTranslationRevision)) {
        FYTrace(optionTrace, @"inline_drop", @{@"reason": @"content_changed"});
        return;
    }
    NSString *reason = [deliveryTicket dropReasonWithSource:runtime];
    if (reason) {
        FYTrace(optionTrace, @"inline_drop", @{@"reason": reason, @"route": @"option", @"input_epoch": @(inputEpoch)});
        [runtimeHost finishContentTranslation:contentRevision];
        return;
    }
    [runtimeHost bindTranslations:translations toIdentities:optionIdentities];
    [runtimeHost refreshLearningSource];
    [runtimeHost refreshLearningStatus];
    FYInlineDebugTracePerform(optionTrace, layoutDebug, ^{
        [runtimeHost handleInlineTranslationResult:translations forItems:optionsToRender error:translationError failureStatus:@"选项翻译出错" successPrefix:@"选项已贴译"];
    });
    [runtimeHost finishContentTranslation:contentRevision];
}

- (void)deliverDialogue:(NSString *)translated error:(NSError *)translationError text:(NSString *)dialogueText identity:(FYRequestIdentity *)dialogueIdentity normalized:(NSString *)normalized started:(NSDate *)translationStart duration:(NSTimeInterval)ocrDuration revision:(NSUInteger)contentRevision ticket:(FYRealtimeDeliveryTicket *)deliveryTicket generation:(NSInteger)cycleGeneration windowID:(uint32_t)windowID inputEpoch:(NSUInteger)inputEpoch cycleStart:(NSDate *)cycleStart trace:(NSDictionary *)dialogueTrace runtime:(id<FYRealtimeResultRuntime>)runtime host:(id<FYRealtimeResultHost>)runtimeHost {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!FYContentRevisionIsCurrent(contentRevision, runtimeHost.contentTranslationRevision)) {
            FYTrace(dialogueTrace, @"caption_drop", @{@"reason": @"content_changed"});
            return;
        }
        NSString *reason = [deliveryTicket dropReasonWithSource:runtime];
        if (reason) {
            FYTrace(dialogueTrace, @"caption_drop", @{@"reason": reason, @"input_epoch": @(inputEpoch)});
            [runtimeHost finishContentTranslation:contentRevision];
            return;
        }
        NSTimeInterval translationDuration = [[NSDate date] timeIntervalSinceDate:translationStart];
        runtimeHost.translationDurationLabel.stringValue = [NSString stringWithFormat:@"翻译耗时  %.2f 秒", translationDuration];
        NSTimeInterval totalDuration = [[NSDate date] timeIntervalSinceDate:cycleStart];
        if (translationError) {
            [runtimeHost showError:FYTranslationFailureMessage(translationError, 0)];
            NSString *status = [NSString stringWithFormat:@"翻译出错 · OCR %.1fs 翻译 %.1fs", ocrDuration, translationDuration];
            [runtimeHost setStatus:status];
            [runtimeHost updateCaptionWindowWithText:[@"翻译失败：" stringByAppendingString:FYTranslationFailureMessage(translationError, 110)] status:status];
            FYTrace(dialogueTrace, @"caption_apply", @{@"reason": @"translation_error", @"error_code": @(translationError.code), @"success": @NO});
        } else {
            [runtimeHost.learningCoordinator setTranslation:translated forIdentity:dialogueIdentity];
            [runtimeHost refreshLearningSource];
            [runtimeHost refreshLearningStatus];
            runtimeHost.lastTranslatedNormalizedText = normalized;
            runtimeHost.lastSubmittedNormalizedText = normalized;
            runtimeHost.translationCount += 1;
            [runtimeHost showError:@""];
            NSString *status = [NSString stringWithFormat:@"译文已更新 · OCR %.1fs 翻译 %.1fs 总 %.1fs", ocrDuration, translationDuration, totalDuration];
            [runtimeHost setStatus:status];
            NSString *display = [runtimeHost displayableTranslation:translated sourceText:dialogueText];
            [runtimeHost updateCaptionWindowWithText:display status:status];
            [[FYRuntimeDiagnostics shared] recordEvent:@"caption" fields:@{@"window_id": @(windowID), @"generation": @(cycleGeneration), @"success": @YES, @"visible": @(runtimeHost.captionPanel.isVisible)}];
            FYTrace(dialogueTrace, @"caption_apply", @{@"reason": @"translated", @"source": dialogueText ?: @"", @"translation": display ?: @"", @"success": @YES, @"visible": @(runtimeHost.captionPanel.isVisible)});
            runtimeHost.latestTranslationLabel.stringValue = display;
            runtimeHost.latestSourceLabel.stringValue = dialogueText;
            [runtimeHost updateTranslationCount];
        }
        [runtimeHost finishContentTranslation:contentRevision];
    });
}

- (void)handleInlineTranslationResult:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items error:(NSError *)translationError failureStatus:(NSString *)failureStatus successPrefix:(NSString *)successPrefix runtime:(id<FYRealtimeResultRuntime>)runtime host:(id<FYRealtimeResultHost>)runtimeHost {
    NSDictionary *trace = FYCurrentTrace();
    NSDictionary *layoutDebug = FYCurrentLayoutDebug();
    FYContentTranslationSnapshot *content = [runtime.contentState snapshot];
    NSInteger generation = runtimeHost.translationGeneration;
    NSInteger mode = [runtimeHost effectiveModeSegment];
    NSUInteger inputEpoch = runtimeHost.captureCardInput.sessionEpoch;
    NSInteger cycleGeometry = content.operations ? content.geometryGeneration : runtimeHost.ocrGeometryGeneration;
    uint32_t cycleTarget = content.operations ? content.displayTarget : runtimeHost.ocrDisplayTargetWindowID;
    FYInlinePlacementDeliveryTicket *deliveryTicket = [[FYInlinePlacementDeliveryTicket alloc]
        initWithContentRevision:content.revision generation:generation
        inputEpoch:inputEpoch mode:mode
        geometryGeneration:cycleGeometry displayTarget:cycleTarget];
    // 先建立"画面 → 显示区域"的落位矩形：窗口截图用整个目标窗口，采集卡用视频帧适配后的可见矩形。
    NSRect placement = NSZeroRect;
    NSString *placementReason = nil;
    BOOL hasPlacement = [runtimeHost inlinePlacementRect:&placement reason:&placementReason];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *reason = [deliveryTicket dropReasonWithSource:runtime];
        if (reason) {
            FYTrace(trace, @"inline_drop", @{@"reason": reason});
            if (![reason isEqualToString:@"content_changed"]) {
                [[FYInlineLayoutDebug shared] recordDecision:[reason isEqualToString:@"geometry_changed"] ? @"drop_stale_geometry" : reason context:layoutDebug];
            }
            // Geometry refresh owns repositioning; rejecting old placement must
            // not hide panels already moved to the new geometry.
            return;
        }
        if (translationError) {
            FYTrace(trace, @"inline_drop", @{@"reason": @"translation_error", @"error_code": @(translationError.code)});
            [runtimeHost showError:FYTranslationFailureMessage(translationError, 0)];
            [runtimeHost setStatus:failureStatus];
            return;
        }
        if (!hasPlacement) {
            // 映射不可用：明确提示，绝不静默把界面译文塞进对白框。
            [runtimeHost clearInlineTranslationPanels];
            [runtimeHost showInlineMappingUnavailableNotice:placementReason];
            FYTrace(trace, @"inline_drop", @{@"reason": @"mapping_unavailable", @"detail": placementReason ?: @""});
            return;
        }
        [runtimeHost showError:@""];
        FYLayoutDebugPerform(layoutDebug, ^{ [runtimeHost showInlineTranslations:translations forItems:items placementRect:placement]; });
        FYTrace(trace, @"inline_apply", @{@"source": [[items valueForKey:@"text"] componentsJoinedByString:@"\n"] ?: @"", @"translation": [translations componentsJoinedByString:@"\n"] ?: @"", @"blocks": @(items.count)});
        // 集中查看走实时页的「界面译文」列表（refreshInlineTranslationList，在 showInlineTranslations 里刷新），
        // 不再写 latestTranslationLabel/latestSourceLabel —— 那两个控件从未创建，用户根本看不到。
        [runtimeHost refreshInlineTranslationList];
        NSUInteger shown = 0;
        for (NSString *value in translations) {
            if (Trim(value).length > 0) { shown += 1; }
        }
        NSString *statusText = [NSString stringWithFormat:@"%@：%lu 条", successPrefix, (unsigned long)shown];
        if (runtimeHost.lastInlineCompactEntryCount > 0) {
            statusText = [statusText stringByAppendingFormat:@"，%lu 条用「查看译文」入口",
                          (unsigned long)runtimeHost.lastInlineCompactEntryCount];
        }
        if (runtimeHost.lastInlineUnplaceableCount > 0) {
            // 没有合法位置的块绝不能静默丢弃：状态区给条数**和第一条译文原文**，
            // 用户在主界面就能直接读到内容（完整译文也写进主界面译文区）。
            NSString *firstUnplaced = nil;
            for (FYInlinePlacement *placement in runtimeHost.lastInlineLayoutResult.placements) {
                if (placement.mode != FYInlineDisplayModeUnplaceable) { continue; }
                if (Trim(placement.translation).length > 0) { firstUnplaced = Trim(placement.translation); break; }
            }
            statusText = firstUnplaced.length > 0
                ? [statusText stringByAppendingFormat:@"，%lu 条译文未在画面显示（暂不可放置）：%@",
                   (unsigned long)runtimeHost.lastInlineUnplaceableCount, Shorten(firstUnplaced, 40)]
                : [statusText stringByAppendingFormat:@"，%lu 条译文未在画面显示（暂不可放置）",
                   (unsigned long)runtimeHost.lastInlineUnplaceableCount];
        }
        [runtimeHost setStatus:statusText];
    });
}

@end
