// 自适应贴译布局：分组器 + 布局引擎的验证。
//
// 分两步，结果分开报告：
//   第一步（本文件 A~F 段）：**人工框**场景 —— 新闻页、邮件页、密集菜单、双栏、
//     底部残缺、窄窗、抖动/缩放。只验证分组与布局本身，不冒充 OCR 全链路。
//   第二步（G 段）：**真实 OCR 输出**夹具（.build/inline-layout/fixtures/*.json），
//     检查分组错误如何影响布局，并把 OCR 框／分组／最终译文位置画成对照图。
//
// 断言只看“合法性与可读性”，不写死页面类型、示例文案或屏幕坐标。

#import "LearningAppTestSupport.h"
#import "FYInlineLayout.h"

static NSUInteger gFailures = 0;
// 证据输出目录（main 里从 argv[1] 传入），用于写对照图/截图。
static NSString *kInlineTestOutputDirectory = nil;
static void Check(BOOL ok, NSString *message) {
    if (ok) {
        NSLog(@"PASS %@", message);
    } else {
        gFailures += 1;
        NSLog(@"FAIL %@", message);
    }
}

static FYInlineTextLine *Line(NSString *text, CGRect rect) {
    return [FYInlineTextLine lineWithText:text rect:rect confidence:0.9 sourceIndex:0];
}

/// 归一化页面坐标下的矩形（x, y 从底部起算）。
static CGRect Box(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    return CGRectMake(x, y, w, h);
}

static NSArray<FYInlineTextBlock *> *Group(NSArray<FYInlineTextLine *> *lines) {
    return [[FYInlineGrouper defaultGrouper] blocksFromLines:lines];
}

static FYInlineBlockKind KindOf(NSArray<FYInlineTextBlock *> *blocks, NSString *contains) {
    for (FYInlineTextBlock *block in blocks) {
        if ([block.text containsString:contains]) { return block.kind; }
    }
    return FYInlineBlockKindShort;
}

static void LogBlocks(NSString *label, NSArray<FYInlineTextBlock *> *blocks) {
    for (NSUInteger index = 0; index < blocks.count; index++) {
        FYInlineTextBlock *block = blocks[index];
        NSLog(@"  %@ B%lu kind=%ld conf=%.2f box=(%.3f,%.3f,%.3f,%.3f) lines=%lu text=<%@>",
              label, (unsigned long)(index + 1), (long)block.kind, block.groupingConfidence,
              block.boundingBox.origin.x, block.boundingBox.origin.y,
              block.boundingBox.size.width, block.boundingBox.size.height,
              (unsigned long)block.lineCount, [block.text stringByReplacingOccurrencesOfString:@"\n" withString:@"⏎"]);
    }
}

static BOOL HasBlockContaining(NSArray<FYInlineTextBlock *> *blocks, NSString *needle) {
    for (FYInlineTextBlock *block in blocks) {
        if ([block.text containsString:needle]) { return YES; }
    }
    return NO;
}

#pragma mark - 场景夹具（人工框）

/// 新闻页：左菜单三项 + 两个标题 + 右侧上下两篇正文。
static NSArray<FYInlineTextLine *> *NewsPageLines(void) {
    return @[
        Line(@"公演日程", Box(.05, .80, .13, .026)),
        Line(@"イベント情報", Box(.05, .72, .15, .026)),
        Line(@"アルバイト", Box(.05, .64, .12, .026)),
        Line(@"お知らせ", Box(.30, .78, .12, .028)),
        Line(@"新商品のご案内", Box(.66, .78, .16, .028)),
        Line(@"新しい季節のイベントが始まります。", Box(.30, .530, .30, .045)),
        Line(@"期間中は限定の衣装も登場します。", Box(.30, .475, .30, .045)),
        Line(@"ぜひお見逃しなく。", Box(.30, .420, .30, .045)),
        Line(@"さらに、期間限定の特別なストーリーも公開予定です。", Box(.66, .480, .28, .050)),
        Line(@"詳細は公式サイトをご確認ください。", Box(.66, .420, .28, .050))
    ];
}

/// 邮件页：左侧列表五项 + 右侧长正文（空行分段）。
static NSArray<FYInlineTextLine *> *MailPageLines(void) {
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray array];
    NSArray<NSString *> *subjects = @[@"バンビへダメ出し！", @"星の警告", @"ヨロシクね♪", @"バンビへ", @"アルバイト情報"];
    CGFloat y = .80;
    for (NSString *subject in subjects) {
        [lines addObject:Line(subject, Box(.04, y, .18, .030))];
        y -= .095;
    }
    [lines addObject:Line(@"乗り気じゃないときに", Box(.52, .620, .42, .032))];
    [lines addObject:Line(@"ムリしても失敗するだけ。", Box(.52, .585, .42, .032))];
    [lines addObject:Line(@"WEBの占いとか見て", Box(.52, .550, .42, .032))];
    [lines addObject:Line(@"波を知ったほうがいいよ？", Box(.52, .515, .42, .032))];
    [lines addObject:Line(@"倒れてからじゃ遅いんだから！", Box(.52, .445, .42, .032))];
    [lines addObject:Line(@"わかった？", Box(.52, .375, .42, .032))];
    [lines addObject:Line(@"+Karen+", Box(.52, .305, .42, .032))];
    return lines;
}

/// 密集菜单：八项紧挨着的条目（绝不能并成一段正文）。
static NSArray<FYInlineTextLine *> *DenseMenuLines(void) {
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray array];
    NSArray<NSString *> *items = @[@"設定", @"セーブ", @"ロード", @"アイテム", @"スキル", @"クエスト", @"図鑑", @"戻る"];
    CGFloat y = .88;
    for (NSString *item in items) {
        [lines addObject:Line(item, Box(.08, y, .20, .028))];
        y -= .075;
    }
    return lines;
}

/// 双栏 + 不等行距：两栏各自的折行间距不同，仍不能跨栏合并。
static NSArray<FYInlineTextLine *> *TwoColumnLines(void) {
    return @[
        Line(@"左のコラムは行間が広めです。", Box(.06, .70, .38, .034)),
        Line(@"それでも同じ段落として読めます。", Box(.06, .625, .38, .034)),
        Line(@"最後まで左の欄に収まります。", Box(.06, .550, .38, .034)),
        Line(@"右のコラムは行間が狭い記事です。", Box(.56, .70, .38, .030)),
        Line(@"行間が違っても欄は分かれます。", Box(.56, .655, .38, .030)),
        Line(@"右の欄だけで一つの段落です。", Box(.56, .610, .38, .030))
    ];
}

/// 画面底部只露出一部分正文。
static NSArray<FYInlineTextLine *> *BottomPartialLines(void) {
    return @[
        Line(@"画面下に半分だけ見えている本文の一行目です。", Box(.20, .060, .50, .034)),
        Line(@"まだ続きがありますが切れています。", Box(.20, .020, .50, .034))
    ];
}

#pragma mark - 布局辅助

static NSArray<FYInlineLayoutRequest *> *RequestsFromBlocks(NSArray<FYInlineTextBlock *> *blocks,
                                                            NSDictionary<NSString *, NSString *> *translations,
                                                            CGRect viewport) {
    NSMutableArray<FYInlineLayoutRequest *> *requests = [NSMutableArray array];
    for (FYInlineTextBlock *block in blocks) {
        NSString *translation = translations[block.text];
        if (translation.length == 0) {
            translation = translations[@"*"];
        }
        // 人工框场景：把归一化框线性换算到显示区域（这一步在生产里由坐标映射完成）。
        CGRect frame = CGRectMake(NSMinX(viewport) + block.boundingBox.origin.x * NSWidth(viewport),
                                  NSMinY(viewport) + block.boundingBox.origin.y * NSHeight(viewport),
                                  block.boundingBox.size.width * NSWidth(viewport),
                                  block.boundingBox.size.height * NSHeight(viewport));
        [requests addObject:[FYInlineLayoutRequest requestWithBlock:block translation:(translation ?: @"译文") sourceFrame:frame]];
    }
    return requests;
}

/// 布局合法性：全部在可见区域内、互不重叠、不遮挡任何**别的**原文块。
static void CheckLayoutLegality(FYInlineLayoutResult *result,
                                NSArray<FYInlineLayoutRequest *> *requests,
                                CGRect viewport,
                                NSString *label) {
    NSMutableArray<NSValue *> *shown = [NSMutableArray array];
    for (NSUInteger index = 0; index < result.placements.count; index++) {
        FYInlinePlacement *placement = result.placements[index];
        if (placement.mode == FYInlineDisplayModeUnplaceable) { continue; }
        CGRect frame = placement.translationFrame;
        Check(CGRectGetMinX(frame) >= NSMinX(viewport) - 1 && CGRectGetMaxX(frame) <= NSMaxX(viewport) + 1 &&
              CGRectGetMinY(frame) >= NSMinY(viewport) - 1 && CGRectGetMaxY(frame) <= NSMaxY(viewport) + 1,
              [NSString stringWithFormat:@"%@：%@ 的译文框在可见区域内", label, placement.blockID]);
        for (NSUInteger other = 0; other < requests.count; other++) {
            if (other == index) { continue; }
            NSRect source = requests[other].sourceFrame;
            Check(!CGRectIntersectsRect(frame, source),
                  [NSString stringWithFormat:@"%@：%@ 的译文框没有遮挡第 %lu 个原文块", label, placement.blockID, (unsigned long)(other + 1)]);
        }
        for (NSValue *value in shown) {
            Check(!CGRectIntersectsRect(frame, value.rectValue),
                  [NSString stringWithFormat:@"%@：%@ 的译文框没有和已放置的译文重叠", label, placement.blockID]);
        }
        [shown addObject:[NSValue valueWithRect:frame]];
    }
}

#pragma mark - A. 分组

static void TestGroupingNewsPage(void) {
    NSArray<FYInlineTextBlock *> *blocks = Group(NewsPageLines());
    Check(blocks.count == 7, [NSString stringWithFormat:@"新闻页：左菜单 3 + 标题 2 + 正文 2 = 7 块（实际 %lu）", (unsigned long)blocks.count]);
    Check(HasBlockContaining(blocks, @"期間中は限定の衣装") && [Group(NewsPageLines())[5].text containsString:@"\n"],
          @"新闻页：正文按折行并成一块并保留原始换行");
    Check(KindOf(blocks, @"期間中は限定") == FYInlineBlockKindLong, @"新闻页：连续正文分类为长卡");
    Check(KindOf(blocks, @"アルバイト") == FYInlineBlockKindShort, @"新闻页：菜单项保持短标签");
    for (FYInlineTextBlock *block in blocks) {
        Check(block.boundingBox.size.width < 0.50, @"新闻页：没有跨栏拼成的大段");
        Check(block.lineTexts.count == block.lineBoxes.count && block.lineBoxes.count == block.sourceIndices.count,
              @"新闻页：保留每行原文、矩形与来源");
    }
}

static void TestGroupingMailPage(void) {
    NSArray<FYInlineTextBlock *> *blocks = Group(MailPageLines());
    LogBlocks(@"邮件页", blocks);
    Check(blocks.count == 6, [NSString stringWithFormat:@"邮件页：左列表 5 + 右正文 1 = 6 块（实际 %lu）", (unsigned long)blocks.count]);
    FYInlineTextBlock *body = nil;
    for (FYInlineTextBlock *block in blocks) {
        if ([block.text containsString:@"ムリしても失敗するだけ"]) { body = block; }
    }
    Check(body != nil, @"邮件页：右侧正文被识别为一块");
    Check(body != nil && body.lineCount == 7, @"邮件页：正文跨空行仍保留 7 行原文（段落不丢句）");
    Check(body != nil && [body.text containsString:@"\n"], @"邮件页：保留 OCR 原始换行");
    Check(body != nil && body.kind == FYInlineBlockKindLong, @"邮件页：右侧长正文分类为长卡");
    Check(KindOf(blocks, @"星の警告") == FYInlineBlockKindShort, @"邮件页：左侧列表项保持短标签");
    for (FYInlineTextBlock *block in blocks) {
        if ([block.text containsString:@"乗り気"] || [block.text containsString:@"アルバイト情報"]) { continue; }
    }
    Check(!HasBlockContaining(blocks, @"アルバイト情報\n乗り気"), @"邮件页：左列表与右正文绝不跨栏合并");
}

