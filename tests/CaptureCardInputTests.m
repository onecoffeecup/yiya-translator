// 采集卡输入：会话生命周期、代次闸门、明确限制与"窗口截图不回退"。
// 全部使用测试替身与合成帧，不打开真实设备、不查询真实权限、不占桌面、不发真实请求。
#import "LearningAppTestSupport.h"
#import "FYTestCaptureCardInput.h"
#import <objc/runtime.h>
#include <sys/stat.h>

// 造一张有强结构的测试画面：固定种子的方块图，便于按内容定位。
static CGImageRef CardPatternImage(size_t width, size_t height, unsigned seed) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!ctx) { return NULL; }
    unsigned state = seed;
    size_t cols = 16, rows = 9;
    for (size_t j = 0; j < rows; j++) {
        for (size_t i = 0; i < cols; i++) {
            state = state * 1103515245u + 12345u;
            double v = ((state >> 16) & 0xFF) / 255.0;
            double v2 = ((state >> 8) & 0xFF) / 255.0;
            CGContextSetRGBFillColor(ctx, v, v2, 1.0 - v, 1);
            CGContextFillRect(ctx, CGRectMake(i * (CGFloat)width / cols, j * (CGFloat)height / rows,
                                              (CGFloat)width / cols + 1, (CGFloat)height / rows + 1));
        }
    }
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return image;
}

// 模拟一个 QuickTime 式窗口截图：深色底 + 顶部标题栏 + 中间的采集画面。
static CGImageRef CardWindowScene(CGImageRef video, size_t width, size_t height, CGRect videoRect, CGFloat titleBar) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!ctx) { return NULL; }
    CGContextSetRGBFillColor(ctx, 0.08, 0.08, 0.09, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, width, height));
    // 标题栏（含几个"按钮"）——自动定位不能把它算进画面
    CGContextSetRGBFillColor(ctx, 0.35, 0.35, 0.37, 1);
    CGContextFillRect(ctx, CGRectMake(0, height - titleBar, width, titleBar));
    CGContextSetRGBFillColor(ctx, 0.86, 0.30, 0.26, 1);
    CGContextFillEllipseInRect(ctx, CGRectMake(16, height - titleBar / 2 - 7, 14, 14));
    CGContextSetRGBFillColor(ctx, 0.95, 0.75, 0.25, 1);
    CGContextFillEllipseInRect(ctx, CGRectMake(38, height - titleBar / 2 - 7, 14, 14));
    CGContextSetRGBFillColor(ctx, 0.30, 0.72, 0.36, 1);
    CGContextFillEllipseInRect(ctx, CGRectMake(60, height - titleBar / 2 - 7, 14, 14));
    if (video) { CGContextDrawImage(ctx, videoRect, video); }
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return image;
}

static void CardShot(NSView *view, NSString *path) {
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    Require([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], @"screenshot write failed");
}
static NSString *CardOutputDirectory(void) {
    const char *dir = getenv("FY_CARD_OUTPUT");
    return dir ? [NSString stringWithUTF8String:dir] : nil;
}
static FYTranslationTrace *CardTrace;
static NSUInteger MockRequests;
static BOOL HoldResponse;
static void (^PendingResponse)(void);

@interface FYTranslationTrace (CaptureCardTest)
+ (instancetype)captureCardTestShared;
@end
@implementation FYTranslationTrace (CaptureCardTest)
+ (instancetype)captureCardTestShared { return CardTrace; }
@end

@interface CardTask : NSObject
@property(copy) void (^response)(void);
- (void)resume;
- (void)cancel;
@end
@implementation CardTask
- (void)resume { if (HoldResponse) { PendingResponse = self.response; } else { self.response(); } }
- (void)cancel {}
@end
@interface CardSession : NSObject
- (id)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion;
@end
@implementation CardSession
- (id)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    MockRequests++;
    // 贴译路由按编号返回（与真实贴译端点一致），对白路由返回普通译文。
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];
    NSString *source = [body[@"messages"] lastObject][@"content"];
    NSString *translated = [source hasPrefix:@"1. "] ? @"1. 采集卡测试界面"
                                                    : [NSString stringWithFormat:@"采集卡测试译文%lu", (unsigned long)MockRequests];
    CardTask *task = [CardTask new];
    task.response = ^{ completion(Envelope(translated), Response(), nil); };
    return task;
}
@end
@interface FYTestURLSession (CaptureCardTest)
+ (id)captureCardTestSession;
@end
@implementation FYTestURLSession (CaptureCardTest)
+ (id)captureCardTestSession { return [CardSession new]; }
@end

@interface CardControl : NSObject
@property NSInteger state;
@property NSInteger selectedSegment;
@property(copy) NSString *stringValue;
@property BOOL enabled;
@end
@implementation CardControl
@end

static FYTestCaptureCardDevice *CardDevice(NSString *uniqueID, NSString *name, BOOL inUse);
static CardControl *CardControlWithSegment(NSInteger segment);
static NSArray *CardFixture(NSString *text, CGFloat width);
static NSArray *CardRecords(NSString *log);
static void ArmCardTrace(NSString *root);


@interface CaptureCardApp : AppDelegate
@property NSArray<OCRTextItem *> *fixture;
@property NSMutableArray<NSString *> *captions;
@property NSMutableArray<NSString *> *statuses;
@property uint32_t fixtureWindowID;
@property(nonatomic, strong) WindowItem *fixtureWindowItem;
@property NSInteger fixtureMode;
@property BOOL fixtureAutoMode;
@property NSUInteger inlineApplies;
@property NSUInteger ocrCalls;
@end
@implementation CaptureCardApp
- (uint32_t)selectedWindowID { return self.fixtureWindowID; }
- (WindowItem *)selectedWindowItem { return self.fixtureWindowItem; }
- (BOOL)autoContentModeEnabled { return self.fixtureAutoMode; }
- (NSInteger)effectiveModeSegment { return self.fixtureMode; }
- (void)updateRunState {}
- (void)setStatus:(NSString *)s { if (s) { [self.statuses addObject:s]; } }
- (void)updatePreviewFromImage:(CGImageRef)i generation:(NSInteger)g {}
- (void)refreshLearningSource {}
- (void)refreshLearningStatus {}
- (void)clearInlineTranslationPanels {}
- (void)setCaptionPanelVisibleForUIMode:(BOOL)m {}
- (void)showError:(NSString *)s {}
- (void)updateTranslationCount {}
- (void)updateCaptionWindowWithText:(NSString *)text status:(NSString *)status { if (text) { [self.captions addObject:text]; } }
- (void)showInlineTranslations:(NSArray *)translations forItems:(NSArray *)items { self.inlineApplies++; }
- (void)showInlineTranslations:(NSArray *)translations forItems:(NSArray *)items placementRect:(NSRect)rect { self.inlineApplies++; }
- (BOOL)hasUsableScreenCaptureAccess { return YES; }
- (NSArray *)filteredInlineTextItems:(NSArray *)items strict:(BOOL)strict { return items; }
- (NSArray *)mergedInlineTextItemsFromItems:(NSArray *)items { return items; }
- (NSString *)recognizeTextBlocksInImage:(CGImageRef)i fastOCR:(BOOL)f languageSegment:(NSInteger)l blocks:(NSArray<OCRTextItem *> **)blocks error:(NSError **)e {
    self.ocrCalls++;
    *blocks = self.fixture;
    return [[self.fixture valueForKey:@"text"] componentsJoinedByString:@"\n"];
}
- (NSArray<OCRTextItem *> *)blocksInsideModalIfPresent:(NSArray<OCRTextItem *> *)b inImage:(CGImageRef)i normalizedExclusions:(NSArray<NSValue *> *)e { return b; }
- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)i fastOCR:(BOOL)f languageSegment:(NSInteger)l error:(NSError **)e {
    self.ocrCalls++;
    return self.fixture;
}
@end

