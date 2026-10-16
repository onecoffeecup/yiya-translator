#import "FYTranslationRuntimeController.h"

#import "FYRealtimeRecognitionWorkflow.h"
#import "FYRealtimeContentPreparation.h"
#import "FYRealtimeContentAdmission.h"
#import "FYRealtimeRequestWorkflow.h"
#import "FYRealtimeResultDelivery.h"

@interface FYTranslationRuntimeController ()
@property(nonatomic, strong) FYRealtimeRecognitionWorkflow *recognitionWorkflow;
@property(nonatomic, strong) FYRealtimeContentPreparation *contentPreparation;
@property(nonatomic, strong) FYRealtimeContentAdmission *contentAdmission;
@property(nonatomic, strong) FYRealtimeRequestWorkflow *requestWorkflow;
@property(nonatomic, strong) FYRealtimeResultDelivery *resultDelivery;
@end

@implementation FYTranslationRuntimeController
@dynamic ocrRefinementContext, ocrRefinementStabilizer;
@dynamic running, timer, inFlight, ocrGeometryGeneration, ocrDisplayTargetWindowID, lastOCRedCaptureFrameIndex;
@dynamic inlineCacheOwner, inlineTranslationSerial, pendingInlineLongBatch, dialogueTranslationCache, translationTaskOwner;
@dynamic contentTranslationRevision, contentTranslationOperations, contentTranslationText, contentTranslationMode, contentTranslationUIItems, contentTranslationGeometryGeneration, contentTranslationDisplayTarget;
- (instancetype)initWithHost:(id<FYTranslationRuntimeControllerHost>)host {
    if ((self = [super init])) {
        _host = host; _contentState = [FYContentTranslationState new];
        _recognitionWorkflow=[FYRealtimeRecognitionWorkflow new];
        _contentPreparation=[FYRealtimeContentPreparation new];
        _contentAdmission=[FYRealtimeContentAdmission new];
        _requestWorkflow=[FYRealtimeRequestWorkflow new];
        _resultDelivery=[FYRealtimeResultDelivery new];
        _recognitionScheduler = [FYRecognitionCycleScheduler new];
        _refinementSession = [FYOCRRefinementSession new];
        _ocrWorker = [FYOCRRecognitionWorker new];
        _inlineCoordinator = [FYInlineTranslationCoordinator new];
        _requestCoordinator = [[FYTranslationRequestCoordinator alloc] initWithTransport:[FYSystemTranslationRequestTransport new]];
    }
    return self;
}



#pragma mark - OCR cycle adapters (native actions and one-way diagnostics)
- (FYOCRRecognitionOperationLease *)ocrOperationsForHost:(id<FYTranslationRuntimeControllerHost>)host layoutDebug:(NSDictionary *)layoutDebug {
    return [[FYOCRRecognitionOperationLease alloc] initWithBlocks:^NSString *(CGImageRef image,FYOCRRecognitionSettings *s,NSArray **blocks,NSError **error) {
        return [host recognizeTextBlocksInImage:image fastOCR:s.fastOCR languageSegment:s.language blocks:blocks error:error];
    } items:^NSArray *(CGImageRef image,FYOCRRecognitionSettings *s,NSError **error) {
        return [host recognizeTextItemsInImage:image fastOCR:s.fastOCR languageSegment:s.language error:error];
    } enlarged:^NSString *(CGImageRef image,CGRect region,FYOCRRecognitionSettings *s,NSArray **blocks,NSError **error) {
        return [host recognizeEnlargedRegionOfImage:image regionX:region.origin.x regionY:region.origin.y
            regionWidth:region.size.width regionHeight:region.size.height fastOCR:s.fastOCR languageSegment:s.language blocks:blocks error:error];
    } sourceText:^NSString *(NSArray *items,NSArray **blocks) { return [FYOCRManager sourceTextForItems:items blocks:blocks];
    } speakers:^NSArray *(NSArray *items,CGImageRef image) { return [FYOCRManager itemsByMarkingSpeakerLabels:items inImage:image];
    } modal:^NSArray *(NSArray *items,CGImageRef image,NSArray *exclusions) {
        return [host blocksInsideModalIfPresent:items inImage:image normalizedExclusions:exclusions];
    } manualPass1:^(void (^work)(void)) { FYLayoutDebugPerform(layoutDebug,work); }];
}
- (FYOCRWorkerObserver)ocrObserverForTrace:(NSDictionary *)trace layoutDebug:(NSDictionary *)layoutDebug
    windowID:(uint32_t)windowID generation:(NSInteger)generation frameIndex:(uint64_t)frameIndex
    language:(NSInteger)language fastOCR:(BOOL)fastOCR {
    return ^(FYOCRWorkerStage stage,FYOCRWorkerProgress *p,CGImageRef image) {
        switch(stage) {
            case FYOCRWorkerBegin: FYTrace(trace,@"task",@{@"reason":@"ocr_started"}); break;
            case FYOCRWorkerDiagnosticImage:
                if(FuyiDiagEnabled()) {
                    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithCGImage:image];
                    NSData *png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                    FYWritePrivateDiagnosticData(png,@"yiya-last-frame.png",NO);
                }
                break;
            case FYOCRWorkerRawCrop:
                FYTrace(trace,@"ocr",@{@"stage":@"vision_raw_crop",@"ocr_lines":FYTraceOCRLines(p.items),@"blocks":@(p.items.count),@"error_code":@(p.error.code)});
                break;
            case FYOCRWorkerMappedPass1: [[FYInlineLayoutDebug shared] recordItems:p.items stage:@"mapped_pass1" context:layoutDebug]; break;
            case FYOCRWorkerPass1Complete:
                [[FYRuntimeDiagnostics shared] recordEvent:@"ocr" fields:@{@"window_id":@(windowID),@"generation":@(generation),@"blocks":@(p.items.count),@"error_code":@(p.error.code),@"elapsed_ms":@(p.elapsed*1000),@"width":@(CGImageGetWidth(image)),@"height":@(CGImageGetHeight(image))}];
                FYTrace(trace,@"ocr",@{@"stage":@"pass1_filtered",@"ocr_lines":FYTraceOCRLines(p.items),@"blocks":@(p.items.count),@"fast_ocr":@(fastOCR),@"language":@(language),@"width":@(CGImageGetWidth(image)),@"height":@(CGImageGetHeight(image)),@"frame_index":@(frameIndex),@"elapsed_ms":@(p.elapsed*1000)});
                break;
            case FYOCRWorkerRefinementSelection:
                FYTrace(trace,@"ocr",@{@"stage":@"refinement_selection",@"reason":@"stable_pass1",@"blocks":@(p.fallbackCount)}); break;
            case FYOCRWorkerRefinementPerformance:
                FuyiDiagLog(@"  OCR pass1=%.2fs pass2=%.2fs total=%.2fs blocks=%lu",p.pass1,p.pass2,p.elapsed,(unsigned long)p.items.count); break;
            case FYOCRWorkerModalPerformance:
                FuyiDiagLog(@"  MODAL %lu -> %lu blocks in %.3fs",(unsigned long)p.items.count,(unsigned long)p.modalItems.count,p.elapsed); break;
            case FYOCRWorkerMerged:
                FYTrace(trace,@"ocr",@{@"stage":@"merged",@"ocr_lines":FYTraceOCRLines(p.items),@"blocks":@(p.items.count)});
                FYTrace(trace,@"ocr",@{@"stage":@"modal_scoped",@"ocr_lines":FYTraceOCRLines(p.modalItems),@"blocks":@(p.modalItems.count)}); break;
            case FYOCRWorkerReleasedImage: FYTrace(trace,@"task",@{@"reason":@"ocr_finished",@"error_code":@(p.error.code)}); break;
        }
    };
}

