#import "FYCaptureRuntimeController.h"

// Native resources are retained only during one synchronous mapping operation.
@interface FYCaptureMappingNativeLease : NSObject <FYCaptureMappingOperations>
@property(nonatomic, strong) id<FYCaptureRuntimeControllerHost> host;
@property(nonatomic, strong) WindowItem *window;
@end
@implementation FYCaptureMappingNativeLease
- (BOOL)mappingWindowPresent { return self.window != nil; }
- (uint32_t)mappingWindowID { return self.window.windowID; }
- (CGRect)mappingWindowFrame { return [self.host appKitFrameForWindowItem:self.window]; }
- (BOOL)mappingLatestFrameSize:(CGSize *)size { return [self.host.captureCardInput latestFrameSize:size]; }
- (BOOL)mappingCanCaptureScreen { return [self.host hasUsableScreenCaptureAccess]; }
- (CGImageRef)copyMappingFrame { return [self.host.captureCardInput copyLatestFrame]; }
- (CGImageRef)copyMappingWindow { return [self.host copyFullCapturedImageForWindow:self.window.windowID]; }
- (BOOL)mappingBuildGridsWithTemplate:(double **)templ templateW:(size_t *)tw templateH:(size_t *)th
    scene:(double **)scene sceneW:(size_t *)sw sceneH:(size_t *)sh aspect:(CGFloat *)aspect
    sceneWidth:(size_t)width reason:(NSString **)reason {
    return [self.host buildCaptureGridsWithFrame:templ templateW:tw templateH:th
        scene:scene sceneW:sw sceneH:sh videoAspect:aspect sceneWidth:width forWindow:self.window reason:reason];
}
- (BOOL)mappingEstimatedRect:(CGRect *)rect { return [self.host captureCardEstimatedDisplayRectForWindow:self.window outRect:rect]; }
- (double)mappingScoreForEntry:(NSDictionary *)entry { return [self.host captureCardMappingScoreForWindow:self.window entry:entry]; }
- (NSString *)mappingSelectedDeviceID { return self.host.selectedCaptureDeviceID; }
- (BOOL)mappingCaptureCardEnabled { return [self.host captureCardInputEnabled]; }
- (void)mappingStoreRect:(CGRect)rect windowFrame:(CGRect)frame aspect:(CGFloat)aspect deviceID:(NSString *)device
    source:(NSString *)source confidence:(CGFloat)confidence windowID:(uint32_t)windowID {
    [self.host storeCaptureCardMapping:rect windowFrame:frame videoAspect:aspect deviceID:device
        source:source confidence:confidence forWindowID:windowID];
}
- (void)mappingResetLayoutCache { [self.host resetInlineLayoutCacheAfterMappingChange]; }
@end

// Observation stays in the native diagnostic adapter, at the original stages.
static void FYObserveCaptureMapping(FYCaptureMappingEvent event) {
    switch (event.kind) {
        case FYMappingPreferFit:
            FuyiDiagLog(@"CAPTURE-AUTO-LOCATE prefer-fit searchScore=%.3f fitScore=%.3f", event.score, event.fitScore);
            break;
        case FYMappingKeepCache:
            FuyiDiagLog(@"CAPTURE-AUTO-LOCATE keep-cached cachedScore=%.3f best=%.3f fitScore=%.3f", event.score, event.otherScore, event.fitScore);
            break;
        case FYMappingMiss:
            FuyiDiagLog(@"CAPTURE-AUTO-LOCATE miss confidence=%.3f fitScore=%.3f aspect=%.3f window=%@ grid=%zux%zu",
                event.score, event.fitScore, event.aspect, NSStringFromRect(event.windowFrame), event.gridWidth, event.gridHeight);
            break;
        case FYMappingHit:
            FuyiDiagLog(@"CAPTURE-AUTO-LOCATE hit confidence=%.3f fitScore=%.3f window=%@ rect=%@ fracWH=(%.3f,%.3f) grid=%zux%zu",
                event.score, event.fitScore, NSStringFromRect(event.windowFrame), NSStringFromRect(event.rect),
                NSWidth(event.rect) / MAX((CGFloat)1, NSWidth(event.windowFrame)),
                NSHeight(event.rect) / MAX((CGFloat)1, NSHeight(event.windowFrame)), event.gridWidth, event.gridHeight);
            break;
        case FYMappingStaleVersion:
            FuyiDiagLog(@"CAPTURE-MAPPING stale-version dropped key=%@", FYDiagTextLength([NSString stringWithFormat:@"%u", event.windowID]));
            break;
        case FYMappingStalePicture:
            FuyiDiagLog(@"CAPTURE-MAPPING stale-picture dropped key=%@ score=%.3f", FYDiagTextLength([NSString stringWithFormat:@"%u", event.windowID]), event.score);
            break;
    }
}

@implementation FYCaptureRuntimeController
@dynamic captureMappingCache, autoLocateSchedule, mappingValidationSchedule;
- (FYCaptureMappingNativeLease *)mappingLeaseForWindow:(WindowItem *)window {
    FYCaptureMappingNativeLease *lease = [FYCaptureMappingNativeLease new];
    lease.host = self.host;
    lease.window = window;
    return lease;
}
- (FYCaptureMappingCache *)captureMappingCache { return self.mappingCoordinator.captureMappingCache; }
- (void)setCaptureMappingCache:(FYCaptureMappingCache *)value { self.mappingCoordinator.captureMappingCache = value; }
- (FYAutoLocateSchedule *)autoLocateSchedule { return self.mappingCoordinator.autoLocateSchedule; }
- (void)setAutoLocateSchedule:(FYAutoLocateSchedule *)value { self.mappingCoordinator.autoLocateSchedule = value; }
- (FYMappingValidationSchedule *)mappingValidationSchedule { return self.mappingCoordinator.mappingValidationSchedule; }
- (void)setMappingValidationSchedule:(FYMappingValidationSchedule *)value { self.mappingCoordinator.mappingValidationSchedule = value; }

@dynamic displayTargetResolved, displayTargetAmbiguous, resolvedDisplayTargetID, lastDisplayTargetProbeDate, lastWindowRecoveryAttemptDate, geometryGeneration, lastDisplayGeometryToken, lastOCRedCaptureFrameIndex, previewTimer, previewQueue, previewInFlight, previewRequestSerial, previewRenderSerial, lastPreviewCaptureFrameIndex, lastPreviewDate;
- (instancetype)initWithHost:(id<FYCaptureRuntimeControllerHost>)host {
    if ((self = [super init])) {
        _host = host;
        _displayTargetTracker = [FYDisplayTargetTracker new];
        _mappingCoordinator = [[FYCaptureMappingCoordinator alloc] initWithConfiguration:
            [[FYCaptureMappingConfiguration alloc] initWithVersion:kCaptureCardMappingVersion scoreUnavailable:kCaptureCardMappingScoreUnavailable]];
        _previewScheduler = [[FYLivePreviewScheduler alloc] initWithSource:self
            queue:dispatch_queue_create("com.nanami.yiya.preview", DISPATCH_QUEUE_SERIAL)];
    }
    return self;
}


// Target compatibility properties do not synthesize adapter storage.
- (BOOL)displayTargetResolved { return self.displayTargetTracker.displayTargetResolved; }
- (void)setDisplayTargetResolved:(BOOL)value { self.displayTargetTracker.displayTargetResolved = value; }
- (BOOL)displayTargetAmbiguous { return self.displayTargetTracker.displayTargetAmbiguous; }
- (void)setDisplayTargetAmbiguous:(BOOL)value { self.displayTargetTracker.displayTargetAmbiguous = value; }
- (uint32_t)resolvedDisplayTargetID { return self.displayTargetTracker.resolvedDisplayTargetID; }
- (void)setResolvedDisplayTargetID:(uint32_t)value { self.displayTargetTracker.resolvedDisplayTargetID = value; }
- (NSDate *)lastDisplayTargetProbeDate { return self.displayTargetTracker.lastDisplayTargetProbeDate; }
- (void)setLastDisplayTargetProbeDate:(NSDate *)value { self.displayTargetTracker.lastDisplayTargetProbeDate = value; }
- (NSDate *)lastWindowRecoveryAttemptDate { return self.displayTargetTracker.lastWindowRecoveryAttemptDate; }
- (void)setLastWindowRecoveryAttemptDate:(NSDate *)value { self.displayTargetTracker.lastWindowRecoveryAttemptDate = value; }
- (NSInteger)geometryGeneration { return self.displayTargetTracker.geometryGeneration; }
- (void)setGeometryGeneration:(NSInteger)value { self.displayTargetTracker.geometryGeneration = value; }
- (NSString *)lastDisplayGeometryToken { return self.displayTargetTracker.lastDisplayGeometryToken; }
- (void)setLastDisplayGeometryToken:(NSString *)value { self.displayTargetTracker.lastDisplayGeometryToken = value; }

// Legacy capture access routes through the host facade to the OCR owner.
- (uint64_t)lastOCRedCaptureFrameIndex { return self.host.lastOCRedCaptureFrameIndex; }
- (void)setLastOCRedCaptureFrameIndex:(uint64_t)value { self.host.lastOCRedCaptureFrameIndex = value; }

#pragma mark - Preview compatibility state (scheduler is the sole owner)

- (NSTimer *)previewTimer { return self.previewScheduler.timer; }
- (void)setPreviewTimer:(NSTimer *)value { self.previewScheduler.timer = value; }

- (dispatch_queue_t)previewQueue { return self.previewScheduler.queue; }
- (void)setPreviewQueue:(dispatch_queue_t)value { self.previewScheduler.queue = value; }

- (BOOL)previewInFlight { return self.previewScheduler.inFlight; }
- (void)setPreviewInFlight:(BOOL)value { self.previewScheduler.inFlight = value; }

- (NSUInteger)previewRequestSerial { return self.previewScheduler.requestSerial; }
- (void)setPreviewRequestSerial:(NSUInteger)value { self.previewScheduler.requestSerial = value; }

- (NSUInteger)previewRenderSerial { return self.previewScheduler.renderSerial; }
- (void)setPreviewRenderSerial:(NSUInteger)value { self.previewScheduler.renderSerial = value; }

- (uint64_t)lastPreviewCaptureFrameIndex { return self.previewScheduler.lastCaptureFrameIndex; }
- (void)setLastPreviewCaptureFrameIndex:(uint64_t)value { self.previewScheduler.lastCaptureFrameIndex = value; }

- (NSDate *)lastPreviewDate { return self.previewScheduler.lastRenderDate; }
- (void)setLastPreviewDate:(NSDate *)value { self.previewScheduler.lastRenderDate = value; }

- (pid_t)selectedWindowOwnerPID {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    uint32_t windowID = [runtimeHost selectedWindowID];
    if (!windowID) { return 0; }
    if (runtimeHost.overlayOwnerPIDSnapshot) { return runtimeHost.overlayOwnerPIDSnapshot.intValue; }
    for (NSDictionary *entry in runtimeHost.overlayWindowSnapshot) {
        if ([entry[(id)kCGWindowNumber] unsignedIntValue] == windowID) {
            return (pid_t)[entry[(id)kCGWindowOwnerPID] intValue];
        }
    }
    NSArray *entries = [runtimeHost windowInfosIncludingWindow:windowID];
    for (NSDictionary *entry in entries) {
        if ([entry[(id)kCGWindowNumber] unsignedIntValue] == windowID) {
            return (pid_t)[entry[(id)kCGWindowOwnerPID] intValue];
        }
    }
    return 0;
}

