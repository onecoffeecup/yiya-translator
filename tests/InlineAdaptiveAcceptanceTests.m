// 独立复验：基于 OCR 文本区域的自适应贴译布局（FYInlineGrouper + FYInlineLayoutEngine）。
//
// 本套件由复验方独立编写：
//   · 不复用实现方测试（InlineAdaptiveLayoutTests.m）的任何夹具、断言或阈值；
//   · 不读取产品私有状态来决定期望值，期望只来自本轮验收点；
//   · 每条断言独立给出 PASS/FAIL 与最小复现（坐标 / 期望 / 实际）。
//
// 只调用公开 API：FYInlineLayout.h 的分组器、布局引擎、匹配器，以及
// LiveCaptionTranslator 的 showInlineTranslations:forItems:placementRect: /
// appKitFrameForOCRItem:inWindowFrame: / inlineBlockIdentityForItem:。

#import "LearningAppTestSupport.h"
#import "FYInlineLayout.h"

#pragma mark - 计分与输出

static NSUInteger gIAPass = 0;
static NSUInteger gIAFail = 0;

static void IACheck(BOOL ok, NSString *scenario, NSString *detail) {
    if (ok) {
        gIAPass += 1;
        NSLog(@"PASS [%@] %@", scenario, detail);
    } else {
        gIAFail += 1;
        NSLog(@"FAIL [%@] %@", scenario, detail);
    }
}

static NSString *IARect(CGRect r) {
    return [NSString stringWithFormat:@"(%.1f,%.1f %.1fx%.1f)", r.origin.x, r.origin.y, r.size.width, r.size.height];
}

static NSString *IAClip(NSString *text, NSUInteger limit) {
    NSString *flat = [(text ?: @"") stringByReplacingOccurrencesOfString:@"\n" withString:@"⏎"];
    if (flat.length <= limit) { return flat; }
    return [[flat substringToIndex:limit] stringByAppendingString:@"…"];
}

static NSString *IAJoined(NSArray<NSString *> *values) {
    return [values componentsJoinedByString:@" | "];
}

#pragma mark - 分组夹具

/// 归一化页面坐标：原点左下，与 Vision 一致。
static CGRect IABox(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    return CGRectMake(x, y, w, h);
}

static FYInlineTextLine *IALine(NSString *text, CGRect rect, NSInteger index) {
    return [FYInlineTextLine lineWithText:text rect:rect confidence:0.9 sourceIndex:index];
}

/// 一列（纵向）文本行：从 top 往下每行下移 pitch。
static void IAAddColumn(NSMutableArray<FYInlineTextLine *> *lines,
                        NSArray<NSString *> *texts,
                        CGFloat x, CGFloat top, CGFloat width, CGFloat height, CGFloat pitch,
                        NSInteger *cursor) {
    for (NSUInteger index = 0; index < texts.count; index++) {
        [lines addObject:IALine(texts[index], IABox(x, top - (CGFloat)index * pitch, width, height), *cursor)];
        *cursor += 1;
    }
}

static NSArray<FYInlineTextBlock *> *IAGroup(NSArray<FYInlineTextLine *> *lines) {
    return [[FYInlineGrouper defaultGrouper] blocksFromLines:lines];
}

static FYInlineTextBlock *IABlockContaining(NSArray<FYInlineTextBlock *> *blocks, NSString *needle) {
    for (FYInlineTextBlock *block in blocks) {
        if ([block.text containsString:needle]) { return block; }
    }
    return nil;
}

static BOOL IATextHasAny(NSString *text, NSArray<NSString *> *needles) {
    for (NSString *needle in needles) {
        if ([text containsString:needle]) { return YES; }
    }
    return NO;
}

static NSString *IABlockDump(NSArray<FYInlineTextBlock *> *blocks) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSUInteger index = 0; index < blocks.count; index++) {
        FYInlineTextBlock *block = blocks[index];
        [parts addObject:[NSString stringWithFormat:@"B%lu{w=%.3f,h=%.3f,n=%ld,kind=%ld}<%@>",
                          (unsigned long)(index + 1), block.boundingBox.size.width, block.boundingBox.size.height,
                          (long)block.lineCount, (long)block.kind, IAClip(block.text, 26)]];
    }
    return IAJoined(parts);
}

static NSString *IAPlacementsDump(FYInlineLayoutResult *result) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (FYInlinePlacement *placement in result.placements) {
        [parts addObject:[NSString stringWithFormat:@"mode=%ld anchor=%ld frame=%@ src=%@ reason=%@",
                          (long)placement.mode, (long)placement.anchor,
                          IARect(placement.translationFrame), IARect(placement.sourceFrame),
                          placement.reason ?: @""]];
    }
    return IAJoined(parts);
}

/// 每行原文、矩形、来源下标都必须落到某个块里，且不产生空占位行。
static void IACheckPreservation(NSArray<FYInlineTextBlock *> *blocks,
                                NSArray<FYInlineTextLine *> *input,
                                NSString *scenario) {
    BOOL shapes = YES;
    BOOL texts = YES;
    NSUInteger total = 0;
    NSMutableArray<NSNumber *> *indices = [NSMutableArray array];
    for (FYInlineTextBlock *block in blocks) {
        total += (NSUInteger)block.lineCount;
        if (block.lineTexts.count != block.lineBoxes.count ||
            block.lineBoxes.count != block.sourceIndices.count ||
            block.lineConfidences.count != block.lineTexts.count) {
            shapes = NO;
        }
        for (NSString *line in block.lineTexts) {
            if (line.length == 0) { texts = NO; }
        }
        [indices addObjectsFromArray:block.sourceIndices];
    }
    NSArray<NSNumber *> *sorted = [indices sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [a compare:b];
    }];
    BOOL complete = sorted.count == input.count;
    for (NSUInteger index = 0; complete && index < sorted.count; index++) {
        if (sorted[index].integerValue != (NSInteger)index) { complete = NO; }
    }
    IACheck(shapes, scenario, [NSString stringWithFormat:@"每块 lineTexts/lineBoxes/lineConfidences/sourceIndices 一一对应（%lu 块）", (unsigned long)blocks.count]);
    IACheck(complete && total == input.count, scenario,
            [NSString stringWithFormat:@"原文行与来源下标零丢失：块内合计 %lu 行 / 输入 %lu 行，来源下标 %@",
             (unsigned long)total, (unsigned long)input.count, complete ? @"0..n-1 完整" : @"有缺口或重复"]);
    IACheck(texts, scenario, @"块内没有空占位行（每行都有原文）");
}

/// 分组不得让一个块的包围盒套住另一个块：那意味着同一段的中间行被跳过，
/// 首尾行跨过中间行合并（阅读顺序被打乱，且给布局制造互相包含的原文区域）。
static void IACheckNoBlockNesting(NSArray<FYInlineTextBlock *> *blocks, NSString *scenario) {
    NSString *detail = @"";
    for (NSUInteger outerIndex = 0; outerIndex < blocks.count; outerIndex++) {
        for (NSUInteger innerIndex = 0; innerIndex < blocks.count; innerIndex++) {
            if (outerIndex == innerIndex) { continue; }
            CGRect outer = blocks[outerIndex].boundingBox;
            CGRect inner = blocks[innerIndex].boundingBox;
            BOOL contained = CGRectGetMinX(inner) >= CGRectGetMinX(outer) - 0.001 &&
                             CGRectGetMaxX(inner) <= CGRectGetMaxX(outer) + 0.001 &&
                             CGRectGetMinY(inner) >= CGRectGetMinY(outer) - 0.001 &&
                             CGRectGetMaxY(inner) <= CGRectGetMaxY(outer) + 0.001;
            BOOL strict = (CGRectGetMinY(inner) - CGRectGetMinY(outer) > 0.004) ||
                          (CGRectGetMaxY(outer) - CGRectGetMaxY(inner) > 0.004) ||
                          (CGRectGetMinX(inner) - CGRectGetMinX(outer) > 0.004) ||
                          (CGRectGetMaxX(outer) - CGRectGetMaxX(inner) > 0.004);
            if (contained && strict && detail.length == 0) {
                detail = [NSString stringWithFormat:@"B%lu<%@> %@ 套住了 B%lu<%@> %@（读序被打乱）",
                          (unsigned long)(outerIndex + 1), IAClip(blocks[outerIndex].text, 14), IARect(outer),
                          (unsigned long)(innerIndex + 1), IAClip(blocks[innerIndex].text, 14), IARect(inner)];
            }
        }
    }
    IACheck(detail.length == 0, scenario,
            [NSString stringWithFormat:@"没有块套住另一块（同页块之间不得穿插包含） %@", detail]);
}

#pragma mark - 布局辅助

static CGRect IADisplayFrameForBox(CGRect box, CGRect viewport) {
    return CGRectMake(NSMinX(viewport) + box.origin.x * NSWidth(viewport),
                      NSMinY(viewport) + box.origin.y * NSHeight(viewport),
                      box.size.width * NSWidth(viewport),
                      box.size.height * NSHeight(viewport));
}

static NSArray<FYInlineLayoutRequest *> *IARequests(NSArray<FYInlineTextBlock *> *blocks,
                                                    NSDictionary<NSString *, NSString *> *translations,
                                                    CGRect viewport) {
    NSMutableArray<FYInlineLayoutRequest *> *requests = [NSMutableArray array];
    for (FYInlineTextBlock *block in blocks) {
        NSString *translation = translations[block.text];
        if (translation.length == 0) { translation = translations[@"*"]; }
        if (translation.length == 0) { translation = @"译文占位文本"; }
        [requests addObject:[FYInlineLayoutRequest requestWithBlock:block
                                                        translation:translation
                                                        sourceFrame:IADisplayFrameForBox(block.boundingBox, viewport)]];
    }
    return requests;
}