#pragma mark - Refinement compatibility state (single context owner)
- (NSDictionary *)ocrRefinementContext { return self.refinementSession.legacyContext; }
- (void)setOcrRefinementContext:(NSDictionary *)value { self.refinementSession.legacyContext = value; }
- (FYOCRRefinementStabilizer *)ocrRefinementStabilizer { return self.refinementSession.stabilizer; }
- (void)setOcrRefinementStabilizer:(FYOCRRefinementStabilizer *)value { self.refinementSession.stabilizer = value; }

#pragma mark - Recognition compatibility state (single scheduler owner)

- (BOOL)running { return self.recognitionScheduler.running; }
- (void)setRunning:(BOOL)value { self.recognitionScheduler.running = value; }
- (NSTimer *)timer { return self.recognitionScheduler.timer; }
- (void)setTimer:(NSTimer *)value { self.recognitionScheduler.timer = value; }
- (BOOL)inFlight { return self.recognitionScheduler.inFlight; }
- (void)setInFlight:(BOOL)value { self.recognitionScheduler.inFlight = value; }
- (NSInteger)ocrGeometryGeneration { return self.recognitionScheduler.geometryGeneration; }
- (void)setOcrGeometryGeneration:(NSInteger)value { self.recognitionScheduler.geometryGeneration = value; }
- (uint32_t)ocrDisplayTargetWindowID { return self.recognitionScheduler.displayTargetWindowID; }
- (void)setOcrDisplayTargetWindowID:(uint32_t)value { self.recognitionScheduler.displayTargetWindowID = value; }
- (uint64_t)lastOCRedCaptureFrameIndex { return self.recognitionScheduler.lastRecognizedFrameIndex; }
- (void)setLastOCRedCaptureFrameIndex:(uint64_t)value { self.recognitionScheduler.lastRecognizedFrameIndex = value; }

- (FYRecognitionCycleLease *)recognitionLeaseForHost:(id<FYTranslationRuntimeControllerHost>)host {
    // This lease keeps the original receiver alive for precisely the queued
    // cycle. Idle components still use their existing weak host references.
    return [[FYRecognitionCycleLease alloc] initWithGeneration:^{ return host.translationGeneration; }
        running:^{ return host.running; } windowID:^{ return [host displayTargetWindowID]; }
        inputEpoch:^{ return host.captureCardInput.sessionEpoch; }];
}

#pragma mark - Request/cache compatibility state

- (FYInlineTranslationCache *)inlineCacheOwner { return self.inlineCoordinator.cache; }
- (void)setInlineCacheOwner:(FYInlineTranslationCache *)value { self.inlineCoordinator.cache = value; }

- (NSUInteger)inlineTranslationSerial { return self.inlineCoordinator.serial; }
- (void)setInlineTranslationSerial:(NSUInteger)value { self.inlineCoordinator.serial = value; }

- (FYInlinePendingLongBatch *)pendingInlineLongBatch { return self.inlineCoordinator.pendingLongBatch; }
- (void)setPendingInlineLongBatch:(FYInlinePendingLongBatch *)value { self.inlineCoordinator.pendingLongBatch = value; }

- (FYTranslationCache *)dialogueTranslationCache { return self.inlineCoordinator.dialogueCache; }
- (void)setDialogueTranslationCache:(FYTranslationCache *)value { self.inlineCoordinator.dialogueCache = value; }

- (FYTranslationTaskOwner *)translationTaskOwner { return self.requestCoordinator.realtimeTaskOwner; }
- (void)setTranslationTaskOwner:(FYTranslationTaskOwner *)value { self.requestCoordinator.realtimeTaskOwner = value; }

#pragma mark - Content compatibility state (single content owner)

- (NSUInteger)contentTranslationRevision { return self.contentState.revision; }
- (void)setContentTranslationRevision:(NSUInteger)value { self.contentState.revision = value; }

- (NSUInteger)contentTranslationOperations { return self.contentState.operations; }
- (void)setContentTranslationOperations:(NSUInteger)value { self.contentState.operations = value; }

- (NSString *)contentTranslationText { return self.contentState.text; }
- (void)setContentTranslationText:(NSString *)value { self.contentState.text = value; }

- (NSInteger)contentTranslationMode { return self.contentState.mode; }
- (void)setContentTranslationMode:(NSInteger)value { self.contentState.mode = value; }

- (NSArray<OCRTextItem *> *)contentTranslationUIItems { return self.contentState.items; }
- (void)setContentTranslationUIItems:(NSArray<OCRTextItem *> *)value { self.contentState.items = value; }

- (NSInteger)contentTranslationGeometryGeneration { return self.contentState.geometryGeneration; }
- (void)setContentTranslationGeometryGeneration:(NSInteger)value { self.contentState.geometryGeneration = value; }

- (uint32_t)contentTranslationDisplayTarget { return self.contentState.displayTarget; }
- (void)setContentTranslationDisplayTarget:(uint32_t)value { self.contentState.displayTarget = value; }

#pragma mark - Lazy delivery adapter (UI/resources remain here)

- (NSInteger)deliveryGeneration { return self.host.translationGeneration; }
- (BOOL)deliveryIsRunning { return self.host.running; }
- (uint32_t)deliveryWindowID { return [self.host displayTargetWindowID]; }
- (NSUInteger)deliveryInputEpoch { return self.host.captureCardInput.sessionEpoch; }
- (NSInteger)deliveryMode { return [self.host effectiveModeSegment]; }
- (NSUInteger)deliveryContentRevision { return self.contentState.revision; }
- (NSInteger)deliveryGeometryGeneration { return self.host.geometryGeneration; }

- (NSURLSessionDataTask *)activeTranslationTask {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; return runtimeHost.translationTaskOwner.activeTask; }

- (void)setActiveTranslationTask:(NSURLSessionDataTask *)task {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    if (!runtimeHost.translationTaskOwner) { runtimeHost.translationTaskOwner = [FYTranslationTaskOwner new]; }
    runtimeHost.translationTaskOwner.activeTask = task;
}

- (void)invalidateContentTranslation {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    if (runtimeHost.contentTranslationOperations) {
        // A cancelled attempt must not delay a new occurrence of that sentence.
        runtimeHost.lastSubmittedNormalizedText = nil;
        runtimeHost.lastTranslationAttemptDate = nil;
    }
    [self.contentState advanceRevision];
    [self.inlineCoordinator advanceSerial];
    [self.inlineCoordinator discardPendingLongBatch];
    [self.contentState clearPending];
    [runtimeHost.translationTaskOwner cancelActiveTask];
}

- (BOOL)pendingContentMatchesText:(NSString *)text mode:(NSInteger)mode {
    id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    return [self.contentState matchesText:text mode:mode equivalent:^BOOL(NSString *current, NSString *previous) {
        return [runtimeHost isSameSubtitleText:current comparedTo:previous];
    }];
}

- (BOOL)pendingInlineMatchesItems:(NSArray<OCRTextItem *> *)items {
    id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    return [self.contentState matchesItems:items key:^NSString *(OCRTextItem *item) {
        return [runtimeHost inlineTranslationCacheKeyForItem:item];
    }];
}

- (NSUInteger)beginContentTranslation:(NSString *)text mode:(NSInteger)mode {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    [runtimeHost invalidateContentTranslation];
    [self.contentState beginText:text mode:mode];
    runtimeHost.lastSubmittedNormalizedText = text;
    runtimeHost.lastTranslationAttemptDate = [runtimeHost translationProcessingDate];
    [self.contentState updateGeometryGeneration:runtimeHost.ocrGeometryGeneration
        displayTarget:runtimeHost.ocrDisplayTargetWindowID];
    return runtimeHost.contentTranslationRevision;
}

- (NSArray<NSString *> *)longInlineKeysForItems:(NSArray<OCRTextItem *> *)items {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    NSMutableArray<NSString *> *keys = [NSMutableArray new];
    for (OCRTextItem *item in items) {
        if (item.blockKind == InlineBlockKindLong) { [keys addObject:[runtimeHost inlineTranslationCacheKeyForItem:item]]; }
    }
    return [keys sortedArrayUsingSelector:@selector(compare:)];
}

