#import "FYCaptureMappingCoordinator.h"
#import "FYCoordinateConversions.h"
static void FYEmitMappingEvent(FYCaptureMappingObserver observer,FYCaptureMappingEvent event) { if(observer)observer(event); }
@implementation FYCaptureMappingConfiguration
- (instancetype)initWithVersion:(NSInteger)version scoreUnavailable:(double)score { if((self=[super init])){_version=version;_scoreUnavailable=score;}return self; }
@end
@implementation FYCaptureMappingCoordinator
- (instancetype)initWithConfiguration:(FYCaptureMappingConfiguration *)configuration { if((self=[super init]))_configuration=configuration;return self; }
- (FYCaptureMappingCache *)mappingCache { if(!_captureMappingCache)_captureMappingCache=[FYCaptureMappingCache new];return _captureMappingCache; }
- (FYAutoLocateSchedule *)locateSchedule { if(!_autoLocateSchedule)_autoLocateSchedule=[FYAutoLocateSchedule new];return _autoLocateSchedule; }
- (FYMappingValidationSchedule *)validationSchedule { if(!_mappingValidationSchedule)_mappingValidationSchedule=[FYMappingValidationSchedule new];return _mappingValidationSchedule; }
- (BOOL)buildGridsWithTemplate:(double **)outTempl templateW:(size_t *)outTW templateH:(size_t *)outTH scene:(double **)outScene sceneW:(size_t *)outWW sceneH:(size_t *)outWH aspect:(CGFloat *)outAspect sceneWidth:(size_t)sceneWidth operations:(id<FYCaptureMappingOperations>)operations reason:(NSString **)outReason {
    if (outTempl) { *outTempl = NULL; }
    if (outScene) { *outScene = NULL; }
    CGSize frameSize = CGSizeZero;
    if (![operations mappingLatestFrameSize:&frameSize]) {
        if (outReason) { *outReason = @"采集卡暂无画面"; }
        return NO;
    }
    if (![operations mappingCanCaptureScreen]) {
        if (outReason) { *outReason = @"需要屏幕录制权限才能自动定位游戏画面"; }
        return NO;
    }
    CGImageRef frameImage = [operations copyMappingFrame];
    if (!frameImage) {
        if (outReason) { *outReason = @"采集卡暂无画面"; }
        return NO;
    }
    CGImageRef windowImage = [operations copyMappingWindow];
    if (!windowImage) {
        CGImageRelease(frameImage);
        if (outReason) { *outReason = @"无法读取目标窗口画面"; }
        return NO;
    }
    return FYBuildCaptureGrids(frameImage, windowImage, frameSize,
        ^NSRect { return [operations mappingWindowFrame]; }, sceneWidth,
        outTempl, outTW, outTH, outScene, outWW, outWH, outAspect, outReason);
}

