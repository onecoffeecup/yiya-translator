// Production timer + translation/cache/response pipeline, synthetic OCR and
// capture, in-memory HTTP completion. No NSApplication or real network.
#import "LearningAppTestSupport.h"
#import <objc/runtime.h>
#import <sys/stat.h>
#import "FYTestCaptureCardInput.h"

@interface AppDelegate (LivePreviewTests)
- (void)restartPreviewTimerIfRunning;
- (void)previewTimerFired:(NSTimer *)timer;
- (void)applyPreviewImage:(CGImageRef)image;
@end

static FYTranslationTrace *TestTrace;
static NSUInteger MockRequests;
static NSMutableArray *SubmittedSources;
static NSDictionary *LastRequestPolicy;
@class TraceTask;
static TraceTask *LastTask;
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
@property NSUInteger cancelCalls;
- (void)resume;
- (void)cancel;
@end
@implementation TraceTask
- (void)resume { if (HoldResponse) { PendingResponse = self.response; } else { self.response(); } }
- (void)cancel { self.cancelCalls++; }
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
        @"reasoning_effort": body[@"reasoning_effort"] ?: @"", @"timeout": @(request.timeoutInterval)};
    NSString *source = [body[@"messages"] lastObject][@"content"];
    [SubmittedSources addObject:source];
    MockRequests++;
    NSString *translated = [source hasPrefix:@"1. "] ? @"1. 测试界面" : [NSString stringWithFormat:@"测试译文%lu", (unsigned long)MockRequests];
    TraceTask *task = [TraceTask new]; LastTask = task;
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
@property(copy) NSString *lastStatus;
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
- (void)setStatus:(NSString *)s { self.lastStatus=s; }
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

// Hold only the OCR service boundary. All capture, cancellation, generation
// checks and busy-state delivery continue through the production AppDelegate.
@interface TraceHeldOCRApp : TracePipelineApp
@property NSArray *ocrEntered, *ocrReleaseGates;
@property BOOL observeGenerationReads;
@property NSUInteger observedGenerationReads;
@end

@interface TraceWindowState : NSObject
@property(getter=isVisible) BOOL visible;
@property(getter=isMiniaturized) BOOL miniaturized;
@property(getter=isOnActiveSpace) BOOL onActiveSpace;
@property NSWindowOcclusionState occlusionState;
@end
@implementation TraceWindowState
@end