- (NSUInteger)beginInlineContentTranslation:(NSString *)text items:(NSArray<OCRTextItem *> *)items trace:(NSDictionary *)trace {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    FYInlinePendingLongBatch *batch = runtimeHost.pendingInlineLongBatch;
    if (![self.inlineCoordinator retainsLongBatchForContent:[self.contentState snapshot]
        newKeys:^NSArray * { return [runtimeHost longInlineKeysForItems:items]; }
        existingKeys:^NSArray * { return [runtimeHost longInlineKeysForItems:runtimeHost.contentTranslationUIItems]; }]) {
        return [runtimeHost beginContentTranslation:text mode:ContentModeUI];
    }
    // Only short fields changed. Keep the long HTTP task and its transport
    // revision, but replace the UI plan so old short results cannot be applied.
    [self.inlineCoordinator advanceSerial];
    [self.inlineCoordinator clearPendingLongCompletions];
    [runtimeHost.translationTaskOwner cancelTasksExceptTask:batch.task];
    [self.contentState replacePendingText:text];
    runtimeHost.lastSubmittedNormalizedText = text;
    runtimeHost.lastTranslationAttemptDate = [runtimeHost translationProcessingDate];
    [self.contentState updateGeometryGeneration:runtimeHost.ocrGeometryGeneration
        displayTarget:runtimeHost.ocrDisplayTargetWindowID];
    FYTrace(trace, @"task", @{@"reason": @"inline_long_batch_retained"});
    return runtimeHost.contentTranslationRevision;
}

- (void)finishContentTranslation:(NSUInteger)revision { [self.contentState finishRevision:revision]; }

- (void)advanceTranslationGeneration {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    runtimeHost.translationGeneration += 1;
    [runtimeHost invalidatePreviewResults];
    [runtimeHost invalidateContentTranslation];
}

- (void)toggleRunning:(id)sender {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    runtimeHost.running ? [runtimeHost stop] : [runtimeHost start];
}

- (void)start {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    if (runtimeHost.running) { return; }
    [runtimeHost updateRuntimeDiagnostics];
    [[FYRuntimeDiagnostics shared] recordEvent:@"start" fields:@{@"window_id": @([runtimeHost selectedWindowID]), @"input_source": @([runtimeHost captureCardInputEnabled] ? 1 : 0)}];
    if ([runtimeHost selectedWindowID] && (FYWindowOwnerIsYiya([runtimeHost selectedWindowItem].effectiveOwnerName) || [runtimeHost selectedWindowOwnerPID] == getpid())) {
        [runtimeHost setStatus:@"不能把译芽自身作为画面来源。请刷新列表，重新选择 QuickTime／OBS 或游戏窗口。"];
        return;
    }
    if (![runtimeHost captureCardInputEnabled] && ![runtimeHost hasScreenAccess] && ![runtimeHost selectedWindowID]) {
        [runtimeHost handleMissingScreenAccessForStart];
        return;
    }

    if (![runtimeHost selectedWindowID]) {
        [runtimeHost setStatus:[runtimeHost captureCardInputEnabled] ? @"请先选择游戏画面所在的显示窗口（QuickTime／OBS）"
                                                       : @"请先选择要翻译的窗口（QuickTime／OBS）"];
        return;
    }

    if ([runtimeHost captureCardInputEnabled]) {
        // 采集卡模式不需要屏幕录制权限。相机权限在这里（用户点了「开始翻译」）按需申请：
        // 第一次弹系统提示，批准后自动继续；已被拒绝时系统不会再弹，只给设置入口。
        if ([runtimeHost.captureCardInput availability] != FYCaptureCardAvailabilityAuthorized) {
            __weak typeof(runtimeHost) weakSelf = runtimeHost;
            [runtimeHost ensureCaptureCardPermissionThen:^(BOOL granted) {
                typeof(runtimeHost) strongSelf = weakSelf;
                if (!strongSelf) { return; }
                if (granted) { [strongSelf start]; } else { [strongSelf updateCaptureCardStatus]; }
            }];
            return;
        }
        if (![runtimeHost startCaptureCardSessionIfPossible]) { return; }
    } else if (![runtimeHost hasUsableScreenCaptureAccess]) {
        [runtimeHost handleMissingScreenAccessForStart];
        return;
    }

    runtimeHost.lastOCRedCaptureFrameIndex = 0;
    runtimeHost.running = YES;
    runtimeHost.captureUnavailable = NO;
    runtimeHost.runButton.title = @"暂停翻译";
    [runtimeHost updateRunState];
    [runtimeHost advanceTranslationGeneration];
    [[runtimeHost translationState] reset];
    [[runtimeHost stabilityOwner] reset];
    [runtimeHost setStatus:@"正在监测画面"];
    [runtimeHost restartPreviewTimerIfRunning];

    [self.recognitionScheduler scheduleTimerWithInterval:[runtimeHost recognitionPollingInterval] target:runtimeHost];
    [runtimeHost timerFired:runtimeHost.timer];
}

- (void)stop {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    [[FYRuntimeDiagnostics shared] recordEvent:@"stop" fields:@{@"window_id": @([runtimeHost selectedWindowID])}];
    // 停采立刻释放采集会话并作废旧帧：暂停后不会再有画面进入 OCR。
    runtimeHost.captureCardInput.previewActive = NO;
    [runtimeHost.captureCardInput stop];
    runtimeHost.lastOCRedCaptureFrameIndex = 0;
    [self.recognitionScheduler invalidateTimer];
    [runtimeHost.previewTimer invalidate];
    runtimeHost.previewTimer = nil;
    runtimeHost.running = NO;
    runtimeHost.captureUnavailable = NO;
    runtimeHost.inFlight = NO;
    [runtimeHost advanceTranslationGeneration];
    // 停止时把自己画在桌面上的东西收干净：贴译面板会留在屏幕上一直不走，
    // 因为它们由定时循环负责清理，循环一停就没人管了。
    [runtimeHost clearInlineTranslationPanels];
    [[runtimeHost inlineCache] clear];
    runtimeHost.lastInlineTranslationKey = nil;
    [runtimeHost setCaptionPanelVisibleForUIMode:NO];
    runtimeHost.runButton.title = @"开始翻译";
    [runtimeHost updateRunState];
    [runtimeHost setStatus:@"已暂停"];
}

- (void)handleInlineTranslationResult:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items error:(NSError *)translationError failureStatus:(NSString *)failureStatus successPrefix:(NSString *)successPrefix {
    [self.resultDelivery handleInlineTranslationResult:translations forItems:items error:translationError
        failureStatus:failureStatus successPrefix:successPrefix runtime:(id<FYRealtimeResultRuntime>)self
        host:(id<FYRealtimeResultHost>)self.host];
}


- (void)timerFired:(NSTimer *)timer {
    [self.recognitionWorkflow tick:timer runtime:(id<FYRealtimeRecognitionRuntime>)self host:(id<FYRealtimeRecognitionHost>)self.host];
}


- (void)processRecognizedRealtimeText:(NSString *)ocrText items:(NSArray<OCRTextItem *> *)ocrBlocks modalItems:(NSArray<OCRTextItem *> *)modalScopedBlocks
    duration:(NSTimeInterval)ocrDuration frame:(FYRealtimeRecognitionFrame *)frame trace:(NSDictionary *)trace layoutDebug:(NSDictionary *)layoutDebug host:(id<FYTranslationRuntimeControllerHost>)runtimeHost {
    FYPreparedRealtimeContent *prepared=[self.contentPreparation prepareText:ocrText items:ocrBlocks modalItems:modalScopedBlocks
        duration:ocrDuration language:frame.language trace:trace layoutDebug:layoutDebug host:(id<FYRealtimeContentPreparationHost>)runtimeHost];
    if (!prepared) { return; }
    if (![self.contentAdmission admitContent:prepared rawText:ocrText items:ocrBlocks duration:ocrDuration trace:trace
        layoutDebug:layoutDebug host:(id<FYRealtimeContentAdmissionHost>)runtimeHost]) { return; }
    [self.requestWorkflow submitContent:prepared items:ocrBlocks duration:ocrDuration frame:frame trace:trace layoutDebug:layoutDebug
        runtime:(id<FYRealtimeRequestRuntime>)self host:(id<FYRealtimeRequestHost>)runtimeHost];
}