- (BOOL)autoDetectWithOperations:(id<FYCaptureMappingOperations>)operations reason:(NSString **)outReason observer:(FYCaptureMappingObserver)observer {
    if (![operations mappingWindowPresent]) { if (outReason) { *outReason = @"未选择目标窗口"; } return NO; }
    // 定位失败时不要每轮都重新抓一次整窗：失败的尝试限流，成功了会缓存映射。
    if ([[self locateSchedule] isThrottled]) {
        if (outReason) { *outReason = @"暂时无法定位游戏画面，可调整贴译位置"; }
        return NO;
    }
    NSRect windowFrame = [operations mappingWindowFrame];
    if (NSWidth(windowFrame) < 40 || NSHeight(windowFrame) < 40) {
        if (outReason) { *outReason = @"目标窗口太小"; }
        return NO;
    }
    double *templ = NULL, *scene = NULL;
    size_t TW = 0, TH = 0, WW = 0, WH = 0;
    CGFloat videoAspect = 1;
    if (![operations mappingBuildGridsWithTemplate:&templ templateW:&TW templateH:&TH scene:&scene sceneW:&WW sceneH:&WH aspect:&videoAspect sceneWidth:320 reason:outReason]) {
        return NO;
    }

    FYCaptureCandidateResult candidate=FYSelectCaptureCandidate(scene, WW, WH, templ, TW, TH, videoAspect, windowFrame,
        ^BOOL(NSRect *fit) { return [operations mappingEstimatedRect:fit]; },
        ^NSDictionary *{ return [[self mappingCache] entryForWindowID:[operations mappingWindowID]]; }, self.configuration.version,
        ^(double searchScore, double fitScore) {
            FYEmitMappingEvent(observer,(FYCaptureMappingEvent){.kind=FYMappingPreferFit,.score=searchScore,.fitScore=fitScore});
        }, ^(double existingScore, double bestScore, double fitScore) {
            FYEmitMappingEvent(observer,(FYCaptureMappingEvent){.kind=FYMappingKeepCache,.score=existingScore,.otherScore=bestScore,.fitScore=fitScore});
        });
    if (candidate.keepExisting) { free(templ); free(scene); return NO; }
    NSRect bestRect=candidate.bestRect;
    double best=candidate.bestScore, fitScore=candidate.fitScore;
    free(templ);
    free(scene);
    [self locateSchedule].lastAttemptDate = [NSDate date];

    if (best < 0.55) {
        if (outReason) { *outReason = @"暂时无法定位游戏画面"; }
        FYEmitMappingEvent(observer,(FYCaptureMappingEvent){.kind=FYMappingMiss,.score=best,.fitScore=fitScore,.aspect=videoAspect,.windowFrame=windowFrame,.gridWidth=WW,.gridHeight=WH});
        return NO;
    }
    // ⚠️ 坐标翻转：bestRect 来自 FYGrayGridFromImage 的像素网格，**y 从图像顶部往下**；
    // AppKit 的 y 从窗口底部往上。旧代码直接把 bestRect.origin.y 加到 NSMinY(windowFrame)，
    // 等于把「距顶部」当成「距底部」——OBS 预览在窗口上半部时，映射整体下移到下方控制区。
    // 正确换算：先用 (1 - (y + h) / gridH) 得到距底部的比例，再乘窗口高度。
    NSRect rect = FYWindowRectFromCaptureGrid(bestRect, WW, WH, windowFrame);
    [operations mappingStoreRect:rect
                      windowFrame:windowFrame
                      aspect:videoAspect
                         deviceID:[operations mappingSelectedDeviceID]
                           source:@"auto"
                       confidence:best
                      windowID:[operations mappingWindowID]];
    // 成功就清掉“失败限流”时间戳：旧映射被判失效后必须能立刻重新定位，
    // 否则会出现「映射已作废、却 3 秒不重新定位」的空窗（贴译整段消失）。
    [self locateSchedule].lastAttemptDate = nil;
    FYEmitMappingEvent(observer,(FYCaptureMappingEvent){.kind=FYMappingHit,.score=best,.fitScore=fitScore,.windowFrame=windowFrame,.rect=rect,.gridWidth=WW,.gridHeight=WH});
    return YES;
}

- (double)scoreForEntry:(NSDictionary *)entry operations:(id<FYCaptureMappingOperations>)operations {
    if (![operations mappingWindowPresent] || !entry) { return self.configuration.scoreUnavailable; }
    double *templ = NULL, *scene = NULL;
    size_t TW = 0, TH = 0, WW = 0, WH = 0;
    CGFloat videoAspect = 1;
    if (![operations mappingBuildGridsWithTemplate:&templ templateW:&TW templateH:&TH scene:&scene sceneW:&WW sceneH:&WH aspect:&videoAspect sceneWidth:320 reason:NULL]) {
        return self.configuration.scoreUnavailable;
    }
    return FYConsumeCaptureMappingGrids(entry, scene, WW, WH, templ, TW, TH);
}

- (void)storeRect:(CGRect)screenRect windowFrame:(CGRect)windowFrame aspect:(CGFloat)videoAspect deviceID:(NSString *)deviceID source:(NSString *)source confidence:(CGFloat)confidence windowID:(uint32_t)windowID operations:(id<FYCaptureMappingOperations>)operations {
    NSDictionary *entry = [FYCaptureMappingAlgorithms captureMappingForRect:screenRect windowFrame:windowFrame
                                                       videoAspect:videoAspect deviceID:deviceID source:source
                                                        confidence:confidence version:self.configuration.version];
    if (!entry) { return; }
    [[self mappingCache] storeEntry:entry forWindowID:windowID];
    // 刚定位出来的映射先给 2 秒宽限再做定点复核：它是拿**当前**这帧画面算出来的，
    // 立刻复核除了多截一次屏没有任何意义。
    [self validationSchedule].lastValidationDate = [NSDate date];
    // 映射变了：让贴译布局缓存与手动位置一起按新映射重算。
    [operations mappingResetLayoutCache];
}

- (void)clearWindowID:(uint32_t)windowID {
    [[self mappingCache] removeWindowID:windowID];
}