- (NSArray<NSDictionary *> *)windowInfosIncludingWindow:(uint32_t)windowID {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, windowID));
}

- (NSArray<NSDictionary *> *)onScreenWindowInfos {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
}

- (FYOCRManager *)ocrManager {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    @synchronized (runtimeHost) {
        if (!_ocrManager) {
            _ocrManager = [FYOCRManager new];
            _ocrManager.configurationObserver = ^(BOOL fast, NSInteger segment, size_t width, size_t height, CGFloat minimum) {
                FuyiDiagLog(@"  OCRCFG seg=%ld fast=%d imgW=%zu imgH=%zu minH=%.4f", (long)segment, fast, width, height, minimum);
            };
        }
        return _ocrManager;
    }
}

- (FYWindowManager *)windowManager {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (!_windowManager) { _windowManager = [FYWindowManager new]; }
    return _windowManager;
}

- (NSArray<WindowItem *> *)availableWindowItems {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [[runtimeHost windowManager] availableWindowItems];
}

- (NSInteger)quickTimeCapturePriority:(WindowItem *)item {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (item.effectiveOwnerName.length == 0 || ![item.effectiveOwnerName hasPrefix:@"QuickTime Player"]) { return 0; }
    NSString *title = item.effectiveTitle;
    if ([@[@"打开", @"Open", @"存储", @"Save", @"导出", @"Export"] containsObject:title]) { return 1; }
    if ([@[@"录影", @"影片录制", @"Movie Recording", @"録画"] containsObject:title]) { return 4; }
    return 3;
}

- (NSArray<WindowItem *> *)displayedWindowItems {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [[runtimeHost windowManager] displayedWindowItems:runtimeHost.windows showingAll:runtimeHost.showAllWindowsInPicker selectedID:[runtimeHost selectedWindowID]];
}

- (BOOL)hasRecommendedWindowItems {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [[runtimeHost windowManager] hasRecommendedWindowItems:runtimeHost.windows];
}

- (NSString *)windowBaseTitleForItem:(WindowItem *)item {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [[runtimeHost windowManager] windowBaseTitleForItem:item];
}

- (NSString *)windowMenuTitleForItem:(WindowItem *)item occurrence:(NSUInteger)occurrence {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [[runtimeHost windowManager] windowMenuTitleForItem:item occurrence:occurrence];
}

- (void)rebuildWindowMenuPreservingSelection {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    uint32_t previousSelection = [runtimeHost selectedWindowID];
    NSArray<WindowItem *> *displayed = [runtimeHost displayedWindowItems];
    [runtimeHost.windowPopup removeAllItems];
    runtimeHost.windowPickerPlaceholder = nil;

    NSMutableDictionary<NSString *, NSNumber *> *labelCounts = [NSMutableDictionary dictionary];
    NSInteger selectedIndex = -1;
    for (NSUInteger index = 0; index < displayed.count; index++) {
        WindowItem *item = displayed[index];
        NSString *base = [runtimeHost windowBaseTitleForItem:item];
        NSUInteger occurrence = (labelCounts[base] ?: @0).unsignedIntegerValue + 1;
        labelCounts[base] = @(occurrence);
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[runtimeHost windowMenuTitleForItem:item occurrence:occurrence]
                                                          action:nil
                                                   keyEquivalent:@""];
        menuItem.representedObject = @(item.windowID);
        [runtimeHost.windowPopup.menu addItem:menuItem];
        if (item.windowID == previousSelection) { selectedIndex = (NSInteger)index; }
    }

    if (selectedIndex >= 0) {
        [runtimeHost.windowPopup selectItemAtIndex:selectedIndex];
        runtimeHost.windowSelectionLost = NO;
        return;
    }

    // 已经丢过选择（窗口关闭）时，占位提示要一直保留到用户重新点选，
    // 刷新/切换精简↔全部都不许顺手把别的窗口选上。
    BOOL lostSelection = previousSelection != 0 || runtimeHost.windowPickerPlaceholder.length > 0;
    NSString *placeholder = lostSelection
        ? @"原窗口已关闭，请重新选择"
        : (displayed.count == 0 ? @"没有找到可用窗口，点「刷新窗口」重试" : nil);
    if (placeholder.length > 0) {
        // 选中的窗口不在了：给一条明确提示，**不静默绑到别的窗口**上。
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:placeholder action:nil keyEquivalent:@""];
        item.representedObject = @0;
        item.enabled = NO;
        [runtimeHost.windowPopup.menu insertItem:item atIndex:0];
        [runtimeHost.windowPopup selectItemAtIndex:0];
        runtimeHost.windowPickerPlaceholder = placeholder;
        runtimeHost.windowSelectionLost = lostSelection;
        return;
    }

    // 用户还没选过（首次刷新）：用排序里的第一个（推荐位最高）作为默认。
    // 之后刷新永远保持这个选择，不会再自动跳到第一项。
    [runtimeHost.windowPopup selectItemAtIndex:0];
}

- (void)refreshWindows:(id)sender {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    uint32_t previousSelection = [runtimeHost selectedWindowID];
    runtimeHost.windows = [[runtimeHost availableWindowItems] mutableCopy];
    // 排序在这里再统一做一次：列表的来源可能是被测试或别的入口替换过的数组，
    // 但"更可能相关的窗口排在前面"这个规则必须对所有来源一致。
    [runtimeHost.windows sortUsingComparator:^NSComparisonResult(WindowItem *left, WindowItem *right) {
        return FYWindowItemSort(left, right);
    }];
    [runtimeHost rebuildWindowMenuPreservingSelection];

    uint32_t currentSelection = [runtimeHost selectedWindowID];
    if (previousSelection != 0 && currentSelection == 0) {
        [runtimeHost setStatus:@"原来的显示窗口已关闭，请重新选择窗口。"];
    }
    [runtimeHost updateWindowCardCopy];
    [runtimeHost updateCurrentWindowLabel];
    if (previousSelection != currentSelection) { [runtimeHost resetForSelectedWindowChange]; }
    // 刷新窗口就是让用户能立刻看到位置变化：几何复核强制跑一次。
    [runtimeHost refreshDisplayGeometryIfNeeded:YES];
    [runtimeHost updateRuntimeDiagnostics];
    if (![runtimeHost captureCardInputEnabled] && ![runtimeHost hasScreenAccess] && runtimeHost.windows.count == 0) {
        [runtimeHost setStatus:@"没有可选窗口：屏幕录制权限尚未生效，请检查权限后重启译芽。可导出诊断包反馈。"];
    }
}

- (void)toggleWindowListScope:(id)sender {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    runtimeHost.showAllWindowsInPicker = !runtimeHost.showAllWindowsInPicker;
    [runtimeHost rebuildWindowMenuPreservingSelection];
    [runtimeHost updateWindowCardCopy];
    [runtimeHost updateCurrentWindowLabel];
    [runtimeHost refreshDisplayGeometryIfNeeded:YES];
}

- (BOOL)selectWindowWithID:(uint32_t)windowID notifyChange:(BOOL)notify {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (windowID == 0) { return NO; }
    NSInteger index = -1;
    for (NSInteger itemIndex = 0; itemIndex < (NSInteger)runtimeHost.windowPopup.numberOfItems; itemIndex++) {
        NSNumber *represented = [runtimeHost.windowPopup.menu itemAtIndex:itemIndex].representedObject;
        if (represented.unsignedIntValue == windowID) { index = itemIndex; break; }
    }
    if (index < 0) { return NO; }
    uint32_t previous = [runtimeHost selectedWindowID];
    [runtimeHost.windowPopup selectItemAtIndex:index];
    runtimeHost.windowPickerPlaceholder = nil;
    runtimeHost.windowSelectionLost = NO;
    [runtimeHost updateCurrentWindowLabel];
    [runtimeHost updateWindowCardCopy];
    if (notify && previous != windowID) { [runtimeHost resetForSelectedWindowChange]; }
    return YES;
}

- (BOOL)recoverWindowSelectionIfRecreated {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    WindowItem *selected = [runtimeHost selectedWindowItem];
    if (!selected) { return NO; }
    NSDate *now = [NSDate date];
    if (![self.displayTargetTracker beginRecoveryAt:now]) { return NO; }

    NSArray<WindowItem *> *available = [runtimeHost availableWindowItems];
    BOOL selectedStillExists = NO;
    WindowItem *quickTimeCandidate = nil;
    NSInteger highestPriority = 1;
    BOOL ambiguous = NO;
    for (WindowItem *candidate in available) {
        if (candidate.windowID == selected.windowID) { selectedStillExists = YES; }
        if (candidate.windowID != selected.windowID && [candidate.displayName isEqualToString:selected.displayName]) {
            // 同一个窗口被系统重建（ID 变了、名字没变）：这是"同一个目标"，可以明确绑定。
            [runtimeHost refreshWindows:nil];
            return [runtimeHost selectWindowWithID:candidate.windowID notifyChange:YES];
        }
        NSInteger priority = [runtimeHost quickTimeCapturePriority:candidate];
        if (priority > highestPriority) {
            highestPriority = priority; quickTimeCandidate = candidate; ambiguous = NO;
        } else if (priority == highestPriority && priority > 1) { ambiguous = YES; }
    }
    // QuickTime's open dialog can disappear when its recording window opens.
    // Rebind only a vanished QuickTime target and an unambiguous content window.
    if (!selectedStillExists && [runtimeHost quickTimeCapturePriority:selected] > 0 && quickTimeCandidate && !ambiguous) {
        [runtimeHost refreshWindows:nil];
        return [runtimeHost selectWindowWithID:quickTimeCandidate.windowID notifyChange:YES];
    }
    return NO;
}

- (void)windowSelectionChanged:(id)sender {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    // 用户主动换窗口：清掉旧窗口的产物，并立刻按新窗口复核几何。
    runtimeHost.displayTargetResolved = NO;
    runtimeHost.displayTargetAmbiguous = NO;
    runtimeHost.resolvedDisplayTargetID = 0;
    [runtimeHost updateCurrentWindowLabel];
    [runtimeHost updateWindowCardCopy];
    [runtimeHost updateOCRPreviewIfVisible];
    [runtimeHost resetForSelectedWindowChange];
    [runtimeHost refreshDisplayGeometryIfNeeded:YES];
}

- (void)resetForSelectedWindowChange {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    [runtimeHost advanceTranslationGeneration];
    runtimeHost.inFlight = NO;
    runtimeHost.captureUnavailable = NO;
    runtimeHost.lastWindowRecoveryAttemptDate = nil;
    // 换窗口 = 换显示目标：重新解析（并在解析完成前隐藏旧贴译）。
    runtimeHost.displayTargetResolved = NO;
    runtimeHost.displayTargetAmbiguous = NO;
    runtimeHost.resolvedDisplayTargetID = 0;
    runtimeHost.lastDisplayGeometryToken = nil;
    [runtimeHost updateRunState];
    [runtimeHost showPreviewUnavailable:[runtimeHost captureCardInputEnabled] ? @"等待采集卡画面" : @"选择窗口并开始翻译后显示画面"];
    runtimeHost.lastPreviewDate = nil;
    runtimeHost.latestTranslationLabel.stringValue = @"等待译文";
    runtimeHost.latestSourceLabel.stringValue = @"";
    [runtimeHost clearInlineTranslationPanels];
    // 换窗口后旧窗口的去重/稳定状态不再适用，重置避免第一句被误判为“文本未变化”
    [[runtimeHost translationState] reset];
    [[runtimeHost stabilityOwner] reset];
    [[runtimeHost inlineCache] clear];
    if (runtimeHost.running) { [runtimeHost timerFired:runtimeHost.timer]; }
}