- (void)translateCurrentInterface:(id)sender {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    if (runtimeHost.inFlight) {
        [runtimeHost setStatus:@"正在处理上一条识别"];
        return;
    }

    BOOL captureCard = [runtimeHost captureCardInputEnabled];
    if (![runtimeHost selectedWindowID]) {
        [runtimeHost setStatus:[runtimeHost captureCardInputEnabled] ? @"请先选择游戏画面所在的显示窗口" : @"请先选择要翻译的窗口"];
        return;
    }
    if (!captureCard && ![runtimeHost hasUsableScreenCaptureAccess]) {
        [runtimeHost handleMissingScreenAccessForStart];
        return;
    }

    [runtimeHost invalidateContentTranslation];
    [self.recognitionScheduler beginCycle];
    NSInteger cycleGeneration = runtimeHost.translationGeneration;
    // 和实时循环一致：识别与贴译都用**实际承载游戏画面的窗口**。
    [runtimeHost refreshDisplayGeometryIfNeeded:YES];
    uint32_t windowID = [runtimeHost displayTargetWindowID];
    if (windowID == 0) {
        [self.recognitionScheduler finishCurrentCycle];
        [runtimeHost hideInlineTranslationPanelsForGeometryChange];
        [runtimeHost setStatus:@"检测到多个可能是游戏画面的窗口，请重新选择显示窗口"];
        return;
    }
    runtimeHost.ocrDisplayTargetWindowID = windowID;
    runtimeHost.ocrGeometryGeneration = runtimeHost.geometryGeneration;
    NSUInteger inputEpoch = runtimeHost.captureCardInput.sessionEpoch;
    FYRecognitionCycleIdentity *cycle = [[FYRecognitionCycleIdentity alloc] initWithGeneration:cycleGeneration
        windowID:windowID inputEpoch:inputEpoch kind:FYRecognitionCycleManual];
    FYRecognitionCycleLease *cycleLease = [self recognitionLeaseForHost:runtimeHost];
    dispatch_async(runtimeHost.captureQueue, ^{
        CGImageRef image = captureCard ? [runtimeHost.captureCardInput copyLatestFrame] : [runtimeHost copyFullCapturedImageForWindow:windowID];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([cycle captureDropReasonWithLease:cycleLease]) {
                if (image) { CGImageRelease(image); }
                [self.recognitionScheduler finishCycle:cycle lease:cycleLease];
                return;
            }
            if (!image) {
                [self.recognitionScheduler finishCurrentCycle];
                if (!captureCard && [runtimeHost recoverWindowSelectionIfRecreated]) {
                    if (!runtimeHost.running) { [runtimeHost translateCurrentInterface:sender]; }
                    return;
                }
                NSString *message = captureCard ? @"采集卡暂无可用画面，请等画面恢复后再翻译当前界面。"
                                                : @"无法截取目标窗口";
                [runtimeHost showPreviewUnavailable:message];
                [runtimeHost setStatus:message];
                return;
            }
            [runtimeHost updatePreviewFromImage:image generation:cycleGeneration];

            NSInteger languageSegment = runtimeHost.languageControl.selectedSegment;
            runtimeHost.learningCoordinator.japaneseMode = (languageSegment == 0);
            [runtimeHost setStatus:@"正在识别当前界面"];
            CGRect ocrScope=[runtimeHost selectedOCRScope];
            NSDictionary *layoutDebug=[[FYInlineLayoutDebug shared] beginFrameWithImage:image metadata:@{
                @"window_id":@(windowID), @"generation":@(cycleGeneration), @"geometry_generation":@(runtimeHost.geometryGeneration),
                @"input_source":@(captureCard), @"input_epoch":@(inputEpoch), @"scope":FYLayoutDebugRect(ocrScope)}];
            FYOCRRecognitionImageLease *imageLease = [[FYOCRRecognitionImageLease alloc] initWithOwnedImage:image];
            FYOCRRecognitionSettings *recognitionSettings = [[FYOCRRecognitionSettings alloc] initWithManual:YES
                language:languageSegment fastOCR:NO autoFit:NO scope:ocrScope exclusions:@[]];
            FYOCRRecognitionOperationLease *operations = [self ocrOperationsForHost:runtimeHost layoutDebug:layoutDebug];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                FYOCRRecognitionResult *result = [self.ocrWorker recognizeImageLease:imageLease settings:recognitionSettings
                    refinement:nil operations:operations cropScope:^(CGRect crop,CGSize size,void(^work)(void)) {
                        FYLayoutDebugPerformCrop(crop,size,work);
                    } observer:^(FYOCRWorkerStage stage,FYOCRWorkerProgress *progress,CGImageRef pixels) {
                        [[FYInlineLayoutDebug shared] recordItems:progress.items stage:@"mapped_pass1" context:layoutDebug];
                    }];
                NSError *error = result.error;
                NSArray<OCRTextItem *> *blocks = result.modalItems;
                NSTimeInterval ocrDuration = result.duration;

                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([cycle recognitionDropReasonWithLease:cycleLease]) {
                        [self.recognitionScheduler finishCycle:cycle lease:cycleLease];
                        return;
                    }
                    runtimeHost.ocrDurationLabel.stringValue = [NSString stringWithFormat:@"最近识别  %.2f 秒", ocrDuration];
                    if (error) {
                        [runtimeHost showError:error.localizedDescription];
                        [runtimeHost setStatus:@"当前界面 OCR 出错"];
                        [self.recognitionScheduler finishCurrentCycle];
                        return;
                    }

                    // 「翻译当前界面」与实时界面路径同源：分块 → 过滤 → 贴译（长短卡 + 映射）。
                    NSMutableArray<OCRTextItem *> *uiItems = [[runtimeHost filteredInlineTextItems:[runtimeHost mergedInlineTextItemsFromItems:blocks] strict:NO] mutableCopy];
                    [[FYInlineLayoutDebug shared] recordItems:uiItems stage:@"inline_grouped" context:layoutDebug];
                    if (uiItems.count == 0) {
                        [runtimeHost setStatus:[NSString stringWithFormat:@"当前界面没有识别到可译文字 · OCR %.1fs", ocrDuration]];
                        [self.recognitionScheduler finishCurrentCycle];
                        return;
                    }
                    NSArray<OCRTextItem *> *uiItemsForRender = [uiItems copy];
                    NSArray<FYRequestIdentity *> *uiIdentities = [runtimeHost.learningCoordinator recordItems:[runtimeHost textsFromItems:uiItemsForRender] kind:FYSentenceKindUI];
                    [runtimeHost refreshLearningSource];
                    [runtimeHost refreshLearningStatus];
                    NSDictionary *uiTrace = [[FYTranslationTrace shared] requestContextForCycle:FYCurrentTrace()];
                    NSDate *translationStart = [NSDate date];
                    [runtimeHost setStatus:[NSString stringWithFormat:@"正在翻译当前界面 · OCR %.1fs", ocrDuration]];
                    FYInlineDebugTracePerform(uiTrace, layoutDebug, ^{
                    [runtimeHost translateInlineTextItems:uiItemsForRender completion:^(NSArray<NSString *> *translations, NSError *translationError) {
                        if ([cycle recognitionDropReasonWithLease:cycleLease]) {
                            [self.recognitionScheduler finishCycle:cycle lease:cycleLease];
                            return;
                        }
                        runtimeHost.translationDurationLabel.stringValue = [NSString stringWithFormat:@"翻译耗时  %.2f 秒", [[NSDate date] timeIntervalSinceDate:translationStart]];
                        [runtimeHost bindTranslations:translations toIdentities:uiIdentities];
                        [runtimeHost refreshLearningSource];
                        [runtimeHost refreshLearningStatus];
                        FYInlineDebugTracePerform(uiTrace, layoutDebug, ^{
                            [runtimeHost handleInlineTranslationResult:translations forItems:uiItemsForRender error:translationError failureStatus:@"界面翻译出错" successPrefix:@"界面译文已更新"];
                        });
                        if (!translationError) {
                            runtimeHost.translationCount += 1;
                            [runtimeHost updateTranslationCount];
                        }
                        [self.recognitionScheduler finishCurrentCycle];
                    }];
                    });
                });
            });
        });
    });
}

