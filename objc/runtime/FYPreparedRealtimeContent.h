#pragma once
#import <Foundation/Foundation.h>
#import "../ocr/FYOCRTextModels.h"
// A synchronous preparation result, retaining the original local aliases.
@interface FYPreparedRealtimeContent : NSObject
- (instancetype)initWithNormalized:(NSString *)normalized items:(NSArray<OCRTextItem *> *)items mode:(NSInteger)mode;
@property(nonatomic, strong, readonly) NSString *normalized;
@property(nonatomic, strong, readonly) NSArray<OCRTextItem *> *items;
@property(nonatomic, readonly) NSInteger mode;
@end