/// 验收点 3：可见区域内、互不重叠、不遮挡任何别的原文块；
/// 另外顺手检查降级项不伪造位置、不出现空细条。
static void IACheckLegality(FYInlineLayoutResult *result,
                            NSArray<FYInlineLayoutRequest *> *requests,
                            CGRect viewport,
                            NSString *scenario) {
    BOOL inside = YES, noPair = YES, noCover = YES, cleanUnplaceable = YES, noStrip = YES;
    NSString *insideDetail = @"", *pairDetail = @"", *coverDetail = @"", *unplaceableDetail = @"", *stripDetail = @"";
    NSMutableArray<NSValue *> *placed = [NSMutableArray array];
    for (NSUInteger index = 0; index < result.placements.count; index++) {
        FYInlinePlacement *placement = result.placements[index];
        if (placement.mode == FYInlineDisplayModeUnplaceable) {
            if (!CGRectIsEmpty(placement.translationFrame) || placement.reason.length == 0) {
                cleanUnplaceable = NO;
                if (unplaceableDetail.length == 0) {
                    unplaceableDetail = [NSString stringWithFormat:@"<%@> frame=%@ reason=“%@”",
                                         IAClip(placement.block.text, 16), IARect(placement.translationFrame), placement.reason];
                }
            }
            continue;
        }
        CGRect frame = placement.translationFrame;
        if (CGRectGetMinX(frame) < NSMinX(viewport) - 1 || CGRectGetMaxX(frame) > NSMaxX(viewport) + 1 ||
            CGRectGetMinY(frame) < NSMinY(viewport) - 1 || CGRectGetMaxY(frame) > NSMaxY(viewport) + 1) {
            inside = NO;
            if (insideDetail.length == 0) {
                insideDetail = [NSString stringWithFormat:@"<%@> frame=%@ 期望在 viewport=%@ 内",
                                IAClip(placement.block.text, 16), IARect(frame), IARect(viewport)];
            }
        }
        if (NSWidth(frame) < 2 || NSHeight(frame) < 20) {
            noStrip = NO;
            if (stripDetail.length == 0) {
                stripDetail = [NSString stringWithFormat:@"<%@> mode=%ld frame=%@",
                               IAClip(placement.block.text, 16), (long)placement.mode, IARect(frame)];
            }
        }
        for (NSUInteger other = 0; other < requests.count; other++) {
            if (other == index) { continue; }
            CGRect source = requests[other].sourceFrame;
            if (NSWidth(source) < 2 || NSHeight(source) < 2) { continue; }
            if (CGRectIntersectsRect(frame, source)) {
                noCover = NO;
                if (coverDetail.length == 0) {
                    coverDetail = [NSString stringWithFormat:@"译文<%@> frame=%@ 压到第 %lu 个原文 %@",
                                   IAClip(placement.block.text, 16), IARect(frame), (unsigned long)(other + 1), IARect(source)];
                }
            }
        }
        for (NSValue *value in placed) {
            if (CGRectIntersectsRect(frame, value.rectValue)) {
                noPair = NO;
                if (pairDetail.length == 0) {
                    pairDetail = [NSString stringWithFormat:@"译文<%@> frame=%@ 与已放置 %@ 重叠",
                                  IAClip(placement.block.text, 16), IARect(frame), IARect(value.rectValue)];
                }
            }
        }
        [placed addObject:[NSValue valueWithRect:frame]];
    }
    IACheck(inside, scenario, [NSString stringWithFormat:@"所有译文框都在可见区域内 %@", insideDetail]);
    IACheck(noPair, scenario, [NSString stringWithFormat:@"所有译文框互不重叠 %@", pairDetail]);
    IACheck(noCover, scenario, [NSString stringWithFormat:@"译文框不遮挡任何别的原文块 %@", coverDetail]);
    IACheck(cleanUnplaceable, scenario, [NSString stringWithFormat:@"不可放置项 frame 为空且 reason 非空 %@", unplaceableDetail]);
    IACheck(noStrip, scenario, [NSString stringWithFormat:@"没有空细条（可见框高度 ≥ 20） %@", stripDetail]);
}

/// 不允许静默丢块：结果与输入同序、逐项对应、可见 + 不可放置 = 输入。
static void IACheckCoverage(FYInlineLayoutResult *result,
                            NSArray<FYInlineLayoutRequest *> *requests,
                            NSString *scenario) {
    BOOL aligned = result.placements.count == requests.count;
    NSString *mismatch = @"";
    for (NSUInteger index = 0; aligned && index < requests.count; index++) {
        NSString *actual = result.placements[index].sourceBlockID ?: @"";
        NSString *expected = requests[index].block.blockID ?: @"";
        if (![actual isEqualToString:expected]) {
            aligned = NO;
            mismatch = [NSString stringWithFormat:@"第 %lu 项 sourceBlockID=<%@> 期望 <%@>",
                        (unsigned long)(index + 1), IAClip(actual, 24), IAClip(expected, 24)];
        }
    }
    IACheck(aligned, scenario, [NSString stringWithFormat:@"结果与输入同序且逐项对应（%lu/%lu）%@",
                                (unsigned long)result.placements.count, (unsigned long)requests.count, mismatch]);
    IACheck(result.placements.count == requests.count &&
            result.visiblePlacements.count + result.unplaceableBlockIDs.count == result.placements.count,
            scenario, [NSString stringWithFormat:@"没有静默丢块：可见 %lu + 不可放置 %lu = 输入 %lu",
                       (unsigned long)result.visiblePlacements.count,
                       (unsigned long)result.unplaceableBlockIDs.count, (unsigned long)requests.count]);
}

static CGFloat IALineHeight(FYInlineLayoutEngine *engine, FYInlinePlacement *placement) {
    NSFont *font = placement.font ?: [engine longBodyFont];
    return ceil(font.ascender - font.descender + font.leading) + engine.longLineSpacing;
}

#pragma mark - 场景数据

/// 左邮件列表（4 项）+ 右长正文（4 行一段）。左列与右列分栏明确。
static NSArray<FYInlineTextLine *> *IALeftRightPageLines(void) {
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray array];
    NSInteger cursor = 0;
    IAAddColumn(lines, @[@"受信トレイ", @"下書き保存", @"送信済み", @"迷惑メール対策"],
                .05, .82, .17, .030, .085, &cursor);
    IAAddColumn(lines, @[@"昨日の打ち合わせの内容をまとめました。",
                         @"資料は共有フォルダに置いてあります。",
                         @"確認できたら返信をお願いします。",
                         @"締め切りは今週の金曜日です。"],
                .55, .70, .40, .032, .045, &cursor);
    return lines;
}

/// 密集菜单：8 个紧挨的短条目（条目本身很短、间距紧）。
static NSArray<FYInlineTextLine *> *IATightMenuLines(void) {
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray array];
    NSInteger cursor = 0;
    IAAddColumn(lines, @[@"スタート", @"コンティニュー", @"オプション", @"ロード",
                         @"セーブ", @"ランキング", @"ヘルプ", @"終了"],
                .10, .88, .20, .028, .045, &cursor);
    return lines;
}

/// 规则排列的**宽**菜单：8 条宽度 0.32、行高 0.030、行距 0.060（正好 2 倍行高）。
/// 这不是实现方测试用的“细窄紧贴菜单”，而是很常见的设置列表形态。
static NSArray<FYInlineTextLine *> *IAWideMenuLines(void) {
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray array];
    NSInteger cursor = 0;
    IAAddColumn(lines, @[@"キャラクター設定", @"サウンド設定変更", @"グラフィック設定", @"操作方法の確認項目",
                         @"言語切り替え設定", @"データ保存と復元", @"ネットワーク接続", @"ゲーム終了の確認"],
                .06, .90, .32, .030, .060, &cursor);
    return lines;
}

/// 标题（大字）+ 正文（小字）。
static NSArray<FYInlineTextLine *> *IATitleBodyLines(void) {
    NSInteger cursor = 0;
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray array];
    IAAddColumn(lines, @[@"お知らせとご案内"], .10, .80, .30, .055, .10, &cursor);
    IAAddColumn(lines, @[@"本日は新しいイベントを開催します。", @"ぜひご参加ください。"],
                .10, .735, .42, .024, .030, &cursor);
    return lines;
}

/// 同一行左右两栏正文，栏间距由参数控制。每栏都是独立的三行段落。
static NSArray<FYInlineTextLine *> *IATwoColumnsAtGutter(CGFloat gutter) {
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray array];
    NSInteger cursor = 0;
    CGFloat rightX = .05 + .28 + gutter;
    CGFloat top = .70;
    NSArray<NSString *> *left = @[@"左側のコラムの一行目の本文です",
                                  @"左側のコラムの二行目の本文です",
                                  @"左側のコラムの三行目の本文です"];
    NSArray<NSString *> *right = @[@"右側のコラムの一行目の本文です",
                                   @"右側のコラムの二行目の本文です",
                                   @"右側のコラムの三行目の本文です"];
    for (NSUInteger index = 0; index < 3; index++) {
        [lines addObject:IALine(left[index], IABox(.05, top - (CGFloat)index * .042, .28, .034), cursor)];
        cursor += 1;
        [lines addObject:IALine(right[index], IABox(rightX, top - (CGFloat)index * .042, .28, .034), cursor)];
        cursor += 1;
    }
    return lines;
}

