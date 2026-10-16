#import "FYLivePreviewScheduler.h"
#import "FYPreviewImage.h"
#import <math.h>

static NSUInteger checks;
static void Check(BOOL value, const char *message) {
    checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); exit(2); }
}
static void Pump(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done() && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.002]];
    }
    Check(done(), "async completion arrives within the bounded deadline");
}
static CGImageRef Frame(size_t width) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, 4, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}

@interface PreviewProbe : NSObject <FYLivePreviewSource, FYLivePreviewTimerTarget>
@property(nonatomic) FYLivePreviewSnapshot state;
@property(nonatomic, weak) FYLivePreviewScheduler *scheduler;
@property(nonatomic) NSUInteger captures;
@property(nonatomic) NSUInteger applies;
@property(nonatomic) NSUInteger visibilityRefreshes;
@property(nonatomic) NSUInteger originalEpoch;
@property(nonatomic) uint64_t actualIndex;
@property(nonatomic) BOOL nullFrame;
@property(nonatomic, strong) dispatch_semaphore_t entered;
@property(nonatomic, strong) dispatch_semaphore_t releaseFrame;
@end
@implementation PreviewProbe
- (instancetype)init {
    if ((self = [super init])) {
        _state = (FYLivePreviewSnapshot){YES, YES, YES, NO, 9, 3, 42, 1, .1};
        _originalEpoch = 3; _actualIndex = 1;
    }
    return self;
}
- (FYLivePreviewSnapshot)previewSnapshot {
    Check(NSThread.isMainThread, "snapshot reads occur on main");
    return self.state;
}
- (FYPreviewFrameLease *)previewFrameLeaseForSnapshot:(FYLivePreviewSnapshot)snapshot {
    Check(NSThread.isMainThread, "resource lease is created on main");
    // Simulates only the image source and its resource lifetime, not scheduling.
    PreviewProbe *owner = self;
    return [[FYPreviewFrameLease alloc] initWithFrameCopy:^CGImageRef(uint64_t *index) {
        if (NSThread.isMainThread) { fprintf(stderr, "FAIL: capture must be off main\n"); exit(2); }
        owner.captures++;
        if (owner.entered) { dispatch_semaphore_signal(owner.entered); }
        if (owner.releaseFrame) { dispatch_semaphore_wait(owner.releaseFrame, DISPATCH_TIME_FOREVER); }
        *index = owner.actualIndex;
        return owner.nullFrame ? NULL : Frame(7);
    } sessionEpoch:^NSUInteger { return owner.originalEpoch; }];
}
- (void)refreshPreviewVisibility { self.visibilityRefreshes++; }
- (void)presentPreviewImage:(CGImageRef)image {
    Check(NSThread.isMainThread && image && CGImageGetWidth(image) == 7, "real preview pixels are delivered on main");
    self.applies++;
}
- (void)previewTimerFired:(NSTimer *)timer { [self.scheduler tick]; }
@end

static FYLivePreviewScheduler *Scheduler(PreviewProbe *probe) {
    FYLivePreviewScheduler *scheduler = [[FYLivePreviewScheduler alloc] initWithSource:probe
        queue:dispatch_queue_create("test.preview", DISPATCH_QUEUE_SERIAL)];
    probe.scheduler = scheduler;
    return scheduler;
}
static void Hold(PreviewProbe *probe) {
    probe.entered = dispatch_semaphore_create(0);
    probe.releaseFrame = dispatch_semaphore_create(0);
}
static void Entered(PreviewProbe *probe) {
    __block BOOL entered = NO;
    Pump(^BOOL {
        if (!entered) { entered = dispatch_semaphore_wait(probe.entered, DISPATCH_TIME_NOW) == 0; }
        return entered;
    });
}
static void ReleaseAndDrain(FYLivePreviewScheduler *scheduler, PreviewProbe *probe) {
    dispatch_semaphore_signal(probe.releaseFrame);
    Pump(^BOOL { return !scheduler.inFlight; });
    probe.entered = nil; probe.releaseFrame = nil;
}

