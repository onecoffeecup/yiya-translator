#import "FYContentPolicy.h"
#import <math.h>

@interface FYContentRoute ()
@property(nonatomic, copy) NSArray<OCRTextItem *> *bandItems;
@property(nonatomic, copy) NSArray<OCRTextItem *> *dialogueItems;
@property(nonatomic, copy) NSArray<OCRTextItem *> *optionItems;
@property(nonatomic, copy) NSString *dialogueText;
@property(nonatomic) BOOL speakerLabelOnly;
@property(nonatomic) BOOL usedFullFrameFallback;
@property(nonatomic, copy) NSString *reason;
@end
@implementation FYContentRoute
@end

static BOOL FYDialogueSameBaseline(OCRTextItem *left, OCRTextItem *right) {
    if (left == right || left.speakerLabel || right.speakerLabel || left.lineCount > 1 || right.lineCount > 1 ||
        [left.text rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound ||
        [right.text rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) return NO;
    CGRect x = left.boundingBox, y = right.boundingBox;
    CGFloat smallHeight = MIN(x.size.height,y.size.height), largeHeight = MAX(x.size.height,y.size.height);
    return x.size.width > 0 && y.size.width > 0 && smallHeight > 0 && smallHeight >= largeHeight * .70 &&
        fabs(CGRectGetMidY(x)-CGRectGetMidY(y)) <= smallHeight * .25;
}
static BOOL FYDialogueAdjacentRowFragments(OCRTextItem *left, OCRTextItem *right) {
    if (!FYDialogueSameBaseline(left,right)) return NO;
    NSString *a = FYNormalizeOCRTextForComparison(left.text), *b = FYNormalizeOCRTextForComparison(right.text);
    if (!a.length || !b.length || MIN(a.length,b.length) > 6 || MAX(a.length,b.length) < 4 ||
        ![FYContentPolicy containsJapaneseKana:a.length >= b.length ? a : b]) return NO;
    CGRect x = left.boundingBox, y = right.boundingBox;
    CGFloat gap = MAX(CGRectGetMinX(x),CGRectGetMinX(y)) - MIN(CGRectGetMaxX(x),CGRectGetMaxX(y));
    // Small overlap tolerates OCR box edges; larger overlap is a competing
    // observation, not another word in the same row.
    CGFloat glyphWidth = MIN(x.size.width/a.length,y.size.width/b.length);
    return gap >= -MIN(x.size.width,y.size.width)*.15 && gap <= MIN(.02,glyphWidth*.75);
}


@implementation FYContentPolicy (DialogueRouting)
+ (FYContentRoute *)dialogueRouteForItems:(NSArray<OCRTextItem *> *)items
                  optionsCanPasteInline:(BOOL)optionsCanPasteInline
                         filterObserver:(FYContentTextFilterObserver)observer {
    NSArray<OCRTextItem *> *band = [self subtitleBandItems:items];
    NSMutableArray<OCRTextItem *> *dialogue = [NSMutableArray array];
    NSMutableArray<OCRTextItem *> *options = [NSMutableArray array];
    if (optionsCanPasteInline) {
        [self splitDialogueAndOptions:band allBlocks:items dialogue:dialogue options:options];
    } else { [dialogue addObjectsFromArray:band]; }
    FYContentRoute *result = [FYContentRoute new];
    result.bandItems = band;
    result.dialogueItems = dialogue;
    result.optionItems = options;
    result.usedFullFrameFallback = dialogue.count == 0;
    BOOL speakerOnly = NO;
    result.dialogueText = [self dialogueTextFromItems:dialogue.count > 0 ? dialogue : items
                                   speakerLabelOnly:&speakerOnly filterObserver:observer];
    result.speakerLabelOnly = speakerOnly;
    result.reason = result.usedFullFrameFallback ? @"full_frame_fallback"
        : (!optionsCanPasteInline ? @"options_mapping_unavailable"
           : (options.count > 0 ? @"dialogue_with_options" : @"dialogue_only"));
    return result;
}

+ (NSString *)dialogueTextFromItems:(NSArray<OCRTextItem *> *)items
                  speakerLabelOnly:(BOOL *)speakerLabelOnly
                    filterObserver:(FYContentTextFilterObserver)observer {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    OCRTextItem *previous = nil;
    for (OCRTextItem *item in items) {
        // A pixel-confirmed name plate is metadata, not a spoken short line.
        // Exclude both recognized names and plate OCR noise from the body.
        // Ordinary spoken lines retain their text, including character names.
        if ([self isExcludedSpeakerLabelItem:item]) { continue; }
        if ([self isCornerHelpButton:item] || [self isFurigana:item nearLargerLineInItems:items]) { continue; }
        FYContentTextFilterReason reason = [self filterReasonForText:item.text
            normalized:FYNormalizeOCRTextForComparison(item.text) boundingBox:item.boundingBox strict:YES];
        if (reason != FYContentTextKeep) {
            if (observer) { observer(item.text, item.boundingBox, reason); }
            continue;
        }
        if (previous && FYDialogueAdjacentRowFragments(previous,item)) {
            lines[lines.count-1] = [lines.lastObject stringByAppendingString:item.text];
        } else { [lines addObject:item.text]; }
        previous = item;
    }
    if (speakerLabelOnly) { *speakerLabelOnly = [self dialogueFrameIsSpeakerLabelOnly:lines]; }
    return [self dialogueTextWithoutTrailingButton:[lines componentsJoinedByString:@"\n"]];
}

+ (BOOL)isExcludedSpeakerLabelItem:(OCRTextItem *)item {
    return item.speakerLabel;
}

+ (NSTimeInterval)recognitionPollingIntervalForMode:(NSInteger)mode {
    return mode == FYContentModeDialogue ? 0.5 : 1.2;
}

+ (NSTimeInterval)translationAttemptThrottleForMode:(NSInteger)mode {
    return mode == FYContentModeUI ? 1.2 : 4.0;
}

+ (BOOL)looksLikeSpeakerName:(NSString *)raw {
    NSString *text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length == 0 || text.length > 10) { return NO; }
    NSCharacterSet *enders = [NSCharacterSet characterSetWithCharactersInString:@"。．.！!？?"];
    if ([enders characterIsMember:[text characterAtIndex:text.length - 1]]) { return NO; }
    BOOL hasNameGlyph = NO;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        // 带平假名的一律不是名字行（`うん、空いてるよ` / `我の手落ちだ` 都要留作正文）。
        if (character >= 0x3040 && character <= 0x309F) { return NO; }
        if ((character >= 0x4E00 && character <= 0x9FFF) ||
            (character >= 0x30A0 && character <= 0x30FF)) { hasNameGlyph = YES; }
    }
    return hasNameGlyph;
}