- (NSArray<OCRTextItem *> *)mergedInlineTextItemsFromItems:(NSArray<OCRTextItem *> *)items {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    if (items.count == 0) { return @[]; }
    NSArray<OCRTextItem *> *visualLines = [FYOCRManager splitMultilineItems:items];
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray arrayWithCapacity:visualLines.count];
    for (NSUInteger index = 0; index < visualLines.count; index++) {
        OCRTextItem *item = visualLines[index];
        [lines addObject:[FYInlineTextLine lineWithText:(item.text ?: @"")
                                                   rect:item.boundingBox
                                             confidence:item.confidence
                                            sourceIndex:(NSInteger)index]];
    }
    NSArray<FYInlineTextBlock *> *blocks = [runtimeHost.inlineGrouper blocksFromLines:lines];
    NSMutableArray<OCRTextItem *> *result = [NSMutableArray arrayWithCapacity:blocks.count];
    for (FYInlineTextBlock *block in blocks) {
        OCRTextItem *item = [[OCRTextItem alloc] init];
        item.text = block.text;
        item.boundingBox = block.boundingBox;
        item.lastLineBox = block.lineBoxes.lastObject ? [block.lineBoxes.lastObject rectValue] : block.boundingBox;
        item.lineTexts = block.lineTexts;
        item.lineBoxes = block.lineBoxes;
        item.lineCount = block.lineCount;
        item.blockKind = block.kind == FYInlineBlockKindLong ? InlineBlockKindLong : InlineBlockKindShort;
        item.groupingConfidence = block.groupingConfidence;
        item.sourceBlockID = block.blockID;
        CGFloat confidenceSum = 0;
        for (NSNumber *value in block.lineConfidences) { confidenceSum += value.doubleValue; }
        item.confidence = block.lineConfidences.count > 0 ? confidenceSum / (CGFloat)block.lineConfidences.count : 0;
        [result addObject:item];
    }
    return result;
}

- (FYInlineTextBlock *)inlineLayoutBlockForItem:(OCRTextItem *)item order:(NSInteger)order {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    FYInlineTextBlock *block = [FYInlineTextBlock new];
    block.text = item.text ?: @"";
    NSArray<NSValue *> *boxes = item.lineBoxes.count > 0 ? item.lineBoxes
        : (item.boundingBox.size.width > 0 ? @[[NSValue valueWithRect:item.boundingBox]] : @[]);
    block.lineBoxes = boxes;
    NSMutableArray<NSString *> *lineTexts = [NSMutableArray array];
    NSArray<NSString *> *split = [block.text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSUInteger index = 0; index < boxes.count; index++) {
        [lineTexts addObject:index < split.count ? split[index] : @""];
    }
    if (lineTexts.count == 0) { [lineTexts addObject:block.text]; }
    block.lineTexts = lineTexts;
    block.boundingBox = item.boundingBox;
    block.kind = item.blockKind == InlineBlockKindLong ? FYInlineBlockKindLong : FYInlineBlockKindShort;
    block.groupingConfidence = item.groupingConfidence > 0 ? item.groupingConfidence : 1.0;
    block.sourceIndices = @[];
    block.readingOrder = order;
    block.blockID = [FYInlineBlockMatcher blockIDForText:block.text lineBoxes:boxes];
    return block;
}

- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    return [runtimeHost filteredInlineTextItems:items strict:YES];
}

- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items strict:(BOOL)strict {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    NSMutableArray<OCRTextItem *> *candidates = [NSMutableArray array];
    NSMutableArray<OCRTextItem *> *accepted = [NSMutableArray array];

    for (OCRTextItem *item in items) {
        NSString *text = Trim(item.text);
        NSString *normalized = NormalizeForComparison(text);
        if (normalized.length < 2) { continue; }
        // 重复识别按**文字 + 位置**联合去重：同一处的同文只留一条，
        // 不同位置的同文内容必须各自保留（两篇文章里的同一句话不能被删掉一条）。
        BOOL duplicate = NO;
        for (OCRTextItem *kept in accepted) {
            if (![NormalizeForComparison(kept.text) isEqualToString:normalized]) { continue; }
            if ([FYInlineBlockMatcher overlapRatio:item.boundingBox right:kept.boundingBox] < 0.5) { continue; }
            duplicate = YES;
            if (item.confidence > kept.confidence) { kept.confidence = item.confidence; }
            break;
        }
        if (duplicate) { continue; }
        if (item.boundingBox.size.height < 0.015 && normalized.length < 5) { continue; }
        if ([runtimeHost shouldIgnoreInlineText:text normalized:normalized boundingBox:item.boundingBox strict:strict]) { continue; }

        item.text = text;
        [accepted addObject:item];
        [candidates addObject:item];
    }

    // 过滤只判断观察本身是否有效，不按全屏块数截断。
    // 否则无关正文拆成两块就会挤掉一直存在的字段，跟踪器将这种删减误判为消失，
    // 继而让邻近译文换位、集中入口增减。空间不足由布局结果处理，译文仍完整列出。
    NSArray<OCRTextItem *> *readingOrder = [candidates sortedArrayUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) {
        CGFloat leftTop = CGRectGetMaxY(left.boundingBox);
        CGFloat rightTop = CGRectGetMaxY(right.boundingBox);
        if (fabs(leftTop - rightTop) > 0.025) {
            return leftTop > rightTop ? NSOrderedAscending : NSOrderedDescending;
        }
        if (left.boundingBox.origin.x < right.boundingBox.origin.x) { return NSOrderedAscending; }
        if (left.boundingBox.origin.x > right.boundingBox.origin.x) { return NSOrderedDescending; }
        return NSOrderedSame;
    }];

    // 按阅读顺序输出，按钮统一挪到队尾，不影响正文的先行布局。
    NSMutableArray<OCRTextItem *> *ordered = [NSMutableArray array];
    for (OCRTextItem *item in readingOrder) {
        if (![runtimeHost isButtonLikeInlineText:NormalizeForComparison(item.text)]) { [ordered addObject:item]; }
    }
    for (OCRTextItem *item in readingOrder) {
        if ([runtimeHost isButtonLikeInlineText:NormalizeForComparison(item.text)]) { [ordered addObject:item]; }
    }
    return ordered;
}

- (NSString *)dialogueTextFromItems:(NSArray<OCRTextItem *> *)items speakerLabelOnly:(BOOL *)speakerLabelOnly {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    return [FYContentRouter dialogueTextFromItems:items speakerLabelOnly:speakerLabelOnly
                                  filterObserver:FYContentFilterDiagnosticObserver()];
}

- (BOOL)shouldIgnoreInlineText:(NSString *)text normalized:(NSString *)normalized boundingBox:(CGRect)box strict:(BOOL)strict {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    FYContentTextFilterReason reason = [FYContentRouter filterReasonForText:text normalized:normalized
                                                             boundingBox:box strict:strict
                                                               japanese:runtimeHost.languageControl.selectedSegment == 0];
    if (reason != FYContentTextKeep) { FYContentFilterDiagnosticObserver()(text, box, reason); }
    return reason != FYContentTextKeep;
}

