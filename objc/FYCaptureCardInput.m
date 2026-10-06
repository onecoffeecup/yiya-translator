#import "FYCaptureCardInput.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

// 采集卡输入：从外接视频采集设备按帧读取画面，交给现有 Vision OCR。
// 设计约束（都来自现场要求，改动前先读 HANDOFF/§采集卡）：
//   * 只采视频、不采音频；不添加任何音频输入。
//   * 只列外接采集设备，并排除内置摄像头、手机接力相机、Desk View —— 绝不默认回退。
//   * 不锁设备格式、不写 activeFormat：QuickTime／OBS 可能同时预览同一设备。
//   * 缓存有界：只保留最近一帧，限速丢弃多余帧，不排队。
//   * 会话代次（sessionEpoch）在开始/停止/断开/运行错误时自增，
//     调用方据此丢弃迟到的旧帧与旧请求，绝不让旧画面更新新会话的字幕。
NSString *FYCaptureCardAvailabilityLabel(FYCaptureCardAvailability value) {
    switch (value) {
        case FYCaptureCardAvailabilityAuthorized: return @"已授权";
        case FYCaptureCardAvailabilityDenied: return @"已拒绝";
        case FYCaptureCardAvailabilityRestricted: return @"受系统限制";
        default: return @"尚未授权";
    }
}

NSString *FYCaptureCardSessionStateLabel(FYCaptureCardSessionState state) {
    switch (state) {
        case FYCaptureCardSessionStateStarting: return @"正在连接采集卡";
        case FYCaptureCardSessionStateRunning: return @"采集卡采集中";
        case FYCaptureCardSessionStateStopped: return @"采集卡已停止";
        case FYCaptureCardSessionStatePermissionDenied: return @"相机权限被拒绝";
        case FYCaptureCardSessionStateNoDevice: return @"未找到所选采集卡";
        case FYCaptureCardSessionStateDeviceUnavailable: return @"采集卡不可用";
        case FYCaptureCardSessionStateDisconnected: return @"采集卡已断开";
        case FYCaptureCardSessionStateFailed: return @"采集卡出错";
        default: return @"采集卡未启动";
    }
}

@implementation FYCaptureCardDeviceInfo
@end

#pragma mark - 单一帧槽

@implementation FYCaptureCardFrameSlot {
    CGImageRef _frame;
    NSTimeInterval _lastStoredTime;
    uint64_t _latestIndex;
    uint64_t _storedCount;
    uint64_t _skippedCount;
}

- (instancetype)init {
    if ((self = [super init])) { _minimumInterval = 0.1; }
    return self;
}

- (void)dealloc {
    if (_frame) { CGImageRelease(_frame); }
}

- (BOOL)shouldStoreFrameAtTime:(NSTimeInterval)now {
    @synchronized(self) {
        if (_frame && _minimumInterval > 0 && (now - _lastStoredTime) < _minimumInterval) {
            _skippedCount += 1;
            return NO;
        }
        return YES;
    }
}

- (void)storeFrame:(CGImageRef)frame index:(uint64_t)index atTime:(NSTimeInterval)now {
    if (!frame) { return; }
    CGImageRef retained = CGImageRetain(frame);
    CGImageRef previous = NULL;
    @synchronized(self) {
        previous = _frame;
        _frame = retained;
        _latestIndex = index;
        _lastStoredTime = now;
        _storedCount += 1;
    }
    if (previous) { CGImageRelease(previous); }
}

- (CGImageRef)copyLatestFrame {
    @synchronized(self) {
        return _frame ? CGImageRetain(_frame) : NULL;
    }
}

- (void)clear {
    CGImageRef previous = NULL;
    @synchronized(self) {
        previous = _frame;
        _frame = NULL;
        _latestIndex = 0;
        _lastStoredTime = 0;
    }
    if (previous) { CGImageRelease(previous); }
}

- (void)resetCounters {
    @synchronized(self) { _storedCount = 0; _skippedCount = 0; }
}

- (uint64_t)latestIndex { @synchronized(self) { return _latestIndex; } }
- (uint64_t)storedCount { @synchronized(self) { return _storedCount; } }
- (uint64_t)skippedCount { @synchronized(self) { return _skippedCount; } }
- (BOOL)hasFrame { @synchronized(self) { return _frame != NULL; } }

