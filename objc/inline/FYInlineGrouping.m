#import "FYInlineLayoutInternal.h"

#pragma mark - FYInlineGrouper

@implementation FYInlineGrouper

+ (instancetype)defaultGrouper {
    FYInlineGrouper *grouper = [FYInlineGrouper new];
    grouper.maxBlockHeightFraction = 0.55;
    grouper.minimumCharacters = 2;
    return grouper;
}

#pragma mark 去重

- (NSArray<FYInlineTextLine *> *)deduplicatedLines:(NSArray<FYInlineTextLine *> *)lines {
    NSMutableArray<FYInlineTextLine *> *kept = [NSMutableArray array];
    for (FYInlineTextLine *line in lines ?: @[]) {
        NSString *normalized = FYInlineNormalize(line.text);
        if (normalized.length == 0) { continue; }
        BOOL duplicate = NO;
        for (NSUInteger index = 0; index < kept.count; index++) {
            FYInlineTextLine *existing = kept[index];
            if (![FYInlineNormalize(existing.text) isEqualToString:normalized]) { continue; }
            // 文字相同还不够：必须**同一处**才算重复识别。
            // 不同位置的同文内容要各自保留（例如两篇文章里的同一句话）。
            CGFloat overlap = [FYInlineBlockMatcher overlapRatio:line.rect right:existing.rect];
            if (overlap < 0.5) { continue; }
            duplicate = YES;
            if (line.confidence > existing.confidence) { kept[index] = line; }
            break;
        }
        if (!duplicate) { [kept addObject:line]; }
    }
    return kept;
}

#pragma mark 阅读顺序

- (NSArray<FYInlineTextLine *> *)readingOrderForLines:(NSArray<FYInlineTextLine *> *)lines {
    NSMutableArray<NSNumber *> *heights = [NSMutableArray array];
    for (FYInlineTextLine *line in lines) { [heights addObject:@(MAX((CGFloat)0.004, line.rect.size.height))]; }
    CGFloat rowTolerance = MAX((CGFloat)0.006, FYInlineMedian(heights) * 0.5);
    return [lines sortedArrayUsingComparator:^NSComparisonResult(FYInlineTextLine *left, FYInlineTextLine *right) {
        // Vision 归一化坐标 y 向上：y 大 = 更靠上，先读。
        CGFloat leftTop = CGRectGetMaxY(left.rect);
        CGFloat rightTop = CGRectGetMaxY(right.rect);
        if (fabs(leftTop - rightTop) > rowTolerance) {
            return leftTop > rightTop ? NSOrderedAscending : NSOrderedDescending;
        }
        if (left.rect.origin.x < right.rect.origin.x) { return NSOrderedAscending; }
        if (left.rect.origin.x > right.rect.origin.x) { return NSOrderedDescending; }
        return NSOrderedSame;
    }];
}

#pragma mark 合并判定

- (CGFloat)representativeLineHeightForBlock:(FYInlineTextBlock *)block {
    NSMutableArray<NSNumber *> *heights = [NSMutableArray array];
    for (NSValue *value in block.lineBoxes) { [heights addObject:@(MAX((CGFloat)0.004, value.rectValue.size.height))]; }
    if (heights.count == 0) { [heights addObject:@(0.03)]; }
    return FYInlineMedian(heights);
}

- (BOOL)line:(FYInlineTextLine *)line isSameLineAsRect:(CGRect)reference rectHeight:(CGFloat)referenceHeight {
    CGFloat maxHeight = MAX(line.rect.size.height, referenceHeight);
    return fabs(CGRectGetMidY(line.rect) - CGRectGetMidY(reference)) < maxHeight * 0.45;
}

