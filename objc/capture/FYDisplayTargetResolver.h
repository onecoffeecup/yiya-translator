#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
// Called synchronously in the original order; never retained by the resolver.
@protocol FYDisplayTargetGeometry <NSObject>
- (CGRect)displayBoundsContainingWindowInfo:(NSDictionary *)info;
- (CGRect)mainDisplayBounds;
- (CGFloat)screenCoverageForBounds:(CGRect)bounds;
- (NSArray<NSDictionary *> *)strongestDisplayTargetCandidates:(NSArray<NSDictionary *> *)candidates;
@end
@interface FYDisplayTargetResolver : NSObject
+ (NSArray<NSDictionary *> *)strongestDisplayTargetCandidates:(NSArray<NSDictionary *> *)candidates;
+ (uint32_t)resolveWindowList:(NSArray<NSDictionary *> *)windowList selectedID:(uint32_t)selected ownerPID:(pid_t)ownerPID
                   geometry:(id<FYDisplayTargetGeometry>)geometry ambiguous:(BOOL *)ambiguous note:(NSString **)note;
@end