/// 三栏页面：栏间距 0.06（常规排版间距），三栏各自一段。
static NSArray<FYInlineTextLine *> *IAThreeColumnLines(CGFloat gutter) {
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray array];
    NSInteger cursor = 0;
    NSArray<NSString *> *columnA = @[@"第一欄の一行目の本文テキスト", @"第一欄の二行目の本文テキスト", @"第一欄の三行目の本文テキスト"];
    NSArray<NSString *> *columnB = @[@"第二欄の一行目の本文テキスト", @"第二欄の二行目の本文テキスト", @"第二欄の三行目の本文テキスト"];
    NSArray<NSString *> *columnC = @[@"第三欄の一行目の本文テキスト", @"第三欄の二行目の本文テキスト", @"第三欄の三行目の本文テキスト"];
    CGFloat step = .26 + gutter;
    for (NSUInteger index = 0; index < 3; index++) {
        [lines addObject:IALine(columnA[index], IABox(.04, .70 - (CGFloat)index * .042, .26, .034), cursor++)];
        [lines addObject:IALine(columnB[index], IABox(.04 + step, .70 - (CGFloat)index * .042, .26, .034), cursor++)];
        [lines addObject:IALine(columnC[index], IABox(.04 + step * 2, .70 - (CGFloat)index * .042, .26, .034), cursor++)];
    }
    return lines;
}

/// 右对齐条目：右边缘对齐、左边缘参差（宽度相近）。
static NSArray<FYInlineTextLine *> *IARightAlignedLines(void) {
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray array];
    NSArray<NSString *> *items = @[@"こうげき力", @"ぼうぎょ力", @"すばやさ", @"たいりょく"];
    NSArray<NSNumber *> *widths = @[@(.10), @(.11), @(.09), @(.10)];
    CGFloat right = .45;
    CGFloat top = .80;
    for (NSUInteger index = 0; index < items.count; index++) {
        CGFloat width = widths[index].doubleValue;
        [lines addObject:IALine(items[index], IABox(right - width, top - (CGFloat)index * .048, width, .028), (NSInteger)index)];
    }
    return lines;
}

/// 超窄竖列：宽度只有 0.07 的长正文竖排五行。
static NSArray<FYInlineTextLine *> *IANarrowColumnLines(void) {
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray array];
    NSInteger cursor = 0;
    IAAddColumn(lines, @[@"狭い列の一行目の長い本文テキスト",
                         @"狭い列の二行目の長い本文テキスト",
                         @"狭い列の三行目の長い本文テキスト",
                         @"狭い列の四行目の長い本文テキスト",
                         @"狭い列の五行目の長い本文テキスト"],
                .90, .70, .07, .045, .050, &cursor);
    return lines;
}

/// 整屏只有一行超长正文。
static NSArray<FYInlineTextLine *> *IASingleLongLine(void) {
    NSString *text = @"これは画面いっぱいに広がる非常に長い一行の本文で、折り返さずに表示される想定のテキストです。翻訳結果も同程度に長くなります。";
    return @[IALine(text, IABox(.05, .45, .90, .040), 0)];
}

#pragma mark - A. 分组：不跨栏、不误并

static void TestGroupingLeftRightPage(void) {
    NSString *scenario = @"分组·左右分栏";
    NSArray<FYInlineTextLine *> *lines = IALeftRightPageLines();
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(lines);
    NSLog(@"  左列表+右正文 → %@", IABlockDump(blocks));

    IACheck(blocks.count == 5, scenario,
            [NSString stringWithFormat:@"左列表 4 项 + 右正文 1 段 = 5 块（实际 %lu；%@）",
             (unsigned long)blocks.count, IABlockDump(blocks)]);
    BOOL noStraddle = YES;
    NSString *straddle = @"";
    for (FYInlineTextBlock *block in blocks) {
        if (block.boundingBox.size.width >= 0.45) {
            noStraddle = NO;
            if (straddle.length == 0) {
                straddle = [NSString stringWithFormat:@"<%@> 宽度 %.3f", IAClip(block.text, 20), block.boundingBox.size.width];
            }
        }
    }
    IACheck(noStraddle, scenario, [NSString stringWithFormat:@"没有横跨两栏的大块（每块宽度 < 0.45）%@", straddle]);

    FYInlineTextBlock *body = IABlockContaining(blocks, @"昨日の打ち合わせ");
    IACheck(body != nil && body.lineCount == 4 && body.kind == FYInlineBlockKindLong, scenario,
            [NSString stringWithFormat:@"右侧正文并成 1 块 4 行且分类为长卡（实际 %@ / %ld 行 / kind=%ld）",
             body ? @"找到" : @"缺失", body ? (long)body.lineCount : 0L, body ? (long)body.kind : -1L]);
    for (NSString *label in @[@"受信トレイ", @"下書き保存", @"送信済み", @"迷惑メール対策"]) {
        FYInlineTextBlock *item = IABlockContaining(blocks, label);
        IACheck(item != nil && item.lineCount == 1 && item.kind == FYInlineBlockKindShort, scenario,
                [NSString stringWithFormat:@"左列表项“%@”独立成短标签块（实际 %@ / %ld 行 / kind=%ld）",
                 label, item ? @"找到" : @"缺失", item ? (long)item.lineCount : 0L, item ? (long)item.kind : -1L]);
    }
    // 左右两栏的文字绝不能出现在同一块里。
    BOOL mixed = NO;
    NSString *mixedDetail = @"";
    for (FYInlineTextBlock *block in blocks) {
        if (IATextHasAny(block.text, @[@"受信トレイ", @"下書き保存", @"送信済み", @"迷惑メール対策"]) &&
            IATextHasAny(block.text, @[@"昨日の打ち合わせ", @"資料は共有フォルダ", @"確認できたら", @"締め切りは"])) {
            mixed = YES;
            mixedDetail = IAClip(block.text, 60);
        }
    }
    IACheck(!mixed, scenario, [NSString stringWithFormat:@"左列表与右侧长正文绝不并成一块 %@", mixedDetail]);
    IACheckPreservation(blocks, lines, scenario);
}

static void TestGroupingDenseMenu(void) {
    NSString *scenario = @"分组·密集菜单";
    NSArray<FYInlineTextLine *> *lines = IATightMenuLines();
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(lines);
    IACheck(blocks.count == 8, scenario,
            [NSString stringWithFormat:@"8 个紧挨短条目保持 8 块（实际 %lu；%@）",
             (unsigned long)blocks.count, IABlockDump(blocks)]);
    BOOL allShort = blocks.count == 8;
    for (FYInlineTextBlock *block in blocks) {
        if (block.kind != FYInlineBlockKindShort) { allShort = NO; }
    }
    IACheck(allShort, scenario, @"密集菜单每一项都保持短标签（不升级成长卡）");
    IACheckPreservation(blocks, lines, scenario);
}

/// 对抗形态 ①：规则排列的**宽条目**菜单（宽 0.32 / 行高 0.030 / 行距 0.060）。
static void TestGroupingWideRegularMenu(void) {
    NSString *scenario = @"分组·规则宽菜单";
    NSArray<FYInlineTextLine *> *lines = IAWideMenuLines();
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(lines);
    NSLog(@"  规则宽菜单（w=.32 h=.030 pitch=.060）→ %@", IABlockDump(blocks));
    IACheck(blocks.count == 8, scenario,
            [NSString stringWithFormat:@"8 个规则排列的宽条目仍应保持 8 块（期望 8，实际 %lu；%@）",
             (unsigned long)blocks.count, IABlockDump(blocks)]);
    IACheckPreservation(blocks, lines, scenario);
}

static void TestGroupingTitleVersusBody(void) {
    NSString *scenario = @"分组·标题与正文字号";
    NSArray<FYInlineTextLine *> *lines = IATitleBodyLines();
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(lines);
    NSLog(@"  标题(0.055) + 正文(0.024) → %@", IABlockDump(blocks));
    IACheck(blocks.count == 2, scenario,
            [NSString stringWithFormat:@"字号差明显时标题与正文分成 2 块（实际 %lu；%@）",
             (unsigned long)blocks.count, IABlockDump(blocks)]);
    FYInlineTextBlock *title = IABlockContaining(blocks, @"お知らせとご案内");
    FYInlineTextBlock *body = IABlockContaining(blocks, @"本日は新しいイベント");
    IACheck(title != nil && title.lineCount == 1, scenario, @"标题单独成块、只有 1 行");
    IACheck(body != nil && body.lineCount == 2, scenario, @"正文两行并成一块");
    IACheckPreservation(blocks, lines, scenario);
}

