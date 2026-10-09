// Production timer + translation/cache/response pipeline, synthetic OCR and
// capture, in-memory HTTP completion. No NSApplication or real network.
#import "LearningAppTestSupport.h"
#import <objc/runtime.h>
#import <sys/stat.h>

static FYTranslationTrace *TestTrace;
static NSUInteger MockRequests;
static NSMutableArray *SubmittedSources;
static NSDictionary *LastRequestPolicy;
static BOOL HoldResponse;
static void (^PendingResponse)(void);

@interface FYTranslationTrace (PipelineTest)
+ (instancetype)pipelineTestShared;
@end
@implementation FYTranslationTrace (PipelineTest)
+ (instancetype)pipelineTestShared { return TestTrace; }
@end

@interface TraceTask : NSObject
@property(copy) void (^response)(void);
- (void)resume;
- (void)cancel;
@end
@implementation TraceTask
- (void)resume { if (HoldResponse) { PendingResponse = self.response; } else { self.response(); } }
- (void)cancel {}
@end
@interface TraceSession : NSObject
- (id)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion;
@end
@implementation TraceSession
- (id)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    // Inspect only fictional test request body; never output or log credentials.
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];
    LastRequestPolicy = @{@"model": body[@"model"] ?: @"",
        @"thinking_type": body[@"thinking"][@"type"] ?: @"",
        @"reasoning_effort": body[@"reasoning_effort"] ?: @""};
    NSString *source = [body[@"messages"] lastObject][@"content"];
    [SubmittedSources addObject:source];
    MockRequests++;
    NSString *translated = [source hasPrefix:@"1. "] ? @"1. 测试界面" : [NSString stringWithFormat:@"测试译文%lu", (unsigned long)MockRequests];
    TraceTask *task = [TraceTask new];
    task.response = ^{ completion(Envelope(translated), Response(), nil); };
    return task;
}
@end
@interface FYTestURLSession (PipelineTest)
+ (id)pipelineTestSession;
@end
@implementation FYTestURLSession (PipelineTest)
+ (id)pipelineTestSession { return [TraceSession new]; }
@end

@interface TraceControl : NSObject
@property(nonatomic) NSInteger state;
@property NSInteger selectedSegment;
@property double doubleValue;
@property(copy) NSString *stringValue;
@property BOOL requiresMainThread;
@property BOOL stateReadOffMain;
@end
@implementation TraceControl
@synthesize state = _state;
- (NSInteger)state {
    if (self.requiresMainThread && !NSThread.isMainThread) { self.stateReadOffMain = YES; }
    return _state;
}
@end