static void TestGroupingDenseMenu(void) {
    NSArray<FYInlineTextBlock *> *blocks = Group(DenseMenuLines());
    Check(blocks.count == 8, [NSString stringWithFormat:@"密集菜单：8 个条目保持 8 块（实际 %lu）", (unsigned long)blocks.count]);
    for (FYInlineTextBlock *block in blocks) {
        Check(block.kind == FYInlineBlockKindShort, [NSString stringWithFormat:@"密集菜单：%@ 保持短标签", block.text]);
    }
}

static void TestGroupingTwoColumns(void) {
    NSArray<FYInlineTextBlock *> *blocks = Group(TwoColumnLines());
    Check(blocks.count == 2, [NSString stringWithFormat:@"双栏（不等行距）：两栏各自成块（实际 %lu）", (unsigned long)blocks.count]);
    for (FYInlineTextBlock *block in blocks) {
        Check(block.boundingBox.size.width < 0.45, @"双栏：没有跨栏合并");
        Check(block.lineCount == 3, @"双栏：每栏 3 行都保留");
    }
}

static void TestGroupingTitleVersusBody(void) {
    NSArray<FYInlineTextLine *> *lines = @[
        Line(@"お知らせ", Box(.30, .80, .20, .050)),
        Line(@"本日は新しいイベントを開催します。", Box(.30, .730, .40, .022)),
        Line(@"ぜひご参加ください。", Box(.30, .700, .40, .022))
    ];
    NSArray<FYInlineTextBlock *> *blocks = Group(lines);
    Check(blocks.count == 2, [NSString stringWithFormat:@"标题与正文字号差：标题独立成块（实际 %lu）", (unsigned long)blocks.count]);
}

static void TestGroupingBottomPartial(void) {
    NSArray<FYInlineTextBlock *> *blocks = Group(BottomPartialLines());
    Check(blocks.count == 1 && blocks.firstObject.lineCount == 2, @"底部残缺正文：两行仍并成一块，不丢句");
}

static void TestDedup(void) {
    NSArray<FYInlineTextLine *> *lines = @[
        Line(@"同じ見出しです", Box(.10, .80, .20, .030)),
        Line(@"同じ見出しです", Box(.105, .8005, .20, .030)),     // 同一处重复识别
        Line(@"同じ見出しです", Box(.60, .30, .20, .030))          // 不同位置的同文内容
    ];
    NSArray<FYInlineTextLine *> *deduplicated = [[FYInlineGrouper defaultGrouper] deduplicatedLines:lines];
    Check(deduplicated.count == 2, [NSString stringWithFormat:@"去重：同处重复去掉一条、异处同文保留（实际 %lu）", (unsigned long)deduplicated.count]);
    NSArray<FYInlineTextBlock *> *blocks = Group(lines);
    Check(blocks.count == 2, @"去重：不同位置的同文内容不串块");
}

#pragma mark - B. 布局

static NSDictionary<NSString *, NSString *> *NewsTranslations(void) {
    return @{
        @"公演日程": @"公演日程",
        @"イベント情報": @"活动信息",
        @"アルバイト": @"兼职",
        @"お知らせ": @"通知",
        @"新商品のご案内": @"新商品介绍",
        @"新しい季節のイベントが始まります。\n期間中は限定の衣装も登場します。\nぜひお見逃しなく。":
            @"新的季节活动即将开始。\n活动期间还会推出限定服装。\n请千万不要错过。",
        @"さらに、期間限定の特別なストーリーも公開予定です。\n詳細は公式サイトをご確認ください。":
            @"此外还会公开期间限定的特别剧情。\n详情请查看官方网站。"
    };
}

static void TestLayoutNewsPage(void) {
    CGRect viewport = CGRectMake(0, 0, 1440, 900);
    NSArray<FYInlineTextBlock *> *blocks = Group(NewsPageLines());
    NSArray<FYInlineLayoutRequest *> *requests = RequestsFromBlocks(blocks, NewsTranslations(), viewport);
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    FYInlineLayoutResult *result = [engine layoutRequests:requests viewport:viewport previous:nil];
    CheckLayoutLegality(result, requests, viewport, @"新闻页");
    NSUInteger cards = 0, patches = 0, compact = 0, unplaceable = 0;
    for (FYInlinePlacement *placement in result.placements) {
        if (placement.mode == FYInlineDisplayModeUnplaceable) { unplaceable += 1; }
        else if (placement.mode == FYInlineDisplayModeCompactEntry) { compact += 1; }
        else if (placement.block.kind == FYInlineBlockKindLong) { cards += 1; }
        else { patches += 1; }
    }
    Check(cards == 2 && patches == 5 && compact == 0 && unplaceable == 0,
          [NSString stringWithFormat:@"新闻页：2 长卡 + 5 短贴片、无降级（实际 卡%lu 片%lu 入口%lu 不可放置%lu）",
           (unsigned long)cards, (unsigned long)patches, (unsigned long)compact, (unsigned long)unplaceable]);
    for (FYInlinePlacement *placement in result.placements) {
        if (placement.block.kind != FYInlineBlockKindShort) { continue; }
        Check(fabs(NSMinX(placement.translationFrame) - NSMinX(placement.sourceFrame)) < 2,
              @"新闻页：短贴片与原文左对齐");
        Check(NSMaxY(placement.translationFrame) <= NSMinY(placement.sourceFrame) + 1 &&
              NSMinY(placement.sourceFrame) - NSMaxY(placement.translationFrame) < 16,
              @"新闻页：短贴片贴在原文正下方");
    }
}

static void TestLayoutMailPageColumnBinding(void) {
    CGRect viewport = CGRectMake(0, 0, 1440, 900);
    NSArray<FYInlineTextBlock *> *blocks = Group(MailPageLines());
    NSMutableDictionary<NSString *, NSString *> *translations = [NSMutableDictionary dictionary];
    for (FYInlineTextBlock *block in blocks) {
        translations[block.text] = block.kind == FYInlineBlockKindLong
            ? @"在没那个心思的时候，硬来也只会失败。去看看网上的占卜什么的，最好还是先了解一下运势哦？等倒下了可就晚了！明白了吗？+Karen+"
            : @"名单项";
    }
    NSArray<FYInlineLayoutRequest *> *requests = RequestsFromBlocks(blocks, translations, viewport);
    FYInlineLayoutResult *result = [[FYInlineLayoutEngine defaultEngine] layoutRequests:requests viewport:viewport previous:nil];
    CheckLayoutLegality(result, requests, viewport, @"邮件页");
    FYInlinePlacement *body = nil;
    for (FYInlinePlacement *placement in result.placements) {
        if (placement.block.kind == FYInlineBlockKindLong) { body = placement; }
    }
    Check(body != nil, @"邮件页：长正文有排版结果");
    Check(body != nil && body.mode != FYInlineDisplayModeCompactEntry, @"邮件页：长正文不是紧凑入口");
    Check(body != nil && NSWidth(body.translationFrame) >= 300, @"邮件页：长卡宽度足够避免碎行");
    Check(body != nil && NSHeight(body.translationFrame) >= [FYInlineLayoutEngine defaultEngine].minimumCardHeight - 1,
          @"邮件页：长卡满足可读下限");
}

static void TestLayoutLongCardReadability(void) {
    CGRect viewport = CGRectMake(0, 0, 1440, 900);
    NSArray<FYInlineTextLine *> *lines = @[
        Line(@"新しい季節のイベントが始まります。", Box(.08, .470, .42, .032)),
        Line(@"期間中は限定の衣装も登場します。", Box(.08, .435, .42, .032)),
        Line(@"ぜひお見逃しなく。", Box(.08, .400, .42, .032))
    ];
    NSArray<FYInlineTextBlock *> *blocks = Group(lines);
    // 足够长（超过卡片允许的最大高度）才会真正需要卡内滚动。
    NSString *longTranslation = @"新的季节活动即将开始。活动期间还会推出限定服装，请千万不要错过。此外还计划公开期间限定的特别剧情，"
                                 "详情请查看官方网站。为了让这段译文超过卡片允许的最大高度、必须滚动才能读到结尾，这里补充大量说明文字："
                                 "活动期间每天登录还可以领取一份小礼物，累计登录七天可获得特别的纪念道具；参与限时任务还能获得额外的兑换券，"
                                 "兑换券可以在活动商店换取限定头像框与家具。活动结束后未使用的兑换券会按比例折算成普通金币，请在活动结束前使用。"
                                 "如果对活动内容有疑问，可以查看游戏内的帮助页面，或联系客服获取更多说明。";
    NSArray<FYInlineLayoutRequest *> *requests = RequestsFromBlocks(blocks, @{blocks.firstObject.text: longTranslation}, viewport);
    FYInlineLayoutResult *result = [[FYInlineLayoutEngine defaultEngine] layoutRequests:requests viewport:viewport previous:nil];
    FYInlinePlacement *placement = result.placements.firstObject;
    Check(placement.mode == FYInlineDisplayModeScrollingCard || placement.mode == FYInlineDisplayModeFullCard,
          @"长卡可读性：给出长卡而不是空细条");
    Check(placement.bodyViewportHeight >= 3 * 30 - 1,
          [NSString stringWithFormat:@"长卡可读性：正文视口至少三行（实际 %.0f）", placement.bodyViewportHeight]);
    Check(placement.scrollable && placement.measuredContentHeight > placement.bodyViewportHeight,
          @"长卡可读性：超长正文可滚动，且能滚到末尾（文档高于视口）");
    Check(placement.bodyViewportFrame.size.height > 0 && placement.font.pointSize >= 18,
          @"长卡可读性：正文用正常阅读字重与字号，不靠缩小字号塞满");
}

/// 中等长度的译文：卡片要按**完整译文**长高（不超过允许高度），而不是停在最小可读高度上被迫滚动。
static void TestLayoutCardHugsContent(void) {
    CGRect viewport = CGRectMake(0, 0, 1440, 900);
    NSArray<FYInlineTextLine *> *lines = @[
        Line(@"新しい季節のイベントが始まります。", Box(.08, .470, .42, .032)),
        Line(@"期間中は限定の衣装も登場します。", Box(.08, .435, .42, .032)),
        Line(@"ぜひお見逃しなく。", Box(.08, .400, .42, .032))
    ];
    NSArray<FYInlineTextBlock *> *blocks = Group(lines);
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];

    // ① 很短：高度取下限（三行可读），但绝不需要滚动。
    NSString *shortText = @"活动开始了。";
    NSArray<FYInlineLayoutRequest *> *shortRequests = RequestsFromBlocks(blocks, @{blocks.firstObject.text: shortText}, viewport);
    FYInlinePlacement *shortPlacement = [engine layoutRequests:shortRequests viewport:viewport previous:nil].placements.firstObject;
    CGFloat shortChrome = shortPlacement.panelPadding * 2 + shortPlacement.titleBandHeight;
    Check(shortPlacement.mode == FYInlineDisplayModeFullCard && !shortPlacement.scrollable,
          @"贴合内容：很短的译文也是完整长卡且不滚动");
    Check(fabs(NSHeight(shortPlacement.translationFrame) -
               MAX(engine.minimumCardHeight, shortPlacement.measuredContentHeight + shortChrome)) <= 2,
          [NSString stringWithFormat:@"贴合内容：卡高 = max(三行可读下限, 正文+内边距+标题带)（实际 %.0f）",
           NSHeight(shortPlacement.translationFrame)]);

    // ② 中等长度：明显高于下限、但仍在一屏之内 → 卡高应等于正文文档高 + chrome。
    NSString *medium = @"新的季节活动即将开始。活动期间还会推出限定服装，请千万不要错过。"
                        "此外还计划公开期间限定的特别剧情，详情请查看官方网站。报名截止到本月底，"
                        "每天登录还能领取一份小礼物，累计登录七天可获得纪念道具。";
    NSArray<FYInlineLayoutRequest *> *requests = RequestsFromBlocks(blocks, @{blocks.firstObject.text: medium}, viewport);
    FYInlineLayoutResult *result = [engine layoutRequests:requests viewport:viewport previous:nil];
    FYInlinePlacement *placement = result.placements.firstObject;
    CGFloat chrome = placement.panelPadding * 2 + placement.titleBandHeight;
    Check(placement.mode == FYInlineDisplayModeFullCard && !placement.scrollable,
          [NSString stringWithFormat:@"贴合内容：中等长度译文给完整长卡且不滚动（实际 mode=%ld）", (long)placement.mode]);
    Check(NSHeight(placement.translationFrame) > engine.minimumCardHeight + 1,
          [NSString stringWithFormat:@"贴合内容：正文多于三行时卡片确实长高（实际 %.0f > 下限 %.0f）",
           NSHeight(placement.translationFrame), engine.minimumCardHeight]);
    Check(fabs(NSHeight(placement.translationFrame) - (placement.measuredContentHeight + chrome)) <= 2,
          [NSString stringWithFormat:@"贴合内容：卡高 = 正文文档高 + 内边距 + 标题带（实际 %.0f，期望 %.0f）",
           NSHeight(placement.translationFrame), placement.measuredContentHeight + chrome]);
    Check(placement.measuredContentHeight <= placement.bodyViewportHeight + 1,
          [NSString stringWithFormat:@"贴合内容：正文全部可见（文档 %.0f ≤ 视口 %.0f）",
           placement.measuredContentHeight, placement.bodyViewportHeight]);
    CheckLayoutLegality(result, requests, viewport, @"贴合内容");
}