/// 对抗形态 ②：同一行左右两栏正文，栏间距 0.018（窄栏距）。
static void TestGroupingNarrowGutterColumns(void) {
    NSString *scenario = @"分组·窄栏距双栏";
    NSArray<FYInlineTextLine *> *lines = IATwoColumnsAtGutter(0.018);
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(lines);
    NSLog(@"  双栏栏距 0.018 → %@", IABlockDump(blocks));
    BOOL mixed = NO;
    NSString *mixedDetail = @"";
    for (FYInlineTextBlock *block in blocks) {
        if ([block.text containsString:@"左側のコラム"] && [block.text containsString:@"右側のコラム"]) {
            mixed = YES;
            if (mixedDetail.length == 0) { mixedDetail = IABlockDump(@[block]); }
        }
    }
    IACheck(!mixed, scenario, [NSString stringWithFormat:@"栏距 0.018 时左右两栏不得并成一块 %@", mixedDetail]);
    BOOL narrow = YES;
    NSString *wideDetail = @"";
    for (FYInlineTextBlock *block in blocks) {
        if (block.boundingBox.size.width > 0.32) {
            narrow = NO;
            if (wideDetail.length == 0) {
                wideDetail = [NSString stringWithFormat:@"块宽 %.3f，期望 ≤ 0.32（单栏宽 0.28）", block.boundingBox.size.width];
            }
        }
    }
    IACheck(narrow, scenario, [NSString stringWithFormat:@"没有块宽超过单栏宽度 %@", wideDetail]);
    IACheckNoBlockNesting(blocks, scenario);

    // 对照组：同样的排版，栏距 0.05（常规间距）必须分成两块。
    NSString *control = @"分组·常规栏距双栏(对照)";
    NSArray<FYInlineTextLine *> *wideGutterLines = IATwoColumnsAtGutter(0.05);
    NSArray<FYInlineTextBlock *> *wideGutterBlocks = IAGroup(wideGutterLines);
    IACheck(wideGutterBlocks.count == 2, control,
            [NSString stringWithFormat:@"栏距 0.05 时两栏各自成块、每块 3 行（实际 %lu 块；%@）",
             (unsigned long)wideGutterBlocks.count, IABlockDump(wideGutterBlocks)]);
    IACheckNoBlockNesting(wideGutterBlocks, control);
    IACheckPreservation(wideGutterBlocks, wideGutterLines, control);

    // 下游影响：同一段被拆散/穿插后，布局还能不能把每一块都放下。
    CGRect viewport = CGRectMake(0, 0, 1440, 900);
    NSArray<FYInlineLayoutRequest *> *controlRequests = IARequests(wideGutterBlocks, @{@"*": @"这一栏的正文译文内容，长度足以形成一张长卡。"}, viewport);
    FYInlineLayoutResult *controlResult = [[FYInlineLayoutEngine defaultEngine] layoutRequests:controlRequests viewport:viewport previous:nil];
    NSLog(@"  常规栏距双栏（分组穿插后）布局：%@", IAPlacementsDump(controlResult));
    IACheckLegality(controlResult, controlRequests, viewport, control);
    IACheckCoverage(controlResult, controlRequests, control);
}

/// 对抗形态 ③：三栏页面（栏距 0.06 常规）。
static void TestGroupingThreeColumns(void) {
    NSString *scenario = @"分组·三栏页面";
    NSArray<FYInlineTextLine *> *lines = IAThreeColumnLines(0.06);
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(lines);
    NSLog(@"  三栏（栏距 0.06）→ %@", IABlockDump(blocks));
    IACheck(blocks.count == 3, scenario,
            [NSString stringWithFormat:@"三栏各自成块（期望 3，实际 %lu；%@）",
             (unsigned long)blocks.count, IABlockDump(blocks)]);
    BOOL narrow = YES;
    for (FYInlineTextBlock *block in blocks) {
        if (block.boundingBox.size.width > 0.30) { narrow = NO; }
    }
    IACheck(narrow, scenario, @"没有跨栏合并（每块宽度 ≤ 0.30）");
    IACheckNoBlockNesting(blocks, scenario);
    IACheckPreservation(blocks, lines, scenario);

    // 对抗：同样的三栏，栏距收到 0.018。
    NSString *tightScenario = @"分组·三栏窄栏距";
    NSArray<FYInlineTextLine *> *tightLines = IAThreeColumnLines(0.018);
    NSArray<FYInlineTextBlock *> *tightBlocks = IAGroup(tightLines);
    NSLog(@"  三栏（栏距 0.018）→ %@", IABlockDump(tightBlocks));
    BOOL perColumn = tightBlocks.count == 3;
    for (FYInlineTextBlock *block in tightBlocks) {
        if (block.boundingBox.size.width > 0.30) { perColumn = NO; }
    }
    IACheck(perColumn, tightScenario,
            [NSString stringWithFormat:@"栏距 0.018 时三栏仍不得跨栏合并（期望 3 块且宽度 ≤ 0.30，实际 %lu 块；%@）",
             (unsigned long)tightBlocks.count, IABlockDump(tightBlocks)]);
    IACheckNoBlockNesting(tightBlocks, tightScenario);
    IACheckPreservation(tightBlocks, tightLines, tightScenario);
}

/// 对抗形态 ④：右对齐条目（右边缘对齐、左边缘参差）。
static void TestGroupingRightAligned(void) {
    NSString *scenario = @"分组·右对齐条目";
    NSArray<FYInlineTextLine *> *lines = IARightAlignedLines();
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(lines);
    IACheck(blocks.count == 4, scenario,
            [NSString stringWithFormat:@"4 个右对齐独立条目保持 4 块（实际 %lu；%@）",
             (unsigned long)blocks.count, IABlockDump(blocks)]);
    IACheckPreservation(blocks, lines, scenario);
}

/// 对抗形态 ⑤：超窄竖列长正文（宽 0.07）。
static void TestGroupingNarrowColumn(void) {
    NSString *scenario = @"分组·超窄竖列";
    NSArray<FYInlineTextLine *> *lines = IANarrowColumnLines();
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(lines);
    IACheck(blocks.count == 1 && blocks.firstObject.lineCount == 5, scenario,
            [NSString stringWithFormat:@"窄列 5 行并成 1 块（实际 %lu 块 / %ld 行）",
             (unsigned long)blocks.count, blocks.count ? (long)blocks.firstObject.lineCount : 0L]);
    IACheck(blocks.count == 1 && blocks.firstObject.kind == FYInlineBlockKindLong, scenario,
            @"窄列长正文分类为长卡");
    IACheckNoBlockNesting(blocks, scenario);
    IACheckPreservation(blocks, lines, scenario);
}

/// 对抗形态 ⑥：整屏只有一行超长正文。
static void TestGroupingSingleLongLine(void) {
    NSString *scenario = @"分组·整屏单行长正文";
    NSArray<FYInlineTextLine *> *lines = IASingleLongLine();
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(lines);
    IACheck(blocks.count == 1 && blocks.firstObject.kind == FYInlineBlockKindLong, scenario,
            [NSString stringWithFormat:@"单行超长正文分类为长卡（实际 %lu 块 / kind=%ld）",
             (unsigned long)blocks.count, blocks.count ? (long)blocks.firstObject.kind : -1L]);
    IACheckPreservation(blocks, lines, scenario);
}

#pragma mark - B. 原文与译文都不丢失

static void TestContentPreservationAndDedup(void) {
    NSString *scenario = @"内容·去重与异位同文";
    FYInlineGrouper *grouper = [FYInlineGrouper defaultGrouper];

    // 同一处重复识别：文字一样、位置重叠 → 只留置信度更高的一条。
    NSArray<FYInlineTextLine *> *duplicateLines = @[
        [FYInlineTextLine lineWithText:@"重複した見出しです" rect:IABox(.10, .80, .25, .030) confidence:0.4 sourceIndex:0],
        [FYInlineTextLine lineWithText:@"重複した見出しです" rect:IABox(.102, .8005, .25, .030) confidence:0.9 sourceIndex:1],
        [FYInlineTextLine lineWithText:@"別の位置にある見出し" rect:IABox(.60, .30, .25, .030) confidence:0.7 sourceIndex:2]
    ];
    NSArray<FYInlineTextLine *> *deduplicated = [grouper deduplicatedLines:duplicateLines];
    IACheck(deduplicated.count == 2, scenario,
            [NSString stringWithFormat:@"同一处重复识别只留一条、异位同文各自保留（实际 %lu 条）",
             (unsigned long)deduplicated.count]);
    CGFloat keptConfidence = 0;
    for (FYInlineTextLine *line in deduplicated) {
        if ([line.text containsString:@"重複した"]) { keptConfidence = line.confidence; }
    }
    IACheck(fabs(keptConfidence - 0.9) < 0.001, scenario,
            [NSString stringWithFormat:@"同一处重复保留置信度更高的一条（期望 0.9，实际 %.2f）", keptConfidence]);

    // 同一段文字出现在两个不同位置：必须是两块，且各自有排版。
    NSString *scenario2 = @"内容·异位同文各自排版";
    NSArray<FYInlineTextLine *> *sameTextLines = @[
        IALine(@"同じ内容の見出しです", IABox(.10, .80, .25, .030), 0),
        IALine(@"同じ内容の見出しです", IABox(.60, .30, .25, .030), 1)
    ];
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(sameTextLines);
    IACheck(blocks.count == 2, scenario2,
            [NSString stringWithFormat:@"同一文字在两个位置 = 2 块（实际 %lu 块）", (unsigned long)blocks.count]);
    IACheck(blocks.count == 2 && ![blocks[0].blockID isEqualToString:blocks[1].blockID], scenario2,
            @"两个位置的块身份（blockID）不同");
    CGRect viewport = CGRectMake(0, 0, 1200, 800);
    NSArray<FYInlineLayoutRequest *> *requests = IARequests(blocks, @{@"*": @"同样内容的小标题"}, viewport);
    FYInlineLayoutResult *result = [[FYInlineLayoutEngine defaultEngine] layoutRequests:requests viewport:viewport previous:nil];
    IACheck(result.placements.count == 2 &&
            result.placements[0].mode != FYInlineDisplayModeUnplaceable &&
            result.placements[1].mode != FYInlineDisplayModeUnplaceable, scenario2,
            @"两个位置各自得到排版（都不是 unplaceable）");
    IACheck(result.placements.count == 2 && !CGRectIntersectsRect(result.placements[0].translationFrame, result.placements[1].translationFrame),
            scenario2, @"两个位置的译文框互不重叠且位置不同");
    IACheckLegality(result, requests, viewport, scenario2);
    IACheckCoverage(result, requests, scenario2);
}

#pragma mark - C. 布局合法性

