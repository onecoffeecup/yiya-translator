#import "FYInlineTextUtilities.h"

#pragma mark - 通用小工具

NSString *FYInlineTrim(NSString *value) {
    if (!value) { return @""; }
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

NSString *FYInlineNormalizeTranslationParagraphs(NSString *text) {
    if (text.length == 0) { return @""; }
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSString *> *paragraphs = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    for (NSString *raw in lines) {
        NSString *line = FYInlineTrim(raw);
        if (line.length == 0) {
            if (current.length > 0) { [paragraphs addObject:[current copy]]; [current setString:@""]; }
            continue;
        }
        [current appendString:line];
    }
    if (current.length > 0) { [paragraphs addObject:[current copy]]; }
    return [paragraphs componentsJoinedByString:@"\n\n"];
}

/// 比较用归一化：只去空白，**保留标点**（标点是证据，不能被抹掉）。
NSString *FYInlineNormalize(NSString *value) {
    NSString *trimmed = FYInlineTrim(value);
    NSMutableString *result = [NSMutableString stringWithCapacity:trimmed.length];
    NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSUInteger index = 0; index < trimmed.length; index++) {
        unichar character = [trimmed characterAtIndex:index];
        if (character == 0x3000 || [spaces characterIsMember:character]) { continue; }
        [result appendFormat:@"%C", character];
    }
    return result;
}

CGFloat FYInlineClamp(CGFloat value, CGFloat low, CGFloat high) {
    if (high < low) { return low; }
    return MIN(MAX(value, low), high);
}

BOOL FYInlineRectContainsRect(CGRect outer, CGRect inner) {
    return CGRectGetMinX(inner) >= CGRectGetMinX(outer) - 0.5 && CGRectGetMaxX(inner) <= CGRectGetMaxX(outer) + 0.5 &&
           CGRectGetMinY(inner) >= CGRectGetMinY(outer) - 0.5 && CGRectGetMaxY(inner) <= CGRectGetMaxY(outer) + 0.5;
}

CGFloat FYInlineMedian(NSArray<NSNumber *> *values) {
    if (values.count == 0) { return 0; }
    NSArray<NSNumber *> *sorted = [values sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [a compare:b];
    }];
    return sorted[sorted.count / 2].doubleValue;
}

BOOL FYInlineLineEndsSentence(NSString *text) {
    NSString *trimmed = FYInlineTrim(text);
    if (trimmed.length == 0) { return NO; }
    unichar last = [trimmed characterAtIndex:trimmed.length - 1];
    return last == L'。' || last == L'！' || last == L'？' || last == L'!' || last == L'?' ||
           last == L'．' || last == L'.' || last == L'」' || last == L'』' || last == L')' || last == L'）';
}

BOOL FYInlineHasSentencePunctuation(NSString *text) {
    // Brackets occur in dates, field labels and menu entries. They do not prove
    // that a distant, narrower observation is the next sentence of a paragraph.
    NSCharacterSet *set = [NSCharacterSet characterSetWithCharactersInString:@"。、，．！？!?…"];
    return [(text ?: @"") rangeOfCharacterFromSet:set].location != NSNotFound;
}
