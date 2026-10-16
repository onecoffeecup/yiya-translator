#import "FYGeometryManager.h"
@implementation FYGeometryManager
+ (NSDictionary *)captureMappingForRect:(NSRect)rect windowFrame:(NSRect)frame videoAspect:(CGFloat)aspect deviceID:(NSString *)deviceID source:(NSString *)source confidence:(CGFloat)confidence version:(NSInteger)version { return [FYCaptureMappingAlgorithms captureMappingForRect:rect windowFrame:frame videoAspect:aspect deviceID:deviceID source:source confidence:confidence version:version]; }
+ (NSRect)captureMappingRect:(NSDictionary *)entry windowFrame:(NSRect)frame { return [FYCaptureMappingAlgorithms captureMappingRect:entry windowFrame:frame]; }
+ (NSString *)captureMappingWindowReason:(NSDictionary *)entry windowFrame:(NSRect)frame { return [FYCaptureMappingAlgorithms captureMappingWindowReason:entry windowFrame:frame]; }
+ (NSString *)captureMappingInputReason:(NSDictionary *)entry frameSize:(CGSize)size hasFrameSize:(BOOL)hasSize deviceID:(NSString *)deviceID { return [FYCaptureMappingAlgorithms captureMappingInputReason:entry frameSize:size hasFrameSize:hasSize deviceID:deviceID]; }
+ (BOOL)captureMappingScoreIsStale:(double)score unavailableValue:(double)unavailable { return [FYCaptureMappingAlgorithms captureMappingScoreIsStale:score unavailableValue:unavailable]; }
+ (CGRect)pixelCropForTopLeftRegion:(CGRect)region imageWidth:(size_t)width imageHeight:(size_t)height { return [FYCoordinateConversions pixelCropForTopLeftRegion:region imageWidth:width imageHeight:height]; }
+ (NSRect)appKitFrameForQuartzBounds:(CGRect)bounds mainScreenTop:(CGFloat)top { return [FYCoordinateConversions appKitFrameForQuartzBounds:bounds mainScreenTop:top]; }
+ (NSRect)frameForNormalizedBox:(CGRect)box inViewport:(NSRect)viewport { return [FYCoordinateConversions frameForNormalizedBox:box inViewport:viewport]; }
+ (NSRect)frameForTopLeftNormalizedBox:(CGRect)box inViewport:(NSRect)viewport { return [FYCoordinateConversions frameForTopLeftNormalizedBox:box inViewport:viewport]; }
+ (CGRect)quartzRectFromSelection:(CGRect)selection panelFrame:(NSRect)panelFrame mainScreenTop:(CGFloat)top { return [FYCoordinateConversions quartzRectFromSelection:selection panelFrame:panelFrame mainScreenTop:top]; }
@end