- (void)hideInlineTranslationPanelsForGeometryChange {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    runtimeHost.inlineGeometryPending = YES;
    [[FYInlineLayoutDebug shared] clearOverlay];
    NSMutableArray<NSPanel *> *panels = [[runtimeHost.inlineTranslationPanels arrayByAddingObjectsFromArray:runtimeHost.inlineLongCardPanels] mutableCopy];
    if (runtimeHost.inlineExpandedReadingPanel) { [panels addObject:runtimeHost.inlineExpandedReadingPanel]; }
    for (NSPanel *panel in panels) {
        if (panel.isVisible) { [panel orderOut:nil]; }
    }
}

- (void)refreshDisplayGeometryIfNeeded:(BOOL)force {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    NSDate *now = [NSDate date];
    if (![self.displayTargetTracker beginProbeAt:now force:force]) { return; }

    NSArray *windowList = runtimeHost.overlayWindowSnapshot ?: [runtimeHost onScreenWindowInfos];
    BOOL ambiguous = NO;
    NSString *note = nil;
    uint32_t resolved = [runtimeHost resolveDisplayTargetWindowIDInWindowList:windowList ambiguous:&ambiguous note:&note];
    BOOL targetChanged = [self.displayTargetTracker acceptTargetID:resolved ambiguous:ambiguous];

    if (targetChanged) {
        CGRect targetBounds = CGRectZero;
        BOOL hasTargetBounds = resolved != 0 && [runtimeHost liveBoundsForWindowID:resolved outBounds:&targetBounds];
        FuyiDiagLog(@"  TARGET id=%u ambiguous=%d bounds=%@ note=<%@>",
                    resolved, ambiguous ? 1 : 0,
                    hasTargetBounds ? NSStringFromRect(targetBounds) : @"(未知)", FYDiagTextLength(note));
    }
    if (ambiguous) {
        // 多个投影、无法确定画面在哪一块：先隐藏旧贴译并提示选择，绝不猜一个窗口。
        [self.displayTargetTracker advanceAmbiguousGeometry];
        [runtimeHost resetInlineLayoutCacheAfterMappingChange];
        [runtimeHost hideInlineTranslationPanelsForGeometryChange];
        [runtimeHost showInlineMappingUnavailableNotice:note ?: @"检测到多个可能是游戏画面的窗口，请重新选择显示窗口"];
        return;
    }

    NSRect placement = NSZeroRect;
    NSString *placementReason = nil;
    BOOL hasPlacement = [runtimeHost inlinePlacementRect:&placement reason:&placementReason];
    if (![self.displayTargetTracker recordPlacement:hasPlacement rect:placement
        targetID:[runtimeHost displayTargetWindowID] targetChanged:targetChanged]) { return; }
    if (targetChanged) { [runtimeHost resetInlineLayoutCacheAfterMappingChange]; }

    if (runtimeHost.inlineExpandedReadingPanel) {
        // 展开卡跟着最新有效映射走；定位暂时不可用就收起，绝不留在旧坐标。
        if (hasPlacement) {
            [runtimeHost repositionExpandedInlineReadingCardInRect:placement];
        } else {
            [runtimeHost closeExpandedInlineReadingCard];
        }
    }
    if (!hasPlacement) {
        [runtimeHost hideInlineTranslationPanelsForGeometryChange];
        // 选中的窗口已经关闭时用下拉框那条更具体的提示（「原窗口已关闭，请重新选择」），
        // 不要被笼统的"请先选择显示窗口"盖掉。
        NSString *message = (runtimeHost.windowSelectionLost && runtimeHost.windowPickerPlaceholder.length > 0)
            ? runtimeHost.windowPickerPlaceholder : note;
        if (message.length > 0) { [runtimeHost showInlineMappingUnavailableNotice:message]; }
        return;
    }
    if (targetChanged) {
        // 换了承载画面的窗口（OBS 编辑器 ↔ 全屏投影）：旧原文块是**另一个窗口的坐标系**，
        // 拿它们按新窗口重排只会得到一个位置错误但看起来"跟过去了"的假象。
        // 先隐藏旧贴译，等这一轮 OCR 用新窗口的画面重新出块，再用缓存译文按正确位置贴回来。
        [runtimeHost hideInlineTranslationPanelsForGeometryChange];
        return;
    }
    // 同一个窗口只是移动/缩放：原文块的归一化坐标仍然有效，直接用**已有译文**按新几何重排。
    if (runtimeHost.lastInlineRenderedTranslations.count > 0 && runtimeHost.lastInlineRenderedItems.count > 0 &&
        runtimeHost.lastInlineRenderedTranslations.count == runtimeHost.lastInlineRenderedItems.count) {
        [runtimeHost showInlineTranslations:runtimeHost.lastInlineRenderedTranslations
                            forItems:runtimeHost.lastInlineRenderedItems
                       placementRect:placement];
    }
}

- (void)updateWindowCardCopy {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    BOOL captureCard = [runtimeHost captureCardInputEnabled];
    if (runtimeHost.windowCardTitleLabel) {
        runtimeHost.windowCardTitleLabel.stringValue = captureCard ? @"游戏画面所在窗口" : @"要翻译的窗口";
    }
    if (runtimeHost.windowCardHintLabel) {
        runtimeHost.windowCardHintLabel.stringValue = captureCard
            ? @"选择显示游戏画面的窗口，字幕和贴译将跟随它。"
            : @"这个窗口既是识别画面的来源，也是字幕和贴译跟随的位置；换窗口会重新识别。";
    }
    if (runtimeHost.windowScopeButton) {
        BOOL hasRecommended = [runtimeHost hasRecommendedWindowItems];
        // 没有推荐窗口时精简列表本来就等于全部，这个入口没有意义，藏起来但列表不为空。
        runtimeHost.windowScopeButton.hidden = !hasRecommended;
        runtimeHost.windowScopeButton.enabled = hasRecommended;
        runtimeHost.windowScopeButton.title = runtimeHost.showAllWindowsInPicker ? @"只看推荐窗口" : @"显示全部窗口";
    }
    if (!runtimeHost.windowCardNoteLabel) { return; }
    NSMutableString *note = [NSMutableString string];
    [note appendString:captureCard
        ? @"上面的「采集卡设备」提供识别画面；这里选的是译文要跟随的显示窗口，两者是分开的。"
        : @"识别来源就是这里选中的窗口（字幕仍显示在悬浮字幕窗上）。"];
    if (runtimeHost.windowPickerPlaceholder.length > 0) {
        [note appendFormat:@" %@", runtimeHost.windowPickerPlaceholder];
    } else if (runtimeHost.windowPopup.numberOfItems > 0) {
        if (![runtimeHost hasRecommendedWindowItems]) {
            [note appendString:@" 没有检测到 OBS／QuickTime／全屏游戏窗口，已列出全部窗口。"];
        } else if (runtimeHost.showAllWindowsInPicker) {
            [note appendFormat:@" 正在显示全部 %lu 个窗口。", (unsigned long)runtimeHost.windowPopup.numberOfItems];
        } else {
            [note appendString:@" 精简列表：优先 OBS／QuickTime／全屏游戏窗口；浏览器、模拟器等点「显示全部窗口」。"];
        }
    }
    runtimeHost.windowCardNoteLabel.stringValue = note;
}

- (FYCaptureCardInput *)captureCardInput {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (!_captureCardInput) {
        _captureCardInput = [FYCaptureCardInput new];
        __weak typeof(runtimeHost) weakSelf = runtimeHost;
        _captureCardInput.stateChangeHandler = ^{
            typeof(runtimeHost) strongSelf = weakSelf;
            if (!strongSelf) { return; }
            [strongSelf updateCaptureCardStatus];
            // 断开/出错/被中断时只说明原因，绝不用旧帧继续翻译。
            if (strongSelf.running && [strongSelf captureCardInputEnabled] &&
                strongSelf.captureCardInput.state != FYCaptureCardSessionStateRunning &&
                strongSelf.captureCardInput.state != FYCaptureCardSessionStateStarting) {
                [strongSelf setStatus:strongSelf.captureCardInput.stateDetail];
            }
        };
    }
    return _captureCardInput;
}

- (BOOL)captureCardInputEnabled {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return runtimeHost.inputSourceSegment == 1;
}

- (void)updateCaptureCardStatus {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    BOOL enabled = [runtimeHost captureCardInputEnabled];
    // 采集卡专属控件只在采集卡模式下出现；窗口截图模式只留一行说明。
    if (runtimeHost.captureCardControlsView) { runtimeHost.captureCardControlsView.hidden = !enabled; }
    if (runtimeHost.inputSourceHintLabel) {
        runtimeHost.inputSourceHintLabel.stringValue = enabled
            ? @"从采集卡直接读取 HDMI 画面：画面里没有 QuickTime／OBS 的控件，也不需要屏幕录制权限；第一次连接时会弹一次相机权限。"
            : @"截取下面选定的那个窗口（QuickTime／OBS）：需要屏幕录制权限，且窗口里的控件（例如 QuickTime 录制条）会一起被截进去。";
    }
    if (!runtimeHost.captureStatusLabel) { return; }
    // 刻意用 ivar 而不是 getter：刷新状态行不应该为了显示"未启动"
    // 就去创建采集对象、查询相机权限（那是 XPC 调用，每次 loadSettings 都做没有意义）。
    FYCaptureCardInput *input = _captureCardInput;
    if (!enabled) {
        runtimeHost.captureStatusLabel.stringValue = @"";
        if (runtimeHost.captureSettingsButton) { runtimeHost.captureSettingsButton.hidden = YES; }
        return;
    }
    if (!input) {
        runtimeHost.captureStatusLabel.stringValue = @"识别输入源：采集卡 · 未启动 · 相机权限：连接时才会查询";
        if (runtimeHost.captureSettingsButton) { runtimeHost.captureSettingsButton.hidden = YES; }
        return;
    }
    FYCaptureCardAvailability availability = [input availability];
    runtimeHost.captureStatusLabel.stringValue = FYCaptureCardStatusText(input.state, availability, input.activeDeviceName,
        input.state == FYCaptureCardSessionStateRunning ? input.receivedFrameCount : 0,
        input.state == FYCaptureCardSessionStateRunning ? input.skippedFrameCount : 0, input.stateDetail);
    // 只有"已被明确拒绝/受限"时系统才不会再次弹窗，这时才需要手动设置入口。
    if (runtimeHost.captureSettingsButton) {
        runtimeHost.captureSettingsButton.hidden = !(availability == FYCaptureCardAvailabilityDenied ||
                                              availability == FYCaptureCardAvailabilityRestricted);
    }
}

- (void)ensureCaptureCardPermissionThen:(void (^)(BOOL granted))continuation {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (!continuation) { return; }
    FYCaptureCardAvailability availability = [runtimeHost.captureCardInput availability];
    FYCapturePermissionAction action=FYCapturePermissionActionForAvailability(availability);
    if (action == FYCapturePermissionActionContinue) { continuation(YES); return; }
    if (action == FYCapturePermissionActionRequest) {
        [runtimeHost setStatus:@"正在申请相机权限：请在系统提示里点「允许」"];
        __weak typeof(runtimeHost) weakSelf = runtimeHost;
        [runtimeHost.captureCardInput requestAccessWithCompletion:^(FYCaptureCardAvailability result) {
            typeof(runtimeHost) strongSelf = weakSelf;
            if (!strongSelf) { return; }
            [strongSelf updateCaptureCardStatus];
            continuation(result == FYCaptureCardAvailabilityAuthorized);
        }];
        return;
    }
    [runtimeHost updateCaptureCardStatus];
    [runtimeHost setStatus:[NSString stringWithFormat:@"相机权限%@：请点「打开相机权限设置」允许译芽后重试；不会改用其他摄像头",
                                               FYCaptureCardAvailabilityLabel(availability)]];
    continuation(NO);
}