static void TestLayoutLeftRightPage(void) {
    NSString *scenario = @"布局·左右分栏";
    CGRect viewport = CGRectMake(0, 0, 1440, 900);
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(IALeftRightPageLines());
    NSDictionary<NSString *, NSString *> *translations = @{
        @"*": @"短标签译文",
        @"昨日の打ち合わせの内容をまとめました。\n資料は共有フォルダに置いてあります。\n確認できたら返信をお願いします。\n締め切りは今週の金曜日です。":
            @"昨天的会议内容已经整理好了。资料放在共享文件夹里。确认之后请回复我。截止日期是本周五。"
    };
    NSArray<FYInlineLayoutRequest *> *requests = IARequests(blocks, translations, viewport);
    FYInlineLayoutResult *result = [[FYInlineLayoutEngine defaultEngine] layoutRequests:requests viewport:viewport previous:nil];
    IACheckLegality(result, requests, viewport, scenario);
    IACheckCoverage(result, requests, scenario);
}

/// 铺满画面的短条目：每块要么有位置、要么被明确标记，绝不强盖别的原文。
static void TestLayoutPackedScreen(void) {
    NSString *scenario = @"布局·铺满画面";
    CGRect viewport = CGRectMake(0, 0, 700, 460);
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray array];
    NSInteger cursor = 0;
    for (NSUInteger row = 0; row < 5; row++) {
        for (NSUInteger column = 0; column < 3; column++) {
            NSString *text = [NSString stringWithFormat:@"項目%lu-%lu", (unsigned long)row, (unsigned long)column];
            [lines addObject:IALine(text, IABox(.02 + (CGFloat)column * .33, .88 - (CGFloat)row * .17, .30, .10), cursor)];
            cursor += 1;
        }
    }
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(lines);
    NSArray<FYInlineLayoutRequest *> *requests = IARequests(blocks, @{@"*": @"菜单项译文"}, viewport);
    FYInlineLayoutResult *result = [[FYInlineLayoutEngine defaultEngine] layoutRequests:requests viewport:viewport previous:nil];
    IACheckLegality(result, requests, viewport, scenario);
    IACheckCoverage(result, requests, scenario);
    IACheck(result.visiblePlacements.count + result.unplaceableBlockIDs.count == requests.count, scenario,
            [NSString stringWithFormat:@"每块要么有位置、要么被明确标记（可见 %lu / 不可放置 %lu / 输入 %lu）",
             (unsigned long)result.visiblePlacements.count, (unsigned long)result.unplaceableBlockIDs.count,
             (unsigned long)requests.count]);
}

static void TestLayoutThreeColumns(void) {
    NSString *scenario = @"布局·三栏";
    CGRect viewport = CGRectMake(0, 0, 1440, 900);
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(IAThreeColumnLines(0.06));
    NSArray<FYInlineLayoutRequest *> *requests = IARequests(blocks, @{@"*": @"这一栏的正文译文内容，长度足以形成一张长卡。"}, viewport);
    FYInlineLayoutResult *result = [[FYInlineLayoutEngine defaultEngine] layoutRequests:requests viewport:viewport previous:nil];
    NSLog(@"  三栏（栏距 0.06）布局：%@", IAPlacementsDump(result));
    IACheckLegality(result, requests, viewport, scenario);
    IACheckCoverage(result, requests, scenario);
}

#pragma mark - D. 长卡可读下限

static FYInlineTextBlock *IALongBodyBlock(void) {
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(IALeftRightPageLines());
    return IABlockContaining(blocks, @"昨日の打ち合わせ");
}

static void TestLongCardReadability(void) {
    NSString *scenario = @"长卡·可读下限与滚动";
    CGRect viewport = CGRectMake(0, 0, 1440, 900);
    FYInlineTextBlock *body = IALongBodyBlock();
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    if (!body) {
        IACheck(NO, scenario, @"夹具缺失：没有找到长正文块");
        return;
    }
    NSString *translation = @"新的季节活动即将开始。活动期间还会推出限定服装，请千万不要错过。此外还计划公开期间限定的特别剧情，"
                             "详情请查看官方网站。为了让这段译文接近卡片的可视高度上限，这里再补充一些说明文字，"
                             "活动期间每天登录还可以领取一份小礼物。";

    NSArray<FYInlineLayoutRequest *> *requests = @[[FYInlineLayoutRequest requestWithBlock:body
                                                                              translation:translation
                                                                              sourceFrame:IADisplayFrameForBox(body.boundingBox, viewport)]];
    FYInlineLayoutResult *result = [engine layoutRequests:requests viewport:viewport previous:nil];
    FYInlinePlacement *placement = result.placements.firstObject;
    CGFloat lineHeight = IALineHeight(engine, placement);
    BOOL longMode = placement != nil &&
        (placement.mode == FYInlineDisplayModeFullCard || placement.mode == FYInlineDisplayModeScrollingCard);
    IACheck(longMode, scenario,
            [NSString stringWithFormat:@"长正文给出长卡而不是紧凑入口/细条（mode=%ld，高度 %.0f，原因“%@”）",
             placement ? (long)placement.mode : -1L, placement ? NSHeight(placement.translationFrame) : 0.0,
             placement.reason ?: @""]);
    if (!longMode) { return; }
    IACheck(NSHeight(placement.translationFrame) >= engine.minimumCardHeight - 1, scenario,
            [NSString stringWithFormat:@"卡片高度 %.0f ≥ 引擎最小可读高度 %.0f",
             NSHeight(placement.translationFrame), engine.minimumCardHeight]);
    IACheck(placement.bodyViewportHeight >= 3 * lineHeight - 1, scenario,
            [NSString stringWithFormat:@"正文视口 %.0f ≥ 3 行（行高 %.0f，3 行 = %.0f）",
             placement.bodyViewportHeight, lineHeight, 3 * lineHeight]);
    IACheck(placement.font.pointSize >= engine.longBodyFontSize - 0.01, scenario,
            [NSString stringWithFormat:@"正文用正常阅读字号（实际 %.1fpt，期望 %.1fpt）",
             placement.font.pointSize, engine.longBodyFontSize]);
    IACheck(placement.bodyViewportFrame.size.height > 0 &&
            NSWidth(placement.bodyViewportFrame) > 0, scenario,
            [NSString stringWithFormat:@"长卡正文视口几何有效 %@", IARect(placement.bodyViewportFrame)]);
    IACheckLegality(result, requests, viewport, scenario);

    // 超长译文：文档高度必须大于视口高度（能滚到底）。
    NSString *scenario2 = @"长卡·超长译文可滚到底";
    NSMutableString *huge = [NSMutableString string];
    for (NSUInteger index = 0; index < 8; index++) {
        [huge appendString:@"这一段用来把译文撑到远超卡片高度，保证文档高度大于可视视口，用户必须滚动才能读到结尾。"];
    }
    NSArray<FYInlineLayoutRequest *> *hugeRequests = @[[FYInlineLayoutRequest requestWithBlock:body
                                                                                 translation:huge
                                                                                 sourceFrame:IADisplayFrameForBox(body.boundingBox, viewport)]];
    FYInlineLayoutResult *hugeResult = [engine layoutRequests:hugeRequests viewport:viewport previous:nil];
    FYInlinePlacement *hugePlacement = hugeResult.placements.firstObject;
    IACheck(hugePlacement.mode == FYInlineDisplayModeScrollingCard, scenario2,
            [NSString stringWithFormat:@"超长译文给出可滚动长卡（mode=%ld）", (long)hugePlacement.mode]);
    IACheck(hugePlacement.scrollable && hugePlacement.measuredContentHeight > hugePlacement.bodyViewportHeight + 0.5, scenario2,
            [NSString stringWithFormat:@"文档高度 %.0f > 视口高度 %.0f（可滚到底）",
             hugePlacement.measuredContentHeight, hugePlacement.bodyViewportHeight]);
    IACheck(hugePlacement.bodyViewportHeight >= 3 * IALineHeight(engine, hugePlacement) - 1, scenario2,
            @"超长译文时正文视口仍不低于三行");
    IACheckLegality(hugeResult, hugeRequests, viewport, scenario2);

    // 短译文（但原文是长正文）：仍然不能出现“只有标题的卡”。
    NSString *scenario3 = @"长卡·短译文不低于可读下限";
    NSArray<FYInlineLayoutRequest *> *shortRequests = @[[FYInlineLayoutRequest requestWithBlock:body
                                                                                  translation:@"很短。"
                                                                                  sourceFrame:IADisplayFrameForBox(body.boundingBox, viewport)]];
    FYInlineLayoutResult *shortResult = [engine layoutRequests:shortRequests viewport:viewport previous:nil];
    FYInlinePlacement *shortPlacement = shortResult.placements.firstObject;
    IACheck(NSHeight(shortPlacement.translationFrame) >= engine.minimumCardHeight - 1, scenario3,
            [NSString stringWithFormat:@"短译文卡片高度 %.0f ≥ 最小可读高度 %.0f（不是只有标题的卡）",
             NSHeight(shortPlacement.translationFrame), engine.minimumCardHeight]);
    IACheck(shortPlacement.bodyViewportHeight >= 3 * IALineHeight(engine, shortPlacement) - 1, scenario3,
            [NSString stringWithFormat:@"短译文卡片正文视口 %.0f 仍 ≥ 三行", shortPlacement.bodyViewportHeight]);
}

#pragma mark - E. 降级链

