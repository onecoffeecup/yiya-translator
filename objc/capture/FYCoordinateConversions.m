#import "FYCoordinateConversions.h"
#import <math.h>
@implementation FYCoordinateConversions
+ (CGRect)pixelCropForTopLeftRegion:(CGRect)region imageWidth:(size_t)width imageHeight:(size_t)height {
    CGRect crop = CGRectMake(floor(region.origin.x * width), floor(region.origin.y * height),
                             MAX(1, floor(region.size.width * width)), MAX(1, floor(region.size.height * height)));
    return CGRectIntersection(crop, CGRectMake(0, 0, width, height));
}

+ (NSRect)appKitFrameForQuartzBounds:(CGRect)bounds mainScreenTop:(CGFloat)top {
    return NSMakeRect(bounds.origin.x, top - bounds.origin.y - bounds.size.height, bounds.size.width, bounds.size.height);
}

+ (NSRect)frameForNormalizedBox:(CGRect)box inViewport:(NSRect)viewport {
    return NSIntegralRect(NSMakeRect(NSMinX(viewport) + box.origin.x * NSWidth(viewport),
                                    NSMinY(viewport) + box.origin.y * NSHeight(viewport),
                                    box.size.width * NSWidth(viewport), box.size.height * NSHeight(viewport)));
}

+ (NSRect)frameForTopLeftNormalizedBox:(CGRect)box inViewport:(NSRect)viewport {
    return NSIntegralRect(NSMakeRect(NSMinX(viewport) + box.origin.x * NSWidth(viewport),
                                    NSMaxY(viewport) - (box.origin.y + box.size.height) * NSHeight(viewport),
                                    box.size.width * NSWidth(viewport), box.size.height * NSHeight(viewport)));
}

+ (CGRect)quartzRectFromSelection:(CGRect)selection panelFrame:(NSRect)panelFrame mainScreenTop:(CGFloat)top {
    return CGRectMake(panelFrame.origin.x + selection.origin.x, top - NSMaxY(panelFrame) + selection.origin.y,
                      selection.size.width, selection.size.height);
}
@end
