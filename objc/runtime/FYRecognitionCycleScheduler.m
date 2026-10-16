#import "FYRecognitionCycleScheduler.h"

BOOL FYCaptureFrameNeedsRecognition(uint64_t latestIndex, uint64_t lastRecognizedIndex) {
    return latestIndex != 0 && latestIndex != lastRecognizedIndex;
}

@implementation FYRecognitionCycleLease {
    NSInteger (^_generation)(void);
    BOOL (^_running)(void);
    uint32_t (^_windowID)(void);
    NSUInteger (^_inputEpoch)(void);
}
- (instancetype)initWithGeneration:(NSInteger (^)(void))generation running:(BOOL (^)(void))running
                          windowID:(uint32_t (^)(void))windowID inputEpoch:(NSUInteger (^)(void))inputEpoch {
    if ((self = [super init])) {
        _generation = [generation copy]; _running = [running copy];
        _windowID = [windowID copy]; _inputEpoch = [inputEpoch copy];
    }
    return self;
}
- (NSInteger)currentGeneration { return _generation(); }
- (BOOL)isRunning { return _running(); }
- (uint32_t)currentWindowID { return _windowID(); }
- (NSUInteger)currentInputEpoch { return _inputEpoch(); }
@end

@implementation FYRecognitionCycleIdentity
- (instancetype)initWithGeneration:(NSInteger)generation windowID:(uint32_t)windowID
                         inputEpoch:(NSUInteger)inputEpoch kind:(FYRecognitionCycleKind)kind {
    if ((self = [super init])) {
        _generation = generation; _windowID = windowID; _inputEpoch = inputEpoch; _kind = kind;
    }
    return self;
}
- (NSString *)captureDropReasonWithLease:(FYRecognitionCycleLease *)lease {
    if (self.generation != [lease currentGeneration]) return @"generation_changed";
    if (self.windowID != [lease currentWindowID]) return @"window_changed";
    if (self.inputEpoch != [lease currentInputEpoch]) return @"input_session_changed";
    return nil;
}
- (NSString *)recognitionDropReasonWithLease:(FYRecognitionCycleLease *)lease {
    if (self.generation != [lease currentGeneration]) return @"generation_changed";
    if (self.kind == FYRecognitionCycleRealtime && ![lease isRunning]) return @"stopped";
    if (self.windowID != [lease currentWindowID]) return @"window_changed";
    if (self.inputEpoch != [lease currentInputEpoch]) return @"input_session_changed";
    return nil;
}
@end

@implementation FYRecognitionCycleScheduler
- (void)beginCycle { self.inFlight = YES; }
- (void)finishCurrentCycle { self.inFlight = NO; }
- (void)finishCycle:(FYRecognitionCycleIdentity *)cycle lease:(FYRecognitionCycleLease *)lease {
    // Stop/start may already own a new busy slot. Match the original generation
    // release rule; neither window nor epoch changes suppress same-run release.
    if (cycle.generation == [lease currentGeneration]) [self finishCurrentCycle];
}
- (BOOL)needsCaptureFrame:(uint64_t)latestIndex {
    return FYCaptureFrameNeedsRecognition(latestIndex, self.lastRecognizedFrameIndex);
}
- (void)scheduleTimerWithInterval:(NSTimeInterval)interval target:(id<FYRecognitionTimerTarget>)target {
    // Preserve the native target/override and the original default runloop mode.
    self.timer = [NSTimer scheduledTimerWithTimeInterval:interval target:target
        selector:@selector(timerFired:) userInfo:nil repeats:YES];
}
- (void)restartTimerWithInterval:(NSTimeInterval)interval target:(id<FYRecognitionTimerTarget>)target {
    if (!self.running) return;
    [self.timer invalidate];
    [self scheduleTimerWithInterval:interval target:target];
}
- (void)invalidateTimer { [self.timer invalidate]; self.timer = nil; }
@end