+ (BOOL)looksLikeSpeakerFurigana:(NSString *)raw {
    NSString *text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length < 2 || text.length > 12) { return NO; }
    NSCharacterSet *enders = [NSCharacterSet characterSetWithCharactersInString:@"。．.！!？?"];
    if ([enders characterIsMember:[text characterAtIndex:text.length - 1]]) { return NO; }
    NSUInteger kana = 0, glyphs = 0;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if (character == ' ' || character == '\t') { continue; }
        glyphs += 1;
        if ((character >= 0x3040 && character <= 0x30FF) ||
            (character >= 0x31F0 && character <= 0x31FF)) { kana += 1; }
    }
    return glyphs > 0 && kana * 10 >= glyphs * 6;
}

+ (BOOL)looksLikeSpeakerLabelCluster:(NSArray<OCRTextItem *> *)cluster {
    if (cluster.count == 0 || cluster.count > 3) { return NO; }
    BOOL hasName = NO;
    CGFloat widest = 0;
    for (OCRTextItem *item in cluster) {
        widest = MAX(widest, item.boundingBox.size.width);
        if ([self looksLikeSpeakerName:item.text]) { hasName = YES; continue; }
        if (![self looksLikeSpeakerFurigana:item.text]) { return NO; }
    }
    return hasName && widest <= 0.35;
}

+ (BOOL)isSpeakerLabelItem:(OCRTextItem *)item inPool:(NSArray<OCRTextItem *> *)pool {
    if (item.speakerLabel) { return YES; }
    if ([self looksLikeSpeakerName:item.text]) { return item.boundingBox.size.width <= 0.35; }
    if (![self looksLikeSpeakerFurigana:item.text]) { return NO; }
    for (OCRTextItem *other in pool) {
        if (other == item || ![self looksLikeSpeakerName:other.text]) { continue; }
        // 底左原点：注音的 midY 更大（更靠上），名字紧贴在它下面。
        if (CGRectGetMidY(other.boundingBox) >= CGRectGetMidY(item.boundingBox)) { continue; }
        if (CGRectGetMidY(item.boundingBox) - CGRectGetMaxY(other.boundingBox) > 0.05) { continue; }
        CGFloat overlap = MIN(CGRectGetMaxX(item.boundingBox), CGRectGetMaxX(other.boundingBox)) -
                          MAX(CGRectGetMinX(item.boundingBox), CGRectGetMinX(other.boundingBox));
        if (overlap >= item.boundingBox.size.width * 0.5) { return YES; }
    }
    return NO;
}

