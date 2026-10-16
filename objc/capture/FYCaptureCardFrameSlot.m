#import "FYCaptureCardFrameSlot.h"
@implementation FYCaptureCardFrameSlot {
    CGImageRef _frame;
    NSTimeInterval _lastStoredTime;
    uint64_t _latestIndex;
    uint64_t _storedCount;
    uint64_t _skippedCount;
}

- (instancetype)init {
    if ((self = [super init])) { _minimumInterval = FYCaptureCardPreviewFrameInterval; }
    return self;
}

@synthesize minimumInterval = _minimumInterval;
- (NSTimeInterval)minimumInterval { @synchronized(self) { return _minimumInterval; } }
- (void)setMinimumInterval:(NSTimeInterval)value { @synchronized(self) { _minimumInterval=value; } }

- (void)dealloc {
    if (_frame) { CGImageRelease(_frame); }
}

- (BOOL)shouldStoreFrameAtTime:(NSTimeInterval)now {
    @synchronized(self) {
        // Small callback jitter must not drop every other nominal 30 Hz frame.
        NSTimeInterval tolerance = MIN(0.001, MAX(0, _minimumInterval) * 0.05);
        if (_frame && _minimumInterval > 0 && (now - _lastStoredTime) < _minimumInterval - tolerance) {
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

- (CGImageRef)copyLatestFrame { return [self copyLatestFrameWithIndex:NULL]; }
- (CGImageRef)copyLatestFrameWithIndex:(uint64_t *)index {
    @synchronized(self) {
        if (index) *index=_frame ? _latestIndex : 0;
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