@end

#pragma mark - 设备发现

// 外接视频采集设备。macOS 14 起是 AVCaptureDeviceTypeExternal，13 用旧名。
static NSArray<AVCaptureDeviceType> *FYExternalVideoDeviceTypes(void) {
    if (@available(macOS 14.0, *)) {
        return @[AVCaptureDeviceTypeExternal];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return @[AVCaptureDeviceTypeExternalUnknown];
#pragma clang diagnostic pop
}

// 明确要排除的"摄像头"类设备。实测本机 macOS 26/27 的外接枚举里会出现
// 「“iPhone (96)”的相机」，因此除了类型判断，再用型号/名称兜底。
static NSArray<AVCaptureDeviceType> *FYCameraLikeDeviceTypes(void) {
    NSMutableArray<AVCaptureDeviceType> *types = [NSMutableArray array];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [types addObject:AVCaptureDeviceTypeBuiltInWideAngleCamera];
#pragma clang diagnostic pop
    if (@available(macOS 14.0, *)) {
        [types addObject:AVCaptureDeviceTypeContinuityCamera];
        [types addObject:AVCaptureDeviceTypeDeskViewCamera];
    }
    return types;
}

static NSArray<AVCaptureDevice *> *FYDevicesOfTypes(NSArray<AVCaptureDeviceType> *types) {
    AVCaptureDeviceDiscoverySession *session =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:types
                                                               mediaType:AVMediaTypeVideo
                                                                position:AVCaptureDevicePositionUnspecified];
    return session.devices ?: @[];
}