+ (BOOL)dialogueFrameIsSpeakerLabelOnly:(NSArray<NSString *> *)lines {
    if (lines.count == 0) { return NO; }
    BOOL hasName = NO;
    for (NSString *line in lines) {
        if ([self looksLikeSpeakerName:line]) { hasName = YES; continue; }
        if ([self looksLikeSpeakerFurigana:line]) { continue; }
        return NO;
    }
    return hasName;
}

+ (void)splitDialogueAndOptions:(NSArray<OCRTextItem *> *)band
                     allBlocks:(NSArray<OCRTextItem *> *)allBlocks
                      dialogue:(NSMutableArray<OCRTextItem *> *)outDialogue
                       options:(NSMutableArray<OCRTextItem *> *)outOptions {
    if (band.count == 0) { return; }

    // Reuse the region that protected this mixed frame from menu classification.
    // A nearby name plate must not bridge the lowest option into the body.
    NSArray<OCRTextItem *> *separatedBody = [self separatedDialogueItemsInItems:allBlocks ?: band];
    // band 已按从上到下排序；这里切成簇
    NSMutableArray<NSMutableArray<OCRTextItem *> *> *clusters = [NSMutableArray array];
    NSMutableArray<OCRTextItem *> *current = nil;
    for (OCRTextItem *item in band) {
        if (!current) {
            current = [NSMutableArray arrayWithObject:item];
            [clusters addObject:current];
            continue;
        }
        CGFloat gap = fabs(CGRectGetMidY(current.lastObject.boundingBox) - CGRectGetMidY(item.boundingBox));
        BOOL crossesBody = separatedBody.count > 0 &&
            [separatedBody containsObject:current.lastObject] != [separatedBody containsObject:item];
        if (gap <= 0.12 && !crossesBody) {
            [current addObject:item];
        } else {
            current = [NSMutableArray arrayWithObject:item];
            [clusters addObject:current];
        }
    }

    // 簇里最宽的一条所在位置，就是这一簇贴在画面的哪一带
    NSMutableArray<NSNumber *> *clusterWidths = [NSMutableArray array];
    for (NSMutableArray<OCRTextItem *> *cluster in clusters) {
        CGFloat widest = 0;
        for (OCRTextItem *item in cluster) { widest = MAX(widest, item.boundingBox.size.width); }
        [clusterWidths addObject:@(widest)];
    }

    // 选“对白簇”：最宽的成型行在画面下半部的那个簇；没有就退回整屏最宽的一条所在的簇
    NSInteger dialogueCluster = -1;
    CGFloat bestWidth = -1;
    for (NSUInteger index = 0; index < clusters.count; index++) {
        NSMutableArray<OCRTextItem *> *cluster = clusters[index];
        for (OCRTextItem *item in cluster) {
            if (![self isFormedTextLine:item]) { continue; }
            if (CGRectGetMidY(item.boundingBox) > 0.42) { continue; }
            if (item.boundingBox.size.width > bestWidth) {
                bestWidth = item.boundingBox.size.width;
                dialogueCluster = (NSInteger)index;
            }
        }
    }
    if (dialogueCluster < 0) {
        for (NSUInteger index = 0; index < clusters.count; index++) {
            CGFloat widest = clusterWidths[index].doubleValue;
            if (widest > bestWidth) {
                bestWidth = widest;
                dialogueCluster = (NSInteger)index;
            }
        }
    }

    // 名字/注音框紧贴在对白框上方，却会被拆成独立一簇丢进「选项」。
    // 实测 `萩尾九段`（名字框）就被标成「选项」单独记了一条学习记录。
    // 这里把它连同紧邻上方的注音一起并回对白框。
    NSInteger labelRunStart = dialogueCluster;
    while (labelRunStart > 0 && [self looksLikeSpeakerLabelCluster:clusters[labelRunStart - 1]]) { labelRunStart -= 1; }

    for (NSUInteger index = 0; index < clusters.count; index++) {
        if ((NSInteger)index >= labelRunStart && (NSInteger)index <= dialogueCluster) {
            if (outDialogue) { [outDialogue addObjectsFromArray:clusters[index]]; }
        } else {
            if (outOptions) { [outOptions addObjectsFromArray:clusters[index]]; }
        }
    }

    // 选项区离对白框往往比较远，band 的“紧收拢”会把它整个漏掉。
    // 这里补一遍：把 band 之外、但和对白框**水平对齐**的行也当作选项收进来。
    // 对齐标准取得比较严（重叠 ≥ 较窄那条的 55%），因为街景招牌通常只和对白框擦边。
    if (outOptions && dialogueCluster >= 0) {
        OCRTextItem *dialogueAnchor = nil;
        CGFloat anchorWidth = 0;
        for (OCRTextItem *item in clusters[dialogueCluster]) {
            if (item.boundingBox.size.width > anchorWidth) {
                anchorWidth = item.boundingBox.size.width;
                dialogueAnchor = item;
            }
        }
        if (dialogueAnchor) {
            NSArray<OCRTextItem *> *pool = allBlocks ?: band;
            for (OCRTextItem *item in pool) {
                if ([outOptions containsObject:item]) { continue; }
                if ([clusters[dialogueCluster] containsObject:item]) { continue; }
                if (FYNormalizeOCRTextForComparison(item.text).length < 2) { continue; }
                if (item.boundingBox.size.width < 0.10) { continue; }
                // 名字框/注音不是选项：实测 `萩尾九段` 会被这条补漏收进选项，单独占一条记录。
                if ([self isSpeakerLabelItem:item inPool:pool]) { continue; }
                // 只补对白框上方的
                if (CGRectGetMidY(item.boundingBox) <= CGRectGetMidY(dialogueAnchor.boundingBox)) { continue; }
                CGFloat overlapLeft = MAX(CGRectGetMinX(item.boundingBox), CGRectGetMinX(dialogueAnchor.boundingBox));
                CGFloat overlapRight = MIN(CGRectGetMaxX(item.boundingBox), CGRectGetMaxX(dialogueAnchor.boundingBox));
                CGFloat overlap = overlapRight - overlapLeft;
                CGFloat narrower = MIN(item.boundingBox.size.width, dialogueAnchor.boundingBox.size.width);
                if (overlap <= 0 || overlap < narrower * 0.55) { continue; }
                [outOptions addObject:item];
            }
        }
    }
}