- (BOOL)isButtonLikeInlineText:(NSString *)normalized {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    if (normalized.length == 0 || normalized.length > 8) { return NO; }
    NSString *lower = normalized.lowercaseString;
    NSArray<NSString *> *buttonTokens = @[@"詳細", @"閉じる", @"戻る", @"戻", @"次へ", @"決定",
                                          @"設定", @"メニュー", @"スキップ", @"ルームへ",
                                          @"back", @"close", @"menu", @"next", @"ok",
                                          @"cancel", @"skip", @"setting", @"settings"];
    for (NSString *token in buttonTokens) {
        if ([lower isEqualToString:token] || [lower hasPrefix:token]) { return YES; }
    }
    return NO;
}

- (double)inlinePriorityForText:(NSString *)text normalized:(NSString *)normalized boundingBox:(CGRect)box {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    double score = 0;
    NSUInteger length = normalized.length;
    score += MIN(40.0, (double)length * 2.2);

    double area = box.size.width * box.size.height;
    score += MIN(18.0, area * 240.0);

    double centerX = CGRectGetMidX(box);
    double centerY = CGRectGetMidY(box);
    double distanceFromCenter = hypot(centerX - 0.5, centerY - 0.5);
    score += MAX(0, 22.0 - distanceFromCenter * 45.0);

    if (length >= 16) { score += 18; }
    if (length >= 28) { score += 15; }
    if (box.size.width > 0.30) { score += 12; }
    if (box.size.height > 0.045) { score += 8; }
    if (box.origin.y > 0.18 && CGRectGetMaxY(box) < 0.86) { score += 10; }

    NSString *lower = normalized.lowercaseString;
    // 按钮类排到最后：正文/条目优先，只有还有余量时才翻按钮
    if ([runtimeHost isButtonLikeInlineText:normalized]) { score -= 90; }
    if ([lower containsString:@"today"] || [lower containsString:@"news"] || [lower containsString:@"web"]) { score -= 25; }
    if (length <= 4) { score -= 18; }
    if (box.origin.y < 0.10 || CGRectGetMaxY(box) > 0.92) { score -= 20; }

    return score;
}

- (NSString *)inlineTranslationCacheKeyForItem:(OCRTextItem *)item {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    NSString *normalized = NormalizeForComparison(item.text);
    return item.blockKind == InlineBlockKindLong ? [@"L:" stringByAppendingString:normalized] : normalized;
}

- (id<FYInlineBatchTransport>)inlineBatchTransportLease {
    id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    return [[FYInlineBatchTransportLease alloc] initWithSnapshot:^FYContentTranslationSnapshot * { return [self.contentState snapshot]; }
        submit:^(FYInlineTranslationBatch *batch, NSMutableArray<NSString *> *translations, void (^completion)(NSError *)) {
            [runtimeHost translateInlineBatch:batch.items indexes:batch.indexes keys:batch.keys translations:translations long:batch.longText completion:completion];
        } submitLong:^(FYInlineTranslationBatch *batch, NSMutableArray<NSString *> *translations, void (^completion)(NSError *)) {
            [runtimeHost translateInlineLongItems:batch.items indexes:batch.indexes keys:batch.keys translations:translations completion:completion];
        } activeTask:^NSURLSessionDataTask * { return runtimeHost.translationTaskOwner.activeTask; }];
}

- (void)translateInlineTextItems:(NSArray<OCRTextItem *> *)items completion:(void (^)(NSArray<NSString *> *, NSError *))completion {
    id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    NSDictionary *trace = FYCurrentTrace();
    [self.inlineCoordinator translateItems:items key:^NSString *(OCRTextItem *item) { return [runtimeHost inlineTranslationCacheKeyForItem:item]; }
        isLong:^BOOL(OCRTextItem *item) { return item.blockKind == InlineBlockKindLong; }
        observer:^(NSUInteger index, BOOL hit) {
            FYTrace(trace, @"cache", @{@"route": @"inline", @"source": items[index].text ?: @"", @"cache_hit": @(hit)});
            if (FYCurrentLayoutDebug()) {
                NSMutableDictionary *context = [FYCurrentLayoutDebug() mutableCopy];
                context[@"block_id"] = [runtimeHost inlineBlockIdentityForItem:items[index]];
                [[FYInlineLayoutDebug shared] recordDecision:hit ? @"translation_cache_hit" : @"translation_cache_miss" context:context];
            }
        } transport:[self inlineBatchTransportLease] completion:completion];
}

- (void)translateInlineLongItems:(NSArray<OCRTextItem *> *)items indexes:(NSArray<NSNumber *> *)indexes
    keys:(NSArray<NSString *> *)keys translations:(NSMutableArray<NSString *> *)translations completion:(void (^)(NSError *))completion {
    FYInlineTranslationBatch *batch = [[FYInlineTranslationBatch alloc] initWithItems:items indexes:indexes keys:keys longText:YES];
    [self.inlineCoordinator translateRetainedLongBatch:batch translations:translations transport:[self inlineBatchTransportLease] completion:completion];
}

- (void)translateInlineBatch:(NSArray<OCRTextItem *> *)items
                     indexes:(NSArray<NSNumber *> *)indexes
                        keys:(NSArray<NSString *> *)keys
                translations:(NSMutableArray<NSString *> *)translations
                        long:(BOOL)isLong
                  completion:(void (^)(NSError *error))completion {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    NSString *numberedText = FYNumberedTranslationSource(items.count, ^NSString *(NSUInteger index) { return items[index].text; });

    NSString *source = SourceLanguageLabel(runtimeHost.languageControl.selectedSegment);
    NSString *prompt = FYInlineBatchPrompt(source, isLong);
    NSInteger maxTokens = FYInlineBatchMaxTokens(items.count, isLong);
    NSUInteger inlineSerial = runtimeHost.inlineTranslationSerial;

    [runtimeHost translateText:numberedText systemPrompt:prompt maxTokens:maxTokens
        modelOverride:nil
        longText:isLong serviceTest:NO completion:^(NSString *translated, NSError *error) {
        FYInlineTranslationBatch *batch = [[FYInlineTranslationBatch alloc] initWithItems:items indexes:indexes keys:keys longText:isLong];
        [self.inlineCoordinator applyText:translated error:error batch:batch translations:translations submittedSerial:inlineSerial
            parse:^NSArray *(NSString *value, NSUInteger count) { return [runtimeHost parseNumberedTranslations:value expectedCount:count]; }
            cache:^(NSString *value, NSString *key) { [runtimeHost cacheInlineTranslation:value forKey:key]; } completion:completion];
    }];
}

- (void)cacheInlineTranslation:(NSString *)value forKey:(NSString *)key {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    [[runtimeHost inlineCache] storeValue:value forKey:key];
}

- (NSArray<NSString *> *)parseNumberedTranslations:(NSString *)text expectedCount:(NSUInteger)count {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    return FYParseNumberedTranslations(text, count);
}

- (FYInlineOCRFrameStabilizer *)inlineFrameStabilizer {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    if (!_inlineFrameStabilizer) { _inlineFrameStabilizer = [FYInlineOCRFrameStabilizer new]; }
    return _inlineFrameStabilizer;
}

- (FYInlineGrouper *)inlineGrouper {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    if (!_inlineGrouper) {
        FYInlineGrouper *grouper = [FYInlineGrouper defaultGrouper];
        __weak typeof(runtimeHost) weakSelf = runtimeHost;
        grouper.shortLabelDetector = ^BOOL(NSString *normalizedText) {
            return [weakSelf isButtonLikeInlineText:normalizedText];
        };
        _inlineGrouper = grouper;
    }
    return _inlineGrouper;
}

