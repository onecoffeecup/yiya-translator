#pragma once
#import "FYOCRTextModels.h"
typedef void (^FYOCRVisionRawObserver)(NSArray<OCRTextItem *> *raw);
@interface FYOCRVisionEngine : NSObject
@property(nonatomic, copy) void (^configurationObserver)(BOOL fastOCR, NSInteger languageSegment, size_t width, size_t height, CGFloat minimumHeight);
- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment rawObserver:(FYOCRVisionRawObserver)rawObserver error:(NSError **)error;
@end