+ (BOOL)containsJapaneseKana:(NSString *)value {
    return FYContainsJapaneseKana(value);
}

+ (BOOL)isFormedTextLine:(OCRTextItem *)block {
    NSString *normalized = FYNormalizeOCRTextForComparison(block.text);
    if (normalized.length >= 8 && block.boundingBox.size.width >= 0.20) { return YES; }
    // 0.15 太贴近现实边缘：对白框被 UI 遮住一半时宽度会掉到 0.13 左右，
    // 只差一点点就被判成“不成型”，整条对白就丢了。放宽到 0.12。
    if (normalized.length >= 6 && block.boundingBox.size.width >= 0.12) { return YES; }
    return NO;
}

+ (BOOL)isShortDialogueAnchor:(OCRTextItem *)block {
    NSString *normalized = FYNormalizeOCRTextForComparison(block.text);
    if (normalized.length < 4) { return NO; }
    if (block.boundingBox.size.height < 0.026) { return NO; }
    if (CGRectGetMidY(block.boundingBox) > 0.45) { return NO; }
    if (block.boundingBox.size.width < 0.06) { return NO; }
    // 纯数字/日期样式的一小串不当对白
    return YES;
}

+ (BOOL)isUnpunctuatedSingleLineDialogue:(NSString *)text box:(CGRect)box {
    NSString *normalized = FYNormalizeOCRTextForComparison(text);
    return normalized.length >= 4 && normalized.length <= 14 && [self containsJapaneseKana:normalized] &&
        box.size.height >= 0.043 && box.size.width >= 0.08 && box.size.width <= 0.30 &&
        CGRectGetMinX(box) >= 0.18 && CGRectGetMaxX(box) <= 0.78 &&
        CGRectGetMidY(box) >= 0.10 && CGRectGetMidY(box) <= 0.38;
}

+ (BOOL)isCornerHelpButton:(OCRTextItem *)block {
    CGRect box = block.boundingBox;
    return CGRectGetMinX(box) >= 0.80 && CGRectGetMidY(box) <= 0.12 &&
        [FYNormalizeOCRTextForComparison(block.text) containsString:@"操作説明"];
}

