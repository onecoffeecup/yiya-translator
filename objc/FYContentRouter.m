#import "FYContentRouter.h"
#import "FYOCRManager.h"

@implementation FYContentModeStability
- (NSInteger)observeMode:(NSInteger)detected {
    if (detected==self.detectedMode) { self.candidateMode=detected;self.candidateHits=0;return self.detectedMode; }
    if (self.candidateMode==detected) self.candidateHits+=1;
    else { self.candidateMode=detected;self.candidateHits=1; }
    if (self.candidateHits>=2) { self.detectedMode=detected;self.candidateHits=0; }
    return self.detectedMode;
}
@end


@interface FYContentModeDecision ()
@property(nonatomic) NSInteger mode;
@property(nonatomic, copy) NSString *reason;
@end
@implementation FYContentModeDecision
@end
static FYContentModeDecision *FYModeDecision(NSInteger mode, NSString *reason) {
    FYContentModeDecision *result = [FYContentModeDecision new];
    result.mode = mode;
    result.reason = reason;
    return result;
}
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
@interface FYContentRouter ()
@property(nonatomic, strong) FYContentModeStability *modeStability;
@property(nonatomic, strong) FYContentModeDecision *lastModeDecision;
@end

static NSUInteger LevenshteinDistance(NSString *left, NSString *right) {
    NSUInteger leftLength = left.length;
    NSUInteger rightLength = right.length;
    if (leftLength == 0) { return rightLength; }
    if (rightLength == 0) { return leftLength; }

    NSMutableArray<NSNumber *> *previous = [NSMutableArray arrayWithCapacity:rightLength + 1];
    NSMutableArray<NSNumber *> *current = [NSMutableArray arrayWithCapacity:rightLength + 1];
    for (NSUInteger column = 0; column <= rightLength; column++) {
        [previous addObject:@(column)];
        [current addObject:@0];
    }

    for (NSUInteger row = 1; row <= leftLength; row++) {
        current[0] = @(row);
        unichar leftCharacter = [left characterAtIndex:row - 1];
        for (NSUInteger column = 1; column <= rightLength; column++) {
            unichar rightCharacter = [right characterAtIndex:column - 1];
            NSUInteger cost = leftCharacter == rightCharacter ? 0 : 1;
            NSUInteger deletion = previous[column].unsignedIntegerValue + 1;
            NSUInteger insertion = current[column - 1].unsignedIntegerValue + 1;
            NSUInteger substitution = previous[column - 1].unsignedIntegerValue + cost;
            current[column] = @(MIN(MIN(deletion, insertion), substitution));
        }
        NSMutableArray<NSNumber *> *swap = previous;
        previous = current;
        current = swap;
    }

    return previous[rightLength].unsignedIntegerValue;
}

@implementation FYContentRouter
- (instancetype)init {
    if ((self = [super init])) { _modeStability = [FYContentModeStability new]; }
    return self;
}
- (NSInteger)observeModeForItems:(NSArray<OCRTextItem *> *)items locked:(BOOL)locked {
    if (locked) {
        self.lastModeDecision = FYModeDecision(self.modeStability.detectedMode, @"mode_locked");
        return self.modeStability.detectedMode;
    }
    self.lastModeDecision = [self.class modeDecisionForItems:items fallback:self.modeStability.detectedMode];
    return [self.modeStability observeMode:self.lastModeDecision.mode];
}
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
    for (OCRTextItem *item in items) {
        // A pixel-confirmed name plate is metadata, not a spoken short line.
        // Preserve recognized names; unrecognized plate OCR must not be sent
        // as body text. Do not apply this rule to ordinary kana/Latin speech.
        if ([self isUncertainSpeakerLabelItem:item]) { continue; }
        if ([self isCornerHelpButton:item] || [self isFurigana:item nearLargerLineInItems:items]) { continue; }
        FYContentTextFilterReason reason = [self filterReasonForText:item.text
            normalized:FYNormalizeOCRTextForComparison(item.text) boundingBox:item.boundingBox strict:YES];
        if (reason != FYContentTextKeep) {
            if (observer) { observer(item.text, item.boundingBox, reason); }
            continue;
        }
        [lines addObject:item.text];
    }
    if (speakerLabelOnly) { *speakerLabelOnly = [self dialogueFrameIsSpeakerLabelOnly:lines]; }
    return [self dialogueTextWithoutTrailingButton:[lines componentsJoinedByString:@"\n"]];
}
+ (BOOL)isUncertainSpeakerLabelItem:(OCRTextItem *)item {
    return item.speakerLabel && ![self looksLikeSpeakerName:item.text];
}
+ (NSTimeInterval)recognitionPollingIntervalForMode:(NSInteger)mode {
    return mode == FYContentModeDialogue ? 0.5 : 1.2;
}
+ (NSTimeInterval)translationAttemptThrottleForMode:(NSInteger)mode {
    return mode == FYContentModeUI ? 1.2 : 4.0;
}