- (NSString *)captionLinesFromTranslations:(NSArray<NSString *> *)translations {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *value in translations) {
        NSString *clean = Trim(value);
        if (clean.length == 0) { continue; }
        [lines addObject:clean];
        if (lines.count >= 5) { break; }
    }
    return lines.count > 0 ? [lines componentsJoinedByString:@"\n"] : @"（本帧没有可显示的译文）";
}

- (nullable NSString *)captureDeviceIDFromPopup {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;    if (!runtimeHost.captureDevicePopup || !runtimeHost.captureDevicePopup.enabled) { return nil; }
    id represented = runtimeHost.captureDevicePopup.selectedItem.representedObject;
    return [represented isKindOfClass:NSString.class] ? represented : nil;
}

- (void)refreshCaptureDevices:(id)sender {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (!runtimeHost.captureDevicePopup) { return; }
    NSArray<FYCaptureCardDeviceInfo *> *devices = [runtimeHost.captureCardInput availableDevices];
    NSString *previous = runtimeHost.selectedCaptureDeviceID;
    [runtimeHost.captureDevicePopup removeAllItems];

    if (devices.count == 0) {
        [runtimeHost.captureDevicePopup addItemWithTitle:@"未检测到采集卡"];
        runtimeHost.captureDevicePopup.enabled = NO;
        runtimeHost.selectedCaptureDeviceID = nil;
        runtimeHost.captureDeviceListLoaded = YES;
        [runtimeHost updateCaptureCardStatus];
        [runtimeHost setStatus:@"未检测到采集卡：请连接采集卡后点「刷新设备」；不会自动改用内置或手机摄像头"];
        return;
    }

    runtimeHost.captureDevicePopup.enabled = YES;
    NSInteger selection = 0;
    for (NSInteger index = 0; index < devices.count; index++) {
        FYCaptureCardDeviceInfo *info = devices[index];
        NSString *title = info.inUseByAnotherApplication
            ? [NSString stringWithFormat:@"%@（其他程序正在使用）", info.displayName]
            : info.displayName;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        item.representedObject = info.uniqueID;
        [runtimeHost.captureDevicePopup.menu addItem:item];
        if (previous.length > 0 && [info.uniqueID isEqualToString:previous]) { selection = index; }
    }
    [runtimeHost.captureDevicePopup selectItemAtIndex:selection];
    runtimeHost.selectedCaptureDeviceID = [runtimeHost captureDeviceIDFromPopup];
    runtimeHost.captureDeviceListLoaded = YES;
    [runtimeHost updateCaptureCardStatus];
    [runtimeHost setStatus:[NSString stringWithFormat:@"检测到 %lu 台采集卡，请选择后点「开始翻译」",
                                               (unsigned long)devices.count]];
}

- (void)captureDeviceChanged:(id)sender {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    runtimeHost.selectedCaptureDeviceID = [runtimeHost captureDeviceIDFromPopup];
    [runtimeHost scheduleSettingsSave];
    if ([runtimeHost captureCardInputEnabled] && runtimeHost.running) {
        // 换设备 = 换会话：先释放旧会话并作废旧帧，再按新设备重新开始。
        [runtimeHost reconnectCaptureDevice:nil];
        return;
    }
    [runtimeHost updateCaptureCardStatus];
}

- (void)inputSourceChanged:(id)sender {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    NSInteger segment = runtimeHost.inputSourceControl.selectedSegment == 1 ? 1 : 0;
    if (segment == runtimeHost.inputSourceSegment) { return; }
    runtimeHost.inputSourceSegment = segment;
    [runtimeHost resetForInputSourceChange];
    if (segment == 1) {
        [runtimeHost refreshCaptureDevices:nil];
        if (runtimeHost.running && ![runtimeHost startCaptureCardSessionIfPossible]) {
            // 运行中切到采集卡但起不来（权限被拒／设备缺失／被占用）：停下来并说明原因，
            // 而不是继续显示"正在运行"却每轮空转。
            NSString *reason = runtimeHost.captureCardInput.stateDetail;
            [runtimeHost stop];
            [runtimeHost setStatus:reason.length > 0 ? reason : @"采集卡未能启动"];
        } else if (runtimeHost.running) {
            [runtimeHost setStatus:@"识别输入源已切换为采集卡；字幕仍显示在下方选中的窗口上"];
        } else {
            [runtimeHost setStatus:@"识别输入源已切换为采集卡；确认设备与权限后点「开始翻译」"];
        }
        [runtimeHost updateCaptureCardStatus];
    } else {
        runtimeHost.captureCardInput.previewActive = NO;
        [runtimeHost.captureCardInput stop];
        if (runtimeHost.running) { [runtimeHost timerFired:runtimeHost.timer]; }
        [runtimeHost setStatus:@"识别输入源已切换为窗口截图"];
        [runtimeHost updateCaptureCardStatus];
    }
    [runtimeHost scheduleSettingsSave];
}

- (void)resetForInputSourceChange {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    [runtimeHost updateWindowCardCopy];
    // 换输入源会让"画面区域"的含义完全不同（窗口整窗 ↔ 采集帧适配矩形）：几何重新解析。
    runtimeHost.displayTargetResolved = NO;
    runtimeHost.displayTargetAmbiguous = NO;
    runtimeHost.resolvedDisplayTargetID = 0;
    runtimeHost.lastDisplayGeometryToken = nil;
    [runtimeHost advanceTranslationGeneration];
    runtimeHost.inFlight = NO;
    runtimeHost.captureUnavailable = NO;
    [[runtimeHost translationState] reset];
    [[runtimeHost stabilityOwner] reset];
    runtimeHost.lastOCRedCaptureFrameIndex = 0;
    runtimeHost.lastPreviewDate = nil;
    [[runtimeHost inlineCache] clear];
    [runtimeHost clearInlineTranslationPanels];
    runtimeHost.latestTranslationLabel.stringValue = @"等待译文";
    runtimeHost.latestSourceLabel.stringValue = @"";
    [runtimeHost showPreviewUnavailable:[runtimeHost captureCardInputEnabled] ? @"等待采集卡画面" : @"选择窗口并开始翻译后显示画面"];
    [runtimeHost updateRunState];
    [runtimeHost restartPreviewTimerIfRunning];
}

- (BOOL)startCaptureCardSessionIfPossible {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (![runtimeHost captureCardInputEnabled]) { return YES; }
    FYCaptureCardInput *input = runtimeHost.captureCardInput;
    if (input.state == FYCaptureCardSessionStateRunning && runtimeHost.selectedCaptureDeviceID.length > 0) { return YES; }

    if (!runtimeHost.captureDeviceListLoaded) { [runtimeHost refreshCaptureDevices:nil]; }
    if (runtimeHost.selectedCaptureDeviceID.length == 0) { runtimeHost.selectedCaptureDeviceID = [runtimeHost captureDeviceIDFromPopup]; }
    if (runtimeHost.selectedCaptureDeviceID.length == 0) {
        [runtimeHost setStatus:@"未选择采集卡设备：请点「刷新设备」后选择；不会自动改用内置或手机摄像头"];
        [runtimeHost updateCaptureCardStatus];
        return NO;
    }
    runtimeHost.lastOCRedCaptureFrameIndex = 0;
    if (![input startWithDeviceUniqueID:runtimeHost.selectedCaptureDeviceID]) {
        [runtimeHost setStatus:input.stateDetail];
        [runtimeHost updateCaptureCardStatus];
        return NO;
    }
    input.previewActive = runtimeHost.running && runtimeHost.framePreview && [runtimeHost livePreviewVisible];
    [runtimeHost updateCaptureCardStatus];
    return YES;
}

- (void)reconnectCaptureDevice:(id)sender {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    // 重连 = 新会话：先释放旧会话并作废旧帧，避免断开期间继续用旧画面。
    runtimeHost.captureCardInput.previewActive = NO;
    [runtimeHost.captureCardInput stop];
    runtimeHost.lastOCRedCaptureFrameIndex = 0;
    if (![runtimeHost captureCardInputEnabled]) {
        [runtimeHost setStatus:@"当前识别输入源是「窗口截图」，重连采集卡前请先切到采集卡"];
        [runtimeHost updateCaptureCardStatus];
        return;
    }
    [runtimeHost refreshCaptureDevices:nil];
    if ([runtimeHost.captureCardInput availability] != FYCaptureCardAvailabilityAuthorized) {
        __weak typeof(runtimeHost) weakSelf = runtimeHost;
        [runtimeHost ensureCaptureCardPermissionThen:^(BOOL granted) {
            typeof(runtimeHost) strongSelf = weakSelf;
            if (!strongSelf) { return; }
            if (granted) { [strongSelf reconnectCaptureDevice:nil]; }
        }];
        return;
    }
    if (![runtimeHost startCaptureCardSessionIfPossible]) {
        NSString *reason = runtimeHost.captureCardInput.stateDetail;
        if ([runtimeHost.captureCardInput availability] != FYCaptureCardAvailabilityAuthorized) {
            reason = [NSString stringWithFormat:@"%@；可点「申请相机权限」", reason];
        }
        // 重连失败时不能停在"正在运行"却每轮空转。
        if (runtimeHost.running) { [runtimeHost stop]; }
        [runtimeHost setStatus:reason.length > 0 ? reason : @"采集卡未能重连"];
        return;
    }
    if (runtimeHost.running) { [runtimeHost timerFired:runtimeHost.timer]; }
    [runtimeHost setStatus:[NSString stringWithFormat:@"已连接采集卡 %@", runtimeHost.captureCardInput.activeDeviceName ?: @"外接采集设备"]];
}

- (void)openCameraAccessSettings:(id)sender {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"];
    if (!url) { return; }
    [NSWorkspace.sharedWorkspace openURL:url];
    [runtimeHost setStatus:@"已打开系统设置的相机权限页：允许译芽后回到应用点「重连采集卡」"];
}

- (CGRect)selectedOCRScope {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (runtimeHost.manualOCRScopeCheckbox.state != NSControlStateValueOn) return CGRectMake(0,0,1,1);
    return CGRectMake(runtimeHost.regionXSlider.doubleValue,runtimeHost.regionYSlider.doubleValue,runtimeHost.regionWidthSlider.doubleValue,runtimeHost.regionHeightSlider.doubleValue);
}