+ (BOOL)isSingleLineDialogue:(OCRTextItem *)block {
    NSString *normalized = FYNormalizeOCRTextForComparison(block.text);
    // A central, full-height English sentence has the same placement evidence
    // as unpunctuated Japanese speech. A decimal/date or corner label does not.
    BOOL latin = [normalized rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"]].location != NSNotFound;
    CGRect box = block.boundingBox;
    if (normalized.length >= 3 && latin && [normalized hasSuffix:@"."] &&
        box.size.width >= .05 && box.size.width <= .30 && box.size.height >= .043 &&
        CGRectGetMinX(box) >= .18 && CGRectGetMaxX(box) <= .78 &&
        CGRectGetMidY(box) >= .10 && CGRectGetMidY(box) <= .38) { return YES; }
    if (normalized.length < 4) { return NO; }
    // 门槛放到 0.05：台词本来就短（实测「行くぞ。」只有 0.08 宽）。
    // 真正的防误判靠“必须以句末标点结尾”，不靠宽度。
    if (block.boundingBox.size.width < 0.05) { return NO; }
    if (block.boundingBox.size.height < 0.026) { return NO; }
    if (CGRectGetMidY(block.boundingBox) > 0.45) { return NO; }
    NSCharacterSet *enders = [NSCharacterSet characterSetWithCharactersInString:@"。！!？?…・、"];
    if ([enders characterIsMember:[normalized characterAtIndex:normalized.length - 1]]) { return YES; }
    // 视觉小说的单行台词不一定有标点；名字框也可能被 OCR 完全漏掉。
    return [self isUnpunctuatedSingleLineDialogue:normalized box:block.boundingBox];
}

+ (BOOL)isDialogueAnchor:(OCRTextItem *)block {
    if (![self isFormedTextLine:block]) { return NO; }
    if (block.boundingBox.size.height < 0.026) { return NO; }
    CGFloat midY = CGRectGetMidY(block.boundingBox);
    if (midY > 0.32) { return NO; }
    CGFloat width = block.boundingBox.size.width;
    NSUInteger length = FYNormalizeOCRTextForComparison(block.text).length;
    // A strong anchor must also satisfy the substantial-line width below.
    // Repeated ellipsis glyphs can make a narrow spoken line reach ten
    // characters; leave it to the existing short-dialogue fallback instead
    // of selecting it here and then rejecting the entire band.
    return width >= 0.22 || (length >= 10 && width >= 0.15);
}

+ (NSArray<OCRTextItem *> *)subtitleBandItems:(NSArray<OCRTextItem *> *)blocks {
    // 锚点不要只看“整屏最宽”：选项里出现「・・・・」这类省略号时可能比对白还宽，
    // 那样会把选项当锚点、真正的对白反而被排除。
    // 也**不再**退回“画面里最低的成型行” —— 那正是把密集文本 UI 误判成对白的元凶。
    // 找不到真正的对白锚点就返回空，让判别走 UI/贴译路线。
    OCRTextItem *anchor = nil;
    BOOL usedShortAnchorFallback = NO;
    for (OCRTextItem *block in blocks) {
        if (![self isDialogueAnchor:block]) { continue; }
        if (!anchor || block.boundingBox.size.width > anchor.boundingBox.size.width) { anchor = block; }
    }

    // 兜底：对白框里**通篇都是短句**时，上面一条都当不了锚点。
    // 真实例子：「思い出した。」6 字/0.13 宽 + 名字「？？？」——整框没有长行，
    // 结果字幕带为空、一个字都不翻。
    // 但不能见到短行就当对白（散落的街景招牌也是短行），
    // 所以要求它**和另一行紧挨着堆叠**：对白框的行距很紧，招牌之间不会这么近。
    // 注意：anchor 可能已经被设成一个“勉强合格”的错读（实测名字框的 `？？？`
    // 被 OCR 读成平假名 `ことと`，长度够格但其实是噪声）。
    // 这时也要走兜底 —— 否则真正的那句「思い出した。」永远进不来。
    // 判定标准是：当前 anchor **是否真的和相邻行堆叠**（孤零零一条不算对白）。
    // 只对**弱锚点**（短而窄）要求堆叠：孤零零一条短行不像对白框。
    // 长行锚点不受影响 —— 单行对白框本来就靠一条长行成立（有测试守着这一点）。
    if (anchor) {
        BOOL weakAnchor = anchor.boundingBox.size.width < 0.16
            && FYNormalizeOCRTextForComparison(anchor.text).length < 10;
        if (weakAnchor) {
            BOOL anchorStacked = NO;
            for (OCRTextItem *other in blocks) {
                if (other == anchor) { continue; }
                if (FYNormalizeOCRTextForComparison(other.text).length < 2) { continue; }
                if (fabs(CGRectGetMidY(other.boundingBox) - CGRectGetMidY(anchor.boundingBox)) >= 0.10) { continue; }
                CGFloat otherLeft = MAX(CGRectGetMinX(other.boundingBox), CGRectGetMinX(anchor.boundingBox));
                CGFloat otherRight = MIN(CGRectGetMaxX(other.boundingBox), CGRectGetMaxX(anchor.boundingBox));
                if (otherRight - otherLeft <= 0) { continue; }
                anchorStacked = YES;
                break;
            }
            // 没堆叠也要留意：它可能只是名字框，而真正的对白在下面更宽的那条
            if (!anchorStacked) {
                OCRTextItem *better = nil;
                for (OCRTextItem *other in blocks) {
                    if (other == anchor || ![self isShortDialogueAnchor:other]) { continue; }
                    if (other.boundingBox.size.width <= anchor.boundingBox.size.width) { continue; }
                    if (!better || other.boundingBox.size.width > better.boundingBox.size.width) { better = other; }
                }
                if (better) {
                    anchor = better;
                    usedShortAnchorFallback = YES;
                } else {
                    anchor = nil;
                }
            }
        }
    }

    if (!anchor) {
        // 单行对白：允许单独一条以句末标点结尾的短句当锚点
        for (OCRTextItem *block in blocks) {
            if (![self isSingleLineDialogue:block]) { continue; }
            anchor = block;
            usedShortAnchorFallback = YES;
            break;
        }
    }

    if (!anchor) {
        for (OCRTextItem *block in blocks) {
            if (![self isShortDialogueAnchor:block]) { continue; }
            CGFloat midY = CGRectGetMidY(block.boundingBox);
            BOOL stacked = NO;
            for (OCRTextItem *other in blocks) {
                if (other == block) { continue; }
                if (FYNormalizeOCRTextForComparison(other.text).length < 2) { continue; }
                if (fabs(CGRectGetMidY(other.boundingBox) - midY) >= 0.10) { continue; }
                // 同一组文字框水平上要对得上
                CGFloat overlapLeft = MAX(CGRectGetMinX(other.boundingBox), CGRectGetMinX(block.boundingBox));
                CGFloat overlapRight = MIN(CGRectGetMaxX(other.boundingBox), CGRectGetMaxX(block.boundingBox));
                if (overlapRight - overlapLeft <= 0) { continue; }
                stacked = YES;
                break;
            }
            if (!stacked) { continue; }
            if (!anchor || block.boundingBox.size.width > anchor.boundingBox.size.width) {
                anchor = block;
                usedShortAnchorFallback = YES;
            }
        }
    }
    if (!anchor) { return @[]; }

    // 兜底否决：这一组里如果没有任何“像对白”的实质长行（够宽或够长），
    // 那它就不是对白框，而是招牌/按钮之类，宁可不翻。
    BOOL hasSubstantialLine = NO;
    for (OCRTextItem *block in blocks) {
        if (block.boundingBox.size.width >= 0.20) { hasSubstantialLine = YES; break; }
        if (FYNormalizeOCRTextForComparison(block.text).length >= 8 && block.boundingBox.size.width >= 0.15) {
            hasSubstantialLine = YES;
            break;
        }
    }
    // 短句兜底路径不能再用“必须有长行”否决 —— 整框都是短句正是它要处理的情况，
    // 它已经用“和相邻行紧挨堆叠”把散落的招牌挡在外面了。
    if (!hasSubstantialLine && !usedShortAnchorFallback) { return @[]; }

    NSMutableArray<OCRTextItem *> *candidates = [NSMutableArray array];
    for (OCRTextItem *block in blocks) {
        if (block == anchor) { continue; }
        if (FYNormalizeOCRTextForComparison(block.text).length < 2) { continue; }
        // 宽度门槛故意放宽到 0.04：对白框里的短句本来就很窄
        // （实测「平気。」只有 0.06 宽、「それより、」0.10），
        // 旧门槛 0.10 会把它们直接剔除 —— 用户看到的就是“第一句没翻译”。
        // 真正防止把菜单/招牌收进来的是下面扩张循环里的“水平重叠 + 紧邻”双条件。
        if (block.boundingBox.size.width < 0.04) { continue; }
        [candidates addObject:block];
    }

    NSMutableArray<OCRTextItem *> *band = [NSMutableArray arrayWithObject:anchor];
    for (NSInteger direction = 0; direction < 2; direction++) {
        CGFloat frontierMidY = CGRectGetMidY(anchor.boundingBox);
        while (YES) {
            OCRTextItem *next = nil;
            CGFloat bestGap = CGFLOAT_MAX;
            for (OCRTextItem *candidate in candidates) {
                CGFloat gap = CGRectGetMidY(candidate.boundingBox) - frontierMidY;
                if (direction == 0 && gap >= 0) { continue; }
                if (direction == 1 && gap <= 0) { continue; }
                // 收拢窗口要“紧”：只把真正连续的相邻行算作一段。
                // 放太宽（曾经是 0.35）会把选项区和对白框连成一片，拆不分家。
                // 但仍需要一点余量：对白框里第一行常和后面几行隔得较开
                // （实测「平気。」与下一行差 0.062），窗口太紧会把首行切掉。
                if (fabs(gap) >= 0.20) { continue; }
                // 水平重叠要占较窄那一条的一半以上：同一组文字框通常对齐，
                // 而街景招牌/背景文字与对白框只是擦边重叠，会被这一条挡住。
                CGFloat overlapLeft = MAX(CGRectGetMinX(candidate.boundingBox), CGRectGetMinX(anchor.boundingBox));
                CGFloat overlapRight = MIN(CGRectGetMaxX(candidate.boundingBox), CGRectGetMaxX(anchor.boundingBox));
                CGFloat overlap = overlapRight - overlapLeft;
                CGFloat narrower = MIN(candidate.boundingBox.size.width, anchor.boundingBox.size.width);
                if (overlap <= 0 || overlap < narrower * 0.5) { continue; }
                if (fabs(gap) < bestGap) {
                    next = candidate;
                    bestGap = fabs(gap);
                }
            }
            if (!next) { break; }
            [band addObject:next];
            [candidates removeObject:next];
            frontierMidY = CGRectGetMidY(next.boundingBox);
        }
    }

    // The vertical band expansion requires horizontal overlap and a minimum
    // width. Recover same-row fragments after that expansion, including narrow
    // quoted words which satisfy neither condition.
    BOOL addedFragment;
    do {
        addedFragment = NO;
        for (OCRTextItem *block in blocks) {
            if ([band containsObject:block]) { continue; }
            for (OCRTextItem *member in [band copy]) {
                if (FYDialogueAdjacentRowFragments(block,member)) {
                    [band addObject:block];addedFragment=YES;break;
                }
            }
        }
    } while (addedFragment);

    [band sortUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) {
        if (FYDialogueSameBaseline(left,right)) {
            if (CGRectGetMinX(left.boundingBox) == CGRectGetMinX(right.boundingBox)) { return NSOrderedSame; }
            return CGRectGetMinX(left.boundingBox) < CGRectGetMinX(right.boundingBox)
                ? NSOrderedAscending : NSOrderedDescending;
        }
        CGFloat leftMidY = CGRectGetMidY(left.boundingBox);
        CGFloat rightMidY = CGRectGetMidY(right.boundingBox);
        if (fabs(leftMidY - rightMidY) < 0.01) { return NSOrderedSame; }
        // 底左原点：midY 大的在画面上方，按从上到下输出
        return leftMidY > rightMidY ? NSOrderedAscending : NSOrderedDescending;
    }];
    return band;
}

