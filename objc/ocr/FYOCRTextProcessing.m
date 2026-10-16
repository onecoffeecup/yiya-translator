#import "FYOCRTextProcessing.h"
#import "FYOCRRefinement.h"
@implementation FYOCRTextProcessing
+ (NSString *)postprocessedTextForItems:(NSArray<OCRTextItem *> *)items renderedTexts:(NSSet<NSString *> *)renderedTexts blocks:(NSArray<OCRTextItem *> **)outBlocks {
    items=[self itemsExcludingOwnOverlay:items renderedTexts:renderedTexts];
    return [self sourceTextForItems:items blocks:outBlocks];
}

+ (NSString *)sourceTextForItems:(NSArray<OCRTextItem *> *)items blocks:(NSArray<OCRTextItem *> **)outBlocks {
    items=[FYOCRRefinement resolveOverlappingItems:items];
    if (outBlocks) *outBlocks=items;
    return [[items valueForKey:@"text"] componentsJoinedByString:@"\n"] ?: @"";
}

+ (BOOL)isOwnOverlayText:(NSString *)raw {
    NSString *t = raw ? [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
    if (t.length == 0) { return NO; }
    NSString *lower = t.lowercaseString;
    // 翻译全失败时状态串会长成「翻译失败：<服务端报错>」，形状不固定，用前缀识别
    if ([t hasPrefix:@"翻译失败："] || [t hasPrefix:@"翻译失败:"]) { return YES; }
    NSArray<NSString *> *needles = @[@"译文已更新", @"自动判别", @"翻译界面", @"正在翻译",
                                     @"等待文本稳定", @"已暂停", @"本次 ", @"OCr ".lowercaseString];
    // 短且**完全没有日文假名/汉字**的碎片：`？？？` 之类的字形被误读成拉丁字母
    // （实测名字框读成 `iee`、`ことと`）。这类东西发去翻译只会得到编造的译文。
    if (t.length <= 6) {
        BOOL hasKanaOrKanji = NO;
        for (NSUInteger index = 0; index < t.length; index++) {
            unichar character = [t characterAtIndex:index];
            if ((character >= 0x3040 && character <= 0x30FF) ||
                (character >= 0x4E00 && character <= 0x9FFF)) { hasKanaOrKanji = YES; break; }
        }
        if (!hasKanaOrKanji) { return YES; }
    }

    // 状态行被 OCR 截断成片段时（实测 `翻译 0.6s 总 0.8s`）关键词会丢，但**计时格式**还在。
    // 游戏正文里不会出现 `0.6s` 这种「数字.数字s」的秒表写法，所以这条很安全。
    BOOL hasTimingPattern = NO;
    {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[0-9]+\\.[0-9]+s"
                                                                              options:0
                                                                                error:NULL];
        if (regex) {
            NSRange full = NSMakeRange(0, t.length);
            hasTimingPattern = [regex firstMatchInString:t options:0 range:full] != nil;
        }
    }
    if (hasTimingPattern) { return YES; }

    BOOL hasNeedle = NO;
    for (NSString *needle in needles) {
        if ([t containsString:needle] || [lower containsString:needle.lowercaseString]) { hasNeedle = YES; break; }
    }
    if (!hasNeedle) { return NO; }
    // 状态行一定带数字（秒数）。这里放宽到“含数字”即可：
    // OCR 常把它读花（实测 `译文已要新・OCR 0.25南译0.3550.55）。••`），
    // 原来要求含「秒/句/s」就漏过了 —— 于是这行乱码混进字幕带、被当成台词送去翻译，
    // 模型自然给出一句完全不相干的译文。
    BOOL hasDigit = NO;
    for (NSUInteger index = 0; index < t.length; index++) {
        unichar character = [t characterAtIndex:index];
        if (character >= '0' && character <= '9') { hasDigit = YES; break; }
    }
    if (hasDigit) { return YES; }

    BOOL looksStatus = [t containsString:@"s"] || [t containsString:@"S"] || [t containsString:@"秒"];
    BOOL looksCount = [t containsString:@"句"];
    return looksStatus || looksCount;
}

