#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@interface FYInlineBlockSnapshot : NSObject
@property(nonatomic, copy) NSString *blockID;
@property(nonatomic, copy) NSString *sourceText;
@property(nonatomic, copy) NSString *translation;
@property(nonatomic, copy) NSArray<NSValue *> *lineBoxes;
@property(nonatomic) NSInteger inputSource;
@property(nonatomic) NSUInteger inputEpoch;
@property(nonatomic, copy) NSString *sentenceID;
@property(nonatomic) NSInteger version;
@end
