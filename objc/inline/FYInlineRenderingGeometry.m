#import "FYInlineRenderingGeometry.h"

NSRect FYInlineLongCardBodyFrame(CGFloat width, CGFloat height, CGFloat padding, CGFloat titleBandHeight) {
    CGFloat titleBand = 24;
    BOOL showsTitleBand = titleBandHeight > 0.5;
    CGFloat top = titleBandHeight > 0 ? padding + titleBandHeight : (showsTitleBand ? padding + titleBand + 13 : padding);
    return NSMakeRect(padding, top, MAX((CGFloat)80, width - padding * 2), MAX((CGFloat)24, height - top - padding));
}

CGFloat FYInlineLongCardLineHeight(CGFloat ascender, CGFloat descender, CGFloat leading) { return ceil(ascender - descender + leading) + 8; }

CGFloat FYInlineLongCardMinimumHeight(CGFloat lineHeight) { return 18 * 2 + lineHeight * 3.0; }

CGFloat FYInlineLongCardBodyViewport(CGFloat cardHeight) { return MAX(0, cardHeight - 18 * 2); }

NSSize FYInlineLongCardSize(NSSize proposed, BOOL compact) {
    return NSMakeSize(compact ? MAX((CGFloat)60, proposed.width) : MAX((CGFloat)160, proposed.width),
                      MAX(compact ? (CGFloat)28 : (CGFloat)34, proposed.height));
}