/// 合并判定。返回 YES/NO、把握程度与原因（原因用于诊断）。
- (BOOL)shouldMergeLine:(FYInlineTextLine *)line
               intoBlock:(FYInlineTextBlock *)block
              confidence:(CGFloat *)outConfidence
                  reason:(NSString **)outReason {
    CGRect itemBox = line.rect;
    CGRect blockBox = block.lineBoxes.lastObject ? [block.lineBoxes.lastObject rectValue] : block.boundingBox;
    CGRect combined = CGRectUnion(block.boundingBox, itemBox);
    CGFloat repHeight = [self representativeLineHeightForBlock:block];
    NSString *itemText = FYInlineNormalize(line.text);
    NSString *blockText = FYInlineNormalize(block.lineTexts.lastObject ?: block.text);

    // 弹窗的关闭按钮是独立操作，不是正文的末行。
    NSArray *dismissLabels = @[@"閉じる", @"とじる", @"关闭", @"關閉", @"close"];
    if ([dismissLabels containsObject:itemText.lowercaseString] ||
        [dismissLabels containsObject:blockText.lowercaseString]) {
        if (outReason) { *outReason = @"关闭按钮保持独立"; }
        return NO;
    }

    if (combined.size.height > self.maxBlockHeightFraction) {
        if (outReason) { *outReason = @"合并后整块过高"; }
        return NO;
    }

    // —— 横向关系 ——
    CGFloat overlapLeft = MAX(CGRectGetMinX(itemBox), CGRectGetMinX(blockBox));
    CGFloat overlapRight = MIN(CGRectGetMaxX(itemBox), CGRectGetMaxX(blockBox));
    CGFloat overlapWidth = MAX((CGFloat)0, overlapRight - overlapLeft);
    CGFloat minWidth = MAX((CGFloat)0.001, MIN(itemBox.size.width, blockBox.size.width));
    CGFloat overlapRatio = overlapWidth / minWidth;
    CGFloat horizontalGap = 0;
    if (CGRectGetMaxX(blockBox) < CGRectGetMinX(itemBox)) {
        horizontalGap = CGRectGetMinX(itemBox) - CGRectGetMaxX(blockBox);
    } else if (CGRectGetMaxX(itemBox) < CGRectGetMinX(blockBox)) {
        horizontalGap = CGRectGetMinX(blockBox) - CGRectGetMaxX(itemBox);
    } else {
        horizontalGap = -overlapWidth;
    }
    CGFloat leftDelta = fabs(CGRectGetMinX(itemBox) - CGRectGetMinX(blockBox));
    CGFloat centerDelta = fabs(CGRectGetMidX(itemBox) - CGRectGetMidX(blockBox));

    // 列间空隙：明显超过一个行高就不是同一栏，绝不跨栏拼段。
    if (horizontalGap > MAX((CGFloat)0.010, repHeight * 1.5) && overlapRatio < 0.15) {
        if (outReason) { *outReason = @"横向间隔超过一列间隙"; }
        return NO;
    }

    CGFloat maxHeight = MAX(itemBox.size.height, blockBox.size.height);
    BOOL sameLine = [self line:line isSameLineAsRect:blockBox rectHeight:[self representativeLineHeightForBlock:block]];
    BOOL itemSmall = itemText.length <= 6 && itemBox.size.width < 0.16 && itemBox.size.height < 0.035;
    BOOL blockSmall = blockText.length <= 6 && blockBox.size.width < 0.16 && blockBox.size.height < 0.035;

    // ① 同一行被 OCR 切开的片段（几何判定，不针对文案写死）。
    BOOL splitFragment = sameLine && itemSmall && blockSmall && horizontalGap >= -0.006 &&
                         horizontalGap < MAX((CGFloat)0.010, MIN((CGFloat)0.030, maxHeight * 0.9));
    if (splitFragment) {
        if (outConfidence) { *outConfidence = 0.90; }
        if (outReason) { *outReason = @"同一行相邻片段"; }
        return YES;
    }
    if (itemSmall && blockSmall) {
        if (outReason) { *outReason = @"两个独立短条目"; }
        return NO;
    }
    BOOL paragraphish = itemText.length >= 8 || blockText.length >= 8 ||
                        itemBox.size.width > 0.18 || blockBox.size.width > 0.18;
    // 同一行的“续写”只允许很小的缝：实测两栏排版 0.018 的栏距（约 20px/1080）如果按
    // 旧阈值 0.022 会被当成一行，左右两栏就并成一块了。阈值按局部行高取（<0.4 倍行高）。
    CGFloat sameLineGap = MAX((CGFloat)0.005, MIN((CGFloat)0.014, maxHeight * 0.40));
    if (sameLine && paragraphish && horizontalGap >= -0.006 && horizontalGap < sameLineGap) {
        if (outConfidence) { *outConfidence = 0.80; }
        if (outReason) { *outReason = @"同一行相邻正文"; }
        return YES;
    }
    if (sameLine) {
        if (outReason) { *outReason = @"同一行但间隔过大"; }
        return NO;
    }

    // —— 纵向关系：同列 + 字号相近才谈合并 ——
    BOOL aligned = leftDelta <= MAX((CGFloat)0.008, repHeight * 0.7) ||
                   (overlapRatio >= 0.55 && centerDelta <= MAX((CGFloat)0.012, repHeight * 0.9));
    if (!aligned) {
        if (outReason) { *outReason = @"左右未对齐（不同栏或不同缩进层级）"; }
        return NO;
    }
    // 字号判定用**块的稳定行高（中位数）**做参照，而不是最后一行：
    // OCR 对含拉丁字符/符号的行常常量出偏小的框高（真实采集帧里 +Karen+ 就是 .030 对 .047），
    // 用单行高度会把同一段正文拆开。阈值 0.5 仍能拦住标题（约 0.44）与正文。
    CGFloat referenceHeight = MAX(repHeight, blockBox.size.height);
    CGFloat heightRatio = (MIN(itemBox.size.height, referenceHeight) /
                           MAX((CGFloat)0.0001, MAX(itemBox.size.height, referenceHeight)));
    if (heightRatio < 0.5) {
        if (outReason) { *outReason = @"字号相差明显（标题与正文）"; }
        return NO;
    }

    CGFloat verticalGap = 0;
    if (CGRectGetMinY(blockBox) >= CGRectGetMaxY(itemBox)) {
        verticalGap = CGRectGetMinY(blockBox) - CGRectGetMaxY(itemBox);
    } else if (CGRectGetMinY(itemBox) >= CGRectGetMaxY(blockBox)) {
        verticalGap = CGRectGetMinY(itemBox) - CGRectGetMaxY(blockBox);
    }

    CGFloat widthRatio = (itemBox.size.width > 0 && blockBox.size.width > 0)
        ? MIN(itemBox.size.width, blockBox.size.width) / MAX(itemBox.size.width, blockBox.size.width) : (CGFloat)0;
    BOOL punctuation = FYInlineHasSentencePunctuation(line.text) ||
                       FYInlineHasSentencePunctuation(block.lineTexts.lastObject ?: block.text);
    CGFloat longestPair = MAX((CGFloat)itemText.length, (CGFloat)blockText.length);
    // 资料页的短字段值与下方备注常常左对齐，但它们属于不同的行。
    // 例如「帰宅部」下隔半行高才是「桜井琥一の弟。」；后者明显更宽且有句号，
    // 不能仅凭句读把二者当成正文折行。真正连续的备注两行仍可按下方规则合并。
    if (block.lineBoxes.count == 1 && blockText.length <= 6 &&
        !FYInlineHasSentencePunctuation(block.text) &&
        // 装饰点被读入短值后会扩大行框，仍需保留短字段与完整备注的边界。
        itemText.length >= 7 && itemBox.size.width > blockBox.size.width * 1.45 &&
        (verticalGap > repHeight * 0.25 ||
         fabs(CGRectGetMidY(itemBox) - CGRectGetMidY(blockBox)) > repHeight * 0.60)) {
        if (outReason) { *outReason = @"短字段值与下方正文分行"; }
        return NO;
    }
    // 规则排列的独立条目：两行都短、宽度相近、且都没有句读 —— 这是菜单/设置列表的样子。
    BOOL entryLike = itemText.length <= 16 && blockText.length <= 16 && widthRatio >= 0.70 && !punctuation;

    // ② 折行合并：间距远小于一个行高（≤0.45 倍代表行高）说明是同段的换行。
    //    证据用文本量：正文折行的行明显长于菜单标签（菜单条目之间不会贴这么紧）。
    CGFloat wrapGap = MAX((CGFloat)0.004, repHeight * 0.45);
    if (verticalGap <= wrapGap) {
        BOOL wrapEvidence = longestPair >= 10 || punctuation;
        if (wrapEvidence && paragraphish) {
            if (outConfidence) { *outConfidence = 0.88; }
            if (outReason) { *outReason = @"同一段落折行（行距小于半行高）"; }
            return YES;
        }
        if (outReason) { *outReason = @"行距很近但没有正文证据（更像两条独立短条目）"; }
        return NO;
    }

    // ③ 段落／条目区间：0.45–1.6 倍代表行高。
    //    真实邮件正文的段间空行约 0.85–1.15 倍行高且带句读；等间距设置列表约 1.0 倍行高、
    //    没有句读。所以这一档必须有**强正文证据**（句读，或明显更长的行），否则按独立条目分开。
    CGFloat paragraphGap = MAX(wrapGap, repHeight * 1.6);
    if (verticalGap <= paragraphGap) {
        BOOL strongProse = punctuation || longestPair >= 24;
        if (strongProse && !entryLike) {
            if (outConfidence) { *outConfidence = 0.62; }
            if (outReason) { *outReason = @"同栏正文段落（间隔在一倍行高量级且有正文证据）"; }
            return YES;
        }
        if (outReason) { *outReason = @"间隔落在条目区间且缺少正文证据"; }
        return NO;
    }
    if (outReason) { *outReason = @"间隔超过段落上限或缺少正文证据"; }
    return NO;
}

