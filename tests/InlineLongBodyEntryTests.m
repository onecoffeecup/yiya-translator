// 长正文「放不下就从画面消失」专项验证（2026-10-06 晚）
//
// 现场症状（用户附图 + /tmp/fuyi-diag.log 14:27:00 / 14:27:34）：
//   「◆桜井琉夏の好み◆」标题有译文，下面五行喜好正文完全没有出现，
//   两条日志都是 UNPLACEABLE <校内でスリリングなことば…>。
//
// 本轮验证的目标：
//   · 紧凑入口必须**按内容测量**（标题文字 + 字体 + 内边距），不继承长卡宽度；
//   · 入口优先放进**它所属正文自身**的范围（顶/底/中），再做近邻回退；
//   · 注定只能降级的长正文要排在短贴片之前，避免小贴片把它附近的空地占满；
//   · 点击入口能读到完整译文（卡内滚动、保留原文与稳定身份、保留学习入口）；
//   · 真的无处可放时，集中列表仍保留全部内容，状态区给出条数；
//   · 诊断能说明是哪一个候选、被哪一块挡了、交叠多厚，以及重复 OCR 框造成的假冲突。
//
// 夹具全部离线合成；正文取自现场日志里的 OCR 文本片段（不是把贴译覆盖层 OCR 当原文）。

#import "LearningAppTestSupport.h"
#import "FYInlineLayout.h"

static NSUInteger gChecks = 0;
static NSUInteger gFailures = 0;
static NSString *gOutputDirectory = nil;

static void Check(BOOL ok, NSString *message) {
    if (ok) {
        gChecks += 1;
        NSLog(@"PASS %@", message);
    } else {
        gFailures += 1;
        NSLog(@"FAIL %@", message);
    }
}

static BOOL DisplaysFullTranslation(FYInlinePlacement *placement) {
    return placement && (placement.mode == FYInlineDisplayModeShortLabel ||
                         placement.mode == FYInlineDisplayModeFullCard ||
                         placement.mode == FYInlineDisplayModeScrollingCard);
}

#pragma mark - 合成场景

static FYInlineTextLine *Line(NSString *text, CGRect box) {
    return [FYInlineTextLine lineWithText:text rect:box confidence:0.92 sourceIndex:0];
}

static NSArray<FYInlineTextBlock *> *Group(NSArray<FYInlineTextLine *> *lines) {
    return [[FYInlineGrouper defaultGrouper] blocksFromLines:lines];
}

static FYInlineTextBlock *EntryBlock(NSString *text, CGRect box, FYInlineBlockKind kind) {
    FYInlineTextBlock *block = [FYInlineTextBlock new];
    block.blockID = [FYInlineBlockMatcher blockIDForText:text lineBoxes:@[[NSValue valueWithRect:box]]];
    block.text = text;
    block.lineTexts = @[text];
    block.lineBoxes = @[[NSValue valueWithRect:box]];
    block.lineConfidences = @[@0.9];
    block.sourceIndices = @[@0];
    block.boundingBox = box;
    block.kind = kind;
    block.groupingConfidence = 1.0;
    block.readingOrder = 0;
    return block;
}


// 与 LiveCaptionTranslator 的 appKitFrameForOCRItem:inWindowFrame: 同一套换算：
// 归一化框（原点左下）→ 显示区域坐标，两者都是 y 向上，所以不需要翻转。
static CGRect ScreenFrame(CGRect viewport, CGRect box) {
    return CGRectMake(NSMinX(viewport) + box.origin.x * NSWidth(viewport),
                      NSMinY(viewport) + box.origin.y * NSHeight(viewport),
                      box.size.width * NSWidth(viewport),
                      box.size.height * NSHeight(viewport));
}

// 现场映射出来的画面区域（14:27:00 CAPTURE-AUTO-LOCATE：rect={{457.2,455.9},{1017.2,571.7}}）。
static CGRect ProfileViewport(void) { return CGRectMake(457, 456, 1017, 572); }

/// 角色资料页：标题、左右两栏菜单/属性、若干短贴片，以及标题下方五行喜好正文。
/// 正文的框取自现场比例（左栏、标题正下方），文本取自日志里的 OCR 片段。
static NSArray<FYInlineTextLine *> *ProfileSceneLines(void) {
    return @[
        Line(@"CHARRACTER", CGRectMake(0.043, 0.864, 0.392, 0.092)),
        Line(@"桜井 琉夏", CGRectMake(0.775, 0.904, 0.130, 0.055)),
        Line(@"RUKA SAKURAI", CGRectMake(0.775, 0.845, 0.165, 0.030)),
        Line(@"Birthday", CGRectMake(0.700, 0.810, 0.104, 0.047)),
        Line(@"Horoscope", CGRectMake(0.700, 0.715, 0.132, 0.040)),
        Line(@"かに座", CGRectMake(0.897, 0.683, 0.080, 0.044)),
        Line(@"• 型", CGRectMake(0.918, 0.580, 0.058, 0.050)),
        Line(@"電話", CGRectMake(0.515, 0.456, 0.049, 0.047)),
        Line(@"みよのメモ", CGRectMake(0.180, 0.426, 0.098, 0.038)),
        Line(@"身長", CGRectMake(0.513, 0.388, 0.050, 0.047)),
        Line(@"◆桜井琉夏の好み◆", CGRectMake(0.178, 0.361, 0.180, 0.038)),
        Line(@"体重", CGRectMake(0.513, 0.317, 0.050, 0.053)),
        Line(@"バイト", CGRectMake(0.515, 0.263, 0.070, 0.041)),
        Line(@"花屋アンネリー", CGRectMake(0.608, 0.263, 0.168, 0.041)),
        Line(@"クラブ", CGRectMake(0.517, 0.201, 0.070, 0.041)),
        Line(@"帰宅部\n桜井琥一の弟。\nスリルは彼の活力。", CGRectMake(0.608, 0.079, 0.204, 0.164)),
        Line(@"備考", CGRectMake(0.515, 0.130, 0.048, 0.047)),
        Line(@"プロフィールを見る", CGRectMake(0.010, 0.003, 0.182, 0.036)),
        // 五行喜好正文（标题正下方，左栏）
        Line(@"校内でスリリングなことばかりしている彼は、", CGRectMake(0.178, 0.322, 0.215, 0.026)),
        Line(@"アクティブで好奇心旺盛。退屈を嫌い、", CGRectMake(0.178, 0.296, 0.200, 0.026)),
        Line(@"いつも何か新しいことに挑戦している。", CGRectMake(0.178, 0.270, 0.205, 0.026)),
        Line(@"スリルを求めて行動するのが好きで、", CGRectMake(0.178, 0.244, 0.195, 0.026)),
        Line(@"じっとしているのは苦手なのだ。", CGRectMake(0.178, 0.218, 0.170, 0.026))
    ];
}

static NSString *const kBodyNeedle = @"校内でスリリング";
static NSString *const kBodyTranslation = @"在校内总做些刺激的事，他活泼又好奇心旺盛。讨厌无聊，总是挑战新事物。喜欢追求惊险刺激，静不下来。";

static FYInlineTextBlock *BodyBlock(NSArray<FYInlineTextBlock *> *blocks) {
    for (FYInlineTextBlock *block in blocks) {
        if ([block.text containsString:kBodyNeedle]) { return block; }
    }
    return nil;
}

static NSArray<FYInlineLayoutRequest *> *RequestsForBlocks(NSArray<FYInlineTextBlock *> *blocks,
                                                           CGRect viewport,
                                                           NSDictionary<NSString *, NSString *> *translations) {
    NSMutableArray<FYInlineLayoutRequest *> *requests = [NSMutableArray array];
    for (FYInlineTextBlock *block in blocks) {
        NSString *translation = nil;
        for (NSString *key in translations) {
            if ([block.text containsString:key]) { translation = translations[key]; break; }
        }
        if (translation.length == 0) {
            // 其它块给一个短译文：它们只是"周围拥挤的元素"，不是本轮的验证目标。
            translation = @"菜单译文";
        }
        [requests addObject:[FYInlineLayoutRequest requestWithBlock:block
                                                        translation:translation
                                                        sourceFrame:ScreenFrame(viewport, block.boundingBox)]];
    }
    return requests;
}

static FYInlineLayoutResult *RunScene(FYInlineLayoutEngine *engine,
                                      NSArray<FYInlineTextLine *> *lines,
                                      CGRect viewport,
                                      NSArray<FYInlineLayoutRequest *> **outRequests) {
    NSArray<FYInlineTextBlock *> *blocks = Group(lines);
    NSMutableDictionary<NSString *, NSString *> *translations = [NSMutableDictionary dictionary];
    translations[kBodyNeedle] = kBodyTranslation;
    NSArray<FYInlineLayoutRequest *> *requests = RequestsForBlocks(blocks, viewport, translations);
    if (outRequests) { *outRequests = requests; }
    return [engine layoutRequests:requests viewport:viewport previous:nil];
}

static BOOL OverlapsAnyOtherSource(FYInlinePlacement *placement, NSArray<FYInlineLayoutRequest *> *requests) {
    for (FYInlineLayoutRequest *request in requests) {
        if ([request.block.blockID isEqualToString:placement.sourceBlockID]) { continue; }
        CGRect hit = CGRectIntersection(placement.translationFrame, request.sourceFrame);
        CGFloat depth = CGRectIsNull(hit) || CGRectIsEmpty(hit) ? 0 : MIN(hit.size.width, hit.size.height);
        if (depth > 10.0 + 0.001) { return YES; }
    }
    return NO;
}

static CGFloat MeasuredEntryTextWidth(FYInlineLayoutEngine *engine) {
    NSString *title = engine.compactEntryTitle;
    NSFont *font = [engine compactEntryFont];
    NSRect natural = [title boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
                                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                      attributes:@{NSFontAttributeName: font}];
    return ceil(NSWidth(natural));
}

#pragma mark - A. 引擎：现场场景