static void TestLayoutCompactEntryAndUnplaceable(void) {
    // 窄小画面：连三行正文都放不下 → 紧凑入口，而不是细条。
    CGRect tiny = CGRectMake(0, 0, 420, 150);
    NSArray<FYInlineTextLine *> *lines = @[
        Line(@"本文が入りきらない狭い画面のテストです。", Box(.10, .40, .70, .10)),
        Line(@"続きの行もあります。", Box(.10, .30, .70, .10))
    ];
    NSArray<FYInlineTextBlock *> *blocks = Group(lines);
    NSArray<FYInlineLayoutRequest *> *requests = RequestsFromBlocks(blocks, @{blocks.firstObject.text: @"这是放不进窄画面的长译文。"}, tiny);
    FYInlineLayoutResult *result = [[FYInlineLayoutEngine defaultEngine] layoutRequests:requests viewport:tiny previous:nil];
    Check(result.placements.count == 1 && result.placements.firstObject.mode == FYInlineDisplayModeCompactEntry,
          @"空间不足：长卡改为紧凑入口（不是细条、也不是静默丢弃）");
    Check(result.placements.firstObject.compactEntry && NSHeight(result.placements.firstObject.translationFrame) >= 30,
          @"空间不足：紧凑入口有可点击高度");
    Check([result.placements.firstObject.reason containsString:@"紧凑入口"], @"空间不足：给出降级原因");

    // 画面被原文块铺满：仍然每一块要么有位置、要么被明确标记；绝不为放下面板去盖别的条目。
    CGRect packed = CGRectMake(0, 0, 600, 400);
    NSMutableArray<FYInlineTextLine *> *packedLines = [NSMutableArray array];
    for (NSUInteger row = 0; row < 8; row++) {
        for (NSUInteger column = 0; column < 3; column++) {
            [packedLines addObject:Line([NSString stringWithFormat:@"項目%lu-%lu", (unsigned long)row, (unsigned long)column],
                                        Box(.02 + column * .33, .90 - row * .115, .30, .11))];
        }
    }
    NSArray<FYInlineTextBlock *> *packedBlocks = Group(packedLines);
    NSMutableDictionary<NSString *, NSString *> *translations = [NSMutableDictionary dictionary];
    for (FYInlineTextBlock *block in packedBlocks) { translations[block.text] = @"菜单项译文"; }
    NSArray<FYInlineLayoutRequest *> *packedRequests = RequestsFromBlocks(packedBlocks, translations, packed);
    FYInlineLayoutResult *packedResult = [[FYInlineLayoutEngine defaultEngine] layoutRequests:packedRequests viewport:packed previous:nil];
    CheckLayoutLegality(packedResult, packedRequests, packed, @"铺满画面");
    Check(packedResult.unplaceableBlockIDs.count + packedResult.visiblePlacements.count == packedBlocks.count,
          @"铺满画面：每一块要么有位置、要么被明确标记，不静默丢弃");

    // 极端样本：原文块互相重叠（OCR 把两层文字框在一起），连“覆盖自身”都会压到别的块。
    // 这时必须明确标记“暂不可放置”，而不是强盖上去。
    CGRect overlappingViewport = CGRectMake(0, 0, 320, 170);
    NSArray<FYInlineTextLine *> *overlappingLines = @[
        Line(@"一つ目の重なった見出しです", Box(.05, .30, .80, .30)),
        Line(@"二つ目の重なった見出しです", Box(.20, .35, .75, .28))
    ];
    NSArray<FYInlineTextBlock *> *overlappingBlocks = Group(overlappingLines);
    NSMutableDictionary<NSString *, NSString *> *overlappingTranslations = [NSMutableDictionary dictionary];
    for (FYInlineTextBlock *block in overlappingBlocks) { overlappingTranslations[block.text] = @"重叠的原文块之一"; }
    NSArray<FYInlineLayoutRequest *> *overlappingRequests = RequestsFromBlocks(overlappingBlocks, overlappingTranslations, overlappingViewport);
    FYInlineLayoutResult *overlappingResult = [[FYInlineLayoutEngine defaultEngine] layoutRequests:overlappingRequests viewport:overlappingViewport previous:nil];
    CheckLayoutLegality(overlappingResult, overlappingRequests, overlappingViewport, @"重叠原文块");
    Check(overlappingResult.unplaceableBlockIDs.count > 0,
          @"重叠原文块：无法合法放置的块被明确上报，而不是强盖其它条目");
    for (FYInlinePlacement *placement in overlappingResult.placements) {
        if (placement.mode != FYInlineDisplayModeUnplaceable) { continue; }
        Check(placement.reason.length > 0, @"重叠原文块：给出不可放置的原因");
        Check(CGRectIsEmpty(placement.translationFrame), @"重叠原文块：不可放置的块没有伪造位置");
    }
}

static void TestLayoutStabilityAndResize(void) {
    CGRect viewport = CGRectMake(0, 0, 1440, 900);
    NSArray<FYInlineTextBlock *> *blocks = Group(NewsPageLines());
    NSArray<FYInlineLayoutRequest *> *requests = RequestsFromBlocks(blocks, NewsTranslations(), viewport);
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    FYInlineLayoutResult *first = [engine layoutRequests:requests viewport:viewport previous:nil];
    FYInlineLayoutResult *second = [engine layoutRequests:requests viewport:viewport previous:first];
    Check(!second.changedFromPrevious, @"稳定：画面与文本没变时不重排");
    for (NSUInteger index = 0; index < first.placements.count; index++) {
        Check(NSEqualRects(first.placements[index].translationFrame, second.placements[index].translationFrame),
              @"稳定：重复布局结果一致");
    }

    // OCR 抖动 1~2 像素：身份不变、位置不跳。
    NSMutableArray<FYInlineTextLine *> *jitteredLines = [NSMutableArray array];
    for (FYInlineTextLine *line in NewsPageLines()) {
        CGRect rect = line.rect;
        rect.origin.x += 0.0015;   // 约 2px（1440 宽）
        rect.origin.y -= 0.0012;
        [jitteredLines addObject:Line(line.text, rect)];
    }
    NSArray<FYInlineTextBlock *> *jitteredBlocks = Group(jitteredLines);
    NSArray<FYInlineLayoutRequest *> *jitteredRequests = RequestsFromBlocks(jitteredBlocks, NewsTranslations(), viewport);
    FYInlineLayoutResult *jittered = [engine layoutRequests:jitteredRequests viewport:viewport previous:first];
    Check(jittered.placements.count == first.placements.count, @"稳定：抖动后块数量不变");
    for (NSUInteger index = 0; index < jittered.placements.count; index++) {
        Check([jittered.placements[index].blockID isEqualToString:first.placements[index].blockID],
              @"稳定：轻微抖动不换块身份（文本相似 + 位置重叠匹配）");
        Check(fabs(NSMidY(jittered.placements[index].translationFrame) - NSMidY(first.placements[index].translationFrame)) < 12,
              @"稳定：轻微抖动不引起译文跳位");
    }

    // 画面尺寸变了：必须更新（不能沿用旧坐标）。
    CGRect resized = CGRectMake(0, 0, 1000, 620);
    NSArray<FYInlineLayoutRequest *> *resizedRequests = RequestsFromBlocks(blocks, NewsTranslations(), resized);
    FYInlineLayoutResult *resizedResult = [engine layoutRequests:resizedRequests viewport:resized previous:first];
    Check(resizedResult.changedFromPrevious, @"缩放：画面尺寸变化必须重新布局");
    CheckLayoutLegality(resizedResult, resizedRequests, resized, @"缩放后");
}

static void TestLayoutJitterDoesNotMatchDifferentText(void) {
    CGRect viewport = CGRectMake(0, 0, 1200, 800);
    NSArray<FYInlineTextLine *> *lines = @[Line(@"まったく別の文章です。", Box(.10, .70, .40, .04))];
    NSArray<FYInlineTextBlock *> *blocks = Group(lines);
    NSArray<FYInlineLayoutRequest *> *requests = RequestsFromBlocks(blocks, @{blocks.firstObject.text: @"完全不同的一篇文章。"}, viewport);
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    FYInlineLayoutResult *first = [engine layoutRequests:requests viewport:viewport previous:nil];

    NSArray<FYInlineTextLine *> *otherLines = @[Line(@"画面が切り替わった別の見出し", Box(.55, .30, .35, .035))];
    NSArray<FYInlineTextBlock *> *otherBlocks = Group(otherLines);
    NSArray<FYInlineLayoutRequest *> *otherRequests = RequestsFromBlocks(otherBlocks, @{otherBlocks.firstObject.text: @"换页后的另一个标题"}, viewport);
    FYInlineLayoutResult *second = [engine layoutRequests:otherRequests viewport:viewport previous:first];
    Check(![second.placements.firstObject.blockID isEqualToString:first.placements.firstObject.blockID],
          @"稳定：换页/明显滚动后不沿用旧块身份");
}

#pragma mark - C. 真实 OCR 夹具

static NSDictionary *LoadJSON(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) { return nil; }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

static NSArray<FYInlineTextLine *> *LinesFromOCRFiixture(NSDictionary *fixture) {
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray array];
    NSInteger index = 0;
    for (NSDictionary *entry in fixture[@"lines"]) {
        NSString *text = entry[@"text"];
        if (![text isKindOfClass:NSString.class]) { continue; }
        CGRect rect = CGRectMake([entry[@"x"] doubleValue], [entry[@"y"] doubleValue],
                                 [entry[@"w"] doubleValue], [entry[@"h"] doubleValue]);
        CGFloat confidence = [entry[@"confidence"] doubleValue];
        [lines addObject:[FYInlineTextLine lineWithText:text rect:rect confidence:confidence sourceIndex:index]];
        index += 1;
    }
    return lines;
}

