#import "FYDisplayTargetTracker.h"
@implementation FYDisplayTargetTracker
- (BOOL)beginProbeAt:(NSDate *)now force:(BOOL)force {
    if (!force && self.lastDisplayTargetProbeDate &&
        [now timeIntervalSinceDate:self.lastDisplayTargetProbeDate] < 0.4) { return NO; }
    self.lastDisplayTargetProbeDate = now;
    return YES;
}
- (BOOL)beginRecoveryAt:(NSDate *)now {
    if (self.lastWindowRecoveryAttemptDate && [now timeIntervalSinceDate:self.lastWindowRecoveryAttemptDate] < 2.0) { return NO; }
    self.lastWindowRecoveryAttemptDate = now;
    return YES;
}
- (BOOL)acceptTargetID:(uint32_t)resolved ambiguous:(BOOL)ambiguous {
    BOOL targetChanged = !self.displayTargetResolved || self.resolvedDisplayTargetID != resolved ||
                         self.displayTargetAmbiguous != ambiguous;
    self.displayTargetResolved = YES;
    self.displayTargetAmbiguous = ambiguous;
    self.resolvedDisplayTargetID = resolved;
    return targetChanged;
}
- (void)advanceAmbiguousGeometry {
    self.geometryGeneration += 1;
    self.lastDisplayGeometryToken = nil;
}
- (BOOL)recordPlacement:(BOOL)hasPlacement rect:(CGRect)placement targetID:(uint32_t)targetID targetChanged:(BOOL)targetChanged {
    NSString *token = hasPlacement
        ? [NSString stringWithFormat:@"t=%u|vp=%.1f,%.1f,%.1f,%.1f", targetID,
           NSMinX(placement), NSMinY(placement), NSWidth(placement), NSHeight(placement)]
        : [NSString stringWithFormat:@"t=%u|none", targetID];
    if (!targetChanged && [self.lastDisplayGeometryToken isEqualToString:token]) { return NO; }
    self.lastDisplayGeometryToken = token;
    self.geometryGeneration += 1;
    return YES;
}
- (uint32_t)windowIDUsingSelection:(uint32_t (^)(void))selectedWindow {
    if (!self.displayTargetResolved) { return selectedWindow(); }
    if (self.displayTargetAmbiguous) { return 0; }
    return self.resolvedDisplayTargetID;
}
@end