static void TestProfileSceneGetsEntry(void) {
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    CGRect viewport = ProfileViewport();
    NSArray<FYInlineLayoutRequest *> *requests = nil;
    FYInlineLayoutResult *result = RunScene(engine, ProfileSceneLines(), viewport, &requests);
    FYInlineTextBlock *body = nil;
    FYInlinePlacement *placement = nil;
    for (FYInlinePlacement *candidate in result.placements) {
        if ([candidate.block.text containsString:kBodyNeedle]) { placement = candidate; body = candidate.block; break; }
    }
    Check(body != nil && body.kind == FYInlineBlockKindLong, @"现场场景：五行喜好正文被分成一个长正文块");
    Check(placement != nil, @"现场场景：正文块有排版结果（不是静默丢弃）");
    if (!placement) { return; }
    Check(placement.mode == FYInlineDisplayModeCompactEntry || placement.mode == FYInlineDisplayModeFullCard ||
          placement.mode == FYInlineDisplayModeScrollingCard,
          [NSString stringWithFormat:@"现场场景：正文块可显示（mode=%ld，原因：%@）", (long)placement.mode, placement.reason]);
    Check(!OverlapsAnyOtherSource(placement, requests), @"现场场景：正文译文没有盖住其它原文");
    if (placement.mode != FYInlineDisplayModeCompactEntry) { return; }

    // 尺寸：与引擎按内容测量的结果一致，且宽度与长卡宽度无关。
    CGSize measured = [engine foldedEntrySizeForViewport:viewport title:placement.entryTitle hint:placement.entryHint];
    Check(fabs(NSWidth(placement.translationFrame) - measured.width) < 1.5 &&
          fabs(NSHeight(placement.translationFrame) - measured.height) < 1.5,
          [NSString stringWithFormat:@"紧凑入口尺寸＝按内容测量的 %.0f×%.0f（实际 %.0f×%.0f）",
           measured.width, measured.height, NSWidth(placement.translationFrame), NSHeight(placement.translationFrame)]);
    Check(NSWidth(placement.translationFrame) >= MeasuredEntryTextWidth(engine) + 14,
          @"紧凑入口宽度足够放下「查看译文」文字（不会被截断）");
    Check(NSHeight(placement.translationFrame) >= 30, @"紧凑入口有可点击高度（不是细条）");
    Check(placement.longCardSize.width > 0 && NSWidth(placement.translationFrame) < placement.longCardSize.width * 0.75,
          [NSString stringWithFormat:@"入口宽度独立于长卡宽度（卡 %.0f，入口 %.0f）",
           placement.longCardSize.width, NSWidth(placement.translationFrame)]);

    // 位置：优先落在正文自身范围内；不遮挡别的原文块、不漂到别的条目。
    CGRect own = placement.sourceFrame;
    CGRect hit = CGRectIntersection(placement.translationFrame, own);
    CGFloat ownOverlap = (hit.size.width * hit.size.height) / MAX((CGFloat)1, NSWidth(placement.translationFrame) * NSHeight(placement.translationFrame));
    CGFloat entryDrift = MAX(0, MAX(NSMinY(placement.sourceFrame) - NSMaxY(placement.translationFrame),
                                   NSMinY(placement.translationFrame) - NSMaxY(placement.sourceFrame)));
    CGFloat driftLimit = MAX(NSHeight(placement.sourceFrame), NSHeight(placement.translationFrame)) + 8;
    Check(ownOverlap >= 0.35 || entryDrift <= driftLimit,
          [NSString stringWithFormat:@"入口落在正文自身范围内或紧邻位置（自身覆盖 %.2f，偏移 %.0f/%.0f）",
           ownOverlap, entryDrift, driftLimit]);
    Check(!OverlapsAnyOtherSource(placement, requests), @"入口没有遮挡任何其它原文块");
    Check(NSMinX(placement.translationFrame) >= NSMinX(viewport) && NSMaxX(placement.translationFrame) <= NSMaxX(viewport) &&
          NSMinY(placement.translationFrame) >= NSMinY(viewport) && NSMaxY(placement.translationFrame) <= NSMaxY(viewport),
          @"入口完整落在可见区域内");

    // 诊断：能指出是哪些候选、被谁挡住。
    Check(placement.rejectedCandidates.count > 0, @"诊断记录了被拒绝的候选");
    BOOL namesConflict = NO;
    for (NSString *line in placement.rejectedCandidates) {
        if ([line containsString:@"遮挡"] || [line containsString:@"超出可见区域"] || [line containsString:@"冲突"]) { namesConflict = YES; }
    }
    Check(namesConflict, @"诊断给出具体拒绝原因（遮挡哪一个块 / 超出可见区域 / 与面板冲突）");
}

static void TestEntryWidthIndependentOfCardWidth(void) {
    CGRect viewport = ProfileViewport();
    FYInlineLayoutEngine *narrow = [FYInlineLayoutEngine defaultEngine];
    // 将上限设在原文列宽以下；局部避让成功后，自适应候选可能在两种设置下
    // 都选中相同的原文宽度，无法验证入口尺寸是否独立。
    narrow.cardMaxWidth = 200;
    narrow.cardWidthFraction = 0.19;
    FYInlineLayoutEngine *wide = [FYInlineLayoutEngine defaultEngine];
    wide.cardMaxWidth = 560;
    wide.cardWidthFraction = 0.62;
    FYInlineLayoutResult *narrowResult = RunScene(narrow, ProfileSceneLines(), viewport, NULL);
    FYInlineLayoutResult *wideResult = RunScene(wide, ProfileSceneLines(), viewport, NULL);
    FYInlinePlacement *narrowPlacement = nil, *widePlacement = nil;
    for (FYInlinePlacement *placement in narrowResult.placements) {
        if ([placement.block.text containsString:kBodyNeedle]) { narrowPlacement = placement; }
    }
    for (FYInlinePlacement *placement in wideResult.placements) {
        if ([placement.block.text containsString:kBodyNeedle]) { widePlacement = placement; }
    }
    Check(narrowPlacement != nil && widePlacement != nil, @"两种卡宽设置下正文块都有排版结果");
    if (!narrowPlacement || !widePlacement) { return; }
    if (narrowPlacement.mode == FYInlineDisplayModeCompactEntry &&
        widePlacement.mode == FYInlineDisplayModeCompactEntry) {
        Check(fabs(NSWidth(narrowPlacement.translationFrame) - NSWidth(widePlacement.translationFrame)) < 0.5,
              [NSString stringWithFormat:@"紧凑入口宽度不随长卡宽度变化（%.0f vs %.0f）",
               NSWidth(narrowPlacement.translationFrame), NSWidth(widePlacement.translationFrame)]);
    }
    Check(narrowPlacement.longCardSize.width != widePlacement.longCardSize.width,
          @"对照成立：两次的长卡宽度确实不同");
}

static void TestCrowdedSceneKeepsEntry(void) {
    // 更拥挤：在正文四周再塞两行菜单，让"下方/上方/左右"全部被占。
    CGRect viewport = ProfileViewport();
    NSMutableArray<FYInlineTextLine *> *lines = [ProfileSceneLines() mutableCopy];
    [lines addObject:Line(@"カレーライスが大好物", CGRectMake(0.190, 0.196, 0.190, 0.024))];
    [lines addObject:Line(@"甘いものにも目がない", CGRectMake(0.190, 0.172, 0.185, 0.024))];
    [lines addObject:Line(@"休日はドライブ", CGRectMake(0.430, 0.218, 0.160, 0.026))];
    [lines addObject:Line(@"海が好き", CGRectMake(0.430, 0.244, 0.120, 0.026))];
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    NSArray<FYInlineLayoutRequest *> *requests = nil;
    FYInlineLayoutResult *result = RunScene(engine, lines, viewport, &requests);
    FYInlinePlacement *placement = nil;
    for (FYInlinePlacement *candidate in result.placements) {
        if ([candidate.block.text containsString:kBodyNeedle]) { placement = candidate; break; }
    }
    Check(placement != nil, @"拥挤页面：正文块有排版结果");
    if (!placement) { return; }
    Check(placement.mode == FYInlineDisplayModeCompactEntry || placement.mode == FYInlineDisplayModeFullCard,
          [NSString stringWithFormat:@"拥挤页面：正文有可读长卡或「查看译文」入口（mode=%ld，原因：%@）", (long)placement.mode, placement.reason]);
    Check(!OverlapsAnyOtherSource(placement, requests), @"拥挤页面：入口没有遮挡别的原文块");
    // 不许漂到别的条目附近：与自己的原文垂直距离必须在布局器的位移上界内。
    CGFloat drift = MAX(0, MAX(NSMinY(placement.sourceFrame) - NSMaxY(placement.translationFrame),
                               NSMinY(placement.translationFrame) - NSMaxY(placement.sourceFrame)));
    CGFloat driftBound = MAX(NSHeight(placement.sourceFrame), NSHeight(placement.translationFrame)) + 8;
    Check(drift <= driftBound,
          [NSString stringWithFormat:@"拥挤页面：入口没有漂到别的条目附近（偏移 %.0f ≤ %.0f）", drift, driftBound]);
}

/// 现场症状复现夹具：按日志里那张角色资料页的拥挤程度构造 ——
/// 正文正下方压着短条目、右侧紧贴属性行与另一个短标题。
/// 旧实现在这里会把这块正文标成 Unplaceable（14:27:00 / 14:27:34 两条日志），
/// 修好后它应该拿到一个按内容测量的「查看译文」入口，并且入口落在正文自己范围内。
static void TestFieldLikeSceneReproduction(void) {
    CGRect viewport = ProfileViewport();
    NSMutableArray<FYInlineTextLine *> *lines = [@[
        Line(@"CHARRACTER", CGRectMake(0.043, 0.864, 0.392, 0.092)),
        Line(@"桜井 琉夏", CGRectMake(0.775, 0.904, 0.130, 0.055)),
        Line(@"RUKA SAKURAI", CGRectMake(0.775, 0.845, 0.165, 0.030)),
        Line(@"Birthday", CGRectMake(0.700, 0.810, 0.104, 0.047)),
        Line(@"Horoscope", CGRectMake(0.700, 0.715, 0.132, 0.040)),
        Line(@"かに座", CGRectMake(0.897, 0.683, 0.080, 0.044)),
        Line(@"• 型", CGRectMake(0.918, 0.580, 0.058, 0.050)),
        Line(@"電話", CGRectMake(0.515, 0.456, 0.049, 0.047)),
        Line(@"みよのメモ", CGRectMake(0.180, 0.426, 0.098, 0.038)),
        Line(@"身長", CGRectMake(0.513, 0.388, 0.050, 0.047)),
        Line(@"◆桜井琉夏の好み◆", CGRectMake(0.178, 0.361, 0.180, 0.038)),
        Line(@"体重", CGRectMake(0.513, 0.317, 0.050, 0.053)),
        Line(@"バイト", CGRectMake(0.515, 0.263, 0.070, 0.041)),
        Line(@"花屋アンネリー", CGRectMake(0.608, 0.263, 0.168, 0.041)),
        Line(@"クラブ", CGRectMake(0.517, 0.201, 0.070, 0.041)),
        Line(@"帰宅部\n桜井琥一の弟。\nスリルは彼の活力。", CGRectMake(0.608, 0.079, 0.204, 0.164)),
        Line(@"備考", CGRectMake(0.515, 0.130, 0.048, 0.047)),
        Line(@"プロフィールを見る", CGRectMake(0.010, 0.003, 0.182, 0.036)),
        // 正文（比左栏略宽，顶到右栏属性行的高度；正下方再压一行短条目）
        Line(@"校内でスリリングなことばかりしている彼は、", CGRectMake(0.178, 0.330, 0.340, 0.026)),
        Line(@"アクティブで好奇心旺盛。退屈を嫌い、", CGRectMake(0.178, 0.304, 0.335, 0.026)),
        Line(@"いつも何か新しいことに挑戦している。", CGRectMake(0.178, 0.278, 0.338, 0.026)),
        Line(@"スリルを求めて行動するのが好きで、", CGRectMake(0.178, 0.252, 0.330, 0.026)),
        Line(@"じっとしているのは苦手なのだ。", CGRectMake(0.178, 0.226, 0.300, 0.026)),
        Line(@"カレーライスが大好物", CGRectMake(0.190, 0.196, 0.190, 0.024)),
        Line(@"右側の短い見出し", CGRectMake(0.530, 0.310, 0.100, 0.035))
    ] mutableCopy];
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    NSArray<FYInlineLayoutRequest *> *requests = nil;
    FYInlineLayoutResult *result = RunScene(engine, lines, viewport, &requests);
    FYInlinePlacement *placement = nil;
    for (FYInlinePlacement *candidate in result.placements) {
        if ([candidate.block.text containsString:kBodyNeedle]) { placement = candidate; break; }
    }
    Check(placement != nil, @"现场复现：正文块有排版结果");
    if (!placement) { return; }
    Check(placement.mode != FYInlineDisplayModeUnplaceable,
          [NSString stringWithFormat:@"现场复现：正文不再「暂不可放置」（mode=%ld，原因：%@）", (long)placement.mode, placement.reason]);
    Check(placement.mode == FYInlineDisplayModeCompactEntry, @"现场复现：正文给出「查看译文」入口");
    if (placement.mode != FYInlineDisplayModeCompactEntry) { return; }
    CGSize measured = [engine foldedEntrySizeForViewport:viewport title:placement.entryTitle hint:placement.entryHint];
    Check(fabs(NSWidth(placement.translationFrame) - measured.width) < 1.5,
          [NSString stringWithFormat:@"现场复现：入口按内容测量（%.0f，长卡 %.0f 宽）",
           NSWidth(placement.translationFrame), placement.longCardSize.width]);
    CGRect hit = CGRectIntersection(placement.translationFrame, placement.sourceFrame);
    CGFloat inside = (hit.size.width * hit.size.height) / MAX((CGFloat)1, NSWidth(placement.translationFrame) * NSHeight(placement.translationFrame));
    CGFloat reproDrift = MAX(0, MAX(NSMinY(placement.sourceFrame) - NSMaxY(placement.translationFrame),
                                    NSMinY(placement.translationFrame) - NSMaxY(placement.sourceFrame)));
    Check(inside >= 0.35 || reproDrift <= MAX(NSHeight(placement.sourceFrame), NSHeight(placement.translationFrame)) + 8,
          [NSString stringWithFormat:@"现场复现：入口落在正文自身范围内或紧邻（%.2f / 偏移 %.0f）", inside, reproDrift]);
    Check(!OverlapsAnyOtherSource(placement, requests), @"现场复现：入口没有遮挡任何别的原文块");
    Check(placement.rejectedCandidates.count > 0, @"现场复现：诊断列出了被拒绝的候选与冲突块");
}