+ (BOOL)isFurigana:(OCRTextItem *)small nearLargerLineInItems:(NSArray<OCRTextItem *> *)blocks {
    CGRect box = small.boundingBox;
    NSString *text = FYNormalizeOCRTextForComparison(small.text);
    if (text.length < 2 || box.size.width > 0.14 || box.size.height > 0.035) { return NO; }
    NSUInteger kanaCount = 0;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if ((character >= 0x3040 && character <= 0x30ff) ||
            (character >= 0x31f0 && character <= 0x31ff)) { kanaCount += 1; }
    }
    if (kanaCount * 4 < text.length * 3) { return NO; }
    for (OCRTextItem *larger in blocks) {
        if (larger == small) { continue; }
        CGRect parent = larger.boundingBox;
        if (parent.size.width < box.size.width * 1.6 || parent.size.height < box.size.height * 1.5) { continue; }
        if (CGRectGetMidY(box) <= CGRectGetMidY(parent) || CGRectGetMidY(box) - CGRectGetMaxY(parent) > 0.05) { continue; }
        CGFloat overlap = MIN(CGRectGetMaxX(box), CGRectGetMaxX(parent)) - MAX(CGRectGetMinX(box), CGRectGetMinX(parent));
        if (overlap >= box.size.width * 0.65) { return YES; }
    }
    return NO;
}