/// 对照图：原图 + OCR 行框（蓝）+ 分组框（绿）+ 最终译文位置（橙/红）。
static void RenderOverlay(NSString *imagePath,
                          NSArray<FYInlineTextLine *> *lines,
                          NSArray<FYInlineTextBlock *> *blocks,
                          FYInlineLayoutResult *result,
                          NSString *outPath) {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:imagePath];
    if (!image) { return; }
    NSSize size = image.size;
    NSImage *canvas = [[NSImage alloc] initWithSize:size];
    [canvas lockFocus];
    [image drawInRect:NSMakeRect(0, 0, size.width, size.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    NSDictionary *labelAttributes = @{NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold],
                                      NSForegroundColorAttributeName: NSColor.whiteColor,
                                      NSParagraphStyleAttributeName: style};
    // 画布是 AppKit 标准坐标（原点左下），Vision 归一化坐标同样原点左下 —— 直接映射，不翻转。
    for (FYInlineTextLine *line in lines) {
        NSRect rect = NSMakeRect(line.rect.origin.x * size.width,
                                 line.rect.origin.y * size.height,
                                 line.rect.size.width * size.width, line.rect.size.height * size.height);
        [[NSColor colorWithSRGBRed:0.2 green:0.6 blue:1 alpha:0.9] setStroke];
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:rect];
        path.lineWidth = 1;
        [path stroke];
    }
    NSUInteger blockIndex = 0;
    for (FYInlineTextBlock *block in blocks) {
        blockIndex += 1;
        NSRect rect = NSMakeRect(block.boundingBox.origin.x * size.width,
                                 block.boundingBox.origin.y * size.height,
                                 block.boundingBox.size.width * size.width, block.boundingBox.size.height * size.height);
        [[NSColor colorWithSRGBRed:0.1 green:0.85 blue:0.3 alpha:0.95] setStroke];
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:rect];
        path.lineWidth = 2;
        [path stroke];
        NSString *label = [NSString stringWithFormat:@"B%lu %@ %.2f", (unsigned long)blockIndex,
                           block.kind == FYInlineBlockKindLong ? @"long" : @"short", block.groupingConfidence];
        [label drawAtPoint:NSMakePoint(rect.origin.x + 2, rect.origin.y + 2) withAttributes:labelAttributes];
    }
    for (FYInlinePlacement *placement in result.placements) {
        if (placement.mode == FYInlineDisplayModeUnplaceable) { continue; }
        // 译文框本来就是显示区域坐标（原点左下），与画布一致 —— 直接画。
        NSRect rect = placement.translationFrame;
        NSColor *color = placement.mode == FYInlineDisplayModeCompactEntry
            ? [NSColor colorWithSRGBRed:1 green:0.2 blue:0.2 alpha:1]
            : (placement.block.kind == FYInlineBlockKindLong
               ? [NSColor colorWithSRGBRed:1 green:0.55 blue:0.05 alpha:1]
               : [NSColor colorWithSRGBRed:1 green:0.85 blue:0.1 alpha:1]);
        [color setStroke];
        [[color colorWithAlphaComponent:0.22] setFill];
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:rect];
        path.lineWidth = 2.5;
        [path fill];
        [path stroke];
        NSString *label = [NSString stringWithFormat:@"B%lu %@/%@", (unsigned long)([blocks indexOfObject:placement.block] + 1),
                           placement.mode == FYInlineDisplayModeShortLabel ? @"短贴片" :
                           (placement.mode == FYInlineDisplayModeFullCard ? @"完整长卡" :
                            (placement.mode == FYInlineDisplayModeScrollingCard ? @"滚动长卡" : @"紧凑入口")),
                           placement.anchor == FYInlineAnchorBelow ? @"下" :
                           (placement.anchor == FYInlineAnchorAbove ? @"上" :
                            (placement.anchor == FYInlineAnchorRight ? @"右" :
                             (placement.anchor == FYInlineAnchorLeft ? @"左" :
                              (placement.anchor == FYInlineAnchorOverlay ? @"覆盖" : @"入口"))))];
        [label drawAtPoint:NSMakePoint(rect.origin.x + 3, MAX(0, rect.origin.y - 14)) withAttributes:labelAttributes];
    }
    [canvas unlockFocus];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:canvas.TIFFRepresentation];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:outPath atomically:YES];
}

/// 面板外观预览：按最终排版把「奶油底 alpha 0.85 + 深棕字」画在真实画面上，
/// 用来检查源画面文字是否会透出来形成“双层文字”。这不是产品渲染，只是外观核对图。
static void RenderAppearancePreview(NSString *imagePath,
                                    NSArray<FYInlineTextLine *> *lines,
                                    NSArray<FYInlineTextBlock *> *blocks,
                                    FYInlineLayoutResult *result,
                                    NSDictionary<NSString *, NSString *> *translations,
                                    NSString *outPath) {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:imagePath];
    if (!image) { return; }
    NSSize size = image.size;
    NSImage *canvas = [[NSImage alloc] initWithSize:size];
    [canvas lockFocus];
    [image drawInRect:NSMakeRect(0, 0, size.width, size.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    for (FYInlinePlacement *placement in result.placements) {
        if (placement.mode == FYInlineDisplayModeUnplaceable) { continue; }
        NSRect frame = placement.translationFrame;
        // 用应用默认的「背景透明度」设置值渲染（现在是跟随设置，不再是固定 0.85）。
        NSColor *cream = [NSColor colorWithSRGBRed:1.0 green:0.973 blue:0.925 alpha:0.58];
        [cream setFill];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:frame
                                                            xRadius:(placement.block.kind == FYInlineBlockKindLong ? 12 : 7)
                                                            yRadius:(placement.block.kind == FYInlineBlockKindLong ? 12 : 7)];
        [path fill];
        [[NSColor colorWithSRGBRed:0.73 green:0.63 blue:0.51 alpha:1] setStroke];
        path.lineWidth = 1.5;
        [path stroke];
        NSString *translation = translations[placement.block.text] ?: placement.translation;
        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.lineBreakMode = NSLineBreakByCharWrapping;
        style.lineSpacing = placement.block.kind == FYInlineBlockKindLong ? 8 : 3;
        NSDictionary *attributes = @{NSFontAttributeName: placement.font ?: [NSFont systemFontOfSize:16],
                                     NSForegroundColorAttributeName: [NSColor colorWithSRGBRed:0.35 green:0.24 blue:0.17 alpha:1],
                                     NSParagraphStyleAttributeName: style};
        NSRect textRect = NSInsetRect(frame, placement.block.kind == FYInlineBlockKindLong ? 18 : 10,
                                      placement.block.kind == FYInlineBlockKindLong ? 18 : 5);
        if (placement.block.kind == FYInlineBlockKindLong) { textRect.origin.y += 30; textRect.size.height -= 30; }
        [translation drawWithRect:textRect options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes];
    }
    [canvas unlockFocus];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:canvas.TIFFRepresentation];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:outPath atomically:YES];
}

/// 真实画面（用户现场采集帧）的手写中文译文，按行给出；用于测量与阅读层级，
/// 不是模型输出。布局只关心文本尺寸，因此这里必须用真实长度的译文而不是占位符。
static NSDictionary<NSString *, NSString *> *RealFrameTranslations(void) {
    return @{
        @"バンビへダメ出し！": @"给巴姆比的差评！",
        @"星の警告": @"星象的警告",
        @"乗り気じゃないときに": @"在没那个心思的时候",
        @"ムリしても失敗するだけ。": @"硬来也只会失败。",
        @"WEBの占いとか見て": @"去看看网上的占卜什么的",
        @"ヨロシクね♪": @"拜托啦♪",
        @"波を知ったほうがいいよ？": @"最好还是先了解一下运势哦？",
        @"倒れてからじゃ遅いんだから！": @"等倒下了可就晚了！",
        @"& バンビへ": @"& 致巴姆比",
        @"わかった？": @"明白了吗？",
        @"アルバイト情報": @"兼职信息",
        @"+Karen+": @"+Karen+",
        @"ルームへ": @"前往房间",
        @"•・戻る": @"•・返回"
    };
}