/// 现场真实帧的 OCR 行（用生产同配置的 Vision 对 `frame` 实时跑出来的 31 行；
/// 见 handoff/long-body-entry-20261006/evidence/field-frame-ocr.txt）。
/// 这一帧里「◆桜井琉夏の好み◆」与五行正文是**分开**的两块，问题出在正文被判成"短块"。
static NSArray<FYInlineTextLine *> *FieldFrameLines(void) {
    NSArray<NSArray *> *rows = @[
        @[@"CHARACTER", @0.043, @0.861, @0.393, @0.095],
        @[@"桜井 琉夏", @0.775, @0.905, @0.130, @0.053],
        @[@"RUKA SAKURAI", @0.792, @0.870, @0.097, @0.027],
        @[@"Birthday", @0.700, @0.810, @0.104, @0.047],
        @[@"7月1日", @0.866, @0.782, @0.110, @0.048],
        @[@"Horoscope", @0.700, @0.713, @0.132, @0.042],
        @[@"かに座", @0.897, @0.683, @0.080, @0.044],
        @[@"Blood", @0.701, @0.617, @0.076, @0.042],
        @[@"• 型", @0.918, @0.580, @0.058, @0.050],
        @[@"電話", @0.515, @0.456, @0.048, @0.044],
        @[@"みよのメモ", @0.180, @0.425, @0.098, @0.040],
        @[@"身長", @0.513, @0.388, @0.050, @0.047],
        @[@"178cm", @0.610, @0.392, @0.114, @0.040],
        @[@"◆桜井琉夏の好み◆", @0.178, @0.361, @0.180, @0.038],
        @[@"体重", @0.515, @0.317, @0.048, @0.050],
        @[@"64kg", @0.609, @0.324, @0.090, @0.043],
        @[@"校内でスリリングなことば", @0.178, @0.302, @0.238, @0.038],
        @[@"かりしている彼は、アクテ", @0.178, @0.243, @0.237, @0.038],
        @[@"バイト", @0.515, @0.263, @0.070, @0.038],
        @[@"花屋アンネリー", @0.610, @0.263, @0.167, @0.038],
        @[@"イブな遊びが好きみたい。", @0.180, @0.180, @0.227, @0.044],
        @[@"クラブ", @0.518, @0.201, @0.068, @0.041],
        @[@"帰宅部", @0.610, @0.201, @0.070, @0.041],
        @[@"じっと物思いに耽るような", @0.180, @0.124, @0.237, @0.038],
        @[@"備考", @0.515, @0.130, @0.048, @0.047],
        @[@"桜井琥一の弟。", @0.610, @0.129, @0.154, @0.051],
        @[@"通話へ", @0.040, @0.077, @0.075, @0.047],
        @[@"スリルは彼の活力。", @0.609, @0.079, @0.203, @0.060],
        @[@"場所は苦手そう。", @0.178, @0.054, @0.152, @0.052],
        @[@"プロフィールを見る", @0.010, @0.003, @0.182, @0.036],
        @[@"●戻る", @0.942, @0.003, @0.047, @0.030]
    ];
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray array];
    for (NSArray *row in rows) {
        [lines addObject:Line(row[0], CGRectMake([row[1] doubleValue], [row[2] doubleValue],
                                                 [row[3] doubleValue], [row[4] doubleValue]))];
    }
    return lines;
}

/// 现场真实帧复跑（用户 16:05 打开的那一页）：
/// 旧实现里五行正文被判成"短块"→ 既没有长卡也没有入口 → Unplaceable（这就是用户看到的消失）。
static void TestFieldFrameRealScene(void) {
    CGRect viewport = CGRectMake(457, 454, 1018, 574);   // 现场日志里的映射矩形
    NSArray<FYInlineTextLine *> *lines = FieldFrameLines();
    NSArray<FYInlineTextBlock *> *blocks = Group(lines);
    FYInlineTextBlock *body = nil;
    FYInlineTextBlock *title = nil;
    FYInlineTextBlock *club = nil;
    FYInlineTextBlock *remarks = nil;
    for (FYInlineTextBlock *block in blocks) {
        if ([block.text containsString:kBodyNeedle]) { body = block; }
        if ([block.text containsString:@"◆桜井琉夏の好み◆"]) { title = block; }
        if ([block.text containsString:@"帰宅部"]) { club = block; }
        if ([block.text containsString:@"桜井琥一の弟。"]) { remarks = block; }
    }
    Check(club != nil && [club.text isEqualToString:@"帰宅部"], @"现场真实帧：社团值不与下一行备注合并");
    Check(remarks != nil && remarks != club && [remarks.text containsString:@"スリルは彼の活力。"],
          @"现场真实帧：备注的两行文字组成独立段落");
    Check(body != nil && body.lineCount == 5, @"现场真实帧：五行喜好正文是一块（5 行）");
    Check(title != nil && title != body, @"现场真实帧：标题与正文是两块，没有错误合并");
    Check(body != nil && body.kind == FYInlineBlockKindLong,
          @"现场真实帧：多行正文按段落证据判为长块（旧判据是按钮列表）");

    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    NSMutableDictionary<NSString *, NSString *> *translations = [NSMutableDictionary dictionary];
    translations[kBodyNeedle] = kBodyTranslation;
    translations[@"◆桜井琉夏の好み◆"] = @"◆樱井琉夏的喜好◆";
    translations[@"帰宅部"] = @"回家部";
    translations[@"桜井琥一の弟。"]= @"樱井琥一的弟弟。刺激是他的活力来源。";
    NSArray<FYInlineLayoutRequest *> *requests = RequestsForBlocks(blocks, viewport, translations);
    FYInlineLayoutResult *result = [engine layoutRequests:requests viewport:viewport previous:nil];
    FYInlinePlacement *bodyPlacement = nil;
    FYInlinePlacement *remarksPlacement = nil;
    FYInlinePlacement *clubPlacement = nil;
    for (FYInlinePlacement *placement in result.placements) {
        if ([placement.block.text containsString:kBodyNeedle]) { bodyPlacement = placement; }
        if ([placement.block.text containsString:@"桜井琥一の弟。"]) { remarksPlacement = placement; }
        if ([placement.block.text isEqualToString:@"帰宅部"]) { clubPlacement = placement; }
    }
    Check(clubPlacement != nil && clubPlacement.mode == FYInlineDisplayModeShortLabel,
          @"现场真实帧：社团值附近有足够空间，不应被判为暂不可放置");
    Check(DisplaysFullTranslation(remarksPlacement),
          @"现场真实帧：社团与备注分离后，备注有完整贴译而非空间不足折叠");
    Check(bodyPlacement != nil, @"现场真实帧：正文块有排版结果");
    if (!bodyPlacement) { return; }
    Check(bodyPlacement.mode != FYInlineDisplayModeUnplaceable,
          [NSString stringWithFormat:@"现场真实帧：正文不再消失（mode=%ld，原因：%@）", (long)bodyPlacement.mode, bodyPlacement.reason]);
    Check(bodyPlacement.mode == FYInlineDisplayModeFullCard ||
          bodyPlacement.mode == FYInlineDisplayModeScrollingCard ||
          bodyPlacement.mode == FYInlineDisplayModeCompactEntry,
          @"现场真实帧：正文以长卡或「查看译文」入口显示");
    Check(!OverlapsAnyOtherSource(bodyPlacement, requests), @"现场真实帧：正文的贴译没有遮挡别的原文块");
    Check(bodyPlacement.reason.length > 0 && bodyPlacement.rejectedCandidates.count > 0,
          @"现场真实帧：诊断给出落位原因与逐候选拒绝原因");
}

static void TestProfileFieldGroupingUnderOCRJitter(void) {
    for (CGFloat jitter = -0.003; jitter <= 0.0031; jitter += 0.0015) {
        NSArray<FYInlineTextLine *> *lines = @[
            Line(@"クラブ", CGRectMake(0.518, 0.201, 0.068, 0.041)),
            Line(@"帰宅部", CGRectMake(0.610, 0.201 + jitter, 0.070, 0.041)),
            Line(@"備考", CGRectMake(0.515, 0.130, 0.048, 0.047)),
            Line(@"桜井琥一の弟。", CGRectMake(0.610, 0.129 - jitter, 0.154, 0.051)),
            Line(@"スリルは彼の活力。", CGRectMake(0.609, 0.079, 0.203, 0.060))
        ];
        FYInlineTextBlock *club = nil, *remarks = nil;
        for (FYInlineTextBlock *block in Group(lines)) {
            if ([block.text containsString:@"帰宅部"]) { club = block; }
            if ([block.text containsString:@"桜井琥一の弟。"]) { remarks = block; }
        }
        Check(club != nil && [club.text isEqualToString:@"帰宅部"] &&
              remarks != nil && remarks != club && remarks.lineCount == 2,
              [NSString stringWithFormat:@"OCR 几何抖动 %.4f 时社团和备注仍分开", jitter]);
    }
}

static void TestProfileRowsWithoutRecognizedLabels(void) {
    // 动态背景可让左侧字段名漏读，也可让相邻 OCR 框垂直相交；
    // 短值与下一行较宽的完整句仍不能合成一条翻译请求。
    NSArray<FYInlineTextLine *> *lines = @[
        Line(@"帰宅部", CGRectMake(0.610, 0.191, 0.070, 0.060)),
        Line(@"桜井琥一の弟。", CGRectMake(0.610, 0.143, 0.154, 0.060)),
        Line(@"スリルは彼の活力。", CGRectMake(0.609, 0.079, 0.203, 0.060))
    ];
    FYInlineTextBlock *club = nil, *remarks = nil;
    for (FYInlineTextBlock *block in Group(lines)) {
        if ([block.text containsString:@"帰宅部"]) { club = block; }
        if ([block.text containsString:@"桜井琥一の弟。"]) { remarks = block; }
    }
    Check(club != nil && [club.text isEqualToString:@"帰宅部"] && remarks != nil &&
          remarks != club && remarks.lineCount == 2,
          @"字段标签漏读且 OCR 行框相交时，社团与备注仍不合并");
}