- (BOOL)estimatedRect:(CGRect *)outRect operations:(id<FYCaptureMappingOperations>)operations {
    if (![operations mappingWindowPresent]) { return NO; }
    CGSize frameSize = CGSizeZero;
    if (![operations mappingLatestFrameSize:&frameSize]) { return NO; }
    if (frameSize.width < 2 || frameSize.height < 2) { return NO; }
    NSRect windowFrame = [operations mappingWindowFrame];
    return FYEstimatedCaptureDisplayRect(frameSize, windowFrame, outRect);
}

- (BOOL)displayRect:(CGRect *)outRect operations:(id<FYCaptureMappingOperations>)operations reason:(NSString **)outReason observer:(FYCaptureMappingObserver)observer {
    if (![operations mappingWindowPresent]) { if (outReason) { *outReason = @"未选择目标窗口。"; } return NO; }
    uint32_t mappingKey = [operations mappingWindowID];
    NSDictionary *entry = [[self mappingCache] entryForWindowID:[operations mappingWindowID]];
    if (!entry) { if (outReason) { *outReason = @"该窗口还没有贴译位置。"; } return NO; }
    // 旧版自动映射可能带有翻转或取样偏差：作废重定位，不能继续读旧结果。
    // 手动调整（source=manual）一直是 AppKit 坐标，不受这个 bug 影响，保留。
    FYCaptureMappingVersionStatus versionStatus = FYCaptureMappingVersion(entry, self.configuration.version);
    BOOL autoMapping = versionStatus != FYCaptureMappingVersionNonAutomatic;
    if (versionStatus == FYCaptureMappingVersionStaleAutomatic) {
        [[self mappingCache] removeWindowID:[operations mappingWindowID]];
        [operations mappingResetLayoutCache];
        [self locateSchedule].lastAttemptDate = nil;   // 允许上层立刻重新定位
        if (outReason) { *outReason = @"旧版自动定位结果已作废，正在重新定位游戏画面"; }
        FYEmitMappingEvent(observer,(FYCaptureMappingEvent){.kind=FYMappingStaleVersion,.windowID=mappingKey});
        return NO;
    }
    NSRect windowFrame = [operations mappingWindowFrame];
    NSString *windowReason = [FYCaptureMappingAlgorithms captureMappingWindowReason:entry windowFrame:windowFrame];
    if (windowReason) { if (outReason) { *outReason = windowReason; } return NO; }
    // Sampling and state remain in coordinator; policy uses explicit snapshot inputs.
    CGSize frameSize = CGSizeZero;
    BOOL hasFrameSize = [operations mappingLatestFrameSize:&frameSize];
    NSString *inputReason = [FYCaptureMappingAlgorithms captureMappingInputReason:entry frameSize:frameSize
                                                         hasFrameSize:hasFrameSize deviceID:[operations mappingSelectedDeviceID]];
    if (inputReason) { if (outReason) { *outReason = inputReason; } return NO; }
    // 自动映射要**适当复核**：OBS 内部预览移动/缩放、面板展开收起时窗口比例可能完全没变，
    // 只看比例会一直拿着错位置。这里限流（≥1.5s 一次）做一次定点比对：
    // 不做全窗口搜索，所以不会每帧昂贵；失败就作废映射并在上层触发重新定位。
    // 手动调整的映射不参与复核（那是用户明确指定的位置）。
    if (autoMapping && [operations mappingCaptureCardEnabled]) {
        NSDate *now = [NSDate date];
        BOOL due = [[self validationSchedule] beginValidationAt:now];
        if (due) {

            double score = [operations mappingScoreForEntry:entry];
            // 阈值 0.30 来自离线标定：位置没变时定点相关性约 0.57，画面移动 ≥5% 就掉到 0.07 以下
            //（大移位甚至为负）。负数同样是“明确对不上”，只有哨兵值才表示取样失败。
            if ([FYCaptureMappingAlgorithms captureMappingScoreIsStale:score unavailableValue:self.configuration.scoreUnavailable]) {
                [[self mappingCache] removeWindowID:[operations mappingWindowID]];
                [operations mappingResetLayoutCache];
                [self locateSchedule].lastAttemptDate = nil;   // 允许上层立刻重新定位
                if (outReason) { *outReason = @"游戏画面位置变了，正在重新定位"; }
                FYEmitMappingEvent(observer,(FYCaptureMappingEvent){.kind=FYMappingStalePicture,.windowID=mappingKey,.score=score});
                return NO;
            }
        }
    }
    NSRect rect = [FYCaptureMappingAlgorithms captureMappingRect:entry windowFrame:windowFrame];
    if (NSWidth(rect) < 2 || NSHeight(rect) < 2) {
        if (outReason) { *outReason = @"贴译位置无效。"; }
        return NO;
    }
    if (outRect) { *outRect = NSIntegralRect(rect); }
    return YES;
}
@end
