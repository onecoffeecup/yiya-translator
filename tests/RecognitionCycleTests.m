#import "FYRecognitionCycleScheduler.h"
#import <objc/runtime.h>

static NSUInteger checks;
static void Check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(2); }
}
@interface CycleSource : NSObject
@property(nonatomic) NSInteger generation;
@property(nonatomic) uint32_t windowID;
@property(nonatomic) NSUInteger epoch;
@property(nonatomic) BOOL running;
@property(nonatomic, strong) NSMutableArray<NSString *> *reads;
@end
@implementation CycleSource
@end
static FYRecognitionCycleLease *Lease(CycleSource *source) {
    return [[FYRecognitionCycleLease alloc] initWithGeneration:^{ [source.reads addObject:@"generation"]; return source.generation; }
        running:^{ [source.reads addObject:@"running"]; return source.running; }
        windowID:^{ [source.reads addObject:@"window"]; return source.windowID; }
        inputEpoch:^{ [source.reads addObject:@"epoch"]; return source.epoch; }];
}
static FYRecognitionCycleIdentity *Cycle(FYRecognitionCycleKind kind) {
    return [[FYRecognitionCycleIdentity alloc] initWithGeneration:7 windowID:42 inputEpoch:3 kind:kind];
}
@interface NativeTarget : NSObject <FYRecognitionTimerTarget>
@property(nonatomic) NSUInteger calls;
@property(nonatomic, strong) NSTimer *seenTimer;
@end
@implementation NativeTarget
- (void)timerFired:(NSTimer *)timer { self.calls++; self.seenTimer = timer; }
@end