/// 兜底：被判成"短块"的多行段落也不能消失 —— 拿不到任何位置时同样给「查看译文」入口。
static void TestMultilineShortBlockStillGetsEntry(void) {
    CGRect viewport = CGRectMake(0, 0, 300, 190);
    FYInlineTextBlock *paragraph = EntryBlock(@"見出しの一行目です\n二行目の続きです\n三行目の終わり",
                                              CGRectMake(0.06, 0.30, 0.88, 0.34), FYInlineBlockKindShort);
    // 真实 OCR 会给每行一个框：多行块必须按真实行数（lineCount）走兜底。
    paragraph.lineBoxes = @[[NSValue valueWithRect:CGRectMake(0.06, 0.535, 0.88, 0.105)],
                            [NSValue valueWithRect:CGRectMake(0.06, 0.418, 0.86, 0.105)],
                            [NSValue valueWithRect:CGRectMake(0.06, 0.300, 0.80, 0.105)]];
    paragraph.lineTexts = @[@"見出しの一行目です", @"二行目の続きです", @"三行目の終わり"];
    FYInlineTextBlock *neighborTop = EntryBlock(@"上の見出し", CGRectMake(0.06, 0.70, 0.60, 0.12), FYInlineBlockKindShort);
    FYInlineTextBlock *neighborBottom = EntryBlock(@"下の見出し", CGRectMake(0.06, 0.06, 0.60, 0.12), FYInlineBlockKindShort);
    NSMutableArray<FYInlineLayoutRequest *> *requests = [NSMutableArray array];
    for (FYInlineTextBlock *block in @[paragraph, neighborTop, neighborBottom]) {
        [requests addObject:[FYInlineLayoutRequest requestWithBlock:block
                                                        translation:@"这是一段多行的正文译文，用来验证被判成短块时也不会消失。"
                                                        sourceFrame:ScreenFrame(viewport, block.boundingBox)]];
    }
    FYInlineLayoutResult *result = [[FYInlineLayoutEngine defaultEngine] layoutRequests:requests viewport:viewport previous:nil];
    FYInlinePlacement *placement = nil;
    for (FYInlinePlacement *candidate in result.placements) {
        if ([candidate.block.text containsString:@"見出しの一行目"]) { placement = candidate; }
    }
    Check(placement != nil, @"短块兜底：多行段落有排版结果");
    if (!placement) { return; }
    Check(placement.mode == FYInlineDisplayModeCompactEntry,
          [NSString stringWithFormat:@"短块兜底：判成短块的多行段落仍给「查看译文」入口（mode=%ld，原因:%@）",
           (long)placement.mode, placement.reason]);
}

static void TestTinyViewportKeepsEverythingListed(void) {
    // 极小区域：允许这一块确实放不下，但必须明确列出、绝不静默丢。
    CGRect viewport = CGRectMake(0, 0, 300, 170);
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    NSArray<FYInlineTextLine *> *lines = @[
        Line(@"見出しです", CGRectMake(0.05, 0.72, 0.60, 0.10)),
        Line(@"校内でスリリングなことばかりしている彼は、", CGRectMake(0.05, 0.42, 0.90, 0.06)),
        Line(@"アクティブで好奇心旺盛。退屈を嫌い、", CGRectMake(0.05, 0.34, 0.90, 0.06)),
        Line(@"いつも何か新しいことに挑戦している。", CGRectMake(0.05, 0.26, 0.90, 0.06)),
        Line(@"スリルを求めて行動するのが好きで、", CGRectMake(0.05, 0.18, 0.90, 0.06)),
        Line(@"じっとしているのは苦手なのだ。", CGRectMake(0.05, 0.10, 0.90, 0.06))
    ];
    NSArray<FYInlineLayoutRequest *> *requests = nil;
    FYInlineLayoutResult *result = RunScene(engine, lines, viewport, &requests);
    Check(result.placements.count == requests.count, @"极小区域：每个块都有排版结果（含暂不可放置）");
    NSUInteger unplaceable = 0, visible = 0;
    for (FYInlinePlacement *placement in result.placements) {
        if (placement.mode == FYInlineDisplayModeUnplaceable) {
            unplaceable += 1;
            Check(placement.reason.length > 0 && [placement.reason containsString:@"放不下"],
                  [NSString stringWithFormat:@"极小区域：暂不可放置给出尺寸原因（%@）", placement.reason]);
        } else {
            visible += 1;
        }
    }
    Check(unplaceable + visible == requests.count, @"极小区域：要么有位置、要么被明确标记，没有静默丢弃");
    Check(result.unplaceableBlockIDs.count == unplaceable, @"极小区域：unplaceableBlockIDs 与结果一致");
}

// 重复 OCR 框：同一段文字被分组器放过后又以两个块的形式到达布局器
//（框略有差异、文字完全相同）。这时它们不该互相把对方的位置挡掉，
// 诊断里也要明确写出"疑似重复识别"，而不是一句"所有候选冲突"。
// 注意：完全同位置同文字的重复行会被 FYInlineGrouper 的联合去重先吃掉，
// 所以这里直接构造两块，专门验证布局器这一层的兜底。
static void TestDuplicateOCRBoxIsNotAFalseConflict(void) {
    CGRect viewport = ProfileViewport();
    NSString *body = @"校内でスリリングなことばかりしている彼は、\nアクティブで好奇心旺盛。退屈を嫌い、\nいつも何か新しいことに挑戦している。\nスリルを求めて行動するのが好きで、\nじっとしているのは苦手なのだ。";
    NSMutableArray<FYInlineLayoutRequest *> *requests = [NSMutableArray array];
    NSArray<NSString *> *neighbors = @[@"◆桜井琉夏の好み◆", @"身長", @"体重", @"バイト", @"クラブ", @"みよのメモ", @"右側の短い見出し", @"カレーライスが大好物"];
    NSArray<NSValue *> *neighborBoxes = @[
        [NSValue valueWithRect:CGRectMake(0.178, 0.361, 0.180, 0.038)],
        [NSValue valueWithRect:CGRectMake(0.513, 0.388, 0.050, 0.047)],
        [NSValue valueWithRect:CGRectMake(0.513, 0.317, 0.050, 0.053)],
        [NSValue valueWithRect:CGRectMake(0.515, 0.263, 0.070, 0.041)],
        [NSValue valueWithRect:CGRectMake(0.517, 0.201, 0.070, 0.041)],
        [NSValue valueWithRect:CGRectMake(0.180, 0.426, 0.098, 0.038)],
        [NSValue valueWithRect:CGRectMake(0.530, 0.310, 0.100, 0.035)],
        [NSValue valueWithRect:CGRectMake(0.190, 0.196, 0.190, 0.024)]
    ];
    for (NSUInteger index = 0; index < neighbors.count; index++) {
        FYInlineTextBlock *block = EntryBlock(neighbors[index], neighborBoxes[index].rectValue, FYInlineBlockKindShort);
        block.lineBoxes = @[];
        [requests addObject:[FYInlineLayoutRequest requestWithBlock:block
                                                        translation:@"短译文"
                                                        sourceFrame:ScreenFrame(viewport, block.boundingBox)]];
    }
    CGRect bodyBox = CGRectMake(0.178, 0.226, 0.340, 0.130);
    FYInlineTextBlock *first = EntryBlock(body, bodyBox, FYInlineBlockKindLong);
    [requests addObject:[FYInlineLayoutRequest requestWithBlock:first translation:kBodyTranslation
                                                    sourceFrame:ScreenFrame(viewport, bodyBox)]];
    // 同一段文字的第二个框：位置只差 2pt（OCR 两次识别的典型差异）。
    CGRect duplicateBox = CGRectMake(0.180, 0.222, 0.338, 0.128);
    FYInlineTextBlock *second = EntryBlock(body, duplicateBox, FYInlineBlockKindLong);
    [requests addObject:[FYInlineLayoutRequest requestWithBlock:second translation:kBodyTranslation
                                                    sourceFrame:ScreenFrame(viewport, duplicateBox)]];

    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    FYInlineLayoutResult *result = [engine layoutRequests:requests viewport:viewport previous:nil];
    NSUInteger entryCount = 0;
    NSUInteger bodyCount = 0;
    BOOL sawDuplicateNote = NO;
    for (FYInlinePlacement *placement in result.placements) {
        if (![placement.block.text containsString:kBodyNeedle]) { continue; }
        bodyCount += 1;
        if (placement.mode == FYInlineDisplayModeCompactEntry) { entryCount += 1; }
        for (NSString *line in placement.rejectedCandidates) {
            if ([line containsString:@"重复识别"]) { sawDuplicateNote = YES; }
        }
    }
    Check(bodyCount == 2, @"重复框：两个同文字的块都进了布局（分组器去重之外的第二层）");
    Check(entryCount >= 1, @"重复 OCR 框：同一段文字至少有一个「查看译文」入口可见");
    Check(sawDuplicateNote, @"重复 OCR 框：诊断明确写出「几乎重合（疑似重复识别）」而不是笼统的冲突");
    Check(!result.unplaceableBlockIDs.count || entryCount >= 1,
          @"重复 OCR 框：重复没有把这一段的入口挤掉");
}

static void TestLongCardStillUsedWhenThereIsRoom(void) {
    // 反向回归：空间足够时仍然给完整长卡/滚动长卡，不因为本轮改动把所有长正文都降级。
    CGRect viewport = CGRectMake(0, 0, 1200, 700);
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    NSArray<FYInlineTextLine *> *lines = @[
        Line(@"校内でスリリングなことばかりしている彼は、", CGRectMake(0.08, 0.62, 0.30, 0.03)),
        Line(@"アクティブで好奇心旺盛。退屈を嫌い、", CGRectMake(0.08, 0.58, 0.30, 0.03)),
        Line(@"いつも何か新しいことに挑戦している。", CGRectMake(0.08, 0.54, 0.30, 0.03)),
        Line(@"スリルを求めて行動するのが好きで、", CGRectMake(0.08, 0.50, 0.30, 0.03)),
        Line(@"じっとしているのは苦手なのだ。", CGRectMake(0.08, 0.46, 0.30, 0.03))
    ];
    NSArray<FYInlineLayoutRequest *> *requests = nil;
    FYInlineLayoutResult *result = RunScene(engine, lines, viewport, &requests);
    FYInlinePlacement *placement = result.placements.firstObject;
    Check(placement != nil && placement.block.kind == FYInlineBlockKindLong, @"有空间场景：正文仍是长块");
    Check(placement.mode == FYInlineDisplayModeFullCard || placement.mode == FYInlineDisplayModeScrollingCard,
          [NSString stringWithFormat:@"有空间场景：仍然给长卡（mode=%ld，原因：%@）", (long)placement.mode, placement.reason]);
    Check(!placement.compactEntry, @"有空间场景：不是紧凑入口");
}

#pragma mark - B. 应用入口：面板、点击展开、集中列表