static BOOL FYLooksLikePhoneOrComputerCamera(AVCaptureDevice *device) {
    NSArray<NSString *> *markers = @[@"iPhone", @"iPad", @"Continuity", @"Desk View", @"DeskView"];
    NSString *name = device.localizedName ?: @"";
    NSString *model = device.modelID ?: @"";
    for (NSString *marker in markers) {
        if ([name rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound) { return YES; }
        if ([model rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound) { return YES; }
    }
    for (NSString *prefix in @[@"iPhone", @"iPad"]) {
        if ([model hasPrefix:prefix]) { return YES; }
    }
    return NO;
}

static FYCaptureCardAvailability FYAvailabilityFromAV(AVAuthorizationStatus status) {
    switch (status) {
        case AVAuthorizationStatusAuthorized: return FYCaptureCardAvailabilityAuthorized;
        case AVAuthorizationStatusDenied: return FYCaptureCardAvailabilityDenied;
        case AVAuthorizationStatusRestricted: return FYCaptureCardAvailabilityRestricted;
        default: return FYCaptureCardAvailabilityNotDetermined;
    }
}

#pragma mark - 采集输入

@interface FYCaptureCardInput () <AVCaptureVideoDataOutputSampleBufferDelegate>
@end

@implementation FYCaptureCardInput {
    NSString *_activeDeviceUniqueID;
    NSString *_activeDeviceName;
    AVCaptureSession *_session;
    AVCaptureDeviceInput *_deviceInput;
    AVCaptureVideoDataOutput *_videoOutput;
    AVCaptureDevice *_activeDevice;
    AVCaptureDevice *_pendingDevice;
    NSArray<id> *_observers;
    dispatch_queue_t _sessionQueue;
    dispatch_queue_t _frameQueue;
    CIContext *_imageContext;
    FYCaptureCardFrameSlot *_slot;
    NSUInteger _sessionEpoch;
    NSUInteger _startToken;
    uint64_t _receivedFrames;
    uint64_t _conversionFailures;
    BOOL _sessionReleased;
    FYCaptureCardSessionState _state;
    NSString *_stateDetail;
}

- (instancetype)init {
    if ((self = [super init])) {
        _sessionQueue = dispatch_queue_create("com.nanami.fuyi.capturecard.session", DISPATCH_QUEUE_SERIAL);
        _frameQueue = dispatch_queue_create("com.nanami.fuyi.capturecard.frames", DISPATCH_QUEUE_SERIAL);
        _slot = [FYCaptureCardFrameSlot new];
        _sessionReleased = YES;
        _state = FYCaptureCardSessionStateIdle;
        _stateDetail = @"采集卡未启动";
    }
    return self;
}

- (void)dealloc {
    [self removeSessionObservers];
}

#pragma mark 只读状态

- (FYCaptureCardSessionState)state { @synchronized(self) { return _state; } }
- (NSString *)stateDetail { @synchronized(self) { return _stateDetail ?: @""; } }
- (NSString *)activeDeviceUniqueID { @synchronized(self) { return _activeDeviceUniqueID; } }
- (NSString *)activeDeviceName { @synchronized(self) { return _activeDeviceName; } }
- (NSUInteger)sessionEpoch { @synchronized(self) { return _sessionEpoch; } }
- (BOOL)sessionReleased { @synchronized(self) { return _sessionReleased; } }
- (uint64_t)receivedFrameCount { @synchronized(self) { return _receivedFrames; } }
- (uint64_t)conversionFailureCount { @synchronized(self) { return _conversionFailures; } }
- (uint64_t)skippedFrameCount { return _slot.skippedCount; }
- (uint64_t)storedFrameCount { return _slot.storedCount; }

- (void)setState:(FYCaptureCardSessionState)state detail:(NSString *)detail {
    BOOL changed = NO;
    @synchronized(self) {
        changed = (_state != state) || ![(_stateDetail ?: @"") isEqualToString:(detail ?: @"")];
        _state = state;
        _stateDetail = [detail copy] ?: @"";
    }
    if (changed) { [self notifyStateChange]; }
}

- (void)notifyStateChange {
    void (^handler)(void) = self.stateChangeHandler;
    if (!handler) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{ handler(); });
}

// 作废当前会话：代次自增并立刻丢掉手里的帧。
// 这是"旧帧／旧请求不得更新新会话字幕"的第一道闸门。
- (NSUInteger)invalidateSessionEpoch {
    NSUInteger epoch = 0;
    @synchronized(self) {
        _sessionEpoch += 1;
        epoch = _sessionEpoch;
    }
    [_slot clear];
    return epoch;
}

#pragma mark 权限与设备

- (FYCaptureCardAvailability)availability {
    return FYAvailabilityFromAV([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]);
}

- (void)requestAccessWithCompletion:(void (^)(FYCaptureCardAvailability))completion {
    if (!completion) { return; }
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        FYCaptureCardAvailability availability = granted ? FYCaptureCardAvailabilityAuthorized
                                                        : FYCaptureCardAvailabilityDenied;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(availability); });
    }];
}

- (NSArray<FYCaptureCardDeviceInfo *> *)availableDevices {
    NSMutableSet<NSString *> *excluded = [NSMutableSet set];
    for (AVCaptureDevice *camera in FYDevicesOfTypes(FYCameraLikeDeviceTypes())) {
        if (camera.uniqueID) { [excluded addObject:camera.uniqueID]; }
    }

    NSMutableArray<FYCaptureCardDeviceInfo *> *result = [NSMutableArray array];
    for (AVCaptureDevice *device in FYDevicesOfTypes(FYExternalVideoDeviceTypes())) {
        if (!device.isConnected) { continue; }
        if (device.uniqueID && [excluded containsObject:device.uniqueID]) { continue; }
        if (FYLooksLikePhoneOrComputerCamera(device)) { continue; }
        FYCaptureCardDeviceInfo *info = [FYCaptureCardDeviceInfo new];
        info.uniqueID = device.uniqueID ?: @"";
        info.displayName = device.localizedName ?: @"外接采集设备";
        info.inUseByAnotherApplication = device.isInUseByAnotherApplication;
        [result addObject:info];
    }
    [result sortUsingComparator:^NSComparisonResult(FYCaptureCardDeviceInfo *left, FYCaptureCardDeviceInfo *right) {
        return [left.displayName localizedCaseInsensitiveCompare:right.displayName];
    }];
    return result;
}

- (nullable AVCaptureDevice *)deviceForUniqueID:(NSString *)uniqueID {
    for (AVCaptureDevice *device in FYDevicesOfTypes(FYExternalVideoDeviceTypes())) {
        if ([device.uniqueID isEqualToString:uniqueID] && device.isConnected) { return device; }
    }
    return nil;
}

