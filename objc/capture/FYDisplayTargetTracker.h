#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
// Sole owner of existing display target / geometry and two probe dates.
// Synchronous on the caller's original serial context; no host or UI retained.
@interface FYDisplayTargetTracker : NSObject
@property(nonatomic) BOOL displayTargetResolved;
@property(nonatomic) BOOL displayTargetAmbiguous;
@property(nonatomic) uint32_t resolvedDisplayTargetID;
@property(nonatomic, strong) NSDate *lastDisplayTargetProbeDate;
@property(nonatomic, strong) NSDate *lastWindowRecoveryAttemptDate;
@property(nonatomic) NSInteger geometryGeneration;
@property(nonatomic, copy) NSString *lastDisplayGeometryToken;
- (BOOL)beginProbeAt:(NSDate *)now force:(BOOL)force;
- (BOOL)beginRecoveryAt:(NSDate *)now;
- (BOOL)acceptTargetID:(uint32_t)resolved ambiguous:(BOOL)ambiguous;
- (void)advanceAmbiguousGeometry;
- (BOOL)recordPlacement:(BOOL)hasPlacement rect:(CGRect)placement targetID:(uint32_t)targetID targetChanged:(BOOL)targetChanged;
- (uint32_t)windowIDUsingSelection:(uint32_t (^)(void))selectedWindow;
@end
