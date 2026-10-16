#pragma once
#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
// Only synchronous font/cache state; never retained by the measurer.
@protocol FYInlineTextMeasurementState <NSObject>
@property(nonatomic, copy, readonly, nullable) NSFont * (^fontProvider)(CGFloat size, NSFontWeight weight);
@property(nonatomic, strong, readonly, nullable) NSMutableDictionary<NSArray *, NSNumber *> *layoutHeightCache;
@end
FOUNDATION_EXPORT NSDictionary *FYInlineTextAttributes(NSFont *font, NSParagraphStyle *style);
FOUNDATION_EXPORT NSRect FYInlineMeasureTextWithAttributes(NSString *text, NSSize size, NSDictionary *attributes);
FOUNDATION_EXPORT NSRect FYInlineMeasurePlainText(NSString *text, NSSize size, NSFont *font);
FOUNDATION_EXPORT CGFloat FYInlineCeiledFontLineHeight(NSFont *font);
@interface FYInlineTextMeasurer : NSObject <FYInlineTextMeasurementState>
@property(nonatomic, copy, nullable) NSFont * (^fontProvider)(CGFloat size, NSFontWeight weight);
@property(nonatomic, strong, nullable) NSMutableDictionary<NSArray *, NSNumber *> *layoutHeightCache;
- (NSFont *)fontOfSize:(CGFloat)size weight:(NSFontWeight)weight stateSource:(id<FYInlineTextMeasurementState>)source;
- (NSParagraphStyle *)paragraphStyleWithLineSpacing:(CGFloat)lineSpacing;
- (CGFloat)measuredHeightForText:(nullable NSString *)text width:(CGFloat)width font:(NSFont *)font
    style:(NSParagraphStyle *)style stateSource:(id<FYInlineTextMeasurementState>)source;
@end
NS_ASSUME_NONNULL_END
