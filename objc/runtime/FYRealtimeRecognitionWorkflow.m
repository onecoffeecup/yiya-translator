#import "FYRealtimeRecognitionWorkflow.h"
#import "../app/FYAppSupport.h"

@implementation FYRealtimeRecognitionWorkflow
- (void)tick:(NSTimer *)timer runtime:(id<FYRealtimeRecognitionRuntime>)runtime host:(id<FYRealtimeRecognitionHost>)runtimeHost {
    if (!runtimeHost.running) { return; }
        if (!runtimeHost.lastDiagnosticCheckDate || [NSDate.date timeIntervalSinceDate:runtimeHost.lastDiagnosticCheckDate] >= 5) {
            [runtimeHost updateRuntimeDiagnostics];
        }
        // 几何复核放在**所有提前返回之前**：即使这一轮 OCR 文本和上一轮完全一样
        //（会被 same_as_last_translated 直接 return），窗口边界检查、映射有效性检查和贴译重排也必须跑。
        [runtimeHost refreshDisplayGeometryIfNeeded:NO];
        if (runtimeHost.inFlight) {
            NSDictionary *busyTrace = [[FYTranslationTrace shared] beginCycleForWindow:[runtimeHost displayTargetWindowID]
                generation:runtimeHost.translationGeneration inputEpoch:runtimeHost.captureCardInput.sessionEpoch
                inputSource:[runtimeHost captureCardInputEnabled] ? 1 : 0];
            FYTrace(busyTrace, @"skip", @{@"reason": @"task_busy"});
            return;
        }
        BOOL captureCard = [runtimeHost captureCardInputEnabled];
        [runtime.recognitionScheduler beginCycle];
        NSDate *cycleStart = [NSDate date];

        // 用**实际承载游戏画面的窗口**（OBS 全屏投影时不是用户选中的编辑器窗口）取画面、算映射：
        // 识别来源、映射坐标系、贴译落位必须全部落在同一个窗口上，否则贴译会跟着旧窗口算。
        uint32_t windowID = [runtimeHost displayTargetWindowID];
        if (windowID == 0) {
            [runtime.recognitionScheduler finishCurrentCycle];
            [runtimeHost hideInlineTranslationPanelsForGeometryChange];
            [runtimeHost setStatus:@"检测到多个可能是游戏画面的窗口，请重新选择显示窗口"];
            return;
        }
        // 本轮 OCR 用的几何代次：异步翻译回来时据此判断"这帧是否已经过期"。
        runtimeHost.ocrDisplayTargetWindowID = windowID;
        runtimeHost.ocrGeometryGeneration = runtimeHost.geometryGeneration;
        [[FYRuntimeDiagnostics shared] recordEvent:@"cycle" fields:@{@"window_id": @(windowID), @"generation": @(runtimeHost.translationGeneration), @"input_source": @(captureCard ? 1 : 0)}];
        NSDictionary *trace = [[FYTranslationTrace shared] beginCycleForWindow:windowID
                                                                   generation:runtimeHost.translationGeneration
                                                                   inputEpoch:runtimeHost.captureCardInput.sessionEpoch
                                                                  inputSource:captureCard ? 1 : 0];
        // 采集会话代次：本轮 OCR/翻译用的画面属于哪一次采集会话。
        // 切源、停采、换设备、断连都会让它自增，迟到的结果据此被丢弃。
        NSUInteger inputEpoch = runtimeHost.captureCardInput.sessionEpoch;
        uint64_t captureFrameIndex = 0;
        if (captureCard) {
            captureFrameIndex = [runtimeHost.captureCardInput latestFrameIndex];
            if (![runtime.recognitionScheduler needsCaptureFrame:captureFrameIndex]) {
                FYTrace(trace, @"skip", @{@"reason": @"capture_card_no_new_frame", @"input_epoch": @(inputEpoch)});
                [runtime.recognitionScheduler finishCurrentCycle];
                [runtimeHost updateCaptureCardStatus];
                [runtimeHost setStatus:runtimeHost.captureCardInput.state == FYCaptureCardSessionStateRunning ? @"等待采集卡新画面" : runtimeHost.captureCardInput.stateDetail];
                return;
            }
        }
        NSInteger cycleGeneration = runtimeHost.translationGeneration;
        FYRecognitionCycleIdentity *cycle = [[FYRecognitionCycleIdentity alloc] initWithGeneration:cycleGeneration
            windowID:windowID inputEpoch:inputEpoch kind:FYRecognitionCycleRealtime];
        FYRecognitionCycleLease *cycleLease = [runtime recognitionLeaseForHost:runtimeHost];
        NSDictionary *captureTrace = trace;
        dispatch_async(runtimeHost.captureQueue, ^{
            // Window pixels and capture-card image conversion must not block AppKit.
            uint64_t actualCaptureFrameIndex = 0;
            CGImageRef fullImage = captureCard ? [runtimeHost.captureCardInput copyLatestFrameWithIndex:&actualCaptureFrameIndex] : [runtimeHost copyFullCapturedImageForWindow:windowID];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([cycle captureDropReasonWithLease:cycleLease]) {
                    if (fullImage) { CGImageRelease(fullImage); }
                    [runtime.recognitionScheduler finishCycle:cycle lease:cycleLease];
                    FYTrace(captureTrace, @"skip", @{@"reason": @"capture_input_changed"});
                    return;
                }
                NSDictionary *trace = captureTrace;
                if (!fullImage) {
                    runtimeHost.ocrRefinementStabilizer=nil;
                    runtimeHost.ocrRefinementContext=nil;
                    FYTrace(trace, @"capture", @{@"success": @NO, @"reason": captureCard ? @"capture_card_no_frame" : @"capture_unavailable"});
                    FYTrace(trace, @"skip", @{@"reason": captureCard ? @"capture_card_no_frame" : @"capture_unavailable", @"input_epoch": @(inputEpoch)});
                    [runtime.recognitionScheduler finishCurrentCycle];
                    if (captureCard) {
                        [runtimeHost updateCaptureCardStatus]; [runtimeHost setStatus:@"采集卡暂无画面"];
                    } else {
                        [[FYRuntimeDiagnostics shared] recordEvent:@"capture" fields:@{@"window_id": @(windowID), @"generation": @(cycleGeneration), @"success": @NO}];
                        if ([runtimeHost recoverWindowSelectionIfRecreated]) { return; }
                        runtimeHost.captureUnavailable = YES; [runtimeHost updateRunState];
                        [runtimeHost setStatus:@"截取窗口失败"]; [runtimeHost showPreviewUnavailable:@"无法截取目标窗口"];
                    }
                    return;
                }
                if (captureCard) { runtimeHost.lastOCRedCaptureFrameIndex = actualCaptureFrameIndex; }
                runtimeHost.captureUnavailable = NO;
                [runtimeHost updateRunState];
                trace = [[FYTranslationTrace shared] frameContextForCycle:trace index:actualCaptureFrameIndex];
                FYTrace(trace, @"capture", @{@"success": @YES, @"width": @(CGImageGetWidth(fullImage)),
                                            @"height": @(CGImageGetHeight(fullImage))});
                [[FYRuntimeDiagnostics shared] recordEvent:@"capture" fields:@{@"window_id": @(windowID), @"generation": @(runtimeHost.translationGeneration), @"success": @YES}];
                [runtimeHost setStatus:@"正在 OCR"];
                [runtimeHost updatePreviewFromImage:fullImage generation:cycleGeneration];
                BOOL fastOCR = NO;
                BOOL autoFit = YES;
    #ifdef FY_TEST_ISOLATED_CREDENTIAL_STORE
                if (runtimeHost.autoFitRegionCheckbox) { autoFit = runtimeHost.autoFitRegionCheckbox.state == NSControlStateValueOn; }
    #endif
                NSInteger languageSegment = runtimeHost.languageControl.selectedSegment;
                runtimeHost.learningCoordinator.japaneseMode = (languageSegment == 0);

                // 两种输入都不包含译芽浮窗：窗口截图只取 IncludingWindow，采集卡只取视频帧。
                // 不能按屏幕浮窗位置遮掉这些干净源图，否则恢复模态过滤后会把真实正文误删。
                NSArray<NSValue *> *exclusionSnapshot = @[];

                CGRect ocrScope=[runtimeHost selectedOCRScope];
                FYOCRRefinementIdentity *refinementIdentity = [[FYOCRRefinementIdentity alloc]
                    initWithGeneration:cycleGeneration windowID:windowID captureCard:captureCard inputEpoch:inputEpoch
                    language:languageSegment scopeSignature:NSStringFromRect(ocrScope)
                    width:CGImageGetWidth(fullImage) height:CGImageGetHeight(fullImage)];
                // The old worker retains its own state; context replacement cannot
                // redirect its evidence into a later generation's state.
                FYOCRRefinementStabilizer *refinementStabilizer = [runtime.refinementSession stateForIdentity:refinementIdentity];
                NSDictionary *layoutDebug=[[FYInlineLayoutDebug shared] beginFrameWithImage:fullImage metadata:@{
                    @"window_id":@(windowID), @"generation":@(cycleGeneration), @"geometry_generation":@(runtimeHost.geometryGeneration),
                    @"input_source":@(captureCard), @"input_epoch":@(inputEpoch), @"frame_index":@(actualCaptureFrameIndex), @"scope":FYLayoutDebugRect(ocrScope)}];
                FYOCRRecognitionImageLease *imageLease = [[FYOCRRecognitionImageLease alloc] initWithOwnedImage:fullImage];
                FYOCRRecognitionSettings *recognitionSettings = [[FYOCRRecognitionSettings alloc] initWithManual:NO
                    language:languageSegment fastOCR:fastOCR autoFit:autoFit scope:ocrScope exclusions:exclusionSnapshot];
                FYOCRRecognitionOperationLease *operations = [runtime ocrOperationsForHost:runtimeHost layoutDebug:layoutDebug];
                FYOCRWorkerObserver observer = [runtime ocrObserverForTrace:trace layoutDebug:layoutDebug windowID:windowID
                    generation:cycleGeneration frameIndex:captureFrameIndex language:languageSegment fastOCR:fastOCR];
                FYTrace(trace, @"task", @{@"reason": @"ocr_scheduled"});
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                  FYInlineDebugTracePerform(trace, layoutDebug, ^{
                    FYOCRRecognitionResult *result = [runtime.ocrWorker recognizeImageLease:imageLease settings:recognitionSettings
                        refinement:refinementStabilizer operations:operations cropScope:^(CGRect crop,CGSize size,void(^work)(void)) {
                            FYLayoutDebugPerformCrop(crop,size,work);
                        } observer:observer];
                    NSError *error = result.error;
                    NSArray<OCRTextItem *> *ocrBlocks = result.items;
                    NSArray<OCRTextItem *> *modalScopedBlocks = result.modalItems;
                    NSString *ocrText = result.text;
                    NSTimeInterval ocrDuration = result.duration;

                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSString *reason = [cycle recognitionDropReasonWithLease:cycleLease];
                        if (reason) {
                            FYTrace(trace, @"skip", @{@"reason": reason, @"input_epoch": @(inputEpoch)});
                            // An old OCR may finish after stop/start acquired a new
                            // cycle. It must not release that cycle's busy flag.
                            [runtime.recognitionScheduler finishCycle:cycle lease:cycleLease];
                            return;
                        }
                        // The network must never hold the capture/OCR slot.
                        [runtime.recognitionScheduler finishCurrentCycle];
                        runtimeHost.ocrDurationLabel.stringValue = [NSString stringWithFormat:@"最近识别  %.2f 秒", ocrDuration];
                        if (error) {
                            FYTrace(trace, @"skip", @{@"reason": @"ocr_error", @"error_code": @(error.code)});
                            [runtimeHost showError:error.localizedDescription];
                            [runtimeHost setStatus:@"OCR 出错"];
                            return;
                        }


                        FYRealtimeRecognitionFrame *frame=[[FYRealtimeRecognitionFrame alloc]
                            initWithGeneration:cycleGeneration windowID:windowID inputEpoch:inputEpoch
                            captureCard:captureCard language:languageSegment cycleStart:cycleStart];
                        [runtime processRecognizedRealtimeText:ocrText items:ocrBlocks modalItems:modalScopedBlocks
                            duration:ocrDuration frame:frame trace:trace layoutDebug:layoutDebug host:runtimeHost];
    });
                  });
                });
            });
        });
}
@end
