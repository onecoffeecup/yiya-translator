#import "FYContentPolicy.h"
static FYContentModeDecision *FYModeDecision(NSInteger mode,NSString *reason) {
    return [[FYContentModeDecision alloc] initWithMode:mode reason:reason];
}

@implementation FYContentPolicy (ModeClassification)
+ (NSInteger)contentModeForItems:(NSArray<OCRTextItem *> *)items fallback:(NSInteger)fallback {
    return [self modeDecisionForItems:items fallback:fallback].mode;
}

+ (FYContentModeDecision *)modeDecisionForItems:(NSArray<OCRTextItem *> *)blocks fallback:(NSInteger)fallbackSegment {
    if (blocks.count == 0) { return FYModeDecision(fallbackSegment, @"empty"); }

    // UI evidence still takes priority unless a distinct lower spoken region
    // supports mixed routing. A wide row alone cannot distinguish a menu.
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

+ (BOOL)textHitsUIToken:(NSString *)text {
    NSString *normalized = FYNormalizeOCRTextForComparison(text);
    if (normalized.length == 0) { return NO; }
    // Preserve spaces for Latin word boundaries; normalizing them away turns
    // "go back" into "goback" before the boundary check.
    NSString *lower = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;

    // A Japanese prefix followed by letters is ordinary text, not a button.
    // Exact labels and punctuation-delimited hints (戻る(B)) remain evidence.
    NSArray<NSString *> *japaneseTokens = @[@"戻る", @"戻", @"閉じる", @"詳細", @"次へ",
                                            @"決定", @"設定", @"メニュー", @"スキップ"];
    for (NSString *token in japaneseTokens) {
        if ([normalized isEqualToString:token]) { return YES; }
        if ([normalized hasPrefix:token] && normalized.length > token.length &&
            ![NSCharacterSet.letterCharacterSet characterIsMember:[normalized characterAtIndex:token.length]]) { return YES; }
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

+ (BOOL)looksLikeUIFrame:(NSArray<OCRTextItem *> *)blocks {
    // A distinct lower spoken region can coexist with options and controls.
    // Equal-sized rows of a pure list do not provide this separation evidence.
    if ([self separatedDialogueItemsInItems:blocks].count > 0) { return NO; }
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
        NSUInteger bandSmallBoxes = 0;
        for (OCRTextItem *item in band) {
            CGRect box = item.boundingBox;
            NSString *text = FYNormalizeOCRTextForComparison(item.text);
            if (text.length <= 8 && box.size.height < 0.036 && box.size.width < 0.20 &&
                ![self isFurigana:item nearLargerLineInItems:blocks]) { bandSmallBoxes++; }
        }
        BOOL wrappedSpeech = [self isWrappedDialogueBand:band];
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
@end