static CardControl *CardText(NSString *text) { CardControl *c = [CardControl new]; c.stringValue = text; return c; }

static CaptureCardApp *CardApp(void) {
    CaptureCardApp *app = [CaptureCardApp new];
    app.running = NO;
    app.fixtureWindowID = 42;
    app.captions = [NSMutableArray new];
    app.statuses = [NSMutableArray new];
    app.inlineTranslationCache = [NSMutableDictionary new];
    // 本套用例关注采集会话闸门，不测文本稳定度：关掉"等待稳定"让每轮都能确定性地翻译一次。
    CardControl *stable = [CardControl new]; stable.state = NSControlStateValueOff;
    CardControl *fit = [CardControl new]; fit.state = NSControlStateValueOff;
    app.stableTextCheckbox = (id)stable;
    app.autoFitRegionCheckbox = (id)fit;
    app.apiKeyField = (id)CardText(@"card-test-key");
    app.baseURLField = (id)CardText(@"https://example.invalid/v1");
    app.modelField = (id)CardText(@"test-model");
    app.realtimeModelField = (id)CardText(@"test-model");
    app.languageControl = (id)CardControlWithSegment(0);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    app.learningCoordinator = [[FYLearningCoordinator alloc] initWithStore:nil analyzer:nil tokenizer:nil catalog:nil];
#pragma clang diagnostic pop
    CardControl *inputSource = [CardControl new];
    inputSource.selectedSegment = 0;
    app.inputSourceControl = (id)inputSource;
    FYTestCaptureCardInput *input = [FYTestCaptureCardInput new];
    input.testAvailability = FYCaptureCardAvailabilityAuthorized;
    input.testDevices = @[CardDevice(@"usb-video", @"USB Video", NO)];
    input.testAvailabilityAfterRequest = FYCaptureCardAvailabilityAuthorized;
    app.captureCardInput = input;
    app.captureDeviceListLoaded = YES;
    app.selectedCaptureDeviceID = @"usb-video";
    return app;
}

static CardControl *CardControlWithSegment(NSInteger segment) {
    CardControl *control = [CardControl new];
    control.selectedSegment = segment;
    control.state = NSControlStateValueOff;
    return control;
}
static FYTestCaptureCardDevice *CardDevice(NSString *uniqueID, NSString *name, BOOL inUse) {
    FYTestCaptureCardDevice *device = [FYTestCaptureCardDevice new];
    device.uniqueID = uniqueID;
    device.displayName = name;
    device.inUseByAnotherApplication = inUse;
    return device;
}
static NSArray *CardFixture(NSString *text, CGFloat width) {
    OCRTextItem *item = [OCRTextItem new];
    item.text = text;
    item.boundingBox = CGRectMake(.2, .2, width, .055);
    return @[item];
}
static WindowItem *CardWindow(CGFloat x, CGFloat y, CGFloat width, CGFloat height) {
    WindowItem *item = [WindowItem new];
    item.windowID = 42;
    item.displayName = @"测试显示窗口";
    item.bounds = CGRectMake(x, y, width, height);
    return item;
}
static void CardCycle(CaptureCardApp *app, NSArray *fixture) {
    app.fixture = fixture;
    [app timerFired:nil];
    Pump(^BOOL { return !app.inFlight; });
}
static void SwitchInputSource(CaptureCardApp *app, NSInteger segment) {
    CardControl *control = (CardControl *)app.inputSourceControl;
    control.selectedSegment = segment;
    [app inputSourceChanged:control];
    Tick();
}
static NSString *CardStatusText(CaptureCardApp *app) {
    for (NSString *status in [app.statuses reverseObjectEnumerator]) {
        if (status.length > 0) { return status; }
    }
    return @"";
}
static NSArray *CardRecords(NSString *log) {
    NSString *text = [NSString stringWithContentsOfFile:log encoding:NSUTF8StringEncoding error:NULL];
    NSMutableArray *records = [NSMutableArray new];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (!line.length) { continue; }
        id record = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        Require(record != nil, @"valid JSONL record");
        [records addObject:record];
    }
    return records;
}
static void ArmCardTrace(NSString *root) {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSDictionary *control = @{@"session": NSUUID.UUID.UUIDString, @"issued_at": @(now), @"expires_at": @(now + 120)};
    NSString *path = [root stringByAppendingPathComponent:@"control.json"];
    [[NSJSONSerialization dataWithJSONObject:control options:0 error:NULL] writeToFile:path atomically:YES];
    chmod(path.fileSystemRepresentation, 0600);
}