+ (double)similarityRatio:(NSString *)left comparedTo:(NSString *)right {
    NSUInteger maxLength = MAX(left.length, right.length);
    if (maxLength == 0) { return 1.0; }
    NSUInteger distance = LevenshteinDistance(left, right);
    return 1.0 - ((double)distance / (double)maxLength);
}

+ (BOOL)isSameSubtitleText:(NSString *)text comparedTo:(NSString *)previous
                     mode:(NSInteger)mode japanese:(BOOL)japanese comparisonKey:(FYContentComparisonKey)key {
    NSString *left = text ?: @"";
    NSString *right = previous ?: @"";
    if (left.length < 2 || right.length < 2) { return NO; }
    if ([left isEqualToString:right]) { return YES; }
    if (mode == FYContentModeDialogue && japanese) {
        // A long sentence with one changed negation/number can still be >90%
        // similar. Only harmless OCR punctuation shares the frame identity;
        // clipped frames are checked directionally against the complete source
        // by the learning coordinator, after consecutive-frame confirmation.
        return [key(left) isEqualToString:key(right)];
    }

    NSUInteger maxLength = MAX(left.length, right.length);
    NSUInteger lengthDelta = left.length > right.length ? left.length - right.length : right.length - left.length;
    if (maxLength <= 6) {
        return lengthDelta == 0 && [self similarityRatio:left comparedTo:right] >= 0.84;
    }

    return [self similarityRatio:left comparedTo:right] >= 0.90;
}

+ (BOOL)isStableText:(NSString *)normalized owner:(FYOCRStabilityOwner *)owner
               mode:(NSInteger)mode japanese:(BOOL)japanese renderedText:(NSString *)rendered
      comparisonKey:(FYContentComparisonKey)key {
    BOOL stable = [owner observe:normalized equivalent:^BOOL(NSString *current, NSString *previous) {
        return [self isSameSubtitleText:current comparedTo:previous mode:mode japanese:japanese comparisonKey:key];
    }];
    // Small real corrections must eventually translate, while one/two-frame
    // substitutions caused by compression need not replace a complete caption.
    if (stable && mode == FYContentModeDialogue && japanese &&
        rendered.length &&
        [self similarityRatio:normalized comparedTo:rendered] >= 0.85 &&
        ![self isSameSubtitleText:normalized comparedTo:rendered mode:mode japanese:japanese comparisonKey:key]) {
        return owner.count >= 3;
    }
    return stable;
}

