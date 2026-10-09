#import "FYTestCaptureCardInput.h"

@implementation FYTestCaptureCardDevice
@end

@implementation FYTestCaptureCardInput {
    FYCaptureCardSessionState _testState;
    NSString *_testDetail;
    NSString *_testActiveID;
    NSString *_testActiveName;
    NSUInteger _testEpoch;
    BOOL _testReleased;
    BOOL _testPreviewActive;
    uint64_t _testReceived;
    uint64_t _testConversionFailures;
    FYCaptureCardFrameSlot *_testSlot;
    NSMutableArray<NSString *> *_testStartAttempts;
    NSMutableArray<NSString *> *_testStartedSessions;
    NSInteger _testStopCalls;
    NSInteger _testTearDowns;
    NSInteger _testAccessRequests;
}

- (instancetype)init {
    if ((self = [super init])) {
        _testState = FYCaptureCardSessionStateIdle;
        _testDetail = @"测试替身未启动";
        _testReleased = YES;
        _testAvailability = FYCaptureCardAvailabilityNotDetermined;
        _testAvailabilityAfterRequest = FYCaptureCardAvailabilityAuthorized;
        _testDevices = @[];
        _testSlot = [FYCaptureCardFrameSlot new];
        // 测试默认不限速，需要验证限速时显式设置 minimumInterval。
        _testSlot.minimumInterval = 0;
        _testStartAttempts = [NSMutableArray array];
        _testStartedSessions = [NSMutableArray array];
    }
    return self;
}

- (FYCaptureCardFrameSlot *)frameSlot { return _testSlot; }
- (NSMutableArray<NSString *> *)startAttempts { return _testStartAttempts; }
- (NSMutableArray<NSString *> *)startedSessions { return _testStartedSessions; }
- (NSInteger)stopCallCount { return _testStopCalls; }
- (NSInteger)teardownCount { return _testTearDowns; }
- (NSInteger)accessRequestCount { return _testAccessRequests; }

- (FYCaptureCardSessionState)state { return _testState; }
- (NSString *)stateDetail { return _testDetail ?: @""; }
- (NSString *)activeDeviceUniqueID { return _testActiveID; }
- (NSString *)activeDeviceName { return _testActiveName; }
- (NSUInteger)sessionEpoch { return _testEpoch; }
- (BOOL)sessionReleased { return _testReleased; }
- (uint64_t)receivedFrameCount { return _testReceived; }
- (uint64_t)conversionFailureCount { return _testConversionFailures; }
- (uint64_t)storedFrameCount { return _testSlot.storedCount; }
- (uint64_t)skippedFrameCount { return _testSlot.skippedCount; }

- (void)testNotify {
    void (^handler)(void) = self.stateChangeHandler;
    if (!handler) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{ handler(); });
}

- (void)testSetState:(FYCaptureCardSessionState)state detail:(NSString *)detail {
    _testState = state;
    _testDetail = [detail copy] ?: @"";
    [self testNotify];
}

// 与生产实现同义：代次自增 + 立刻丢弃手里的帧。
- (NSUInteger)testInvalidateSessionEpoch {
    _testEpoch += 1;
    [_testSlot clear];
    return _testEpoch;
}

#pragma mark 权限与设备

- (FYCaptureCardAvailability)availability { return _testAvailability; }

- (void)requestAccessWithCompletion:(void (^)(FYCaptureCardAvailability))completion {
    _testAccessRequests += 1;
    // 与系统一样是异步回调：授权状态与回调在同一个主队列块里生效，
    // 调用方必须先收到回调才可能看到新状态。
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_testAvailability = self->_testAvailabilityAfterRequest;
        FYCaptureCardAvailability result = self->_testAvailability;
        [self testSetState:result == FYCaptureCardAvailabilityAuthorized ? FYCaptureCardSessionStateIdle
                                                                    : FYCaptureCardSessionStatePermissionDenied
                   detail:@"权限申请结果已更新"];
        if (completion) { completion(result); }
    });
}

- (NSArray<FYCaptureCardDeviceInfo *> *)availableDevices {
    NSMutableArray<FYCaptureCardDeviceInfo *> *result = [NSMutableArray array];
    for (FYTestCaptureCardDevice *device in _testDevices) {
        FYCaptureCardDeviceInfo *info = [FYCaptureCardDeviceInfo new];
        info.uniqueID = device.uniqueID;
        info.displayName = device.displayName;
        info.inUseByAnotherApplication = device.inUseByAnotherApplication;
        [result addObject:info];
    }
    return result;
}

#pragma mark 开始 / 停止