+ (NSArray<OCRTextItem *> *)itemsExcludingOwnOverlay:(NSArray<OCRTextItem *> *)items
                                     renderedTexts:(NSSet<NSString *> *)renderedTexts {
    if (items.count == 0) { return items; }
    NSMutableArray<OCRTextItem *> *kept = [NSMutableArray arrayWithCapacity:items.count];
    for (OCRTextItem *item in items) {
        if ([self isOwnOverlayText:item.text]) { continue; }
        if (renderedTexts.count > 0) {
            NSString *normalized = FYNormalizeOCRTextForComparison(item.text);
            if (normalized.length > 0 && [renderedTexts containsObject:normalized]) { continue; }
        }
        [kept addObject:item];
    }
    return kept;
}

+ (NSSet<NSString *> *)renderedTranslationSetForCaption:(NSString *)captionText inlineCache:(NSDictionary *)inlineCache {
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    NSString *normalizedCaption = FYNormalizeOCRTextForComparison(captionText);
    if (normalizedCaption.length >= 2) { [set addObject:normalizedCaption]; }
    for (NSString *value in inlineCache.allValues) {
        if (![value isKindOfClass:NSString.class]) { continue; }
        NSString *normalized = FYNormalizeOCRTextForComparison(value);
        if (normalized.length >= 2) { [set addObject:normalized]; }
    }
    return set;
}

+ (NSArray<OCRTextItem *> *)splitMultilineItems:(NSArray<OCRTextItem *> *)items {
    NSMutableArray<OCRTextItem *> *result = [NSMutableArray array];
    for (OCRTextItem *item in items ?: @[]) {
        NSArray<NSString *> *parts = [item.text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
        NSMutableArray<NSNumber *> *indexes = [NSMutableArray array];
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        NSUInteger longest = 0;
        for (NSUInteger index = 0; index < parts.count; index++) {
            NSString *line = [parts[index] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (line.length == 0) { continue; }
            [indexes addObject:@(index)];
            [lines addObject:line];
            longest = MAX(longest, line.length);
        }
        if (lines.count < 2) { [result addObject:item]; continue; }
        CGRect outer = item.boundingBox;
        for (NSUInteger ordinal = 0; ordinal < lines.count; ordinal++) {
            NSUInteger originalIndex = indexes[ordinal].unsignedIntegerValue;
            CGRect lineBox = CGRectZero;
            if (item.lineBoxes.count == parts.count) { lineBox = item.lineBoxes[originalIndex].rectValue; }
            if (CGRectIsEmpty(lineBox) ||
                (fabs(CGRectGetWidth(lineBox) - CGRectGetWidth(outer)) < 0.001 &&
                 fabs(CGRectGetHeight(lineBox) - CGRectGetHeight(outer)) < 0.001)) {
                // Older OCR results provide only the union box. Preserve row order and
                // approximate widths until Vision's character-range boxes are available.
                CGFloat height = CGRectGetHeight(outer) / (CGFloat)lines.count;
                CGFloat width = CGRectGetWidth(outer) * (CGFloat)lines[ordinal].length / (CGFloat)MAX((NSUInteger)1, longest);
                lineBox = CGRectMake(CGRectGetMinX(outer), CGRectGetMaxY(outer) - (ordinal + 1) * height,
                                     MIN(CGRectGetWidth(outer), MAX((CGFloat)0.005, width)), height);
            }
            OCRTextItem *lineItem = [OCRTextItem new];
            lineItem.text = lines[ordinal];
            lineItem.boundingBox = lineBox;
            lineItem.lastLineBox = lineBox;
            lineItem.lineTexts = @[lineItem.text];
            lineItem.lineBoxes = @[[NSValue valueWithRect:lineBox]];
            lineItem.lineCount = 1;
            lineItem.blockKind = item.blockKind;
            lineItem.confidence = item.confidence;
            lineItem.groupingConfidence = item.groupingConfidence;
            lineItem.speakerLabel = item.speakerLabel;
            [result addObject:lineItem];
        }
    }
    return result;
}

+ (NSString *)textFromRecognizedLines:(NSArray<NSString *> *)lines {
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *value in lines) {
        NSString *line = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (line.length > 0) { [kept addObject:line]; }
    }
    return [kept componentsJoinedByString:@"\n"];
}
@end