+ (FYContentTextFilterReason)filterReasonForText:(NSString *)text normalized:(NSString *)normalized boundingBox:(CGRect)box strict:(BOOL)strict {
    if (normalized.length == 0) { return FYContentTextEmpty; }

    // 只过滤纯省略号、纯标点/符号与空白；没有假名/汉字不等于没有文字。
    // 英文句号与省略号不能触发整行删除。
    // 只要含一个有效日文字符就必须保留 —— 「え……」只有一个字也必须留。
    //
    // 以前这里用「点号占比 ≥ 一半 + 实义部分 ≤ 3 字 + 框宽 < 0.16」判噪声，把
    // 「あれは・・・・・・」（框宽 0.115987）整行删掉，只剩「琥一／話し合いだ。」；
    // 「退学って……」「どれど……」也栽在同类判据上。按用户要求删掉这些
    // 字数/框宽/点号占比条件，不再用新的宽度阈值或词语表替代。
    {
        NSCharacterSet *dots = [NSCharacterSet characterSetWithCharactersInString:@"・…‥.．·"];
        BOOL hasJapanese = NO;
        for (NSUInteger index = 0; index < text.length; index++) {
            unichar character = [text characterAtIndex:index];
            if ([dots characterIsMember:character]) { continue; }
            if ((character >= 0x3040 && character <= 0x30FF) ||    // 平假名 / 片假名
                (character >= 0x4E00 && character <= 0x9FFF) ||    // 汉字
                (character >= 0xFF66 && character <= 0xFF9F)) {    // 半角片假名
                hasJapanese = YES;
                break;
            }
        }
        // 纯标点/符号行（同样没有假名汉字）也没有可译内容。
        if (!hasJapanese && text.length > 0) {
            NSCharacterSet *punct = [NSCharacterSet punctuationCharacterSet];
            NSCharacterSet *symbols = [NSCharacterSet symbolCharacterSet];
            NSCharacterSet *spaces = [NSCharacterSet whitespaceAndNewlineCharacterSet];
            BOOL onlyPunctuation = YES;
            for (NSUInteger index = 0; index < text.length; index++) {
                unichar character = [text characterAtIndex:index];
                if (character == 0x3000 || [spaces characterIsMember:character] ||
                    [punct characterIsMember:character] || [symbols characterIsMember:character]) { continue; }
                onlyPunctuation = NO;
                break;
            }
            if (onlyPunctuation) {
                return FYContentTextPunctuationOnly;
            }
        }
    }

    NSString *lower = normalized.lowercaseString;
    if (strict) {
        // 对白模式：这些词基本是游戏 UI/环境噪声，不该混进字幕
        NSArray<NSString *> *ignoreTokens = @[
            @"today", @"web", @"back", @"戻る", @"戻", @"詳細", @"閉じる", @"ルームへ",
            @"更新", @"news", @"no.", @"no", @"ok", @"yes", @"skip", @"auto", @"menu"
        ];
        // 说明：这条“界面词表”规则保持不变（它需要同时命中词表与长度/宽度条件，
        // 不属于本轮要删除的“仅凭字数/框宽/省略号比例删除”的误删条件）。
        for (NSString *token in ignoreTokens) {
            if ([lower isEqualToString:token] || [lower containsString:token]) {
                if (normalized.length <= 8 || box.size.width < 0.16 || box.size.height < 0.06) {
                    return FYContentTextDialogueControl;
                }
            }
        }

        // 这里原本还有一条“短、窄、全平假名 = 名字框错读”的删除规则（`ことと` 之类）。
        // 按本轮要求删除：只要含有效日文文字，就不能凭字数少、框窄删掉 —— 「え」这种
        // 单字台词同样要保留。代价是名字框的错读可能被翻译出来；完整性优先。
    } else {
        // 这里原本还有一条“短且全是平假名/符号 = 噪声”的删除规则（同样会把
        // 「え……」这类短台词在贴译路径也删掉）。本轮删除：含有效日文文字就保留。
        // 下面只保留“完全没有假名/汉字”的纯字母碎片过滤 —— 那种行里没有可译的日文。

        // 短且**完全没有日文假名/汉字**的纯字母碎片，也是 `？？？` 之类的错读
        // （实测名字框被读成 `iee`），发去翻译只会得到编造的译文。
        if (!strict && normalized.length <= 6) {
            BOOL hasKanaOrKanji = NO;
            for (NSUInteger index = 0; index < normalized.length; index++) {
                unichar character = [normalized characterAtIndex:index];
                if ((character >= 0x3040 && character <= 0x30FF) ||   // 平假名 / 片假名
                    (character >= 0x4E00 && character <= 0x9FFF)) {   // 汉字
                    hasKanaOrKanji = YES;
                    break;
                }
            }
            if (!hasKanaOrKanji) { return FYContentTextShortUIFragment; }
        }

        // 界面模式：按钮、日期、条目编号都是用户要看的文字，不能当成噪声丢掉。
        // 之前和上面共用同一张表，导致「No. 48 5/1更新」被 “更新” 命中而整条不翻，
        // 「詳細」「戻る」这类按钮也永远不会被翻译。
        // 这里只丢真正的装饰：版本号样式的一小串字符。
        NSArray<NSString *> *decorativeTokens = @[@"no.", @"no"];
        for (NSString *token in decorativeTokens) {
            if (([lower isEqualToString:token]) && normalized.length <= 3) { return FYContentTextDecoration; }
        }
    }

    NSCharacterSet *digitsAndMarks = [NSCharacterSet characterSetWithCharactersInString:@"0123456789/.-〜~年月日(月)(火)(水)(木)(金)(土)(日) "];
    BOOL onlyDigitsAndMarks = normalized.length > 0;
    for (NSUInteger index = 0; index < normalized.length; index++) {
        if (![digitsAndMarks characterIsMember:[normalized characterAtIndex:index]]) {
            onlyDigitsAndMarks = NO;
            break;
        }
    }
    if (onlyDigitsAndMarks) { return FYContentTextDateOrNumber; }

    // 贴边且短：多半是画面边缘的按钮。
    // 但**必须同时够窄**才算按钮 —— 对白框本身就贴在画面下方，
    // 实测把它整句丢掉（`送ってく。` 宽 0.11、y=0.052）会让最后一行对白消失。
    BOOL nearBottomOrTop = box.origin.y < 0.08 || CGRectGetMaxY(box) > 0.94;
    // 必须**横向也贴边**才算角落按钮。对白框本身就贴在画面下方（实测「行くぞ。」y=0.053），
    // 只按纵向+窄度判定会把台词整句丢掉 —— 现在字幕为空就是这么来的。
    BOOL nearLeftOrRight = box.origin.x < 0.12 || CGRectGetMaxX(box) > 0.88;
    if (nearBottomOrTop && nearLeftOrRight && normalized.length <= 8 && box.size.width < 0.10) {
        return FYContentTextCorner;
    }

    return FYContentTextKeep;
}