static AppDelegate *EntryFixtureApp(CGRect windowBounds) {
    AppDelegate *app = [[AppDelegate alloc] init];
    [app createMainWindow];
    app.inlineTranslationPanels = [NSMutableArray array];
    app.inlineLongCardPanels = [NSMutableArray array];
    app.inlineTranslationCache = [NSMutableDictionary dictionary];
    app.captionFontSizeSlider = [NSSlider sliderWithValue:30 minValue:12 maxValue:48 target:nil action:nil];
    app.captionOpacitySlider = [NSSlider sliderWithValue:0.58 minValue:0 maxValue:1 target:nil action:nil];
    WindowItem *window = [[WindowItem alloc] init];
    window.windowID = 9301;
    window.displayName = @"Fixture";
    window.bounds = windowBounds;
    app.windows = [NSMutableArray arrayWithObject:window];
    app.windowPopup = [[NSPopUpButton alloc] init];
    [app.windowPopup addItemWithTitle:@"Fixture"];
    app.windowPopup.menu.itemArray.firstObject.representedObject = @(9301);
    return app;
}

static OCRTextItem *EntryItem(NSString *text, CGRect box, InlineBlockKind kind, NSArray<NSValue *> *lineBoxes) {
    OCRTextItem *item = [[OCRTextItem alloc] init];
    item.text = text;
    item.boundingBox = box;
    item.lineBoxes = lineBoxes ?: @[[NSValue valueWithRect:box]];
    item.lineTexts = @[text];
    item.lineCount = (NSInteger)item.lineBoxes.count;
    item.blockKind = kind;
    item.confidence = 0.95;
    item.groupingConfidence = 1.0;
    return item;
}

static void TestCombinedVisionObservationUsesSeparateFieldRows(void) {
    AppDelegate *app = EntryFixtureApp(CGRectMake(457, 454, 1018, 574));
    NSMutableArray<OCRTextItem *> *raw = [NSMutableArray array];
    for (FYInlineTextLine *line in FieldFrameLines()) {
        if ([line.text isEqualToString:@"帰宅部"] || [line.text isEqualToString:@"桜井琥一の弟。"] ||
            [line.text isEqualToString:@"スリルは彼の活力。"]) { continue; }
        [raw addObject:EntryItem(line.text, line.rect, InlineBlockKindShort, nil)];
    }
    CGRect unionBox = CGRectMake(0.608, 0.079, 0.204, 0.164);
    NSArray<NSValue *> *preciseBoxes = @[
        [NSValue valueWithRect:CGRectMake(0.610, 0.201, 0.070, 0.041)],
        [NSValue valueWithRect:CGRectMake(0.610, 0.129, 0.154, 0.051)],
        [NSValue valueWithRect:CGRectMake(0.609, 0.079, 0.203, 0.060)]];
    for (NSUInteger variant = 0; variant < 2; variant++) {
        OCRTextItem *combined = EntryItem(@"帰宅部\n桜井琥一の弟。\nスリルは彼の活力。",
                                           unionBox, InlineBlockKindShort, variant == 0 ? preciseBoxes : nil);
        NSArray<OCRTextItem *> *merged = [app mergedInlineTextItemsFromItems:[raw arrayByAddingObject:combined]];
        OCRTextItem *club = nil, *remarks = nil;
        for (OCRTextItem *item in merged) {
            if ([item.text containsString:@"帰宅部"]) { club = item; }
            if ([item.text containsString:@"桜井琥一の弟。"]) { remarks = item; }
        }
        Check(club != nil && [club.text isEqualToString:@"帰宅部"] && remarks != nil &&
              remarks != club && [remarks.text containsString:@"スリルは彼の活力。"],
              [NSString stringWithFormat:@"Vision 多行结果（%@）：社团与备注仍是两条译文",
               variant == 0 ? @"逐行框" : @"仅总框"]);
    }
}

static void TestDecoratedProfileValueKeepsSeparateTranslation(void) {
    // 2026-10-07 23:21 的现场观察：装饰点扩大社团框，使其与左侧标签轻微重叠。
    // 同时覆盖标签漏读，避免仅依赖左侧标签才能分开两个字段。
    for (NSUInteger variant = 0; variant < 2; variant++) {
        CGRect viewport = CGRectMake(488, 472, 966, 546);
        AppDelegate *app = EntryFixtureApp(viewport);
        NSMutableArray *raw = [NSMutableArray array];
        for (FYInlineTextLine *line in FieldFrameLines()) {
            if ([line.text isEqualToString:@"帰宅部"] || [line.text isEqualToString:@"桜井琥一の弟。"] ||
                [line.text isEqualToString:@"スリルは彼の活力。"] ||
                (variant == 1 && ([line.text isEqualToString:@"クラブ"] || [line.text isEqualToString:@"備考"]))) { continue; }
            [raw addObject:EntryItem(line.text, line.rect, InlineBlockKindShort, nil)];
        }
        [raw addObjectsFromArray:@[
            EntryItem(@"•帰宅部", CGRectMake(.583271, .200723, .096791, .042342), InlineBlockKindShort, nil),
            EntryItem(@"桜井琥一の弟。", CGRectMake(.609768, .129390, .153959, .051420), InlineBlockKindShort, nil),
            EntryItem(@"スリルは彼の活力。", CGRectMake(.609495, .079067, .202832, .061861), InlineBlockKindShort, nil)]];
        NSArray *grouped = [app filteredInlineTextItems:[app mergedInlineTextItemsFromItems:raw] strict:NO];
        [app.inlineFrameStabilizer observeItems:grouped];
        NSArray<OCRTextItem *> *stable = [app.inlineFrameStabilizer observeItems:grouped];
        OCRTextItem *club = nil, *remarks = nil;
        NSMutableArray *translations = [NSMutableArray array];
        for (OCRTextItem *item in stable) {
            NSDictionary *labels = @{@"クラブ": @"俱乐部", @"備考": @"备注", @"身長": @"身高",
                                     @"体重": @"体重", @"バイト": @"打工", @"電話": @"电话"};
            NSString *translation = labels[item.text] ?: @"菜单译文";
            if ([item.text containsString:@"帰宅部"]) { club = item; translation = @"回家部"; }
            if ([item.text containsString:@"桜井琥一の弟。"]) {
                remarks = item; translation = @"樱井琥一的弟弟。\n刺激是他的活力来源。";
            }
            if ([item.text containsString:kBodyNeedle]) { translation = kBodyTranslation; }
            [translations addObject:translation];
        }
        Check(club && [club.text isEqualToString:@"•帰宅部"] && remarks && remarks != club &&
              [remarks.text isEqualToString:@"桜井琥一の弟。\nスリルは彼の活力。"],
              [NSString stringWithFormat:@"带装饰点的现场帧（标签%@）：分组及首次确认保持两条译文", variant == 0 ? @"存在" : @"漏读"]);
        [app showInlineTranslations:translations forItems:stable placementRect:viewport];
        FYInlinePlacement *clubPlacement = nil, *remarksPlacement = nil;
        for (FYInlinePlacement *placement in app.lastInlineLayoutResult.placements) {
            if ([placement.block.text containsString:@"帰宅部"]) { clubPlacement = placement; }
            if ([placement.block.text containsString:@"桜井琥一の弟。"]) { remarksPlacement = placement; }
        }
        Check(clubPlacement && remarksPlacement && clubPlacement != remarksPlacement &&
              clubPlacement.mode == FYInlineDisplayModeShortLabel && DisplaysFullTranslation(remarksPlacement),
              [NSString stringWithFormat:@"带装饰点的现场帧：社团与两行备注完整贴译，不触发空间不足折叠（社团 %ld %@；备注 %ld %@）",
               (long)clubPlacement.mode, clubPlacement.reason, (long)remarksPlacement.mode, remarksPlacement.reason]);
        if (remarksPlacement.mode == FYInlineDisplayModeUnplaceable) {
            NSLog(@"DECORATED-PROFILE rejected=%@", remarksPlacement.rejectedCandidates);
            for (FYInlinePlacement *p in app.lastInlineLayoutResult.placements) {
                NSLog(@"DECORATED-PROFILE text=%@ source=%@ panel=%@", p.block.text,
                      NSStringFromRect(p.sourceFrame), NSStringFromRect(p.translationFrame));
            }
        }
        [app clearInlineTranslationPanels];
    }
}

static void TestCompactProseIsNotAMenu(void) {
    NSArray<NSArray<NSString *> *> *paragraphs = @[
        @[@"桜井琉夏の兄。", @"悪態とクールの紙一重。"],
        @[@"桜井琥一の弟。", @"スリルは彼の活力。"],
        @[@"兄と同居している。", @"人混みは苦手らしい。"]];
    for (NSArray<NSString *> *sentences in paragraphs) {
        for (NSNumber *width in @[@0.23, @0.247]) {
            NSArray<FYInlineTextBlock *> *blocks = Group(@[
                Line(sentences[0], CGRectMake(.610, .129, .160, .051)),
                Line(sentences[1], CGRectMake(.610, .079, width.doubleValue, .061))]);
            Check(blocks.count == 1 && blocks.firstObject.kind == FYInlineBlockKindLong,
                  @"紧排的完整短句在窄列及宽度阈值两侧均按正文处理");
        }
    }
    for (NSArray<NSString *> *labels in @[@[@"設定", @"ロード"], @[@"予定（未定）", @"【状態】"]]) {
        NSArray<FYInlineTextBlock *> *blocks = Group(@[
            Line(labels[0], CGRectMake(.610, .129, .160, .051)),
            Line(labels[1], CGRectMake(.610, .079, .160, .061))]);
        BOOL allShort = blocks.count == 2;
        for (FYInlineTextBlock *block in blocks) { allShort &= block.kind == FYInlineBlockKindShort; }
        Check(allShort, @"紧排菜单和括号字段仍是独立短条目");
    }
}

static void TestFieldSpaceDoesNotDependOnTextKind(void) {
    CGRect viewport = CGRectMake(488, 472, 966, 546);
    for (NSNumber *kind in @[@(FYInlineBlockKindShort), @(FYInlineBlockKindLong)]) {
        FYInlineTextBlock *remarks = EntryBlock(@"桜井琉夏の兄。\n悪態とクールの紙一重。",
                                               CGRectMake(.610, .079, .247, .102), kind.integerValue);
        remarks.lineBoxes = @[[NSValue valueWithRect:CGRectMake(.610, .129, .160, .051)],
                              [NSValue valueWithRect:CGRectMake(.610, .079, .247, .061)]];
        remarks.lineTexts = @[@"桜井琉夏の兄。", @"悪態とクールの紙一重。"];
        NSArray<FYInlineTextBlock *> *blocks = @[
            EntryBlock(@"ガソリンスタンド", CGRectMake(.610, .263, .187, .038), FYInlineBlockKindShort),
            EntryBlock(@"クラブ", CGRectMake(.517, .201, .070, .041), FYInlineBlockKindShort),
            EntryBlock(@"帰宅部", CGRectMake(.610, .201, .070, .041), FYInlineBlockKindShort),
            EntryBlock(@"備考", CGRectMake(.515, .130, .048, .047), FYInlineBlockKindShort), remarks];
        NSArray *translations = @[@"加油站", @"社团", @"回家部", @"备注", @"樱井琉夏的哥哥。\n坏脾气与冷酷仅一线之隔。"];
        NSMutableArray *requests = [NSMutableArray array];
        for (NSUInteger i = 0; i < blocks.count; i++) {
            [requests addObject:[FYInlineLayoutRequest requestWithBlock:blocks[i] translation:translations[i]
                                                            sourceFrame:ScreenFrame(viewport, blocks[i].boundingBox)]];
        }
        FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
        engine.shortFontSize = 14.51; engine.coverFontSize = 15.51;
        engine.longBodyFontSize = 17.51; engine.minimumLongBodyFontSize = 13.51;
        engine.longTitleFontSize = 12.51; engine.cardMaxWidth = 314.588;
        engine.shortMaxWidth = 314.588 * 360 / 560;
        FYInlineLayoutResult *result = [engine layoutRequests:requests viewport:viewport previous:nil];
        FYInlinePlacement *p = [result placementForBlockID:remarks.blockID];
        Check(DisplaysFullTranslation(p), @"空间判定独立于 Short/Long：有合法空隙时显示完整备注");
        BOOL clear = DisplaysFullTranslation(p) && CGRectContainsRect(viewport, p.translationFrame);
        for (FYInlinePlacement *other in result.placements) {
            if (other == p) { continue; }
            CGRect source = CGRectIntersection(p.translationFrame, other.sourceFrame);
            CGRect panel = CGRectIntersection(p.translationFrame, other.translationFrame);
            if ((!CGRectIsNull(source) && !CGRectIsEmpty(source)) ||
                (other.mode != FYInlineDisplayModeUnplaceable && !CGRectIsNull(panel) && !CGRectIsEmpty(panel))) { clear = NO; }
            Check(DisplaysFullTranslation(other), @"字段内避让也保留周围短字段的完整译文");
        }
        Check(clear, @"两类正文均在自己的字段附近，与其它原文、译文零重叠");
    }
}