static void TestRealOCRCaptureFrame(NSString *outputDirectory) {
    NSString *fixturePath = @".build/inline-layout/fixtures/frame-02.json";
    NSDictionary *fixture = LoadJSON(fixturePath);
    if (!fixture) {
        NSLog(@"SKIP 真实 OCR 夹具尚未生成：%@（第一步人工框结果不受影响）", fixturePath);
        return;
    }
    NSArray<FYInlineTextLine *> *lines = LinesFromOCRFiixture(fixture);
    Check(lines.count >= 10, [NSString stringWithFormat:@"真实 OCR：读到 %lu 行", (unsigned long)lines.count]);

    NSArray<FYInlineTextBlock *> *blocks = Group(lines);
    LogBlocks(@"真实 OCR", blocks);
    Check(blocks.count >= 6 && blocks.count <= lines.count,
          [NSString stringWithFormat:@"真实 OCR：%lu 行并成 %lu 块", (unsigned long)lines.count, (unsigned long)blocks.count]);
    // 左侧邮件列表与右侧正文必须分开：不能出现横跨整屏的大块。
    for (FYInlineTextBlock *block in blocks) {
        Check(block.boundingBox.size.width < 0.60,
              [NSString stringWithFormat:@"真实 OCR：没有跨栏大块（宽度 %.2f）", block.boundingBox.size.width]);
    }
    Check(HasBlockContaining(blocks, @"乗り気じゃないときに"), @"真实 OCR：右侧正文至少成块");

    CGFloat imageWidth = [fixture[@"image"][@"width"] doubleValue] ?: 1920;
    CGFloat imageHeight = [fixture[@"image"][@"height"] doubleValue] ?: 1080;
    // 布局在“显示区域”坐标下：这里直接以画面像素为显示区域（宽 = 图像宽 * 0.9 的可见区域示例）。
    CGRect viewport = CGRectMake(0, 0, imageWidth, imageHeight);
    NSDictionary<NSString *, NSString *> *translations = RealFrameTranslations();
    NSMutableArray<FYInlineLayoutRequest *> *requests = [NSMutableArray array];
    for (FYInlineTextBlock *block in blocks) {
        NSString *translation = translations[block.text];
        if (translation.length == 0) {
            // 没有手写译文的行：保留原文长度用于测量，报告里明确标注。
            translation = block.text;
        }
        CGRect frame = CGRectMake(block.boundingBox.origin.x * imageWidth,
                                  block.boundingBox.origin.y * imageHeight,
                                  block.boundingBox.size.width * imageWidth,
                                  block.boundingBox.size.height * imageHeight);
        [requests addObject:[FYInlineLayoutRequest requestWithBlock:block translation:translation sourceFrame:frame]];
    }
    FYInlineLayoutResult *result = [[FYInlineLayoutEngine defaultEngine] layoutRequests:requests viewport:viewport previous:nil];
    CheckLayoutLegality(result, requests, viewport, @"真实 OCR");

    for (NSUInteger index = 0; index < result.placements.count; index++) {
        FYInlinePlacement *placement = result.placements[index];
        NSLog(@"  真实 OCR 放置 P%lu mode=%ld anchor=%ld frame=(%.0f,%.0f,%.0f,%.0f) src=(%.0f,%.0f,%.0f,%.0f) reason=%@",
              (unsigned long)(index + 1), (long)placement.mode, (long)placement.anchor,
              placement.translationFrame.origin.x, placement.translationFrame.origin.y,
              NSWidth(placement.translationFrame), NSHeight(placement.translationFrame),
              placement.sourceFrame.origin.x, placement.sourceFrame.origin.y,
              NSWidth(placement.sourceFrame), NSHeight(placement.sourceFrame), placement.reason);
    }
    NSString *report = [NSString stringWithFormat:
        @"{\"fixture\":\"frame-02\",\"lines\":%lu,\"blocks\":%lu,\"placements\":%lu,\"unplaceable\":%lu,\"compact\":%lu}",
        (unsigned long)lines.count, (unsigned long)blocks.count, (unsigned long)result.placements.count,
        (unsigned long)result.unplaceableBlockIDs.count, (unsigned long)result.compactEntryBlockIDs.count];
    NSString *textPath = [outputDirectory stringByAppendingPathComponent:@"real-ocr-summary.txt"];
    [report writeToFile:textPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSLog(@"真实 OCR 摘要：%@", report);

    NSString *overlay = [outputDirectory stringByAppendingPathComponent:@"overlay-frame-02.png"];
    RenderOverlay(@".build/capture-card-check/hardware-capture-20261005/frame-02.png", lines, blocks, result, overlay);
    Check([[NSFileManager defaultManager] fileExistsAtPath:overlay], @"真实 OCR：生成 OCR 框／分组／译文位置对照图");
    NSString *preview = [outputDirectory stringByAppendingPathComponent:@"preview-frame-02-panels.png"];
    NSMutableDictionary<NSString *, NSString *> *previewTranslations = [translations mutableCopy];
    for (FYInlineTextBlock *block in blocks) {
        if (previewTranslations[block.text].length == 0) { previewTranslations[block.text] = block.text; }
    }
    RenderAppearancePreview(@".build/capture-card-check/hardware-capture-20261005/frame-02.png", lines, blocks, result,
                            previewTranslations, preview);
    Check([[NSFileManager defaultManager] fileExistsAtPath:preview], @"真实 OCR：生成面板外观（alpha 0.85）核对图");
}

#pragma mark - D. 接入运行界面后的端到端行为

/// withMainWindow：需要状态区/主界面译文区（真实控件）时传 YES。
/// 注意主窗口创建会刷新窗口列表，所以假目标窗口必须在它之后装上。
static AppDelegate *InlineFixtureAppWithOptions(CGRect windowBounds, BOOL withMainWindow);

static AppDelegate *InlineFixtureApp(CGRect windowBounds) {
    return InlineFixtureAppWithOptions(windowBounds, NO);
}

static AppDelegate *InlineFixtureAppWithOptions(CGRect windowBounds, BOOL withMainWindow) {
    AppDelegate *app = [[AppDelegate alloc] init];
    if (withMainWindow) { [app createMainWindow]; }
    app.inlineTranslationPanels = [NSMutableArray array];
    app.inlineLongCardPanels = [NSMutableArray array];
    app.inlineTranslationCache = [NSMutableDictionary dictionary];
    app.captionFontSizeSlider = [NSSlider sliderWithValue:30 minValue:12 maxValue:48 target:nil action:nil];
    app.captionOpacitySlider = [NSSlider sliderWithValue:0.58 minValue:0 maxValue:1 target:nil action:nil];
    WindowItem *window = [[WindowItem alloc] init];
    window.windowID = 9101;
    window.displayName = @"Fixture";
    window.bounds = windowBounds;
    app.windows = [NSMutableArray arrayWithObject:window];
    app.windowPopup = [[NSPopUpButton alloc] init];
    [app.windowPopup addItemWithTitle:@"Fixture"];
    app.windowPopup.menu.itemArray.firstObject.representedObject = @(9101);
    return app;
}

static OCRTextItem *AppItem(NSString *text, CGRect box, InlineBlockKind kind) {
    OCRTextItem *item = [[OCRTextItem alloc] init];
    item.text = text;
    item.boundingBox = box;
    item.lineBoxes = @[[NSValue valueWithRect:box]];
    item.lineCount = 1;
    item.blockKind = kind;
    item.confidence = 0.9;
    item.groupingConfidence = 1.0;
    return item;
}

static NSScrollView *LongCardScrollOf(NSPanel *panel) {
    for (NSView *child in panel.contentView.subviews) {
        if ([child isKindOfClass:NSScrollView.class]) { return (NSScrollView *)child; }
    }
    return nil;
}

/// 面板绝不覆盖任何**别的**原文块（端到端：真正渲染出来的窗口中检查）。
static void CheckAppPanelsDoNotCoverOtherSources(AppDelegate *app,
                                                 NSArray<OCRTextItem *> *items,
                                                 NSRect windowFrame,
                                                 NSString *label) {
    NSMutableArray<NSPanel *> *panels = [[app.inlineTranslationPanels arrayByAddingObjectsFromArray:app.inlineLongCardPanels] mutableCopy];
    for (NSPanel *panel in panels) {
        for (OCRTextItem *item in items) {
            NSRect source = [app appKitFrameForOCRItem:item inWindowFrame:windowFrame];
            // 自己那一块允许被覆盖（覆盖自身正文是合法降级），别的块不允许。
            NSString *identity = [app inlineBlockIdentityForItem:item];
            if ([panel.identifier isEqualToString:identity]) { continue; }
            if ([panel.identifier containsString:identity]) { continue; }
            Check(!CGRectIntersectsRect(panel.frame, source),
                  [NSString stringWithFormat:@"%@：面板 %@ 没有遮挡原文 <%@>", label, panel.identifier, Shorten(item.text, 18)]);
        }
    }
}

static void TestAppCompactEntryOpensFullCard(void) {
    // 画面高度不足以放下可读的三行正文 → 紧凑入口；点击后打开完整阅读卡并保留块身份。
    AppDelegate *app = InlineFixtureApp(CGRectMake(0, 0, 520, 170));
    OCRTextItem *item = AppItem(@"新しい季節のイベントが始まります。\n期間中は限定の衣装も登場します。\nぜひお見逃しなく。",
                               CGRectMake(0.06, 0.30, 0.60, 0.22), InlineBlockKindLong);
    [app showInlineTranslations:@[@"新的季节活动即将开始。活动期间还会推出限定服装，请千万不要错过。"]
                       forItems:@[item]];
    Check(app.inlineLongCardPanels.count == 1, @"紧凑入口场景：生成一个长卡面板");
    NSPanel *panel = app.inlineLongCardPanels.firstObject;
    FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
    Check([card isKindOfClass:FYInlineLongCardView.class] && card.compactEntry,
          @"紧凑入口场景：面板是紧凑入口而不是细条");
    Check(NSHeight(panel.frame) >= 30 && NSWidth(panel.frame) >= 120, @"紧凑入口仍有可点击尺寸");
    Check(card.onClick != nil, @"紧凑入口可点击");
    card.onClick();
    Check(app.inlineExpandedReadingPanel != nil, @"点击紧凑入口打开完整阅读卡");
    if (app.inlineExpandedReadingPanel) {
        NSScrollView *scroll = LongCardScrollOf(app.inlineExpandedReadingPanel);
        Check(scroll != nil, @"展开的完整阅读卡有滚动区");
        // 展开卡自己的点击目标必须绑定**这一块**的原文（不是最新对白、也不是别的块）。
        FYInlineLongCardView *expanded = (FYInlineLongCardView *)app.inlineExpandedReadingPanel.contentView;
        Check([expanded isKindOfClass:FYInlineLongCardView.class] && expanded.onClick != nil,
              @"展开的完整阅读卡可点击进入学习");
        Check([[app inlineSnapshotForItem:item translation:@"x"].blockID isEqualToString:[app inlineBlockIdentityForItem:item]],
              @"展开卡的块身份与原始块一致");
        [app closeExpandedInlineReadingCard];
        Check(app.inlineExpandedReadingPanel == nil, @"展开卡可以关闭");
    }
    [app clearInlineTranslationPanels];
}

static void TestAppScrollPositionSemantics(void) {
    AppDelegate *app = InlineFixtureApp(CGRectMake(0, 0, 1440, 900));
    OCRTextItem *itemA = AppItem(@"新しい季節のイベントが始まります。\n期間中は限定の衣装も登場します。\nぜひお見逃しなく。",
                                 CGRectMake(0.08, 0.14, 0.42, 0.10), InlineBlockKindLong);
    NSString *longTranslation = @"新的季节活动即将开始。活动期间还会推出限定服装，请千万不要错过。此外还计划公开期间限定的特别剧情，"
                                 "详情请查看官方网站。为了让这段译文超过卡片允许的最大高度、必须滚动才能读到结尾，这里补充大量说明文字："
                                 "活动期间每天登录还可以领取一份小礼物，累计登录七天可获得特别的纪念道具；参与限时任务还能获得额外的兑换券，"
                                 "兑换券可以在活动商店换取限定头像框与家具。活动结束后未使用的兑换券会按比例折算成普通金币。";
    [app showInlineTranslations:@[longTranslation] forItems:@[itemA]];
    Check(app.inlineLongCardPanels.count == 1, @"滚动语义：生成一张长卡");
    NSPanel *panel = app.inlineLongCardPanels.firstObject;
    NSScrollView *scroll = LongCardScrollOf(panel);
    Check(scroll != nil && NSHeight(scroll.documentView.frame) > NSHeight(scroll.contentView.bounds),
          @"滚动语义：正文可滚动到末尾");
    CGFloat maxY = NSHeight(scroll.documentView.frame) - NSHeight(scroll.contentView.bounds);
    [scroll.contentView scrollToPoint:NSMakePoint(0, maxY)];
    [scroll reflectScrolledClipView:scroll.contentView];
    Check(scroll.contentView.bounds.origin.y > 0, @"滚动语义：确实滚到了中间/底部");

    // 同一块更新（译文变长）：保留滚动位置（并夹到新的可滚动范围）。
    NSString *longer = [longTranslation stringByAppendingString:@"补充说明：活动内容可能在不另行通知的情况下变更，请以官方公告为准。更多详情请查看官方网站的活动页面。"];
    [app showInlineTranslations:@[longer] forItems:@[itemA]];
    NSPanel *samePanel = app.inlineLongCardPanels.firstObject;
    NSScrollView *sameScroll = LongCardScrollOf(samePanel);
    Check(samePanel == panel, @"滚动语义：同一块更新复用同一面板");
    Check(sameScroll.contentView.bounds.origin.y > 0, @"滚动语义：同一块更新保留滚动位置");

    // 切换到另一块：新面板必须从正文开头开始。
    OCRTextItem *itemB = AppItem(@"さらに、期間限定の特別なストーリーも公開予定です。\n詳細は公式サイトをご確認ください。",
                                 CGRectMake(0.56, 0.16, 0.38, 0.09), InlineBlockKindLong);
    [app showInlineTranslations:@[longer] forItems:@[itemB]];
    Check(app.inlineLongCardPanels.count == 1, @"滚动语义：切换块后仍然一张卡");
    NSPanel *other = app.inlineLongCardPanels.firstObject;
    Check(other != panel, @"滚动语义：切换到另一块时新建面板（旧面板关闭）");
    NSScrollView *otherScroll = LongCardScrollOf(other);
    Check(otherScroll.contentView.bounds.origin.y == 0, @"滚动语义：切换到另一块回到正文开头");
    [app clearInlineTranslationPanels];
}

static void TestAppJitterKeepsPanelIdentity(void) {
    AppDelegate *app = InlineFixtureApp(CGRectMake(0, 0, 1440, 900));
    NSArray<OCRTextItem *> *items = @[
        AppItem(@"公演日程", CGRectMake(0.08, 0.76, 0.15, 0.028), InlineBlockKindShort),
        AppItem(@"イベント情報", CGRectMake(0.08, 0.69, 0.16, 0.028), InlineBlockKindShort)
    ];
    [app showInlineTranslations:@[@"公演日程", @"活动信息"] forItems:items];
    Check(app.inlineTranslationPanels.count == 2, @"抖动：先生成两个贴片");
    NSPanel *first = app.inlineTranslationPanels.firstObject;
    NSRect firstFrame = first.frame;

    // OCR 抖动 2~3 像素：不得换面板、不得跳位。
    NSMutableArray<OCRTextItem *> *jittered = [NSMutableArray array];
    for (OCRTextItem *item in items) {
        CGRect box = item.boundingBox;
        box.origin.x += 0.002;
        box.origin.y += 0.0015;
        [jittered addObject:AppItem(item.text, box, InlineBlockKindShort)];
    }
    [app showInlineTranslations:@[@"公演日程", @"活动信息"] forItems:jittered];
    Check(app.inlineTranslationPanels.count == 2, @"抖动：贴片数量不变");
    NSPanel *afterJitter = app.inlineTranslationPanels.firstObject;
    Check(afterJitter == first, @"抖动：复用同一个面板实例（不重建、不闪）");
    Check(fabs(NSMidX(afterJitter.frame) - NSMidX(firstFrame)) <= 6 &&
          fabs(NSMidY(afterJitter.frame) - NSMidY(firstFrame)) <= 6,
          @"抖动：译文位置不跳");

    // 画面明显变化（换页）：面板内容随之更新，不是简单沿用旧位置。
    NSArray<OCRTextItem *> *moved = @[
        AppItem(@"公演日程", CGRectMake(0.08, 0.20, 0.15, 0.028), InlineBlockKindShort),
        AppItem(@"イベント情報", CGRectMake(0.08, 0.13, 0.16, 0.028), InlineBlockKindShort)
    ];
    [app showInlineTranslations:@[@"公演日程", @"活动信息"] forItems:moved];
    NSPanel *afterMove = app.inlineTranslationPanels.firstObject;
    Check(fabs(NSMidY(afterMove.frame) - NSMidY(firstFrame)) > 100,
          @"明显滚动/换页：译文位置必须跟着更新");
    CheckAppPanelsDoNotCoverOtherSources(app, moved, NSMakeRect(0, 0, 1440, 900), @"抖动后");
    [app clearInlineTranslationPanels];
}

static void TestAppUnplaceableIsReportedNotDropped(void) {
    // 两个原文块互相重叠、画面又小到没有别的合法位置：必须标记“暂不可放置”，
    // 不能强盖，也不能静默丢弃（主界面译文区与状态区都要能看到）。
    // 状态区与主界面译文区是主窗口里的控件：这里创建主窗口，才能验证“不静默丢弃”。
    AppDelegate *app = InlineFixtureAppWithOptions(CGRectMake(0, 0, 340, 120), YES);
    OCRTextItem *itemA = AppItem(@"重なった見出しです", CGRectMake(0.02, 0.04, 0.95, 0.88), InlineBlockKindShort);
    OCRTextItem *itemB = AppItem(@"二つ目の見出しです", CGRectMake(0.05, 0.08, 0.90, 0.80), InlineBlockKindShort);
    NSArray<NSString *> *translations = @[@"重叠的标题之一", @"第二个标题"];
    [app showInlineTranslations:translations forItems:@[itemA, itemB]];
    Check(app.lastInlineUnplaceableCount == 2,
          [NSString stringWithFormat:@"不可放置：两块都被标记（实际 %lu）", (unsigned long)app.lastInlineUnplaceableCount]);
    Check(app.inlineTranslationPanels.count == 0, @"不可放置：没有伪造位置的面板");
    Check(app.lastInlineLayoutResult.placements.count == 2, @"不可放置：布局结果仍逐块给出原因");
    for (FYInlinePlacement *placement in app.lastInlineLayoutResult.placements) {
        Check(placement.mode == FYInlineDisplayModeUnplaceable, @"不可放置：模式明确为 unplaceable");
        Check(placement.reason.length > 0, @"不可放置：有人可读原因");
    }

    // 走完整的翻译结果入口：状态区说明降级，主界面译文区优先列出这些译文。
    [app handleInlineTranslationResult:translations
                              forItems:@[itemA, itemB]
                                 error:nil
                         failureStatus:@"界面翻译出错"
                         successPrefix:@"界面译文已更新"];
    Tick();
    Check([app.statusLabel.stringValue containsString:@"暂不可放置"],
          [NSString stringWithFormat:@"不可放置：状态区给出提示（实际“%@”）", app.statusLabel.stringValue]);
    Check([app.statusLabel.stringValue containsString:@"重叠的标题"],
          @"不可放置：状态区直接给出未放置译文的原文，不是只报一个数字");
    [app clearInlineTranslationPanels];
}

/// 视觉风险取证：alpha 0.85 的长卡在**覆盖自身原文**这一降级模式下，
/// 源画面文字会以约 15% 透出（双层文字）。这里用真实采集帧把该情形画出来，单独报告。
static void TestRealOCROverlayDoubleText(NSString *outputDirectory) {
    NSDictionary *fixture = LoadJSON(@".build/inline-layout/fixtures/frame-02.json");
    if (!fixture) { NSLog(@"SKIP 覆盖式双层文字取证：缺少真实 OCR 夹具"); return; }
    NSArray<FYInlineTextLine *> *lines = LinesFromOCRFiixture(fixture);
    NSArray<FYInlineTextBlock *> *blocks = Group(lines);
    FYInlineTextBlock *letter = nil;
    for (FYInlineTextBlock *block in blocks) {
        if (block.kind == FYInlineBlockKindLong) { letter = block; }
    }
    if (!letter) { NSLog(@"SKIP 覆盖式双层文字取证：真实帧里没有长正文块"); return; }
    CGFloat imageWidth = [fixture[@"image"][@"width"] doubleValue] ?: 1920;
    CGFloat imageHeight = [fixture[@"image"][@"height"] doubleValue] ?: 1080;
    // 把可见区域收到正文自身附近：下方/上方/侧边全部不合法，只剩“覆盖自身正文”。
    NSRect source = CGRectMake(letter.boundingBox.origin.x * imageWidth,
                               letter.boundingBox.origin.y * imageHeight,
                               letter.boundingBox.size.width * imageWidth,
                               letter.boundingBox.size.height * imageHeight);
    CGRect viewport = CGRectInset(source, -20, -16);
    NSString *translation = @"在没那个心思的时候，硬来也只会失败。去看看网上的占卜什么的，最好还是先了解一下运势哦？等倒下了可就晚了！明白了吗？+Karen+";
    FYInlineLayoutRequest *request = [FYInlineLayoutRequest requestWithBlock:letter translation:translation sourceFrame:source];
    FYInlineLayoutResult *result = [[FYInlineLayoutEngine defaultEngine] layoutRequests:@[request] viewport:viewport previous:nil];
    FYInlinePlacement *placement = result.placements.firstObject;
    Check(placement.mode != FYInlineDisplayModeUnplaceable, @"覆盖式取证：在紧贴正文的可见区域里仍能给出阅读卡");
    Check(placement.anchor == FYInlineAnchorOverlay,
          [NSString stringWithFormat:@"覆盖式取证：确实落到“覆盖自身正文”（anchor=%ld）", (long)placement.anchor]);
    NSString *out = [outputDirectory stringByAppendingPathComponent:@"preview-frame-02-overlay-doubletext.png"];
    RenderAppearancePreview(@".build/capture-card-check/hardware-capture-20261005/frame-02.png", lines, blocks, result,
                            @{letter.text: translation}, out);
    Check([[NSFileManager defaultManager] fileExistsAtPath:out], @"覆盖式取证：生成双层文字核对图");
    NSLog(@"覆盖式取证：长卡 frame=(%.0f,%.0f,%.0f,%.0f) 原因=%@",
          placement.translationFrame.origin.x, placement.translationFrame.origin.y,
          NSWidth(placement.translationFrame), NSHeight(placement.translationFrame), placement.reason);
}

/// 第二份真实 OCR 夹具：应用自身示例页面的真实截图（1440×900 经 sips 缩放到 2000×1250 后 OCR）。
/// 注意：这**不是**用户提供的真实新闻页截图；用户新闻页本轮拿不到真机截图，报告中单独标注。
static void TestRealOCRAppScreenshot(NSString *outputDirectory) {
    NSString *fixturePath = @".build/inline-layout/fixtures/yiya-inline-news.json";
    NSString *imagePath = @".build/inline-layout/inputs/yiya-inline-news.png";
    NSDictionary *fixture = LoadJSON(fixturePath);
    if (!fixture) {
        NSLog(@"SKIP 应用示例页面 OCR 夹具尚未生成：%@", fixturePath);
        return;
    }
    NSArray<FYInlineTextLine *> *lines = LinesFromOCRFiixture(fixture);
    Check(lines.count >= 10, [NSString stringWithFormat:@"应用示例页 OCR：读到 %lu 行", (unsigned long)lines.count]);
    NSArray<FYInlineTextBlock *> *blocks = Group(lines);
    LogBlocks(@"应用示例页", blocks);
    CGFloat imageWidth = [fixture[@"image"][@"width"] doubleValue] ?: 2000;
    CGFloat imageHeight = [fixture[@"image"][@"height"] doubleValue] ?: 1250;
    CGRect viewport = CGRectMake(0, 0, imageWidth, imageHeight);
    NSMutableArray<FYInlineLayoutRequest *> *requests = [NSMutableArray array];
    for (FYInlineTextBlock *block in blocks) {
        // 布局只看文本尺寸：这里用原文占位测量，报告里明确标注不是模型译文。
        NSString *translation = block.kind == FYInlineBlockKindLong
            ? @"这是示例页面的中文译文占位文本，用来验证长卡在真实 OCR 框下的宽度、可读下限与滚动范围。"
            : @"示例条目";
        CGRect frame = CGRectMake(block.boundingBox.origin.x * imageWidth,
                                  block.boundingBox.origin.y * imageHeight,
                                  block.boundingBox.size.width * imageWidth,
                                  block.boundingBox.size.height * imageHeight);
        [requests addObject:[FYInlineLayoutRequest requestWithBlock:block translation:translation sourceFrame:frame]];
    }
    FYInlineLayoutResult *result = [[FYInlineLayoutEngine defaultEngine] layoutRequests:requests viewport:viewport previous:nil];
    CheckLayoutLegality(result, requests, viewport, @"应用示例页");
    NSString *overlay = [outputDirectory stringByAppendingPathComponent:@"overlay-app-screenshot.png"];
    RenderOverlay(imagePath, lines, blocks, result, overlay);
    Check([[NSFileManager defaultManager] fileExistsAtPath:overlay], @"应用示例页：生成对照图");
    NSLog(@"应用示例页摘要：lines=%lu blocks=%lu placements=%lu unplaceable=%lu compact=%lu",
          (unsigned long)lines.count, (unsigned long)blocks.count, (unsigned long)result.placements.count,
          (unsigned long)result.unplaceableBlockIDs.count, (unsigned long)result.compactEntryBlockIDs.count);
}

#pragma mark - E. 贴译透明度跟随设置 + 拖动位置

static NSColor *PanelFillColor(NSPanel *panel) {
    CGColorRef color = panel.contentView.layer.backgroundColor;
    return color ? [NSColor colorWithCGColor:color] : nil;
}

static NSString *ShortPanelText(NSPanel *panel) {
    NSTextField *label = (NSTextField *)panel.contentView.subviews.firstObject;
    return [label isKindOfClass:NSTextField.class] ? label.stringValue : @"";
}

static CGFloat ShortPanelTextAlpha(NSPanel *panel) {
    NSTextField *label = (NSTextField *)panel.contentView.subviews.firstObject;
    if (![label isKindOfClass:NSTextField.class]) { return 0; }
    NSColor *color = label.attributedStringValue.length > 0
        ? [label.attributedStringValue attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]
        : label.textColor;
    return color.alphaComponent;
}

static CGFloat LongCardBodyAlpha(NSPanel *panel) {
    for (NSView *child in panel.contentView.subviews) {
        if (![child isKindOfClass:NSScrollView.class]) { continue; }
        NSView *document = ((NSScrollView *)child).documentView;
        if ([document isKindOfClass:NSTextField.class]) {
            NSTextField *label = (NSTextField *)document;
            NSColor *color = label.attributedStringValue.length > 0
                ? [label.attributedStringValue attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]
                : label.textColor;
            return color.alphaComponent;
        }
    }
    return 0;
}

static void TestAppOpacityFollowsSetting(void) {
    AppDelegate *app = InlineFixtureApp(CGRectMake(0, 0, 1440, 900));
    app.captionOpacitySlider = [NSSlider sliderWithValue:0.58 minValue:0 maxValue:0.95 target:nil action:nil];
    NSArray<OCRTextItem *> *items = @[
        AppItem(@"公演日程", CGRectMake(0.08, 0.76, 0.15, 0.028), InlineBlockKindShort),
        AppItem(@"新しい季節のイベントが始まります。\n期間中は限定の衣装も登場します。\nぜひお見逃しなく。",
                CGRectMake(0.50, 0.30, 0.36, 0.10), InlineBlockKindLong)
    ];
    [app showInlineTranslations:@[@"公演日程", @"新的季节活动即将开始。活动期间还会推出限定服装，请千万不要错过。"] forItems:items];
    Check(app.inlineTranslationPanels.count == 1 && app.inlineLongCardPanels.count == 1, @"透明度：短贴片与长卡各一个面板");
    NSPanel *patch = app.inlineTranslationPanels.firstObject;
    NSPanel *card = app.inlineLongCardPanels.firstObject;
    NSColor *patchFill = PanelFillColor(patch);
    NSColor *cardFill = PanelFillColor(card);
    Check(patchFill && fabs(patchFill.alphaComponent - 0.58) < 0.02,
          [NSString stringWithFormat:@"透明度：短贴片跟随设置值 0.58（实际 %.2f）", patchFill.alphaComponent]);
    Check(cardFill && fabs(cardFill.alphaComponent - 0.58) < 0.02,
          [NSString stringWithFormat:@"透明度：长卡跟随设置值 0.58（实际 %.2f）", cardFill.alphaComponent]);
    Check(ShortPanelTextAlpha(patch) >= 0.99 && LongCardBodyAlpha(card) >= 0.99,
          @"透明度：文字始终完全不透明");

    // 改设置：已显示的两个面板立即更新（只改背景，不动文字）
    app.captionOpacitySlider.doubleValue = 0.30;
    [app controlValueChanged:app.captionOpacitySlider];
    Check(fabs(PanelFillColor(patch).alphaComponent - 0.30) < 0.02 &&
          fabs(PanelFillColor(card).alphaComponent - 0.30) < 0.02,
          [NSString stringWithFormat:@"透明度：改设置后两个面板立即更新（短 %.2f / 卡 %.2f）",
           PanelFillColor(patch).alphaComponent, PanelFillColor(card).alphaComponent]);
    Check(ShortPanelTextAlpha(patch) >= 0.99 && LongCardBodyAlpha(card) >= 0.99,
          @"透明度：改设置只动背景，文字仍不透明");

    // 刷新（译文变化触发就地更新）后不恢复旧值
    [app showInlineTranslations:@[@"公演日程（已更新）", @"新的季节活动即将开始——译文更新，长度足够触发就地更新。"] forItems:items];
    Check(fabs(PanelFillColor(app.inlineTranslationPanels.firstObject).alphaComponent - 0.30) < 0.02,
          @"透明度：刷新后短贴片仍是新值");
    Check(fabs(PanelFillColor(app.inlineLongCardPanels.firstObject).alphaComponent - 0.30) < 0.02,
          @"透明度：刷新后长卡仍是新值");
    [app clearInlineTranslationPanels];

    // 新建设置（没有滑块的极端情况）用与设置一致的默认值，而不是 0
    AppDelegate *bare = InlineFixtureApp(CGRectMake(0, 0, 1440, 900));
    Check(fabs([bare inlinePanelFillAlpha] - 0.58) < 0.001, @"透明度：拿不到滑块时用设置默认值 0.58");
}

static void TestLayoutManualOffset(void) {
    CGRect viewport = CGRectMake(0, 0, 1440, 900);
    NSArray<FYInlineTextLine *> *lines = @[
        Line(@"新しい季節のイベントが始まります。", Box(.08, .47, .42, .032)),
        Line(@"期間中は限定の衣装も登場します。", Box(.08, .435, .42, .032)),
        Line(@"ぜひお見逃しなく。", Box(.08, .40, .42, .032))
    ];
    NSArray<FYInlineTextBlock *> *blocks = Group(lines);
    NSArray<FYInlineLayoutRequest *> *requests = RequestsFromBlocks(blocks, @{blocks.firstObject.text: @"新的季节活动即将开始，请千万不要错过。"}, viewport);
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    FYInlineLayoutResult *automatic = [engine layoutRequests:requests viewport:viewport previous:nil];
    NSRect autoFrame = automatic.placements.firstObject.translationFrame;
    CGRect source = requests.firstObject.sourceFrame;
    FYInlinePlacement *autoPlacement = automatic.placements.firstObject;

    // 手动偏移：位置 = 原文锚点 + 偏移，锚点记成 Manual
    FYInlineLayoutRequest *manual = [FYInlineLayoutRequest requestWithBlock:blocks.firstObject
                                                                translation:autoPlacement.translation
                                                                sourceFrame:source];
    manual.manuallyPlaced = YES;
    manual.manualOffset = CGSizeMake(40, 120);
    FYInlineLayoutResult *manualResult = [engine layoutRequests:@[manual] viewport:viewport previous:nil];
    FYInlinePlacement *placement = manualResult.placements.firstObject;
    Check(placement.manuallyPlaced && placement.anchor == FYInlineAnchorManual, @"手动位置：标成手动锚点");
    Check(fabs(NSMinX(placement.translationFrame) - (NSMinX(source) + 40)) <= 1 &&
          fabs(NSMinY(placement.translationFrame) - (NSMinY(source) + 120)) <= 1,
          [NSString stringWithFormat:@"手动位置：等于原文锚点 + 偏移（实际 %.0f,%.0f；自动布局本来在 %.0f,%.0f）",
           placement.translationFrame.origin.x, placement.translationFrame.origin.y, autoFrame.origin.x, autoFrame.origin.y]);
    Check([placement.reason containsString:@"手动位置"], @"手动位置：给出可读原因");

    // 偏移把面板推出画面 → 夹回可见区域
    FYInlineLayoutRequest *extreme = [FYInlineLayoutRequest requestWithBlock:blocks.firstObject
                                                                 translation:autoPlacement.translation
                                                                 sourceFrame:source];
    extreme.manuallyPlaced = YES;
    extreme.manualOffset = CGSizeMake(-4000, 4000);
    FYInlinePlacement *clamped = [engine layoutRequests:@[extreme] viewport:viewport previous:nil].placements.firstObject;
    Check(CGRectGetMinX(clamped.translationFrame) >= NSMinX(viewport) &&
          CGRectGetMaxX(clamped.translationFrame) <= NSMaxX(viewport) &&
          CGRectGetMinY(clamped.translationFrame) >= NSMinY(viewport) &&
          CGRectGetMaxY(clamped.translationFrame) <= NSMaxY(viewport),
          @"手动位置：超出可见区域时夹回画面内");

    // 再次布局（带上一帧）：手动位置保持，其它块避开它
    NSArray<FYInlineTextLine *> *otherLines = @[
        Line(@"さらに、期間限定の特別なストーリーも公開予定です。", Box(.56, .30, .38, .034)),
        Line(@"詳細は公式サイトをご確認ください。", Box(.56, .265, .38, .034))
    ];
    NSArray<FYInlineTextBlock *> *otherBlocks = Group(otherLines);
    NSArray<FYInlineLayoutRequest *> *mixed = @[
        manual,
        [FYInlineLayoutRequest requestWithBlock:otherBlocks.firstObject translation:@"此外还会公开期间限定的特别剧情，详情请查看官方网站。" sourceFrame:otherBlocks.firstObject.boundingBox],
    ];
    // 把归一化框换算到显示区域
    FYInlineLayoutRequest *other = mixed[1];
    other.sourceFrame = CGRectMake(NSMinX(viewport) + other.sourceFrame.origin.x * NSWidth(viewport),
                                   NSMinY(viewport) + other.sourceFrame.origin.y * NSHeight(viewport),
                                   other.sourceFrame.size.width * NSWidth(viewport),
                                   other.sourceFrame.size.height * NSHeight(viewport));
    FYInlineLayoutResult *again = [engine layoutRequests:mixed viewport:viewport previous:manualResult];
    FYInlinePlacement *kept = again.placements.firstObject;
    Check(NSEqualRects(kept.translationFrame, placement.translationFrame), @"手动位置：OCR 刷新后不跳回自动位置");
    FYInlinePlacement *otherPlacement = again.placements.lastObject;
    if (otherPlacement.mode != FYInlineDisplayModeUnplaceable) {
        Check(!CGRectIntersectsRect(otherPlacement.translationFrame, kept.translationFrame),
              @"手动位置：其它块会避开手动摆放的卡");
    }
}

static void TestAppManualPositionPersistsAndDoesNotLeak(void) {
    AppDelegate *app = InlineFixtureApp(CGRectMake(0, 0, 1440, 900));
    NSString *source = @"新しい季節のイベントが始まります。\n期間中は限定の衣装も登場します。\nぜひお見逃しなく。";
    NSString *translation = @"新的季节活动即将开始。活动期间还会推出限定服装，请千万不要错过。";
    OCRTextItem *item = AppItem(source, CGRectMake(0.50, 0.30, 0.36, 0.10), InlineBlockKindLong);
    [app showInlineTranslations:@[translation] forItems:@[item]];
    Check(app.inlineLongCardPanels.count == 1, @"拖动：先生成一张卡");
    NSPanel *panel = app.inlineLongCardPanels.firstObject;

    // 模拟用户拖动（真实鼠标在本会话无法验证）：移动面板并走拖动结束的记录路径
    [panel setFrame:NSOffsetRect(panel.frame, -80, 60) display:NO];
    NSRect dragged = panel.frame;
    [app recordInlineManualOffsetForPanel:panel];
    Check(app.inlineManualOffsets.count == 1,
          [NSString stringWithFormat:@"拖动：记录了一条相对原文锚点的偏移（panelIdentifier=<%@> placementID=<%@> source=%.0f,%.0f frame=%.0f,%.0f）",
           panel.identifier, app.lastInlineLayoutResult.placements.firstObject.blockID,
           app.lastInlineLayoutResult.placements.firstObject.sourceFrame.origin.x,
           app.lastInlineLayoutResult.placements.firstObject.sourceFrame.origin.y,
           panel.frame.origin.x, panel.frame.origin.y]);

    // OCR 抖动后刷新：复用同一面板、位置不跳回
    OCRTextItem *jittered = AppItem(source, CGRectMake(0.502, 0.2985, 0.36, 0.10), InlineBlockKindLong);
    [app showInlineTranslations:@[translation] forItems:@[jittered]];
    Check(app.inlineLongCardPanels.count == 1 && app.inlineLongCardPanels.firstObject == panel,
          @"拖动：刷新复用同一面板");
    Check(fabs(NSMidX(panel.frame) - NSMidX(dragged)) <= 6 && fabs(NSMidY(panel.frame) - NSMidY(dragged)) <= 6,
          [NSString stringWithFormat:@"拖动：OCR 抖动刷新后不跳回（位移 %.1f,%.1f）",
           NSMidX(panel.frame) - NSMidX(dragged), NSMidY(panel.frame) - NSMidY(dragged)]);

    // 拖动过程中 OCR 循环不得把面板拽回去：置上拖动标记后这一帧先不重排
    NSRect duringDrag = panel.frame;
    app.inlineDraggingPanel = panel;
    [app showInlineTranslations:@[translation] forItems:@[jittered] placementRect:[app appKitFrameForWindowItem:app.windows.firstObject]];
    Check(NSEqualRects(panel.frame, duringDrag), @"拖动：拖动过程中不重排（不会被自动排版拉走）");
    app.inlineDraggingPanel = nil;

    // 窗口移动：偏移相对锚点，面板跟着窗口一起走
    // 落位区域来自目标窗口（含屏幕上方的原点补偿），所以“窗口移动”要从真实基线平移。
    NSRect baseViewport = [app appKitFrameForWindowItem:app.windows.firstObject];
    NSRect movedViewport = CGRectOffset(baseViewport, 120, 40);
    NSArray<OCRTextItem *> *movedItems = @[AppItem(source, item.boundingBox, InlineBlockKindLong)];
    NSRect beforeMove = panel.frame;
    [app showInlineTranslations:@[translation] forItems:movedItems placementRect:movedViewport];
    NSRect movedSource = [app appKitFrameForOCRItem:movedItems.firstObject inWindowFrame:movedViewport];
    Check(fabs((NSMinX(panel.frame) - NSMinX(beforeMove)) - 120) <= 8 &&
          fabs((NSMinY(panel.frame) - NSMinY(beforeMove)) - 40) <= 8,
          [NSString stringWithFormat:@"拖动：窗口移动后贴译跟着窗口一起走（实际位移 %.0f,%.0f，期望 120,40；原文移动后 %.0f,%.0f）",
           NSMinX(panel.frame) - NSMinX(beforeMove), NSMinY(panel.frame) - NSMinY(beforeMove),
           NSMinX(movedSource), NSMinY(movedSource)]);

    // 换页：完全不同的文本块，不得继承这个偏移
    OCRTextItem *otherItem = AppItem(@"全く別のページの見出しです。", CGRectMake(0.10, 0.62, 0.30, 0.035), InlineBlockKindLong);
    [app showInlineTranslations:@[@"完全不同的另一页标题。"] forItems:@[otherItem]];
    Check(app.inlineLongCardPanels.count == 1, @"拖动：换页后仍是单张卡");
    NSRect otherFrame = app.inlineLongCardPanels.firstObject.frame;
    Check(!NSEqualRects(otherFrame, panel.frame), @"拖动：换页后不会沿用旧块的位置");
    Check([app inlineManualOffsetForText:otherItem.text normalizedBox:otherItem.boundingBox] == nil,
          @"拖动：换页后的新块查不到旧偏移（不会继承）");

    // 缩放后仍在可见区域内
    NSRect smaller = CGRectMake(0, 0, 900, 600);
    [app showInlineTranslations:@[@"完全不同的另一页标题。"] forItems:@[otherItem] placementRect:smaller];
    for (NSPanel *any in app.inlineLongCardPanels) {
        Check(NSMinX(any.frame) >= NSMinX(smaller) - 1 && NSMaxX(any.frame) <= NSMaxX(smaller) + 1 &&
              NSMinY(any.frame) >= NSMinY(smaller) - 1 && NSMaxY(any.frame) <= NSMaxY(smaller) + 1,
              @"拖动：缩放到更小的可见区域后贴译仍在画面内");
    }
    [app clearInlineTranslationPanels];
    Check(app.inlineManualOffsets.count == 0, @"拖动：清理面板时手动位置一起清掉");
}

static void TestAppOptionDragModeAndCardHitZones(void) {
    AppDelegate *app = InlineFixtureApp(CGRectMake(0, 0, 1440, 900));
    [app showInlineTranslations:@[@"公演日程"] forItems:@[AppItem(@"公演日程", CGRectMake(0.08, 0.76, 0.15, 0.028), InlineBlockKindShort)]];
    Check(app.inlineTranslationPanels.count == 1, @"Option 拖动：先有一个短贴片");
    NSPanel *panel = app.inlineTranslationPanels.firstObject;
    Check(panel.ignoresMouseEvents, @"Option 拖动：平时保持鼠标穿透");
    Check([panel.contentView isKindOfClass:FYInlinePatchView.class], @"Option 拖动：短贴片内容视图支持拖动");

    [app applyInlineDragMode:YES];
    Check(!panel.ignoresMouseEvents, @"Option 拖动：按住 Option 后可交互");
    FYInlinePatchView *patch = (FYInlinePatchView *)panel.contentView;
    Check(patch.dragEnabled && patch.showsDragHint, @"Option 拖动：进入可拖动状态");
    Check(patch.layer.borderWidth > 2.0, @"Option 拖动：给出可拖动反馈（边框加粗）");
    Check(fabs(PanelFillColor(panel).alphaComponent - 0.58) < 0.02, @"Option 拖动：反馈不改变背景不透明度");

    [app applyInlineDragMode:NO];
    Check(panel.ignoresMouseEvents && !patch.dragEnabled && patch.layer.borderWidth < 2.0,
          @"Option 拖动：松开后恢复穿透与普通外观");
    [app clearInlineTranslationPanels];
    Check(app.inlineModifierTimer == nil, @"Option 拖动：面板清理后监听定时器停止");

    // 长卡：标题栏拖动 / 正文点击，且拖动结束不误触学习
    OCRTextItem *item = AppItem(@"新しい季節のイベントが始まります。\n期間中は限定の衣装も登場します。\nぜひお見逃しなく。",
                                CGRectMake(0.50, 0.30, 0.36, 0.10), InlineBlockKindLong);
    NSPanel *card = [app inlineLongPanelForTranslation:@"新的季节活动即将开始，请千万不要错过。" item:item frame:NSMakeRect(200, 300, 420, 200)];
    FYInlineLongCardView *cardView = (FYInlineLongCardView *)card.contentView;
    Check([cardView isKindOfClass:FYInlineLongCardView.class], @"长卡：内容视图是卡片视图");
    Check(cardView.titleBarHeight > 30 && [cardView pointIsInTitleBar:NSMakePoint(20, 10)],
          @"长卡：顶部是标题栏拖动区");
    Check(![cardView pointIsInTitleBar:NSMakePoint(20, cardView.titleBarHeight + 40)],
          @"长卡：正文区域不算标题栏");
    cardView.windowDragEnabled = NO;   // 测试里不进入真实窗口拖动循环
    __block NSInteger clicks = 0, drags = 0;
    cardView.onClick = ^{ clicks += 1; };
    cardView.onDragEnded = ^{ drags += 1; };
    CGFloat height = NSHeight(cardView.bounds);
    NSEvent *(^makeEvent)(NSEventType, NSPoint) = ^NSEvent *(NSEventType type, NSPoint point) {
        return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0
                              windowNumber:card.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    };
    // ① 标题栏按下 → 只算拖动，不打开学习
    [cardView mouseDown:makeEvent(NSEventTypeLeftMouseDown, NSMakePoint(30, height - 12))];
    Check(drags == 1 && clicks == 0, @"长卡：标题栏拖动不触发学习");
    // ② 正文按下 → 抬起（没有位移）算点击
    [cardView mouseDown:makeEvent(NSEventTypeLeftMouseDown, NSMakePoint(30, 40))];
    [cardView mouseUp:makeEvent(NSEventTypeLeftMouseUp, NSMakePoint(30, 40))];
    Check(clicks == 1, @"长卡：正文点击仍然打开学习");
    // ③ 正文按下 → 拖动超过阈值 → 抬起不算点击
    [cardView mouseDown:makeEvent(NSEventTypeLeftMouseDown, NSMakePoint(30, 40))];
    [cardView mouseDragged:makeEvent(NSEventTypeLeftMouseDragged, NSMakePoint(80, 90))];
    [cardView mouseUp:makeEvent(NSEventTypeLeftMouseUp, NSMakePoint(80, 90))];
    Check(clicks == 1, @"长卡：正文拖动结束不误触学习");
    [card close];
    [app clearInlineTranslationPanels];
}

#pragma mark - F. 复验发现的两个缺陷（稳定身份 + 集中查看入口）

/// 复验 P2：布局匹配出的稳定身份必须传到选中判定 / 学习快照，OCR 抖动 1px 不能丢选中态。
static void TestStableIdentityReachesSelectionAndSnapshot(void) {
    AppDelegate *app = InlineFixtureApp(CGRectMake(0, 0, 1200, 800));
    NSString *source = @"新しい季節のイベントが始まります。\n期間中は限定の衣装も登場します。\nぜひお見逃しなく。";
    NSString *translation = @"新的季节活动即将开始。活动期间还会推出限定服装，请千万不要错过。";
    OCRTextItem *item = AppItem(source, CGRectMake(0.20, 0.30, 0.45, 0.14), InlineBlockKindLong);

    // 第一帧：面板身份 = 本帧原始身份
    [app showInlineTranslations:@[translation] forItems:@[item]];
    Check(app.inlineLongCardPanels.count == 1, @"稳定身份：先生成一张长卡");
    NSPanel *panel = app.inlineLongCardPanels.firstObject;
    FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
    Check([card.stableBlockID isEqualToString:panel.identifier],
          @"稳定身份：面板的块身份与卡片保存的稳定身份一致");
    Check([card.stableBlockID isEqualToString:[app inlineBlockIdentityForItem:item]],
          @"稳定身份：首帧稳定身份就是本帧身份");

    // 模拟点击卡片进入学习：快照必须带稳定身份
    app.inlineBlockSnapshot = [app inlineSnapshotForItem:item translation:translation stableBlockID:card.stableBlockID];
    Check([app inlineBlockIsSelectedForItem:item], @"稳定身份：点击后该块是选中态");

    // 抖动 0.001 归一化坐标（1200×800 下约 1px 多）后刷新：面板复用、选中态不丢
    OCRTextItem *jittered = AppItem(source, CGRectMake(0.201, 0.299, 0.45, 0.14), InlineBlockKindLong);
    [app showInlineTranslations:@[translation] forItems:@[jittered]];
    Check(app.inlineLongCardPanels.firstObject == panel, @"稳定身份：抖动后复用同一面板");
    Check([app inlineBlockIsSelectedForItem:jittered],
          [NSString stringWithFormat:@"稳定身份：OCR 抖动约 1px 后选中态不丢（快照 %@ / 面板 %@ / 本帧 %@）",
           app.inlineBlockSnapshot.blockID, panel.identifier, [app inlineBlockIdentityForItem:jittered]]);
    Check([app.inlineBlockSnapshot.blockID isEqualToString:panel.identifier],
          @"稳定身份：学习快照的块身份就是布局稳定身份");
    Check([(FYInlineLongCardView *)panel.contentView showsSelectedBadge],
          @"稳定身份：面板仍显示「已选中」标识");
    [app clearInlineTranslationPanels];
}

/// 复验 P1：暂不可放置的译文必须有真正可读的集中查看入口，不能只写两个从未创建的旧控件、
/// 也不能只保留前三条。
static void TestUnplaceableListedInCentralViewer(void) {
    AppDelegate *app = InlineFixtureAppWithOptions(CGRectMake(0, 0, 340, 120), YES);
    NSMutableArray<OCRTextItem *> *items = [NSMutableArray array];
    NSMutableArray<NSString *> *translations = [NSMutableArray array];
    for (NSUInteger index = 0; index < 5; index++) {
        [items addObject:AppItem([NSString stringWithFormat:@"重なった見出し%lu", (unsigned long)index],
                                 CGRectMake(0.02, 0.04, 0.95, 0.88), InlineBlockKindShort)];
        [translations addObject:[NSString stringWithFormat:@"第 %lu 条暂不可放置的完整译文", (unsigned long)(index + 1)]];
    }
    [app showInlineTranslations:translations forItems:items];
    Check(app.lastInlineUnplaceableCount == 5,
          [NSString stringWithFormat:@"集中查看：五块都判定为暂不可放置（实际 %lu）", (unsigned long)app.lastInlineUnplaceableCount]);
    Check(app.inlineTranslationListCard != nil, @"集中查看：实时页里有界面译文列表");
    Check(!app.inlineTranslationListCard.hidden, @"集中查看：有未放置译文时列表可见");
    Check(app.inlineTranslationListStack.arrangedSubviews.count == 5,
          [NSString stringWithFormat:@"集中查看：五条全部列出、不截断（实际 %lu）", (unsigned long)app.inlineTranslationListStack.arrangedSubviews.count]);
    Check(app.inlineTranslationListSnapshots.count == 5, @"集中查看：每条都保留块身份用于跳转");
    Check([app.inlineTranslationListCount.stringValue containsString:@"5"], @"集中查看：标题给出条数");
    FYInlineBlockSnapshot *last = app.inlineTranslationListSnapshots.lastObject;
    Check([last.translation isEqualToString:translations.lastObject],
          @"集中查看：最后一条的完整译文也在（不是只留前三条）");
    Check(last.sourceText.length > 0 && last.blockID.length > 0,
          @"集中查看：每条都保留原文与块身份");
    Check([last.sourceText containsString:@"重なった見出し4"], @"集中查看：最后一条对应的是第五个块");

    // 列表里的按钮能打开该块的原文与语法（用不可变快照，不用刷新后的数组下标）
    BOOL opened = (last.blockID.length > 0);
    Check(opened, @"集中查看：可点击进入该块的原文与语法");

    // 视觉证据：实时页上的集中查看列表
    if (app.mainWindow) {
        NSView *view = app.mainWindow.contentView;
        // 把「界面译文」卡片滚进可见区域再截图，作为集中查看入口的证据。
        [view layoutSubtreeIfNeeded];
        [app.inlineTranslationListCard scrollRectToVisible:app.inlineTranslationListCard.bounds];
        [view displayIfNeeded];
        NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
        NSString *out = [kInlineTestOutputDirectory stringByAppendingPathComponent:@"inline-translation-list.png"];
        Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:out atomically:YES],
              @"集中查看：生成实时页列表截图");
    }

    // 清理后面板与列表一起收起
    [app clearInlineTranslationPanels];
    Check(app.inlineTranslationListCard.hidden && app.inlineTranslationListStack.arrangedSubviews.count == 0,
          @"集中查看：没有未放置内容时列表收起");
}