+ (NSInteger)contentModeForItems:(NSArray<OCRTextItem *> *)items fallback:(NSInteger)fallback {
    return [self modeDecisionForItems:items fallback:fallback].mode;
}

+ (FYContentModeDecision *)modeDecisionForItems:(NSArray<OCRTextItem *> *)blocks fallback:(NSInteger)fallbackSegment {
    if (blocks.count == 0) { return FYModeDecision(fallbackSegment, @"empty"); }

    // UI 特征优先否决：画面里有「戻る / 詳細 / メニュー」这类按钮，或者是文本密集的列表/菜单页，
    // 就走贴译整屏，而不是把某条宽行当对白。
    // 现实依据：列表页里也有很宽的行（实测 0.26），光凭“有没有宽行”分不出对白和列表。
    if ([self looksLikeUIFrame:blocks]) { return FYModeDecision(FYContentModeUI, @"ui_evidence"); }

    // 再看有没有成形的对白框：有就按对白处理，别被街景招牌/公告牌带偏
    if ([self subtitleBandItems:blocks].count > 0) { return FYModeDecision(FYContentModeDialogue, @"dialogue_band"); }

    // 一帧只读到角落操作提示，或短台词被 OCR 截成 1~2 字时，不据此切换已确认的模式。
    if (blocks.count <= 2 && [self UITokenHitCount:blocks] == 0) {
        BOOL hasCentralDialogueFragment = NO;
        BOOL onlyCornerHints = YES;
        for (OCRTextItem *block in blocks) {
            CGRect box = block.boundingBox;
            if ([self containsJapaneseKana:block.text] && CGRectGetMidY(box) >= 0.10 &&
                CGRectGetMidY(box) <= 0.38 && CGRectGetMinX(box) >= 0.18 &&
                CGRectGetMaxX(box) <= 0.78 && box.size.height >= 0.035) {
                hasCentralDialogueFragment = YES;
            }
            if (!(CGRectGetMinX(box) >= 0.80 && CGRectGetMidY(box) <= 0.12)) {
                onlyCornerHints = NO;
            }
        }
        if (hasCentralDialogueFragment || onlyCornerHints) { return FYModeDecision(fallbackSegment, hasCentralDialogueFragment ? @"central_fragment" : @"corner_hints"); }
    }

    return FYModeDecision(FYContentModeUI, @"default_ui");
}