static void TestDegradationChain(void) {
    // 画面连三行正文都放不下 → 紧凑入口，而不是细条。
    NSString *scenario = @"降级·空间不足给紧凑入口";
    CGRect tiny = CGRectMake(0, 0, 520, 170);
    NSArray<FYInlineTextLine *> *lines = @[
        IALine(@"本文が入りきらない狭い画面のテストです。", IABox(.02, .55, .95, .20), 0),
        IALine(@"続きの行もここにあります。", IABox(.02, .30, .95, .20), 1)
    ];
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(lines);
    NSArray<FYInlineLayoutRequest *> *requests = IARequests(blocks, @{@"*": @"这是放不进窄画面的长译文。"}, tiny);
    FYInlineLayoutResult *result = [[FYInlineLayoutEngine defaultEngine] layoutRequests:requests viewport:tiny previous:nil];
    FYInlinePlacement *placement = result.placements.firstObject;
    IACheck(placement.mode == FYInlineDisplayModeCompactEntry, scenario,
            [NSString stringWithFormat:@"连三行都放不下时给出紧凑入口（期望 CompactEntry，实际 mode=%ld，frame=%@，原因“%@”）",
             (long)placement.mode, IARect(placement.translationFrame), placement.reason ?: @""]);
    IACheck(NSHeight(placement.translationFrame) >= 30, scenario,
            [NSString stringWithFormat:@"紧凑入口有可点击高度（实际 %.0f，期望 ≥ 30，不是空细条）",
             NSHeight(placement.translationFrame)]);
    IACheck(placement.compactEntry && placement.reason.length > 0, scenario,
            [NSString stringWithFormat:@"紧凑入口带降级原因：“%@”", placement.reason ?: @""]);
    IACheckLegality(result, requests, tiny, scenario);
    IACheckCoverage(result, requests, scenario);

    // 原文块互相重叠、所有候选都不合法 → Unplaceable，且不伪造位置。
    NSString *scenario2 = @"降级·重叠原文不可放置";
    CGRect cramped = CGRectMake(0, 0, 300, 170);
    NSArray<FYInlineTextLine *> *overlapLines = @[
        IALine(@"重なった見出しA", IABox(.02, .03, .95, .90), 0),
        IALine(@"重なった見出しB", IABox(.05, .06, .90, .85), 1)
    ];
    NSArray<FYInlineTextBlock *> *overlapBlocks = IAGroup(overlapLines);
    NSArray<FYInlineLayoutRequest *> *overlapRequests = IARequests(overlapBlocks, @{@"*": @"重叠标题的译文"}, cramped);
    FYInlineLayoutResult *overlapResult = [[FYInlineLayoutEngine defaultEngine] layoutRequests:overlapRequests viewport:cramped previous:nil];
    IACheck(overlapResult.unplaceableBlockIDs.count == overlapBlocks.count, scenario2,
            [NSString stringWithFormat:@"重叠原文块全部被标记为不可放置（不可放置 %lu / 输入 %lu）",
             (unsigned long)overlapResult.unplaceableBlockIDs.count, (unsigned long)overlapBlocks.count]);
    for (FYInlinePlacement *placement in overlapResult.placements) {
        IACheck(placement.mode == FYInlineDisplayModeUnplaceable, scenario2,
                [NSString stringWithFormat:@"“%@”模式为 Unplaceable（实际 %ld）",
                 IAClip(placement.block.text, 16), (long)placement.mode]);
        IACheck(CGRectIsEmpty(placement.translationFrame), scenario2,
                [NSString stringWithFormat:@"“%@”没有伪造位置（frame=%@）",
                 IAClip(placement.block.text, 16), IARect(placement.translationFrame)]);
        IACheck(placement.reason.length > 0, scenario2,
                [NSString stringWithFormat:@"“%@”给出非空原因：“%@”", IAClip(placement.block.text, 16), placement.reason ?: @""]);
    }
    IACheckLegality(overlapResult, overlapRequests, cramped, scenario2);
    IACheckCoverage(overlapResult, overlapRequests, scenario2);
}

#pragma mark - F. 帧间稳定

static void TestFrameStability(void) {
    NSString *scenario = @"稳定·同输入两次";
    CGRect viewport = CGRectMake(0, 0, 1440, 900);
    NSArray<FYInlineTextLine *> *lines = IALeftRightPageLines();
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(lines);
    NSDictionary<NSString *, NSString *> *translations = @{
        @"*": @"短标签译文",
        @"昨日の打ち合わせの内容をまとめました。\n資料は共有フォルダに置いてあります。\n確認できたら返信をお願いします。\n締め切りは今週の金曜日です。":
            @"昨天的会议内容已经整理好了。资料放在共享文件夹里。确认之后请回复我。截止日期是本周五。"
    };
    NSArray<FYInlineLayoutRequest *> *requests = IARequests(blocks, translations, viewport);
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    FYInlineLayoutResult *first = [engine layoutRequests:requests viewport:viewport previous:nil];
    FYInlineLayoutResult *second = [engine layoutRequests:requests viewport:viewport previous:first];
    IACheck(!second.changedFromPrevious, scenario,
            @"画面与文本完全没变时 changedFromPrevious == NO");
    BOOL same = first.placements.count == second.placements.count;
    for (NSUInteger index = 0; same && index < first.placements.count; index++) {
        same = [first.placements[index].blockID isEqualToString:second.placements[index].blockID] &&
               NSEqualRects(first.placements[index].translationFrame, second.placements[index].translationFrame) &&
               first.placements[index].mode == second.placements[index].mode;
    }
    IACheck(same, scenario, @"两次布局的 blockID / translationFrame / mode 完全一致");
    IACheck(second.revision > first.revision, scenario,
            [NSString stringWithFormat:@"revision 递增（%lu → %lu）",
             (unsigned long)first.revision, (unsigned long)second.revision]);

    // OCR 抖动 0.002（1440 宽 ≈ 2.9px）：块身份稳定、位置偏移小。
    NSString *jit = @"稳定·抖动 0.002";
    NSMutableArray<FYInlineTextLine *> *jitterLines = [NSMutableArray array];
    for (FYInlineTextLine *line in lines) {
        CGRect rect = line.rect;
        rect.origin.x += 0.002;
        rect.origin.y -= 0.0016;
        [jitterLines addObject:IALine(line.text, rect, line.sourceIndex)];
    }
    NSArray<FYInlineTextBlock *> *jitterBlocks = IAGroup(jitterLines);
    NSArray<FYInlineLayoutRequest *> *jitterRequests = IARequests(jitterBlocks, translations, viewport);
    FYInlineLayoutResult *jittered = [engine layoutRequests:jitterRequests viewport:viewport previous:first];
    IACheck(jittered.placements.count == first.placements.count, jit,
            [NSString stringWithFormat:@"抖动后块数量不变（%lu → %lu）",
             (unsigned long)first.placements.count, (unsigned long)jittered.placements.count]);
    BOOL identity = jittered.placements.count == first.placements.count;
    CGFloat maxDrift = 0;
    NSString *driftDetail = @"";
    for (NSUInteger index = 0; identity && index < first.placements.count; index++) {
        FYInlinePlacement *before = first.placements[index];
        FYInlinePlacement *after = jittered.placements[index];
        BOOL sameID = [before.blockID isEqualToString:after.blockID];
        if (!sameID) {
            identity = NO;
            driftDetail = [NSString stringWithFormat:@"第 %lu 块身份变化 <%@> → <%@>",
                           (unsigned long)(index + 1), IAClip(before.blockID, 24), IAClip(after.blockID, 24)];
            break;
        }
        CGFloat drift = MAX(fabs(NSMidX(before.translationFrame) - NSMidX(after.translationFrame)),
                            fabs(NSMidY(before.translationFrame) - NSMidY(after.translationFrame)));
        if (drift > maxDrift) {
            maxDrift = drift;
            driftDetail = [NSString stringWithFormat:@"第 %lu 块位移 %.1fpx（原文抖动 %.1fpx）",
                           (unsigned long)(index + 1), drift, 0.002 * NSWidth(viewport)];
        }
    }
    IACheck(identity, jit, [NSString stringWithFormat:@"抖动 0.002 后块身份（blockID）不变 %@", driftDetail]);
    IACheck(identity && maxDrift <= 8, jit,
            [NSString stringWithFormat:@"抖动后译文位置偏移小（最大位移 %.1fpx ≤ 8px；%@）", maxDrift, driftDetail]);
    // 证明稳定化确实在工作：分组给出的原始身份已经变了，是布局匹配救回来的。
    BOOL rawChanged = NO;
    for (NSUInteger index = 0; index < MIN(blocks.count, jitterBlocks.count); index++) {
        if (![blocks[index].blockID isEqualToString:jitterBlocks[index].blockID]) { rawChanged = YES; }
    }
    IACheck(rawChanged, jit, @"抖动后分组原始身份确实改变（说明稳定身份来自帧间匹配而非文本未变）");

    // 明显移动/换页：必须 changedFromPrevious == YES，且不沿用旧身份。
    NSString *moved = @"稳定·明显移动不沿用旧身份";
    NSArray<FYInlineTextLine *> *firstLines = @[IALine(@"公演日程のご案内です", IABox(.05, .80, .20, .030), 0)];
    NSArray<FYInlineTextBlock *> *firstBlocks = IAGroup(firstLines);
    NSArray<FYInlineLayoutRequest *> *firstRequests = IARequests(firstBlocks, @{@"*": @"公演日程通知"}, viewport);
    FYInlineLayoutResult *firstResult = [engine layoutRequests:firstRequests viewport:viewport previous:nil];

    NSArray<FYInlineTextLine *> *movedLines = @[IALine(@"公演日程のご案内です", IABox(.05, .12, .20, .030), 0)];
    NSArray<FYInlineTextBlock *> *movedBlocks = IAGroup(movedLines);
    NSArray<FYInlineLayoutRequest *> *movedRequests = IARequests(movedBlocks, @{@"*": @"公演日程通知"}, viewport);
    FYInlineLayoutResult *movedResult = [engine layoutRequests:movedRequests viewport:viewport previous:firstResult];
    IACheck(movedResult.changedFromPrevious, moved, @"明显移动后 changedFromPrevious == YES");
    IACheck(movedResult.placements.count > 0 &&
            ![movedResult.placements.firstObject.blockID isEqualToString:firstResult.placements.firstObject.blockID],
            moved, [NSString stringWithFormat:@"明显移动后不沿用旧块身份（<%@> vs <%@>）",
                    IAClip(firstResult.placements.firstObject.blockID, 26),
                    IAClip(movedResult.placements.firstObject.blockID, 26)]);
    BOOL anyMatched = NO;
    for (FYInlinePlacement *placement in movedResult.placements) {
        if (placement.matchedPreviousFrame) { anyMatched = YES; }
    }
    IACheck(!anyMatched, moved, @"明显移动后没有任何块声称匹配上一帧");

    // 换页：完全不同的文字。
    NSString *pageTurn = @"稳定·换页不沿用旧身份";
    NSArray<FYInlineTextLine *> *newLines = @[IALine(@"まったく別の画面の見出しです", IABox(.55, .30, .30, .035), 0)];
    NSArray<FYInlineTextBlock *> *newBlocks = IAGroup(newLines);
    NSArray<FYInlineLayoutRequest *> *newRequests = IARequests(newBlocks, @{@"*": @"完全不同页面的标题"}, viewport);
    FYInlineLayoutResult *pageResult = [engine layoutRequests:newRequests viewport:viewport previous:firstResult];
    IACheck(pageResult.changedFromPrevious, pageTurn, @"换页后 changedFromPrevious == YES");
    IACheck(![pageResult.placements.firstObject.blockID isEqualToString:firstResult.placements.firstObject.blockID],
            pageTurn, @"换页后不沿用旧块身份");
}