- (void)translateText:(NSString *)text completion:(void (^)(NSString *translated, NSError *error))completion {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    [runtimeHost translateText:text
           systemPrompt:[runtimeHost systemPrompt]
              maxTokens:240
             completion:completion];
}

- (void)translateText:(NSString *)text systemPrompt:(NSString *)systemPrompt maxTokens:(NSInteger)maxTokens completion:(void (^)(NSString *translated, NSError *error))completion {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    [runtimeHost translateText:text
           systemPrompt:systemPrompt
              maxTokens:maxTokens
          modelOverride:nil
             completion:completion];
}

- (void)translateDialogueText:(NSString *)text
                     identity:(FYRequestIdentity *)identity
                 systemPrompt:(NSString *)systemPrompt
                   completion:(void (^)(NSString *translated, NSError *error))completion {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    NSDictionary *trace = FYCurrentTrace();
    NSInteger generation = runtimeHost.translationGeneration;
    NSInteger serviceGeneration = runtimeHost.serviceTestGeneration;
    NSString *key = FYTranslationCacheKey(generation, serviceGeneration, identity.sentenceID, identity.version, text, systemPrompt);
    NSString *cached = [runtimeHost.dialogueTranslationCache valueForKey:key];
    if (cached) {
        FYTrace(trace, @"cache", @{@"route": @"dialogue", @"cache_hit": @YES, @"sentence_id": identity.sentenceID ?: @"", @"version": @(identity.version)});
        completion(cached, nil);
        return;
    }
    FYTrace(trace, @"cache", @{@"route": @"dialogue", @"cache_hit": @NO, @"reason": key ? @"key_or_value_miss" : @"no_sentence_identity", @"sentence_id": identity.sentenceID ?: @"", @"version": @(identity.version)});
    [runtimeHost translateTextRealtime:text systemPrompt:systemPrompt maxTokens:240 completion:^(NSString *translated, NSError *error) {
        if (key && !error && FYTranslationCacheCanStore(generation, runtimeHost.translationGeneration,
                                                       serviceGeneration, runtimeHost.serviceTestGeneration, translated)) {
            if (!runtimeHost.dialogueTranslationCache) { runtimeHost.dialogueTranslationCache = [FYTranslationCache new]; }
            [runtimeHost.dialogueTranslationCache storeValue:translated forKey:key];
        }
        completion(translated, error);
    }];
}

- (void)translateTextRealtime:(NSString *)text
                 systemPrompt:(NSString *)systemPrompt
                    maxTokens:(NSInteger)maxTokens
                   completion:(void (^)(NSString *translated, NSError *error))completion {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    [runtimeHost translateText:text
           systemPrompt:systemPrompt
              maxTokens:maxTokens
          modelOverride:nil
             completion:completion];
}

- (void)translateText:(NSString *)text
          systemPrompt:(NSString *)systemPrompt
             maxTokens:(NSInteger)maxTokens
         modelOverride:(NSString *)modelOverride
            completion:(void (^)(NSString *translated, NSError *error))completion {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    [runtimeHost translateText:text systemPrompt:systemPrompt maxTokens:maxTokens modelOverride:modelOverride
        longText:NO serviceTest:NO completion:completion];
}

- (void)translateText:(NSString *)text systemPrompt:(NSString *)systemPrompt maxTokens:(NSInteger)maxTokens
        modelOverride:(NSString *)modelOverride longText:(BOOL)longText serviceTest:(BOOL)serviceTest
        completion:(void (^)(NSString *, NSError *))completion {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    NSDictionary *trace = FYCurrentTrace();
    FYPreparedTranslationRequest *prepared = [FYPreparedTranslationRequest prepareText:text
        configuration:[runtimeHost translationConfiguration] systemPrompt:systemPrompt defaultPrompt:^NSString * { return [runtimeHost systemPrompt]; }
        maxTokens:maxTokens modelOverride:modelOverride longText:longText];
    if (!prepared.request) {
        if (prepared.failureReason) { FYTrace(trace, @"request_complete", @{@"reason": prepared.failureReason, @"success": @NO, @"error_code": @(prepared.error.code)}); }
        completion(nil, prepared.error); return;
    }

    if (trace) {
        NSMutableDictionary *taskTrace = [trace mutableCopy];
        taskTrace[@"http_task_id"] = NSUUID.UUID.UUIDString;
        trace = [taskTrace copy];
    }
    if (serviceTest && !runtimeHost.serviceTestTaskOwner) { runtimeHost.serviceTestTaskOwner = [FYTranslationTaskOwner new]; }
    if (!serviceTest && !runtimeHost.translationTaskOwner) { runtimeHost.translationTaskOwner = [FYTranslationTaskOwner new]; }
    FYTranslationTaskOwner *owner = serviceTest ? runtimeHost.serviceTestTaskOwner : runtimeHost.translationTaskOwner;
    NSInteger generation = serviceTest ? runtimeHost.serviceTestGeneration : runtimeHost.translationGeneration;
    NSUInteger contentRevision = runtimeHost.contentTranslationRevision;
    uint32_t diagnosticWindowID = [runtimeHost displayTargetWindowID];
    FYTranslationRequestIdentity *identity = [[FYTranslationRequestIdentity alloc]
        initWithScope:(serviceTest ? FYTranslationRequestServiceTest : FYTranslationRequestRealtime) generation:generation revision:contentRevision];
    FYTranslationRequestLease *lease = [[FYTranslationRequestLease alloc] initWithIdentity:identity
        generation:^NSInteger { return serviceTest ? runtimeHost.serviceTestGeneration : runtimeHost.translationGeneration; }
        revision:^NSUInteger { return runtimeHost.contentTranslationRevision; }];
    NSDate *httpStart = [NSDate date];
    [self.requestCoordinator submit:prepared owner:owner lease:lease
        observer:^(NSURLResponse *response, NSError *error) {
            FuyiDiagLog(@"    HTTP %ld in %.2fs err=<%@>", (long)[(NSHTTPURLResponse *)response statusCode],
                [[NSDate date] timeIntervalSinceDate:httpStart], [NSString stringWithFormat:@"code:%ld", (long)error.code]);
            [[FYRuntimeDiagnostics shared] recordEvent:@"http" fields:@{@"window_id": @(diagnosticWindowID), @"generation": @(generation), @"http_status": @([(NSHTTPURLResponse *)response statusCode]), @"error_code": @(error.code), @"elapsed_ms": @([[NSDate date] timeIntervalSinceDate:httpStart] * 1000)}];
            FYTrace(trace, @"http_complete", @{@"http_status": @([(NSHTTPURLResponse *)response statusCode]), @"elapsed_ms": @([[NSDate date] timeIntervalSinceDate:httpStart] * 1000), @"error_code": @(error.code)});
        } received:^(NSString *translated, NSError *error) {
            [[FYRuntimeDiagnostics shared] recordEvent:@"translation" fields:@{@"window_id": @(diagnosticWindowID), @"generation": @(generation), @"success": @(!error), @"error_code": @(error.code)}];
            FYTrace(trace, @"request_complete", @{@"success": @(!error), @"error_code": @(error.code), @"translation": error ? @"" : (translated ?: @"")});
        } willResume:^{ FYTrace(trace, @"request_submit", @{@"source": Trim(text), @"generation": @(generation)}); }
        completion:completion dropped:^(FYTranslationRequestDrop reason) {
            FYTrace(trace, @"caption_drop", @{@"reason": reason == FYTranslationRequestContentChanged ? @"content_changed_before_delivery" : @"generation_changed_before_delivery"});
        }];
}

- (NSURL *)chatCompletionsURL {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; return FYTranslationServiceURLWithError(runtimeHost.baseURLField.stringValue,NULL); }

- (NSString *)systemPrompt {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    return [runtimeHost systemPromptForMode:[runtimeHost effectiveModeSegment]];
}