// 说话人名字框：短、没有句末标点、不含平假名（实测 `萩尾九段` / `片霧秋兵` / `ルード`）。
// 这类框会被 OCR 单独读成一行，或单独成一簇被当成「选项」，
// 于是在学习库里各占一条「最近台词」，把 5 条额度从真台词那里挤掉。
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

// 名字框上方的假名注音被 OCR 单独读成一行（实测 `かたぎりし、ゆうの` / `＜だん`）。
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

// 一簇全是名字/注音（且至少有一行是名字），才当成名字框 —— 宽度上限防止把整行正文吞进来。
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

// 单独一行是不是名字框的一部分：名字本身，或紧贴其上方的假名注音。
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

// 整帧只有说话人名字（可以带注音）—— 正文没读到。这种帧写进学习库只会白占一条额度。
// 必须真的有一行是名字：短句 `はい` 也满足“假名行”的判定，不能被当成名字框丢掉。
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

// 把 band 拆成「对白」和「选项」两组。
// 做法：先按垂直间距把 band 分成一簇一簇（连续的行 ≤0.12，隔开的就是不同簇），
// 再把位于画面下半部的簇判为对白框，其余在上方的簇判为选项。
// 依据：视觉小说的对白框固定在画面下方，选项浮在上方；
// 这样就算选项自身的行距比较大，也不会把两个选项拆到两组里去。
+ (void)splitDialogueAndOptions:(NSArray<OCRTextItem *> *)band
                     allBlocks:(NSArray<OCRTextItem *> *)allBlocks
                      dialogue:(NSMutableArray<OCRTextItem *> *)outDialogue
                       options:(NSMutableArray<OCRTextItem *> *)outOptions {
    if (band.count == 0) { return; }

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
        if (gap <= 0.12) {
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
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        if ((character >= 0x3040 && character <= 0x30ff) || (character >= 0x31f0 && character <= 0x31ff)) {
            return YES;
        }
    }
    return NO;
}

// 从整窗 OCR 里挑出“对白框”那几行：取最低的一条长行当锚点，再收拢它附近的行。
// 目的：街景招牌、公告牌这类环境文本不该混进对白翻译。
// 对白/选项的文字块：幅面够大、字数够多。街景招牌、图标标签这类零碎短文本天然被排除。
+ (BOOL)isFormedTextLine:(OCRTextItem *)block {
    NSString *normalized = FYNormalizeOCRTextForComparison(block.text);
    if (normalized.length >= 8 && block.boundingBox.size.width >= 0.20) { return YES; }
    // 0.15 太贴近现实边缘：对白框被 UI 遮住一半时宽度会掉到 0.13 左右，
    // 只差一点点就被判成“不成型”，整条对白就丢了。放宽到 0.12。
    if (normalized.length >= 6 && block.boundingBox.size.width >= 0.12) { return YES; }
    return NO;
}

