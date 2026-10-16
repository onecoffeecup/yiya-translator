#pragma once
#import "FYOCRTextModels.h"
typedef void (^FYOCRCropScopePerform)(CGRect crop, CGSize size, void (^work)(void));
@interface FYOCRImageGeometry : NSObject
+ (NSArray<OCRTextItem *> *)recognizeImage:(CGImageRef)image topLeftScope:(CGRect)scope recognizer:(NSArray<OCRTextItem *> *(^)(CGImageRef,NSError **))recognizer cropScope:(FYOCRCropScopePerform)cropScope error:(NSError **)error;
+ (NSString *)recognizeEnlargedImage:(CGImageRef)image visionRegion:(CGRect)region recognizer:(NSString *(^)(CGImageRef,NSArray<OCRTextItem *> **,NSError **))recognizer cropScope:(FYOCRCropScopePerform)cropScope blocks:(NSArray<OCRTextItem *> **)blocks error:(NSError **)error;
+ (CGImageRef)copyEnlargedImage:(CGImageRef)image visionRegion:(CGRect)region pixelCrop:(CGRect *)crop CF_RETURNS_RETAINED;
+ (void)remapItems:(NSArray<OCRTextItem *> *)items fromPixelCrop:(CGRect)crop imageSize:(CGSize)imageSize;
@end
