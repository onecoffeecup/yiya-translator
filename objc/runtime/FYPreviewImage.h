#pragma once
#import <CoreGraphics/CoreGraphics.h>

// Returned image is owned by the caller; native-size immutable images retain
// their original pixels, large images use the existing 2560-pixel bound.
CGImageRef FYCopyPreviewImage(CGImageRef source) CF_RETURNS_RETAINED;