// 挑出“对白 + 选项”这些需要翻译的文字块。
// 做法：以画面**下半部**里最宽的一条成型行作锚点（视觉小说的对白框在下半部，而且通常最宽），
// 再把与它水平大幅重叠、纵向邻接的块一起收进来。
// 注意 Vision 的 boundingBox 是底左原点：y 越大越靠近画面顶端。
// 能不能当“对白框”的锚点。
// 对白框的现实特征：① 贴在画面很靠下的位置 ② 框里有一条像台词的宽行。
// 判得严一点很重要 —— 文本密集的功能 UI 里也有不少宽行，放松了就会把 UI 误判成对白、
// 于是整屏文字被塞进字幕窗，而该贴译的内容反而没人管。
// “短句对白”锚点：只在对白框通篇短句时兜底使用。
// 门槛刻意比 IsDialogueAnchorCandidate 低（实测「思い出した。」是 6 字 / 0.13 宽）。
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

// 单行对白：整屏只有一句台词（没有名字框、没有第二行）。
// 之前“短句兜底”要求它和相邻行堆叠，于是单行对白被误杀（band=0 → 被判成界面贴译）。
// 台词几乎都以句末标点结尾，而街景招牌通常没有 —— 用这个区分。
+ (BOOL)isSingleLineDialogue:(OCRTextItem *)block {
    NSString *normalized = FYNormalizeOCRTextForComparison(block.text);
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

    [band sortUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) {
        CGFloat leftMidY = CGRectGetMidY(left.boundingBox);
        CGFloat rightMidY = CGRectGetMidY(right.boundingBox);
        if (fabs(leftMidY - rightMidY) < 0.01) { return NSOrderedSame; }
        // 底左原点：midY 大的在画面上方，按从上到下输出
        return leftMidY > rightMidY ? NSOrderedAscending : NSOrderedDescending;
    }];
    return band;
}

// 判定“这一帧看起来像功能界面”：小按钮、菜单词、密集短文本、贴边文字
// 画面里出现几个游戏 UI 特有的按钮/菜单词？
// 这是区分“功能 UI”和“剧情对白”最可靠的单一信号 ——
// 新闻、列表、菜单页一定带「戻る / 詳細 / メニュー」这类词，对白框不会。
//
// 匹配必须精确：早期用 containsString 会误判 ——
// 日文那边的 "River Books" 会命中 "ok"，对白 "これでプレゼントはOK。" 也会命中 "ok"。
+ (BOOL)textHitsUIToken:(NSString *)text {
    NSString *normalized = FYNormalizeOCRTextForComparison(text);
    if (normalized.length == 0) { return NO; }
    NSString *lower = normalized.lowercaseString;

    // 日文按钮词：整条相等，或者出现在开头（「詳細を見る」「戻る」这类）
    NSArray<NSString *> *japaneseTokens = @[@"戻る", @"戻", @"閉じる", @"詳細", @"次へ",
                                            @"決定", @"設定", @"メニュー", @"スキップ"];
    for (NSString *token in japaneseTokens) {
        if ([normalized isEqualToString:token] || [normalized hasPrefix:token]) { return YES; }
    }

    // 拉丁词：必须是独立词，不能在别的单词里（避免 "Books" → "ok"）
    NSArray<NSString *> *latinTokens = @[@"back", @"close", @"menu", @"next", @"ok",
                                         @"cancel", @"skip", @"setting", @"settings", @"web"];
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    for (NSString *token in latinTokens) {
        NSRange searchRange = NSMakeRange(0, lower.length);
        while (searchRange.length > 0) {
            NSRange found = [lower rangeOfString:token options:0 range:searchRange];
            if (found.location == NSNotFound) { break; }
            BOOL leftFree = (found.location == 0) ||
                            ![letters characterIsMember:[lower characterAtIndex:found.location - 1]];
            NSUInteger after = found.location + found.length;
            BOOL rightFree = (after >= lower.length) ||
                             ![letters characterIsMember:[lower characterAtIndex:after]];
            if (leftFree && rightFree) { return YES; }
            NSUInteger next = found.location + found.length;
            if (next >= lower.length) { break; }
            searchRange = NSMakeRange(next, lower.length - next);
        }
    }
    return NO;
}