+ (BOOL)isWrappedDialogueBand:(NSArray<OCRTextItem *> *)band {
    if (band.count < 3 || ![self isSpeakerLabelItem:band.firstObject inPool:band]) { return NO; }
    NSUInteger kanaLines = 0;
    BOOL punctuated = NO, continuation = NO;
    NSCharacterSet *enders = [NSCharacterSet characterSetWithCharactersInString:@"。！!？?…・、"];
    NSCharacterSet *complete = [NSCharacterSet characterSetWithCharactersInString:@"。．.！!？?…‥"];
    OCRTextItem *previous = nil;
    for (OCRTextItem *item in band) {
        CGRect box = item.boundingBox;
        if (CGRectGetMidY(box) > .45 || box.size.height < .026 || box.size.width > .30) { return NO; }
        if (previous) {
            CGRect before = previous.boundingBox;
            CGFloat height = MAX(before.size.height,box.size.height);
            if (fabs(CGRectGetMinX(before)-CGRectGetMinX(box)) > MAX(.025,height) ||
                fabs(CGRectGetMidY(before)-CGRectGetMidY(box)) > height*2.5) { return NO; }
        }
        NSString *text = FYNormalizeOCRTextForComparison(item.text);
        if (text.length >= 3 && [self containsJapaneseKana:text]) {
            kanaLines++;
            unichar last = [text characterAtIndex:text.length-1];
            punctuated |= [enders characterIsMember:last];
            continuation |= ![self looksLikeSpeakerName:text] && ![complete characterIsMember:last];
        }
        previous = item;
    }
    return kanaLines >= 2 && punctuated && continuation;
}