static void TestProfileRemarksAcrossCharactersAndViewports(void) {
    // 琥一现场 23:50：备注译文比原文框高，居中时压到上方社团约 4pt。
    // 使用真实译文、完整周边字段、生产分组/跟踪/渲染，并保留角色切换的前帧布局。
    NSArray<NSValue *> *viewports = @[
        [NSValue valueWithRect:CGRectMake(488, 472, 966, 546)],
        [NSValue valueWithRect:CGRectMake(457, 454, 1018, 574)],
        [NSValue valueWithRect:CGRectMake(250, 250, 1200, 680)]];
    for (NSValue *value in viewports) {
        for (NSNumber *fontSize in @[@14.51, @16]) {
          for (NSNumber *width in @[@314.588, @560]) {
            CGRect viewport = value.rectValue;
            AppDelegate *app = EntryFixtureApp(viewport);
            app.batchFontSizeSlider = [NSSlider sliderWithValue:fontSize.doubleValue minValue:10 maxValue:36 target:nil action:nil];
            app.batchWidthSlider = [NSSlider sliderWithValue:width.doubleValue minValue:200 maxValue:800 target:nil action:nil];
            app.batchHeightSlider = [NSSlider sliderWithValue:330 minValue:100 maxValue:600 target:nil action:nil];
            [app applyBatchAppearanceToLayoutEngine];
            for (NSNumber *character in @[@YES, @NO, @YES]) {
                BOOL brother = character.boolValue;
                NSString *first = brother ? @"桜井琉夏の兄。" : @"桜井琥一の弟。";
                NSString *second = brother ? @"悪態とクールの紙一重。" : @"スリルは彼の活力。";
                NSString *translation = brother ? @"樱井琉夏的哥哥。\n坏脾气与冷酷仅一线之隔。" :
                                                  @"樱井琥一的弟弟。\n刺激是他的活力来源。";
                NSMutableArray<OCRTextItem *> *raw = [NSMutableArray array];
                for (FYInlineTextLine *line in FieldFrameLines()) {
                    NSString *text = line.text;
                    CGRect box = line.rect;
                    if ([text isEqualToString:@"帰宅部"]) { box = CGRectMake(.608, .201, .072, .041); }
                    if ([text isEqualToString:@"桜井琥一の弟。"]) { text = first; box = CGRectMake(.610, .129, .160, .051); }
                    if ([text isEqualToString:@"スリルは彼の活力。"]) {
                        text = second; box = CGRectMake(.610, .079, brother ? .2474 : .203, .0609);
                    }
                    if (brother && [text isEqualToString:@"桜井 琉夏"]) { text = @"桜井 琥一"; }
                    if (brother && [text isEqualToString:@"RUKA SAKURAI"]) { text = @"KOUICHI SAKURAI"; }
                    if (brother && [text isEqualToString:@"花屋アンネリー"]) { text = @"ガソリンスタンド"; }
                    [raw addObject:EntryItem(text, box, InlineBlockKindShort, nil)];
                }
                NSArray *grouped = [app filteredInlineTextItems:[app mergedInlineTextItemsFromItems:raw] strict:NO];
                NSArray<OCRTextItem *> *stable = nil;
                for (NSUInteger frame = 0; frame < 4; frame++) { stable = [app.inlineFrameStabilizer observeItems:grouped]; }
                NSMutableArray<NSString *> *translations = [NSMutableArray array];
                for (OCRTextItem *item in stable) {
                    NSDictionary *labels = @{@"クラブ": @"社团", @"備考": @"备注", @"身長": @"身高",
                                             @"体重": @"体重", @"バイト": @"打工", @"電話": @"电话"};
                    NSString *translated = labels[item.text] ?: @"菜单译文";
                    if ([item.text containsString:@"帰宅部"]) { translated = @"回家部"; }
                    if ([item.text containsString:first]) { translated = translation; }
                    if ([item.text containsString:kBodyNeedle]) { translated = kBodyTranslation; }
                    [translations addObject:translated];
                }
                [app showInlineTranslations:translations forItems:stable placementRect:viewport];
                FYInlinePlacement *remarks = nil, *club = nil;
                for (FYInlinePlacement *p in app.lastInlineLayoutResult.placements) {
                    if ([p.block.text containsString:first]) { remarks = p; }
                    if ([p.block.text containsString:@"帰宅部"]) { club = p; }
                }
                NSString *context = [NSString stringWithFormat:@"角色切换 %@ %.0fx%.0f 字号%.2f 宽%.0f",
                                     brother ? @"琥一" : @"琉夏", NSWidth(viewport), NSHeight(viewport), fontSize.doubleValue, width.doubleValue];
                Check(remarks && club && remarks != club && DisplaysFullTranslation(remarks) &&
                      remarks.block.kind == FYInlineBlockKindLong &&
                      club.mode == FYInlineDisplayModeShortLabel && [remarks.translation isEqualToString:translation],
                      [context stringByAppendingFormat:@"：社团与完整备注分别显示（备注 mode=%ld %@）",
                       (long)remarks.mode, remarks.reason]);
                if (!DisplaysFullTranslation(remarks)) { continue; }
                BOOL clear = CGRectContainsRect(viewport, remarks.translationFrame);
                for (FYInlinePlacement *other in app.lastInlineLayoutResult.placements) {
                    if (other == remarks) { continue; }
                    CGRect sourceHit = CGRectIntersection(remarks.translationFrame, other.sourceFrame);
                    if (!CGRectIsNull(sourceHit) && !CGRectIsEmpty(sourceHit)) { clear = NO; }
                    if (other.mode != FYInlineDisplayModeUnplaceable) {
                        CGRect panelHit = CGRectIntersection(remarks.translationFrame, other.translationFrame);
                        if (!CGRectIsNull(panelHit) && !CGRectIsEmpty(panelHit)) { clear = NO; }
                    }
                }
                Check(clear, [context stringByAppendingString:@"：备注在画面内且与其它原文、译文零重叠"]);
            }
            [app clearInlineTranslationPanels];
          }
        }
    }
}

static OCRTextItem *ProfileBodyItem(void) {
    NSArray<NSValue *> *boxes = @[
        [NSValue valueWithRect:CGRectMake(0.178, 0.322, 0.215, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.296, 0.200, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.270, 0.205, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.244, 0.195, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.218, 0.170, 0.026)]
    ];
    return EntryItem(@"校内でスリリングなことばかりしている彼は、\nアクティブで好奇心旺盛。退屈を嫌い、\nいつも何か新しいことに挑戦している。\nスリルを求めて行動するのが好きで、\nじっとしているのは苦手なのだ。",
                     CGRectMake(0.178, 0.218, 0.215, 0.130), InlineBlockKindLong, boxes);
}

static NSScrollView *ScrollOf(NSView *view) {
    for (NSView *child in view.subviews) {
        if ([child isKindOfClass:NSScrollView.class]) { return (NSScrollView *)child; }
    }
    return nil;
}

