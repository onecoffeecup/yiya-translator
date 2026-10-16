#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@interface FYCoordinateConversions : NSObject
+ (CGRect)pixelCropForTopLeftRegion:(CGRect)region imageWidth:(size_t)width imageHeight:(size_t)height;
+ (NSRect)appKitFrameForQuartzBounds:(CGRect)bounds mainScreenTop:(CGFloat)top;
+ (NSRect)frameForNormalizedBox:(CGRect)box inViewport:(NSRect)viewport;
+ (NSRect)frameForTopLeftNormalizedBox:(CGRect)box inViewport:(NSRect)viewport;
+ (CGRect)quartzRectFromSelection:(CGRect)selection panelFrame:(NSRect)panelFrame mainScreenTop:(CGFloat)top;
@end