- (BOOL)isSelectableCaptureCard:(AVCaptureDevice *)device {
    for (AVCaptureDevice *camera in FYDevicesOfTypes(FYCameraLikeDeviceTypes())) {
        if (camera.uniqueID && [camera.uniqueID isEqualToString:device.uniqueID]) { return NO; }
    }
    return !FYLooksLikePhoneOrComputerCamera(device);
}

#pragma mark 开始 / 停止

- (BOOL)startWithDeviceUniqueID:(NSString *)uniqueID {
    if (uniqueID.length == 0) {
        [self setState:FYCaptureCardSessionStateNoDevice detail:@"请先选择采集卡设备（不会自动改用内置或手机摄像头）"];
        return NO;
    }
    // 先彻底作废旧会话与旧帧；随后任何一轮都不会再读到上一台设备的画面。
    NSUInteger token = 0;
    @synchronized(self) {
        _startToken += 1;
        token = _startToken;
    }
    [self invalidateSessionEpoch];
    @synchronized(self) {
        _receivedFrames = 0;
        _conversionFailures = 0;
        _sessionReleased = NO;
    }
    [_slot resetCounters];

    dispatch_async(_sessionQueue, ^{ [self teardownSession]; });

    FYCaptureCardAvailability availability = [self availability];
    if (availability != FYCaptureCardAvailabilityAuthorized) {
        [self setState:FYCaptureCardSessionStatePermissionDenied
                detail:[NSString stringWithFormat:@"相机权限%@：请点「申请相机权限」或到系统设置 › 隐私与安全性 › 相机里允许译芽；不会改用其他摄像头",
                                                  FYCaptureCardAvailabilityLabel(availability)]];
        @synchronized(self) { _sessionReleased = YES; }
        return NO;
    }

    AVCaptureDevice *device = [self deviceForUniqueID:uniqueID];
    if (!device) {
        [self setState:FYCaptureCardSessionStateNoDevice
                detail:@"所选采集卡不存在或未连接；请刷新设备后重新选择，不会自动改用其他摄像头"];
        @synchronized(self) { _sessionReleased = YES; }
        return NO;
    }
    if (![self isSelectableCaptureCard:device]) {
        [self setState:FYCaptureCardSessionStateDeviceUnavailable
                detail:@"该设备不是受支持的采集卡（内置/手机摄像头不在此模式内启用）"];
        @synchronized(self) { _sessionReleased = YES; }
        return NO;
    }

    NSString *name = device.localizedName ?: @"外接采集设备";
    BOOL shared = device.isInUseByAnotherApplication;
    @synchronized(self) {
        _pendingDevice = device;
        _activeDeviceUniqueID = device.uniqueID;
        _activeDeviceName = name;
    }
    [self setState:FYCaptureCardSessionStateStarting
            detail:shared ? [NSString stringWithFormat:@"正在连接采集卡 %@（该设备已被其他程序打开，采集卡通常可共享）", name]
                          : [NSString stringWithFormat:@"正在连接采集卡 %@", name]];

    dispatch_async(_sessionQueue, ^{ [self configureAndStartWithToken:token]; });
    return YES;
}

- (void)stop {
    // 立即作废：调用方此刻开始拿不到任何旧帧，即使释放还在队列里排队。
    [self invalidateSessionEpoch];
    @synchronized(self) { _startToken += 1; }
    NSString *name = self.activeDeviceName;
    dispatch_async(_sessionQueue, ^{ [self teardownSession]; });
    [self setState:FYCaptureCardSessionStateStopped
            detail:name.length ? [NSString stringWithFormat:@"已停止采集卡 %@，采集会话已释放", name]
                               : @"采集卡未启动"];
}

- (BOOL)isCurrentStartToken:(NSUInteger)token {
    @synchronized(self) { return _startToken == token; }
}

