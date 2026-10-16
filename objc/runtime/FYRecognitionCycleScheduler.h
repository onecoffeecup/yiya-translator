#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Canonical legacy predicate shared by capture checks and OCR scheduling.
FOUNDATION_EXPORT BOOL FYCaptureFrameNeedsRecognition(uint64_t latestIndex, uint64_t lastRecognizedIndex);

typedef NS_ENUM(NSInteger, FYRecognitionCycleKind) {
    FYRecognitionCycleRealtime,
    FYRecognitionCycleManual,
};

// These four lazy reads refer to the original receiver. The bounded lease is
// retained only by its asynchronous cycle, never by the scheduler or identity.
@interface FYRecognitionCycleLease : NSObject
- (instancetype)initWithGeneration:(NSInteger (^)(void))generation
                           running:(BOOL (^)(void))running
                          windowID:(uint32_t (^)(void))windowID
                        inputEpoch:(NSUInteger (^)(void))inputEpoch;
- (NSInteger)currentGeneration;
- (BOOL)isRunning;
- (uint32_t)currentWindowID;
- (NSUInteger)currentInputEpoch;
@end

@interface FYRecognitionCycleIdentity : NSObject
- (instancetype)initWithGeneration:(NSInteger)generation windowID:(uint32_t)windowID
                         inputEpoch:(NSUInteger)inputEpoch kind:(FYRecognitionCycleKind)kind;
@property(nonatomic, readonly) NSInteger generation;
@property(nonatomic, readonly) uint32_t windowID;
@property(nonatomic, readonly) NSUInteger inputEpoch;
@property(nonatomic, readonly) FYRecognitionCycleKind kind;
// Capture delivery has no running guard, including for realtime cycles.
- (nullable NSString *)captureDropReasonWithLease:(FYRecognitionCycleLease *)lease;
// Only realtime OCR requires running. Manual OCR/HTTP is allowed while paused.
- (nullable NSString *)recognitionDropReasonWithLease:(FYRecognitionCycleLease *)lease;
@end

@protocol FYRecognitionTimerTarget <NSObject>
- (void)timerFired:(nullable NSTimer *)timer;
@end

// Main-thread state and scheduling; cold construction starts no work. Preview,
// HTTP tasks and content revisions have separate owners. No idle host reference.
@interface FYRecognitionCycleScheduler : NSObject
@property(nonatomic) BOOL running;
@property(nonatomic) BOOL inFlight;
@property(nonatomic, strong, nullable) NSTimer *timer;
@property(nonatomic) uint64_t lastRecognizedFrameIndex;
@property(nonatomic) NSInteger geometryGeneration;
@property(nonatomic) uint32_t displayTargetWindowID;
- (void)beginCycle;
- (void)finishCurrentCycle;
- (void)finishCycle:(FYRecognitionCycleIdentity *)cycle lease:(FYRecognitionCycleLease *)lease;
- (BOOL)needsCaptureFrame:(uint64_t)latestIndex;
- (void)scheduleTimerWithInterval:(NSTimeInterval)interval target:(id<FYRecognitionTimerTarget>)target;
- (void)restartTimerWithInterval:(NSTimeInterval)interval target:(id<FYRecognitionTimerTarget>)target;
- (void)invalidateTimer;
@end
NS_ASSUME_NONNULL_END
