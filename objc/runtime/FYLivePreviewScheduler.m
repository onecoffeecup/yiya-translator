#import "FYLivePreviewScheduler.h"
#import "FYPreviewImage.h"

@implementation FYPreviewFrameLease {
    FYPreviewFrameCopy _frameCopy;
    NSUInteger (^_sessionEpoch)(void);
}
- (instancetype)initWithFrameCopy:(FYPreviewFrameCopy)frameCopy sessionEpoch:(NSUInteger (^)(void))sessionEpoch {
    if ((self = [super init])) { _frameCopy = [frameCopy copy]; _sessionEpoch = [sessionEpoch copy]; }
    return self;
}
- (CGImageRef)copyFrameWithIndex:(uint64_t *)actualIndex { return _frameCopy(actualIndex); }
- (NSUInteger)currentSessionEpoch { return _sessionEpoch(); }
@end

@implementation FYLivePreviewScheduler
- (instancetype)initWithSource:(id<FYLivePreviewSource>)source queue:(dispatch_queue_t)queue {
    if ((self = [super init])) { _source = source; _queue = queue; }
    return self;
}

- (void)invalidateResults {
    self.requestSerial += 1;
    self.renderSerial += 1;
    self.lastCaptureFrameIndex = 0;
    // A queued task keeps the busy slot until its main-thread completion.
}

- (void)restartWithSnapshot:(FYLivePreviewSnapshot)snapshot timerTarget:(id<FYLivePreviewTimerTarget>)target {
    [self.timer invalidate];
    self.timer = nil;
    [self invalidateResults];
    if (!snapshot.running || !snapshot.hasSurface || !snapshot.visible) { return; }
    self.timer = [NSTimer timerWithTimeInterval:snapshot.frameInterval target:target
        selector:@selector(previewTimerFired:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [target previewTimerFired:self.timer];
}

- (void)tick {
    id<FYLivePreviewSource> source = self.source;
    if (!source) { return; }
    FYLivePreviewSnapshot snapshot = [source previewSnapshot];
    if (!snapshot.visible) { [source refreshPreviewVisibility]; return; }
    if (!snapshot.running || !snapshot.hasSurface || self.inFlight) { return; }
    if (!snapshot.captureCard && snapshot.windowID == 0) { return; }
    if (snapshot.captureCard && (snapshot.latestFrameIndex == 0 || snapshot.latestFrameIndex == self.lastCaptureFrameIndex)) { return; }
    FYPreviewFrameLease *lease = [source previewFrameLeaseForSnapshot:snapshot];
    NSUInteger serial = ++self.requestSerial;
    self.inFlight = YES;
    dispatch_async(self.queue, ^{
        @autoreleasepool {
            uint64_t actualIndex = 0;
            CGImageRef image = [lease copyFrameWithIndex:&actualIndex];
            CGImageRef preview = FYCopyPreviewImage(image);
            if (image) { CGImageRelease(image); }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.inFlight = NO;
                id<FYLivePreviewSource> receiver = self.source;
                if (serial == self.requestSerial && preview && receiver) {
                    FYLivePreviewSnapshot current = [receiver previewSnapshot];
                    if (current.running && current.visible && snapshot.generation == current.generation &&
                        snapshot.sessionEpoch == lease.currentSessionEpoch &&
                        snapshot.captureCard == current.captureCard && snapshot.windowID == current.windowID) {
                        self.lastCaptureFrameIndex = actualIndex;
                        [receiver presentPreviewImage:preview];
                    }
                }
                if (preview) { CGImageRelease(preview); }
            });
        }
    });
}

- (void)renderStoppedImage:(CGImageRef)image generation:(NSInteger)generation delivery:(void (^)(CGImageRef))delivery {
    id<FYLivePreviewSource> source = self.source;
    if (!image || !source) { return; }
    FYLivePreviewSnapshot snapshot = [source previewSnapshot];
    if (!snapshot.hasSurface || snapshot.running) { return; }
    NSDate *now = [NSDate date];
    if (self.lastRenderDate && [now timeIntervalSinceDate:self.lastRenderDate] < 0.1) { return; }
    self.lastRenderDate = now;
    NSUInteger serial = ++self.renderSerial;
    CGImageRef retained = CGImageRetain(image);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        CGImageRef scaled = FYCopyPreviewImage(retained);
        CGImageRelease(retained);
        if (!scaled) { return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            id<FYLivePreviewSource> receiver = self.source;
            if (receiver) {
                FYLivePreviewSnapshot current = [receiver previewSnapshot];
                if (generation == current.generation && serial == self.renderSerial) { delivery(scaled); }
            }
            CGImageRelease(scaled);
        });
    });
}
@end
