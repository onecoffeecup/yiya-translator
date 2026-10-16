#import "FYRealtimeContentAdmission.h"
#import "../app/FYAppSupport.h"

@implementation FYRealtimeContentAdmission
- (BOOL)admitContent:(FYPreparedRealtimeContent *)prepared rawText:(NSString *)ocrText items:(NSArray<OCRTextItem *> *)ocrBlocks duration:(NSTimeInterval)ocrDuration trace:(NSDictionary *)trace layoutDebug:(NSDictionary *)layoutDebug host:(id<FYRealtimeContentAdmissionHost>)runtimeHost {
    NSString *normalized=prepared.normalized;
    NSArray<OCRTextItem *> *currentUIItems=prepared.items;
    NSInteger currentFrameMode=prepared.mode;
    double translatedSimilarity = SimilarityRatio(normalized, runtimeHost.lastTranslatedNormalizedText ?: @"");
                        double submittedSimilarity = SimilarityRatio(normalized, runtimeHost.lastSubmittedNormalizedText ?: @"");

                        // 「文本相同」只能跳过**网络翻译**，不能跳过窗口边界/映射复核和贴译重排。
                        // 实际显示目标（OBS 编辑器 ↔ 全屏投影）换过、而渲染还是按旧目标做的时候，
                        // 必须继续往下走：走的是缓存命中路径（translateInlineTextItems 直接命中缓存），
                        // 不会重新请求翻译，但会用**这一帧**的原文块把贴译排到新位置上。
                        BOOL sameTextAsRendered = currentFrameMode == ContentModeUI
                            ? [normalized isEqualToString:(runtimeHost.lastTranslatedNormalizedText ?: @"")]
                            : [runtimeHost isSameSubtitleText:normalized comparedTo:runtimeHost.lastTranslatedNormalizedText];
                        BOOL geometryChangedSinceRender = currentFrameMode == ContentModeUI &&
                            ![(runtimeHost.lastInlineRenderGeometryToken ?: @"") isEqualToString:(runtimeHost.lastDisplayGeometryToken ?: @"")];
                        if (currentFrameMode == ContentModeUI && currentUIItems.count == runtimeHost.lastInlineRenderedItems.count) {
                            for (NSUInteger index = 0; index < currentUIItems.count; index++) {
                                CGRect old = runtimeHost.lastInlineRenderedItems[index].boundingBox;
                                CGRect now = currentUIItems[index].boundingBox;
                                if (MAX(MAX(fabs(NSMinX(old)-NSMinX(now)), fabs(NSMinY(old)-NSMinY(now))),
                                        MAX(fabs(NSWidth(old)-NSWidth(now)), fabs(NSHeight(old)-NSHeight(now)))) >= 0.010) {
                                    geometryChangedSinceRender = YES;
                                    break;
                                }
                            }
                        }
                        BOOL groupingChangedSinceRender = NO;
                        if (currentFrameMode == ContentModeUI && currentUIItems.count > 0 && runtimeHost.lastInlineRenderedItems.count > 0) {
                            NSArray<NSString *> *currentTexts = [currentUIItems valueForKey:@"text"];
                            NSArray<NSString *> *renderedTexts = [runtimeHost.lastInlineRenderedItems valueForKey:@"text"];
                            if (![currentTexts isEqualToArray:renderedTexts]) {
                                if ([currentTexts isEqualToArray:runtimeHost.inlinePendingGroupedTexts]) { runtimeHost.inlinePendingGroupedCount += 1; }
                                else { runtimeHost.inlinePendingGroupedTexts = currentTexts; runtimeHost.inlinePendingGroupedCount = 1; }
                                groupingChangedSinceRender = runtimeHost.inlinePendingGroupedCount >= 2;
                            } else {
                                runtimeHost.inlinePendingGroupedTexts = nil;
                                runtimeHost.inlinePendingGroupedCount = 0;
                            }
                        }

                        if (sameTextAsRendered && runtimeHost.contentTranslationOperations &&
                            (![runtimeHost pendingContentMatchesText:normalized mode:currentFrameMode] ||
                             (currentFrameMode == ContentModeUI && ![runtimeHost pendingInlineMatchesItems:currentUIItems]))) {
                            // A -> pending B -> A may be a new occurrence. Confirm it
                            // first; beginContentTranslation cancels B after stability.
                            sameTextAsRendered = NO;
                        }
                        if (sameTextAsRendered && !geometryChangedSinceRender && !groupingChangedSinceRender) {
                            runtimeHost.inlineOCRPendingText = nil;
                            runtimeHost.inlineOCRPendingCount = 0;
                            // A restored frame interrupts a candidate correction. Without
                            // this reset, intermittent OCR noise can accumulate two hits.
                            [[runtimeHost stabilityOwner] reset];
                            FYLayoutDebugPerform(layoutDebug, ^{
                                [runtimeHost recordInlineLayoutDebug:runtimeHost.lastInlineLayoutResult previous:runtimeHost.lastInlineLayoutResult
                                    viewport:runtimeHost.lastInlineLayoutDebugViewport reason:@"cache_same_as_last_translated"];
                            });
                            // 文本没变时不再走渲染路径，展开态记账要在这里补一次：
                            // 否则"这一块已从页面消失"会停在第一帧，阅读卡一直留在画面上。
                        [runtimeHost advanceExpandedReadingState];
                            FYTrace(trace, @"skip", @{@"reason": @"same_as_last_translated"});
                            [runtimeHost setStatus:[NSString stringWithFormat:@"文本未变化 · 相似 %.0f%% · OCR %.1fs", translatedSimilarity * 100, ocrDuration]];
                            return NO;
                        }
                        if (sameTextAsRendered) {
                            FYTrace(trace, @"skip", @{@"reason": @"same_as_last_translated_geometry_changed"});
                            [runtimeHost setStatus:[NSString stringWithFormat:@"画面位置变化 · 用已有译文重排 · OCR %.1fs", ocrDuration]];
                        }
                        if ([runtimeHost pendingContentMatchesText:normalized mode:currentFrameMode] &&
                            (currentFrameMode != ContentModeUI || [runtimeHost pendingInlineMatchesItems:currentUIItems])) {
                            [[runtimeHost stabilityOwner] reset];
                            if (currentFrameMode == ContentModeUI) {
                                runtimeHost.contentTranslationUIItems = currentUIItems;
                                runtimeHost.contentTranslationGeometryGeneration = runtimeHost.ocrGeometryGeneration;
                                runtimeHost.contentTranslationDisplayTarget = runtimeHost.ocrDisplayTargetWindowID;
                            }
                            FYTrace(trace, @"skip", @{@"reason": @"translation_pending"});
                            [runtimeHost setStatus:[NSString stringWithFormat:@"正在等待当前文字的译文 · OCR %.1fs", ocrDuration]];
                            return NO;
                        }
                        // UI OCR changes have already been confirmed per on-screen block by
                        // inlineFrameStabilizer. A second whole-page text gate would make a
                        // real edit wait indefinitely when unrelated background text jitters.

                        // 节流阈值按模式分开：
                        //   对白模式 4 秒 —— 防 OCR 抖动、防同一句台词反复请求
                        //   界面模式 1.2 秒 —— 界面是**用户自己在动**（滑动、翻页），
                        //                      让它等满 4 秒没道理，实测会变成“过了 5 秒才翻出来”
                        NSTimeInterval attemptThrottle = [runtimeHost translationAttemptThrottleForMode:currentFrameMode];

                        if (!groupingChangedSinceRender && [[runtimeHost translationState] shouldThrottleText:normalized geometryChanged:geometryChangedSinceRender interval:attemptThrottle
                            equivalent:^BOOL(NSString *current, NSString *previous) { return [runtimeHost isSameSubtitleText:current comparedTo:previous]; }
                            now:^NSDate *{ return [runtimeHost translationProcessingDate]; }]) {
                        [runtimeHost advanceExpandedReadingState];
                            FYTrace(trace, @"skip", @{@"reason": @"submission_throttle"});
                            [runtimeHost setStatus:[NSString stringWithFormat:@"等待翻译返回 · 相似 %.0f%% · OCR %.1fs", submittedSimilarity * 100, ocrDuration]];
                            return NO;
                        }

                        BOOL shouldWaitForStableText = YES;
    #ifdef FY_TEST_ISOLATED_CREDENTIAL_STORE
                        if (runtimeHost.stableTextCheckbox) { shouldWaitForStableText = runtimeHost.stableTextCheckbox.state == NSControlStateValueOn; }
    #endif
                        // 界面模式不等稳定：用户滑完就希望立刻看到译文，多等一帧就多一分延迟
                        if (currentFrameMode == ContentModeUI) { shouldWaitForStableText = NO; }
                        if (shouldWaitForStableText && ![runtimeHost isStableText:normalized]) {
                            FYTrace(trace, @"stable", @{@"reason": @"waiting", @"stable_required": @YES, @"stable_count": @(runtimeHost.stableCandidateCount)});
                            [runtimeHost setStatus:[NSString stringWithFormat:@"等待文本稳定 · OCR %.1fs", ocrDuration]];
                            return NO;
                        }

                        FYTrace(trace, @"stable", @{@"reason": shouldWaitForStableText ? @"accepted" : @"not_required",
                                                   @"stable_required": @(shouldWaitForStableText), @"stable_count": @(runtimeHost.stableCandidateCount)});
                        if (FuyiDiagEnabled()) {
                            NSUInteger tokens = UITokenHitCount(ocrBlocks);
                            NSUInteger substantial = 0;
                            for (OCRTextItem *b in ocrBlocks) {
                                NSString *n = NormalizeForComparison(b.text);
                                if (n.length == 0) { continue; }
                                if (b.boundingBox.size.width >= 0.15) { substantial += 1; continue; }
                                if (n.length >= 8 && b.boundingBox.size.width >= 0.13 && b.boundingBox.size.height >= 0.030) { substantial += 1; }
                            }
                            NSArray<OCRTextItem *> *dbgBand = SubtitleBandItemsFromBlocks(ocrBlocks);
                            FuyiDiagLog(@"CYCLE auto=%d blocks=%lu tokens=%lu substantial=%lu looksUI=%d band=%lu detected=%ld text=<%@>",
                                        YES,
                                        (unsigned long)ocrBlocks.count, (unsigned long)tokens, (unsigned long)substantial,
                                        LooksLikeUIFrame(ocrBlocks), (unsigned long)dbgBand.count,
                                        (long)runtimeHost.detectedModeSegment, FYDiagTextLength(ocrText));
                        }
    return YES;
}
@end