static void TestAppCompactEntryShowsAndExpands(void) {
    // 与现场同量级的画面区域：正文所在的一栏很挤。
    NSRect viewport = NSRectFromCGRect(ProfileViewport());
    AppDelegate *app = EntryFixtureApp(viewport);
    NSArray<OCRTextItem *> *items = @[
        EntryItem(@"◆桜井琉夏の好み◆", CGRectMake(0.178, 0.361, 0.180, 0.038), InlineBlockKindShort, nil),
        EntryItem(@"身長", CGRectMake(0.513, 0.388, 0.050, 0.047), InlineBlockKindShort, nil),
        EntryItem(@"体重", CGRectMake(0.513, 0.317, 0.050, 0.053), InlineBlockKindShort, nil),
        EntryItem(@"バイト", CGRectMake(0.515, 0.263, 0.070, 0.041), InlineBlockKindShort, nil),
        EntryItem(@"花屋アンネリー", CGRectMake(0.608, 0.263, 0.168, 0.041), InlineBlockKindShort, nil),
        EntryItem(@"クラブ", CGRectMake(0.517, 0.201, 0.070, 0.041), InlineBlockKindShort, nil),
        EntryItem(@"帰宅部\n桜井琥一の弟。\nスリルは彼の活力。", CGRectMake(0.608, 0.079, 0.204, 0.164), InlineBlockKindShort, nil),
        EntryItem(@"みよのメモ", CGRectMake(0.180, 0.426, 0.098, 0.038), InlineBlockKindShort, nil),
        ProfileBodyItem()
    ];
    NSArray<NSString *> *translations = @[@"◆樱井琉夏的喜好◆", @"身高", @"体重", @"打工", @"花店安妮莉", @"社团", @"回家部\n樱井琥一的弟弟。刺激是他的活力。", @"美代的笔记", kBodyTranslation];
    [app showInlineTranslations:translations forItems:items placementRect:viewport];

    // 正文那一块必须真的出现在画面上（要么完整长卡，要么"查看译文"入口）。
    FYInlinePlacement *bodyPlacement = nil;
    for (FYInlinePlacement *placement in app.lastInlineLayoutResult.placements) {
        if ([placement.block.text containsString:kBodyNeedle]) { bodyPlacement = placement; break; }
    }
    Check(bodyPlacement != nil, @"应用：正文块出现在布局结果里");
    if (!bodyPlacement) { return; }
    Check(bodyPlacement.mode != FYInlineDisplayModeUnplaceable,
          [NSString stringWithFormat:@"应用：正文没有变成「暂不可放置」（mode=%ld）", (long)bodyPlacement.mode]);

    NSPanel *bodyPanel = nil;
    for (NSPanel *panel in app.inlineLongCardPanels) {
        if ([panel.identifier isEqualToString:bodyPlacement.blockID]) { bodyPanel = panel; }
    }
    Check(bodyPanel != nil, @"应用：正文对应的面板真的创建出来了（不是只在数据里）");
    if (!bodyPanel) { return; }
    BOOL folded = bodyPlacement.mode == FYInlineDisplayModeCompactEntry;
    Check(folded || bodyPlacement.mode == FYInlineDisplayModeFullCard ||
          bodyPlacement.mode == FYInlineDisplayModeScrollingCard,
          [NSString stringWithFormat:@"应用：正文以完整长卡或入口显示（mode=%ld）", (long)bodyPlacement.mode]);

    FYInlineLongCardView *card = (FYInlineLongCardView *)bodyPanel.contentView;
    Check([card isKindOfClass:FYInlineLongCardView.class] && card.compactEntry == folded,
          @"应用：面板形态与布局结果一致");
    Check(NSHeight(bodyPanel.frame) >= 30 && NSWidth(bodyPanel.frame) >= MeasuredEntryTextWidth(app.inlineLayoutEngine) + 14,
          [NSString stringWithFormat:@"应用：面板尺寸可读（%.0f×%.0f）", NSWidth(bodyPanel.frame), NSHeight(bodyPanel.frame)]);
    if (folded) {
    // 折叠入口的三行文案：标题 / 收起原因 / 「点击展开 ▾」，与引擎测量用的是同一份。
    FYInlineLongCardView *entryCard = (FYInlineLongCardView *)bodyPanel.contentView;
    NSString *expectedHint = bodyPlacement.entryHint;
    Check(entryCard.foldedEntryHintLabel != nil &&
          [entryCard.foldedEntryHintLabel.stringValue isEqualToString:expectedHint],
          [NSString stringWithFormat:@"应用：入口提示文字就是引擎量过的那一行（%@）", expectedHint]);
    Check(entryCard.foldedEntryActionLabel != nil &&
          [entryCard.foldedEntryActionLabel.stringValue containsString:@"点击展开"] &&
          [entryCard.foldedEntryActionLabel.stringValue containsString:@"▾"],
          @"应用：入口有「点击展开 ▾」动作行");
    BOOL hintFits = NO;
    if (entryCard.foldedEntryHintLabel) {
        NSFont *hintFont = [app.inlineLayoutEngine foldedEntryHintFont];
        CGFloat needed = ceil(NSWidth([entryCard.foldedEntryHintLabel.stringValue boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
                                                                                              options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                                                           attributes:@{NSFontAttributeName: hintFont}]));
        hintFits = NSWidth(entryCard.foldedEntryHintLabel.frame) + 1 >= needed;
    }
    Check(hintFits, @"应用：入口提示不会被截断（不是只靠悬停）");
    }

    // 面板不遮挡别的原文块。
    for (OCRTextItem *item in items) {
        if ([item.text containsString:kBodyNeedle]) { continue; }
        NSRect source = [app appKitFrameForOCRItem:item inWindowFrame:viewport];
        Check(!CGRectIntersectsRect(bodyPanel.frame, source),
              [NSString stringWithFormat:@"应用：入口没有遮挡原文 <%@>", Shorten(item.text, 12)]);
    }

    // 点击 → 完整阅读卡（卡内滚动、保留原文、稳定身份、学习入口）。
    if (folded) {
    Check(card.onClick != nil, @"应用：入口可点击");
    if (card.onClick) { card.onClick(); }
    Check(app.inlineExpandedReadingPanel != nil, @"应用：点击入口打开了完整阅读卡");
    if (app.inlineExpandedReadingPanel) {
        NSScrollView *scroll = ScrollOf(app.inlineExpandedReadingPanel.contentView);
        Check(scroll != nil, @"应用：完整阅读卡有滚动区（长文本可滚动）");
        FYInlineLongCardView *expanded = (FYInlineLongCardView *)app.inlineExpandedReadingPanel.contentView;
        Check(expanded.stableBlockID.length > 0 && [expanded.stableBlockID isEqualToString:bodyPlacement.blockID],
              @"应用：展开卡保留同一个稳定块身份");
        BOOL readable = NO;
        if ([scroll.documentView isKindOfClass:NSTextField.class]) {
            NSString *shown = [(NSTextField *)scroll.documentView stringValue];
            readable = [shown containsString:@"好奇心旺盛"] && [shown containsString:@"静不下来"];
        }
        Check(readable, @"应用：展开卡里能看到完整译文（不是截断的）");
        // 折叠回入口（需求 3：保留完整阅读路径且能收起来）。
        expanded.onCollapse ? expanded.onCollapse() : (void)0;
        if (expanded.onClick) { expanded.onClick(); }
        Check(app.inlineExpandedReadingPanel == nil, @"应用：展开卡可以收起（再点一次）");
    }

    // 集中列表 / 状态区：这一块用入口显示，条数要能对上。
    Check(app.inlineTranslationListCount.stringValue.length > 0,
          [NSString stringWithFormat:@"应用：集中列表标出降级条数（%@）", app.inlineTranslationListCount.stringValue]);
    Check(app.inlineTranslationListSnapshots.count >= 1, @"应用：集中列表保留了这一块的原文+译文快照");
    Check(app.lastInlineCompactEntryCount >= 1, @"应用：统计里记下了「查看译文」入口条数");
    } else {
        Check(!card.compactEntry && ScrollOf(card) != nil, @"应用：完整长卡直接显示正文");
        Check(app.lastInlineCompactEntryCount == 0, @"应用：完整长卡不计入折叠入口");
    }
}

/// 被判成"短块"的多行项拿到紧凑入口时，必须用长卡视图渲染成入口卡片
/// （短贴片视图拿不到 labelFrame，会变成空框）。
static void TestAppShortBlockEntryRendersAsCard(void) {
    NSRect viewport = NSMakeRect(0, 0, 300, 190);
    AppDelegate *app = EntryFixtureApp(viewport);
    NSArray<NSValue *> *paragraphLines = @[
        [NSValue valueWithRect:CGRectMake(0.06, 0.535, 0.88, 0.105)],
        [NSValue valueWithRect:CGRectMake(0.06, 0.418, 0.86, 0.105)],
        [NSValue valueWithRect:CGRectMake(0.06, 0.300, 0.80, 0.105)]
    ];
    OCRTextItem *paragraph = EntryItem(@"見出しの一行目です\n二行目の続きです\n三行目の終わり",
                                      CGRectMake(0.06, 0.300, 0.88, 0.34), InlineBlockKindShort, paragraphLines);
    paragraph.lineTexts = @[@"見出しの一行目です", @"二行目の続きです", @"三行目の終わり"];
    paragraph.lineCount = 3;
    OCRTextItem *top = EntryItem(@"上の見出し", CGRectMake(0.06, 0.70, 0.60, 0.12), InlineBlockKindShort, nil);
    OCRTextItem *bottom = EntryItem(@"下の見出し", CGRectMake(0.06, 0.06, 0.60, 0.12), InlineBlockKindShort, nil);
    NSArray<OCRTextItem *> *items = @[paragraph, top, bottom];
    [app showInlineTranslations:@[@"这是一段多行的正文译文，用来验证被判成短块时也不会消失。", @"上面的标题", @"下面的标题"]
                       forItems:items placementRect:viewport];
    FYInlinePlacement *placement = nil;
    for (FYInlinePlacement *candidate in app.lastInlineLayoutResult.placements) {
        if ([candidate.block.text containsString:@"見出しの一行目"]) { placement = candidate; }
    }
    Check(placement != nil && placement.mode == FYInlineDisplayModeCompactEntry,
          [NSString stringWithFormat:@"应用·短块入口：多行短块降级成入口（mode=%ld）", (long)placement.mode]);
    NSPanel *panel = app.inlineLongCardPanels.firstObject;
    Check(panel != nil, @"应用·短块入口：入口面板是长卡视图（不是短贴片）");
    if (!panel) { return; }
    FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
    Check([card isKindOfClass:FYInlineLongCardView.class] && card.compactEntry,
          @"应用·短块入口：面板确实是「查看译文」入口卡片");
    Check(NSHeight(panel.frame) >= 30 && NSWidth(panel.frame) >= 90,
          [NSString stringWithFormat:@"应用·短块入口：入口可点击、不是空框（%.0f×%.0f）", NSWidth(panel.frame), NSHeight(panel.frame)]);
    Check(card.onClick != nil, @"应用·短块入口：入口可点击");
    card.onClick();
    Check(app.inlineExpandedReadingPanel != nil, @"应用·短块入口：点击后能读到完整译文");
}

static void TestAppUnplaceableStaysInListAndStatus(void) {
    // 极小画面里塞三块长正文：必然有人确实放不下 → 集中列表保留 + 状态区明确说"未在画面显示"。
    NSRect viewport = NSMakeRect(0, 0, 260, 150);
    AppDelegate *app = EntryFixtureApp(viewport);
    OCRTextItem *first = EntryItem(@"校内でスリリングなことばかりしている彼は、\nアクティブで好奇心旺盛。退屈を嫌い、\nいつも何か新しいことに挑戦している。",
                                   CGRectMake(0.04, 0.42, 0.92, 0.30), InlineBlockKindLong, nil);
    OCRTextItem *second = EntryItem(@"スリルを求めて行動するのが好きで、\nじっとしているのは苦手なのだ。\n海とドライブが大好きです。",
                                    CGRectMake(0.04, 0.06, 0.92, 0.30), InlineBlockKindLong, nil);
    OCRTextItem *third = EntryItem(@"その他のかなり長い説明文がここに続きます。\n読み飛ばさないでください。",
                                   CGRectMake(0.30, 0.66, 0.66, 0.22), InlineBlockKindLong, nil);
    NSArray<OCRTextItem *> *items = @[first, second, third];
    // 走完整的翻译结果入口（状态区/集中列表都是它更新的）。
    [app handleInlineTranslationResult:@[kBodyTranslation, @"喜欢追求惊险刺激，静不下来。喜欢大海和兜风。", @"其它的长说明文在这里继续，请不要跳过。"]
                              forItems:items
                                 error:nil
                         failureStatus:@"界面翻译出错"
                         successPrefix:@"界面译文已更新"];
    Tick();
    Tick();
    NSUInteger degraded = app.lastInlineUnplaceableCount + app.lastInlineCompactEntryCount;
    Check(degraded >= 1, @"极小画面：统计里至少有 1 条降级");
    Check(app.inlineTranslationListCard != nil && !app.inlineTranslationListCard.hidden,
          @"极小画面：集中列表仍然保留这些内容（没有隐藏）");
    Check([app.inlineTranslationListCount.stringValue containsString:@"条"],
          [NSString stringWithFormat:@"极小画面：集中列表标出条数（%@）", app.inlineTranslationListCount.stringValue]);
    Check(app.inlineTranslationListSnapshots.count >= 1, @"极小画面：集中列表里有可点击的学习入口快照");
    if (app.lastInlineUnplaceableCount > 0) {
        Check([app.statusLabel.stringValue containsString:@"未在画面显示"],
              [NSString stringWithFormat:@"极小画面：状态区明确提示有多少条未在画面显示（%@）", app.statusLabel.stringValue]);
        Check([app.statusLabel.stringValue containsString:@"暂不可放置"],
              @"极小画面：状态区保留「暂不可放置」的说法（可被测试与用户对上）");
    } else {
        Check(app.lastInlineCompactEntryCount >= 1 && [app.statusLabel.stringValue containsString:@"查看译文"],
              [NSString stringWithFormat:@"极小画面：全部降级为入口时状态区说明条数（%@）", app.statusLabel.stringValue]);
    }
}

#pragma mark - 截图

static void SaveCanvas(NSImage *image, NSString *path) {
    if (!image || path.length == 0) { return; }
    CGImageRef cg = [image CGImageForProposedRect:NULL context:NULL hints:NULL];
    if (!cg) { return; }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (png) { [png writeToFile:path atomically:YES]; }
}

