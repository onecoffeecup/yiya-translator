#import "FYPreviewImage.h"
#import <Foundation/Foundation.h>
#import <math.h>

CGImageRef FYCopyPreviewImage(CGImageRef source) {
    if (!source) { return NULL; }
    size_t sourceWidth = CGImageGetWidth(source), sourceHeight = CGImageGetHeight(source);
    double scale = MIN(1.0, 2560.0 / MAX((size_t)1, MAX(sourceWidth, sourceHeight)));
    // Retain immutable native-size frames instead of allocating and redrawing
    // another full-frame bitmap on every preview tick.
    if (scale >= 1.0) { return CGImageRetain(source); }
    size_t width = MAX((size_t)1, (size_t)llround(sourceWidth * scale));
    size_t height = MAX((size_t)1, (size_t)llround(sourceHeight * scale));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (!context) { return NULL; }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), source);
    CGImageRef result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return result;
}
