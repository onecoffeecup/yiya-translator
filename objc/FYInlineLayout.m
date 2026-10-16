#import "FYInlineLayout.h"
#import "inline/FYInlineLayoutCalculatorInternal.h"

@implementation FYInlineLayoutEngine
@dynamic fontProvider, layoutHeightCache;
- (instancetype)init {
    if ((self = [super init])) { _textMeasurer = [FYInlineTextMeasurer new]; }
    return self;
}

- (NSFont * (^)(CGFloat, NSFontWeight))fontProvider { return self.textMeasurer.fontProvider; }

- (void)setFontProvider:(NSFont * (^)(CGFloat, NSFontWeight))value { self.textMeasurer.fontProvider = value; }

- (NSMutableDictionary<NSArray *, NSNumber *> *)layoutHeightCache { return self.textMeasurer.layoutHeightCache; }

- (void)setLayoutHeightCache:(NSMutableDictionary<NSArray *, NSNumber *> *)value { self.textMeasurer.layoutHeightCache = value; }

+ (instancetype)defaultEngine {
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine new];
    FYConfigureInlineLayoutDefaults(engine);
    return engine;
}

- (NSFont *)fontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
    return [self.textMeasurer fontOfSize:size weight:weight stateSource:self];
}

- (NSParagraphStyle *)paragraphStyleWithLineSpacing:(CGFloat)lineSpacing {
    return [self.textMeasurer paragraphStyleWithLineSpacing:lineSpacing];
}

- (CGFloat)measuredHeightForText:(NSString *)text
                           width:(CGFloat)width
                            font:(NSFont *)font
                           style:(NSParagraphStyle *)style {
    return [self.textMeasurer measuredHeightForText:text width:width font:font style:style stateSource:self];
}
- (NSString *)fontNameForFont:(NSFont *)font { return font.fontName; }
- (CGFloat)regularFontWeight { return NSFontWeightRegular; }
- (CGFloat)semiboldFontWeight { return NSFontWeightSemibold; }
- (NSDictionary *)textAttributesForFont:(NSFont *)font style:(NSParagraphStyle *)style { return FYInlineTextAttributes(font, style); }
- (NSRect)boundsForText:(NSString *)text size:(NSSize)size attributes:(NSDictionary *)attributes { return FYInlineMeasureTextWithAttributes(text, size, attributes); }
- (NSRect)plainBoundsForText:(NSString *)text size:(NSSize)size font:(NSFont *)font { return FYInlineMeasurePlainText(text, size, font); }
- (CGFloat)ceiledLineHeightForFont:(NSFont *)font { return FYInlineCeiledFontLineHeight(font); }
- (NSString *)compatibilityShortTitleForBlockText:(NSString *)text { return [FYInlineLayoutEngine shortTitleForBlockText:text]; }
@end