int main(void) { @autoreleasepool {
    unsetenv("FUYI_DIAG");
    NSString *root = [FYTestTemporaryDirectory() stringByAppendingPathComponent:@"capture-card"];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];
    CardTrace = [[FYTranslationTrace alloc] initWithDirectory:root clock:^{ return NSDate.date.timeIntervalSince1970; } maxBytes:1024 * 1024];
    method_exchangeImplementations(class_getClassMethod(FYTranslationTrace.class, @selector(shared)),
                                   class_getClassMethod(FYTranslationTrace.class, @selector(captureCardTestShared)));
    method_exchangeImplementations(class_getClassMethod(FYTestURLSession.class, @selector(sharedSession)),
                                   class_getClassMethod(FYTestURLSession.class, @selector(captureCardTestSession)));

    // —— 1. 单一帧槽（真实生产类）：有界缓存、限速、清空即作废 ——
    FYCaptureCardFrameSlot *slot = [FYCaptureCardFrameSlot new];
    slot.minimumInterval = 0.1;
    Require(slot.minimumInterval == 0.1 && !slot.hasFrame && slot.copyLatestFrame == NULL, @"empty slot has no frame");
    CGImageRef first = NULL;
    {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, 8, 8, 8, 32, space, kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(space);
        first = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
    }
    Require([slot shouldStoreFrameAtTime:100.0], @"first frame is accepted");
    [slot storeFrame:first index:1 atTime:100.0];
    CGImageRelease(first);
    Require(slot.hasFrame && slot.latestIndex == 1 && slot.storedCount == 1 && slot.skippedCount == 0, @"slot holds exactly one frame");
    NSUInteger skipped = 0;
    for (int i = 0; i < 99; i++) {
        if (![slot shouldStoreFrameAtTime:100.0 + i * 0.001]) { skipped++; }
    }
    Require(skipped == 99 && slot.storedCount == 1 && slot.skippedCount == 99, @"rapid frames are dropped, not queued");
    Require(slot.latestIndex == 1, @"dropped frames never replace the stored frame");
    Require([slot shouldStoreFrameAtTime:100.2], @"rate limit expires and allows the next frame");
    CGImageRef second = NULL;
    {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, 64, 32, 8, 256, space, kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(space);
        second = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
    }
    [slot storeFrame:second index:101 atTime:100.2];
    CGImageRef latest = slot.copyLatestFrame;
    Require(latest != NULL && CGImageGetWidth(latest) == 64 && CGImageGetHeight(latest) == 32 && slot.latestIndex == 101,
            @"only the newest frame is retained");
    CGImageRelease(latest);
    slot.minimumInterval = 0;
    NSUInteger storedBefore = slot.storedCount;
    for (int i = 0; i < 100; i++) { [slot storeFrame:second index:(uint64_t)(200 + i) atTime:101.0 + i]; }
    Require(slot.storedCount == storedBefore + 100 && slot.latestIndex == 299,
            @"overwriting a single slot never accumulates a backlog");
    CGImageRelease(second);
    [slot clear];
    Require(!slot.hasFrame && slot.copyLatestFrame == NULL && slot.latestIndex == 0,
            @"clear releases the frame so no stale picture can be reused");

    // —— 2. 权限被拒绝：不启动任何设备、不自动申请、也不回退到别的摄像头 ——
    MockRequests = 0;
    CaptureCardApp *denied = CardApp();
    FYTestCaptureCardInput *deniedInput = (FYTestCaptureCardInput *)denied.captureCardInput;
    deniedInput.testAvailability = FYCaptureCardAvailabilityDenied;
    SwitchInputSource(denied, 1);
    [denied start];
    Require(!denied.running && denied.timer == nil, @"start must fail while camera permission is denied");
    Require(deniedInput.startAttempts.count == 0 && deniedInput.startedSessions.count == 0,
            @"a denied permission never attempts or starts any device, so it can never fall back to another camera");
    Require(deniedInput.accessRequestCount == 0, @"an explicit denial is never re-prompted");
    Require([CardStatusText(denied) containsString:@"权限"], @"the status line tells the user about the permission problem");
    Require([CardStatusText(denied) containsString:@"不会改用其他摄像头"], @"denial explains that no other camera is used");
    Require(deniedInput.accessRequestCount == 0, @"a denied permission is not requested again until the user changes it in settings");
    // 尚未决定过：由「开始翻译」触发一次系统提示，批准后自动继续（不需要单独点"申请相机权限"）
    CaptureCardApp *pending = CardApp();
    FYTestCaptureCardInput *pendingInput = (FYTestCaptureCardInput *)pending.captureCardInput;
    pendingInput.testAvailability = FYCaptureCardAvailabilityNotDetermined;
    pendingInput.testAvailabilityAfterRequest = FYCaptureCardAvailabilityAuthorized;
    SwitchInputSource(pending, 1);
    [pending start];
    Require(pendingInput.accessRequestCount == 1, @"starting asks for the camera permission exactly once when undecided");
    Pump(^BOOL { return pending.running; });
    Require(pending.running && pendingInput.state == FYCaptureCardSessionStateRunning,
            @"granting the permission continues into capture automatically");
    Require(pendingInput.startedSessions.count == 1, @"exactly one capture session starts after the grant");
    // 用户拒绝弹窗时：不启动、明确提示
    CaptureCardApp *refused = CardApp();
    FYTestCaptureCardInput *refusedInput = (FYTestCaptureCardInput *)refused.captureCardInput;
    refusedInput.testAvailability = FYCaptureCardAvailabilityNotDetermined;
    refusedInput.testAvailabilityAfterRequest = FYCaptureCardAvailabilityDenied;
    SwitchInputSource(refused, 1);
    [refused start];
    Pump(^BOOL { return !refused.running && refusedInput.accessRequestCount == 1; });
    Tick();
    Require(!refused.running && refusedInput.startedSessions.count == 0, @"refusing the prompt starts nothing");
    Require([CardStatusText(refused) containsString:@"权限"], @"a refused prompt is reported to the user");

    // 运行中切到采集卡却起不来：必须停下来并说明原因，而不是继续假装在跑
    CaptureCardApp *deniedSwitch = CardApp();
    FYTestCaptureCardInput *deniedSwitchInput = (FYTestCaptureCardInput *)deniedSwitch.captureCardInput;
    deniedSwitchInput.testAvailability = FYCaptureCardAvailabilityDenied;
    deniedSwitch.running = YES;
    SwitchInputSource(deniedSwitch, 1);
    Require(!deniedSwitch.running && deniedSwitch.timer == nil, @"switching to an unavailable input source stops the run");
    Require(deniedSwitchInput.startedSessions.count == 0, @"stopping on a permission failure still starts no session");
    Require([CardStatusText(deniedSwitch) containsString:@"权限"], @"the failure reason replaces the paused status");

    // —— 3. 设备缺失 / 被占用：明确状态，不静默切换 ——
    CaptureCardApp *missing = CardApp();
    FYTestCaptureCardInput *missingInput = (FYTestCaptureCardInput *)missing.captureCardInput;
    missingInput.testDevices = @[];
    SwitchInputSource(missing, 1);
    [missing start];
    Require(!missing.running && missingInput.startedSessions.count == 0, @"missing device must not start anything");
    Require(missingInput.state == FYCaptureCardSessionStateNoDevice, @"missing device is reported as such");
    CaptureCardApp *busy = CardApp();
    FYTestCaptureCardInput *busyInput = (FYTestCaptureCardInput *)busy.captureCardInput;
    busyInput.testDevices = @[CardDevice(@"usb-video", @"USB Video", YES)];
    SwitchInputSource(busy, 1);
    [busy start];
    Require(!busy.running && busyInput.startedSessions.count == 0, @"occupied device must not start anything");
    Require(busyInput.state == FYCaptureCardSessionStateDeviceUnavailable, @"occupied device is reported as unavailable");

    // —— 4. 开始 → 采一帧 → 停止：释放会话、作废旧帧、代次自增 ——
    CaptureCardApp *app = CardApp();
    FYTestCaptureCardInput *input = (FYTestCaptureCardInput *)app.captureCardInput;
    SwitchInputSource(app, 1);
    [app start];
    Require(app.running && input.state == FYCaptureCardSessionStateRunning, @"authorized external device starts a session");
    Require(input.startedSessions.count == 1 && [input.startedSessions.firstObject isEqualToString:@"usb-video"],
            @"the explicitly selected device is the one opened");
    Require(input.accessRequestCount == 0, @"an already authorized device needs no prompt");
    NSUInteger runningEpoch = input.sessionEpoch;
    Require(runningEpoch > 0, @"starting a session establishes a new input epoch");
    Require([input testEnqueueFrameIndex:1 pixelSize:16], @"frame arrives");
    CardCycle(app, CardFixture(@"ミヨは占いに凝ってんの。", .55));
    Require(app.ocrCalls == 1 && app.captions.count == 1, @"capture-card frame is OCRed and translated once");
    Require(app.lastOCRedCaptureFrameIndex == 1, @"the consumed frame index is recorded");
    CardCycle(app, CardFixture(@"ミヨは占いに凝ってんの。", .55));
    Require(app.ocrCalls == 1 && app.captions.count == 1, @"a repeated cycle without a new frame performs no OCR at all");
    Require([CardStatusText(app) containsString:@"等待采集卡新画面"], @"waiting state is explained to the user");
    [app stop];
    Require(!app.running && app.timer == nil, @"stop ends the run loop");
    Require(input.stopCallCount == 1 && input.state == FYCaptureCardSessionStateStopped, @"stop reaches the capture session exactly once");
    Require(input.sessionReleased, @"the capture session is released on stop");
    Require(input.sessionEpoch > runningEpoch, @"stopping bumps the input epoch so late results are invalidated");
    Require(input.copyLatestFrame == NULL && input.latestFrameIndex == 0, @"no frame survives the stop");
    NSUInteger ocrAfterStop = app.ocrCalls;
    CardCycle(app, CardFixture(@"ミヨは占いに凝ってんの。", .55));
    Require(app.ocrCalls == ocrAfterStop, @"paused app performs no further OCR");

    // —— 5. 断开：不沿用旧帧、明确提示、重连可恢复 ——
    CaptureCardApp *outage = CardApp();
    FYTestCaptureCardInput *outageInput = (FYTestCaptureCardInput *)outage.captureCardInput;
    SwitchInputSource(outage, 1);
    [outage start];
    [outageInput testEnqueueFrameIndex:1 pixelSize:16];
    CardCycle(outage, CardFixture(@"ミヨは占いに凝ってんの。", .55));
    NSUInteger ocrBeforeOutage = outage.ocrCalls;
    NSUInteger epochBeforeOutage = outageInput.sessionEpoch;
    [outageInput testDisconnectActiveDevice];
    Tick();
    Require(outageInput.state == FYCaptureCardSessionStateDisconnected, @"disconnect is reported explicitly");
    Require(outageInput.sessionEpoch > epochBeforeOutage && outageInput.sessionReleased, @"disconnect releases the session and bumps the epoch");
    Require(outageInput.copyLatestFrame == NULL, @"disconnect discards the last frame");
    CardCycle(outage, CardFixture(@"ミヨは占いに凝ってんの。", .55));
    Require(outage.ocrCalls == ocrBeforeOutage && outage.captions.count == 1, @"no OCR runs on stale frames after a disconnect");
    Require([CardStatusText(outage) containsString:@"断开"], @"the disconnect reason is shown to the user");
    Require([CardStatusText(outage) containsString:@"重连"], @"the user is told how to recover");
    [outage reconnectCaptureDevice:nil];
    Require(outageInput.state == FYCaptureCardSessionStateRunning && outageInput.startedSessions.count == 2, @"reconnect restarts the same device");
    Require(outageInput.sessionEpoch > epochBeforeOutage + 1, @"reconnect establishes another input epoch");
    CardCycle(outage, CardFixture(@"ミヨは占いに凝ってんの。", .55));
    Require(outage.ocrCalls == ocrBeforeOutage, @"after reconnect no OCR happens until a new frame arrives");
    [outage stop];

    // —— 6. 断连后迟到的翻译结果不得更新新会话字幕；日志可对上代次 ——
    ArmCardTrace(root);
    CaptureCardApp *late = CardApp();
    FYTestCaptureCardInput *lateInput = (FYTestCaptureCardInput *)late.captureCardInput;
    SwitchInputSource(late, 1);
    [late start];
    [lateInput testEnqueueFrameIndex:7 pixelSize:16];
    late.fixture = CardFixture(@"ミヨは占いに凝ってんの。", .55);
    HoldResponse = YES;
    [late timerFired:nil];
    Pump(^BOOL { return PendingResponse != nil; });
    Require(late.inFlight, @"the request is still in flight while the device is unplugged");
    NSUInteger epochAtRequest = lateInput.sessionEpoch;
    [lateInput testDisconnectActiveDevice];
    Require(lateInput.sessionEpoch != epochAtRequest, @"the input session really changed mid-request");
    PendingResponse();
    PendingResponse = nil;
    HoldResponse = NO;
    Pump(^BOOL { return !late.inFlight; });
    Require(late.captions.count == 0, @"a reply from the previous input session cannot update the caption");
    NSArray *records = CardRecords([root stringByAppendingPathComponent:@"events.jsonl"]);
    BOOL droppedForSession = NO, requestLinked = NO, ocrLinked = NO;
    for (NSDictionary *record in records) {
        // 丢弃记录属于**发起请求的那次采集会话**（代次 == epochAtRequest），
        // 原因字段说明它已经被新会话取代（上面的 sessionEpoch != epochAtRequest 已确认）。
        if ([record[@"event"] isEqual:@"caption_drop"] && [record[@"reason"] isEqual:@"input_session_changed"] &&
            [record[@"input_epoch"] unsignedIntegerValue] == epochAtRequest) { droppedForSession = YES; }
        if ([record[@"event"] isEqual:@"request_submit"] && [record[@"input_source"] intValue] == 1 &&
            [record[@"input_epoch"] unsignedIntegerValue] == epochAtRequest) { requestLinked = YES; }
        if ([record[@"event"] isEqual:@"ocr"] && [record[@"frame_index"] unsignedIntegerValue] == 7 &&
            [record[@"input_epoch"] unsignedIntegerValue] == epochAtRequest) { ocrLinked = YES; }
    }
    Require(droppedForSession, @"the dropped reply is logged against the new input session");
    Require(requestLinked, @"the translation request is logged with the input session that produced the frame");
    Require(ocrLinked, @"the OCR frame is logged with the same input session and frame index");
    NSString *log = [NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"events.jsonl"] encoding:NSUTF8StringEncoding error:NULL];
    Require(![log containsString:@"usb-video"], @"hardware identifiers never reach the diagnostic log");
    [late stop];
    [NSFileManager.defaultManager removeItemAtPath:[root stringByAppendingPathComponent:@"control.json"] error:NULL];

    // —— 7. 切源：窗口截图不回退，采集卡不碰屏幕截图 ——
    MockRequests = 0;
    CaptureCardApp *switchApp = CardApp();
    FYTestCaptureCardInput *switchInput = (FYTestCaptureCardInput *)switchApp.captureCardInput;
    switchApp.running = YES;
    NSUInteger capturesBefore = FYTestCaptureCount();
    CardCycle(switchApp, CardFixture(@"ミヨは占いに凝ってんの。", .55));
    Require(FYTestCaptureCount() > capturesBefore && switchApp.captions.count == 1,
            @"default window-screenshot mode still captures the window and translates");
    Require(switchInput.startedSessions.count == 0, @"window mode never opens the capture card");
    SwitchInputSource(switchApp, 1);
    Require(switchApp.inputSourceSegment == 1 && switchInput.state == FYCaptureCardSessionStateRunning,
            @"switching to capture card starts the selected device");
    NSUInteger capturesAfterSwitch = FYTestCaptureCount();
    [switchInput testEnqueueFrameIndex:1 pixelSize:16];
    CardCycle(switchApp, CardFixture(@"ミヨは占いに凝ってんの。", .55));
    Require(switchApp.captions.count == 2, @"capture-card mode keeps translating");
    Require(FYTestCaptureCount() == capturesAfterSwitch, @"capture-card mode does not touch screen capture at all");
    SwitchInputSource(switchApp, 0);
    Require(switchApp.inputSourceSegment == 0 && switchInput.state == FYCaptureCardSessionStateStopped, @"switching back stops and releases the capture session");
    Require(switchInput.stopCallCount == 1, @"switching back stops the session exactly once");
    Pump(^BOOL { return !switchApp.inFlight; });
    NSUInteger captionsAfterReturn = switchApp.captions.count;
    NSUInteger capturesBeforeReturn = FYTestCaptureCount();
    CardCycle(switchApp, CardFixture(@"次は図書館に行きましょう。", .6));
    Require(FYTestCaptureCount() > capturesBeforeReturn, @"window capture resumes after switching back");
    Require(switchApp.captions.count == captionsAfterReturn + 1, @"window-screenshot mode still produces new captions");
    Require(switchInput.startedSessions.count == 1, @"switching back never restarts the capture card");

    // —— 8. 采集卡自动定位：默认不需要任何手动校准 ——
    // 8a) 没有目标窗口 → 不贴译，提示简短，且**不写字幕框**（字幕框只放对白译文）。
    MockRequests = 0;
    CaptureCardApp *uiUnmapped = CardApp();
    FYTestCaptureCardInput *uiInput = (FYTestCaptureCardInput *)uiUnmapped.captureCardInput;
    uiUnmapped.fixtureMode = ContentModeUI;
    uiUnmapped.fixtureAutoMode = NO;
    uiUnmapped.fixtureWindowItem = nil;   // 没有显示画面 → 无法定位
    SwitchInputSource(uiUnmapped, 1);
    [uiUnmapped start];
    [uiInput testEnqueueFrameIndex:1 pixelSize:16];
    CardCycle(uiUnmapped, CardFixture(@"設定メニュー", .3));
    Require(uiUnmapped.inlineApplies == 0, @"capture-card mode without a locatable region must not place inline panels");
    Require([CardStatusText(uiUnmapped) containsString:@"暂时无法定位游戏画面"],
            @"the shortfall must be one short line in the status area");
    Require([CardStatusText(uiUnmapped) containsString:@"调整贴译位置"],
            @"the short line must point at the optional adjustment entry");
    Require(![CardStatusText(uiUnmapped) containsString:@"整窗估算"] &&
            ![CardStatusText(uiUnmapped) containsString:@"映射"],
            @"user-facing copy must not contain implementation talk");
    for (NSString *caption in uiUnmapped.captions) {
        Require(![caption containsString:@"提示"] && ![caption containsString:@"定位"] && ![caption containsString:@"校准"],
                @"the subtitle box must only carry dialogue, never a placement notice");
    }
    // 8a-2) 定位失败不影响对白翻译：切回对白模式照常产生字幕。
    uiUnmapped.fixtureMode = ContentModeDialogue;
    Require([uiInput testEnqueueFrameIndex:2 pixelSize:16], @"dialogue check needs a fresh capture frame");
    NSUInteger captionsBeforeDialogue = uiUnmapped.captions.count;
    CardCycle(uiUnmapped, CardFixture(@"次の台詞です。", .6));
    Require(uiUnmapped.captions.count == captionsBeforeDialogue + 1,
            @"dialogue translation keeps updating even when inline placement cannot be located");
    [uiUnmapped stop];

    // 8b) 自动定位：画面必须**从像素里被找到**（窗口截图 + 采集帧内容比对），
    //     既不是注入矩形，也不是"有窗口 + 有帧"就算成功。
    CaptureCardApp *uiAuto = CardApp();
    FYTestCaptureCardInput *autoInput = (FYTestCaptureCardInput *)uiAuto.captureCardInput;
    uiAuto.fixtureMode = ContentModeUI;
    uiAuto.fixtureAutoMode = NO;
    uiAuto.fixtureWindowItem = CardWindow(100, 100, 800, 600);
    SwitchInputSource(uiAuto, 1);
    [uiAuto start];
    // QuickTime 式窗口：1000×700 的窗口截图，顶部 62px 标题栏，画面贴在 (140,150,740,420)
    const size_t sceneW = 1000, sceneH = 700;
    const CGRect videoInScene = {{140, 150}, {740, 420}};
    CGImageRef autoFrame = CardPatternImage(320, 180, 4242);
    CGImageRef autoScene = CardWindowScene(autoFrame, sceneW, sceneH, videoInScene, 62);
    Require(autoFrame != NULL && autoScene != NULL, @"auto-locate fixture images");
    FYTestSetWindowImage(autoScene);
    Require([autoInput testStoreFrame:autoFrame index:1], @"auto-locate fixture frame");
    CGImageRelease(autoFrame);
    CGImageRelease(autoScene);
    NSRect autoWindowFrame = [uiAuto appKitFrameForWindowItem:uiAuto.fixtureWindowItem];
    Require([uiAuto autoDetectCaptureCardVideoRectForWindow:uiAuto.fixtureWindowItem reason:NULL],
            @"auto-locate must find the capture picture inside a QuickTime-style window from pixels alone");
    NSRect autoRect = NSZeroRect;
    Require([uiAuto captureCardDisplayRectForWindow:uiAuto.fixtureWindowItem outRect:&autoRect],
            @"the auto-located region must immediately become the mapping (no manual step)");
    CGFloat expectX = NSMinX(autoWindowFrame) + videoInScene.origin.x / sceneW * NSWidth(autoWindowFrame);
    CGFloat expectY = NSMinY(autoWindowFrame) + videoInScene.origin.y / sceneH * NSHeight(autoWindowFrame);
    CGFloat expectW = videoInScene.size.width / sceneW * NSWidth(autoWindowFrame);
    CGFloat expectH = videoInScene.size.height / sceneH * NSHeight(autoWindowFrame);
    Require(fabs(NSMinX(autoRect) - expectX) < NSWidth(autoWindowFrame) * 0.04 &&
            fabs(NSMinY(autoRect) - expectY) < NSHeight(autoWindowFrame) * 0.04 &&
            fabs(NSWidth(autoRect) - expectW) < NSWidth(autoWindowFrame) * 0.06 &&
            fabs(NSHeight(autoRect) - expectH) < NSHeight(autoWindowFrame) * 0.06,
            ([NSString stringWithFormat:@"auto-located %@ must match the pasted picture %@ (title bar excluded)",
              NSStringFromRect(autoRect), NSStringFromRect(NSMakeRect(expectX, expectY, expectW, expectH))]));
    // 标题栏区域绝不能被当成画面
    Require(NSMaxY(autoRect) < NSMaxY(autoWindowFrame) - NSHeight(autoWindowFrame) * 0.05,
            @"the title bar area must not be claimed as the picture");
    // 首次定位后同一帧周期内不再重复截屏定位（稳态不反复抓屏）
    NSUInteger capturesAfterLocate = FYTestCaptureCount();
    [uiAuto inlinePlacementRect:NULL reason:NULL];
    [uiAuto inlinePlacementRect:NULL reason:NULL];
    Require(FYTestCaptureCount() == capturesAfterLocate,
            @"a valid mapping must not re-run window capture every cycle");
    // 窗口移动：归一化映射继续有效；窗口比例变化：失效并重新自动定位
    [uiAuto captureCardDisplayRectForWindow:uiAuto.fixtureWindowItem outRect:NULL];
    uiAuto.fixtureWindowItem = CardWindow(40, 60, 800, 600);
    NSRect movedAuto = NSZeroRect;
    Require([uiAuto captureCardDisplayRectForWindow:uiAuto.fixtureWindowItem outRect:&movedAuto],
            @"moving the window must keep the normalized mapping valid");
    NSRect movedFrame = [uiAuto appKitFrameForWindowItem:uiAuto.fixtureWindowItem];
    Require(fabs((NSMinX(movedAuto) - NSMinX(movedFrame)) - (NSMinX(autoRect) - NSMinX(autoWindowFrame))) < 2,
            @"the located region must follow the window when it moves");
    [uiAuto stop];
    FYTestSetWindowImage(NULL);

    // 8c) 手动调整只作可选补救：走**真实入口**（点「调整贴译位置」→ 拖框层 → 松开保存），
    //     而不是测试直接往字典注入矩形。
    CaptureCardApp *uiMapped = CardApp();
    FYTestCaptureCardInput *mappedInput = (FYTestCaptureCardInput *)uiMapped.captureCardInput;
    uiMapped.fixtureMode = ContentModeUI;
    uiMapped.fixtureAutoMode = NO;
    uiMapped.fixtureWindowItem = CardWindow(100, 100, 800, 600);
    SwitchInputSource(uiMapped, 1);
    [uiMapped start];
    Require(uiMapped.running, @"the capture-card fixture must actually be running");
    Require([mappedInput testEnqueueFrameIndex:1 pixelSize:16], @"mapped fixture needs a frame");
    uiMapped.selectedCaptureDeviceID = @"dev-A";   // 校准前记下当时的设备标识
    Require(![uiMapped captureCardDisplayRectForWindow:uiMapped.fixtureWindowItem outRect:NULL],
            @"before calibration the capture-card mapping must be unavailable");
    // ① 真实的「校准采集卡画面区域」按钮
    [uiMapped beginCaptureCardCalibration:nil];
    NSPanel *calibrationPanel = uiMapped.captureCalibrationPanel;
    Require(calibrationPanel != nil && calibrationPanel.isVisible,
            @"the calibrate entry point must actually raise a frame-selection layer over the target window");
    NSView *layer = calibrationPanel.contentView;
    Require([layer isKindOfClass:NSClassFromString(@"FYCaptureCalibrationView")],
            @"the calibration layer must be the drag-to-select view");
    // ② 模拟用户在这层上拖框选（窗口坐标 → 屏幕坐标由这一层自己换算）
    CGFloat layerW = NSWidth(layer.bounds), layerH = NSHeight(layer.bounds);
    NSEvent *(^drag)(NSEventType, NSPoint) = ^NSEvent *(NSEventType type, NSPoint point) {
        return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0
                              windowNumber:calibrationPanel.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    };
    NSString *shotDir = CardOutputDirectory();
    [layer mouseDown:drag(NSEventTypeLeftMouseDown, NSMakePoint(16, layerH - 16))];
    [layer mouseDragged:drag(NSEventTypeLeftMouseDragged, NSMakePoint(layerW - 60, 60))];
    if (shotDir) {
        CardShot(layer, [shotDir stringByAppendingPathComponent:@"capture-calibration.png"]);
    }
    [layer mouseUp:drag(NSEventTypeLeftMouseUp, NSMakePoint(layerW - 16, 16))];
    Require(uiMapped.captureCalibrationPanel == nil, @"finishing the drag must close the calibration layer");
    Require([CardStatusText(uiMapped) containsString:@"已按你框选的区域贴译"], @"the manual adjustment must be confirmed to the user");
    NSRect mappedRect = NSZeroRect;
    NSString *mappedReason = nil;
    Require([uiMapped captureCardDisplayRectForWindow:uiMapped.fixtureWindowItem outRect:&mappedRect reason:&mappedReason],
            ([NSString stringWithFormat:@"the user-selected frame region must become the capture-card mapping (%@)", mappedReason ?: @"no reason"]));
    NSRect mappedWindow = [uiMapped appKitFrameForWindowItem:uiMapped.fixtureWindowItem];
    Require(NSWidth(mappedRect) > NSWidth(mappedWindow) * 0.8 && NSHeight(mappedRect) > NSHeight(mappedWindow) * 0.8,
            @"the calibrated rect must follow what the user dragged");
    // ③ 校准落盘（随现有 settings 保存，不改 SettingsKey）
    [uiMapped saveSettings:nil];
    NSDictionary *savedSettings = [[NSUserDefaults standardUserDefaults] objectForKey:SettingsKey];
    Require([savedSettings[@"captureVideoRects"] isKindOfClass:NSDictionary.class] &&
            savedSettings[@"captureVideoRects"][@"42"] != nil,
            @"the manual adjustment must be persisted (with string keys, so the plist round-trip works)");
    // 模拟重启：把存下来的设置重新载入，手动调整必须仍然可用。
    CaptureCardApp *relaunched = CardApp();
    [relaunched loadSettings];   // 模拟重启：从已保存的设置恢复
    relaunched.fixtureMode = ContentModeUI;
    relaunched.fixtureAutoMode = NO;
    relaunched.fixtureWindowItem = CardWindow(100, 100, 800, 600);
    SwitchInputSource(relaunched, 1);
    [relaunched start];
    Require([(FYTestCaptureCardInput *)relaunched.captureCardInput testEnqueueFrameIndex:1 pixelSize:16], @"relaunch fixture needs a frame");
    Require([relaunched captureCardDisplayRectForWindow:relaunched.fixtureWindowItem outRect:NULL],
            @"a saved manual adjustment must still be usable after a relaunch");
    [relaunched stop];
    // ④ 窗口移动：归一化存储让调整继续有效，且跟着窗口平移
    uiMapped.fixtureWindowItem = CardWindow(40, 60, 800, 600);
    NSRect movedRect = NSZeroRect;
    Require([uiMapped captureCardDisplayRectForWindow:uiMapped.fixtureWindowItem outRect:&movedRect],
            @"moving the window must keep a normalized adjustment valid");
    NSRect movedWindow = [uiMapped appKitFrameForWindowItem:uiMapped.fixtureWindowItem];
    Require(fabs((NSMinX(movedRect) - NSMinX(movedWindow)) - (NSMinX(mappedRect) - NSMinX(mappedWindow))) < 2,
            @"after a move the adjusted region must follow the window");
    // ⑤ 窗口比例变化：旧映射失效（不能悄悄用旧矩形）
    uiMapped.fixtureWindowItem = CardWindow(100, 100, 400, 600);
    NSString *invalidReason = nil;
    Require(![uiMapped captureCardDisplayRectForWindow:uiMapped.fixtureWindowItem outRect:NULL reason:&invalidReason] &&
            [invalidReason containsString:@"比例"],
            @"changing the window aspect must invalidate the stored mapping");
    uiMapped.fixtureWindowItem = CardWindow(100, 100, 800, 600);
    // ⑥ 输入源/画面比例变化：同样失效
    uiMapped.fixtureWindowItem = CardWindow(100, 100, 800, 600);
    [mappedInput testEnqueueFrameIndex:2 pixelWidth:32 pixelHeight:18];   // 16:9 → 画面比例变了
    NSString *sourceReason = nil;
    Require(![uiMapped captureCardDisplayRectForWindow:uiMapped.fixtureWindowItem outRect:NULL reason:&sourceReason] &&
            [sourceReason containsString:@"比例"],
            @"a changed capture aspect must invalidate the stored mapping");
    // ⑥b 换设备：同样失效
    Require([mappedInput testEnqueueFrameIndex:3 pixelSize:16], @"restore the calibrated aspect frame");
    uiMapped.selectedCaptureDeviceID = @"dev-B";
    NSString *deviceReason = nil;
    Require(![uiMapped captureCardDisplayRectForWindow:uiMapped.fixtureWindowItem outRect:NULL reason:&deviceReason] &&
            [deviceReason containsString:@"设备"],
            @"switching the capture device must invalidate the stored mapping");
    uiMapped.selectedCaptureDeviceID = @"dev-A";
    // ⑦ 调整有效时：与窗口截图同一条贴译流程
    CardCycle(uiMapped, CardFixture(@"設定メニュー", .3));
    Pump(^BOOL { return uiMapped.inlineApplies > 0 || uiMapped.captions.count > 0; });
    Require(uiMapped.inlineApplies == 1, @"capture card with a calibrated display mapping must place inline translations");
    // ⑧ 清除校准 → 立刻回到「映射不可用」
    [uiMapped clearCaptureCardCalibration:nil];
    Require(![uiMapped captureCardDisplayRectForWindow:uiMapped.fixtureWindowItem outRect:NULL],
            @"clearing the calibration must remove the mapping");
    [uiMapped stop];

    CaptureCardApp *uiWindow = CardApp();
    uiWindow.fixtureMode = ContentModeUI;
    uiWindow.fixtureAutoMode = NO;
    uiWindow.fixtureWindowItem = CardWindow(100, 100, 800, 600);
    uiWindow.running = YES;
    CardCycle(uiWindow, CardFixture(@"設定メニュー", .3));
    Pump(^BOOL { return uiWindow.inlineApplies > 0; });
    Require(uiWindow.inlineApplies == 1, @"window-screenshot mode still uses inline translation");

    // —— 8b. 「翻译当前界面」也走同一套界面贴译流程 ——
    MockRequests = 0;
    CaptureCardApp *iface = CardApp();
    iface.fixtureMode = ContentModeUI;
    iface.fixtureAutoMode = NO;
    iface.fixtureWindowItem = CardWindow(100, 100, 800, 600);
    iface.running = NO;
    iface.fixture = CardFixture(@"公演日程", .3);
    NSUInteger inlineBeforeInterface = iface.inlineApplies;
    [iface translateCurrentInterface:nil];
    Pump(^BOOL { return iface.inlineApplies > inlineBeforeInterface; });
    Require(iface.inlineApplies == inlineBeforeInterface + 1, @"translate-current-interface must run the inline translation flow");

    // —— 9. 「引用最新句」重新识别当前画面：必须跟随识别输入源 ——
    [NSApplication sharedApplication];
    CaptureCardApp *ask = CardApp();
    FYTestCaptureCardInput *askInput = (FYTestCaptureCardInput *)ask.captureCardInput;
    ask.running = YES;
    SwitchInputSource(ask, 1);
    Require(ask.running && askInput.state == FYCaptureCardSessionStateRunning, @"capture-card session is running for the reference action");
    Require([askInput testEnqueueFrameIndex:3 pixelSize:16], @"frame available for the reference action");
    ask.fixture = CardFixture(@"ミヨは占いに凝ってんの。", .55);
    NSUInteger capturesBeforeAsk = FYTestCaptureCount();
    __block NSString *askedSource = nil;
    __block NSError *askedError = nil;
    [ask captureLatestStudySentenceWithCompletion:^(NSString *source, NSError *error) {
        askedSource = source;
        askedError = error;
    }];
    Pump(^BOOL { return askedSource != nil || askedError != nil; });
    Require(askedError == nil && [askedSource containsString:@"ミヨは占いに凝ってんの。"],
            @"latest-sentence reference reads the capture-card frame");
    Require(FYTestCaptureCount() == capturesBeforeAsk, @"latest-sentence reference never captures the screen in capture-card mode");
    // 采集卡没有画面时必须明确报错，不能沿用旧画面
    [ask stop];
    __block NSError *noFrameError = nil;
    [ask captureLatestStudySentenceWithCompletion:^(NSString *source, NSError *error) { noFrameError = error; }];
    Pump(^BOOL { return noFrameError != nil; });
    Require(noFrameError != nil && [noFrameError.localizedDescription containsString:@"采集卡"],
            @"a missing capture-card frame is reported instead of reusing an old picture");
    // 窗口截图模式下同一动作仍然截窗（原有语义不变）
    CaptureCardApp *askWindow = CardApp();
    askWindow.running = YES;
    askWindow.fixture = CardFixture(@"ミヨは占いに凝ってんの。", .55);
    NSUInteger capturesBeforeWindowAsk = FYTestCaptureCount();
    __block NSString *windowSource = nil;
    [askWindow captureLatestStudySentenceWithCompletion:^(NSString *source, NSError *error) { windowSource = source ?: @""; }];
    Pump(^BOOL { return windowSource != nil; });
    Require(FYTestCaptureCount() > capturesBeforeWindowAsk, @"window-screenshot mode still captures the window for the reference action");

    // —— 10. 运行设置页与新的「画面来源」卡片能真正构建出来（不开窗口） ——
    [NSApplication sharedApplication];
    AppDelegate *uiApp = [AppDelegate new];
    FYTestCaptureCardInput *smokeInput = [FYTestCaptureCardInput new];
    smokeInput.testDevices = @[CardDevice(@"usb-video", @"USB Video", NO)];
    uiApp.captureCardInput = smokeInput;
    // 运行设置页里的运行状态标签由实时页创建；这里只搭最小脚手架，不开窗口。
    uiApp.ocrDurationLabel = [NSTextField labelWithString:@""];
    uiApp.translationDurationLabel = [NSTextField labelWithString:@""];
    uiApp.translationCountLabel = [NSTextField labelWithString:@""];
    NSView *page = [uiApp makeRunSettingsPage];
    Require(page != nil, @"run settings page builds with the new capture-card controls");
    Require(uiApp.inputSourceControl != nil && uiApp.inputSourceControl.segmentCount == 2,
            @"the input-source selector offers window screenshot and capture card");
    Require(uiApp.windowPopup != nil, @"the subtitle display window selector is still present");
    Require(uiApp.captureDevicePopup != nil && uiApp.captureStatusLabel != nil,
            @"device selector and connection status are present");
    [uiApp.windowPopup addItemWithTitle:@"QuickTime Player"];
    [uiApp refreshCaptureDevices:nil];
    Require(uiApp.captureDevicePopup.enabled, @"device list enables the selector when a capture card exists");
    Require([uiApp captureDeviceIDFromPopup] != nil, @"the selected capture device can be read back");
    smokeInput.testDevices = @[];
    [uiApp refreshCaptureDevices:nil];
    Require(!uiApp.captureDevicePopup.enabled, @"an empty device list disables selection instead of guessing");
    uiApp.inputSourceSegment = 0;
    [uiApp updateCaptureCardStatus];
    Require(uiApp.captureCardControlsView.hidden && uiApp.inputSourceHintLabel.stringValue.length > 0,
            @"window-screenshot mode hides the capture-card controls and keeps one hint line");
    uiApp.inputSourceSegment = 1;
    [uiApp updateCaptureCardStatus];
    Require(!uiApp.captureCardControlsView.hidden && [uiApp.captureStatusLabel.stringValue containsString:@"相机权限"],
            @"capture-card mode shows the controls and the permission state");
    smokeInput.testAvailability = FYCaptureCardAvailabilityDenied;
    [uiApp updateCaptureCardStatus];
    Require(!uiApp.captureSettingsButton.hidden, @"a denied permission exposes the settings shortcut");
    smokeInput.testAvailability = FYCaptureCardAvailabilityAuthorized;
    [uiApp updateCaptureCardStatus];
    Require(uiApp.captureSettingsButton.hidden, @"an authorized permission hides the settings shortcut");

    // —— 11. 真实采集卡类：无硬件条件下不出错、不误判设备类型 ——
    FYCaptureCardInput *real = [FYCaptureCardInput new];
    Require(real.state == FYCaptureCardSessionStateIdle && real.sessionEpoch == 0 && real.sessionReleased,
            @"a fresh input is idle and released");
    Require(real.copyLatestFrame == NULL && real.latestFrameIndex == 0, @"a fresh input has no frame");
    [real stop];
    Require(real.state == FYCaptureCardSessionStateStopped && real.sessionEpoch == 1 && real.sessionReleased,
            @"stop on an idle input is safe and invalidates frames");
    [real stop];
    Require(real.sessionEpoch == 2, @"repeated stop keeps invalidating without crashing");
    Require(![real startWithDeviceUniqueID:@""], @"an empty device id cannot start a session");
    Require(real.state == FYCaptureCardSessionStateNoDevice && real.sessionReleased, @"empty device id is reported as no device");
    FYCaptureCardAvailability realAvailability = [real availability];
    Require([real availableDevices] != nil, @"device discovery works without camera permission");
    Require(![real startWithDeviceUniqueID:@"__yiya_test_missing_device__"], @"a missing device cannot start a session");
    FYCaptureCardSessionState expected = realAvailability == FYCaptureCardAvailabilityAuthorized
        ? FYCaptureCardSessionStateNoDevice
        : FYCaptureCardSessionStatePermissionDenied;
    Require(real.state == expected, @"a missing device reports either 'no device' or the actual permission state");
    Require(real.copyLatestFrame == NULL && real.latestFrameIndex == 0, @"failed starts never leave a frame behind");
    Require(real.sessionReleased, @"failed starts leave nothing open");
    for (FYCaptureCardDeviceInfo *device in [real availableDevices]) {
        NSString *name = device.displayName.lowercaseString;
        Require(![name containsString:@"iphone"] && ![name containsString:@"ipad"] &&
                ![name containsString:@"continuity"] && ![name containsString:@"desk view"],
                @"device discovery excludes phone and desk-view cameras");
    }

    printf("PASS CaptureCardInputTests: bounded single-frame slot; permission denial and missing/occupied devices never start or fall back; start/stop/disconnect/reconnect release the session and bump the epoch; no OCR on stale frames; late replies cannot update a new session; window-screenshot mode unchanged; the capture-card picture is auto-located from window pixels (title bar excluded, no manual step), the optional manual adjustment still works and survives a relaunch, stale mappings are invalidated by window/aspect/device changes, placement notices never overwrite the subtitle box, and dialogue keeps updating when placement cannot be located\n");
} return 0; }