- (void)selectOCRRegion:(id)sender {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    [runtimeHost refreshDisplayGeometryIfNeeded:YES];
    WindowItem *window = [runtimeHost displayTargetWindowItem];
    if (!window) {
        NSString *message = [runtimeHost captureCardInputEnabled] ? @"请先选择游戏画面所在的显示窗口" : @"请先选择要翻译的窗口";
        [runtimeHost setStatus:message];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = message;
        alert.informativeText = @"在「窗口」列表中选择显示游戏画面的窗口，再点击手动框选。";
        [alert addButtonWithTitle:@"知道了"];
        [alert beginSheetModalForWindow:runtimeHost.mainWindow completionHandler:nil];
        return;
    }

    NSRect scopeViewport=[runtimeHost appKitFrameForWindowItem:window];
    if ([runtimeHost captureCardInputEnabled]) {
        CGSize frameSize = CGSizeZero;
        if (![runtimeHost.captureCardInput latestFrameSize:&frameSize]) {
            [runtimeHost setStatus:@"请先连接采集卡并等待画面，再框选 OCR 区域"];
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"采集卡还没有画面";
            alert.informativeText = @"手动 OCR 范围按采集视频保存。先连接采集卡，收到画面后再框选。";
            [alert addButtonWithTitle:@"重连采集卡"];
            [alert addButtonWithTitle:@"取消"];
            __weak typeof(runtimeHost) weakSelf = runtimeHost;
            [alert beginSheetModalForWindow:runtimeHost.mainWindow completionHandler:^(NSModalResponse response) {
                if (response == NSAlertFirstButtonReturn) { [weakSelf reconnectCaptureDevice:nil]; }
            }];
            return;
        }
        if (![runtimeHost inlinePlacementRect:&scopeViewport reason:NULL]) {
            [runtimeHost setStatus:@"请先定位视频画面，再框选 OCR 区域"];
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"还没有定位视频画面";
            alert.informativeText = @"先在目标窗口框出采集视频的位置；完成后会继续框选 OCR 区域。";
            [alert addButtonWithTitle:@"定位视频画面"];
            [alert addButtonWithTitle:@"取消"];
            __weak typeof(runtimeHost) weakSelf = runtimeHost;
            [alert beginSheetModalForWindow:runtimeHost.mainWindow completionHandler:^(NSModalResponse response) {
                if (response == NSAlertFirstButtonReturn) {
                    weakSelf.selectOCRRegionAfterCaptureCalibration = YES;
                    [weakSelf beginCaptureCardCalibration:nil];
                    if (!weakSelf.captureCalibrationPanel) {
                        weakSelf.selectOCRRegionAfterCaptureCalibration = NO;
                    }
                }
            }];
            return;
        }
    }
    CGFloat screenTop=NSMaxY(NSScreen.mainScreen.frame);
    CGRect quartzViewport=CGRectMake(NSMinX(scopeViewport),screenTop-NSMaxY(scopeViewport),NSWidth(scopeViewport),NSHeight(scopeViewport));
    NSScreen *targetScreen = [runtimeHost screenForWindowItem:window] ?: NSScreen.mainScreen;
    NSRect panelFrame = NSIntersectionRect(scopeViewport, targetScreen.frame);
    if (NSWidth(panelFrame) < 80 || NSHeight(panelFrame) < 80) {
        [runtimeHost setStatus:@"游戏画面未在当前屏幕上，请将它显示出来后重试"];
        return;
    }

    [runtimeHost hideInterfaceForRegionSelection];
    if (runtimeHost.regionSelectionKeyMonitor) {
        [NSEvent removeMonitor:runtimeHost.regionSelectionKeyMonitor];
        runtimeHost.regionSelectionKeyMonitor = nil;
    }
    [runtimeHost.regionSelectionPanel close];

    runtimeHost.regionSelectionPanel = [[FYRegionSelectionPanel alloc] initWithContentRect:panelFrame
                                                           styleMask:NSWindowStyleMaskBorderless
                                                             backing:NSBackingStoreBuffered
                                                               defer:NO];
    runtimeHost.regionSelectionPanel.backgroundColor = [NSColor clearColor];
    runtimeHost.regionSelectionPanel.opaque = NO;
    runtimeHost.regionSelectionPanel.hasShadow = NO;
    runtimeHost.regionSelectionPanel.level = NSScreenSaverWindowLevel;
    runtimeHost.regionSelectionPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;

    RegionSelectionView *selectionView = [[RegionSelectionView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(panelFrame), NSHeight(panelFrame))];
    selectionView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    selectionView.helpFontSize = runtimeHost.captionFontSizeSlider.doubleValue;
    selectionView.helpTextColor = [runtimeHost captionTextColor];

    __weak typeof(runtimeHost) weakSelf = runtimeHost;
    selectionView.completion = ^(CGRect selectedRect, CGSize viewSize, BOOL cancelled) {
        id<FYCaptureRuntimeControllerHost> strongSelf = weakSelf;
        if (!strongSelf) { return; }

        if (strongSelf.regionSelectionKeyMonitor) {
            [NSEvent removeMonitor:strongSelf.regionSelectionKeyMonitor];
            strongSelf.regionSelectionKeyMonitor = nil;
        }
        [strongSelf.regionSelectionPanel close];
        strongSelf.regionSelectionPanel = nil;

        if (cancelled) {
            [strongSelf restoreInterfaceAfterRegionSelectionShowingOCRPreview:NO];
            [strongSelf setStatus:@"已取消框选"];
            return;
        }

        CGRect quartzSelection = [strongSelf quartzRectFromSelectionRect:selectedRect panelFrame:panelFrame];
        CGRect clippedSelection = CGRectIntersection(quartzSelection, quartzViewport);

        if (CGRectIsNull(clippedSelection) || clippedSelection.size.width < 24 || clippedSelection.size.height < 24) {
            [strongSelf restoreInterfaceAfterRegionSelectionShowingOCRPreview:NO];
            [strongSelf setStatus:@"框选区域没有落在游戏画面里"];
            return;
        }

        double x = (clippedSelection.origin.x - quartzViewport.origin.x) / quartzViewport.size.width;
        double y = (clippedSelection.origin.y - quartzViewport.origin.y) / quartzViewport.size.height;
        double width = clippedSelection.size.width / quartzViewport.size.width;
        double height = clippedSelection.size.height / quartzViewport.size.height;

        strongSelf.regionXSlider.doubleValue = MAX(0, MIN(1, x));
        strongSelf.regionYSlider.doubleValue = MAX(0, MIN(1, y));
        strongSelf.regionWidthSlider.doubleValue = MAX(0.05, MIN(1, width));
        strongSelf.regionHeightSlider.doubleValue = MAX(0.05, MIN(1, height));
        strongSelf.manualOCRScopeCheckbox.state=NSControlStateValueOn;
        [strongSelf controlValueChanged:strongSelf.manualOCRScopeCheckbox];
        [strongSelf saveSettings:nil];
        [strongSelf restoreInterfaceAfterRegionSelectionShowingOCRPreview:YES];
        [strongSelf setStatus:[NSString stringWithFormat:@"OCR 区域已更新：x %.2f y %.2f w %.2f h %.2f",
                               strongSelf.regionXSlider.doubleValue,
                               strongSelf.regionYSlider.doubleValue,
                               strongSelf.regionWidthSlider.doubleValue,
                               strongSelf.regionHeightSlider.doubleValue]];
    };

    runtimeHost.regionSelectionPanel.contentView = selectionView;
    [NSApp activateIgnoringOtherApps:YES];
    [runtimeHost.regionSelectionPanel makeKeyAndOrderFront:nil];
    [runtimeHost.regionSelectionPanel makeFirstResponder:selectionView];
    runtimeHost.regionSelectionKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (event.keyCode != 53 || !weakSelf.regionSelectionPanel) { return event; }
        selectionView.completion(CGRectZero, selectionView.bounds.size, YES);
        return nil;
    }];
    [runtimeHost setStatus:@"在游戏画面内拖动框选 OCR 区域，Esc 取消"];
}

- (void)hideInterfaceForRegionSelection {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    runtimeHost.selectingCaptureRegion = YES;
    runtimeHost.mainWindowVisibleBeforeRegionSelection = runtimeHost.mainWindow.isVisible;
    runtimeHost.captionPanelVisibleBeforeRegionSelection = runtimeHost.captionPanel.isVisible;
    runtimeHost.ocrPreviewVisibleBeforeRegionSelection = runtimeHost.ocrPreviewPanel.isVisible;

    [runtimeHost.mainWindow orderOut:nil];
    [runtimeHost.captionPanel orderOut:nil];
    [runtimeHost.ocrPreviewPanel orderOut:nil];
    [runtimeHost.captionDockPanel orderOut:nil];
    [runtimeHost.studyChatPanel orderOut:nil];
    [runtimeHost.quickSourceTextView dismissSourceHover];
    [runtimeHost.quickSentencePanel orderOut:nil];
}

