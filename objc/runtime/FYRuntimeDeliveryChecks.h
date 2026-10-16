#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL FYContentRevisionIsCurrent(NSUInteger submitted, NSUInteger current);
FOUNDATION_EXPORT BOOL FYInlinePlanIsCurrent(NSUInteger submittedRevision, NSUInteger currentRevision,
    NSUInteger submittedSerial, NSUInteger currentSerial);
// Main-queue delivery preserves the original generation check and callback lifetime.
FOUNDATION_EXPORT void FYDeliverTranslationOnMain(NSInteger requestGeneration, NSInteger (^currentGeneration)(void),
    NSString * _Nullable translated, NSError * _Nullable error,
    void (^completion)(NSString * _Nullable, NSError * _Nullable), void (^ _Nullable dropped)(void));
// Original compatibility functions; their implementation lives only here.
FOUNDATION_EXPORT NSString * _Nullable FYInlineDeliveryDropReason(NSInteger generation, NSInteger currentGeneration,
    NSUInteger inputEpoch, NSUInteger currentInputEpoch, BOOL running, NSInteger mode, NSInteger currentMode);
FOUNDATION_EXPORT BOOL FYGeometryDeliveryIsStale(NSInteger generation, NSInteger currentGeneration,
    uint32_t targetID, uint32_t currentTargetID);

// Lazy primitive reads retain the original short-circuit policy; this is not a
// mutable application context. A ticket never stores or retains this source.
@protocol FYRuntimeDeliverySource <NSObject>
- (NSInteger)deliveryGeneration;
- (BOOL)deliveryIsRunning;
- (uint32_t)deliveryWindowID;
- (NSUInteger)deliveryInputEpoch;
- (NSInteger)deliveryMode;
@end
@protocol FYInlinePlacementDeliverySource <FYRuntimeDeliverySource>
- (NSUInteger)deliveryContentRevision;
- (NSInteger)deliveryGeometryGeneration;
@end

@interface FYRealtimeDeliveryTicket : NSObject
- (instancetype)initWithGeneration:(NSInteger)generation windowID:(uint32_t)windowID
    inputEpoch:(NSUInteger)epoch mode:(NSInteger)mode;
@property(nonatomic, readonly) NSInteger generation;
@property(nonatomic, readonly) uint32_t windowID;
@property(nonatomic, readonly) NSUInteger inputEpoch;
@property(nonatomic, readonly) NSInteger mode;
- (nullable NSString *)dropReasonWithSource:(id<FYRuntimeDeliverySource>)source;
@end

// Placement also supports an explicit single-frame action while paused.
// It preserves the original running-dependent mode guard, not the realtime stop guard.
@interface FYInlinePlacementDeliveryTicket : NSObject
- (instancetype)initWithContentRevision:(NSUInteger)revision generation:(NSInteger)generation
    inputEpoch:(NSUInteger)epoch mode:(NSInteger)mode geometryGeneration:(NSInteger)geometry
    displayTarget:(uint32_t)target;
@property(nonatomic, readonly) NSUInteger contentRevision;
@property(nonatomic, readonly) NSInteger generation;
@property(nonatomic, readonly) NSUInteger inputEpoch;
@property(nonatomic, readonly) NSInteger mode;
@property(nonatomic, readonly) NSInteger geometryGeneration;
@property(nonatomic, readonly) uint32_t displayTarget;
- (nullable NSString *)dropReasonWithSource:(id<FYInlinePlacementDeliverySource>)source;
@end
NS_ASSUME_NONNULL_END