#pragma mark 分组

/// 行距是否接近"实排"：正文按列宽折行时，行与行之间只有很小的空隙；
/// 菜单/按钮列表的行距通常接近甚至超过行高。用两者的比值判定，不写死像素或字号。
- (BOOL)linesLookTightlyStacked:(NSArray<FYInlineTextLine *> *)lines {
    if (lines.count < 2) { return NO; }
    NSArray<FYInlineTextLine *> *sorted = [lines sortedArrayUsingComparator:^NSComparisonResult(FYInlineTextLine *left, FYInlineTextLine *right) {
        CGFloat leftTop = CGRectGetMaxY(left.rect);
        CGFloat rightTop = CGRectGetMaxY(right.rect);
        if (fabs(leftTop - rightTop) > 1e-6) { return leftTop > rightTop ? NSOrderedAscending : NSOrderedDescending; }
        return left.rect.origin.x < right.rect.origin.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    CGFloat gapSum = 0, heightSum = 0;
    NSUInteger pairs = 0;
    for (NSUInteger index = 0; index + 1 < sorted.count; index++) {
        CGRect upper = sorted[index].rect;
        CGRect lower = sorted[index + 1].rect;
        CGFloat gap = NSMinY(upper) - CGRectGetMaxY(lower);
        if (gap < 0) { gap = 0; }
        gapSum += gap;
        heightSum += MIN(NSHeight(upper), NSHeight(lower));
        pairs += 1;
    }
    if (pairs == 0) { return NO; }
    CGFloat averageGap = gapSum / (CGFloat)pairs;
    CGFloat averageHeight = heightSum / (CGFloat)pairs;
    if (averageHeight <= 0.0001) { return NO; }
    return averageGap <= averageHeight * 0.55;
}

- (FYInlineBlockKind)kindForLines:(NSArray<FYInlineTextLine *> *)lines normalized:(NSString *)normalizedText {    NSUInteger lineCount = lines.count;
    if (lineCount == 0) { return FYInlineBlockKindShort; }
    NSString *normalized = normalizedText ?: @"";
    CGFloat width = 0, height = 0;
    for (FYInlineTextLine *line in lines) {
        width = MAX(width, line.rect.size.width);
        height = MAX(height, line.rect.size.height);
    }
    BOOL wide = width > 0.24;
    BOOL tall = height > 0.075;

    if (lineCount == 1) {
        // 单行只有文本本身足够长才算正文；宽度单独不构成正文证据（宽而短的按钮要保持穿透）。
        if (self.shortLabelDetector && self.shortLabelDetector(normalized)) { return FYInlineBlockKindShort; }
        if (normalized.length >= 16) { return FYInlineBlockKindLong; }
        return FYInlineBlockKindShort;
    }
    // 段落证据先于「每行很短」的菜单猜测：窄列里两句完整介绍仍是正文。
    // 用句读和相对行距识别，不按角色、恰好两行或某个总字数特判。
    BOOL explicitControls = self.shortLabelDetector != nil;
    for (FYInlineTextLine *line in lines) {
        if (!self.shortLabelDetector || !self.shortLabelDetector(FYInlineNormalize(line.text))) {
            explicitControls = NO;
            break;
        }
    }
    if (!explicitControls && FYInlineHasSentencePunctuation(normalized) &&
        [self linesLookTightlyStacked:lines]) {
        return FYInlineBlockKindLong;
    }
    // 规则排列的短条目列表保持短贴片。但「每行 ≤14 字」**不等于**按钮列表：
    // OCR 会按列宽把一段正文切成若干短行（现场：五行喜好正文每行 8~12 字、左对齐、
    // 行距只有 0.45 倍行高、最大行宽 0.239 刚好低于 0.24），旧判据把它当按钮列表，
    // 于是既没有长卡、也没有紧凑入口，整段正文从画面消失。
    // 段落证据：行数够多 + 每行都是较长的片段 + 行距接近"实排"。
    BOOL buttonList = YES;
    for (FYInlineTextLine *line in lines) {
        if (FYInlineNormalize(line.text).length > 14) { buttonList = NO; break; }
    }
    if (buttonList && !wide && !tall) {
        NSUInteger totalLength = normalized.length;
        CGFloat averageLength = lineCount > 0 ? (CGFloat)totalLength / (CGFloat)lineCount : 0;
        if (lineCount >= 4 && totalLength >= 24 && averageLength >= 9 &&
            [self linesLookTightlyStacked:lines]) {
            return FYInlineBlockKindLong;
        }
        return FYInlineBlockKindShort;
    }

    BOOL continuity = NO;
    for (NSUInteger index = 0; index + 1 < lines.count; index++) {
        if (!FYInlineLineEndsSentence(lines[index].text)) { continuity = YES; break; }
    }
    if ((continuity || normalized.length >= 26) && (wide || tall || normalized.length >= 20)) {
        return FYInlineBlockKindLong;
    }
    return FYInlineBlockKindShort;
}

- (FYInlineTextLine *)rowLabelToLeftOfRect:(CGRect)valueRect inLines:(NSArray<FYInlineTextLine *> *)lines {
    FYInlineTextLine *nearest = nil;
    CGFloat nearestGap = CGFLOAT_MAX;
    for (FYInlineTextLine *candidate in lines) {
        CGRect label = candidate.rect;
        CGFloat horizontalGap = CGRectGetMinX(valueRect) - CGRectGetMaxX(label);
        // OCR 可能把值前的装饰点并入行框，与标签产生少量几何重叠。
        // 只容忍四分之一行高以内的误差，仍要求标签位于值的左侧。
        CGFloat overlapTolerance = MIN((CGFloat)0.012,
            MAX(CGRectGetHeight(label), CGRectGetHeight(valueRect)) * 0.25);
        if (horizontalGap < -overlapTolerance || horizontalGap > 0.085 ||
            CGRectGetMidX(label) >= CGRectGetMinX(valueRect) ||
            CGRectGetWidth(label) > 0.10 || FYInlineNormalize(candidate.text).length > 6) { continue; }
        if (fabs(CGRectGetMidY(label) - CGRectGetMidY(valueRect)) >
            MAX(CGRectGetHeight(label), CGRectGetHeight(valueRect)) * 0.55) { continue; }
        if (horizontalGap < nearestGap) { nearest = candidate; nearestGap = horizontalGap; }
    }
    return nearest;
}

- (BOOL)line:(FYInlineTextLine *)line startsAnotherFieldRowAfterBlock:(FYInlineTextBlock *)block
   inLines:(NSArray<FYInlineTextLine *> *)lines {
    CGRect previous = block.lineBoxes.lastObject ? block.lineBoxes.lastObject.rectValue : block.boundingBox;
    FYInlineTextLine *upperLabel = [self rowLabelToLeftOfRect:previous inLines:lines];
    FYInlineTextLine *lowerLabel = [self rowLabelToLeftOfRect:line.rect inLines:lines];
    return upperLabel && lowerLabel && upperLabel != lowerLabel &&
        fabs(CGRectGetMinX(upperLabel.rect) - CGRectGetMinX(lowerLabel.rect)) < 0.030;
}

- (NSArray<FYInlineTextBlock *> *)blocksFromLines:(NSArray<FYInlineTextLine *> *)lines {
    NSArray<FYInlineTextLine *> *deduplicated = [self deduplicatedLines:lines];
    NSMutableArray<FYInlineTextLine *> *filtered = [NSMutableArray array];
    for (FYInlineTextLine *line in deduplicated) {
        NSString *text = FYInlineTrim(line.text);
        if ((NSInteger)FYInlineNormalize(text).length < self.minimumCharacters) { continue; }
        line.text = text;
        [filtered addObject:line];
    }
    NSArray<FYInlineTextLine *> *ordered = [self readingOrderForLines:filtered];

    NSMutableArray<FYInlineTextBlock *> *blocks = [NSMutableArray array];
    for (FYInlineTextLine *line in ordered) {
        NSString *text = FYInlineTrim(line.text);
        FYInlineTextBlock *target = nil;
        BOOL merge = NO;
        CGFloat confidence = 1.0;
        for (FYInlineTextBlock *block in [blocks reverseObjectEnumerator]) {
            // 同栏字段的值可能左对齐、甚至被 Vision 合进同一个 observation；
            // 两行分别有自己的左侧标签时，它们是表格的两行，不是正文折行。
            if ([self line:line startsAnotherFieldRowAfterBlock:block inLines:ordered]) { continue; }
            CGFloat found = 0;
            NSString *blockReason = nil;
            if ([self shouldMergeLine:line intoBlock:block confidence:&found reason:&blockReason]) {
                target = block;
                merge = YES;
                confidence = found;
                break;
            }
        }
        if (!merge || !target) {
            FYInlineTextBlock *block = [FYInlineTextBlock new];
            block.text = text;
            block.boundingBox = line.rect;
            block.lineTexts = @[text];
            block.lineBoxes = @[@(line.rect)];
            block.lineConfidences = @[@(line.confidence)];
            block.sourceIndices = @[@(line.sourceIndex)];
            block.groupingConfidence = 1.0;
            [blocks addObject:block];
            continue;
        }

        BOOL sameLine = [self line:line isSameLineAsRect:[target.lineBoxes.lastObject rectValue]
                                            rectHeight:[target.lineBoxes.lastObject rectValue].size.height];
        NSString *separator = sameLine ? @" " : @"\n";
        target.text = [target.text stringByAppendingFormat:@"%@%@", separator, text];
        target.boundingBox = CGRectUnion(target.boundingBox, line.rect);
        target.lineTexts = [target.lineTexts arrayByAddingObject:text];
        target.lineBoxes = [target.lineBoxes arrayByAddingObject:@(line.rect)];
        target.lineConfidences = [target.lineConfidences arrayByAddingObject:@(line.confidence)];
        target.sourceIndices = [target.sourceIndices arrayByAddingObject:@(line.sourceIndex)];
        target.groupingConfidence = MIN(target.groupingConfidence, confidence);
    }

    // 分类 + 稳定身份 + 阅读顺序。
    NSMutableArray<FYInlineTextBlock *> *result = [NSMutableArray array];
    for (NSUInteger index = 0; index < blocks.count; index++) {
        FYInlineTextBlock *block = blocks[index];
        NSMutableArray<FYInlineTextLine *> *blockLines = [NSMutableArray array];
        for (NSUInteger lineIndex = 0; lineIndex < block.lineBoxes.count; lineIndex++) {
            FYInlineTextLine *line = [FYInlineTextLine new];
            line.text = block.lineTexts[lineIndex];
            line.rect = [block.lineBoxes[lineIndex] rectValue];
            line.confidence = [block.lineConfidences[lineIndex] doubleValue];
            line.sourceIndex = [block.sourceIndices[lineIndex] integerValue];
            [blockLines addObject:line];
        }
        block.kind = [self kindForLines:blockLines normalized:FYInlineNormalize(block.text)];
        block.blockID = [FYInlineBlockMatcher blockIDForText:block.text lineBoxes:block.lineBoxes];
        block.readingOrder = (NSInteger)index;
        [result addObject:block];
    }
    return result;
}

@end