- (BOOL)autoContentModeEnabled {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    // 内容模式已彻底固定为自动判别，手动指定已被移除。
    return YES;
}

- (NSTimeInterval)translationAttemptThrottleForMode:(NSInteger)modeSegment {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    return [FYContentRouter translationAttemptThrottleForMode:modeSegment];
}

- (NSArray<OCRTextItem *> *)blocksInsideModalIfPresent:(NSArray<OCRTextItem *> *)blocks
                                              inImage:(CGImageRef)image
                                    normalizedExclusions:(NSArray<NSValue *> *)exclusionValues {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    return [FYOCRManager items:blocks scopedToModalInImage:image exclusions:exclusionValues];
}

- (NSInteger)effectiveModeSegment {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    return runtimeHost.detectedModeSegment;
}

- (NSInteger)stableContentModeForBlocks:(NSArray<OCRTextItem *> *)blocks {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    return [runtimeHost.contentRouter observeModeForItems:blocks
        locked:(runtimeHost.inlineOverflowChoicePanel != nil || runtimeHost.inlineExpandedReadingPanel != nil)];
}

- (NSString *)systemPromptForMode:(NSInteger)modeSegment {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    NSString *source = SourceLanguageLabel(runtimeHost.languageControl.selectedSegment);
    if (modeSegment == 1) {
        return [NSString stringWithFormat:@"你是一个游戏界面与公告文本翻译器。把用户发来的%@ OCR 文本翻译成简体中文。只输出译文，不解释。保留标题、日期、正文、按钮等自然结构；去掉重复、残缺、装饰性或背景噪声文字；菜单和按钮要短，公告正文要完整准确。", source];
    }

    return [NSString stringWithFormat:@"你是一个游戏字幕实时翻译器。把用户发来的%@翻译成自然、准确、口语化的简体中文。只输出译文，不解释，不加引号。保留人名和专有名词。遇到多行文本，按原意合并成适合字幕阅读的短句。", source];
}

- (FYInlineTranslationCache *)inlineCache {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    if (!self.inlineCoordinator.cache) self.inlineCoordinator.cache = [FYInlineTranslationCache new];
    return self.inlineCoordinator.cache;
}

- (NSMutableDictionary *)inlineTranslationCache {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; return [runtimeHost inlineCache].entries; }

- (void)setInlineTranslationCache:(NSMutableDictionary<NSString *, NSString *> *)value {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; [runtimeHost inlineCache].entries=value; }

- (FYContentRouter *)contentRouter {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    if (!_contentRouter) { _contentRouter = [FYContentRouter new]; }
    return _contentRouter;
}

- (FYContentModeStability *)modeStability {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; return runtimeHost.contentRouter.modeStability; }

- (NSInteger)detectedModeSegment {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; return [runtimeHost modeStability].detectedMode; }

- (void)setDetectedModeSegment:(NSInteger)value {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; [runtimeHost modeStability].detectedMode=value; }

- (NSInteger)candidateModeSegment {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; return [runtimeHost modeStability].candidateMode; }

- (void)setCandidateModeSegment:(NSInteger)value {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; [runtimeHost modeStability].candidateMode=value; }

- (NSInteger)candidateModeHits {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; return [runtimeHost modeStability].candidateHits; }

- (void)setCandidateModeHits:(NSInteger)value {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; [runtimeHost modeStability].candidateHits=value; }

- (FYTranslationRunState *)translationState {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    if (!_translationRunState) _translationRunState=[FYTranslationRunState new];
    return _translationRunState;
}

- (NSDate *)translationProcessingDate {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; return NSDate.date; }

- (NSString *)lastTranslatedNormalizedText {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; return [runtimeHost translationState].lastTranslatedText; }

- (void)setLastTranslatedNormalizedText:(NSString *)value {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; [runtimeHost translationState].lastTranslatedText=value; }

- (NSString *)lastSubmittedNormalizedText {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; return [runtimeHost translationState].lastSubmittedText; }

- (void)setLastSubmittedNormalizedText:(NSString *)value {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; [runtimeHost translationState].lastSubmittedText=value; }

- (NSDate *)lastTranslationAttemptDate {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; return [runtimeHost translationState].lastAttemptDate; }

- (void)setLastTranslationAttemptDate:(NSDate *)value {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; [runtimeHost translationState].lastAttemptDate=value; }

- (NSTimeInterval)recognitionPollingInterval {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    // Legacy hidden settings do not affect players' capture/OCR policy.
    return [FYContentRouter recognitionPollingIntervalForMode:[runtimeHost effectiveModeSegment]];
}

- (void)restartTimerIfRunning {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    if (!runtimeHost.running) { return; }

    [self.recognitionScheduler restartTimerWithInterval:[runtimeHost recognitionPollingInterval] target:runtimeHost];
}

- (FYOCRStabilityOwner *)stabilityOwner {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    if (!_ocrStabilityOwner) _ocrStabilityOwner=[FYOCRStabilityOwner new];
    return _ocrStabilityOwner;
}

- (NSString *)stableCandidate {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; return [runtimeHost stabilityOwner].candidate; }

- (void)setStableCandidate:(NSString *)value {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; [runtimeHost stabilityOwner].candidate=value; }

- (NSInteger)stableCandidateCount {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; return [runtimeHost stabilityOwner].count; }

- (void)setStableCandidateCount:(NSInteger)value {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host; [runtimeHost stabilityOwner].count=value; }

- (BOOL)isStableText:(NSString *)normalized {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    return [FYContentRouter isStableText:normalized owner:[runtimeHost stabilityOwner]
        mode:[runtimeHost effectiveModeSegment] japanese:(runtimeHost.languageControl.selectedSegment == 0)
        renderedText:runtimeHost.lastTranslatedNormalizedText comparisonKey:^NSString *(NSString *text) {
            return FYDialogueComparisonKey(text);
        }];
}

- (BOOL)shouldAcceptInlineOCRCorrection:(NSString *)text comparedTo:(NSString *)rendered {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    // 动态背景可能让同一界面的 OCR 文字偶发增删或误识别。相似界面的新读数
    // 连续出现三帧才替换已显示的译文；明显换页仍立即响应。
    if (rendered.length == 0 || SimilarityRatio(text, rendered) < 0.75) {
        runtimeHost.inlineOCRPendingText = nil;
        runtimeHost.inlineOCRPendingCount = 0;
        return YES;
    }
    if ([runtimeHost.inlineOCRPendingText isEqualToString:text]) {
        runtimeHost.inlineOCRPendingCount++;
    } else {
        runtimeHost.inlineOCRPendingText = text;
        runtimeHost.inlineOCRPendingCount = 1;
    }
    if (runtimeHost.inlineOCRPendingCount < 3) { return NO; }
    runtimeHost.inlineOCRPendingText = nil;
    runtimeHost.inlineOCRPendingCount = 0;
    return YES;
}

- (BOOL)isSameSubtitleText:(NSString *)text comparedTo:(NSString *)previous {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    return [FYContentRouter isSameSubtitleText:text comparedTo:previous mode:[runtimeHost effectiveModeSegment]
        japanese:(runtimeHost.languageControl.selectedSegment == 0) comparisonKey:^NSString *(NSString *value) {
            return FYDialogueComparisonKey(value);
        }];
}

- (NSString *)displayableTranslation:(NSString *)translated sourceText:(NSString *)sourceText {
    __attribute__((unused)) id<FYTranslationRuntimeControllerHost> runtimeHost = self.host;
    return FYDisplayableTranslation(translated, sourceText,
        ^NSString *(NSString *value) { return Trim(value); },
        ^NSString *(NSString *value) { return NormalizeForComparison(value); },
        ^BOOL(NSString *current, NSString *previous) { return [runtimeHost isSameSubtitleText:current comparedTo:previous]; },
        ^BOOL(NSString *line) { return runtimeHost.languageControl.selectedSegment == 0 && ContainsJapaneseText(line); });
}

@end
