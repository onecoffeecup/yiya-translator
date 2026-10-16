#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// Value snapshot: no controls, device handles or mutable application context.
typedef struct {
    BOOL running;
    BOOL visible;
    BOOL hasSurface;
    BOOL captureCard;
    NSInteger generation;
    NSUInteger sessionEpoch;
    uint32_t windowID;
    uint64_t latestFrameIndex;
    NSTimeInterval frameInterval;
} FYLivePreviewSnapshot;

typedef CGImageRef _Nullable (^FYPreviewFrameCopy)(uint64_t *actualIndex);

// A single queued capture retains only the resource/receiver needed for that
// work. Epoch reads refer to this original resource, even if the source changes.
@interface FYPreviewFrameLease : NSObject
- (instancetype)initWithFrameCopy:(FYPreviewFrameCopy)frameCopy
                    sessionEpoch:(NSUInteger (^)(void))sessionEpoch;
- (nullable CGImageRef)copyFrameWithIndex:(uint64_t *)actualIndex CF_RETURNS_RETAINED;
- (NSUInteger)currentSessionEpoch;
@end

@protocol FYLivePreviewSource <NSObject>
- (FYLivePreviewSnapshot)previewSnapshot;
- (FYPreviewFrameLease *)previewFrameLeaseForSnapshot:(FYLivePreviewSnapshot)snapshot;
- (void)refreshPreviewVisibility;
- (void)presentPreviewImage:(CGImageRef)image;
@end

// Keeps the existing native action and subclass override as the timer entry.
@protocol FYLivePreviewTimerTarget <NSObject>
- (void)previewTimerFired:(nullable NSTimer *)timer;
@end

// All state access and scheduling calls are confined to the main thread.
// Construction starts no timer, window, capture session or network operation.
@interface FYLivePreviewScheduler : NSObject
- (instancetype)initWithSource:(id<FYLivePreviewSource>)source queue:(dispatch_queue_t)queue;
@property(nonatomic, weak, readonly) id<FYLivePreviewSource> source;
@property(nonatomic, strong, nullable) NSTimer *timer;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic) BOOL inFlight;
@property(nonatomic) NSUInteger requestSerial;
@property(nonatomic) NSUInteger renderSerial;
@property(nonatomic) uint64_t lastCaptureFrameIndex;
@property(nonatomic, strong, nullable) NSDate *lastRenderDate;
- (void)invalidateResults;
- (void)restartWithSnapshot:(FYLivePreviewSnapshot)snapshot timerTarget:(id<FYLivePreviewTimerTarget>)target;
- (void)tick;
- (void)renderStoppedImage:(CGImageRef)image generation:(NSInteger)generation
                 delivery:(void (^)(CGImageRef image))delivery;
@end
NS_ASSUME_NONNULL_END
