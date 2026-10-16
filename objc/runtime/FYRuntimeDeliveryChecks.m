#import "FYRuntimeDeliveryChecks.h"

BOOL FYContentRevisionIsCurrent(NSUInteger submitted, NSUInteger current) { return submitted == current; }
BOOL FYInlinePlanIsCurrent(NSUInteger submittedRevision, NSUInteger currentRevision,
    NSUInteger submittedSerial, NSUInteger currentSerial) {
    return FYContentRevisionIsCurrent(submittedRevision, currentRevision) && submittedSerial == currentSerial;
}

NSString *FYInlineDeliveryDropReason(NSInteger generation, NSInteger currentGeneration,
    NSUInteger inputEpoch, NSUInteger currentInputEpoch, BOOL running, NSInteger mode, NSInteger currentMode) {
    if (generation != currentGeneration) return @"generation_changed";
    if (inputEpoch != currentInputEpoch) return @"input_session_changed";
    if (running && mode != currentMode) return @"mode_changed";
    return nil;
}

BOOL FYGeometryDeliveryIsStale(NSInteger generation, NSInteger currentGeneration, uint32_t targetID, uint32_t currentTargetID) {
    return generation != currentGeneration || (targetID != 0 && targetID != currentTargetID);
}

void FYDeliverTranslationOnMain(NSInteger requestGeneration, NSInteger (^currentGeneration)(void),
    NSString *translated, NSError *error, void (^completion)(NSString *, NSError *), void (^dropped)(void)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (requestGeneration != currentGeneration()) { if (dropped) { dropped(); } return; }
        completion(translated, error);
    });
}


@implementation FYRealtimeDeliveryTicket
- (instancetype)initWithGeneration:(NSInteger)generation windowID:(uint32_t)windowID inputEpoch:(NSUInteger)epoch mode:(NSInteger)mode {
    if ((self = [super init])) { _generation = generation; _windowID = windowID; _inputEpoch = epoch; _mode = mode; }
    return self;
}
- (NSString *)dropReasonWithSource:(id<FYRuntimeDeliverySource>)source {
    if (self.generation != source.deliveryGeneration) { return @"generation_changed"; }
    if (!source.deliveryIsRunning) { return @"stopped"; }
    if (self.windowID != source.deliveryWindowID) { return @"window_changed"; }
    if (self.inputEpoch != source.deliveryInputEpoch) { return @"input_session_changed"; }
    if (self.mode != source.deliveryMode) { return @"mode_changed"; }
    return nil;
}
@end

@implementation FYInlinePlacementDeliveryTicket
- (instancetype)initWithContentRevision:(NSUInteger)revision generation:(NSInteger)generation
    inputEpoch:(NSUInteger)epoch mode:(NSInteger)mode geometryGeneration:(NSInteger)geometry displayTarget:(uint32_t)target {
    if ((self = [super init])) {
        _contentRevision = revision; _generation = generation; _inputEpoch = epoch;
        _mode = mode; _geometryGeneration = geometry; _displayTarget = target;
    }
    return self;
}
- (NSString *)dropReasonWithSource:(id<FYInlinePlacementDeliverySource>)source {
    if (!FYContentRevisionIsCurrent(self.contentRevision, source.deliveryContentRevision)) { return @"content_changed"; }
    NSInteger generation = source.deliveryGeneration;
    NSUInteger epoch = source.deliveryInputEpoch;
    BOOL running = source.deliveryIsRunning;
    NSInteger currentMode = (self.generation == generation && self.inputEpoch == epoch && running) ? source.deliveryMode : self.mode;
    NSString *reason = FYInlineDeliveryDropReason(self.generation, generation, self.inputEpoch, epoch, running, self.mode, currentMode);
    if (reason) { return reason; }
    NSInteger geometry = source.deliveryGeometryGeneration;
    uint32_t target = (self.geometryGeneration == geometry && self.displayTarget != 0) ? source.deliveryWindowID : self.displayTarget;
    return FYGeometryDeliveryIsStale(self.geometryGeneration, geometry, self.displayTarget, target) ? @"geometry_changed" : nil;
}
@end