int main(void) { @autoreleasepool {
    __weak PreviewProbe *idle;
    FYLivePreviewScheduler *scheduler;
    @autoreleasepool {
        PreviewProbe *probe = [PreviewProbe new]; idle = probe; scheduler = Scheduler(probe);
        Check(!scheduler.timer && !scheduler.inFlight && probe.captures == 0, "minimal construction creates no timer or capture");
    }
    Check(!idle && !scheduler.source, "idle component holds its source weakly");
    [scheduler tick];
    Check(!scheduler.inFlight, "released source does not schedule work");

    PreviewProbe *probe = [PreviewProbe new]; scheduler = Scheduler(probe);
    FYLivePreviewSnapshot state = probe.state;
    state.visible = NO; probe.state = state; [scheduler tick];
    Check(probe.visibilityRefreshes == 1 && !scheduler.inFlight, "hidden input uses the existing visibility refresh seam");
    state.visible = YES; state.running = NO; probe.state = state; [scheduler tick];
    state.running = YES; state.hasSurface = NO; probe.state = state; [scheduler tick];
    state.hasSurface = YES; state.windowID = 0; probe.state = state; [scheduler tick];
    Check(probe.captures == 0 && !scheduler.inFlight, "stopped, absent-surface and absent-window inputs do not capture");
    state.captureCard = YES; state.latestFrameIndex = 0; probe.state = state; [scheduler tick];
    state.latestFrameIndex = 1; probe.state = state; scheduler.lastCaptureFrameIndex = 1; [scheduler tick];
    Check(probe.captures == 0, "capture-card empty and already-rendered frame identities are skipped");
    scheduler.lastCaptureFrameIndex = 0; probe.actualIndex = 8;
    [scheduler tick]; Pump(^BOOL { return !scheduler.inFlight; });
    Check(probe.applies == 1 && scheduler.lastCaptureFrameIndex == 8, "delivery records the actual frame index returned atomically with pixels");

    // A held capture spanning invalidation and restart retains one busy lease.
    probe = [PreviewProbe new]; scheduler = Scheduler(probe); Hold(probe);
    [scheduler restartWithSnapshot:probe.state timerTarget:probe]; Entered(probe);
    Check(fabs(scheduler.timer.timeInterval - .1) < .0001, "window timer keeps 100 ms cadence");
    for (NSUInteger i = 0; i < 20; i++) { [scheduler tick]; }
    NSUInteger serial = scheduler.requestSerial, render = scheduler.renderSerial;
    scheduler.lastCaptureFrameIndex = 90; [scheduler invalidateResults];
    Check(scheduler.inFlight && scheduler.requestSerial == serial + 1 && scheduler.renderSerial == render + 1 &&
          scheduler.lastCaptureFrameIndex == 0, "invalidation changes identities without releasing the queued busy lease");
    [scheduler restartWithSnapshot:probe.state timerTarget:probe];
    [scheduler.timer setFireDate:NSDate.distantFuture];
    Check(probe.captures == 1 && scheduler.inFlight, "restart cannot enqueue a second capture behind held old work");
    ReleaseAndDrain(scheduler, probe);
    Check(probe.applies == 0, "invalidated held capture is discarded");
    [scheduler tick]; Pump(^BOOL { return !scheduler.inFlight; });
    Check(probe.captures == 2 && probe.applies == 1, "after old delivery a new request can own the busy lease");
    [scheduler.timer invalidate]; scheduler.timer = nil;
    state = probe.state; state.captureCard = YES; state.frameInterval = 1.0 / 30.0; probe.state = state;
    [scheduler restartWithSnapshot:state timerTarget:probe];
    Check(fabs(scheduler.timer.timeInterval - 1.0 / 30.0) < .0001, "capture-card timer keeps its supplied 30 Hz cadence");
    [scheduler.timer invalidate]; scheduler.timer = nil; Pump(^BOOL { return !scheduler.inFlight; });

    for (NSUInteger boundary = 0; boundary < 8; boundary++) {
        probe = [PreviewProbe new]; scheduler = Scheduler(probe); Hold(probe);
        [scheduler tick]; Entered(probe);
        state = probe.state;
        if (boundary == 0) { state.generation++; }
        if (boundary == 1) { probe.originalEpoch++; }
        if (boundary == 2) { state.windowID++; }
        if (boundary == 3) { state.captureCard = YES; }
        if (boundary == 4) { state.running = NO; }
        if (boundary == 5) { state.visible = NO; }
        if (boundary == 6) { [scheduler invalidateResults]; }
        if (boundary == 7) { probe.nullFrame = YES; }
        probe.state = state;
        ReleaseAndDrain(scheduler, probe);
        Check(probe.applies == 0 && scheduler.lastCaptureFrameIndex == 0, "late/null pixels cannot pass changed generation, epoch, window, source, stop, visibility or serial");
    }

    // A queued frame retains the original receiver only until work finishes.
    __weak PreviewProbe *pending;
    dispatch_semaphore_t release;
    @autoreleasepool {
        probe = [PreviewProbe new]; pending = probe; scheduler = Scheduler(probe); Hold(probe);
        release = probe.releaseFrame; [scheduler tick]; Entered(probe); probe = nil;
    }
    Check(pending != nil, "queued capture resource lease retains its original receiver");
    dispatch_semaphore_signal(release);
    Pump(^BOOL { return !scheduler.inFlight; });
    Pump(^BOOL { return pending == nil; });
    Check(!scheduler.source, "completed capture releases original receiver and weak adapter");

    probe = [PreviewProbe new]; scheduler = Scheduler(probe);
    CGImageRef image = Frame(7);
    __block NSUInteger pausedApplies = 0;
    [scheduler renderStoppedImage:image generation:9 delivery:^(CGImageRef scaled) { (void)scaled; pausedApplies++; }];
    Check(!scheduler.lastRenderDate && pausedApplies == 0, "OCR image cannot schedule a render during live preview");
    state = probe.state; state.running = NO; probe.state = state;
    [scheduler renderStoppedImage:image generation:9 delivery:^(CGImageRef scaled) {
        Check(NSThread.isMainThread && CGImageGetWidth(scaled) == 7, "stopped rendering preserves pixels and main-thread delivery");
        pausedApplies++;
    }];
    NSUInteger renderSerial = scheduler.renderSerial;
    [scheduler renderStoppedImage:image generation:9 delivery:^(CGImageRef scaled) { (void)scaled; pausedApplies++; }];
    Check(scheduler.renderSerial == renderSerial, "stopped rendering retains 100 ms throttle");
    Pump(^BOOL { return pausedApplies == 1; });
    for (NSUInteger boundary = 0; boundary < 2; boundary++) {
        scheduler.lastRenderDate = nil;
        __weak PreviewProbe *renderLease;
        @autoreleasepool {
            PreviewProbe *token = [PreviewProbe new]; renderLease = token;
            [scheduler renderStoppedImage:image generation:state.generation delivery:^(CGImageRef scaled) {
                (void)scaled; token.applies++; pausedApplies++;
            }];
            if (boundary == 0) { state.generation++; probe.state = state; }
            else { [scheduler invalidateResults]; }
        }
        Pump(^BOOL { return renderLease == nil; });
        Check(pausedApplies == 1, "stopped old-generation or invalidated-serial render cannot overwrite newer work");
    }
    CGImageRelease(image);
    printf("PASS LivePreviewSchedulerTests: %lu checks; minimal source, bounded leases, identities, release and stopped rendering\n", (unsigned long)checks);
} return 0; }
