#import "capture/FYCaptureMapping.h"
#import "capture/FYCoordinateConversions.h"
#import "runtime/FYRuntimeDeliveryChecks.h"

@interface FYGeometryManager : NSObject
+ (NSDictionary *)captureMappingForRect:(NSRect)rect windowFrame:(NSRect)frame videoAspect:(CGFloat)aspect
                                deviceID:(NSString *)deviceID source:(NSString *)source
                              confidence:(CGFloat)confidence version:(NSInteger)version;
// Unrounded reconstruction; coordinator retains size validation and integral rounding.
+ (NSRect)captureMappingRect:(NSDictionary *)entry windowFrame:(NSRect)frame;
// Capture mapping policy only; nil reason means valid. No device/frame acquisition.
+ (NSString *)captureMappingWindowReason:(NSDictionary *)entry windowFrame:(NSRect)frame;
+ (NSString *)captureMappingInputReason:(NSDictionary *)entry frameSize:(CGSize)size
                         hasFrameSize:(BOOL)hasSize deviceID:(NSString *)deviceID;
+ (BOOL)captureMappingScoreIsStale:(double)score unavailableValue:(double)unavailable;
// Top-left normalized capture region, floor/minimum-one/intersection semantics.
+ (CGRect)pixelCropForTopLeftRegion:(CGRect)region imageWidth:(size_t)width imageHeight:(size_t)height;
+ (NSRect)appKitFrameForQuartzBounds:(CGRect)bounds mainScreenTop:(CGFloat)top;
+ (NSRect)frameForNormalizedBox:(CGRect)box inViewport:(NSRect)viewport;
+ (NSRect)frameForTopLeftNormalizedBox:(CGRect)box inViewport:(NSRect)viewport;
+ (CGRect)quartzRectFromSelection:(CGRect)selection panelFrame:(NSRect)panelFrame mainScreenTop:(CGFloat)top;
@end
