#import "FYInlineTextMeasurer.h"
#import "../FYLocalFont.h"

NSDictionary *FYInlineTextAttributes(NSFont *font, NSParagraphStyle *style) {
    return @{NSFontAttributeName: font, NSParagraphStyleAttributeName: style};
}
NSRect FYInlineMeasureTextWithAttributes(NSString *text, NSSize size, NSDictionary *attributes) {
    return [text boundingRectWithSize:size
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:attributes];
}
NSRect FYInlineMeasurePlainText(NSString *text, NSSize size, NSFont *font) {
    return [text boundingRectWithSize:size
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName: font}];
}
CGFloat FYInlineCeiledFontLineHeight(NSFont *font) {
    return ceil(font.ascender - font.descender + font.leading);
}
@implementation FYInlineTextMeasurer
- (NSFont *)fontOfSize:(CGFloat)size weight:(NSFontWeight)weight stateSource:(id<FYInlineTextMeasurementState>)stateSource {
    if (stateSource.fontProvider) { return stateSource.fontProvider(size, weight); }
    NSString *name = weight >= NSFontWeightSemibold ? @"STYuanti-SC-Bold" : @"STYuanti-SC-Regular";
    return FYLocalFontNamed(name, size) ?: [NSFont systemFontOfSize:size weight:weight];
}

- (NSParagraphStyle *)paragraphStyleWithLineSpacing:(CGFloat)lineSpacing {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByCharWrapping;
    style.lineSpacing = lineSpacing;
    return style;
}

- (CGFloat)measuredHeightForText:(NSString *)text
                           width:(CGFloat)width
                            font:(NSFont *)font
                           style:(NSParagraphStyle *)style stateSource:(id<FYInlineTextMeasurementState>)stateSource {
    if (width <= 4 || text.length == 0) { return 0; }
    // 多轮避让会反复测量同一正文、字体和宽度；只在本轮排版内复用结果。
    NSArray *key = stateSource.layoutHeightCache ? @[text, @(width), font, style] : nil;
    NSNumber *cached = key ? stateSource.layoutHeightCache[key] : nil;
    if (cached) { return cached.doubleValue; }
    NSRect measured = FYInlineMeasureTextWithAttributes(text, NSMakeSize(width, CGFLOAT_MAX), FYInlineTextAttributes(font, style));
    CGFloat height = ceil(NSHeight(measured));
    if (key) { stateSource.layoutHeightCache[key] = @(height); }
    return height;
}
@end