- (void)restoreInterfaceAfterRegionSelectionShowingOCRPreview:(BOOL)showOCRPreview {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (runtimeHost.mainWindowVisibleBeforeRegionSelection) {
        [runtimeHost.mainWindow makeKeyAndOrderFront:nil];
    }

    runtimeHost.selectingCaptureRegion = NO;
    [runtimeHost refreshOverlayVisibility:nil];

    if (showOCRPreview || runtimeHost.ocrPreviewVisibleBeforeRegionSelection) {
        [runtimeHost updateOCRPreviewPanel];
    } else {
        [runtimeHost.ocrPreviewPanel orderOut:nil];
    }

    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showOCRPreview:(id)sender {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if ([runtimeHost updateOCRPreviewPanel]) {
        [runtimeHost setStatus:@"OCR 框已显示"];
    }
}

- (void)hideOCRPreview:(id)sender {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    [runtimeHost.ocrPreviewPanel close];
    runtimeHost.ocrPreviewPanel = nil;
    runtimeHost.ocrPreviewLabel = nil;
    [runtimeHost setStatus:@"OCR 框已隐藏"];
}

- (void)updateOCRPreviewIfVisible {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (runtimeHost.ocrPreviewPanel) {
        [runtimeHost updateOCRPreviewPanel];
    }
}

- (BOOL)livePreviewVisible {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    NSWindow *window = runtimeHost.mainWindow;
    return window && window.isVisible && !window.isMiniaturized && window.isOnActiveSpace &&
        (window.occlusionState & NSWindowOcclusionStateVisible) != 0;
}

- (void)refreshPreviewVisibility:(id)sender {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    BOOL active = runtimeHost.running && runtimeHost.framePreview && [runtimeHost livePreviewVisible];
    runtimeHost.captureCardInput.previewActive = active && [runtimeHost captureCardInputEnabled];
    if (active != (runtimeHost.previewTimer != nil)) { [runtimeHost restartPreviewTimerIfRunning]; }
}

- (void)windowDidChangeOcclusionState:(NSNotification *)notification {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host; [runtimeHost refreshPreviewVisibility:notification]; }

- (void)windowDidMiniaturize:(NSNotification *)notification {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host; [runtimeHost refreshPreviewVisibility:notification]; }

- (void)windowDidDeminiaturize:(NSNotification *)notification {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host; [runtimeHost refreshPreviewVisibility:notification]; }

// This adapter reads UI/resources; the scheduler receives scalar snapshots only.
- (FYLivePreviewSnapshot)previewSnapshot {
    id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (!runtimeHost) { return (FYLivePreviewSnapshot){0}; }
    BOOL visible = [runtimeHost livePreviewVisible];
    BOOL card = [runtimeHost captureCardInputEnabled];
    BOOL active = runtimeHost.running && runtimeHost.framePreview && visible;
    FYCaptureCardInput *input = active ? runtimeHost.captureCardInput : nil;
    return (FYLivePreviewSnapshot){runtimeHost.running, visible, runtimeHost.framePreview != nil, card,
        runtimeHost.translationGeneration, input.sessionEpoch, active ? [runtimeHost displayTargetWindowID] : 0,
        card ? input.latestFrameIndex : 0, card ? FYCaptureCardPreviewFrameInterval : 0.1};
}

- (FYPreviewFrameLease *)previewFrameLeaseForSnapshot:(FYLivePreviewSnapshot)snapshot {
    id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    FYCaptureCardInput *input = runtimeHost.captureCardInput;
    return [[FYPreviewFrameLease alloc] initWithFrameCopy:^CGImageRef(uint64_t *actualIndex) {
        return snapshot.captureCard ? [input copyLatestFrameWithIndex:actualIndex] :
            [runtimeHost copyFullCapturedImageForWindow:snapshot.windowID];
    } sessionEpoch:^NSUInteger { return input.sessionEpoch; }];
}

- (void)refreshPreviewVisibility { [self.host refreshPreviewVisibility:nil]; }
- (void)presentPreviewImage:(CGImageRef)image { [self.host applyPreviewImage:image]; }

- (void)invalidatePreviewResults { [self.previewScheduler invalidateResults]; }

- (void)restartPreviewTimerIfRunning {
    id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    FYLivePreviewSnapshot snapshot = [self previewSnapshot];
    runtimeHost.captureCardInput.previewActive = snapshot.running && snapshot.hasSurface && snapshot.visible && snapshot.captureCard;
    [self.previewScheduler restartWithSnapshot:snapshot timerTarget:runtimeHost];
}

- (void)previewTimerFired:(NSTimer *)timer { [self.previewScheduler tick]; }

- (void)applyPreviewImage:(CGImageRef)image {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    runtimeHost.framePreview.image = [[NSImage alloc] initWithCGImage:image
        size:NSMakeSize(CGImageGetWidth(image), CGImageGetHeight(image))];
    runtimeHost.previewPlaceholder.hidden = YES;
}

- (BOOL)hasScreenAccess {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return CGPreflightScreenCaptureAccess();
}

- (BOOL)hasUsableScreenCaptureAccess {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if ([runtimeHost hasScreenAccess]) {
        return YES;
    }

    return [runtimeHost canCaptureSelectedWindowOnce];
}

- (BOOL)canCaptureSelectedWindowOnce {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    uint32_t windowID = [runtimeHost selectedWindowID];
    if (!windowID) { return NO; }
    // Capturing our own app does not prove that screen-recording access works.
    if (FYWindowOwnerIsYiya([runtimeHost selectedWindowItem].effectiveOwnerName) || [runtimeHost selectedWindowOwnerPID] == getpid()) { return NO; }

    CGImageRef image = [runtimeHost copyFullCapturedImageForWindow:windowID];
    if (!image) { return NO; }

    BOOL usable = CGImageGetWidth(image) > 1 && CGImageGetHeight(image) > 1;
    if (usable) { [runtimeHost updatePreviewFromImage:image generation:runtimeHost.translationGeneration]; }
    CGImageRelease(image);
    return usable;
}

- (void)handleMissingScreenAccessForStart {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    [runtimeHost showPreviewUnavailable:@"无法预览：请检查屏幕录制权限"];
    if (runtimeHost.screenAccessRequestedDuringSession) {
        [runtimeHost setStatus:@"权限还没对当前进程生效；请点“重启 App”"];
        return;
    }

    [runtimeHost setStatus:@"需要屏幕录制权限"];
    [runtimeHost requestScreenAccess:nil];
}

- (uint32_t)selectedWindowID {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    NSNumber *number = runtimeHost.windowPopup.selectedItem.representedObject;
    return number.unsignedIntValue;
}

- (WindowItem *)windowItemForWindowID:(uint32_t)windowID {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (windowID == 0) { return nil; }
    for (WindowItem *item in runtimeHost.windows) {
        if (item.windowID == windowID) { return item; }
    }
    return nil;
}

- (WindowItem *)selectedWindowItem {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [runtimeHost windowItemForWindowID:[runtimeHost selectedWindowID]];
}

- (BOOL)liveBoundsForWindowID:(uint32_t)windowID outBounds:(CGRect *)outBounds {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [[runtimeHost windowManager] liveBoundsForWindowID:windowID outBounds:outBounds];
}

- (uint32_t)resolveDisplayTargetWindowIDInWindowList:(NSArray<NSDictionary *> *)windowList
                                           ambiguous:(BOOL *)outAmbiguous
                                                note:(NSString **)outNote {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [[runtimeHost windowManager] resolveDisplayTargetWindowIDInWindowList:windowList selectedID:[runtimeHost selectedWindowID] ownerPID:[runtimeHost selectedWindowOwnerPID] ambiguous:outAmbiguous note:outNote];
}

- (uint32_t)displayTargetWindowID {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [self.displayTargetTracker windowIDUsingSelection:^uint32_t { return [runtimeHost selectedWindowID]; }];
}

- (WindowItem *)displayTargetWindowItem {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    uint32_t windowID = [runtimeHost displayTargetWindowID];
    if (windowID == 0) { return nil; }
    // 解析出来的目标可能还没进下拉列表（刚出现的全屏投影）。**必须**返回 ID 与解析目标一致的
    // 对象：过去退回 selectedWindowItem（旧 ID），后续 appKitFrameForWindowItem: 按旧 ID 查坐标，
    // 于是"解析到 9602、却拿到 9601 的框"。
    WindowItem *item = [runtimeHost windowItemForWindowID:windowID];
    if (!item) { item = [runtimeHost windowItemForResolvedTargetID:windowID]; }
    if (!item) {
        // 兜底只允许"解析目标 == 用户选择的那个窗口"（ID 一致，是同一扇窗，不算冒充）。
        WindowItem *selectedItem = [runtimeHost selectedWindowItem];
        if (selectedItem && selectedItem.windowID == windowID) { item = selectedItem; }
    }
    CGRect liveBounds = CGRectZero;
    if ([runtimeHost liveBoundsForWindowID:windowID outBounds:&liveBounds]) {
        if (!item) {
            item = [[WindowItem alloc] init];
            item.windowID = windowID;
        }
        item.bounds = liveBounds;
    }
    if (item && item.windowID != windowID) { return nil; }   // 兜底：ID 对不上就不使用
    return item;
}

- (WindowItem *)windowItemForResolvedTargetID:(uint32_t)windowID {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [[runtimeHost windowManager] windowItemForID:windowID];
}

- (NSScreen *)screenForWindowItem:(WindowItem *)item {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    NSRect windowFrame = [runtimeHost appKitFrameForWindowItem:item];
    NSScreen *bestScreen = NSScreen.mainScreen;
    CGFloat bestArea = 0;

    for (NSScreen *screen in NSScreen.screens) {
        NSRect intersection = NSIntersectionRect(screen.frame, windowFrame);
        CGFloat area = NSWidth(intersection) * NSHeight(intersection);
        if (area > bestArea) {
            bestArea = area;
            bestScreen = screen;
        }
    }

    return bestScreen;
}

- (NSRect)appKitFrameForWindowItem:(WindowItem *)item {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    CGRect bounds = item.bounds;
    CGRect liveBounds = CGRectZero;
    if ([runtimeHost liveBoundsForWindowID:item.windowID outBounds:&liveBounds]) { bounds = liveBounds; }
    return [FYGeometryManager appKitFrameForQuartzBounds:bounds mainScreenTop:NSMaxY(NSScreen.mainScreen.frame)];
}

- (BOOL)buildCaptureGridsWithFrame:(double **)outTempl templateW:(size_t *)outTW templateH:(size_t *)outTH
                             scene:(double **)outScene sceneW:(size_t *)outWW sceneH:(size_t *)outWH
                       videoAspect:(CGFloat *)outAspect
                        sceneWidth:(size_t)sceneWidth
                         forWindow:(WindowItem *)window
                            reason:(NSString **)outReason {
    FYCaptureMappingNativeLease *lease = [self mappingLeaseForWindow:window];
    return [self.mappingCoordinator buildGridsWithTemplate:outTempl templateW:outTW templateH:outTH
        scene:outScene sceneW:outWW sceneH:outWH aspect:outAspect sceneWidth:sceneWidth operations:lease reason:outReason];
}

- (BOOL)autoDetectCaptureCardVideoRectForWindow:(WindowItem *)window reason:(NSString **)outReason {
    FYCaptureMappingNativeLease *lease = [self mappingLeaseForWindow:window];
    return [self.mappingCoordinator autoDetectWithOperations:lease reason:outReason observer:^(FYCaptureMappingEvent event) { FYObserveCaptureMapping(event); }];
}

- (void)resetInlineLayoutCacheAfterMappingChange {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    runtimeHost.lastInlineTranslationKey = nil;
    runtimeHost.lastInlineLayoutResult = nil;
    if (runtimeHost.inlineStableBlockIDs) { [runtimeHost.inlineStableBlockIDs removeAllObjects]; }
}

- (double)captureCardMappingScoreForWindow:(WindowItem *)window entry:(NSDictionary *)entry {
    FYCaptureMappingNativeLease *lease = [self mappingLeaseForWindow:window];
    return [self.mappingCoordinator scoreForEntry:entry operations:lease];
}

- (void)storeCaptureCardMapping:(NSRect)screenRect
                     windowFrame:(NSRect)windowFrame
                     videoAspect:(CGFloat)videoAspect
                        deviceID:(NSString *)deviceID
                          source:(NSString *)source
                      confidence:(CGFloat)confidence
                     forWindowID:(uint32_t)windowID {
    FYCaptureMappingNativeLease *lease = [self mappingLeaseForWindow:nil];
    [self.mappingCoordinator storeRect:screenRect windowFrame:windowFrame aspect:videoAspect deviceID:deviceID
        source:source confidence:confidence windowID:windowID operations:lease];
}

- (void)calibrateCaptureCardVideoRect:(NSRect)screenRect
                          windowFrame:(NSRect)windowFrame
                          videoAspect:(CGFloat)videoAspect
                             deviceID:(NSString *)deviceID
                          forWindowID:(uint32_t)windowID {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    [runtimeHost storeCaptureCardMapping:screenRect windowFrame:windowFrame videoAspect:videoAspect
                         deviceID:deviceID source:@"manual" confidence:1.0 forWindowID:windowID];
}

- (void)clearCaptureCardCalibrationForWindowID:(uint32_t)windowID {
    [self.mappingCoordinator clearWindowID:windowID];
}

- (BOOL)captureCardHasCalibratedVideoRectForWindow:(WindowItem *)window {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (!window) { return NO; }
    NSRect rect = NSZeroRect;
    return [runtimeHost captureCardDisplayRectForWindow:window outRect:&rect reason:NULL];
}

- (NSString *)captureCardCalibrationSummaryForWindow:(WindowItem *)window {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (!window) { return @"未选择目标窗口"; }
    NSDictionary *entry = [[runtimeHost mappingCache] entryForWindowID:window.windowID];
    NSRect rect = NSZeroRect;
    if (entry && [runtimeHost captureCardDisplayRectForWindow:window outRect:&rect reason:NULL]) {
        BOOL manual = [entry[@"source"] isEqualToString:@"manual"];
        return [NSString stringWithFormat:@"%@ · 画面区域 %.0f×%.0f", manual ? @"已手动调整" : @"已自动定位", NSWidth(rect), NSHeight(rect)];
    }
    return @"暂时无法定位游戏画面，可调整贴译位置";
}

- (BOOL)captureCardEstimatedDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect {
    FYCaptureMappingNativeLease *lease = [self mappingLeaseForWindow:window];
    return [self.mappingCoordinator estimatedRect:outRect operations:lease];
}

- (BOOL)captureCardDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [runtimeHost captureCardDisplayRectForWindow:window outRect:outRect reason:NULL];
}

- (BOOL)captureCardDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect reason:(NSString **)outReason {
    FYCaptureMappingNativeLease *lease = [self mappingLeaseForWindow:window];
    return [self.mappingCoordinator displayRect:outRect operations:lease reason:outReason observer:^(FYCaptureMappingEvent event) { FYObserveCaptureMapping(event); }];
}

