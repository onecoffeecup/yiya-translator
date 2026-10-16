#pragma once
#import "FYOCRTextModels.h"

// Caller-owned sampling buffer. Do not copy ownership; release once (repeat release is safe).
typedef struct {
    unsigned char *pixels;
    size_t width;
    size_t height;
    size_t bytesPerRow;
    CGContextRef context;
} FYOCRPixelBuffer;
FOUNDATION_EXPORT FYOCRPixelBuffer FYCreateOCRPixelBuffer(CGImageRef image);
FOUNDATION_EXPORT void FYReleaseOCRPixelBuffer(FYOCRPixelBuffer *buffer);
FOUNDATION_EXPORT BOOL FYOCRModalSurroundingsAreDimmer(unsigned char *pixels, size_t width, size_t height,
    size_t bytesPerRow, CGRect rect);
FOUNDATION_EXPORT BOOL FYOCRModalRectQualifiesForCropping(CGRect rect);

// RGBA pixel policies; dimensions/stride and exclusions are supplied explicitly.
FOUNDATION_EXPORT BOOL FYDetectBrightOCRContentRegion(const unsigned char *pixels, size_t width, size_t height,
    size_t bytesPerRow, CGRect *outNormalizedRect, BOOL *outDimmedColumns,
    const CGRect *exclusions, size_t exclusionCount);
FOUNDATION_EXPORT BOOL FYOCRBlockSitsOnBrightBackdrop(OCRTextItem *block, const unsigned char *pixels,
    size_t width, size_t height, size_t bytesPerRow);

@interface FYOCRPixelAnalysis : NSObject
+ (NSArray<OCRTextItem *> *)itemsByMarkingSpeakerLabels:(NSArray<OCRTextItem *> *)items inImage:(CGImageRef)image;
+ (NSArray<OCRTextItem *> *)items:(NSArray<OCRTextItem *> *)items scopedToModalInImage:(CGImageRef)image exclusions:(NSArray<NSValue *> *)exclusions;
+ (NSArray<OCRTextItem *> *)items:(NSArray<OCRTextItem *> *)items inModalRegion:(CGRect)region exclusions:(NSArray<NSValue *> *)exclusions;
@end
