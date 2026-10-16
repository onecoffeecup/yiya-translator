#pragma once
#import "FYInlineLayoutCalculator.h"
NS_ASSUME_NONNULL_BEGIN
@interface FYInlineCandidate : NSObject
@property (nonatomic) FYInlineAnchor anchor;
@property (nonatomic) CGRect frame;
@property (nonatomic) CGFloat distance;
@property (nonatomic) NSInteger anchorRank;
@property (nonatomic) BOOL compact;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *rejection;   // 非空 = 有静态问题（严重程度见 hardRejection）
@property (nonatomic) CGFloat occlusionDepth;   // 与其它原文块的最大交叠厚度（pt）
@property (nonatomic) BOOL hardRejection;       // 超界/离原文过远：任何情况都不接受
@property (nonatomic) BOOL scrollable;
@property (nonatomic) CGFloat measuredContentHeight;
@property (nonatomic) CGFloat bodyViewportHeight;
@end


// Native actions preserve the concrete receiver and original helper overrides.
// Declarations carry no storage; only the native facade implements these actions.
@interface FYInlineLayoutCalculator (NativeMeasurementActions)
@property(nonatomic, strong, nullable) NSMutableDictionary<NSArray *, NSNumber *> *layoutHeightCache;
- (NSFont *)fontOfSize:(CGFloat)size weight:(CGFloat)weight;
- (NSParagraphStyle *)paragraphStyleWithLineSpacing:(CGFloat)lineSpacing;
- (CGFloat)measuredHeightForText:(NSString *)text width:(CGFloat)width font:(NSFont *)font style:(NSParagraphStyle *)style;
- (NSString *)fontNameForFont:(NSFont *)font;
- (CGFloat)regularFontWeight;
- (CGFloat)semiboldFontWeight;
- (NSDictionary *)textAttributesForFont:(NSFont *)font style:(NSParagraphStyle *)style;
- (NSRect)boundsForText:(NSString *)text size:(NSSize)size attributes:(NSDictionary *)attributes;
- (NSRect)plainBoundsForText:(NSString *)text size:(NSSize)size font:(NSFont *)font;
- (CGFloat)ceiledLineHeightForFont:(NSFont *)font;
- (nullable NSString *)compatibilityShortTitleForBlockText:(NSString *)text;
@end

NS_ASSUME_NONNULL_END