- (void)configureAndStartWithToken:(NSUInteger)token {
    AVCaptureDevice *device = nil;
    @synchronized(self) { device = _pendingDevice; }
    if (!device || ![self isCurrentStartToken:token]) { return; }

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) {
        [self failStartWithDetail:[NSString stringWithFormat:@"无法打开采集卡 %@：%@；不会自动改用其他摄像头",
                                                             device.localizedName ?: @"外接采集设备",
                                                             error.localizedDescription ?: @"设备可能被独占"]
                          token:token];
        return;
    }
    if (![self isCurrentStartToken:token]) { return; }

    AVCaptureSession *session = [AVCaptureSession new];
    // 刻意不调用 beginConfiguration / lockForConfiguration / activeFormat：
    // QuickTime、OBS 可能正在同时预览这台采集卡，锁格式会干扰它们的画面。
    if (![session canAddInput:input]) {
        [self failStartWithDetail:[NSString stringWithFormat:@"采集卡 %@ 无法添加视频输入（可能正被独占）", device.localizedName ?: @""]
                          token:token];
        return;
    }
    [session addInput:input];

    AVCaptureVideoDataOutput *output = [AVCaptureVideoDataOutput new];
    // 只保留最新帧：到达晚的帧直接丢，配合单一帧槽形成有界缓存。
    output.alwaysDiscardsLateVideoFrames = YES;
    output.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    [output setSampleBufferDelegate:self queue:_frameQueue];
    if (![session canAddOutput:output]) {
        [session removeInput:input];
        [self failStartWithDetail:[NSString stringWithFormat:@"采集卡 %@ 无法添加视频输出", device.localizedName ?: @""]
                          token:token];
        return;
    }
    [session addOutput:output];

    if (!_imageContext) {
        _imageContext = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
    }

    @synchronized(self) {
        _session = session;
        _deviceInput = input;
        _videoOutput = output;
        _activeDevice = device;
        _pendingDevice = nil;
        _sessionReleased = NO;
    }
    [self installSessionObserversForSession:session device:device];

    [session startRunning];

    if (![self isCurrentStartToken:token]) {
        [self teardownSession];
        return;
    }
    BOOL running = session.isRunning;
    NSString *name = device.localizedName ?: @"外接采集设备";
    @synchronized(self) { _sessionReleased = !running; }
    if (!running) {
        [self setState:FYCaptureCardSessionStateFailed detail:[NSString stringWithFormat:@"采集卡 %@ 启动失败", name]];
        [self teardownSession];
        return;
    }
    [self setState:FYCaptureCardSessionStateRunning
            detail:[NSString stringWithFormat:@"正在采集 %@（只采视频，不采音频）", name]];
}

- (void)failStartWithDetail:(NSString *)detail token:(NSUInteger)token {
    if (![self isCurrentStartToken:token]) {
        [self teardownSession];
        return;
    }
    @synchronized(self) { _sessionReleased = YES; _pendingDevice = nil; }
    [self setState:FYCaptureCardSessionStateDeviceUnavailable detail:detail];
}

// 只在 _sessionQueue 上执行。释放输入输出并清空帧槽。
- (void)teardownSession {
    AVCaptureSession *session = nil;
    AVCaptureVideoDataOutput *output = nil;
    AVCaptureDeviceInput *input = nil;
    @synchronized(self) {
        session = _session; output = _videoOutput; input = _deviceInput;
        _session = nil; _videoOutput = nil; _deviceInput = nil; _activeDevice = nil; _pendingDevice = nil;
    }
    [self removeSessionObservers];
    if (output) { [output setSampleBufferDelegate:nil queue:NULL]; }
    if (session.isRunning) { [session stopRunning]; }
    if (session && output) { [session removeOutput:output]; }
    if (session && input) { [session removeInput:input]; }
    [_slot clear];
    @synchronized(self) { _sessionReleased = YES; }
    [self notifyStateChange];
}

#pragma mark 会话通知