#pragma mark - G. 接进 UI 后

@interface IAAcceptanceApp : AppDelegate
@end
@implementation IAAcceptanceApp
- (BOOL)translationTargetIsForeground { return YES; }
@end

static IAAcceptanceApp *IAAuditApp(NSRect bounds) {
    IAAcceptanceApp *app = [IAAcceptanceApp new];
    app.inlineTranslationPanels = [NSMutableArray array];
    app.inlineLongCardPanels = [NSMutableArray array];
    app.inlineTranslationCache = [NSMutableDictionary dictionary];
    app.captionFontSizeSlider = [NSSlider sliderWithValue:30 minValue:12 maxValue:48 target:nil action:nil];
    app.captionOpacitySlider = [NSSlider sliderWithValue:0.58 minValue:0 maxValue:1 target:nil action:nil];
    WindowItem *window = [WindowItem new];
    window.windowID = 9201;
    window.displayName = @"AcceptanceFixture";
    window.bounds = bounds;
    app.windows = [NSMutableArray arrayWithObject:window];
    app.windowPopup = [[NSPopUpButton alloc] init];
    [app.windowPopup addItemWithTitle:@"AcceptanceFixture"];
    app.windowPopup.menu.itemArray.firstObject.representedObject = @(9201);
    return app;
}

static OCRTextItem *IAItem(NSString *text, CGRect box, InlineBlockKind kind) {
    OCRTextItem *item = [[OCRTextItem alloc] init];
    item.text = text;
    item.boundingBox = box;
    item.lineBoxes = @[[NSValue valueWithRect:box]];
    item.lineTexts = @[text];
    item.lineCount = 1;
    item.blockKind = kind;
    item.confidence = 0.9;
    item.groupingConfidence = 1.0;
    item.sourceBlockID = @"";
    return item;
}

static NSTextField *IAPanelLabel(NSPanel *panel) {
    for (NSView *view in panel.contentView.subviews) {
        if ([view isKindOfClass:NSTextField.class]) { return (NSTextField *)view; }
    }
    return nil;
}

static void IACheckPanelsDoNotCoverOtherSources(IAAcceptanceApp *app,
                                                NSArray<OCRTextItem *> *items,
                                                NSRect windowFrame,
                                                NSString *scenario) {
    NSArray<NSPanel *> *panels = [app.inlineTranslationPanels arrayByAddingObjectsFromArray:app.inlineLongCardPanels];
    for (NSPanel *panel in panels) {
        for (OCRTextItem *item in items) {
            NSString *identity = [app inlineBlockIdentityForItem:item];
            if ([panel.identifier isEqualToString:identity]) { continue; }
            NSRect source = [app appKitFrameForOCRItem:item inWindowFrame:windowFrame];
            if (CGRectIntersectsRect(panel.frame, source)) {
                IACheck(NO, scenario,
                        [NSString stringWithFormat:@"面板 <%@> frame=%@ 遮挡了原文 <%@> %@",
                         IAClip(panel.identifier, 20), IARect(panel.frame), IAClip(item.text, 16), IARect(source)]);
                return;
            }
        }
    }
    IACheck(YES, scenario, [NSString stringWithFormat:@"%lu 个面板都没有遮挡任何别的原文块（真实坐标换算）",
                            (unsigned long)panels.count]);
}

static void TestUIPanelReuseAndLegality(void) {
    NSString *scenario = @"UI·同内容复用面板";
    NSRect windowFrame = NSMakeRect(0, 0, 1200, 800);
    IAAcceptanceApp *app = IAAuditApp(windowFrame);
    NSArray<OCRTextItem *> *items = @[
        IAItem(@"設定画面を開く", IABox(.08, .78, .18, .030), InlineBlockKindShort),
        IAItem(@"保存して終了します", IABox(.08, .70, .18, .030), InlineBlockKindShort),
        IAItem(@"昨日の打ち合わせの内容をまとめました。\n資料は共有フォルダに置いてあります。\n確認できたら返信をお願いします。",
               IABox(.55, .30, .40, .12), InlineBlockKindLong)
    ];
    NSArray<NSString *> *translations = @[@"打开设置画面", @"保存并退出", @"昨天的会议内容已经整理好了。资料放在共享文件夹里。确认之后请回复我。"];

    [app showInlineTranslations:translations forItems:items placementRect:windowFrame];
    NSUInteger shortCount = app.inlineTranslationPanels.count;
    NSUInteger longCount = app.inlineLongCardPanels.count;
    NSPanel *shortPanel = app.inlineTranslationPanels.firstObject;
    NSPanel *longPanel = app.inlineLongCardPanels.firstObject;
    IACheck(shortCount == 2 && longCount == 1, scenario,
            [NSString stringWithFormat:@"两个短贴片 + 一张长卡（实际 短 %lu / 长 %lu）",
             (unsigned long)shortCount, (unsigned long)longCount]);

    // 同样内容再来一次：必须复用同一批 NSPanel 对象。
    [app showInlineTranslations:translations forItems:items placementRect:windowFrame];
    IACheck(app.inlineTranslationPanels.firstObject == shortPanel && app.inlineLongCardPanels.firstObject == longPanel, scenario,
            @"同内容两次调用复用同一 NSPanel 实例（对象相同）");
    IACheck(app.inlinePanelsByBlockID.count == 3, scenario,
            [NSString stringWithFormat:@"按块身份登记的面板仍为 3（实际 %lu）", (unsigned long)app.inlinePanelsByBlockID.count]);
    IACheckPanelsDoNotCoverOtherSources(app, items, windowFrame, @"UI·面板不遮挡别的原文");

    // 译文变化：同一块就地更新，面板对象不变、内容更新。
    NSString *scenario2 = @"UI·译文就地更新";
    NSArray<NSString *> *changed = @[@"打开设置界面", @"保存并退出", @"昨天的会议记录已经整理好了。资料放在共享文件夹里。"];
    [app showInlineTranslations:changed forItems:items placementRect:windowFrame];
    IACheck(app.inlineTranslationPanels.firstObject == shortPanel, scenario2,
            @"译文变化后短贴片复用同一面板（不重建、不闪）");
    NSTextField *label = IAPanelLabel(shortPanel);
    IACheck(label != nil && [label.stringValue containsString:@"打开设置界面"], scenario2,
            [NSString stringWithFormat:@"短贴片内容就地更新（实际“%@”）", label.stringValue ?: @"<无标签>"]);
    IACheck(app.inlineLongCardPanels.firstObject == longPanel, scenario2,
            @"译文变化后长卡复用同一面板");
    IACheck(app.inlineTranslationPanels.count == 2 && app.inlineLongCardPanels.count == 1, scenario2,
            @"译文变化后面板数量不变");
    IACheckPanelsDoNotCoverOtherSources(app, items, windowFrame, scenario2);

    // 抖动 0.002：面板对象不变、位置偏移小。
    NSString *scenario3 = @"UI·抖动复用面板";
    NSRect frameBeforeJitter = shortPanel.frame;
    NSRect longFrameBeforeJitter = longPanel.frame;
    NSString *beforeDump = IAPlacementsDump(app.lastInlineLayoutResult);
    NSLog(@"  UI 抖动前布局：%@", beforeDump);
    NSMutableArray<OCRTextItem *> *jittered = [NSMutableArray array];
    for (OCRTextItem *item in items) {
        CGRect box = item.boundingBox;
        box.origin.x += 0.002;
        box.origin.y -= 0.0016;
        [jittered addObject:IAItem(item.text, box, item.blockKind)];
    }
    [app showInlineTranslations:changed forItems:jittered placementRect:windowFrame];
    NSString *afterDump = IAPlacementsDump(app.lastInlineLayoutResult);
    NSLog(@"  UI 抖动后布局：%@", afterDump);
    IACheck(app.inlineTranslationPanels.firstObject == shortPanel && app.inlineLongCardPanels.firstObject == longPanel, scenario3,
            @"原文抖动 0.002 后面板仍未重建（对象相同）");
    NSPanel *shortAfter = app.inlineTranslationPanels.firstObject;
    NSPanel *longAfter = app.inlineLongCardPanels.firstObject;
    CGFloat shortDrift = MAX(fabs(NSMidX(shortAfter.frame) - NSMidX(frameBeforeJitter)),
                             fabs(NSMidY(shortAfter.frame) - NSMidY(frameBeforeJitter)));
    CGFloat longDrift = MAX(fabs(NSMidX(longAfter.frame) - NSMidX(longFrameBeforeJitter)),
                            fabs(NSMidY(longAfter.frame) - NSMidY(longFrameBeforeJitter)));
    IACheck(shortDrift <= 8 && longDrift <= 8, scenario3,
            [NSString stringWithFormat:@"抖动 2~3px 后译文位置偏移小（短贴片 %.1fpx / 长卡 %.1fpx，期望 ≤ 8px）\n        抖动前：%@\n        抖动后：%@",
             shortDrift, longDrift, beforeDump, afterDump]);
    IACheckPanelsDoNotCoverOtherSources(app, jittered, windowFrame, scenario3);
    [app clearInlineTranslationPanels];
}