- (void)updateCaptureCalibrationStatus {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (!runtimeHost.captureCalibrationLabel) { return; }
    BOOL captureCard = [runtimeHost captureCardInputEnabled];
    WindowItem *window = [runtimeHost displayTargetWindowItem];
    runtimeHost.captureCalibrationLabel.stringValue = captureCard
        ? [runtimeHost captureCardCalibrationSummaryForWindow:window]
        : @"切换到「采集卡」输入源后可以调整贴译位置。";
    runtimeHost.captureCalibrateButton.enabled = captureCard && window != nil;
    // 「恢复自动定位」只在用户手动调整过之后才有意义。
    NSDictionary *entry = window ? [[runtimeHost mappingCache] entryForWindowID:window.windowID] : nil;
    runtimeHost.captureCalibrateClearButton.enabled = captureCard && [entry[@"source"] isEqualToString:@"manual"];
    runtimeHost.captureCalibrateClearButton.hidden = !runtimeHost.captureCalibrateClearButton.enabled;
}

- (void)beginCaptureCardCalibration:(id)sender {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (![runtimeHost captureCardInputEnabled]) {
        [runtimeHost setStatus:@"先切换到「采集卡」输入源，再调整贴译位置。"];
        return;
    }
    WindowItem *window = [runtimeHost displayTargetWindowItem];
    if (!window) {
        [runtimeHost setStatus:@"先选择一个显示画面的目标窗口，再调整贴译位置。"];
        return;
    }
    CGSize frameSize = CGSizeZero;
    if (![runtimeHost.captureCardInput latestFrameSize:&frameSize]) {
        [runtimeHost setStatus:@"采集卡暂无可用画面：先让采集卡出画，再调整贴译位置。"];
        return;
    }
    NSRect windowFrame = [runtimeHost appKitFrameForWindowItem:window];
    if (NSWidth(windowFrame) < 40 || NSHeight(windowFrame) < 40) {
        [runtimeHost setStatus:@"目标窗口太小，无法调整贴译位置。"];
        return;
    }
    [runtimeHost endCaptureCardCalibration];
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:windowFrame
                                                styleMask:NSWindowStyleMaskBorderless
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.opaque = NO;
    panel.backgroundColor = NSColor.clearColor;
    panel.hasShadow = NO;
    panel.level = NSStatusWindowLevel + 1;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    FYCaptureCalibrationView *view = [[FYCaptureCalibrationView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(windowFrame), NSHeight(windowFrame))];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    __weak typeof(runtimeHost) weakSelf = runtimeHost;
    uint32_t windowID = window.windowID;
    CGFloat videoAspect = frameSize.width / MAX((CGFloat)1, frameSize.height);
    NSString *deviceID = runtimeHost.selectedCaptureDeviceID;
    view.onFinish = ^(NSRect screenRect) {
        [weakSelf finishCaptureCardCalibration:screenRect windowFrame:windowFrame videoAspect:videoAspect deviceID:deviceID windowID:windowID];
    };
    view.onCancel = ^{
        weakSelf.selectOCRRegionAfterCaptureCalibration = NO;
        [weakSelf endCaptureCardCalibration];
        [weakSelf setStatus:@"已取消调整贴译位置。"];
    };
    panel.contentView = view;
    runtimeHost.captureCalibrationPanel = panel;
    [panel makeKeyAndOrderFront:nil];
    [panel makeFirstResponder:view];
    runtimeHost.captureCalibrationKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (event.keyCode != 53) { return event; }
        weakSelf.selectOCRRegionAfterCaptureCalibration = NO;
        [weakSelf endCaptureCardCalibration];
        [weakSelf setStatus:@"已取消调整贴译位置。"];
        return nil;
    }];
    [runtimeHost setStatus:@"在目标窗口上拖出采集卡画面显示的区域，松开完成，Esc 取消。"];
}

- (void)endCaptureCardCalibration {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (runtimeHost.captureCalibrationKeyMonitor) {
        [NSEvent removeMonitor:runtimeHost.captureCalibrationKeyMonitor];
        runtimeHost.captureCalibrationKeyMonitor = nil;
    }
    [runtimeHost.captureCalibrationPanel close];
    runtimeHost.captureCalibrationPanel = nil;
}

- (void)finishCaptureCardCalibration:(NSRect)screenRect
                         windowFrame:(NSRect)windowFrame
                         videoAspect:(CGFloat)videoAspect
                            deviceID:(NSString *)deviceID
                          windowID:(uint32_t)windowID {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    [runtimeHost endCaptureCardCalibration];
    if (NSWidth(screenRect) < 40 || NSHeight(screenRect) < 40) {
        runtimeHost.selectOCRRegionAfterCaptureCalibration = NO;
        [runtimeHost setStatus:@"框选区域太小，未保存。"];
        return;
    }
    [runtimeHost calibrateCaptureCardVideoRect:screenRect windowFrame:windowFrame videoAspect:videoAspect deviceID:deviceID forWindowID:windowID];
    [runtimeHost scheduleSettingsSave];
    [runtimeHost updateCaptureCalibrationStatus];
    [runtimeHost setStatus:[NSString stringWithFormat:@"已按你框选的区域贴译（%.0f×%.0f）。", NSWidth(screenRect), NSHeight(screenRect)]];
    if (runtimeHost.selectOCRRegionAfterCaptureCalibration) {
        runtimeHost.selectOCRRegionAfterCaptureCalibration = NO;
        [runtimeHost selectOCRRegion:nil];
    }
}

- (void)clearCaptureCardCalibration:(id)sender {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    WindowItem *window = [runtimeHost displayTargetWindowItem];
    if (!window) { return; }
    [runtimeHost clearCaptureCardCalibrationForWindowID:window.windowID];
    [runtimeHost scheduleSettingsSave];
    [runtimeHost updateCaptureCalibrationStatus];
    [runtimeHost setStatus:@"已恢复自动定位。"];
}

- (NSString *)inlineTargetUnavailableReasonWithFallback:(NSString *)fallback {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    if (runtimeHost.displayTargetAmbiguous) { return @"检测到多个可能是游戏画面的窗口，请重新选择显示窗口"; }
    if (runtimeHost.windowSelectionLost && runtimeHost.windowPickerPlaceholder.length > 0) { return runtimeHost.windowPickerPlaceholder; }
    return fallback;
}

- (BOOL)inlinePlacementRect:(NSRect *)outRect reason:(NSString **)outReason {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    WindowItem *window = [runtimeHost displayTargetWindowItem];
    if (![runtimeHost captureCardInputEnabled]) {
        if (!window) {
            if (outReason) { *outReason = [runtimeHost inlineTargetUnavailableReasonWithFallback:@"未选择目标窗口，界面文字暂不贴译。"]; }
            return NO;
        }
        if (outRect) { *outRect = [runtimeHost appKitFrameForWindowItem:window]; }
        return YES;
    }
    CGSize frameSize = CGSizeZero;
    if (![runtimeHost.captureCardInput latestFrameSize:&frameSize]) {
        if (outReason) { *outReason = @"采集卡暂无可用画面，出画后会自动贴上译文。"; }
        return NO;
    }
    if (!window) {
        if (outReason) { *outReason = [runtimeHost inlineTargetUnavailableReasonWithFallback:@"暂时无法定位游戏画面，可调整贴译位置"]; }
        return NO;
    }
    NSRect mapped = NSZeroRect;
    NSString *mappedReason = nil;
    if ([runtimeHost captureCardDisplayRectForWindow:window outRect:&mapped reason:&mappedReason]) {
        if (outRect) { *outRect = mapped; }
        return YES;
    }
    FuyiDiagLog(@"CAPTURE-MAPPING unusable reason=<%@>", FYDiagTextLength(mappedReason));
    // 没有可用的映射（首次使用 / 变了窗口或输入源）：自动定位一次，用户不需要先手动校准。
    if ([runtimeHost autoDetectCaptureCardVideoRectForWindow:window reason:NULL] &&
        [runtimeHost captureCardDisplayRectForWindow:window outRect:&mapped reason:NULL]) {
        if (outRect) { *outRect = mapped; }
        return YES;
    }
    if (outReason) { *outReason = @"暂时无法定位游戏画面，可调整贴译位置"; }
    return NO;
}

- (void)showInlineMappingUnavailableNotice:(NSString *)reason {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    [runtimeHost setStatus:reason.length ? reason : @"暂时无法定位游戏画面，可调整贴译位置"];
    FuyiDiagLog(@"INLINE-MAPPING-UNAVAILABLE %@", FYDiagTextLength(reason));
}

- (CGRect)quartzRectFromSelectionRect:(CGRect)selectionRect panelFrame:(NSRect)panelFrame {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [FYGeometryManager quartzRectFromSelection:selectionRect panelFrame:panelFrame mainScreenTop:NSMaxY(NSScreen.mainScreen.frame)];
}

- (NSRect)appKitOCRPreviewFrameForWindowItem:(WindowItem *)item {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    NSRect frame = [runtimeHost appKitFrameForWindowItem:item];
    if ([runtimeHost captureCardInputEnabled] && ![runtimeHost captureCardDisplayRectForWindow:item outRect:&frame]) return NSZeroRect;
    CGRect box = CGRectMake(runtimeHost.regionXSlider.doubleValue, runtimeHost.regionYSlider.doubleValue, runtimeHost.regionWidthSlider.doubleValue, runtimeHost.regionHeightSlider.doubleValue);
    return [FYGeometryManager frameForTopLeftNormalizedBox:box inViewport:frame];
}