@interface TracePreviewApp : TracePipelineApp
@property NSUInteger previewApplies;
@property size_t previewWidth;
@property NSUInteger previewCaptures;
@end
@implementation TracePreviewApp
- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)windowID {
    @synchronized(self) { self.previewCaptures++; }
    return [super copyFullCapturedImageForWindow:windowID];
}
- (void)applyPreviewImage:(CGImageRef)image {
    Require(NSThread.isMainThread, @"preview images are applied on main");
    self.previewApplies++; self.previewWidth = CGImageGetWidth(image);
}
@end
@implementation TraceHeldOCRApp
- (NSInteger)translationGeneration {
    if (NSThread.isMainThread && self.observeGenerationReads) { self.observedGenerationReads++; }
    return [super translationGeneration];
}
- (NSArray *)recognizeTextItemsInImage:(CGImageRef)i fastOCR:(BOOL)f languageSegment:(NSInteger)l error:(NSError **)e {
    NSUInteger slot;
    @synchronized(self) { slot = self.ocrCalls++; }
    Require(slot < self.ocrEntered.count, @"unexpected overlapping OCR");
    dispatch_semaphore_signal(self.ocrEntered[slot]);
    Require(dispatch_semaphore_wait(self.ocrReleaseGates[slot], dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0,
            @"held synthetic OCR must be released");
    return @[];
}
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
static TracePipelineApp *TraceAppOfClass(Class appClass) {
    TracePipelineApp *a = [appClass new]; a.running = YES; a.fixtureWindowID = 42;
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
    if ([a isKindOfClass:TracePreviewApp.class]) {
        TraceWindowState *window=[TraceWindowState new]; window.visible=YES; window.onActiveSpace=YES;
        window.occlusionState=NSWindowOcclusionStateVisible; a.mainWindow=(id)window;
    }
    a.learningCoordinator = [[FYLearningCoordinator alloc] initWithStore:nil analyzer:nil tokenizer:nil catalog:nil];
    return a;
}
static TracePipelineApp *TraceApp(void) { return TraceAppOfClass(TracePipelineApp.class); }
static NSArray *Fixture(NSString *text, CGFloat width);
static void CheckIndependentLivePreview(void) {
    Require([AppDelegate instancesRespondToSelector:@selector(restartPreviewTimerIfRunning)],
            @"live preview needs a scheduler independent of held translation requests");
    for (NSUInteger source = 0; source < 2; source++) {
        TracePreviewApp *a = (id)TraceAppOfClass(TracePreviewApp.class);
        a.framePreview = (id)[NSObject new]; // Display boundary only; no AppKit window.
        a.inputSourceSegment = source;
        FYTestCaptureCardInput *card = [FYTestCaptureCardInput new]; a.captureCardInput = card;
        Require([card testEnqueueFrameIndex:1 pixelSize:16], @"initial synthetic frame");
        CGImageRef stale = [card copyLatestFrame];
        a.fixture = Fixture(@"明日はみんなで図書館に行きましょう。", .65);
        ((TraceControl *)(id)a.stableTextCheckbox).state = NSControlStateValueOff;
        MockRequests = 0; SubmittedSources = [NSMutableArray new];
        PendingResponse = nil; HoldResponse = YES;
        [a timerFired:nil]; Pump(^BOOL { return PendingResponse != nil; });
        Require(a.inFlight, @"production HTTP request is held while preview is tested");
        NSUInteger ocrBefore = a.ocrCalls, requestsBefore = MockRequests;
        uint64_t ocrFrameBefore = a.lastOCRedCaptureFrameIndex;
        [a restartPreviewTimerIfRunning];
        NSTimeInterval expectedInterval = source == 1 ? 1.0 / 30.0 : .1;
        Require(fabs(((NSTimer *)[a valueForKey:@"previewTimer"]).timeInterval - expectedInterval) < .001,
                @"capture-card preview targets 30 fps, window screenshots retain 10 fps");
        for (NSUInteger index = 1; index <= 3; index++) {
            Require([card testEnqueueFrameIndex:index + 1 pixelSize:16 + index], @"synthetic latest frame");
            CGImageRef frame = [card copyLatestFrame]; FYTestSetWindowImage(frame); CGImageRelease(frame);
            NSUInteger before = a.previewApplies;
            Pump(^BOOL { return a.previewApplies > before && a.previewWidth == 16 + index; });
            Require(a.previewWidth == 16 + index, @"preview follows new frames while translation is busy");
        }
        Require(a.inFlight && a.ocrCalls == ocrBefore && MockRequests == requestsBefore,
                @"preview never clears OCR ownership or submits extra translation requests");
        if (source == 1) {
            NSUInteger before = a.previewApplies;
            for (NSUInteger tick = 0; tick < 5; tick++) { [a previewTimerFired:nil]; Tick(); }
            Require(a.previewApplies == before, @"unchanged capture-card frame is not rendered repeatedly");
            Require(a.lastOCRedCaptureFrameIndex == ocrFrameBefore, @"preview does not consume OCR frame identity");
        }
        [((NSTimer *)[a valueForKey:@"previewTimer"]) setFireDate:NSDate.distantFuture];
        Pump(^BOOL { return !a.previewInFlight; });
        NSUInteger liveApplies = a.previewApplies;
        // Invoke the production method, bypassing the fixture's no-op OCR display.
        void (*update)(id, SEL, CGImageRef, NSInteger) = (void *)class_getMethodImplementation(AppDelegate.class,
            @selector(updatePreviewFromImage:generation:));
        update(a, @selector(updatePreviewFromImage:generation:), stale, a.translationGeneration);
        CGImageRelease(stale);
        Tick();
        Require(a.previewApplies == liveApplies && a.previewWidth == 19,
                @"old OCR pixels cannot overwrite the newer independent preview");
        void (^response)(void) = PendingResponse; PendingResponse = nil; HoldResponse = NO;
        [a stop]; response(); NSUInteger stopped = a.previewApplies;
        [a previewTimerFired:nil]; Tick();
        Require(a.previewApplies == stopped, @"paused preview stays stopped");
    }
    FYTestSetWindowImage(NULL);

    TracePreviewApp *switched = (id)TraceAppOfClass(TracePreviewApp.class);
    switched.framePreview = (id)[NSObject new];
    for (NSNumber *source in @[@0, @1, @0]) {
        switched.inputSourceSegment = source.integerValue;
        [switched resetForInputSourceChange];
        Require(fabs(switched.previewTimer.timeInterval - (source.integerValue == 1 ? 1.0 / 30.0 : .1)) < .001,
                @"switching inputs applies the corresponding live preview cadence immediately");
    }
    [switched stop];

    for (NSUInteger action = 0; action < 7; action++) {
        TracePreviewApp *held = (id)TraceAppOfClass(TracePreviewApp.class);
        held.framePreview = (id)[NSObject new]; held.inFlight = YES;
        held.captureEntered = dispatch_semaphore_create(0); held.captureRelease = dispatch_semaphore_create(0);
        dispatch_semaphore_t release = held.captureRelease;
        [held restartPreviewTimerIfRunning];
        __block BOOL entered = NO;
        Pump(^BOOL {
            if (!entered) { entered = dispatch_semaphore_wait(held.captureEntered, DISPATCH_TIME_NOW) == 0; }
            return entered;
        });
        for (NSUInteger tick = 0; tick < 20; tick++) { [held previewTimerFired:nil]; }
        Require(held.previewCaptures == 1, @"slow captures have only one preview task in flight");
        if (action == 0) { [held stop]; }
        if (action == 1) { held.fixtureWindowID = 43; }
        if (action == 2) { [held advanceTranslationGeneration]; }
        if (action == 3) { held.inputSourceSegment = 1; }
        if (action == 4) { [held restartPreviewTimerIfRunning]; }
        if (action == 5) { [held.captureCardInput stop]; }
        if (action == 6) { ((TraceWindowState *)(id)held.mainWindow).visible=NO; [held refreshPreviewVisibility:nil]; }
        [(NSTimer *)[held valueForKey:@"previewTimer"] invalidate];
        dispatch_semaphore_signal(release);
        Pump(^BOOL { return ![[held valueForKey:@"previewInFlight"] boolValue]; });
        Require(held.previewApplies == 0, @"late pixels cannot reappear after stop/window/source/generation/restart/epoch changes");
        [held stop];
    }
    printf("PASS independent live preview: held HTTP, capture 30 Hz/window 10 Hz, bounded work, stale delivery protection\n");
}

static void CheckHiddenPreview(void) {
    for (NSUInteger state=0; state<4; state++) {
        TracePreviewApp *a=(id)TraceAppOfClass(TracePreviewApp.class);
        a.framePreview=(id)[NSObject new];
        TraceWindowState *w=(id)a.mainWindow;
        [a restartPreviewTimerIfRunning]; Pump(^BOOL { return !a.previewInFlight; });
        NSUInteger before=a.previewCaptures;
        if(state==0) w.visible=NO;
        if(state==1) w.miniaturized=YES;
        if(state==2) w.onActiveSpace=NO;
        if(state==3) w.occlusionState=0;
        [a restartPreviewTimerIfRunning];
        [a previewTimerFired:nil]; Tick();
        Require(!a.previewTimer && a.previewCaptures==before,@"hidden/minimized/other-space/occluded preview performs no screenshots");
        w.visible=YES; w.miniaturized=NO; w.onActiveSpace=YES; w.occlusionState=NSWindowOcclusionStateVisible;
        [a restartPreviewTimerIfRunning];
        Pump(^BOOL { return a.previewCaptures>before && !a.previewInFlight; });
        Require(a.previewTimer!=nil,@"visible preview resumes immediately");
        [a stop];
    }
}
static void CheckCapturePreviewCadence(void) {
    FYCaptureCardInput *input=[FYCaptureCardInput new];
    Require(!input.previewActive,@"input defaults to OCR-only cadence");
    input.previewActive=YES; Require(input.previewActive,@"visible preview enables 30 Hz conversion");
    input.previewActive=NO; Require(!input.previewActive,@"hidden preview restores 10 Hz conversion");
    FYCaptureCardFrameSlot *ownedSlot=[input valueForKey:@"slot"];
    CGImageRef injected=FYTestWindowImage(CGRectNull,kCGWindowListOptionIncludingWindow,42,kCGWindowImageDefault);
    for (NSNumber *visible in @[@NO,@YES]) {
        input.previewActive=visible.boolValue; [ownedSlot clear]; NSUInteger accepted=0;
        for (NSUInteger index=0;index<60;index++) {
            NSTimeInterval now=100+index/60.0;
            if ([ownedSlot shouldStoreFrameAtTime:now]) { [ownedSlot storeFrame:injected index:index+1 atTime:now]; accepted++; }
        }
        Require(accepted==(visible.boolValue ? 30 : 10),@"actual input-owned slot converts 10 background or 30 visible frames per second");
    }
    CGImageRelease(injected);
    FYCaptureCardFrameSlot *slot = [FYCaptureCardFrameSlot new];
    CGImageRef frame = FYTestWindowImage(CGRectNull, kCGWindowListOptionIncludingWindow, 42, kCGWindowImageDefault);
    NSUInteger accepted = 0;
    for (NSUInteger index = 0; index < 60; index++) {
        // Normal 60 Hz input with sub-millisecond callback timing variation.
        NSTimeInterval now = 100.0 + index / 60.0 + (index % 4 == 2 ? -.0005 : 0);
        if ([slot shouldStoreFrameAtTime:now]) { [slot storeFrame:frame index:index + 1 atTime:now]; accepted++; }
    }
    Require(accepted == 30, @"capture-card slot must admit 30 fresh frames per second rather than the old 10 fps cap");
    CGImageRef preview = FYCopyPreviewImage(frame);
    Require(preview == frame, @"native-size immutable preview avoids a redundant full-frame pixel copy");
    CGImageRelease(frame);
    Require(CGImageGetWidth(preview) == 16, @"reused preview retains its own image lifetime");
    CGImageRelease(preview);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 3000, 2, 8, 12000, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    Require(context != NULL, @"synthetic oversized preview image");
    CGImageRef large = CGBitmapContextCreateImage(context); CGContextRelease(context);
    CGImageRef bounded = FYCopyPreviewImage(large);
    Require(bounded && CGImageGetWidth(bounded) == 2560, @"oversized preview still resizes within its pixel budget");
    CGImageRelease(large); CGImageRelease(bounded);
    printf("PASS capture preview cadence: 30/60 synthetic frames, bounded latest slot, no redundant native-size copy\n");
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
        TraceTask *testTask = LastTask;
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
        Require([a.serviceStatusLabel.stringValue isEqual:@"正在测试服务"] && testTask.cancelCalls == 0, @"run changes must leave service test owned and pending");
        staleResponse(); Tick();
        Require([a.serviceStatusLabel.stringValue isEqual:@"服务测试成功"] && a.captions.count == 0,
                @"test completes independently without replacing the changed run caption");
        if (!a.running) { Require([a.lastStatus isEqual:@"翻译测试完成"],@"a completed test clears the paused status even after window/source/scope changes"); }
        HoldResponse = NO;
    }
}
static void CheckServiceConfigurationCancellation(void) {
    for (NSUInteger action=0;action<2;action++) {
        TracePipelineApp *a=TraceApp(); a.running=NO; SubmittedSources=[NSMutableArray new]; HoldResponse=YES;
        [a testTranslation:nil]; TraceTask *oldTask=LastTask;
        void (^oldResponse)(void)=PendingResponse; PendingResponse=nil;
        if (action==0) { [a serviceSettingsChanged]; }
        else { [a testTranslation:nil]; }
        Require(oldTask.cancelCalls==1,@"changing service or testing again cancels the old service task only");
        oldResponse(); Tick();
        Require([a.serviceStatusLabel.stringValue isEqual:action==0 ? @"服务未测试" : @"正在测试服务"],@"old service completion cannot overwrite changed configuration or replacement test");
        if (action==0) { Require([a.lastStatus isEqual:@"服务未测试"],@"cancelled service test clears paused testing status"); }
        if (action==1) { void (^fresh)(void)=PendingResponse; PendingResponse=nil; fresh(); Tick();
            Require([a.serviceStatusLabel.stringValue isEqual:@"服务测试成功"] && a.captions.count==1,@"replacement service test completes and keeps idle test-caption behavior"); }
        HoldResponse=NO;
    }
}
static void CheckInlineRequestTimeouts(void) {
    TracePipelineApp *a=TraceApp(); HoldResponse=NO; SubmittedSources=[NSMutableArray new];
    NSMutableArray *items=[NSMutableArray array],*indexes=[NSMutableArray array],*keys=[NSMutableArray array];
    for (NSUInteger index=0;index<4;index++) {
        [items addObject:Fixture(@"合成按钮",.1).firstObject]; [indexes addObject:@(index)]; [keys addObject:[NSString stringWithFormat:@"fixture-%lu",(unsigned long)index]];
    }
    for (NSNumber *longText in @[@NO,@YES]) {
        __block BOOL done=NO;
        NSMutableArray *translations=[NSMutableArray arrayWithArray:@[@"",@"",@"",@""]];
        [a translateInlineBatch:items indexes:indexes keys:keys translations:translations long:longText.boolValue completion:^(NSError *error) { Require(!error,@"synthetic inline batch decodes"); done=YES; }];
        Pump(^BOOL { return done; });
        NSTimeInterval timeout=[LastRequestPolicy[@"timeout"] doubleValue];
        Require(longText.boolValue ? timeout>=60 && timeout<=90 : timeout==15,@"actual AppDelegate short/long batch request uses explicit timeout category");
    }
}
static void CheckAtomicCaptureIdentity(void) {
    TracePipelineApp *a=TraceApp(); a.inputSourceSegment=1; a.fixture=@[];
    FYTestCaptureCardInput *card=[FYTestCaptureCardInput new]; a.captureCardInput=card;
    Require([card testEnqueueFrameIndex:1 pixelSize:16],@"first synthetic capture frame");
    dispatch_semaphore_t entered=dispatch_semaphore_create(0), release=dispatch_semaphore_create(0);
    dispatch_async(a.captureQueue, ^{ dispatch_semaphore_signal(entered); dispatch_semaphore_wait(release,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)); });
    Require(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0,@"capture queue held before tick");
    [a timerFired:nil]; Require(a.inFlight,@"queued capture owns busy slot");
    Require([card testEnqueueFrameIndex:2 pixelSize:18],@"new frame arrives before background copy");
    dispatch_semaphore_signal(release); Pump(^BOOL { return !a.inFlight; });
    Require(a.lastOCRedCaptureFrameIndex==2,@"OCR identity is the atomically copied frame, rather than the tick snapshot");
    NSUInteger calls=a.ocrCalls; [a timerFired:nil]; Tick();
    Require(a.ocrCalls==calls,@"same actual frame cannot enter OCR twice"); [a stop];
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
static void CheckLateOCRRestartOwnership(void) {
    for (NSUInteger oldRoute = 0; oldRoute < 2; oldRoute++) {
        for (NSUInteger newRoute = 0; newRoute < 2; newRoute++) {
            TraceHeldOCRApp *a = (id)TraceAppOfClass(TraceHeldOCRApp.class);
            a.ocrEntered = @[dispatch_semaphore_create(0), dispatch_semaphore_create(0), dispatch_semaphore_create(0)];
            a.ocrReleaseGates = @[dispatch_semaphore_create(0), dispatch_semaphore_create(0), dispatch_semaphore_create(0)];
            NSUInteger requestsBefore = MockRequests;
            if (oldRoute) { [a translateCurrentInterface:nil]; } else { [a timerFired:nil]; }
            __block BOOL entered = NO;
            Pump(^BOOL { return entered || (entered = dispatch_semaphore_wait(a.ocrEntered[0], DISPATCH_TIME_NOW) == 0); });
            [a stop];
            if (newRoute) { [a translateCurrentInterface:nil]; }
            else { [a start]; [a.timer invalidate]; a.timer = nil; }
            entered = NO;
            Pump(^BOOL { return entered || (entered = dispatch_semaphore_wait(a.ocrEntered[1], DISPATCH_TIME_NOW) == 0); });
            Require(a.inFlight, @"the restarted cycle owns the busy flag while its OCR is held");
            // Observing the production generation read acknowledges the stale
            // main-queue callback without sleeps or a simulated delivery guard.
            a.observeGenerationReads = YES;
            dispatch_semaphore_signal(a.ocrReleaseGates[0]);
            Pump(^BOOL { return a.observedGenerationReads > 0; });
            a.observeGenerationReads = NO;
            Require(a.inFlight, @"stale OCR must not release a restarted cycle's busy flag");
            [a timerFired:nil]; [a translateCurrentInterface:nil];
            Require(a.ocrCalls == 2 && a.inFlight, @"busy timer/manual entry points cannot start a third OCR");
            dispatch_semaphore_signal(a.ocrReleaseGates[1]);
            Pump(^BOOL { return !a.inFlight; });
            Require(a.captions.count == 0 && a.inlineApplies == 0 && MockRequests == requestsBefore,
                    @"cancelled empty OCR cannot reach translation or display");
            dispatch_semaphore_signal(a.ocrReleaseGates[2]);
            a.running = YES; TraceCycle(a, @[]);
            Require(a.ocrCalls == 3, @"the current cycle releases busy ownership and allows a fresh OCR");
            [a stop];
        }
    }
    puts("PASS late OCR restart ownership: 4 realtime/manual combinations; no overlapping cycle or stale display");
}
static void CheckDialogueLatencyPolicies(void) {
    // Exercise the actual scheduled timer and serialized HTTP request. Only
    // fictional service configuration is inspected; no UI or real API calls.
    TracePipelineApp *polling = TraceApp();
    // Synthetic legacy preferences, isolated in-memory store.
    [NSUserDefaults.standardUserDefaults setObject:@{@"interval":@4,@"fastOCR":@YES,@"stableText":@NO} forKey:SettingsKey];
    [polling loadSettings];
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
    Require(interfaceInterval == 1.2, @"interface polling ignores old hidden cadence and uses 1.2 seconds");
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
    CheckHiddenPreview();
    CheckServiceConfigurationCancellation();
    CheckInlineRequestTimeouts();
    CheckAtomicCaptureIdentity();
    CheckLateCaptureCancellation();
    CheckLateOCRRestartOwnership();
    CheckVisibilitySnapshots();
    CheckDialogueLatencyPolicies();
    CheckCapturePreviewCadence();
    CheckIndependentLivePreview();
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