#pragma mark - H. 真实 OCR 夹具

static NSDictionary *IALoadFixture(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) { return nil; }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

static NSArray<FYInlineTextLine *> *IALinesFromFixture(NSDictionary *fixture) {
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray array];
    NSInteger index = 0;
    for (NSDictionary *entry in fixture[@"lines"]) {
        NSString *text = entry[@"text"];
        if (![text isKindOfClass:NSString.class]) { continue; }
        CGRect rect = CGRectMake([entry[@"x"] doubleValue], [entry[@"y"] doubleValue],
                                 [entry[@"w"] doubleValue], [entry[@"h"] doubleValue]);
        [lines addObject:[FYInlineTextLine lineWithText:text rect:rect
                                             confidence:[entry[@"confidence"] doubleValue]
                                            sourceIndex:index]];
        index += 1;
    }
    return lines;
}

static NSString *IAFixtureTranslation(FYInlineTextBlock *block) {
    if ([block.text containsString:@"乗り気"]) {
        return @"在没那个心思的时候，硬来也只会失败。去看看网上的占卜什么的，最好还是先了解一下运势哦？等倒下了可就晚了！明白了吗？";
    }
    if (block.kind == FYInlineBlockKindLong) {
        return @"这是一段较长的正文译文，用来检查长卡在真实 OCR 框下的宽度、可读下限与滚动范围是否满足要求。";
    }
    return @"短标签译文";
}

static void TestRealFixtureFrame02(NSString *outputDirectory) {
    NSString *scenario = @"真实夹具·frame-02";
    NSString *path = @".build/inline-layout/fixtures/frame-02.json";
    NSDictionary *fixture = IALoadFixture(path);
    if (!fixture) {
        NSLog(@"SKIP [%@] 夹具不存在：%@", scenario, path);
        return;
    }
    NSArray<FYInlineTextLine *> *lines = IALinesFromFixture(fixture);
    IACheck(lines.count == 14, scenario,
            [NSString stringWithFormat:@"读取真实采集帧行数（期望 14，实际 %lu）", (unsigned long)lines.count]);
    NSArray<FYInlineTextBlock *> *blocks = IAGroup(lines);
    NSLog(@"  真实 frame-02 分组 → %@", IABlockDump(blocks));
    IACheck(blocks.count == 8, scenario,
            [NSString stringWithFormat:@"14 行 → 8 块（实现方报告值；实际 %lu）%@",
             (unsigned long)blocks.count, blocks.count == 8 ? @"" : [NSString stringWithFormat:@"，与报告不一致：%@", IABlockDump(blocks)]]);
    IACheckPreservation(blocks, lines, scenario);

    BOOL noStraddle = YES;
    for (FYInlineTextBlock *block in blocks) {
        if (block.boundingBox.size.width >= 0.60) { noStraddle = NO; }
    }
    IACheck(noStraddle, scenario, @"没有横跨左列表与右正文的大块（每块宽度 < 0.60）");

    FYInlineTextBlock *body = IABlockContaining(blocks, @"乗り気じゃないときに");
    IACheck(body != nil && body.lineCount == 7 && body.kind == FYInlineBlockKindLong, scenario,
            [NSString stringWithFormat:@"右侧长正文并成 1 块 7 行且为长卡（实际 %@ / %ld 行 / kind=%ld）",
             body ? @"找到" : @"缺失", body ? (long)body.lineCount : 0L, body ? (long)body.kind : -1L]);
    FYInlineTextBlock *subject = IABlockContaining(blocks, @"星の警告");
    IACheck(subject != nil && subject.lineCount == 1 && subject.kind == FYInlineBlockKindShort, scenario,
            @"左侧列表项“星の警告”独立成短标签块");
    BOOL mixed = NO;
    for (FYInlineTextBlock *block in blocks) {
        if ([block.text containsString:@"バンビへダメ出し"] && [block.text containsString:@"乗り気じゃない"]) {
            mixed = YES;
        }
    }
    IACheck(!mixed, scenario, @"左列表项与右侧正文绝不并成一块");

    CGFloat imageWidth = [fixture[@"image"][@"width"] doubleValue] ?: 1920;
    CGFloat imageHeight = [fixture[@"image"][@"height"] doubleValue] ?: 1080;
    CGRect viewport = CGRectMake(0, 0, imageWidth, imageHeight);
    NSMutableArray<FYInlineLayoutRequest *> *requests = [NSMutableArray array];
    for (FYInlineTextBlock *block in blocks) {
        [requests addObject:[FYInlineLayoutRequest requestWithBlock:block
                                                        translation:IAFixtureTranslation(block)
                                                        sourceFrame:IADisplayFrameForBox(block.boundingBox, viewport)]];
    }
    FYInlineLayoutResult *result = [[FYInlineLayoutEngine defaultEngine] layoutRequests:requests viewport:viewport previous:nil];
    IACheckLegality(result, requests, viewport, scenario);
    IACheckCoverage(result, requests, scenario);
    FYInlinePlacement *bodyPlacement = nil;
    for (FYInlinePlacement *placement in result.placements) {
        if (placement.block == body) { bodyPlacement = placement; }
    }
    IACheck(bodyPlacement != nil &&
            (bodyPlacement.mode == FYInlineDisplayModeFullCard || bodyPlacement.mode == FYInlineDisplayModeScrollingCard), scenario,
            [NSString stringWithFormat:@"右侧长正文给出长卡（mode=%ld，frame=%@，原因“%@”）",
             bodyPlacement ? (long)bodyPlacement.mode : -1L,
             bodyPlacement ? IARect(bodyPlacement.translationFrame) : @"<无>", bodyPlacement.reason ?: @""]);
    IACheck(bodyPlacement != nil && NSWidth(bodyPlacement.translationFrame) >= 300, scenario,
            [NSString stringWithFormat:@"右侧长卡宽度 ≥ 300（实际 %.0f）",
             bodyPlacement ? NSWidth(bodyPlacement.translationFrame) : 0.0]);

    if (outputDirectory.length > 0) {
        NSMutableArray<NSString *> *dump = [NSMutableArray array];
        for (NSUInteger index = 0; index < result.placements.count; index++) {
            FYInlinePlacement *placement = result.placements[index];
            [dump addObject:[NSString stringWithFormat:@"P%lu mode=%ld anchor=%ld frame=%@ src=%@ reason=%@",
                             (unsigned long)(index + 1), (long)placement.mode, (long)placement.anchor,
                             IARect(placement.translationFrame), IARect(placement.sourceFrame), placement.reason ?: @""]];
        }
        NSString *report = [NSString stringWithFormat:@"lines=%lu blocks=%lu placements=%lu unplaceable=%lu compact=%lu\n%@\n",
                            (unsigned long)lines.count, (unsigned long)blocks.count, (unsigned long)result.placements.count,
                            (unsigned long)result.unplaceableBlockIDs.count, (unsigned long)result.compactEntryBlockIDs.count,
                            IAJoined(dump)];
        [report writeToFile:[outputDirectory stringByAppendingPathComponent:@"frame-02-layout.txt"]
                 atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
}

#pragma mark - main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSString *outputDirectory = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : NSTemporaryDirectory();
        [[NSFileManager defaultManager] createDirectoryAtPath:outputDirectory withIntermediateDirectories:YES attributes:nil error:NULL];

        NSLog(@"== A/B 分组：不跨栏、菜单不误并、原文不丢 ==");
        TestGroupingLeftRightPage();
        TestGroupingDenseMenu();
        TestGroupingWideRegularMenu();
        TestGroupingTitleVersusBody();
        TestGroupingNarrowGutterColumns();
        TestGroupingThreeColumns();
        TestGroupingRightAligned();
        TestGroupingNarrowColumn();
        TestGroupingSingleLongLine();
        TestContentPreservationAndDedup();

        NSLog(@"== C/D 布局：合法性、长卡可读下限 ==");
        TestLayoutLeftRightPage();
        TestLayoutPackedScreen();
        TestLayoutThreeColumns();
        TestLongCardReadability();

        NSLog(@"== E 降级链 ==");
        TestDegradationChain();

        NSLog(@"== F 帧间稳定 ==");
        TestFrameStability();

        NSLog(@"== G 接进 UI 后 ==");
        TestUIPanelReuseAndLegality();

        NSLog(@"== H 真实 OCR 夹具 ==");
        TestRealFixtureFrame02(outputDirectory);

        NSString *summary = [NSString stringWithFormat:
            @"{\"suite\":\"InlineAdaptiveAcceptanceTests\",\"pass\":%lu,\"fail\":%lu}",
            (unsigned long)gIAPass, (unsigned long)gIAFail];
        if (outputDirectory.length > 0) {
            [summary writeToFile:[outputDirectory stringByAppendingPathComponent:@"acceptance-summary.json"]
                      atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }
        NSLog(@"ACCEPTANCE SUMMARY %@", summary);
        return gIAFail ? 1 : 0;
    }
}
