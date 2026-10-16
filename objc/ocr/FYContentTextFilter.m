#import "FYContentPolicy.h"
@implementation FYContentPolicy (TextFiltering)
+ (FYContentTextFilterReason)filterReasonForText:(NSString *)text normalized:(NSString *)normalized boundingBox:(CGRect)box strict:(BOOL)strict {
    return [self filterReasonForText:text normalized:normalized boundingBox:box strict:strict japanese:YES];
}
+ (FYContentTextFilterReason)filterReasonForText:(NSString *)text normalized:(NSString *)normalized boundingBox:(CGRect)box strict:(BOOL)strict japanese:(BOOL)japanese {
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
        // Isolated control labels need both an exact token and control geometry.
        // Substrings of ordinary speech (know, Books, 戻らないで) are not controls.
        NSArray<NSString *> *ignoreTokens = @[
            @"today", @"web", @"back", @"戻る", @"戻", @"詳細", @"閉じる", @"ルームへ",
            @"更新", @"news", @"no.", @"no", @"ok", @"yes", @"skip", @"auto", @"menu"
        ];
        for (NSString *token in ignoreTokens) {
            if ([lower isEqualToString:token]) {
                BOOL peripheral = CGRectGetMinX(box) < .15 || CGRectGetMaxX(box) > .85 || CGRectGetMidY(box) > .45;
                if (box.size.height < .036 || peripheral) {
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
        if (japanese && normalized.length <= 6) {
            BOOL hasKanaOrKanji = NO;
            for (NSUInteger index = 0; index < normalized.length; index++) {
                unichar character = [normalized characterAtIndex:index];
                if ((character >= 0x3040 && character <= 0x30FF) ||   // 平假名 / 片假名
                    (character >= 0x4E00 && character <= 0x9FFF) ||   // 汉字
                    (character >= 0xFF66 && character <= 0xFF9F)) {  // 半角片假名
                    hasKanaOrKanji = YES;
                    break;
                }
            }
            if (!hasKanaOrKanji) { return FYContentTextShortUIFragment; }
        }

        // Preserve English No/Yes menus. Japanese OCR retains its standalone
        // Latin numbering-decoration rule; numeric/date filtering is separate.
        NSArray<NSString *> *decorativeTokens = @[@"no.", @"no"];
        for (NSString *token in decorativeTokens) {
            if (japanese && [lower isEqualToString:token] && normalized.length <= 3) { return FYContentTextDecoration; }
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


@end