+ (NSArray<OCRTextItem *> *)separatedDialogueItemsInItems:(NSArray<OCRTextItem *> *)items {
    NSSet *controls = [NSSet setWithArray:@[@"戻る",@"戻",@"閉じる",@"詳細",@"次へ",@"決定",@"設定",@"メニュー",@"スキップ",
        @"back",@"close",@"menu",@"next",@"ok",@"cancel",@"skip",@"setting",@"settings",@"web"]];
    BOOL (^control)(OCRTextItem *) = ^BOOL(OCRTextItem *item) {
        return [controls containsObject:FYNormalizeOCRTextForComparison(item.text).lowercaseString] || [self isCornerHelpButton:item];
    };
    NSArray *band = [self subtitleBandItems:items];
    if ([self isWrappedDialogueBand:band]) {
        BOOL outsideControl = NO, onlyControls = YES;
        for (OCRTextItem *item in items) {
            if ([band containsObject:item] || [self isFurigana:item nearLargerLineInItems:items]) { continue; }
            outsideControl = YES;
            if (!control(item)) { onlyControls = NO; }
        }
        if (outsideControl && onlyControls) { return band; }
    }
    OCRTextItem *anchor = nil;
    NSCharacterSet *punctuation = [NSCharacterSet characterSetWithCharactersInString:@"。！!？?…"];
    NSCharacterSet *latin = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"];
    for (OCRTextItem *item in items) {
        NSString *text = FYNormalizeOCRTextForComparison(item.text);
        if (![self isDialogueAnchor:item] || control(item) || item.speakerLabel) { continue; }
        BOOL spoken = [self containsJapaneseKana:text] && [text rangeOfCharacterFromSet:punctuation].location != NSNotFound;
        spoken |= [text rangeOfCharacterFromSet:latin].location != NSNotFound &&
            ([text hasSuffix:@"."] || [text hasSuffix:@"!"] || [text hasSuffix:@"?"]);
        if (spoken && (!anchor || item.boundingBox.size.width > anchor.boundingBox.size.width)) { anchor = item; }
    }
    if (!anchor) { return @[]; }
    NSMutableArray<OCRTextItem *> *body = [NSMutableArray arrayWithObject:anchor];
    BOOL added;
    do {
        added = NO;
        for (OCRTextItem *item in items) {
            if ([body containsObject:item] || control(item) || CGRectGetMidY(item.boundingBox) > .42) { continue; }
            for (OCRTextItem *row in [body copy]) {
                CGRect a = item.boundingBox, b = row.boundingBox;
                CGFloat overlap = MIN(CGRectGetMaxX(a),CGRectGetMaxX(b))-MAX(CGRectGetMinX(a),CGRectGetMinX(b));
                if (FYDialogueAdjacentRowFragments(item,row) ||
                    (overlap > 0 && overlap >= MIN(a.size.width,b.size.width)*.5 &&
                     fabs(CGRectGetMidY(a)-CGRectGetMidY(b)) <= MIN(.12,MAX(a.size.height,b.size.height)*2.5))) {
                    [body addObject:item];added=YES;break;
                }
            }
        }
    } while (added);
    CGFloat top = 0;
    for (OCRTextItem *item in body) { top = MAX(top,CGRectGetMaxY(item.boundingBox)); }
    BOOL separated = NO;
    for (OCRTextItem *item in items) {
        if ([body containsObject:item] || [self isFurigana:item nearLargerLineInItems:items]) { continue; }
        if (control(item)) { separated = YES;continue; }
        CGRect box = item.boundingBox, spoken = anchor.boundingBox;
        if (CGRectGetMinY(box) < top + .025 ||
            !(spoken.size.width >= box.size.width*1.25 || spoken.size.height >= box.size.height*1.10)) { return @[]; }
        separated = YES;
    }
    return separated ? body : @[];
}

+ (NSString *)dialogueTextWithoutTrailingButton:(NSString *)text {
    return [(text ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
@end