- (BOOL)updateOCRPreviewPanel {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    WindowItem *window = [runtimeHost displayTargetWindowItem];
    if (!window) {
        [runtimeHost setStatus:[runtimeHost captureCardInputEnabled] ? @"请先选择游戏画面所在的显示窗口" : @"请先选择要翻译的窗口"];
        return NO;
    }

    NSRect frame = [runtimeHost appKitOCRPreviewFrameForWindowItem:window];
    if (NSWidth(frame) < 24 || NSHeight(frame) < 24) {
        [runtimeHost setStatus:@"OCR 框太小，无法显示"];
        return NO;
    }

    if (!runtimeHost.ocrPreviewPanel) {
        runtimeHost.ocrPreviewPanel = [[NSPanel alloc] initWithContentRect:frame
                                                          styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO];
        runtimeHost.ocrPreviewPanel.backgroundColor = [NSColor clearColor];
        runtimeHost.ocrPreviewPanel.opaque = NO;
        runtimeHost.ocrPreviewPanel.hasShadow = NO;
        runtimeHost.ocrPreviewPanel.ignoresMouseEvents = YES;
        // 取景框要“最底层”：用普通窗口层级，别压在其他东西上面。
        // 曾经是 NSStatusWindowLevel(25)，比悬浮字幕窗还高，会盖住游戏文字；
        // 而且它中间原来是 8% 蓝色填充，等于在游戏画面上多蒙了一层，
        // 让取景框里的字被染色 / 被 QuickTime 录制条和它一起遮挡。
        runtimeHost.ocrPreviewPanel.level = NSNormalWindowLevel;
        runtimeHost.ocrPreviewPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;

        NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame))];
        content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        content.wantsLayer = YES;
        // 中间完全透明，**一笔都不画**，只留边框：
        // 这样取景框不会给游戏画面增加任何遮挡，OCR 读到什么用户就看到什么。
        content.layer.backgroundColor = NSColor.clearColor.CGColor;
        content.layer.borderColor = [runtimeHost captionTextColor].CGColor;
        content.layer.borderWidth = 3;
        content.layer.cornerRadius = 8;

        runtimeHost.ocrPreviewLabel = [runtimeHost label:@"OCR 识别区域" font:FYUIFont(MAX((CGFloat)12, runtimeHost.captionFontSizeSlider.doubleValue * 0.5), NSFontWeightBold) color:[runtimeHost captionTextColor]];
        runtimeHost.ocrPreviewLabel.wantsLayer = YES;
        runtimeHost.ocrPreviewLabel.layer.backgroundColor = [FYAppearanceBackdropForText([runtimeHost captionTextColor]) colorWithAlphaComponent:0.94].CGColor;
        runtimeHost.ocrPreviewLabel.layer.cornerRadius = 5;
        runtimeHost.ocrPreviewLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:runtimeHost.ocrPreviewLabel];
        [NSLayoutConstraint activateConstraints:@[
            [runtimeHost.ocrPreviewLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:10],
            [runtimeHost.ocrPreviewLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:8]
        ]];

        runtimeHost.ocrPreviewPanel.contentView = content;
    }

    runtimeHost.ocrPreviewPanel.contentView.layer.borderColor = [runtimeHost captionTextColor].CGColor;
    runtimeHost.ocrPreviewLabel.font = FYUIFont(MAX((CGFloat)12, runtimeHost.captionFontSizeSlider.doubleValue * 0.5), NSFontWeightBold);
    runtimeHost.ocrPreviewLabel.textColor = [runtimeHost captionTextColor];
    runtimeHost.ocrPreviewLabel.layer.backgroundColor = [FYAppearanceBackdropForText([runtimeHost captionTextColor]) colorWithAlphaComponent:0.94].CGColor;
    [runtimeHost.ocrPreviewPanel setFrame:frame display:YES];
    [runtimeHost.ocrPreviewPanel orderFrontRegardless];
    return YES;
}

- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)windowID {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [runtimeHost copyCapturedImageForWindow:windowID regionX:0 regionY:0 regionWidth:1 regionHeight:1];
}

- (CGImageRef)copyCapturedImageForWindow:(uint32_t)windowID regionX:(double)x regionY:(double)y regionWidth:(double)width regionHeight:(double)height {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    CGImageRef image = CGWindowListCreateImage(
        CGRectNull,
        kCGWindowListOptionIncludingWindow,
        (CGWindowID)windowID,
        kCGWindowImageBoundsIgnoreFraming | kCGWindowImageNominalResolution
    );
    if (!image) { return nil; }

    CGImageRef cropped = FYCopyCapturedRegion(image, CGRectMake(x, y, width, height));
    CGImageRelease(image);
    return cropped;
}

- (NSString *)recognizeEnlargedRegionOfImage:(CGImageRef)image
                                    regionX:(double)x
                                    regionY:(double)y
                                regionWidth:(double)width
                               regionHeight:(double)height
                                     fastOCR:(BOOL)fastOCR
                             languageSegment:(NSInteger)languageSegment
                                      blocks:(NSArray<OCRTextItem *> **)outBlocks
                                       error:(NSError **)error {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [FYOCRManager recognizeEnlargedImage:image visionRegion:CGRectMake(x, y, width, height)
        recognizer:^NSString *(CGImageRef scaled, NSArray<OCRTextItem *> **items, NSError **recognitionError) {
            return [runtimeHost recognizeTextBlocksInImage:scaled fastOCR:fastOCR languageSegment:languageSegment blocks:items error:recognitionError];
        } blocks:outBlocks error:error];
}

- (NSString *)recognizeTextBlocksInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment blocks:(NSArray<OCRTextItem *> **)outBlocks error:(NSError **)error {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    NSArray<OCRTextItem *> *items = [runtimeHost recognizeTextItemsInImage:image fastOCR:fastOCR languageSegment:languageSegment error:error];
    FYTrace(FYCurrentTrace(), @"ocr", @{@"stage": @"vision_raw", @"ocr_lines": FYTraceOCRLines(items),
                                      @"blocks": @(items.count), @"error_code": @(error ? (*error).code : 0)});
    // IncludingWindow and capture-card frames exclude our overlay windows.
    // Text-only feedback filtering would delete unchanged dates and shared kanji.
    return [FYOCRManager sourceTextForItems:items blocks:outBlocks];
}

- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment error:(NSError **)error {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    return [[runtimeHost ocrManager] recognizeTextItemsInImage:image fastOCR:fastOCR languageSegment:languageSegment error:error];
}

- (FYAutoLocateSchedule *)locateSchedule {
    return [self.mappingCoordinator locateSchedule];
}

- (NSDate *)lastAutoLocateAttempt {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host; return [runtimeHost locateSchedule].lastAttemptDate; }

- (void)setLastAutoLocateAttempt:(NSDate *)value {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host; [runtimeHost locateSchedule].lastAttemptDate=value; }

- (FYCaptureMappingCache *)mappingCache {
    return [self.mappingCoordinator mappingCache];
}

- (NSMutableDictionary *)captureCardVideoRects {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host; return [runtimeHost mappingCache].entries; }

- (void)setCaptureCardVideoRects:(NSMutableDictionary<NSString *, NSDictionary *> *)value {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host; [runtimeHost mappingCache].entries=value; }

- (FYMappingValidationSchedule *)validationSchedule {
    return [self.mappingCoordinator validationSchedule];
}

- (NSDate *)lastMappingValidationDate {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host; return [runtimeHost validationSchedule].lastValidationDate; }

- (void)setLastMappingValidationDate:(NSDate *)value {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host; [runtimeHost validationSchedule].lastValidationDate=value; }

- (void)showPreviewUnavailable:(NSString *)message {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    runtimeHost.framePreview.image = nil;
    runtimeHost.previewPlaceholder.stringValue = message;
    runtimeHost.previewPlaceholder.hidden = NO;
}

- (void)updatePreviewFromImage:(CGImageRef)image generation:(NSInteger)generation {
    id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    [self.previewScheduler renderStoppedImage:image generation:generation delivery:^(CGImageRef scaled) {
        [runtimeHost applyPreviewImage:scaled];
    }];
}

- (void)clampRegionSliders {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    double x = MIN(MAX(runtimeHost.regionXSlider.doubleValue, 0), 0.95);
    double y = MIN(MAX(runtimeHost.regionYSlider.doubleValue, 0), 0.95);
    double width = MIN(MAX(runtimeHost.regionWidthSlider.doubleValue, 0.05), 1 - x);
    double height = MIN(MAX(runtimeHost.regionHeightSlider.doubleValue, 0.05), 1 - y);
    runtimeHost.regionXSlider.doubleValue = x;
    runtimeHost.regionYSlider.doubleValue = y;
    runtimeHost.regionWidthSlider.doubleValue = width;
    runtimeHost.regionHeightSlider.doubleValue = height;
}

- (void)captureLatestStudySentenceWithCompletion:(void (^)(NSString *,NSError *))completion {
    __attribute__((unused)) id<FYCaptureRuntimeControllerHost> runtimeHost = self.host;
    uint32_t windowID=[runtimeHost selectedWindowID];
    NSInteger generation=runtimeHost.translationGeneration;
    NSInteger language=runtimeHost.languageControl.selectedSegment;
    BOOL dialogueMode=[runtimeHost effectiveModeSegment]==ContentModeDialogue;
    BOOL captureCard=[runtimeHost captureCardInputEnabled];
    NSUInteger inputEpoch=runtimeHost.captureCardInput.sessionEpoch;
    NSSet<NSString *> *rendered=RenderedTranslationSet(runtimeHost.captionTextLabel.stringValue,runtimeHost.inlineTranslationCache);
    // 「引用最新句」的语义是"重新识别当前画面"，不是绑定已显示字幕
    //（「看原句」「问 AI」走 resolveLatestStudyIdentity，仍绑定当前句，行为不变）。
    // 因此它必须和实时循环用同一个识别输入源：采集卡模式取采集卡最新帧，
    // 窗口截图模式才截窗 —— 否则采集卡模式下这个动作又会把录制条拍进去。
    CGImageRef image=captureCard?[runtimeHost.captureCardInput copyLatestFrame]:[runtimeHost copyFullCapturedImageForWindow:windowID];
    if(!image){
        NSString *message=captureCard?@"采集卡暂无画面，请等画面恢复后重新引用。"
                                     :@"无法截取当前画面，请检查游戏窗口后重新引用。";
        completion(@"",[NSError errorWithDomain:@"FYStudyReference" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]);
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil;
        // Nominal-resolution game captures can have dialogue below Vision's
        // accurate-recognition pixel threshold. Upscale this one-off snapshot
        // before recognition; continuous translation keeps its own fast path.
        size_t width=CGImageGetWidth(image),height=CGImageGetHeight(image);
        CGFloat scale=MIN(2.0,4096.0/MAX(width,height));
        CGImageRef enlarged=NULL;
        if(scale>1){
            CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
            CGContextRef context=CGBitmapContextCreate(NULL,(size_t)(width*scale),(size_t)(height*scale),8,0,space,kCGImageAlphaPremultipliedLast);
            CGColorSpaceRelease(space);
            if(context){
                CGContextSetInterpolationQuality(context,kCGInterpolationHigh);
                CGContextDrawImage(context,CGRectMake(0,0,width*scale,height*scale),image);
                enlarged=CGBitmapContextCreateImage(context);CGContextRelease(context);
            }
        }
        NSArray<OCRTextItem *> *blocks=[runtimeHost recognizeTextItemsInImage:enlarged ?: image fastOCR:NO languageSegment:language error:&error];
        if(enlarged){CGImageRelease(enlarged);}
        CGImageRelease(image);
        blocks=OCRItemsExcludingOwnOverlay(blocks,rendered);
        dispatch_async(dispatch_get_main_queue(),^{
            NSError *referenceError=error;
            if(generation!=runtimeHost.translationGeneration || windowID!=[runtimeHost selectedWindowID] ||
               (captureCard && inputEpoch!=runtimeHost.captureCardInput.sessionEpoch)){
                NSString *message=(captureCard && inputEpoch!=runtimeHost.captureCardInput.sessionEpoch)
                    ? @"识别期间采集卡输入已切换，请重新引用。"
                    : @"识别期间目标窗口已切换，请重新引用。";
                completion(@"",[NSError errorWithDomain:@"FYStudyReference" code:2 userInfo:@{NSLocalizedDescriptionKey:message}]);return;
            }
            NSString *source=@"";
            if(!error && dialogueMode){
                NSMutableArray<OCRTextItem *> *dialogue=[NSMutableArray array],*options=[NSMutableArray array];
                SplitDialogueAndOptionsFromItems(SubtitleBandItemsFromBlocks(blocks),blocks,dialogue,options);
                BOOL speakerOnly=NO;
                source=[runtimeHost dialogueTextFromItems:dialogue.count?dialogue:blocks speakerLabelOnly:&speakerOnly];
                if(speakerOnly){source=@"";}
            }else if(!error){source=[[blocks valueForKey:@"text"] componentsJoinedByString:@"\n"];}
            if(!referenceError && NormalizeForComparison(source).length<2){
                referenceError=[NSError errorWithDomain:@"FYStudyReference" code:3 userInfo:@{NSLocalizedDescriptionKey:@"当前画面没有识别到对白，请等文字显示完整后重新引用。"}];
            }
            completion(referenceError?@"":source,referenceError);
        });
    });
}

@end
