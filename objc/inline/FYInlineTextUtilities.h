#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
NS_ASSUME_NONNULL_BEGIN
// Internal helpers shared by grouping and layout, with a single implementation.
NSString *FYInlineTrim(NSString * _Nullable value);
NSString *FYInlineNormalize(NSString * _Nullable value);
CGFloat FYInlineClamp(CGFloat value, CGFloat low, CGFloat high);
BOOL FYInlineRectContainsRect(CGRect outer, CGRect inner);
CGFloat FYInlineMedian(NSArray<NSNumber *> * _Nullable values);
BOOL FYInlineLineEndsSentence(NSString * _Nullable text);
BOOL FYInlineHasSentencePunctuation(NSString * _Nullable text);

FOUNDATION_EXPORT NSString *FYInlineNormalizeTranslationParagraphs(NSString * _Nullable text);
NS_ASSUME_NONNULL_END