static void CheckGates(void) {
    for (NSUInteger kind = 0; kind < 2; kind++) {
        FYRecognitionCycleIdentity *cycle = Cycle(kind);
        Check(cycle.generation == 7 && cycle.windowID == 42 && cycle.inputEpoch == 3 && cycle.kind == (FYRecognitionCycleKind)kind,
              @"submitted identity preserves all scalar values");
        for (NSString *setter in @[@"setGeneration:", @"setWindowID:", @"setInputEpoch:", @"setKind:"]) {
            Check(![cycle respondsToSelector:NSSelectorFromString(setter)], @"cycle identity has no mutable API");
        }
        for (NSUInteger phase = 0; phase < 2; phase++) {
            for (NSUInteger change = 0; change < 5; change++) {
                CycleSource *source = [CycleSource new]; source.generation = 7; source.windowID = 42;
                source.epoch = 3; source.running = YES; source.reads = [NSMutableArray new];
                if (change == 1) source.generation++;
                if (change == 2) source.running = NO;
                if (change == 3) source.windowID++;
                if (change == 4) source.epoch++;
                BOOL runningGuard = phase == 1 && kind == FYRecognitionCycleRealtime;
                NSString *expected = change == 1 ? @"generation_changed" :
                    change == 2 && runningGuard ? @"stopped" :
                    change == 3 ? @"window_changed" : change == 4 ? @"input_session_changed" : nil;
                FYRecognitionCycleLease *lease = Lease(source);
                Check(source.reads.count == 0, @"lease construction performs no host reads");
                NSString *reason = phase ? [cycle recognitionDropReasonWithLease:lease] : [cycle captureDropReasonWithLease:lease];
                Check(reason == expected || [reason isEqual:expected], @"capture and recognition preserve realtime/manual validity");
                NSMutableArray *reads = [NSMutableArray arrayWithObject:@"generation"];
                if (change != 1) {
                    if (runningGuard) [reads addObject:@"running"];
                    if (!(change == 2 && runningGuard)) {
                        [reads addObject:@"window"];
                        if (change != 3) [reads addObject:@"epoch"];
                    }
                }
                Check([source.reads isEqual:reads], @"gates preserve lazy read order and short circuit");
            }
        }
    }
}
static void CheckBusyAndFrames(void) {
    FYRecognitionCycleScheduler *scheduler = [FYRecognitionCycleScheduler new];
    Check(!scheduler.running && !scheduler.inFlight && !scheduler.timer && !scheduler.lastRecognizedFrameIndex,
          @"cold owner has no work or timer");
    CycleSource *source = [CycleSource new]; source.generation = 7; source.reads = [NSMutableArray new];
    FYRecognitionCycleLease *lease = Lease(source);
    FYRecognitionCycleIdentity *cycle = Cycle(FYRecognitionCycleRealtime);
    [scheduler beginCycle]; source.generation = 8;
    [scheduler finishCycle:cycle lease:lease];
    Check(scheduler.inFlight, @"old callback cannot release the restarted OCR slot");
    source.generation = 7; source.windowID = 99; source.epoch = 9; source.running = NO;
    [scheduler finishCycle:cycle lease:lease];
    Check(!scheduler.inFlight, @"same generation releases its slot even after source/window/stop change");
    Check([source.reads isEqual:@[@"generation", @"generation"]], @"release consults only generation");
    [scheduler beginCycle]; [scheduler finishCurrentCycle];
    Check(!scheduler.inFlight, @"explicit stop or rejected capture can clear the current slot");
    scheduler.lastRecognizedFrameIndex = 9;
    Check(![scheduler needsCaptureFrame:0], @"missing frame never enters OCR");
    Check(![scheduler needsCaptureFrame:9], @"repeated frame never enters OCR");
    Check([scheduler needsCaptureFrame:10], @"new frame enters OCR");
    Check([scheduler needsCaptureFrame:1], @"nonzero rewound frame preserves acceptance");
    scheduler.lastRecognizedFrameIndex = 0;
    Check([scheduler needsCaptureFrame:9], @"input reset allows its first available frame");
}
static void CheckTimerAndLifetime(void) {
    FYRecognitionCycleScheduler *scheduler = [FYRecognitionCycleScheduler new];
    NativeTarget *target = [NativeTarget new];
    [scheduler restartTimerWithInterval:.005 target:target];
    Check(!scheduler.timer && !target.calls, @"paused restart starts no timer");
    scheduler.running = YES; [scheduler beginCycle];
    [scheduler scheduleTimerWithInterval:.005 target:target];
    NSTimer *oldTimer = scheduler.timer;
    Check(oldTimer.valid && oldTimer.timeInterval == .005 && target.calls == 0,
          @"scheduling preserves requested cadence with no implicit immediate tick");
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1];
    while (!target.calls && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    }
    Check(target.calls && target.seenTimer == scheduler.timer, @"real runloop dispatch invokes original native receiver");
    [scheduler restartTimerWithInterval:.03 target:target];
    Check(!oldTimer.valid && scheduler.timer.valid && scheduler.timer != oldTimer && scheduler.timer.timeInterval == .03,
          @"mode restart replaces and invalidates only the recognition timer");
    Check(scheduler.inFlight, @"timer replacement does not release OCR busy ownership");
    [scheduler invalidateTimer];
    Check(!scheduler.timer && scheduler.inFlight && scheduler.running, @"timer invalidation preserves explicit state transition ordering");
    __weak NativeTarget *releasedTarget;
    @autoreleasepool {
        NativeTarget *local = [NativeTarget new]; releasedTarget = local;
        [scheduler scheduleTimerWithInterval:10 target:local];
    }
    Check(releasedTarget != nil, @"active native timer keeps its receiver alive");
    [scheduler invalidateTimer];
    Check(releasedTarget == nil, @"invalidated timer releases its receiver without idle owner retention");
    __weak CycleSource *releasedSource;
    FYRecognitionCycleLease *held;
    @autoreleasepool {
        CycleSource *local = [CycleSource new]; local.generation = 7; local.reads = [NSMutableArray new];
        releasedSource = local; held = Lease(local);
    }
    Check(releasedSource && [held currentGeneration] == 7, @"queued lease keeps the original receiver alive");
    held = nil;
    Check(!releasedSource, @"completed lease releases the receiver while scheduler and identity remain");
}
int main(void) {
    @autoreleasepool { CheckGates(); CheckBusyAndFrames(); CheckTimerAndLifetime(); }
    printf("PASS recognition cycle: %lu checks; Foundation only, native timer, stale release and lease lifetime\n", (unsigned long)checks);
    return 0;
}
