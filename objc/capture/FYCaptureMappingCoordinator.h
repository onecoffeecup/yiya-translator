#pragma once
#import "FYCaptureMapping.h"
NS_ASSUME_NONNULL_BEGIN
@interface FYCaptureMappingConfiguration : NSObject
@property(nonatomic, readonly) NSInteger version;
@property(nonatomic, readonly) double scoreUnavailable;
- (instancetype)initWithVersion:(NSInteger)version scoreUnavailable:(double)score;
@end
// Three narrow synchronous boundaries. Implementations never pass UI objects
// into the mapping algorithm; a per-operation native lease preserves self actions.
@protocol FYCaptureMappingWindow <NSObject>
- (BOOL)mappingWindowPresent;
- (uint32_t)mappingWindowID;
- (CGRect)mappingWindowFrame;
@end
@protocol FYCaptureMappingImages <NSObject>
- (BOOL)mappingLatestFrameSize:(CGSize *)size;
- (BOOL)mappingCanCaptureScreen;
- (CGImageRef _Nullable)copyMappingFrame CF_RETURNS_RETAINED;
- (CGImageRef _Nullable)copyMappingWindow CF_RETURNS_RETAINED;
@end
@protocol FYCaptureMappingPlacement <NSObject>
- (BOOL)mappingBuildGridsWithTemplate:(double * _Nullable * _Nullable)templ templateW:(size_t *)tw templateH:(size_t *)th
    scene:(double * _Nullable * _Nullable)scene sceneW:(size_t *)sw sceneH:(size_t *)sh aspect:(CGFloat *)aspect sceneWidth:(size_t)width reason:(NSString * _Nullable * _Nullable)reason;
- (BOOL)mappingEstimatedRect:(CGRect *)rect;
- (double)mappingScoreForEntry:(NSDictionary *)entry;
- (nullable NSString *)mappingSelectedDeviceID;
- (BOOL)mappingCaptureCardEnabled;
- (void)mappingStoreRect:(CGRect)rect windowFrame:(CGRect)frame aspect:(CGFloat)aspect deviceID:(nullable NSString *)device
    source:(NSString *)source confidence:(CGFloat)confidence windowID:(uint32_t)windowID;
- (void)mappingResetLayoutCache;
@end
@protocol FYCaptureMappingOperations <FYCaptureMappingWindow,FYCaptureMappingImages,FYCaptureMappingPlacement>
@end
typedef NS_ENUM(NSInteger,FYCaptureMappingEventKind){FYMappingPreferFit,FYMappingKeepCache,FYMappingMiss,FYMappingHit,FYMappingStaleVersion,FYMappingStalePicture};
typedef struct {
    FYCaptureMappingEventKind kind;
    double score,fitScore,otherScore;
    CGFloat aspect;
    CGRect windowFrame,rect;
    size_t gridWidth,gridHeight;
    uint32_t windowID;
} FYCaptureMappingEvent;
typedef void (^FYCaptureMappingObserver)(FYCaptureMappingEvent event);
@interface FYCaptureMappingCoordinator : NSObject
@property(nonatomic, strong, readonly) FYCaptureMappingConfiguration *configuration;
// Existing lazy owners. Compatibility setters may set nil; helper getters
// recreate on the original next access, retaining the existing entries identity.
@property(nonatomic, strong, nullable) FYCaptureMappingCache *captureMappingCache;
@property(nonatomic, strong, nullable) FYAutoLocateSchedule *autoLocateSchedule;
@property(nonatomic, strong, nullable) FYMappingValidationSchedule *mappingValidationSchedule;
- (instancetype)initWithConfiguration:(FYCaptureMappingConfiguration *)configuration;
- (FYCaptureMappingCache *)mappingCache;
- (FYAutoLocateSchedule *)locateSchedule;
- (FYMappingValidationSchedule *)validationSchedule;
- (BOOL)buildGridsWithTemplate:(double * _Nullable * _Nullable)templ templateW:(size_t *)tw templateH:(size_t *)th
    scene:(double * _Nullable * _Nullable)scene sceneW:(size_t *)sw sceneH:(size_t *)sh aspect:(CGFloat *)aspect
    sceneWidth:(size_t)width operations:(id<FYCaptureMappingOperations>)operations reason:(NSString * _Nullable * _Nullable)reason;
- (BOOL)autoDetectWithOperations:(id<FYCaptureMappingOperations>)operations reason:(NSString * _Nullable * _Nullable)reason observer:(nullable FYCaptureMappingObserver)observer;
- (double)scoreForEntry:(nullable NSDictionary *)entry operations:(id<FYCaptureMappingOperations>)operations;
- (void)storeRect:(CGRect)rect windowFrame:(CGRect)frame aspect:(CGFloat)aspect deviceID:(nullable NSString *)device
    source:(nullable NSString *)source confidence:(CGFloat)confidence windowID:(uint32_t)windowID operations:(id<FYCaptureMappingOperations>)operations;
- (void)clearWindowID:(uint32_t)windowID;
- (BOOL)estimatedRect:(CGRect *)rect operations:(id<FYCaptureMappingOperations>)operations;
- (BOOL)displayRect:(CGRect * _Nullable)rect operations:(id<FYCaptureMappingOperations>)operations reason:(NSString * _Nullable * _Nullable)reason observer:(nullable FYCaptureMappingObserver)observer;
@end
NS_ASSUME_NONNULL_END
