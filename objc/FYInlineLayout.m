#import "FYInlineLayout.h"

#pragma mark - 通用小工具

static NSString *FYInlineTrim(NSString *value) {
    if (!value) { return @""; }
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

/// 比较用归一化：只去空白，**保留标点**（标点是证据，不能被抹掉）。
static NSString *FYInlineNormalize(NSString *value) {
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

static CGFloat FYInlineClamp(CGFloat value, CGFloat low, CGFloat high) {
    if (high < low) { return low; }
    return MIN(MAX(value, low), high);
}

static BOOL FYInlineRectContainsRect(CGRect outer, CGRect inner) {
    return CGRectGetMinX(inner) >= CGRectGetMinX(outer) - 0.5 && CGRectGetMaxX(inner) <= CGRectGetMaxX(outer) + 0.5 &&
           CGRectGetMinY(inner) >= CGRectGetMinY(outer) - 0.5 && CGRectGetMaxY(inner) <= CGRectGetMaxY(outer) + 0.5;
}

static CGFloat FYInlineMedian(NSArray<NSNumber *> *values) {
    if (values.count == 0) { return 0; }
    NSArray<NSNumber *> *sorted = [values sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [a compare:b];
    }];
    return sorted[sorted.count / 2].doubleValue;
}

static BOOL FYInlineLineEndsSentence(NSString *text) {
    NSString *trimmed = FYInlineTrim(text);
    if (trimmed.length == 0) { return NO; }
    unichar last = [trimmed characterAtIndex:trimmed.length - 1];
    return last == L'。' || last == L'！' || last == L'？' || last == L'!' || last == L'?' ||
           last == L'．' || last == L'.' || last == L'」' || last == L'』' || last == L')' || last == L'）';
}

static BOOL FYInlineHasSentencePunctuation(NSString *text) {
    NSCharacterSet *set = [NSCharacterSet characterSetWithCharactersInString:@"。、，．，！？!?…「」『』（）()"];
    return [(text ?: @"") rangeOfCharacterFromSet:set].location != NSNotFound;
}

#pragma mark - FYInlineTextLine

@implementation FYInlineTextLine
+ (instancetype)lineWithText:(NSString *)text rect:(CGRect)rect confidence:(CGFloat)confidence sourceIndex:(NSInteger)sourceIndex {
    FYInlineTextLine *line = [FYInlineTextLine new];
    line.text = text ?: @"";
    line.rect = rect;
    line.confidence = confidence;
    line.sourceIndex = sourceIndex;
    return line;
}
@end

#pragma mark - FYInlineTextBlock

@implementation FYInlineTextBlock
- (NSInteger)lineCount { return (NSInteger)self.lineTexts.count; }
- (instancetype)init {
    self = [super init];
    if (self) {
        _text = @"";
        _lineTexts = @[];
        _lineBoxes = @[];
        _lineConfidences = @[];
        _sourceIndices = @[];
        _groupingConfidence = 1.0;
    }
    return self;
}
@end

#pragma mark - FYInlineLayoutRequest

@implementation FYInlineLayoutRequest
+ (instancetype)requestWithBlock:(FYInlineTextBlock *)block translation:(NSString *)translation sourceFrame:(CGRect)sourceFrame {
    FYInlineLayoutRequest *request = [FYInlineLayoutRequest new];
    request.block = block;
    request.translation = translation ?: @"";
    request.sourceFrame = sourceFrame;
    return request;
}
@end

#pragma mark - FYInlinePlacement

@implementation FYInlinePlacement
- (instancetype)init {
    self = [super init];
    if (self) {
        _blockID = @"";
        _sourceBlockID = @"";
        _translation = @"";
        _reason = @"";
        _rejectedCandidates = @[];
    }
    return self;
}
@end

#pragma mark - FYInlineLayoutResult

@interface FYInlineLayoutResult ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, FYInlinePlacement *> *byBlockID;
@end

@implementation FYInlineLayoutResult
- (instancetype)init {
    self = [super init];
    if (self) {
        _placements = @[];
        _visiblePlacements = @[];
        _unplaceableBlockIDs = @[];
        _compactEntryBlockIDs = @[];
        _byBlockID = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)setPlacements:(NSArray<FYInlinePlacement *> *)placements {
    _placements = [placements copy] ?: @[];
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    NSMutableArray *visible = [NSMutableArray array];
    NSMutableArray *unplaceable = [NSMutableArray array];
    NSMutableArray *compact = [NSMutableArray array];
    for (FYInlinePlacement *placement in _placements) {
        if (placement.blockID.length > 0) { map[placement.blockID] = placement; }
        if (placement.mode == FYInlineDisplayModeUnplaceable) {
            [unplaceable addObject:placement.blockID];
        } else {
            [visible addObject:placement];
        }
        if (placement.mode == FYInlineDisplayModeCompactEntry) { [compact addObject:placement.blockID]; }
    }
    self.byBlockID = map;
    _visiblePlacements = visible;
    _unplaceableBlockIDs = unplaceable;
    _compactEntryBlockIDs = compact;
}
- (FYInlinePlacement *)placementForBlockID:(NSString *)blockID {
    if (blockID.length == 0) { return nil; }
    return self.byBlockID[blockID];
}
@end

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

- (FYInlineBlockKind)kindForLines:(NSArray<FYInlineTextLine *> *)lines normalized:(NSString *)normalizedText {
    NSUInteger lineCount = lines.count;
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
    // 规则排列的短条目列表保持短贴片。
    BOOL buttonList = YES;
    for (FYInlineTextLine *line in lines) {
        if (FYInlineNormalize(line.text).length > 14) { buttonList = NO; break; }
    }
    if (buttonList && !wide && !tall) { return FYInlineBlockKindShort; }

    BOOL continuity = NO;
    for (NSUInteger index = 0; index + 1 < lines.count; index++) {
        if (!FYInlineLineEndsSentence(lines[index].text)) { continuity = YES; break; }
    }
    if ((continuity || normalized.length >= 26) && (wide || tall || normalized.length >= 20)) {
        return FYInlineBlockKindLong;
    }
    return FYInlineBlockKindShort;
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

#pragma mark - FYInlineBlockMatcher

@implementation FYInlineBlockMatcher

+ (NSString *)blockIDForText:(NSString *)text lineBoxes:(NSArray<NSValue *> *)lineBoxes {
    NSMutableString *key = [NSMutableString stringWithString:FYInlineNormalize(text)];
    for (NSValue *value in lineBoxes) {
        CGRect rect = value.rectValue;
        [key appendFormat:@"|%.3f,%.3f,%.3f,%.3f", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
    }
    return [key copy];
}

+ (NSString *)normalizedForSimilarity:(NSString *)text {
    return FYInlineNormalize(text);
}

+ (CGFloat)textSimilarity:(NSString *)left right:(NSString *)right {
    NSString *a = FYInlineNormalize(left);
    NSString *b = FYInlineNormalize(right);
    if (a.length == 0 || b.length == 0) { return 0; }
    if ([a isEqualToString:b]) { return 1.0; }
    if (a.length < 2 || b.length < 2) { return 0; }
    NSMutableDictionary<NSString *, NSNumber *> *bigrams = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index + 1 < a.length; index++) {
        NSString *gram = [a substringWithRange:NSMakeRange(index, 2)];
        bigrams[gram] = @(bigrams[gram].integerValue + 1);
    }
    NSUInteger matches = 0;
    for (NSUInteger index = 0; index + 1 < b.length; index++) {
        NSString *gram = [b substringWithRange:NSMakeRange(index, 2)];
        NSInteger count = bigrams[gram].integerValue;
        if (count > 0) {
            matches += 1;
            bigrams[gram] = @(count - 1);
        }
    }
    return (CGFloat)(2.0 * matches) / (CGFloat)((a.length - 1) + (b.length - 1));
}

+ (CGFloat)overlapRatio:(CGRect)left right:(CGRect)right {
    CGRect hit = CGRectIntersection(left, right);
    if (CGRectIsNull(hit) || CGRectIsEmpty(hit)) { return 0; }
    CGFloat hitArea = hit.size.width * hit.size.height;
    CGFloat smaller = MIN(left.size.width * left.size.height, right.size.height * right.size.width);
    if (smaller <= 0) { return 0; }
    return hitArea / smaller;
}

+ (NSString *)stableBlockIDForBlock:(FYInlineTextBlock *)block
                               text:(NSString *)text
                        sourceFrame:(CGRect)sourceFrame
                     previousResult:(FYInlineLayoutResult *)previous {
    if (!previous || previous.placements.count == 0) { return nil; }
    NSString *normalized = FYInlineNormalize(text);
    FYInlinePlacement *best = nil;
    CGFloat bestScore = 0;
    for (FYInlinePlacement *placement in previous.placements) {
        if (placement.blockID.length == 0) { continue; }
        CGFloat similarity = [self textSimilarity:normalized right:placement.block.text ?: placement.translation];
        BOOL sameText = similarity >= 0.999;
        if (similarity < 0.62) { continue; }
        CGFloat overlap = [self overlapRatio:sourceFrame right:placement.sourceFrame];
        if (overlap < 0.20) { continue; }
        CGFloat sizeRatio = MIN(NSWidth(sourceFrame), NSWidth(placement.sourceFrame)) /
                            MAX((CGFloat)0.001, MAX(NSWidth(sourceFrame), NSWidth(placement.sourceFrame)));
        if (sizeRatio < 0.55) { continue; }
        CGFloat score = overlap * (sameText ? 2.0 : 1.0) + similarity;
        if (score > bestScore) { bestScore = score; best = placement; }
    }
    return best.blockID;
}

@end

#pragma mark - 候选位置

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

@implementation FYInlineCandidate
@end

#pragma mark - FYInlineLayoutEngine

@interface FYInlineLayoutEngine ()
@property (nonatomic) NSUInteger revision;
@end

@implementation FYInlineLayoutEngine

+ (instancetype)defaultEngine {
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine new];
    engine.shortFontSize = 16;
    engine.coverFontSize = 17;
    engine.longBodyFontSize = 19;
    engine.longTitleFontSize = 14;
    engine.longLineSpacing = 8;
    engine.minimumBodyLines = 3;
    engine.cardMaxWidth = 560;
    engine.cardWidthFraction = 0.52;
    engine.cardWideFraction = 0.62;
    engine.cardMaxHeight = 330;
    engine.cardHeightFraction = 0.55;
    engine.viewportMargin = 8;
    engine.panelGap = 4;
    engine.compactEntryHeight = 34;
    engine.stabilityTolerance = 3;
    engine.shortWidthFraction = 0.42;
    engine.shortMaxWidth = 360;
    return engine;
}

#pragma mark 字体与段落样式（测量与绘制共用）

- (NSFont *)fontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
    if (self.fontProvider) { return self.fontProvider(size, weight); }
    NSString *name = weight >= NSFontWeightSemibold ? @"STYuanti-SC-Bold" : @"STYuanti-SC-Regular";
    return [NSFont fontWithName:name size:size] ?: [NSFont systemFontOfSize:size weight:weight];
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
                           style:(NSParagraphStyle *)style {
    if (width <= 4 || text.length == 0) { return 0; }
    NSRect measured = [text boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
                                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                      attributes:@{NSFontAttributeName: font, NSParagraphStyleAttributeName: style}];
    return ceil(NSHeight(measured));
}

- (CGFloat)longCardLineHeight:(FYInlinePlacement *)placement {
    NSFont *font = placement.font ?: [self fontOfSize:self.longBodyFontSize weight:NSFontWeightRegular];
    return ceil(font.ascender - font.descender + font.leading) + self.longLineSpacing;
}

- (CGFloat)minimumCardHeight {
    CGFloat padding = 18;
    CGFloat titleBand = 24 + 13;
    NSFont *font = [self fontOfSize:self.longBodyFontSize weight:NSFontWeightRegular];
    CGFloat lineHeight = ceil(font.ascender - font.descender + font.leading) + self.longLineSpacing;
    return padding * 2 + titleBand + lineHeight * MAX((CGFloat)1, (CGFloat)self.minimumBodyLines);
}

- (NSFont *)shortBodyFontForCover:(BOOL)cover {
    return [self fontOfSize:(cover ? self.coverFontSize : self.shortFontSize) weight:NSFontWeightRegular];
}
- (NSParagraphStyle *)shortParagraphStyle {
    return [self paragraphStyleWithLineSpacing:3];
}
- (NSFont *)longBodyFont {
    return [self fontOfSize:self.longBodyFontSize weight:NSFontWeightRegular];
}
- (NSParagraphStyle *)longBodyParagraphStyle {
    return [self paragraphStyleWithLineSpacing:self.longLineSpacing];
}
- (NSFont *)longTitleFont {
    return [self fontOfSize:self.longTitleFontSize weight:NSFontWeightSemibold];
}

- (CGFloat)measuredBodyHeight:(NSString *)translation placement:(FYInlinePlacement *)placement width:(CGFloat)width {
    CGFloat textWidth = MAX((CGFloat)80, width - placement.panelPadding * 2);
    return [self measuredHeightForText:translation width:textWidth font:placement.font style:placement.paragraphStyle];
}

#pragma mark 短贴片

- (FYInlinePlacement *)basePlacementForRequest:(FYInlineLayoutRequest *)request
                                    stableID:(NSString *)stableID
                                    viewport:(CGRect)viewport {
    FYInlinePlacement *placement = [FYInlinePlacement new];
    placement.blockID = stableID;
    placement.sourceBlockID = request.block.blockID;
    placement.block = request.block;
    placement.translation = request.translation;
    placement.readingOrder = request.block.readingOrder;
    placement.sourceFrame = request.sourceFrame;
    placement.groupingConfidence = request.block.groupingConfidence;
    placement.matchedPreviousFrame = ![stableID isEqualToString:request.block.blockID];
    placement.panelPadding = 10;
    placement.titleBandHeight = 0;
    placement.cornerRadius = 7;
    return placement;
}

- (void)prepareShortPlacement:(FYInlinePlacement *)placement
                    sourceText:(NSString *)sourceText
                      viewport:(CGRect)viewport {
    NSString *normalizedSource = FYInlineNormalize(sourceText);
    BOOL hasLineBreak = [sourceText rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound;
    BOOL cover = hasLineBreak || normalizedSource.length >= 18 ||
                 (normalizedSource.length >= 12 && NSHeight(placement.sourceFrame) > NSHeight(viewport) * 0.055);
    CGFloat fontSize = cover ? self.coverFontSize : self.shortFontSize;
    CGFloat paddingX = cover ? 12 : 10;
    CGFloat paddingY = cover ? 6 : 5;
    NSFont *font = [self fontOfSize:fontSize weight:NSFontWeightRegular];
    NSParagraphStyle *style = [self shortParagraphStyle];
    placement.font = font;
    placement.paragraphStyle = style;
    placement.panelPadding = paddingY;
    placement.titleBandHeight = 0;
    placement.cornerRadius = 7;

    CGFloat maxWidth = MIN(NSWidth(viewport) - 16, MAX((CGFloat)90, MIN(self.shortMaxWidth, NSWidth(viewport) * self.shortWidthFraction)));
    maxWidth = MAX((CGFloat)80, maxWidth);
    NSDictionary *attributes = @{NSFontAttributeName: font, NSParagraphStyleAttributeName: style};
    NSRect natural = [placement.translation boundingRectWithSize:NSMakeSize(10000, CGFLOAT_MAX)
                                                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                      attributes:attributes];
    if (!cover) {
        maxWidth = MIN(maxWidth, MAX((CGFloat)48, ceil(NSWidth(natural)) + paddingX * 2 + 4));
    }
    CGFloat width = maxWidth;
    CGFloat textWidth = MAX((CGFloat)20, width - paddingX * 2 - 4);
    CGFloat textHeight = [self measuredHeightForText:placement.translation width:textWidth font:font style:style];
    CGFloat maximumHeight = MAX((CGFloat)40, NSHeight(viewport) - 16);
    CGFloat height = MIN(MAX(textHeight + paddingY * 2 + 4, 28), maximumHeight);
    placement.measuredContentHeight = textHeight;
    placement.bodyViewportHeight = MAX(0, height - paddingY * 2);
    placement.scrollable = NO;
    placement.labelFrame = NSMakeRect(paddingX, height - paddingY - MIN(height - paddingY * 2, textHeight + 4),
                                      width - paddingX * 2, MIN(height - paddingY * 2, textHeight + 4));
    placement.translationFrame = NSMakeRect(0, 0, width, height);
    placement.reason = cover ? @"短贴片按长原文覆盖式尺寸" : @"短贴片贴合译文宽度";
}

#pragma mark 长阅读卡

/// 长卡测量：从原文宽度出发尝试有限几个宽度，选第一个能完整容纳译文的宽度；
/// 都放不下就用最宽的那个并在卡内滚动。高度按**完整译文**计算，优先贴合内容、减少空白，
/// 但不低于可读下限（内边距 + 标题 + 三行正文）。
- (void)prepareLongPlacement:(FYInlinePlacement *)placement
             widthCandidates:(NSArray<NSNumber *> *)widths
                  windowInner:(CGFloat)windowInner
                         cap:(CGFloat)cap
                    minHeight:(CGFloat)minimumHeight {
    CGFloat padding = 18;
    CGFloat titleBand = 24 + 13;
    placement.panelPadding = padding;
    placement.titleBandHeight = titleBand;
    placement.cornerRadius = 12;

    // 卡高 = 正文文档高 + 内边距 + 标题带。以前漏加了 chrome，导致中等长度的译文
    // 明明能一屏放下却被迫滚动、卡片高度也没真正贴合内容。
    // 文档高统一按 +4 的排版余量算，与 applyInlineLongCardBody 的文档高度同一口径。
    CGFloat chrome = padding * 2 + titleBand;
    CGFloat capBody = MAX(0, cap - chrome);
    CGFloat chosenWidth = widths.firstObject.doubleValue;
    CGFloat chosenContent = 0;
    BOOL fits = NO;
    for (NSUInteger index = 0; index < widths.count; index++) {
        CGFloat width = widths[index].doubleValue;
        CGFloat content = [self measuredBodyHeight:placement.translation placement:placement width:width] + 4;
        chosenWidth = width;
        chosenContent = content;
        if (content <= capBody) { fits = YES; break; }
    }
    CGFloat height = fits ? (chosenContent + chrome) : cap;
    height = FYInlineClamp(height, MIN(minimumHeight, windowInner), MIN(cap, windowInner));
    CGFloat viewportHeight = MAX(0, height - chrome);
    placement.translationFrame = NSMakeRect(0, 0, chosenWidth, height);
    placement.measuredContentHeight = chosenContent;
    placement.bodyViewportHeight = viewportHeight;
    placement.scrollable = chosenContent > viewportHeight + 0.5;
    placement.bodyViewportFrame = NSMakeRect(padding, padding + titleBand, MAX((CGFloat)80, chosenWidth - padding * 2),
                                             viewportHeight);
}

#pragma mark 候选生成

- (NSArray<FYInlineCandidate *> *)candidatesForPlacement:(FYInlinePlacement *)placement
                                                viewport:(CGRect)viewport
                                           compactEntry:(BOOL)compact
                                                 widths:(NSArray<NSNumber *> *)widths {
    NSMutableArray<FYInlineCandidate *> *candidates = [NSMutableArray array];
    CGFloat gap = self.panelGap;
    CGRect source = placement.sourceFrame;
    CGFloat minX = NSMinX(viewport) + self.viewportMargin;
    CGFloat maxX = NSMaxX(viewport) - self.viewportMargin;
    CGFloat width = widths.firstObject.doubleValue;
    CGFloat height = NSHeight(placement.translationFrame) > 0 ? NSHeight(placement.translationFrame) : self.compactEntryHeight;
    if (compact) { height = self.compactEntryHeight; }

    void (^add)(FYInlineAnchor, CGFloat, CGFloat, NSInteger, NSString *) = ^(FYInlineAnchor anchor, CGFloat x, CGFloat y, NSInteger rank, NSString *name) {
        FYInlineCandidate *candidate = [FYInlineCandidate new];
        candidate.anchor = anchor;
        candidate.anchorRank = rank;
        candidate.compact = compact;
        candidate.name = name;
        candidate.frame = NSMakeRect(x, y, width, height);
        candidate.measuredContentHeight = placement.measuredContentHeight;
        candidate.bodyViewportHeight = placement.bodyViewportHeight;
        candidate.scrollable = placement.scrollable;
        candidate.distance = MAX(0, MAX(CGRectGetMinY(source) - CGRectGetMaxY(candidate.frame),
                                        CGRectGetMinY(candidate.frame) - CGRectGetMaxY(source)));
        [candidates addObject:candidate];
    };

    CGFloat anchorX = FYInlineClamp(NSMinX(source), minX, MAX(minX, maxX - width));
    // ① 原文下方近邻
    add(FYInlineAnchorBelow, anchorX, CGRectGetMinY(source) - height - gap, 0, @"原文下方");
    // ② 原文上方近邻
    add(FYInlineAnchorAbove, anchorX, CGRectGetMaxY(source) + gap, 1, @"原文上方");
    // ③ 原文右侧 / 左侧近邻
    add(FYInlineAnchorRight, CGRectGetMaxX(source) + gap, CGRectGetMidY(source) - height / 2.0, 2, @"原文右侧");
    add(FYInlineAnchorLeft, CGRectGetMinX(source) - gap - width, CGRectGetMidY(source) - height / 2.0, 3, @"原文左侧");
    // ④ 只覆盖自身正文区域
    add(FYInlineAnchorOverlay, anchorX, CGRectGetMidY(source) - height / 2.0, 4, @"覆盖原文自身");

    return candidates;
}

#pragma mark 候选合法性

- (void)filterCandidates:(NSArray<FYInlineCandidate *> *)candidates
                placement:(FYInlinePlacement *)placement
                 viewport:(CGRect)viewport
            otherSources:(NSArray<NSValue *> *)otherSources
           sourceIndices:(NSArray<NSNumber *> *)sourceIndices
              selfIndex:(NSUInteger)selfIndex
                  report:(NSMutableArray<NSString *> *)report {
    for (FYInlineCandidate *candidate in candidates) {
        if (!FYInlineRectContainsRect(viewport, candidate.frame)) {
            candidate.rejection = @"超出可见区域";
            candidate.hardRejection = YES;
            continue;
        }
        if (candidate.anchor != FYInlineAnchorOverlay) {
            // 位移有界：不许漂到别的条目附近。
            CGFloat maxDrift = MAX(NSHeight(placement.sourceFrame), NSHeight(candidate.frame)) + self.panelGap + 4;
            if (candidate.distance > maxDrift) {
                candidate.rejection = @"离原文过远";
                candidate.hardRejection = YES;
                continue;
            }
        }
        // 覆盖自身正文是允许的；压到**别的**块才不合法。这里只记下最大交叠厚度：
        // 是否真的非法由统一安排阶段结合「上一帧是否用同一个锚定方向」判定，
        // 这样 1~3px 的抖动不会让贴片在下方/上方之间来回跳。
        for (NSUInteger index = 0; index < otherSources.count; index++) {
            if (index == selfIndex) { continue; }
            CGRect other = otherSources[index].rectValue;
            if (NSWidth(other) < 2 || NSHeight(other) < 2) { continue; }
            if (!CGRectIntersectsRect(candidate.frame, other)) { continue; }
            CGRect hit = CGRectIntersection(candidate.frame, other);
            CGFloat depth = (hit.size.width > 0 && hit.size.height > 0) ? MIN(hit.size.width, hit.size.height) : 0;
            if (depth > candidate.occlusionDepth) {
                candidate.occlusionDepth = depth;
                candidate.rejection = [NSString stringWithFormat:@"遮挡第 %@ 个原文块（%.0fpt）",
                                       sourceIndices[index], depth];
            }
        }
    }
    for (FYInlineCandidate *candidate in candidates) {
        if (candidate.rejection.length > 0) {
            [report addObject:[NSString stringWithFormat:@"%@：%@", candidate.name, candidate.rejection]];
        }
    }
}

#pragma mark 细缝消解

/// 候选与其它原文块只差 1~容差 点的细缝时：不直接接受重叠，也不因此换锚点，
/// 而是沿垂直方向做 ≤ 容差 的微移把它消掉 —— 既严格不遮挡别的块，又保持锚定方向与位置稳定。
- (FYInlineCandidate *)candidate:(FYInlineCandidate *)candidate
          resolvingSliverWithin:(CGFloat)tolerance
                       viewport:(CGRect)viewport
                     placement:(FYInlinePlacement *)placement
                   otherSources:(NSArray<NSValue *> *)otherSources
                    placedFrames:(NSArray<NSValue *> *)placedFrames {
    if (candidate.occlusionDepth <= 0 || candidate.occlusionDepth > tolerance) { return nil; }
    CGFloat step = candidate.occlusionDepth + 0.5;
    for (NSNumber *shift in @[@(step), @(-step)]) {
        CGRect moved = NSOffsetRect(candidate.frame, 0, shift.doubleValue);
        if (fabs(shift.doubleValue) > tolerance + 0.5) { continue; }
        if (!FYInlineRectContainsRect(viewport, moved)) { continue; }
        if (candidate.anchor != FYInlineAnchorOverlay) {
            CGFloat maxDrift = MAX(NSHeight(placement.sourceFrame), NSHeight(moved)) + self.panelGap + 4;
            CGFloat distance = MAX(0, MAX(CGRectGetMinY(placement.sourceFrame) - CGRectGetMaxY(moved),
                                          CGRectGetMinY(moved) - CGRectGetMaxY(placement.sourceFrame)));
            if (distance > maxDrift) { continue; }
        }
        BOOL blocked = NO;
        for (NSValue *value in otherSources) {
            if (CGRectIntersectsRect(moved, value.rectValue)) { blocked = YES; break; }
        }
        if (blocked) { continue; }
        for (NSValue *value in placedFrames) {
            if (CGRectIntersectsRect(moved, value.rectValue)) { blocked = YES; break; }
        }
        if (blocked) { continue; }
        FYInlineCandidate *resolved = [FYInlineCandidate new];
        resolved.anchor = candidate.anchor;
        resolved.anchorRank = candidate.anchorRank;
        resolved.compact = candidate.compact;
        resolved.name = candidate.name;
        resolved.frame = moved;
        resolved.distance = candidate.distance;
        resolved.scrollable = candidate.scrollable;
        resolved.measuredContentHeight = candidate.measuredContentHeight;
        resolved.bodyViewportHeight = candidate.bodyViewportHeight;
        resolved.occlusionDepth = 0;
        return resolved;
    }
    return nil;
}

#pragma mark 评分

- (CGFloat)scoreForCandidate:(FYInlineCandidate *)candidate
                   placement:(FYInlinePlacement *)placement
                    previous:(FYInlinePlacement *)previous
              columnAnchors:(NSDictionary<NSNumber *, NSNumber *> *)columnAnchors
                    columnKey:(NSNumber *)columnKey {
    CGFloat score = candidate.anchorRank * 42.0 + candidate.distance;
    if (previous) {
        if (previous.anchor == candidate.anchor) { score -= 30.0; }
        CGRect previousFrame = previous.translationFrame;
        score += fabs(CGRectGetMidY(previousFrame) - CGRectGetMidY(candidate.frame)) * 0.35;
        score += fabs(CGRectGetMidX(previousFrame) - CGRectGetMidX(candidate.frame)) * 0.15;
    }
    NSNumber *columnAnchor = columnAnchors[columnKey];
    if (columnAnchor && columnAnchor.integerValue == (NSInteger)candidate.anchor) { score -= 24.0; }
    if (columnAnchor && columnAnchor.integerValue != (NSInteger)candidate.anchor) { score += 14.0; }
    return score;
}

- (NSNumber *)columnKeyForSourceFrame:(CGRect)sourceFrame viewport:(CGRect)viewport {
    CGFloat x = NSWidth(viewport) > 0 ? (NSMidX(sourceFrame) - NSMinX(viewport)) / NSWidth(viewport) : 0.5;
    return @((NSInteger)floor(FYInlineClamp(x, 0, 0.999) * 4.0));   // 画面横向 4 等分作为“列”的粗分桶
}

#pragma mark 主入口

- (FYInlineLayoutResult *)layoutRequests:(NSArray<FYInlineLayoutRequest *> *)requests
                                viewport:(CGRect)viewport
                                previous:(FYInlineLayoutResult *)previous {
    FYInlineLayoutResult *result = [FYInlineLayoutResult new];
    if (NSWidth(viewport) < 2 || NSHeight(viewport) < 2 || requests.count == 0) {
        result.placements = @[];
        result.changedFromPrevious = previous != nil && previous.placements.count > 0;
        result.revision = ++self.revision;
        return result;
    }

    NSMutableArray<NSValue *> *sourceFrames = [NSMutableArray array];
    NSMutableArray<NSNumber *> *sourceIndices = [NSMutableArray array];
    for (NSUInteger index = 0; index < requests.count; index++) {
        [sourceFrames addObject:[NSValue valueWithRect:requests[index].sourceFrame]];
        [sourceIndices addObject:@(index + 1)];
    }

    // ① 帧间身份稳定 + 单块测量 + 候选生成
    NSMutableArray<FYInlinePlacement *> *placements = [NSMutableArray array];
    NSMutableArray<NSArray<FYInlineCandidate *> *> *candidateLists = [NSMutableArray array];
    NSMutableSet<NSString *> *claimedPreviousIDs = [NSMutableSet set];
    for (NSUInteger requestIndex = 0; requestIndex < requests.count; requestIndex++) {
        FYInlineLayoutRequest *request = requests[requestIndex];
        NSString *stableID = nil;
        if (previous) {
            stableID = [FYInlineBlockMatcher stableBlockIDForBlock:request.block
                                                              text:request.block.text
                                                       sourceFrame:request.sourceFrame
                                                    previousResult:previous];
            if (stableID.length > 0 && [claimedPreviousIDs containsObject:stableID]) { stableID = nil; }
            if (stableID.length > 0) { [claimedPreviousIDs addObject:stableID]; }
        }
        if (stableID.length == 0) { stableID = request.block.blockID; }
        FYInlinePlacement *placement = [self basePlacementForRequest:request stableID:stableID viewport:viewport];
        placement.blockID = stableID;

        NSMutableArray<NSString *> *report = [NSMutableArray array];
        if (request.translation.length == 0) {
            placement.mode = FYInlineDisplayModeUnplaceable;
            placement.reason = @"没有译文可显示";
            placement.rejectedCandidates = report;
            [placements addObject:placement];
            [candidateLists addObject:@[]];
            continue;
        }

        BOOL compact = NO;
        if (request.block.kind == FYInlineBlockKindLong) {
            compact = [self prepareLongPlacementForRequest:request placement:placement viewport:viewport];
        } else {
            [self prepareShortPlacement:placement sourceText:request.block.text viewport:viewport];
        }
        if (request.manuallyPlaced) {
            // 用户拖动过的块：位置＝原文锚点 + 手动偏移，只夹到可见区域内；
            // 不参与候选评分，也不因为它压到别的原文块就被拉回去（那是用户的选择）。
            NSRect frame = placement.translationFrame;
            frame.origin.x = NSMinX(request.sourceFrame) + request.manualOffset.width;
            frame.origin.y = NSMinY(request.sourceFrame) + request.manualOffset.height;
            frame.origin.x = FYInlineClamp(frame.origin.x, NSMinX(viewport) + self.viewportMargin,
                                           MAX(NSMinX(viewport) + self.viewportMargin,
                                               NSMaxX(viewport) - self.viewportMargin - NSWidth(frame)));
            frame.origin.y = FYInlineClamp(frame.origin.y, NSMinY(viewport) + self.viewportMargin,
                                           MAX(NSMinY(viewport) + self.viewportMargin,
                                               NSMaxY(viewport) - self.viewportMargin - NSHeight(frame)));
            placement.translationFrame = NSIntegralRect(frame);
            placement.manuallyPlaced = YES;
            placement.anchor = FYInlineAnchorManual;
            placement.compactEntry = compact;
            if (compact) {
                placement.mode = FYInlineDisplayModeCompactEntry;
            } else if (request.block.kind == FYInlineBlockKindLong) {
                placement.mode = placement.scrollable ? FYInlineDisplayModeScrollingCard : FYInlineDisplayModeFullCard;
            } else {
                placement.mode = FYInlineDisplayModeShortLabel;
            }
            placement.reason = [NSString stringWithFormat:@"手动位置（相对原文锚点 %.0f, %.0f）",
                                placement.translationFrame.origin.x - NSMinX(request.sourceFrame),
                                placement.translationFrame.origin.y - NSMinY(request.sourceFrame)];
            [placements addObject:placement];
            [candidateLists addObject:@[]];
            continue;
        }
        // 紧凑入口的候选同样要过边界与冲突检查：没有合法位置就标记“暂不可放置”。
        NSArray<FYInlineCandidate *> *candidates = [self candidatesForPlacement:placement viewport:viewport
                                                                   compactEntry:compact
                                                                         widths:@[@(NSWidth(placement.translationFrame))]];
        [self filterCandidates:candidates placement:placement viewport:viewport
                  otherSources:sourceFrames sourceIndices:sourceIndices
                     selfIndex:requestIndex report:report];
        placement.rejectedCandidates = report;
        [candidateLists addObject:candidates];
        [placements addObject:placement];
    }

    // ② 统一安排：先处理候选最少（最受限）的块，再按阅读顺序；
    //    合法优先，冲突的候选直接不可用 —— 不靠降低评分来允许跨栏或压扁。
    NSMutableArray<NSNumber *> *order = [NSMutableArray array];
    for (NSUInteger index = 0; index < placements.count; index++) { [order addObject:@(index)]; }
    [order sortUsingComparator:^NSComparisonResult(NSNumber *left, NSNumber *right) {
        NSUInteger leftLegal = 0, rightLegal = 0;
        for (FYInlineCandidate *candidate in candidateLists[left.unsignedIntegerValue]) { if (!candidate.hardRejection && candidate.occlusionDepth <= 0.5) { leftLegal++; } }
        for (FYInlineCandidate *candidate in candidateLists[right.unsignedIntegerValue]) { if (!candidate.hardRejection && candidate.occlusionDepth <= 0.5) { rightLegal++; } }
        if (leftLegal != rightLegal) { return leftLegal < rightLegal ? NSOrderedAscending : NSOrderedDescending; }
        return left.unsignedIntegerValue < right.unsignedIntegerValue ? NSOrderedAscending : NSOrderedDescending;
    }];

    NSMutableArray<NSValue *> *placedFrames = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, NSNumber *> *columnAnchors = [NSMutableDictionary dictionary];
    for (NSNumber *number in order) {
        NSUInteger index = number.unsignedIntegerValue;
        FYInlinePlacement *placement = placements[index];
        if (placement.mode == FYInlineDisplayModeUnplaceable) { continue; }
        if (placement.manuallyPlaced) {
            // 手动位置先占位，后面的候选会避开它。
            [placedFrames addObject:[NSValue valueWithRect:placement.translationFrame]];
            continue;
        }
        NSArray<FYInlineCandidate *> *candidates = candidateLists[index];
        FYInlinePlacement *previousPlacement = [previous placementForBlockID:placement.blockID];
        NSNumber *columnKey = [self columnKeyForSourceFrame:placement.sourceFrame viewport:viewport];

        // 合法性与帧间稳定在此合流：
        //   · 压到别的原文块/别的译文一律非法；
        //   · 但 1~stabilityTolerance 点的细缝先尝试“微移消解”，避免 OCR 抖动让锚点翻面。
        FYInlineCandidate *chosen = nil;
        for (FYInlineCandidate *loopCandidate in candidates) {
            if (loopCandidate.hardRejection) { continue; }
            FYInlineCandidate *candidate = loopCandidate;
            FYInlineCandidate *usable = candidate;
            if (candidate.occlusionDepth > 0) {
                usable = [self candidate:candidate resolvingSliverWithin:self.stabilityTolerance
                                viewport:viewport placement:placement
                            otherSources:sourceFrames placedFrames:placedFrames];
                if (!usable) { continue; }
            }
            BOOL conflict = NO;
            for (NSValue *value in placedFrames) {
                CGRect hit = CGRectIntersection(value.rectValue, usable.frame);
                if (CGRectIsNull(hit) || CGRectIsEmpty(hit)) { continue; }
                if (MIN(hit.size.width, hit.size.height) > 0) { conflict = YES; break; }
            }
            if (conflict) {
                FYInlineCandidate *resolved = [self candidate:usable resolvingSliverWithin:self.stabilityTolerance
                                                     viewport:viewport placement:placement
                                                 otherSources:sourceFrames placedFrames:placedFrames];
                if (resolved) { usable = resolved; } else { continue; }
            }
            if (!chosen || [self scoreForCandidate:usable placement:placement previous:previousPlacement
                                     columnAnchors:columnAnchors columnKey:columnKey] <
                           [self scoreForCandidate:chosen placement:placement previous:previousPlacement
                                     columnAnchors:columnAnchors columnKey:columnKey]) {
                chosen = usable;
            }
        }

        if (!chosen) {
            // ③ 明确降级：长卡先给紧凑入口，再不行标记“暂不可放置”，绝不强盖别的条目。
            if (placement.block.kind == FYInlineBlockKindLong) {
                NSMutableArray<NSString *> *compactReport = [placement.rejectedCandidates mutableCopy] ?: [NSMutableArray array];
                FYInlineCandidate *compact = [self bestCompactCandidateForPlacement:placement viewport:viewport
                                                                      placedFrames:placedFrames sourceFrames:sourceFrames
                                                                     sourceIndices:sourceIndices
                                                                         selfIndex:index report:compactReport];
                placement.rejectedCandidates = compactReport;
                if (compact) {
                    placement.mode = FYInlineDisplayModeCompactEntry;
                    placement.anchor = FYInlineAnchorCompactEntry;
                    placement.compactEntry = YES;
                    placement.translationFrame = compact.frame;
                    placement.reason = @"没有合法的长卡位置：改为「查看译文」紧凑入口，点击展开完整阅读卡";
                } else {
                    placement.mode = FYInlineDisplayModeUnplaceable;
                    placement.reason = @"所有候选都会遮挡其它原文块或互相冲突：本块暂不可放置（译文仍在主界面列出）";
                    placement.translationFrame = NSZeroRect;
                }
            } else {
                placement.mode = FYInlineDisplayModeUnplaceable;
                placement.reason = @"所有候选都会遮挡其它原文块或互相冲突：本块暂不可放置（译文仍在主界面列出）";
                placement.translationFrame = NSZeroRect;
            }
        } else {
            placement.translationFrame = chosen.frame;
            placement.anchor = chosen.anchor;
            if (placement.compactEntry) {
                placement.mode = FYInlineDisplayModeCompactEntry;
            } else if (placement.block.kind == FYInlineBlockKindLong) {
                placement.mode = placement.scrollable ? FYInlineDisplayModeScrollingCard : FYInlineDisplayModeFullCard;
            } else {
                placement.mode = FYInlineDisplayModeShortLabel;
            }
            if (placement.compactEntry) {
                placement.reason = [NSString stringWithFormat:@"%@：画面放不下可读的三行正文，这里给「查看译文」紧凑入口", chosen.name];
                [placedFrames addObject:[NSValue valueWithRect:placement.translationFrame]];
                continue;
            }
            placement.bodyViewportHeight = chosen.bodyViewportHeight;
            placement.reason = [NSString stringWithFormat:@"%@，%@", chosen.name,
                                placement.mode == FYInlineDisplayModeScrollingCard ? @"正文超出视口、卡内滚动" :
                                (placement.mode == FYInlineDisplayModeFullCard ? @"完整正文一屏可见" : @"贴合译文宽度")];
            if (placement.block.kind == FYInlineBlockKindLong && !placement.scrollable) {
                placement.reason = [NSString stringWithFormat:@"%@，按完整译文计算高度", chosen.name];
            }
            columnAnchors[columnKey] = @((NSInteger)chosen.anchor);
        }
        if (!CGRectIsEmpty(placement.translationFrame)) {
            [placedFrames addObject:[NSValue valueWithRect:placement.translationFrame]];
        }
    }

    result.placements = placements;
    result.revision = ++self.revision;
    result.changedFromPrevious = [self result:result differsFromPrevious:previous];
    return result;
}

/// 长卡的宽度与高度测量。返回 YES 表示这一块只能给紧凑入口
/// （画面连可读的三行正文都放不下）。
- (BOOL)prepareLongPlacementForRequest:(FYInlineLayoutRequest *)request
                             placement:(FYInlinePlacement *)placement
                              viewport:(CGRect)viewport {
    NSFont *font = [self fontOfSize:self.longBodyFontSize weight:NSFontWeightRegular];
    placement.font = font;
    placement.paragraphStyle = [self paragraphStyleWithLineSpacing:self.longLineSpacing];
    // 先落定内边距与标题带：下面的宽度候选测量必须用和最终绘制完全相同的正文宽度，
    // 否则“要不要换更宽候选”会按错误的文字宽度判断。
    placement.panelPadding = 18;
    placement.titleBandHeight = 24 + 13;
    placement.cornerRadius = 12;

    CGFloat minimumHeight = [self minimumCardHeight];
    CGFloat windowInner = NSHeight(viewport) - 24;
    if (windowInner < minimumHeight) {
        // 连三行正文都放不下：给明确的紧凑入口，不生成细条、不静默丢弃。
        CGFloat available = MAX((CGFloat)60, NSWidth(viewport) - self.viewportMargin * 2);
        CGFloat width = MIN(MAX((CGFloat)180, NSWidth(request.sourceFrame)), available);
        placement.translationFrame = NSMakeRect(0, 0, width, self.compactEntryHeight);
        placement.mode = FYInlineDisplayModeCompactEntry;
        placement.compactEntry = YES;
        placement.scrollable = NO;
        placement.measuredContentHeight = [self measuredBodyHeight:placement.translation placement:placement
                                                             width:MAX((CGFloat)180, NSWidth(request.sourceFrame))];
        placement.bodyViewportHeight = 0;
        placement.reason = @"画面放不下可读的三行正文：使用紧凑入口";
        return YES;
    }
    NSArray<NSNumber *> *widths = [self cardWidthCandidatesForSource:request.sourceFrame viewport:viewport];
    CGFloat cap = MIN(self.cardMaxHeight, NSHeight(viewport) * self.cardHeightFraction);
    // 基准宽度放不下完整译文时，允许再试一个更宽的有限候选（减少不必要的滚动），
    // 但绝不靠缩小字号去塞。
    if ([self measuredBodyHeight:placement.translation placement:placement width:widths.firstObject.doubleValue] > cap) {
        widths = [self cardWidthCandidatesForSource:request.sourceFrame viewport:viewport wide:YES];
    }
    [self prepareLongPlacement:placement widthCandidates:widths windowInner:windowInner cap:cap
                     minHeight:minimumHeight];
    return NO;
}

- (NSArray<NSNumber *> *)cardWidthCandidatesForSource:(CGRect)sourceFrame viewport:(CGRect)viewport wide:(BOOL)wide {
    CGFloat available = MAX((CGFloat)200, NSWidth(viewport) - 24);
    CGFloat desired = MAX(NSWidth(sourceFrame), 300);
    CGFloat fraction = wide ? self.cardWideFraction : self.cardWidthFraction;
    CGFloat base = MIN(desired, MIN(self.cardMaxWidth, MIN(available, NSWidth(viewport) * fraction)));
    base = MAX(base, MIN((CGFloat)260, available));
    return @[@(base)];
}

- (NSArray<NSNumber *> *)cardWidthCandidatesForSource:(CGRect)sourceFrame viewport:(CGRect)viewport {
    return [self cardWidthCandidatesForSource:sourceFrame viewport:viewport wide:NO];
}

- (FYInlineCandidate *)bestCompactCandidateForPlacement:(FYInlinePlacement *)placement
                                               viewport:(CGRect)viewport
                                           placedFrames:(NSArray<NSValue *> *)placedFrames
                                           sourceFrames:(NSArray<NSValue *> *)sourceFrames
                                          sourceIndices:(NSArray<NSNumber *> *)sourceIndices
                                              selfIndex:(NSUInteger)selfIndex
                                                 report:(NSMutableArray<NSString *> *)report {
    NSArray<FYInlineCandidate *> *candidates = [self candidatesForPlacement:placement viewport:viewport compactEntry:YES
                                                                       widths:@[@(NSWidth(placement.translationFrame))]];
    [self filterCandidates:candidates placement:placement viewport:viewport otherSources:sourceFrames
             sourceIndices:sourceIndices selfIndex:selfIndex report:report];
    FYInlineCandidate *best = nil;
    for (FYInlineCandidate *candidate in candidates) {
        if (candidate.hardRejection || candidate.occlusionDepth > 0) { continue; }
        BOOL conflict = NO;
        for (NSValue *value in placedFrames) {
            if (CGRectIntersectsRect(value.rectValue, candidate.frame)) { conflict = YES; break; }
        }
        if (conflict) { continue; }
        if (!best || candidate.anchorRank < best.anchorRank) { best = candidate; }
    }
    return best;
}

- (BOOL)result:(FYInlineLayoutResult *)result differsFromPrevious:(FYInlineLayoutResult *)previous {
    if (!previous) { return YES; }
    if (previous.placements.count != result.placements.count) { return YES; }
    for (NSUInteger index = 0; index < result.placements.count; index++) {
        FYInlinePlacement *now = result.placements[index];
        FYInlinePlacement *before = previous.placements[index];
        if (![now.blockID isEqualToString:before.blockID]) { return YES; }
        if (now.mode != before.mode) { return YES; }
        if (![now.translation isEqualToString:before.translation]) { return YES; }
        if (!NSEqualRects(now.translationFrame, before.translationFrame)) { return YES; }
        if (fabs(now.measuredContentHeight - before.measuredContentHeight) > 0.5) { return YES; }
    }
    return NO;
}

@end