- (BOOL)startWithDeviceUniqueID:(NSString *)uniqueID {
    [_testStartAttempts addObject:uniqueID ?: @""];
    [self testInvalidateSessionEpoch];
    _testReceived = 0;
    _testConversionFailures = 0;
    [_testSlot resetCounters];
    _testReleased = NO;

    if (uniqueID.length == 0) {
        [self testSetState:FYCaptureCardSessionStateNoDevice detail:@"未选择采集卡设备"];
        _testReleased = YES;
        return NO;
    }
    if (_testAvailability != FYCaptureCardAvailabilityAuthorized) {
        [self testSetState:FYCaptureCardSessionStatePermissionDenied
                    detail:[NSString stringWithFormat:@"相机权限%@：不会改用其他摄像头",
                                                      FYCaptureCardAvailabilityLabel(_testAvailability)]];
        _testReleased = YES;
        return NO;
    }
    FYTestCaptureCardDevice *found = nil;
    for (FYTestCaptureCardDevice *device in _testDevices) {
        if ([device.uniqueID isEqualToString:uniqueID]) { found = device; break; }
    }
    if (!found) {
        [self testSetState:FYCaptureCardSessionStateNoDevice detail:@"所选采集卡不存在或未连接"];
        _testReleased = YES;
        return NO;
    }
    if (found.inUseByAnotherApplication) {
        [self testSetState:FYCaptureCardSessionStateDeviceUnavailable detail:@"采集卡被其他程序独占"];
        _testReleased = YES;
        return NO;
    }

    _testActiveID = found.uniqueID;
    _testActiveName = found.displayName;
    [_testStartedSessions addObject:found.uniqueID];
    _testReleased = NO;
    [self testSetState:FYCaptureCardSessionStateRunning
                detail:[NSString stringWithFormat:@"正在采集 %@（只采视频，不采音频）", found.displayName]];
    return YES;
}

- (void)stop {
    _testStopCalls += 1;
    _testTearDowns += 1;
    [self testInvalidateSessionEpoch];
    _testReleased = YES;
    NSString *name = _testActiveName;
    [self testSetState:FYCaptureCardSessionStateStopped
                detail:name.length ? [NSString stringWithFormat:@"已停止采集卡 %@，采集会话已释放", name]
                                   : @"采集卡未启动"];
}

#pragma mark 模拟

- (BOOL)testEnqueueFrameIndex:(uint64_t)index pixelSize:(size_t)pixelSize {
    return [self testEnqueueFrameIndex:index pixelWidth:pixelSize pixelHeight:pixelSize];
}

- (BOOL)testStoreFrame:(CGImageRef)image index:(uint64_t)index {
    if (!image) { return NO; }
    _testReceived += 1;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (![_testSlot shouldStoreFrameAtTime:now]) { return NO; }
    [_testSlot storeFrame:image index:index atTime:now];
    return YES;
}

- (BOOL)testEnqueueFrameIndex:(uint64_t)index pixelWidth:(size_t)width pixelHeight:(size_t)height {
    _testReceived += 1;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (![_testSlot shouldStoreFrameAtTime:now]) { return NO; }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
                                                 kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) { _testConversionFailures += 1; return NO; }
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!image) { _testConversionFailures += 1; return NO; }
    [_testSlot storeFrame:image index:index atTime:now];
    CGImageRelease(image);
    return YES;
}

- (void)testDisconnectActiveDevice {
    _testTearDowns += 1;
    [self testInvalidateSessionEpoch];
    _testReleased = YES;
    NSString *name = _testActiveName ?: @"采集卡";
    [self testSetState:FYCaptureCardSessionStateDisconnected
                detail:[NSString stringWithFormat:@"%@ 已断开：采集会话已释放，不再使用旧帧；重新连接后点「重连采集卡」", name]];
}

- (void)testSimulateRuntimeFailure {
    _testTearDowns += 1;
    [self testInvalidateSessionEpoch];
    _testReleased = YES;
    [self testSetState:FYCaptureCardSessionStateFailed detail:@"采集出错：采集会话已释放"];
}

- (CGImageRef)copyLatestFrame { return [_testSlot copyLatestFrame]; }
- (CGImageRef)copyLatestFrameWithIndex:(uint64_t *)index { return [_testSlot copyLatestFrameWithIndex:index]; }
// Synthetic input admits explicitly injected frames; cadence is tested on the production slot.
- (BOOL)previewActive { return _testPreviewActive; }
- (void)setPreviewActive:(BOOL)active { _testPreviewActive=active; }
- (uint64_t)latestFrameIndex { return _testSlot.latestIndex; }

@end