/// 把"游戏画面 + 原文框 + 最终贴译位置"画成对照图：
/// 灰底=画面、蓝框=OCR 原文块、绿=「查看译文」入口/长卡、黄=短贴片。
static void DrawResult(FYInlineLayoutEngine *engine,
                       NSArray<FYInlineLayoutRequest *> *requests,
                       FYInlineLayoutResult *result,
                       CGRect viewport,
                       NSString *path) {
    // 只把**目标正文**画成高亮：别的块淡出，方便一眼看出这一段有没有入口。
    NSString *highlight = kBodyNeedle;
    NSSize size = NSMakeSize(NSWidth(viewport), NSHeight(viewport));
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor colorWithCalibratedWhite:0.95 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    for (NSUInteger index = 0; index < requests.count; index++) {
        BOOL isTarget = [requests[index].block.text containsString:highlight];
        NSRect local = NSMakeRect(NSMinX(requests[index].sourceFrame) - NSMinX(viewport),
                                  NSMinY(requests[index].sourceFrame) - NSMinY(viewport),
                                  NSWidth(requests[index].sourceFrame), NSHeight(requests[index].sourceFrame));
        [[NSColor colorWithCalibratedRed:0.16 green:0.42 blue:0.95 alpha:isTarget ? 0.22 : 0.07] setFill];
        NSRectFill(local);
        [[NSColor colorWithCalibratedRed:0.16 green:0.42 blue:0.95 alpha:isTarget ? 0.95 : 0.25] setStroke];
        NSFrameRect(local);
    }
    for (FYInlinePlacement *placement in result.placements) {
        if (placement.mode == FYInlineDisplayModeUnplaceable) { continue; }
        BOOL isTarget = [placement.block.text containsString:highlight];
        if (!isTarget) { continue; }   // 其它块淡出，只留目标正文的最终位置
        NSRect local = NSMakeRect(NSMinX(placement.translationFrame) - NSMinX(viewport),
                                  NSMinY(placement.translationFrame) - NSMinY(viewport),
                                  NSWidth(placement.translationFrame), NSHeight(placement.translationFrame));
        BOOL entry = placement.mode == FYInlineDisplayModeCompactEntry;
        [[NSColor colorWithCalibratedRed:0.08 green:0.62 blue:0.33 alpha:entry ? 0.9 : 0.4] setFill];
        NSRectFill(local);
        [[NSColor colorWithCalibratedRed:0.04 green:0.42 blue:0.22 alpha:1.0] setStroke];
        NSFrameRect(local);
        if (entry) {
            NSString *label = engine.compactEntryTitle;
            NSDictionary *attributes = @{NSFontAttributeName: [engine compactEntryFont],
                                         NSForegroundColorAttributeName: NSColor.whiteColor};
            NSSize textSize = [label sizeWithAttributes:attributes];
            [label drawAtPoint:NSMakePoint(NSMinX(local) + MAX(2, (NSWidth(local) - textSize.width) / 2),
                                           NSMinY(local) + MAX(2, (NSHeight(local) - textSize.height) / 2))
                withAttributes:attributes];
        }
    }
    [image unlockFocus];
    SaveCanvas(image, path);
}

static void TestScreenshots(void) {
    if (gOutputDirectory.length == 0) { return; }
    [[NSFileManager defaultManager] createDirectoryAtPath:gOutputDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    // 现场复现夹具（与 TestFieldLikeSceneReproduction 同一份几何）：
    // 修好后这里能看到正文自身范围内的「查看译文」入口；未修版本这里是空的（Unplaceable）。
    NSMutableArray<FYInlineTextLine *> *lines = [@[
        Line(@"CHARRACTER", CGRectMake(0.043, 0.864, 0.392, 0.092)),
        Line(@"桜井 琉夏", CGRectMake(0.775, 0.904, 0.130, 0.055)),
        Line(@"RUKA SAKURAI", CGRectMake(0.775, 0.845, 0.165, 0.030)),
        Line(@"Birthday", CGRectMake(0.700, 0.810, 0.104, 0.047)),
        Line(@"Horoscope", CGRectMake(0.700, 0.715, 0.132, 0.040)),
        Line(@"かに座", CGRectMake(0.897, 0.683, 0.080, 0.044)),
        Line(@"• 型", CGRectMake(0.918, 0.580, 0.058, 0.050)),
        Line(@"電話", CGRectMake(0.515, 0.456, 0.049, 0.047)),
        Line(@"みよのメモ", CGRectMake(0.180, 0.426, 0.098, 0.038)),
        Line(@"身長", CGRectMake(0.513, 0.388, 0.050, 0.047)),
        Line(@"◆桜井琉夏の好み◆", CGRectMake(0.178, 0.361, 0.180, 0.038)),
        Line(@"体重", CGRectMake(0.513, 0.317, 0.050, 0.053)),
        Line(@"バイト", CGRectMake(0.515, 0.263, 0.070, 0.041)),
        Line(@"花屋アンネリー", CGRectMake(0.608, 0.263, 0.168, 0.041)),
        Line(@"クラブ", CGRectMake(0.517, 0.201, 0.070, 0.041)),
        Line(@"帰宅部\n桜井琥一の弟。\nスリルは彼の活力。", CGRectMake(0.608, 0.079, 0.204, 0.164)),
        Line(@"備考", CGRectMake(0.515, 0.130, 0.048, 0.047)),
        Line(@"プロフィールを見る", CGRectMake(0.010, 0.003, 0.182, 0.036)),
        Line(@"校内でスリリングなことばかりしている彼は、", CGRectMake(0.178, 0.330, 0.340, 0.026)),
        Line(@"アクティブで好奇心旺盛。退屈を嫌い、", CGRectMake(0.178, 0.304, 0.335, 0.026)),
        Line(@"いつも何か新しいことに挑戦している。", CGRectMake(0.178, 0.278, 0.338, 0.026)),
        Line(@"スリルを求めて行動するのが好きで、", CGRectMake(0.178, 0.252, 0.330, 0.026)),
        Line(@"じっとしているのは苦手なのだ。", CGRectMake(0.178, 0.226, 0.300, 0.026)),
        Line(@"カレーライスが大好物", CGRectMake(0.190, 0.196, 0.190, 0.024)),
        Line(@"右側の短い見出し", CGRectMake(0.530, 0.310, 0.100, 0.035))
    ] mutableCopy];
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    NSArray<FYInlineLayoutRequest *> *requests = nil;
    FYInlineLayoutResult *result = RunScene(engine, lines, ProfileViewport(), &requests);
    NSString *path = [gOutputDirectory stringByAppendingPathComponent:@"longbody-scene.png"];
    // 对照证据：目标正文的原文框、长卡尺寸、入口尺寸、最终状态。
    CGRect sourceFrame = CGRectZero;
    for (FYInlineLayoutRequest *request in requests) {
        if ([request.block.text containsString:kBodyNeedle]) { sourceFrame = request.sourceFrame; }
    }
    for (FYInlinePlacement *placement in result.placements) {
        if (![placement.block.text containsString:kBodyNeedle]) { continue; }
        NSLog(@"GEOMETRY-EVIDENCE bodySrc=(%.0f,%.0f,%.0f,%.0f) longCard=%.0fx%.0f compactEntry=%.0fx%.0f mode=%ld frame=%@",
              sourceFrame.origin.x, sourceFrame.origin.y, sourceFrame.size.width, sourceFrame.size.height,
              placement.longCardSize.width, placement.longCardSize.height,
              placement.compactEntrySize.width, placement.compactEntrySize.height,
              (long)placement.mode, NSStringFromRect(placement.translationFrame));
    }
    DrawResult(engine, requests, result, ProfileViewport(), path);
    Check([[NSFileManager defaultManager] fileExistsAtPath:path], @"写出长正文场景对照图（原文框 + 最终贴译位置）");
}

#pragma mark - main

@interface CleanSourceOCRApp : AppDelegate
@property(nonatomic, copy) NSArray<OCRTextItem *> *fixture;
@end
@implementation CleanSourceOCRApp
- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fast
                                    languageSegment:(NSInteger)language error:(NSError **)error { return self.fixture; }
@end

static void TestSourceTextSurvivesIdenticalTranslations(void) {
    CleanSourceOCRApp *app = [CleanSourceOCRApp new];
    NSArray *texts = @[@"4月12日（日）", @"学力", @"1年目"];
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < texts.count; i++) {
        OCRTextItem *item = [OCRTextItem new]; item.text = texts[i];
        item.boundingBox = CGRectMake(.1+i*.25, .8, .2, .05); [items addObject:item];
        app.inlineTranslationCache[texts[i]] = texts[i];
    }
    app.fixture = items;
    for (NSInteger frame = 0; frame < 6; frame++) {
        NSArray *blocks = nil;
        NSString *text = [app recognizeTextBlocksInImage:NULL fastOCR:NO languageSegment:0 blocks:&blocks error:NULL];
        Check(blocks.count == texts.count && [text containsString:@"4月12日（日）"] && [text containsString:@"学力"],
              @"干净采集源中的日期与同形汉字不会因为已经翻译过而被删");
    }
}

static void TestBracketedFieldDoesNotAbsorbBackground(void) {
    // 22:21 实机日志：动画背景上的「クラ」间歇出现，旧分组把日期中的括号
    // 当成正文句读证据，导致日期译文在单行与两行之间反复变化。
    for (NSString *date in @[@"4月12日（日）", @"予定（未定）", @"【ステータス】"]) {
        NSArray *blocks = Group(@[
            Line(date, CGRectMake(.7017, .9201, .1967, .0533)),
            Line(@"クラ", CGRectMake(.8133, .8225, .0333, .0267))
        ]);
        Check(blocks.count == 2 && [((FYInlineTextBlock *)blocks.firstObject).text isEqualToString:date],
              @"括号字段与较远的背景短字保持独立");
    }
    NSArray *prose = Group(@[
        Line(@"桜井琥一の弟。", CGRectMake(.6098, .1296, .1539, .0509)),
        Line(@"スリルは彼の活力。", CGRectMake(.6095, .0791, .2028, .0618))
    ]);
    Check(prose.count == 1, @"真正的连续备注仍组成一个段落");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        unsetenv("FUYI_DIAG");
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if (argc > 1) { gOutputDirectory = [NSString stringWithUTF8String:argv[1]]; }

        TestProfileSceneGetsEntry();
        TestEntryWidthIndependentOfCardWidth();
        TestCrowdedSceneKeepsEntry();
        TestFieldLikeSceneReproduction();
        TestFieldFrameRealScene();
        TestProfileFieldGroupingUnderOCRJitter();
        TestProfileRowsWithoutRecognizedLabels();
        TestBracketedFieldDoesNotAbsorbBackground();
        TestSourceTextSurvivesIdenticalTranslations();
        TestCombinedVisionObservationUsesSeparateFieldRows();
        TestDecoratedProfileValueKeepsSeparateTranslation();
        TestCompactProseIsNotAMenu();
        TestFieldSpaceDoesNotDependOnTextKind();
        TestProfileRemarksAcrossCharactersAndViewports();
        TestMultilineShortBlockStillGetsEntry();
        TestTinyViewportKeepsEverythingListed();
        TestDuplicateOCRBoxIsNotAFalseConflict();
        TestLongCardStillUsedWhenThereIsRoom();
        TestAppCompactEntryShowsAndExpands();
        TestAppUnplaceableStaysInListAndStatus();
        TestAppShortBlockEntryRendersAsCard();
        TestScreenshots();

        Require(gFailures == 0, [NSString stringWithFormat:@"%lu 条断言失败", (unsigned long)gFailures]);
        printf("PASS InlineLongBodyEntryTests: %lu 条断言；长正文紧凑入口按内容测量 / 正文内落位 / 拥挤与极小区域 / 重复框假冲突 / 点击展开 / 集中列表\n",
               (unsigned long)gChecks);
    }
    return 0;
}
