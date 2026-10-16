#import "FYOCRImageGeometry.h"
#import <math.h>

@implementation FYOCRImageGeometry
+ (NSString *)recognizeEnlargedImage:(CGImageRef)image visionRegion:(CGRect)region
    recognizer:(NSString *(^)(CGImageRef, NSArray<OCRTextItem *> **, NSError **))recognizer
    cropScope:(FYOCRCropScopePerform)cropScope blocks:(NSArray<OCRTextItem *> **)outBlocks error:(NSError **)error {
    CGRect crop=CGRectZero;
    CGImageRef scaled=[self copyEnlargedImage:image visionRegion:region pixelCrop:&crop];
    if (!scaled) return @"";
    __block NSArray<OCRTextItem *> *localBlocks=nil;
    __block NSString *text;
    __block NSError *cropError=error ? *error : nil;
    BOOL wantsError=error != NULL;
    void (^work)(void) = ^{ text=recognizer(scaled,&localBlocks,wantsError ? &cropError : NULL); };
    if (cropScope) cropScope(crop, CGSizeMake(CGImageGetWidth(image),CGImageGetHeight(image)), work); else work();
    if (error) *error=cropError;
    [self remapItems:localBlocks fromPixelCrop:crop imageSize:CGSizeMake(CGImageGetWidth(image),CGImageGetHeight(image))];
    if (outBlocks) *outBlocks=localBlocks;
    CGImageRelease(scaled);
    return text;
}

+ (CGImageRef)copyEnlargedImage:(CGImageRef)image visionRegion:(CGRect)region pixelCrop:(CGRect *)outCrop {
    size_t imageWidth = CGImageGetWidth(image);
    size_t imageHeight = CGImageGetHeight(image);
    if (imageWidth < 2 || imageHeight < 2) { return NULL; }

    // Region and OCR boxes use Vision's bottom-left origin; CGImage cropping
    // uses the top-left origin. Convert both the crop and its returned boxes.
    CGRect crop = CGRectMake(floor(region.origin.x * imageWidth),
                             floor((1.0 - region.origin.y - region.size.height) * imageHeight),
                             MAX((size_t)2, floor(region.size.width * imageWidth)),
                             MAX((size_t)2, floor(region.size.height * imageHeight)));
    crop = CGRectIntersection(crop, CGRectMake(0, 0, imageWidth, imageHeight));
    if (crop.size.width < 2 || crop.size.height < 2) { return NULL; }

    CGImageRef cropped = CGImageCreateWithImageInRect(image, crop);
    if (!cropped) { return NULL; }

    // 放大 2 倍，但对最长边设硬上限：超过约 1800px 之后 OCR 精度基本不再提升，
    // 耗时却随像素数线性增长 —— 之前上限 4000 会跑出 3000x950 这种巨图，一轮好几秒。
    size_t scaledWidth = MIN((size_t)(crop.size.width * 2.0), (size_t)1800);
    size_t scaledHeight = MIN((size_t)(crop.size.height * 2.0), (size_t)1800);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, scaledWidth, scaledHeight, 8, 0, space,
                                                 kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) {
        CGImageRelease(cropped);
        return NULL;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, scaledWidth, scaledHeight), cropped);
    CGImageRef scaled = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGImageRelease(cropped);
    if (!scaled) { return NULL; }

    if (outCrop) { *outCrop = crop; }
    return scaled;
}

+ (void)remapItems:(NSArray<OCRTextItem *> *)items fromPixelCrop:(CGRect)crop imageSize:(CGSize)imageSize {
    CGFloat baseX = crop.origin.x / imageSize.width, baseY = 1.0 - CGRectGetMaxY(crop) / imageSize.height;
    CGFloat scaleX = crop.size.width / imageSize.width, scaleY = crop.size.height / imageSize.height;
    for (OCRTextItem *block in items) {
        CGRect b = block.boundingBox;
        block.boundingBox = CGRectMake(baseX + b.origin.x * scaleX, baseY + b.origin.y * scaleY,
                                       b.size.width * scaleX, b.size.height * scaleY);
        CGRect last = block.lastLineBox;
        if (!CGRectIsEmpty(last)) {
            block.lastLineBox = CGRectMake(baseX + last.origin.x * scaleX, baseY + last.origin.y * scaleY,
                                          last.size.width * scaleX, last.size.height * scaleY);
        }
        if (block.lineBoxes.count > 0) {
            NSMutableArray<NSValue *> *mapped = [NSMutableArray arrayWithCapacity:block.lineBoxes.count];
            for (NSValue *value in block.lineBoxes) {
                CGRect line = value.rectValue;
                if (!CGRectIsEmpty(line)) {
                    line = CGRectMake(baseX + line.origin.x * scaleX, baseY + line.origin.y * scaleY,
                                      line.size.width * scaleX, line.size.height * scaleY);
                }
                [mapped addObject:[NSValue valueWithRect:line]];
            }
            block.lineBoxes = mapped;
        }
    }
}

+ (NSArray<OCRTextItem *> *)recognizeImage:(CGImageRef)image topLeftScope:(CGRect)scope
    recognizer:(NSArray<OCRTextItem *> *(^)(CGImageRef cropped, NSError **error))recognizer cropScope:(FYOCRCropScopePerform)cropScope error:(NSError **)error {
    if (CGRectEqualToRect(scope, CGRectMake(0,0,1,1))) return recognizer(image,error);
    if (!image || !isfinite(scope.origin.x) || !isfinite(scope.origin.y) ||
        !isfinite(scope.size.width) || !isfinite(scope.size.height) || scope.size.width<=0 || scope.size.height<=0) return @[];
    CGRect bounded=CGRectIntersection(scope,CGRectMake(0,0,1,1));
    if (CGRectIsNull(bounded) || CGRectIsEmpty(bounded)) return @[];
    CGSize size=CGSizeMake(CGImageGetWidth(image),CGImageGetHeight(image));
    CGRect crop=CGRectIntersection(CGRectIntegral(CGRectMake(bounded.origin.x*size.width,bounded.origin.y*size.height,
        bounded.size.width*size.width,bounded.size.height*size.height)),CGRectMake(0,0,size.width,size.height));
    CGImageRef cropped=CGImageCreateWithImageInRect(image,crop);
    if (!cropped) {
        if (error) *error=[NSError errorWithDomain:@"LiveCaptionTranslator" code:901 userInfo:@{NSLocalizedDescriptionKey:@"无法读取手动识别区域。"}];
        return @[];
    }
    __block NSArray<OCRTextItem *> *items;
    __block NSError *cropError=error ? *error : nil;
    BOOL wantsError=error != NULL;
    if (cropScope) cropScope(crop, size, ^{ items=recognizer(cropped,wantsError ? &cropError : NULL); }); else (^{ items=recognizer(cropped,wantsError ? &cropError : NULL); })();
    if (error) *error=cropError;
    CGImageRelease(cropped);
    [self remapItems:items fromPixelCrop:crop imageSize:size];
    return items;
}
@end