- (void)installSessionObserversForSession:(AVCaptureSession *)session device:(AVCaptureDevice *)device {
    [self removeSessionObservers];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSMutableArray<id> *observers = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    [observers addObject:[center addObserverForName:AVCaptureSessionRuntimeErrorNotification
                                             object:session
                                              queue:nil
                                         usingBlock:^(NSNotification *note) {
        NSError *error = note.userInfo[AVCaptureSessionErrorKey];
        [weakSelf handleRuntimeFailure:error];
    }]];
    [observers addObject:[center addObserverForName:AVCaptureDeviceWasDisconnectedNotification
                                             object:device
                                              queue:nil
                                         usingBlock:^(NSNotification *__unused note) {
        [weakSelf handleDeviceDisconnected];
    }]];
    [observers addObject:[center addObserverForName:AVCaptureSessionWasInterruptedNotification
                                             object:session
                                              queue:nil
                                         usingBlock:^(NSNotification *note) {
        [weakSelf handleSessionInterrupted:note.userInfo];
    }]];
    [observers addObject:[center addObserverForName:AVCaptureSessionInterruptionEndedNotification
                                             object:session
                                              queue:nil
                                         usingBlock:^(NSNotification *__unused note) {
        [weakSelf handleSessionInterruptionEnded];
    }]];
    @synchronized(self) { _observers = observers; }
}

- (void)removeSessionObservers {
    NSArray<id> *observers = nil;
    @synchronized(self) { observers = _observers; _observers = nil; }
    for (id observer in observers) { [[NSNotificationCenter defaultCenter] removeObserver:observer]; }
}

- (void)handleDeviceDisconnected {
    NSString *name = self.activeDeviceName ?: @"采集卡";
    dispatch_async(_sessionQueue, ^{ [self teardownSession]; });
    [self invalidateSessionEpoch];
    [self setState:FYCaptureCardSessionStateDisconnected
            detail:[NSString stringWithFormat:@"%@ 已断开：采集会话已释放，不再使用旧帧；重新连接后点「重连采集卡」", name]];
}

- (void)handleRuntimeFailure:(NSError *)error {
    NSString *name = self.activeDeviceName ?: @"采集卡";
    dispatch_async(_sessionQueue, ^{ [self teardownSession]; });
    [self invalidateSessionEpoch];
    [self setState:FYCaptureCardSessionStateFailed
            detail:[NSString stringWithFormat:@"%@ 采集出错：%@；采集会话已释放", name, error.localizedDescription ?: @"未知错误"]];
}

- (void)handleSessionInterrupted:(NSDictionary *)userInfo {
    (void)userInfo;
    NSString *name = self.activeDeviceName ?: @"采集卡";
    [self setState:FYCaptureCardSessionStateDeviceUnavailable
            detail:[NSString stringWithFormat:@"%@ 采集被系统中断：可能被其他程序独占，请关闭它后点「重连采集卡」", name]];
}

- (void)handleSessionInterruptionEnded {
    NSString *name = self.activeDeviceName ?: @"采集卡";
    [self setState:FYCaptureCardSessionStateRunning
            detail:[NSString stringWithFormat:@"正在采集 %@（中断已结束，只采视频，不采音频）", name]];
}

#pragma mark 取帧

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) { return; }
    uint64_t index = 0;
    @synchronized(self) { _receivedFrames += 1; index = _receivedFrames; }

    // 限速 + 单槽：帧读取与像素转换都在专用队列上，主线程只取结果。
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (![_slot shouldStoreFrameAtTime:now]) { return; }

    CGImageRef image = [self createImageFromPixelBuffer:pixelBuffer];
    if (!image) {
        @synchronized(self) { _conversionFailures += 1; }
        return;
    }
    [_slot storeFrame:image index:index atTime:now];
    CGImageRelease(image);
}

- (CGImageRef)createImageFromPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    if (!image || !_imageContext) { return NULL; }
    return [_imageContext createCGImage:image fromRect:image.extent];
}

- (CGImageRef)copyLatestFrame {
    return [_slot copyLatestFrame];
}

- (uint64_t)latestFrameIndex {
    return _slot.latestIndex;
}

- (BOOL)latestFrameSize:(CGSize *)outSize {
    CGImageRef frame = [self copyLatestFrame];
    if (!frame) { return NO; }
    size_t width = CGImageGetWidth(frame);
    size_t height = CGImageGetHeight(frame);
    CGImageRelease(frame);
    if (width < 2 || height < 2) { return NO; }
    if (outSize) { *outSize = CGSizeMake((CGFloat)width, (CGFloat)height); }
    return YES;
}

@end