@interface TracePipelineApp : AppDelegate
@property NSArray<OCRTextItem *> *fixture;
@property NSMutableArray *captions;
@property uint32_t fixtureWindowID;
@property NSInteger fixtureMode;
@property NSUInteger inlineApplies;
@property BOOL captureReadOnMain;
@property NSUInteger ocrCalls;
@property dispatch_semaphore_t captureEntered;
@property dispatch_semaphore_t captureRelease;
@end
@implementation TracePipelineApp
- (uint32_t)selectedWindowID { return self.fixtureWindowID; }
// This fixture has one capture/display target; keep both APIs on the same fake ID.
- (uint32_t)displayTargetWindowID { return self.fixtureWindowID; }
- (void)refreshDisplayGeometryIfNeeded:(BOOL)force {}
- (BOOL)inlinePlacementRect:(NSRect *)rect reason:(NSString **)reason { if (rect) { *rect = NSMakeRect(0, 0, 800, 600); } return YES; }
- (NSArray *)diagnosticWindowInfos { return @[]; }
- (BOOL)diagnosticQuickTimeRunning { return NO; }
- (WindowItem *)selectedWindowItem { return nil; }
- (BOOL)autoContentModeEnabled { return NO; }
- (NSInteger)effectiveModeSegment { return self.fixtureMode; }
- (NSString *)systemPrompt { return @"TRACE_PRIVATE_PROMPT_SENTINEL"; }
- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)windowID {
    self.captureReadOnMain = NSThread.isMainThread;
    if (self.captureRelease) {
        dispatch_semaphore_signal(self.captureEntered);
        Require(dispatch_semaphore_wait(self.captureRelease, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0,
                @"held synthetic capture must be released");
        self.captureRelease = nil;
    }
    return [super copyFullCapturedImageForWindow:windowID];
}
- (void)updateRunState {}
- (void)updateRuntimeDiagnostics {}
- (BOOL)hasScreenAccess { return YES; }
- (BOOL)hasUsableScreenCaptureAccess { return YES; }
- (pid_t)selectedWindowOwnerPID { return 99999; }
- (void)showPreviewUnavailable:(NSString *)s {}
- (void)hideInlineTranslationPanelsForGeometryChange {}
- (void)clampRegionSliders {}
- (void)updateCaptionAppearance {}
- (void)updateThemeSummary {}
- (void)updateOCRPreviewIfVisible {}
- (void)scheduleSettingsSave {}
- (void)setStatus:(NSString *)s {}
- (void)updatePreviewFromImage:(CGImageRef)i generation:(NSInteger)g {}
- (void)refreshLearningSource {}
- (void)refreshLearningStatus {}
- (void)clearInlineTranslationPanels {}
- (void)setCaptionPanelVisibleForUIMode:(BOOL)m {}
- (void)showError:(NSString *)s { Require(s.length == 0, @"unexpected pipeline error"); }
- (void)updateTranslationCount {}
- (void)updateCaptionWindowWithText:(NSString *)text status:(NSString *)status { [self.captions addObject:text]; }
- (void)showInlineTranslations:(NSArray *)translations forItems:(NSArray *)items { self.inlineApplies++; }
- (void)showInlineTranslations:(NSArray *)translations forItems:(NSArray *)items placementRect:(NSRect)rect { self.inlineApplies++; }
- (NSArray *)filteredInlineTextItems:(NSArray *)items strict:(BOOL)strict { return items; }
- (NSArray *)mergedInlineTextItemsFromItems:(NSArray *)items { return items; }
- (NSArray *)recognizeTextItemsInImage:(CGImageRef)i fastOCR:(BOOL)f languageSegment:(NSInteger)l error:(NSError **)e {
    self.ocrCalls++;
    return self.fixture;
}
- (NSArray<OCRTextItem *> *)blocksInsideModalIfPresent:(NSArray<OCRTextItem *> *)b inImage:(CGImageRef)i normalizedExclusions:(NSArray<NSValue *> *)e { return b; }
@end

@interface TraceVisibilityProbe : AppDelegate
@property uint32_t fixtureWindowID;
@property NSArray *fixtureWindows;
@property NSUInteger onScreenQueries;
@property NSUInteger ownerQueries;
@property pid_t observedOwnerPID;
@end
@implementation TraceVisibilityProbe
- (uint32_t)selectedWindowID { return self.fixtureWindowID; }
- (NSArray *)onScreenWindowInfos { self.onScreenQueries++; return self.fixtureWindows; }
- (NSArray *)windowInfosIncludingWindow:(uint32_t)windowID {
    self.ownerQueries++;
    return @[@{(id)kCGWindowNumber:@(windowID), (id)kCGWindowOwnerPID:@1234}];
}
- (BOOL)translationTargetIsForeground {
    Require(self.overlayWindowSnapshot != nil, @"visibility policy receives this polling cycle's snapshot");
    self.observedOwnerPID = [self selectedWindowOwnerPID];
    return NO;
}
- (NSWindowLevel)overlayLevelForTargetPID:(pid_t)pid inWindowList:(NSArray *)windows {
    Require(pid == self.observedOwnerPID && windows == self.overlayWindowSnapshot,
            @"level and visibility share the same owner and window list");
    return NSNormalWindowLevel;
}
- (void)expireInlineOverflowEntryIfNeeded {}
@end

static void CheckVisibilitySnapshots(void) {
    for (NSUInteger scenario = 0; scenario < 3; scenario++) {
        TraceVisibilityProbe *a = [TraceVisibilityProbe new];
        a.fixtureWindowID = scenario == 2 ? 0 : 42;
        a.fixtureWindows = scenario == 0 ? @[@{(id)kCGWindowNumber:@42, (id)kCGWindowOwnerPID:@1234}] : @[];
        [a refreshOverlayVisibility:nil];
        Require(a.onScreenQueries == (scenario == 2 ? 0 : 1) && a.ownerQueries == (scenario == 1 ? 1 : 0),
                @"one visible-list query; at most one offscreen-owner fallback; no target means no queries");
        Require(a.observedOwnerPID == (scenario == 2 ? 0 : 1234), @"offscreen targets retain their owner identity");
        Require(a.overlayWindowSnapshot == nil && a.overlayOwnerPIDSnapshot == nil, @"snapshots expire after each polling cycle");
    }
}

static TraceControl *TextControl(NSString *text) { TraceControl *c = [TraceControl new]; c.stringValue = text; return c; }
static TracePipelineApp *TraceApp(void) {
    TracePipelineApp *a = [TracePipelineApp new]; a.running = YES; a.fixtureWindowID = 42;
    a.captions = [NSMutableArray new]; a.inlineTranslationCache = [NSMutableDictionary new];
    TraceControl *stable = [TraceControl new]; stable.state = NSControlStateValueOn;
    TraceControl *fit = [TraceControl new]; fit.state = NSControlStateValueOff; fit.requiresMainThread = YES;
    a.stableTextCheckbox = (id)stable; a.autoFitRegionCheckbox = (id)fit;
    a.apiKeyField = (id)TextControl(@"TRACE_CREDENTIAL_SENTINEL");
    a.baseURLField = (id)TextControl(@"https://example.invalid/v1");
    a.modelField = (id)TextControl(@"test-model");
    a.realtimeModelField = (id)TextControl(@"test-model");
    a.serviceStatusLabel = (id)TextControl(@"服务未测试");
    a.serviceErrorLabel = (id)TextControl(@"");
    a.learningCoordinator = [[FYLearningCoordinator alloc] initWithStore:nil analyzer:nil tokenizer:nil catalog:nil];
    return a;
}
static NSArray *Fixture(NSString *text, CGFloat width) {
    OCRTextItem *item = [OCRTextItem new]; item.text = text; item.boundingBox = CGRectMake(.2, .2, width, .055);
    return @[item];
}
static void TraceCycle(TracePipelineApp *a, NSArray *fixture) {
    a.fixture = fixture; [a timerFired:nil]; Pump(^BOOL { return !a.inFlight; });
    Require(FYCurrentTrace() == nil, @"scoped context cannot leak after timer callback");
    Require(![(TraceControl *)(id)a.autoFitRegionCheckbox stateReadOffMain], @"OCR options must be read on the main thread");
    Require(!a.activeTranslationTask, @"completed HTTP tasks release run ownership");
    Require(!a.captureReadOnMain, @"window pixels are captured off the main thread");
}
static void CheckServiceTestCancellation(void) {
    for (NSUInteger action = 0; action < 4; action++) {
        TracePipelineApp *a = TraceApp(); a.fixture = @[]; a.running = NO;
        SubmittedSources = [NSMutableArray new]; HoldResponse = YES;
        [a testTranslation:nil];
        Require([a.serviceStatusLabel.stringValue isEqual:@"正在测试服务"] && PendingResponse,
                @"synthetic service test begins and holds its response");
        void (^staleResponse)(void) = PendingResponse; PendingResponse = nil;
        switch (action) {
            case 0: [a start]; [a.timer invalidate]; a.timer = nil; break;
            case 1: [a resetForSelectedWindowChange]; break;
            case 2: [a resetForInputSourceChange]; break;
            case 3:
                a.regionXSlider = (id)[TraceControl new];
                [a controlValueChanged:a.regionXSlider]; break;
        }
        Pump(^BOOL { return !a.inFlight; });
        Require([a.serviceStatusLabel.stringValue isEqual:@"服务未测试"], @"run changes reset a pending service test");
        staleResponse(); Tick();
        Require([a.serviceStatusLabel.stringValue isEqual:@"服务未测试"] && a.captions.count == 0,
                @"late test response cannot restore stale status or caption");
        HoldResponse = NO;
    }
}
static void CheckLateCaptureCancellation(void) {
    for (NSUInteger route = 0; route < 2; route++) {
        BOOL manual = route == 1;
        TracePipelineApp *a = TraceApp(); a.fixture = @[];
        a.captureEntered = dispatch_semaphore_create(0);
        dispatch_semaphore_t release = dispatch_semaphore_create(0); a.captureRelease = release;
        if (manual) { [a translateCurrentInterface:nil]; } else { [a timerFired:nil]; }
        Require(a.inFlight, @"capture schedules without blocking the calling main thread");
        __block BOOL entered = NO;
        Pump(^BOOL { return entered || (entered = dispatch_semaphore_wait(a.captureEntered, DISPATCH_TIME_NOW) == 0); });
        a.running = NO; // Isolate the old capture; a running window reset starts a fresh cycle automatically.
        [a resetForSelectedWindowChange];
        dispatch_semaphore_signal(release);
        // A queue barrier ensures that the old image has reached its main-queue
        // delivery before checking that cancellation prevented OCR.
        __block BOOL drained = NO;
        dispatch_async(a.captureQueue, ^{ dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; }); });
        Pump(^BOOL { return drained; });
        Require(a.ocrCalls == 0 && !a.inFlight && !a.captureReadOnMain,
                @"late timer/manual captures are discarded before OCR after a window change");
        a.running = YES;
        TraceCycle(a, @[]);
        Require(a.ocrCalls > 0, @"a fresh capture still completes after cancellation");
    }
}
static void CheckDialogueLatencyPolicies(void) {
    // Exercise the actual scheduled timer and serialized HTTP request. Only
    // fictional service configuration is inspected; no UI or real API calls.
    TracePipelineApp *polling = TraceApp();
    TraceControl *interval = [TraceControl new]; interval.doubleValue = 1.2;
    polling.intervalSlider = (id)interval;
    [polling restartTimerIfRunning];
    NSTimeInterval dialogueInterval = polling.timer.timeInterval;
    [polling.timer invalidate]; polling.timer = nil;
    polling.fixtureMode = ContentModeUI;
    [polling restartTimerIfRunning];
    NSTimeInterval interfaceInterval = polling.timer.timeInterval;
    [polling.timer invalidate]; polling.timer = nil;

    TracePipelineApp *relay = TraceApp();
    relay.baseURLField.stringValue = @"https://relay.example.invalid/v1";
    relay.modelField.stringValue = @"gpt-4.1-mini";
    relay.realtimeModelField.stringValue = @"deepseek-flash";
    relay.stableTextCheckbox.state = NSControlStateValueOff;
    TraceCycle(relay, Fixture(@"明日はみんなで図書館に行きましょう。", .4));
    BOOL realtimeReasoningDisabled = [LastRequestPolicy[@"model"] isEqual:@"deepseek-flash"] &&
        [LastRequestPolicy[@"thinking_type"] isEqual:@"disabled"] &&
        [LastRequestPolicy[@"reasoning_effort"] isEqual:@"none"];

    TracePipelineApp *other = TraceApp();
    other.baseURLField.stringValue = @"https://relay.example.invalid/v1";
    other.modelField.stringValue = @"deepseek-flash";
    other.realtimeModelField.stringValue = @"gpt-4.1-mini";
    other.stableTextCheckbox.state = NSControlStateValueOff;
    TraceCycle(other, Fixture(@"今日は公園で犬と一緒に遊びます。", .4));
    BOOL otherModelUnmodified = [LastRequestPolicy[@"model"] isEqual:@"gpt-4.1-mini"] &&
        [LastRequestPolicy[@"thinking_type"] length] == 0 &&
        [LastRequestPolicy[@"reasoning_effort"] length] == 0;
    printf("Latency probes: dialogue_poll_ms=%.0f; interface_poll_ms=%.0f; realtime_reasoning_disabled=%d; other_model_unmodified=%d\n",
        dialogueInterval * 1000, interfaceInterval * 1000, realtimeReasoningDisabled, otherModelUnmodified);
    Require(dialogueInterval <= .5, @"dialogue must confirm fresh frames at most 500ms apart despite the legacy hidden 1.2s setting");
    Require(interfaceInterval == 1.2, @"interface polling must retain its configured cadence");
    Require(realtimeReasoningDisabled, @"DeepSeek realtime override on a relay must disable reasoning based on the actual requested model");
    Require(otherModelUnmodified, @"a different quality model must not inject DeepSeek fields into a non-DeepSeek realtime request");
}
static TracePipelineApp *RunSequence(NSArray *full, NSArray *partial) {
    MockRequests = 0; SubmittedSources = [NSMutableArray new];
    TracePipelineApp *a = TraceApp();
    for (NSArray *f in @[full, full, partial, partial, full, full]) { TraceCycle(a, f); }
    return a;
}
static void ArmTrace(NSString *root) {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSDictionary *control = @{@"session": NSUUID.UUID.UUIDString, @"issued_at": @(now), @"expires_at": @(now + 120)};
    NSString *path = [root stringByAppendingPathComponent:@"control.json"];
    [[NSJSONSerialization dataWithJSONObject:control options:0 error:NULL] writeToFile:path atomically:YES];
    chmod(path.fileSystemRepresentation, 0600);
}
static NSArray *Records(NSString *log) {
    NSString *text = [NSString stringWithContentsOfFile:log encoding:NSUTF8StringEncoding error:NULL];
    NSMutableArray *records = [NSMutableArray new];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (!line.length) { continue; }
        id record = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        Require(record != nil, @"valid JSONL"); [records addObject:record];
    }
    return records;
}
static NSUInteger Count(NSArray *records, NSString *event) {
    NSUInteger count = 0; for (NSDictionary *r in records) { if ([r[@"event"] isEqual:event]) { count++; } } return count;
}
int main(void) { @autoreleasepool {
    unsetenv("FUYI_DIAG");
    Require(!FuyiDiagEnabled(), @"isolated tests ignore live legacy screenshot switches");
    NSString *root = [FYTestTemporaryDirectory() stringByAppendingPathComponent:@"trace"];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];
    TestTrace = [[FYTranslationTrace alloc] initWithDirectory:root clock:^{ return NSDate.date.timeIntervalSince1970; } maxBytes:1024 * 1024];
    method_exchangeImplementations(class_getClassMethod(FYTranslationTrace.class, @selector(shared)), class_getClassMethod(FYTranslationTrace.class, @selector(pipelineTestShared)));
    method_exchangeImplementations(class_getClassMethod(FYTestURLSession.class, @selector(sharedSession)), class_getClassMethod(FYTestURLSession.class, @selector(pipelineTestSession)));
    CheckServiceTestCancellation();
    CheckLateCaptureCancellation();
    CheckVisibilitySnapshots();
    CheckDialogueLatencyPolicies();
    NSString *log = [root stringByAppendingPathComponent:@"events.jsonl"];
    NSArray *full = Fixture(@"明日はみんなで図書館に行きましょう。", .65);
    NSArray *partial = Fixture(@"明日はみんなで", .31);
    TracePipelineApp *off = RunSequence(full, partial);
    NSArray *offSources = [SubmittedSources copy], *offCaptions = [off.captions copy];
    Require(MockRequests == 1 && ![NSFileManager.defaultManager fileExistsAtPath:log], @"disabled: clipped frames reuse the one complete translation, no log");
    ArmTrace(root);
    TracePipelineApp *on = RunSequence(full, partial);
    Require(MockRequests == 1 && [offSources isEqual:SubmittedSources] && [offCaptions isEqual:on.captions], @"trace must preserve requests and displayed outputs");
    NSArray *records = Records(log);
    Require(Count(records,@"request_submit") == 1 && Count(records,@"request_complete") == 1 && Count(records,@"caption_apply") == 3, @"one HTTP result plus reused full captions are logged using mock transport");
    Require(Count(records,@"ocr") == 24 && Count(records,@"stable") == 6 && Count(records,@"mode") == 6, @"raw and processed OCR frames and stability decisions logged");
    Require(Count(records,@"capture") == 6 && Count(records,@"task") == 18, @"capture and OCR scheduling lifecycle logged");
    for (NSDictionary *submit in records) {
        if (![submit[@"event"] isEqual:@"request_submit"]) { continue; }
        BOOL response = NO, apply = NO;
        for (NSDictionary *r in records) {
            if (![r[@"request_id"] isEqual:submit[@"request_id"]]) { continue; }
            Require([r[@"cycle"] isEqual:submit[@"cycle"]] && [r[@"session"] isEqual:submit[@"session"]], @"same request stays in its cycle and session");
            Require([r[@"frame_id"] isEqual:submit[@"frame_id"]], @"same captured frame survives asynchronous delivery");
            if ([@[@"request_submit", @"http_complete", @"request_complete"] containsObject:r[@"event"]]) {
                Require([r[@"http_task_id"] isEqual:submit[@"http_task_id"]], @"physical HTTP task correlated separately from logical batch");
            }
            response |= [r[@"event"] isEqual:@"request_complete"];
            apply |= [r[@"event"] isEqual:@"caption_apply"];
        }
        Require(response && apply, @"request completion and applied caption are linked");
    }
    TraceCycle(on, full);
    Require(MockRequests == 1, @"unchanged frame skips request");
    on.lastTranslatedNormalizedText = nil; on.lastSubmittedNormalizedText = nil;
    TraceCycle(on, full); TraceCycle(on, full);
    Require(MockRequests == 1, @"cache hit does not submit another request");
    BOOL hit = NO, skipped = NO;
    for (NSDictionary *r in Records(log)) {
        hit |= [r[@"event"] isEqual:@"cache"] && [r[@"cache_hit"] boolValue];
        skipped |= [r[@"reason"] isEqual:@"same_as_last_translated"];
    }
    Require(hit && skipped, @"cache hit and unchanged skip are observable");
    TracePipelineApp *late = TraceApp();
    TraceCycle(late, full);
    HoldResponse = YES; late.fixture = full; [late timerFired:nil];
    Pump(^BOOL { return PendingResponse != nil; });
    [late timerFired:nil];
    BOOL busy = NO;
    for (NSDictionary *r in Records(log)) { busy |= [r[@"reason"] isEqual:@"task_busy"]; }
    Require(busy, @"busy cycle is observable without capturing another frame");
    late.fixtureWindowID = 43; PendingResponse(); PendingResponse = nil; HoldResponse = NO;
    Pump(^BOOL { return !late.inFlight; });
    Require(late.captions.count == 0, @"window change still drops response");
    BOOL dropped = NO;
    for (NSDictionary *r in Records(log)) { dropped |= [r[@"event"] isEqual:@"caption_drop"] && [r[@"reason"] isEqual:@"window_changed"]; }
    Require(dropped, @"window change reason logged");
    TracePipelineApp *ui = TraceApp(); ui.fixtureMode = ContentModeUI;
    TraceCycle(ui, Fixture(@"設定メニュー", .3));
    Require(ui.inlineApplies == 0, @"first UI frame waits for confirmation using the real stabilizer");
    TraceCycle(ui, Fixture(@"設定メニュー", .3));
    Pump(^BOOL { return ui.inlineApplies == 1; });
    Require(Count(Records(log), @"inline_apply") == 1, @"UI transition route can correlate inline application");
    NSString *text = [NSString stringWithContentsOfFile:log encoding:NSUTF8StringEncoding error:NULL];
    Require(![text containsString:@"TRACE_CREDENTIAL_SENTINEL"] && ![text containsString:@"TRACE_PRIVATE_PROMPT_SENTINEL"] && ![text containsString:@"Authorization"] && ![text containsString:@"example.invalid"], @"actual logging call sites exclude credential/prompt/header/URL");
    NSDictionary *runtime = [FYRuntimeDiagnostics.shared reportForSnapshot:@{}];
    NSString *metadata = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:runtime options:0 error:NULL] encoding:NSUTF8StringEncoding];
    Require(![metadata containsString:@"TRACE_CREDENTIAL"] && ![metadata containsString:@"TRACE_PRIVATE"] && ![metadata containsString:@"明日は"] && ![metadata containsString:@"example.invalid"], @"runtime metadata call sites never retain credentials, prompts, dialogue or endpoint");
    Require(Count(runtime[@"events"], @"ocr") > 0 && Count(runtime[@"events"], @"http") > 0 && Count(runtime[@"events"], @"caption") > 0, @"runtime history includes real OCR, request and caption metadata");
    NSUInteger bytes = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    [NSFileManager.defaultManager removeItemAtPath:[root stringByAppendingPathComponent:@"control.json"] error:NULL];
    TraceCycle(on, partial); TraceCycle(on, partial);
    Require([[[NSFileManager defaultManager] attributesOfItemAtPath:log error:NULL] fileSize] == bytes, @"stop dynamically suppresses all pipeline writes");
    Require(NSApp == nil && FYCurrentTrace() == nil, @"no app UI and no leaked trace context");
    printf("PASS TranslationTracePipelineTests: off/on request parity=1; OCR/stability/cache/request/response/apply correlation; stale-window drop; inline route; credential exclusion; dynamic stop; synthetic capture and mock HTTP only\n");
} return 0; }