#pragma mark - main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *outputDirectory = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : NSTemporaryDirectory();
        [[NSFileManager defaultManager] createDirectoryAtPath:outputDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
        kInlineTestOutputDirectory = outputDirectory;

        NSLog(@"== 第一步：人工框（分组） ==");
        TestGroupingNewsPage();
        TestGroupingMailPage();
        TestGroupingDenseMenu();
        TestGroupingTwoColumns();
        TestGroupingTitleVersusBody();
        TestGroupingBottomPartial();
        TestDedup();

        NSLog(@"== 第一步：人工框（布局） ==");
        TestLayoutNewsPage();
        TestLayoutMailPageColumnBinding();
        TestLayoutLongCardReadability();
        TestLayoutCardHugsContent();
        TestLayoutCompactEntryAndUnplaceable();
        TestLayoutStabilityAndResize();
        TestLayoutJitterDoesNotMatchDifferentText();

        NSLog(@"== 第二步：真实 OCR 输出 ==");
        TestRealOCRCaptureFrame(outputDirectory);
        TestRealOCROverlayDoubleText(outputDirectory);
        TestRealOCRAppScreenshot(outputDirectory);

        NSLog(@"== 接入运行界面：端到端行为 ==");
        TestAppCompactEntryOpensFullCard();
        TestAppScrollPositionSemantics();
        TestAppJitterKeepsPanelIdentity();
        TestAppUnplaceableIsReportedNotDropped();

        NSLog(@"== 透明度跟随设置 + 拖动位置 ==");
        TestAppOpacityFollowsSetting();
        TestLayoutManualOffset();
        TestAppManualPositionPersistsAndDoesNotLeak();
        TestAppOptionDragModeAndCardHitZones();

        NSLog(@"== 复验缺陷回归 ==");
        TestStableIdentityReachesSelectionAndSnapshot();
        TestUnplaceableListedInCentralViewer();

        if (gFailures == 0) {
            NSLog(@"自适应贴译布局检查通过（第一步人工框 + 第二步真实 OCR，见上方分别的记录）");
            return 0;
        }
        NSLog(@"自适应贴译布局检查失败：%lu 项", (unsigned long)gFailures);
        return 1;
    }
}