+ (NSUInteger)UITokenHitCount:(NSArray<OCRTextItem *> *)blocks {
    NSUInteger tokenHitCount = 0;
    for (OCRTextItem *block in blocks) {
        if ([self textHitsUIToken:block.text]) { tokenHitCount += 1; }
    }
    return tokenHitCount;
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

+ (BOOL)looksLikeUIFrame:(NSArray<OCRTextItem *> *)blocks {
    NSUInteger smallBoxCount = 0;
    NSUInteger edgeCount = 0;
    NSUInteger wideLineCount = 0;
    NSUInteger textBlockCount = 0;
    CGFloat totalWidth = 0;
    NSUInteger tokenHitCount = [self UITokenHitCount:blocks];

    for (OCRTextItem *block in blocks) {
        NSString *normalized = FYNormalizeOCRTextForComparison(block.text);
        if (normalized.length == 0) { continue; }
        textBlockCount += 1;
        totalWidth += block.boundingBox.size.width;

        BOOL smallBox = normalized.length <= 8 && block.boundingBox.size.height < 0.036 &&
            block.boundingBox.size.width < 0.20 && ![self isFurigana:block nearLargerLineInItems:blocks];
        if (smallBox) { smallBoxCount += 1; }
        if (block.boundingBox.size.width >= 0.32) { wideLineCount += 1; }

        BOOL nearEdge = block.boundingBox.origin.y < 0.10 || CGRectGetMaxY(block.boundingBox) > 0.90;
        if (nearEdge && normalized.length <= 12) { edgeCount += 1; }
    }

    if (tokenHitCount >= 2) { return YES; }
    if (tokenHitCount >= 1 && (smallBoxCount >= 2 || edgeCount >= 3)) { return YES; }
    if (smallBoxCount >= 4 || (blocks.count >= 5 && smallBoxCount >= 3)) {
        // A speaker label and several short dialogue lines are also small boxes.
        // Exempt wrapped speech with a leading speaker label. Aligned choices
        // can also contain kana and punctuation, including below a name heading.
        // A continuation fragment distinguishes the supported short-dialogue
        // case from a list of independently completed sentences.
        NSArray<OCRTextItem *> *band = [self subtitleBandItems:blocks];
        NSUInteger kanaLines = 0, bandSmallBoxes = 0;
        BOOL compact = band.count >= 3, punctuated = NO, hasContinuation = NO;
        BOOL hasSpeakerLabel = band.count > 0 && [self isSpeakerLabelItem:band.firstObject inPool:band];
        NSCharacterSet *enders = [NSCharacterSet characterSetWithCharactersInString:@"。！!？?…・、"];
        NSCharacterSet *sentenceEnders = [NSCharacterSet characterSetWithCharactersInString:@"。．.！!？?…‥"];
        OCRTextItem *previous = nil;
        for (OCRTextItem *item in band) {
            CGRect box = item.boundingBox;
            NSString *text = FYNormalizeOCRTextForComparison(item.text);
            if (CGRectGetMidY(box) > 0.45 || box.size.height < 0.026 || box.size.width > 0.30) { compact = NO; }
            if (previous) {
                CGRect before = previous.boundingBox;
                CGFloat lineHeight = MAX(before.size.height, box.size.height);
                if (fabs(CGRectGetMinX(before) - CGRectGetMinX(box)) > MAX(0.025, lineHeight) ||
                    fabs(CGRectGetMidY(before) - CGRectGetMidY(box)) > lineHeight * 2.5) { compact = NO; }
            }
            if (text.length >= 3 && [self containsJapaneseKana:text]) {
                kanaLines++;
                if ([enders characterIsMember:[text characterAtIndex:text.length - 1]]) { punctuated = YES; }
                if (![self looksLikeSpeakerName:text] &&
                    ![sentenceEnders characterIsMember:[text characterAtIndex:text.length - 1]]) { hasContinuation = YES; }
            }
            if (text.length <= 8 && box.size.height < 0.036 && box.size.width < 0.20 &&
                ![self isFurigana:item nearLargerLineInItems:blocks]) { bandSmallBoxes++; }
            previous = item;
        }
        BOOL wrappedSpeech = compact && hasSpeakerLabel && hasContinuation && kanaLines >= 2 && punctuated;
        NSUInteger menuBoxes = wrappedSpeech ? smallBoxCount - bandSmallBoxes : smallBoxCount;
        if (menuBoxes >= 4 || (blocks.count >= 5 && menuBoxes >= 3)) { return YES; }
    }
    // 贴边文字很多、且完全没有宽行 —— 但这必须**同时**带上 UI 按钮词才算数。
    // 单独用贴边信号太弱：对白游戏的字幕框本身就贴着画面底部，
    // 实测城镇对白帧 edge=4（其中还包含我们自己浮窗的文字），会把对白误判成 UI。
    if (edgeCount >= 4 && wideLineCount == 0 && tokenHitCount >= 1) { return YES; }

    // 文本密集 = 列表 / 菜单 / 新闻页。
    // 判据用“实质行数”（够宽、够长的行），实测能干净分开：
    //   新闻列表页 8 行，对白帧 3 行。纯招牌画面只有 1~2 行。
    // 不用“平均宽度”，因为街景招牌会把平均值拉低，反而误伤对白帧。
    NSUInteger substantialLineCount = 0;
    for (OCRTextItem *block in blocks) {
        NSString *normalized = FYNormalizeOCRTextForComparison(block.text);
        if (normalized.length == 0) { continue; }
        CGFloat width = block.boundingBox.size.width;
        if (width >= 0.15) { substantialLineCount += 1; continue; }
        if (normalized.length >= 8 && width >= 0.13 && block.boundingBox.size.height >= 0.030) {
            substantialLineCount += 1;
        }
    }
    if (substantialLineCount >= 6) { return YES; }

    (void)textBlockCount;
    (void)totalWidth;
    return NO;
}

// OCR 常把紧邻对白的小按钮粘进同一行：实测 `思い出した。` 被读成 `思い出した。使用`。
// 直接发去翻译，模型会照着输出「想起来了。使用」—— 按钮文字混进了字幕。
// 规则：句末标点之后只剩一小段**纯汉字**（2~4 字），且整串里有假名，就把它当按钮切掉。
+ (NSString *)dialogueTextWithoutTrailingButton:(NSString *)text {
    NSString *trimmed = (text ? [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"");
    if (trimmed.length == 0) { return trimmed; }

    NSCharacterSet *kanaSet = [NSCharacterSet characterSetWithCharactersInString:
        @"ぁあぃいぅうぇえぉおかがきぎくぐけげこごさざしじすずせぜそぞただちぢっつづてでとどなにぬねのはばぱひびぴふぶぷへべぺほぼぽまみむめもゃやゅゆょよらりるれろゎわゐゑをんァアィイゥウェエォオカガキギクグケゲコゴサザシジスズセゼソゾタダチヂッツヅテデトドナニヌネノハバパヒビピフブプヘベペホボポマミムメモャヤュユョヨラリルレロヮワヰヱヲンヴー"];
    BOOL hasKana = NO;
    for (NSUInteger index = 0; index < trimmed.length; index++) {
        if ([kanaSet characterIsMember:[trimmed characterAtIndex:index]]) { hasKana = YES; break; }
    }
    if (!hasKana) { return trimmed; }

    // 从末尾往前吃掉 2~4 个纯汉字，并要求它前面是句末标点
    NSUInteger end = trimmed.length;
    NSUInteger runStart = end;
    while (runStart > 0) {
        unichar character = [trimmed characterAtIndex:runStart - 1];
        if (character >= 0x4E00 && character <= 0x9FFF) { runStart -= 1; continue; }
        break;
    }
    NSUInteger hanRun = end - runStart;
    if (hanRun < 2 || hanRun > 4 || runStart == 0) { return trimmed; }

    NSCharacterSet *sentenceEnd = [NSCharacterSet characterSetWithCharactersInString:@"。．.!！?？、，,…」』）)"];
    if (![sentenceEnd characterIsMember:[trimmed characterAtIndex:runStart - 1]]) { return trimmed; }

    return [[trimmed substringToIndex:runStart] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

@end
