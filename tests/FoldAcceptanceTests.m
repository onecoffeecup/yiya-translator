// 折叠入口修复验收（2026-10-06 晚）
//
// 用户报的两个缺陷 + 一处重复块问题，本套件逐条验收：
//   ① 「明明有空间却收起」：长卡宽度过去只有一个候选、且被硬抬到最少 300pt。
//      现在按**有限候选组合**逐个尝试（宽度贴合原文/略宽/旧基准；修饰完整/紧凑；字号 19→17→15），
//      只有全部失败才给折叠入口。
//   ② 「还有 N 条译文」入口固定左下角、压住别的贴译。现在纳入统一避让（贴译面板 / 折叠入口 /
//      展开卡 / 字幕浮窗 / 画面边界 / 所有原文框），取第一个完全不相交的候选；文案改为单行。
//   ③ 重复块：ResolveOverlappingOCRItems 用「几何 + 双向文本覆盖率」删掉同一处的冗余合并读法，
//      同文不同位置绝不删。
//
// 全部走真实入口：showInlineTranslations / handleInlineTranslationResult / layoutRequests: /
// MergeRefinedOCRItems（产品 static 函数）/ buildInlineOverflowEntryForViewport: +
// positionInlineOverflowEntryInViewport: / refreshDisplayGeometryIfNeeded:。
// 夹具离线合成，不联网、不截屏真实内容。

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

#pragma mark - 夹具

static NSString *const kAccBodyNeedle = @"校内でスリリング";
static NSString *const kAccBodyTranslation = @"在校内总做些刺激的事，他活泼又好奇心旺盛。讨厌无聊，总是挑战新事物。喜欢追求惊险刺激，静不下来。";

/// 与 tests/InlineFoldReadTests.m 同一套真实接缝：几何可覆盖 + 面板真的可见（否则 isVisible 断言假阴性）。
@interface AccApp : AppDelegate
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *liveBounds;
@property (nonatomic) uint32_t fixtureTargetID;
@property (nonatomic) BOOL fixtureTargetUnavailable;
@property (nonatomic) NSUInteger translateCallCount;
@property (nonatomic, copy) NSArray<NSString *> *fixtureTranslations;
@end

@implementation AccApp
- (BOOL)translationTargetIsForeground { return !self.fixtureTargetUnavailable; }
- (BOOL)liveBoundsForWindowID:(uint32_t)windowID outBounds:(CGRect *)outBounds {
    NSValue *value = self.liveBounds[@(windowID)];
    if (!value) { return NO; }
    if (outBounds) { *outBounds = value.rectValue; }
    return YES;
}
- (uint32_t)resolveDisplayTargetWindowIDInWindowList:(NSArray<NSDictionary *> *)windowList
                                           ambiguous:(BOOL *)outAmbiguous
                                                note:(NSString **)outNote {
    if (outAmbiguous) { *outAmbiguous = NO; }
    if (self.fixtureTargetUnavailable) {
        if (outNote) { *outNote = @"测试：目标窗口暂时定位不到"; }
        return 0;
    }
    return self.fixtureTargetID;
}
- (void)translateInlineTextItems:(NSArray<OCRTextItem *> *)items
                      completion:(void (^)(NSArray<NSString *> *translations, NSError *error))completion {
    self.translateCallCount += 1;
    if (completion) { completion(self.fixtureTranslations ?: @[], nil); }
}
@end

static AccApp *AccFixtureApp(NSRect windowBounds) {
    AccApp *app = [[AccApp alloc] init];
    [app createMainWindow];
    app.inlineTranslationPanels = [NSMutableArray array];
    app.inlineLongCardPanels = [NSMutableArray array];
    app.inlineTranslationCache = [NSMutableDictionary dictionary];
    app.captionFontSizeSlider = [NSSlider sliderWithValue:30 minValue:12 maxValue:48 target:nil action:nil];
    app.captionOpacitySlider = [NSSlider sliderWithValue:0.58 minValue:0 maxValue:1 target:nil action:nil];
    WindowItem *window = [[WindowItem alloc] init];
    window.windowID = 9701;
    window.displayName = @"AccFixture";
    window.bounds = windowBounds;
    app.windows = [NSMutableArray arrayWithObject:window];
    app.windowPopup = [[NSPopUpButton alloc] init];
    [app.windowPopup addItemWithTitle:@"AccFixture"];
    app.windowPopup.menu.itemArray.firstObject.representedObject = @(9701);
    app.fixtureTargetID = 9701;
    app.fixtureTargetUnavailable = NO;
    app.liveBounds = [NSMutableDictionary dictionary];
    app.fixtureTranslations = @[];
    return app;
}

static OCRTextItem *AccItem(NSString *text, CGRect box, InlineBlockKind kind, NSArray<NSValue *> *lineBoxes) {
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

#pragma mark - 场景：244pt 宽的长正文 + 稀疏短块（「琉夏的喜好」式）

/// 现场映射出来的画面区域（约 1018×574）。
static NSRect AccViewport(void) { return NSMakeRect(457, 454, 1018, 574); }

/// 长正文：原文框 244×196pt；上下左右留出空间，只有标题在更上方。
static OCRTextItem *AccBodyItem(void) {
    NSArray<NSValue *> *lines = @[
        [NSValue valueWithRect:CGRectMake(0.20, 0.86, 0.24, 0.05)],
        [NSValue valueWithRect:CGRectMake(0.20, 0.80, 0.24, 0.05)],
        [NSValue valueWithRect:CGRectMake(0.20, 0.74, 0.24, 0.05)],
        [NSValue valueWithRect:CGRectMake(0.20, 0.68, 0.24, 0.05)],
        [NSValue valueWithRect:CGRectMake(0.20, 0.62, 0.24, 0.05)]
    ];
    return AccItem(@"校内でスリリングなことばかりしている彼は、\nアクティブで好奇心旺盛。退屈を嫌い、\nいつも何か新しいことに挑戦している。\nスリルを求めて行動するのが好きで、\nじっとしているのは苦手なのだ。",
                   CGRectMake(0.20, 0.62, 0.24, 0.29), InlineBlockKindLong, lines);
}

static OCRTextItem *AccBodyItemJittered(void) {
    OCRTextItem *item = AccBodyItem();
    CGRect box = item.boundingBox;
    box.origin.x += 0.0015;   // ≈1.5pt @1018
    box.origin.y -= 0.0015;
    OCRTextItem *jittered = AccItem(item.text, box, InlineBlockKindLong, item.lineBoxes);
    jittered.lineTexts = item.lineTexts;
    return jittered;
}

static NSArray<OCRTextItem *> *AccSparseItems(void) {
    return @[
        AccItem(@"◆桜井琉夏の好み◆", CGRectMake(0.20, 0.94, 0.18, 0.04), InlineBlockKindShort, nil),
        AccItem(@"身長", CGRectMake(0.70, 0.72, 0.05, 0.05), InlineBlockKindShort, nil),
        AccItem(@"体重", CGRectMake(0.70, 0.60, 0.05, 0.05), InlineBlockKindShort, nil),
        AccItem(@"戻る", CGRectMake(0.88, 0.06, 0.08, 0.05), InlineBlockKindShort, nil),
        AccBodyItem()
    ];
}

static NSArray<NSString *> *AccSparseTranslations(void) {
    return @[@"◆樱井琉夏的喜好◆", @"身高", @"体重", @"返回", kAccBodyTranslation];
}

/// 现场资料页（拥挤）：正文 219pt 宽、四周被短块占满 —— 长卡放不下，只能折叠。
static NSArray<OCRTextItem *> *AccCrowdedItems(void) {
    NSArray<NSValue *> *bodyLines = @[
        [NSValue valueWithRect:CGRectMake(0.178, 0.322, 0.215, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.296, 0.200, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.270, 0.205, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.244, 0.195, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.218, 0.170, 0.026)]
    ];
    return @[
        AccItem(@"◆桜井琉夏の好み◆", CGRectMake(0.178, 0.361, 0.180, 0.038), InlineBlockKindShort, nil),
        AccItem(@"身長", CGRectMake(0.513, 0.388, 0.050, 0.047), InlineBlockKindShort, nil),
        AccItem(@"体重", CGRectMake(0.513, 0.317, 0.050, 0.053), InlineBlockKindShort, nil),
        AccItem(@"バイト", CGRectMake(0.515, 0.263, 0.070, 0.041), InlineBlockKindShort, nil),
        AccItem(@"花屋アンネリー", CGRectMake(0.608, 0.263, 0.168, 0.041), InlineBlockKindShort, nil),
        AccItem(@"クラブ", CGRectMake(0.517, 0.201, 0.070, 0.041), InlineBlockKindShort, nil),
        AccItem(@"帰宅部\n桜井琥一の弟。\nスリルは彼の活力。", CGRectMake(0.608, 0.079, 0.204, 0.164), InlineBlockKindShort, nil),
        AccItem(@"みよのメモ", CGRectMake(0.180, 0.426, 0.098, 0.038), InlineBlockKindShort, nil),
        AccItem(@"校内でスリリングなことばかりしている彼は、\nアクティブで好奇心旺盛。退屈を嫌い、\nいつも何か新しいことに挑戦している。\nスリルを求めて行動するのが好きで、\nじっとしているのは苦手なのだ。",
                CGRectMake(0.178, 0.218, 0.215, 0.130), InlineBlockKindLong, bodyLines)
    ];
}

static NSArray<NSString *> *AccCrowdedTranslations(void) {
    // 短译文会贴合正文直接显示；这里用确实需要折叠的长译文验收入口。
    NSString *longBody = [NSString stringWithFormat:@"%@\n%@\n%@", kAccBodyTranslation, kAccBodyTranslation, kAccBodyTranslation];
    return @[@"◆樱井琉夏的喜好◆", @"身高", @"体重", @"打工", @"花店安妮莉", @"社团",
             @"回家部\n桜井琥一的弟弟。刺激是他的活力。", @"美代的笔记", longBody];
}

#pragma mark - 读取

static FYInlinePlacement *AccPlacementFor(AppDelegate *app, NSString *needle) {
    for (FYInlinePlacement *placement in app.lastInlineLayoutResult.placements) {
        if ([placement.block.text containsString:needle]) { return placement; }
    }
    return nil;
}

static NSArray<NSPanel *> *AccPanels(AccApp *app) {
    return [app.inlineTranslationPanels arrayByAddingObjectsFromArray:app.inlineLongCardPanels];
}

static NSPanel *AccPanelForBlockID(AccApp *app, NSString *blockID) {
    if (blockID.length == 0) { return nil; }
    for (NSPanel *panel in AccPanels(app)) {
        if ([panel.identifier isEqualToString:blockID]) { return panel; }
    }
    return nil;
}

static NSScrollView *AccScrollOf(NSView *view) {
    for (NSView *child in view.subviews) {
        if ([child isKindOfClass:NSScrollView.class]) { return (NSScrollView *)child; }
    }
    return nil;
}

static NSTextField *AccTitleLabel(FYInlineLongCardView *card) {
    for (NSView *sub in card.subviews) {
        if (![sub isKindOfClass:NSTextField.class]) { continue; }
        NSTextField *label = (NSTextField *)sub;
        if (label == card.foldedEntryHintLabel || label == card.foldedEntryActionLabel ||
            label == card.expandedFooterLabel) { continue; }
        return label;
    }
    return nil;
}

static void AccCollectButtons(NSView *view, NSMutableArray<NSButton *> *buttons) {
    if ([view isKindOfClass:NSButton.class]) { [buttons addObject:(NSButton *)view]; }
    for (NSView *child in view.subviews) { AccCollectButtons(child, buttons); }
}

/// 一块正文「卡片是否被截断」的判定：要么一屏放得下，要么可滚动且视口至少三行。
static BOOL AccBodyReadable(FYInlinePlacement *placement) {
    if (placement.scrollable) {
        NSFont *font = placement.font;
        if (!font) { return NO; }
        CGFloat lineHeight = ceil(font.ascender - font.descender + font.leading) + placement.paragraphStyle.lineSpacing;
        return placement.bodyViewportHeight + 0.5 >= lineHeight * 3.0;
    }
    return placement.measuredContentHeight <= placement.bodyViewportHeight + 0.5;
}

#pragma mark - 1. 「琉夏的喜好」式场景：有空间就不折叠

static void TestLongBodyKeepsCard(void) {
    AccApp *app = AccFixtureApp(AccViewport());
    [app showInlineTranslations:AccSparseTranslations() forItems:AccSparseItems() placementRect:AccViewport()];
    FYInlinePlacement *placement = AccPlacementFor(app, kAccBodyNeedle);
    Check(placement != nil, @"有空间：长正文块有排版结果");
    if (!placement) { return; }
    Check(placement.mode == FYInlineDisplayModeFullCard || placement.mode == FYInlineDisplayModeScrollingCard,
          [NSString stringWithFormat:@"有空间：长正文以长卡显示（mode=%ld，原因：%@）", (long)placement.mode, placement.reason]);
    Check(!placement.compactEntry, @"有空间：不是折叠入口");
    Check(placement.mode != FYInlineDisplayModeUnplaceable, @"有空间：也不是「暂不可放置」");

    CGFloat available = MIN(MAX((CGFloat)200, NSWidth(AccViewport()) - 24), app.inlineLayoutEngine.cardMaxWidth);
    Check(NSWidth(placement.translationFrame) <= available + 0.5 && NSWidth(placement.translationFrame) >= 160,
          [NSString stringWithFormat:@"有空间：卡片宽 %.0f 在 [160, %.0f] 内（不再硬抬到 300）",
           NSWidth(placement.translationFrame), available]);
    Check(placement.chosenBodyFontSize >= 15 && placement.chosenBodyFontSize <= 19,
          [NSString stringWithFormat:@"有空间：采用字号 %.0f 在 15…19 之间", placement.chosenBodyFontSize]);
    Check(AccBodyReadable(placement),
          [NSString stringWithFormat:@"有空间：正文可读（滚动=%@，视口高 %.0f，文档高 %.0f）",
           placement.scrollable ? @"是" : @"否", placement.bodyViewportHeight, placement.measuredContentHeight]);

    NSPanel *panel = AccPanelForBlockID(app, placement.blockID);
    Check(panel != nil && [panel.contentView isKindOfClass:FYInlineLongCardView.class],
          @"有空间：长卡面板真的创建出来了");
    if (panel) {
        Check(!((FYInlineLongCardView *)panel.contentView).compactEntry, @"有空间：面板不是折叠入口卡片");
        Check(panel.isVisible, @"有空间：长卡显示在画面上");
    }
}

#pragma mark - 2. 短译文不折叠 / 极小原文区域必须给入口

static void TestShortTranslationLargeAreaStaysCard(void) {
    NSRect viewport = AccViewport();
    AccApp *app = AccFixtureApp(viewport);
    OCRTextItem *shortBody = AccItem(@"プロフィールを見る", CGRectMake(0.20, 0.60, 0.40, 0.12), InlineBlockKindLong, nil);
    [app showInlineTranslations:@[@"查看个人资料"] forItems:@[shortBody] placementRect:viewport];
    FYInlinePlacement *placement = app.lastInlineLayoutResult.placements.firstObject;
    Check(placement != nil, @"短译文：有排版结果");
    if (!placement) { return; }
    Check(placement.mode == FYInlineDisplayModeFullCard,
          [NSString stringWithFormat:@"短译文+大原文区域：给完整长卡、不折叠（mode=%ld）", (long)placement.mode]);
    Check(!placement.compactEntry && placement.mode != FYInlineDisplayModeUnplaceable, @"短译文：既没折叠也没消失");
}

static void TestTinySourceAreaStillGetsEntry(void) {
    // 拥挤资料页：正文原文区域相对译文很小，长卡确实放不下 → 必须给折叠入口，绝不 Unplaceable。
    AccApp *app = AccFixtureApp(AccViewport());
    [app showInlineTranslations:AccCrowdedTranslations() forItems:AccCrowdedItems() placementRect:AccViewport()];
    FYInlinePlacement *placement = AccPlacementFor(app, kAccBodyNeedle);
    Check(placement != nil, @"极小原文区域：长正文块有排版结果");
    if (!placement) { return; }
    Check(placement.mode != FYInlineDisplayModeUnplaceable,
          [NSString stringWithFormat:@"极小原文区域：不消失（mode=%ld，原因：%@）", (long)placement.mode, placement.reason]);
    Check(placement.mode == FYInlineDisplayModeCompactEntry,
          [NSString stringWithFormat:@"极小原文区域：允许折叠，但必须是折叠入口（mode=%ld）", (long)placement.mode]);
    if (placement.mode == FYInlineDisplayModeCompactEntry) {
        Check(placement.compactEntry, @"极小原文区域：placement.compactEntry == YES");
        NSPanel *panel = AccPanelForBlockID(app, placement.blockID);
        Check(panel != nil && [(FYInlineLongCardView *)panel.contentView compactEntry],
              @"极小原文区域：确实渲染成折叠入口卡片");
        CGSize measured = [app.inlineLayoutEngine foldedEntrySizeForViewport:AccViewport()
                                                                      title:placement.entryTitle
                                                                       hint:placement.entryHint];
        Check(fabs(NSWidth(placement.translationFrame) - measured.width) < 1.5 &&
              fabs(NSHeight(placement.translationFrame) - measured.height) < 1.5,
              @"极小原文区域：入口尺寸仍是按内容测量");
    }
}

#pragma mark - 3. 重复块：几何 + 文本双证据

static void TestDuplicateBlockResolution(void) {
    // ① 一个跨两行的合并块 + 它的两行各自的逐行块（框正好合起来盖满合并块）。
    OCRTextItem *line1 = AccItem(@"校内でスリリングなことばかり", CGRectMake(0.10, 0.60, 0.60, 0.06), InlineBlockKindShort, nil);
    OCRTextItem *line2 = AccItem(@"している彼は、アクティブで", CGRectMake(0.10, 0.54, 0.60, 0.06), InlineBlockKindShort, nil);
    OCRTextItem *merged = AccItem(@"校内でスリリングなことばかり している彼は、アクティブで",
                                  CGRectMake(0.10, 0.54, 0.60, 0.12), InlineBlockKindLong, nil);
    NSArray<OCRTextItem *> *resolved = MergeRefinedOCRItems(@[merged, line1, line2], @[]);
    Check(resolved.count == 2, [NSString stringWithFormat:@"重复块：去重后只剩逐行块 2 块（实际 %lu）", (unsigned long)resolved.count]);
    BOOL hasMerged = NO, hasLine1 = NO, hasLine2 = NO;
    for (OCRTextItem *item in resolved) {
        if ([item.text containsString:@"校内でスリリングなことばかり している"]) { hasMerged = YES; }
        if ([item.text containsString:@"校内でスリリングなことばかり"]) { hasLine1 = YES; }
        if ([item.text containsString:@"している彼は、アクティブで"]) { hasLine2 = YES; }
    }
    Check(!hasMerged, @"重复块：冗余的合并读法被删掉");
    Check(hasLine1 && hasLine2, @"重复块：两行逐行块都保留");

    // ② 同文不同位置：框不互相包含，绝不误删。
    OCRTextItem *top = AccItem(@"同じテキストです", CGRectMake(0.10, 0.80, 0.30, 0.06), InlineBlockKindShort, nil);
    OCRTextItem *bottom = AccItem(@"同じテキストです", CGRectMake(0.10, 0.20, 0.30, 0.06), InlineBlockKindShort, nil);
    NSArray<OCRTextItem *> *sameText = MergeRefinedOCRItems(@[top, bottom], @[]);
    Check(sameText.count == 2, [NSString stringWithFormat:@"重复块：同文不同位置两块都保留（实际 %lu）", (unsigned long)sameText.count]);

    // ③ 真实入口也走一遍：App 的合并路径不吞掉另一处的同文块。
    AccApp *app = AccFixtureApp(AccViewport());
    NSArray<OCRTextItem *> *viaApp = [app mergedInlineTextItemsFromItems:@[top, bottom]];
    Check(viaApp.count == 2, [NSString stringWithFormat:@"重复块：mergedInlineTextItemsFromItems: 也保留两块（实际 %lu）",
                             (unsigned long)viaApp.count]);
}

#pragma mark - 4. 总入口不再压住别的贴译

static void TestOverflowEntryAvoidsExistingPanel(void) {
    NSRect viewport = AccViewport();
    AccApp *app = AccFixtureApp(viewport);

    // 现场复现：先有一条真实的「查看个人资料」贴片，位置就是快照里那个。
    NSRect chipFrame = NSMakeRect(467, 481, 120, 36);
    NSPanel *chip = [[NSPanel alloc] initWithContentRect:chipFrame
                                               styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    chip.ignoresMouseEvents = NO;
    [app.inlineTranslationPanels addObject:chip];
    [chip orderFrontRegardless];   // 真实可见的贴片才会进入避让障碍集合
    Check(chip.isVisible, @"总入口避让：对照贴片已显示（否则避让无从谈起）");

    app.inlineOverflowCount = 3;
    [app buildInlineOverflowEntryForViewport:viewport];
    [app positionInlineOverflowEntryInViewport:viewport];
    [app.inlineOverflowPanel orderFrontRegardless];   // 真实路径里由 updateInlineOverflowEntry… 负责显示
    Check(app.inlineOverflowPanel != nil && app.inlineOverflowPanel.isVisible,
          @"总入口避让：总入口面板已建立并显示");
    if (!app.inlineOverflowPanel) { return; }
    NSRect overflow = app.inlineOverflowPanel.frame;
    CGRect hit = CGRectIntersection(chip.frame, overflow);
    CGFloat overlapArea = CGRectIsNull(hit) ? 0 : hit.size.width * hit.size.height;
    Check(overlapArea <= 0.5,
          [NSString stringWithFormat:@"总入口避让：与「查看个人资料」贴片不相交（贴片 %@ / 入口 %@ / 交叠面积 %.1f）",
           NSStringFromRect(chip.frame), NSStringFromRect(overflow), overlapArea]);
    Check(NSMinX(overflow) >= NSMinX(viewport) - 0.5 && NSMaxX(overflow) <= NSMaxX(viewport) + 0.5 &&
          NSMinY(overflow) >= NSMinY(viewport) - 0.5 && NSMaxY(overflow) <= NSMaxY(viewport) + 0.5,
          [NSString stringWithFormat:@"总入口避让：入口仍完整落在画面内（%@）", NSStringFromRect(overflow)]);

    // 真实路径：极小画面里既有其它可见贴译、又有放不下的长正文 → 总入口和它们都不相交。
    NSRect denseViewport = NSMakeRect(0, 0, 340, 220);
    AccApp *dense = AccFixtureApp(denseViewport);
    [dense showInlineTranslations:@[kAccBodyTranslation,
                                    @"喜欢追求惊险刺激，静不下来。喜欢大海和兜风。",
                                    @"返回"]
                         forItems:@[AccItem(@"校内でスリリングなことばかりしている彼は、\nアクティブで好奇心旺盛。退屈を嫌い、\nいつも何か新しいことに挑戦している。",
                                            CGRectMake(0.04, 0.42, 0.92, 0.30), InlineBlockKindLong, nil),
                                    AccItem(@"スリルを求めて行動するのが好きで、\nじっとしているのは苦手なのだ。\n海とドライブが大好きです。",
                                            CGRectMake(0.04, 0.06, 0.92, 0.30), InlineBlockKindLong, nil),
                                    AccItem(@"戻る", CGRectMake(0.78, 0.88, 0.16, 0.08), InlineBlockKindShort, nil)]
                    placementRect:denseViewport];
    NSUInteger denseVisible = 0;
    for (NSPanel *panel in AccPanels(dense)) { if (panel.isVisible) { denseVisible += 1; } }
    NSLog(@"DIAGNOSTIC 极小画面：placements=%lu unplaceable=%lu compactEntry=%lu overflow=%lu visiblePanels=%lu",
          (unsigned long)dense.lastInlineLayoutResult.placements.count,
          (unsigned long)dense.lastInlineUnplaceableCount,
          (unsigned long)dense.lastInlineCompactEntryCount,
          (unsigned long)dense.inlineOverflowCount, (unsigned long)denseVisible);
    Check(denseVisible >= 1,
          [NSString stringWithFormat:@"总入口避让：真实路径里至少有 1 条可见贴译（%lu）", (unsigned long)denseVisible]);
    if (dense.inlineOverflowPanel) {
        NSRect overflowFrame = dense.inlineOverflowPanel.frame;
        CGFloat worst = 0;
        for (NSPanel *panel in AccPanels(dense)) {
            if (!panel.isVisible) { continue; }
            CGRect intersection = CGRectIntersection(panel.frame, overflowFrame);
            if (!CGRectIsNull(intersection)) { worst = MAX(worst, intersection.size.width * intersection.size.height); }
        }
        Check(worst <= 0.5,
              [NSString stringWithFormat:@"总入口避让：真实路径下与所有可见贴译不相交（最大交叠 %.1f）", worst]);
    } else {
        Check(dense.lastInlineCompactEntryCount >= 1,
              @"总入口避让：没有总入口时，长正文必须至少拿到折叠入口（不静默消失）");
    }
}

#pragma mark - 5. 极端拥挤：仍然有可发现的阅读路径

static void TestCrowdedTinyKeepsReadingPath(void) {
    NSRect viewport = NSMakeRect(0, 0, 260, 150);
    AccApp *app = AccFixtureApp(viewport);
    NSArray<OCRTextItem *> *items = @[
        AccItem(@"校内でスリリングなことばかりしている彼は、\nアクティブで好奇心旺盛。退屈を嫌い、\nいつも何か新しいことに挑戦している。",
                CGRectMake(0.04, 0.42, 0.92, 0.30), InlineBlockKindLong, nil),
        AccItem(@"スリルを求めて行動するのが好きで、\nじっとしているのは苦手なのだ。\n海とドライブが大好きです。",
                CGRectMake(0.04, 0.06, 0.92, 0.30), InlineBlockKindLong, nil),
        AccItem(@"その他のかなり長い説明文がここに続きます。\n読み飛ばさないでください。",
                CGRectMake(0.30, 0.66, 0.66, 0.22), InlineBlockKindLong, nil)
    ];
    [app showInlineTranslations:@[kAccBodyTranslation,
                                  @"喜欢追求惊险刺激，静不下来。喜欢大海和兜风。",
                                  @"其它的长说明文在这里继续，请不要跳过。"]
                       forItems:items
                  placementRect:viewport];
    NSUInteger visible = 0, entries = 0, unplaceable = 0;
    for (FYInlinePlacement *placement in app.lastInlineLayoutResult.placements) {
        if (placement.mode == FYInlineDisplayModeUnplaceable) { unplaceable += 1; continue; }
        visible += 1;
        if (placement.mode == FYInlineDisplayModeCompactEntry) { entries += 1; }
    }
    Check(visible + unplaceable == items.count,
          [NSString stringWithFormat:@"极端拥挤：每块都有结论（可见 %lu + 放不下 %lu = %lu）",
           (unsigned long)visible, (unsigned long)unplaceable, (unsigned long)items.count]);
    Check(visible >= 1 || app.inlineOverflowPanel != nil,
          [NSString stringWithFormat:@"极端拥挤：至少有一个可发现的阅读路径（可见 %lu / 总入口 %@）",
           (unsigned long)visible, app.inlineOverflowPanel ? @"有" : @"无"]);
    Check(visible + app.inlineOverflowCount == items.count,
          [NSString stringWithFormat:@"极端拥挤：画面上的贴译/入口 + 总入口清单覆盖全部 %lu 块（%lu + %lu）",
           (unsigned long)items.count, (unsigned long)visible, (unsigned long)app.inlineOverflowCount]);
    Check(app.inlineOverflowCount == unplaceable && app.inlineOverflowEntries.count == unplaceable,
          [NSString stringWithFormat:@"极端拥挤：放不下的 %lu 块都进了总入口清单", (unsigned long)unplaceable]);
    NSLog(@"DIAGNOSTIC 极端拥挤：可见 %lu（其中折叠入口 %lu）放不下 %lu 总入口 %lu",
          (unsigned long)visible, (unsigned long)entries, (unsigned long)unplaceable,
          (unsigned long)app.inlineOverflowCount);
}

#pragma mark - 6. 抖动 / 换页 / 几何切换的稳定性

static void TestStabilityAcrossJitterPageAndGeometry(void) {
    AccApp *app = AccFixtureApp(AccViewport());
    [app showInlineTranslations:AccSparseTranslations() forItems:AccSparseItems() placementRect:AccViewport()];
    FYInlinePlacement *before = AccPlacementFor(app, kAccBodyNeedle);
    Check(before != nil, @"稳定性：第一帧长正文有排版结果");
    if (!before) { return; }
    NSUInteger variantBefore = before.chosenVariant;
    CGFloat fontSizeBefore = before.chosenBodyFontSize;
    FYInlineDisplayMode modeBefore = before.mode;
    NSString *blockIDBefore = before.blockID;

    // ±1.5pt 抖动重排：chosenVariant / 字号 / 折叠状态不变。
    NSMutableArray<OCRTextItem *> *jittered = [AccSparseItems() mutableCopy];
    jittered[jittered.count - 1] = AccBodyItemJittered();
    [app showInlineTranslations:AccSparseTranslations() forItems:jittered placementRect:AccViewport()];
    FYInlinePlacement *after = AccPlacementFor(app, kAccBodyNeedle);
    Check(after != nil, @"稳定性：抖动后仍有排版结果");
    if (after) {
        Check(after.chosenVariant == variantBefore,
              [NSString stringWithFormat:@"稳定性：抖动后候选序号不变（%lu → %lu）",
               (unsigned long)variantBefore, (unsigned long)after.chosenVariant]);
        Check(fabs(after.chosenBodyFontSize - fontSizeBefore) < 0.01,
              [NSString stringWithFormat:@"稳定性：抖动后字号不变（%.0f → %.0f）", fontSizeBefore, after.chosenBodyFontSize]);
        Check(after.mode == modeBefore, @"稳定性：抖动后折叠状态不变");
        Check([after.blockID isEqualToString:blockIDBefore], @"稳定性：抖动后稳定块身份不变");
    }

    // 换页：clear + 新场景 → 旧面板不残留。
    [app clearInlineTranslationPanels];
    Check(app.inlineTranslationPanels.count == 0 && app.inlineLongCardPanels.count == 0,
          @"换页：清画面后没有残留面板");
    Check(AccPanelForBlockID(app, blockIDBefore) == nil, @"换页：旧块面板已移除");
    OCRTextItem *newBlock = AccItem(@"別の画面の長い説明文です。\n二行目の続きです。\n三行目の終わりです。",
                                    CGRectMake(0.55, 0.15, 0.30, 0.20), InlineBlockKindLong, nil);
    [app showInlineTranslations:@[@"另一个页面的长说明文。第二行继续。第三行结束。"]
                       forItems:@[newBlock]
                  placementRect:AccViewport()];
    Check(app.lastInlineLayoutResult.placements.count == 1, @"换页：新场景只有一块");
    Check(AccPanelForBlockID(app, blockIDBefore) == nil, @"换页：旧块面板没有随着新场景复活");

    // 几何切换：目标窗口移动/缩小后，贴译落到新区域内。
    AccApp *moving = AccFixtureApp(AccViewport());
    [moving showInlineTranslations:AccSparseTranslations() forItems:AccSparseItems() placementRect:AccViewport()];
    Check(AccPlacementFor(moving, kAccBodyNeedle) != nil, @"几何切换：初始场景有贴译");
    CGRect movedBounds = CGRectMake(200, 80, 660, 420);
    moving.liveBounds[@(moving.fixtureTargetID)] = [NSValue valueWithRect:NSRectFromCGRect(movedBounds)];
    [moving refreshDisplayGeometryIfNeeded:YES];
    NSRect newViewport = [moving appKitFrameForWindowItem:moving.windows.firstObject];
    [moving showInlineTranslations:AccSparseTranslations() forItems:AccSparseItems() placementRect:newViewport];
    BOOL allInside = YES;
    NSUInteger visibleCount = 0;
    for (NSPanel *panel in AccPanels(moving)) {
        if (!panel.isVisible) { continue; }
        visibleCount += 1;
        if (!NSContainsRect(NSInsetRect(newViewport, -1, -1), panel.frame)) { allInside = NO; }
    }
    Check(visibleCount >= 1 && allInside,
          [NSString stringWithFormat:@"几何切换：重排后 %lu 个可见贴译都落在新画面区域内", (unsigned long)visibleCount]);
    // 每个仍有位置的块（含折叠入口）都必须落在新画面区域内，不能停在旧坐标。
    BOOL everyFrameInside = YES;
    for (FYInlinePlacement *placement in moving.lastInlineLayoutResult.placements) {
        if (CGRectIsEmpty(placement.translationFrame)) { continue; }
        if (!NSContainsRect(NSInsetRect(newViewport, -1, -1), placement.translationFrame)) { everyFrameInside = NO; }
    }
    Check(everyFrameInside, @"几何切换：所有有位置的块（含入口）都落在新画面区域内");
    FYInlinePlacement *movedBody = AccPlacementFor(moving, kAccBodyNeedle);
    NSLog(@"DIAGNOSTIC 几何切换：正文 mode=%ld 字号=%.0f 卡=%@ 区域=%@",
          (long)(movedBody ? movedBody.mode : -1), movedBody ? movedBody.chosenBodyFontSize : -1,
          movedBody ? NSStringFromRect(movedBody.translationFrame) : @"(nil)", NSStringFromRect(newViewport));
}

#pragma mark - 7. 可读性：测量与绘制同一口径

static void TestReadabilityMatchesMeasurement(void) {
    AccApp *app = AccFixtureApp(AccViewport());
    [app showInlineTranslations:AccSparseTranslations() forItems:AccSparseItems() placementRect:AccViewport()];
    FYInlinePlacement *placement = AccPlacementFor(app, kAccBodyNeedle);
    Check(placement != nil && placement.mode != FYInlineDisplayModeCompactEntry,
          @"可读性：用的是长卡而不是折叠入口");
    if (!placement || placement.mode == FYInlineDisplayModeCompactEntry) { return; }
    Check(placement.font != nil && fabs(placement.font.pointSize - placement.chosenBodyFontSize) < 0.01,
          [NSString stringWithFormat:@"可读性：正文 font.pointSize %.1f == chosenBodyFontSize %.0f",
           placement.font.pointSize, placement.chosenBodyFontSize]);
    Check(placement.chosenBodyFontSize >= app.inlineLayoutEngine.minimumLongBodyFontSize,
          [NSString stringWithFormat:@"可读性：字号 %.0f ≥ 下限 %.0f",
           placement.chosenBodyFontSize, app.inlineLayoutEngine.minimumLongBodyFontSize]);
    Check(placement.paragraphStyle != nil &&
          fabs(placement.paragraphStyle.lineSpacing - app.inlineLayoutEngine.longLineSpacing) < 0.01,
          [NSString stringWithFormat:@"可读性：段落行距 %.1f == 引擎 longLineSpacing %.1f",
           placement.paragraphStyle.lineSpacing, app.inlineLayoutEngine.longLineSpacing]);
    Check(fabs(NSWidth(placement.bodyViewportFrame) -
               (NSWidth(placement.translationFrame) - 2 * placement.panelPadding)) < 0.5,
          [NSString stringWithFormat:@"可读性：正文视口宽 %.0f == 卡宽 %.0f − 2×内边距 %.0f",
           NSWidth(placement.bodyViewportFrame), NSWidth(placement.translationFrame), placement.panelPadding]);

    NSPanel *panel = AccPanelForBlockID(app, placement.blockID);
    NSScrollView *scroll = panel ? AccScrollOf(panel.contentView) : nil;
    Check(scroll != nil, @"可读性：长卡上有真实滚动区");
    if (scroll) {
        Check(NSEqualRects(NSIntegralRect(scroll.frame), NSIntegralRect(placement.bodyViewportFrame)),
              [NSString stringWithFormat:@"可读性：绘制用的滚动区 %@ == 布局测量 %@",
               NSStringFromRect(scroll.frame), NSStringFromRect(placement.bodyViewportFrame)]);
    }
}

#pragma mark - 8. 诊断：试过哪些候选、为什么折叠

static void TestVariantDiagnostics(void) {
    AccApp *app = AccFixtureApp(AccViewport());
    [app showInlineTranslations:AccSparseTranslations() forItems:AccSparseItems() placementRect:AccViewport()];
    FYInlinePlacement *card = AccPlacementFor(app, kAccBodyNeedle);
    Check(card != nil && card.variantDiagnostics.count > 0,
          [NSString stringWithFormat:@"诊断：长卡记录了候选尝试（%lu 行）", (unsigned long)card.variantDiagnostics.count]);
    if (card) {
        BOOL hasCandidate = NO, hasWidth = NO, hasFont = NO;
        for (NSString *line in card.variantDiagnostics) {
            if ([line containsString:@"候选#"]) { hasCandidate = YES; }
            if ([line containsString:@"宽"]) { hasWidth = YES; }
            if ([line containsString:@"字号"]) { hasFont = YES; }
        }
        Check(hasCandidate && hasWidth && hasFont,
              @"诊断：候选记录里有宽度与字号（能看出试了哪一档）");
        NSLog(@"DIAGNOSTIC 长卡诊断：%@", [card.variantDiagnostics componentsJoinedByString:@" | "]);
    }

    AccApp *folded = AccFixtureApp(AccViewport());
    [folded showInlineTranslations:AccCrowdedTranslations() forItems:AccCrowdedItems() placementRect:AccViewport()];
    FYInlinePlacement *foldedPlacement = AccPlacementFor(folded, kAccBodyNeedle);
    Check(foldedPlacement != nil && foldedPlacement.mode == FYInlineDisplayModeCompactEntry,
          @"诊断：拥挤场景的正文确实折叠了");
    if (foldedPlacement && foldedPlacement.mode == FYInlineDisplayModeCompactEntry) {
        BOOL explainsFold = NO, namesConflict = NO;
        for (NSString *line in foldedPlacement.variantDiagnostics) {
            if ([line containsString:@"折叠（"]) { explainsFold = YES; }
            if ([line containsString:@"首个冲突："]) { namesConflict = YES; }
        }
        Check(explainsFold, @"诊断：折叠块写明「折叠（…）」的失败原因");
        Check(namesConflict, @"诊断：折叠块给出「首个冲突：…」");
        NSLog(@"DIAGNOSTIC 折叠诊断：%@", [foldedPlacement.variantDiagnostics componentsJoinedByString:@" | "]);
    }
}

#pragma mark - 9. 回归：折叠入口的基本交互仍在

static void TestFoldInteractionRegression(void) {
    AccApp *app = AccFixtureApp(AccViewport());
    [app showInlineTranslations:AccCrowdedTranslations() forItems:AccCrowdedItems() placementRect:AccViewport()];
    FYInlinePlacement *placement = AccPlacementFor(app, kAccBodyNeedle);
    Check(placement != nil && placement.mode == FYInlineDisplayModeCompactEntry, @"回归：拥挤场景给出折叠入口");
    if (!placement || placement.mode != FYInlineDisplayModeCompactEntry) { return; }
    NSPanel *panel = AccPanelForBlockID(app, placement.blockID);
    FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
    Check([card isKindOfClass:FYInlineLongCardView.class] && card.compactEntry, @"回归：入口是 compactEntry 卡片");
    NSString *hint = card.foldedEntryHintLabel.stringValue ?: @"";
    Check([hint isEqualToString:app.inlineLayoutEngine.foldedEntryHintTooLong] ||
          [hint isEqualToString:app.inlineLayoutEngine.foldedEntryHintCrowded],
          [NSString stringWithFormat:@"回归：收起原因三行文案仍在（%@）", hint]);
    NSString *action = card.foldedEntryActionLabel.stringValue ?: @"";
    Check([action containsString:@"点击展开"] && [action containsString:@"▾"],
          [NSString stringWithFormat:@"回归：动作行仍是「点击展开 ▾」（%@）", action]);
    Check(card.onClick != nil, @"回归：入口可点击");
    if (!card.onClick) { return; }

    NSUInteger hiddenOthers = 0, totalOthers = 0;
    card.onClick();
    Check(app.inlineExpandedReadingPanel != nil, @"回归：点击入口打开展开阅读卡");
    if (!app.inlineExpandedReadingPanel) { return; }
    for (NSPanel *other in AccPanels(app)) {
        totalOthers += 1;
        if (!other.isVisible && other.ignoresMouseEvents) { hiddenOthers += 1; }
    }
    Check(totalOthers >= 1 && hiddenOthers == totalOthers,
          [NSString stringWithFormat:@"回归：展开时其它贴译全部隐藏且不接收鼠标事件（%lu/%lu）",
           (unsigned long)hiddenOthers, (unsigned long)totalOthers]);
    FYInlineLongCardView *expanded = (FYInlineLongCardView *)app.inlineExpandedReadingPanel.contentView;
    NSScrollView *scroll = AccScrollOf(expanded);
    BOOL showsFull = NO;
    if ([scroll.documentView isKindOfClass:NSTextField.class]) {
        NSString *text = [(NSTextField *)scroll.documentView stringValue];
        showsFull = [text containsString:@"好奇心旺盛"] && [text containsString:@"静不下来"];
    }
    Check(showsFull, @"回归：展开卡里能读到完整译文");
    Check(expanded.expandedFooterLabel && [expanded.expandedFooterLabel.stringValue containsString:@"Esc 收起"],
          @"回归：展开卡底部提示仍有「Esc 收起」");
    Check(app.inlineExpandedReadingKeyMonitor != nil, @"回归：Esc 收起监视器已安装");
    NSButton *collapse = expanded.collapseButton;
    Check(collapse != nil && [collapse.title isEqualToString:@"收起"], @"回归：有可见「收起」按钮");
    [collapse performClick:nil];
    Check(app.inlineExpandedReadingPanel == nil, @"回归：点「收起」按钮后展开卡关闭");
    Check(app.inlineExpandedReadingKeyMonitor == nil, @"回归：收起后 Esc 监视器卸载");

    // 总入口文案：单行「还有 N 条译文 · 查看」。
    AccApp *overflowApp = AccFixtureApp(AccViewport());
    overflowApp.inlineOverflowCount = 4;
    [overflowApp buildInlineOverflowEntryForViewport:AccViewport()];
    FYInlineLongCardView *overflowCard = (FYInlineLongCardView *)overflowApp.inlineOverflowPanel.contentView;
    BOOL singleLineCopy = NO;
    NSMutableArray<NSString *> *overflowLabels = [NSMutableArray array];
    if ([overflowCard isKindOfClass:FYInlineLongCardView.class]) {
        NSTextField *title = AccTitleLabel(overflowCard);
        singleLineCopy = [title.stringValue containsString:@"还有 4 条译文"] && [title.stringValue containsString:@"查看"];
        for (NSView *sub in overflowCard.subviews) {
            if (![sub isKindOfClass:NSTextField.class]) { continue; }
            NSString *value = [(NSTextField *)sub stringValue];
            if (value.length > 0) { [overflowLabels addObject:value]; }
        }
    }
    Check(singleLineCopy, @"回归：总入口文案是单行「还有 N 条译文 · 查看」");
    NSLog(@"DIAGNOSTIC 总入口：尺寸=%@ 标签=%@",
          overflowApp.inlineOverflowPanel ? NSStringFromRect(overflowApp.inlineOverflowPanel.frame) : @"(nil)",
          [overflowLabels componentsJoinedByString:@" / "]);
}

#pragma mark - 截图

static void AccSaveCanvas(NSImage *image, NSString *path) {
    if (!image || path.length == 0) { return; }
    CGImageRef cg = [image CGImageForProposedRect:NULL context:NULL hints:NULL];
    if (!cg) { return; }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (png) { [png writeToFile:path atomically:YES]; }
}

static void AccDrawRect(NSRect rect, NSRect offset, NSColor *fill, NSColor *stroke, CGFloat width) {
    NSRect local = NSOffsetRect(rect, -NSMinX(offset), -NSMinY(offset));
    if (fill) {
        [fill setFill];
        NSRectFillUsingOperation(local, NSCompositingOperationSourceOver);
    }
    if (stroke) {
        [stroke setStroke];
        NSFrameRectWithWidth(local, width);
    }
}

/// 真实面板 frame + 真实原文框画对照图：灰底=画面、蓝框=原文块、绿=长卡/折叠入口、黄=短贴片。
static void AccDrawState(AccApp *app, NSArray<OCRTextItem *> *items, NSRect viewport, NSString *path) {
    NSMutableArray<NSPanel *> *panels = [AccPanels(app) mutableCopy];
    if (app.inlineExpandedReadingPanel) { [panels addObject:app.inlineExpandedReadingPanel]; }
    if (app.inlineOverflowPanel) { [panels addObject:app.inlineOverflowPanel]; }

    CGFloat minX = NSMinX(viewport), minY = NSMinY(viewport);
    CGFloat maxX = NSMaxX(viewport), maxY = NSMaxY(viewport);
    for (OCRTextItem *item in items) {
        NSRect source = [app appKitFrameForOCRItem:item inWindowFrame:viewport];
        minX = MIN(minX, NSMinX(source)); minY = MIN(minY, NSMinY(source));
        maxX = MAX(maxX, NSMaxX(source)); maxY = MAX(maxY, NSMaxY(source));
    }
    for (NSPanel *panel in panels) {
        minX = MIN(minX, NSMinX(panel.frame)); minY = MIN(minY, NSMinY(panel.frame));
        maxX = MAX(maxX, NSMaxX(panel.frame)); maxY = MAX(maxY, NSMaxY(panel.frame));
    }
    NSRect offset = NSMakeRect(minX - 24, minY - 24, 0, 0);
    NSSize size = NSMakeSize(maxX - minX + 48, maxY - minY + 48);
    if (size.width < 10 || size.height < 10) { return; }

    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor colorWithCalibratedWhite:0.94 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    for (OCRTextItem *item in items) {
        NSRect source = [app appKitFrameForOCRItem:item inWindowFrame:viewport];
        BOOL body = [item.text containsString:kAccBodyNeedle];
        AccDrawRect(source, offset,
                    [NSColor colorWithCalibratedRed:0.16 green:0.42 blue:0.95 alpha:body ? 0.22 : 0.10],
                    [NSColor colorWithCalibratedRed:0.10 green:0.30 blue:0.80 alpha:body ? 0.95 : 0.45],
                    body ? 2.0 : 1.0);
    }
    for (NSPanel *panel in panels) {
        BOOL visible = panel.isVisible;
        BOOL isCard = [panel.contentView isKindOfClass:FYInlineLongCardView.class];
        if (!visible) {
            AccDrawRect(panel.frame, offset, nil, [NSColor colorWithCalibratedWhite:0.55 alpha:0.55], 1.0);
            continue;
        }
        AccDrawRect(panel.frame, offset,
                    isCard ? [NSColor colorWithCalibratedRed:0.08 green:0.62 blue:0.33 alpha:0.85]
                           : [NSColor colorWithCalibratedRed:0.95 green:0.78 blue:0.15 alpha:0.85],
                    isCard ? [NSColor colorWithCalibratedRed:0.04 green:0.42 blue:0.22 alpha:1.0]
                           : [NSColor colorWithCalibratedRed:0.72 green:0.55 blue:0.05 alpha:1.0],
                    1.5);
        NSView *content = panel.contentView;
        if ([content isKindOfClass:FYInlineLongCardView.class]) {
            for (NSView *sub in content.subviews) {
                if (![sub isKindOfClass:NSTextField.class]) { continue; }
                NSTextField *label = (NSTextField *)sub;
                if (label.stringValue.length == 0 || label.hidden) { continue; }
                NSRect inWindow = [label convertRect:label.bounds toView:nil];
                NSRect global = NSOffsetRect(inWindow, NSMinX(panel.frame), NSMinY(panel.frame));
                NSPoint point = NSMakePoint(NSMinX(global) - NSMinX(offset), NSMinY(global) - NSMinY(offset));
                [label.stringValue drawAtPoint:point
                                withAttributes:@{NSFontAttributeName: label.font ?: [NSFont systemFontOfSize:11],
                                                 NSForegroundColorAttributeName: NSColor.blackColor}];
            }
        }
    }
    [image unlockFocus];
    AccSaveCanvas(image, path);
}

/// 复核补测：候选的"修饰"这一维必须真的生效（曾经被 prepareLongPlacement 硬编码覆盖），
/// 且总入口必须是单行「还有 N 条译文 · 查看」（曾经多画了「文本过长，已收起 / 点击展开 ▾」）。
static void TestReviewChromeAndSingleLineOverflow(void) {
    NSRect viewport = AccViewport();
    AccApp *app = AccFixtureApp(viewport);
    NSArray<OCRTextItem *> *items = AccSparseItems();
    NSArray<NSString *> *translations = AccSparseTranslations();
    [app showInlineTranslations:translations forItems:items placementRect:viewport];
    FYInlinePlacement *placement = AccPlacementFor(app, @"校内で");
    Check(placement != nil, @"复核：找到长正文块");
    if (placement) {
        FYInlineLayoutRequest *request = nil;
        for (NSUInteger index = 0; index < items.count; index++) {
            FYInlineTextBlock *block = [app inlineLayoutBlockForItem:items[index] order:(NSInteger)index];
            if ([[block.text stringByReplacingOccurrencesOfString:@"\n" withString:@""] containsString:@"校内で"]) {
                request = [FYInlineLayoutRequest requestWithBlock:block translation:translations[index]
                                                      sourceFrame:[app appKitFrameForOCRItem:items[index] inWindowFrame:viewport]];
                break;
            }
        }
        Check(request != nil, @"复核：能重建这个长块的请求");
        if (request) {
            NSArray<NSDictionary *> *variants = [app.inlineLayoutEngine longCardVariantsForRequest:request viewport:viewport];
            NSUInteger index = MIN(placement.chosenVariant, variants.count - 1);
            NSDictionary *variant = variants.count > 0 ? variants[index] : nil;
            Check(variant != nil && fabs(placement.panelPadding - [variant[@"padding"] doubleValue]) < 0.6 &&
                  fabs(placement.titleBandHeight - [variant[@"titleBand"] doubleValue]) < 0.6,
                  [NSString stringWithFormat:@"复核：采用候选的修饰真的生效（padding %.0f/%.0f，标题带 %.0f/%.0f）",
                   placement.panelPadding, [variant[@"padding"] doubleValue],
                   placement.titleBandHeight, [variant[@"titleBand"] doubleValue]]);
            BOOL hasCompactChrome = NO;
            for (NSDictionary *candidate in variants) {
                if ([candidate[@"chrome"] isEqualToString:@"紧凑"] && [candidate[@"titleBand"] doubleValue] <= 0.5) {
                    hasCompactChrome = YES;
                }
            }
            Check(hasCompactChrome, @"复核：候选组合里确实有「紧凑」修饰这一维（标题带 0）");
        }
    }

    // 总入口：极小画面塞满 → 单行文案，卡上只有一个可见标签。
    NSRect tiny = NSMakeRect(0, 0, 260, 150);
    NSMutableArray<OCRTextItem *> *dense = [NSMutableArray array];
    NSMutableArray<NSString *> *denseTranslations = [NSMutableArray array];
    for (NSInteger index = 0; index < 3; index++) {
        CGRect box = CGRectMake(0.02, 0.04 + index * 0.33, 0.96, 0.30);
        OCRTextItem *item = AccItem(@"長い段落の一行目です。\n二行目の続きです。\n三行目の終わりです。", box, InlineBlockKindLong,
                                    @[[NSValue valueWithRect:CGRectMake(0.02, 0.20 + index * 0.33, 0.96, 0.09)],
                                      [NSValue valueWithRect:CGRectMake(0.02, 0.10 + index * 0.33, 0.90, 0.09)]]);
        [dense addObject:item];
        [denseTranslations addObject:@"这是一段很长的译文，用来把画面塞满，确保没有任何可读正文位置。"];
    }
    AccApp *tinyApp = AccFixtureApp(tiny);
    [tinyApp showInlineTranslations:denseTranslations forItems:dense placementRect:tiny];
    Check(tinyApp.inlineOverflowPanel != nil, @"复核：极小画面出现总入口");
    if (tinyApp.inlineOverflowPanel) {
        NSMutableArray<NSString *> *labels = [NSMutableArray array];
        for (NSView *sub in tinyApp.inlineOverflowPanel.contentView.subviews) {
            if ([sub isKindOfClass:NSTextField.class] && [(NSTextField *)sub stringValue].length > 0) {
                [labels addObject:[(NSTextField *)sub stringValue]];
            }
        }
        Check(labels.count == 1 && [labels.firstObject containsString:@"还有"],
              [NSString stringWithFormat:@"复核：总入口是单行「还有 N 条译文 · 查看」（实际 %@）", labels]);
        Check(NSHeight(tinyApp.inlineOverflowPanel.frame) <= 64,
              [NSString stringWithFormat:@"复核：总入口高度就是一行（%.0f，单行上限 64）", NSHeight(tinyApp.inlineOverflowPanel.frame)]);
    }
}

static void TestScreenshots(void) {
    if (gOutputDirectory.length == 0) { return; }
    [[NSFileManager defaultManager] createDirectoryAtPath:gOutputDirectory withIntermediateDirectories:YES attributes:nil error:NULL];

    // ① 正常贴译：长正文以卡片显示。
    AccApp *normal = AccFixtureApp(AccViewport());
    [normal showInlineTranslations:AccSparseTranslations() forItems:AccSparseItems() placementRect:AccViewport()];
    NSString *normalPath = [gOutputDirectory stringByAppendingPathComponent:@"fold-accept-normal.png"];
    AccDrawState(normal, AccSparseItems(), AccViewport(), normalPath);

    // ② 单块折叠入口。
    AccApp *folded = AccFixtureApp(AccViewport());
    [folded showInlineTranslations:AccCrowdedTranslations() forItems:AccCrowdedItems() placementRect:AccViewport()];
    NSString *foldedPath = [gOutputDirectory stringByAppendingPathComponent:@"fold-accept-folded.png"];
    AccDrawState(folded, AccCrowdedItems(), AccViewport(), foldedPath);

    // ③ 极端兜底总入口：且不与其它贴译相交。
    NSRect viewport = AccViewport();
    AccApp *overflowApp = AccFixtureApp(viewport);
    NSRect chipFrame = NSMakeRect(467, 481, 120, 36);
    NSPanel *chip = [[NSPanel alloc] initWithContentRect:chipFrame
                                               styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    chip.ignoresMouseEvents = NO;
    [overflowApp.inlineTranslationPanels addObject:chip];
    [chip orderFrontRegardless];
    overflowApp.inlineOverflowCount = 3;
    [overflowApp buildInlineOverflowEntryForViewport:viewport];
    [overflowApp positionInlineOverflowEntryInViewport:viewport];
    [overflowApp.inlineOverflowPanel orderFrontRegardless];
    Check(overflowApp.inlineOverflowPanel.isVisible, @"截图：总入口在图上确实可见");
    NSArray<OCRTextItem *> *overflowItems = @[AccItem(@"校内でスリリングなことばかりしている彼は、",
                                                      CGRectMake(0.04, 0.42, 0.92, 0.30), InlineBlockKindLong, nil)];
    NSString *overflowPath = [gOutputDirectory stringByAppendingPathComponent:@"fold-accept-overflow.png"];
    AccDrawState(overflowApp, overflowItems, viewport, overflowPath);
    CGRect clip = CGRectIntersection(chip.frame, overflowApp.inlineOverflowPanel.frame);
    Check(CGRectIsNull(clip) || clip.size.width * clip.size.height <= 0.5,
          @"截图：总入口图里总入口与对照贴片确实不相交");

    NSFileManager *manager = [NSFileManager defaultManager];
    Check([manager fileExistsAtPath:normalPath] && [manager fileExistsAtPath:foldedPath] &&
          [manager fileExistsAtPath:overflowPath],
          @"截图：写出正常 / 折叠 / 总入口三张对照图");
}

#pragma mark - main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        unsetenv("FUYI_DIAG");
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if (argc > 1) { gOutputDirectory = [NSString stringWithUTF8String:argv[1]]; }

        Check(FYOverlayShouldShow(YES,NO,NO), @"active target shows ordinary overlays outside expanded reading");
        Check(!FYOverlayShouldShow(YES,YES,NO) && FYOverlayShouldShow(YES,YES,YES), @"expanded reading hides others but keeps current card");
        Check(!FYOverlayShouldShow(NO,YES,YES) && !FYOverlayShouldShow(NO,NO,NO), @"inactive target hides all inline overlays");
        TestLongBodyKeepsCard();
        TestShortTranslationLargeAreaStaysCard();
        TestTinySourceAreaStillGetsEntry();
        TestDuplicateBlockResolution();
        TestOverflowEntryAvoidsExistingPanel();
        TestCrowdedTinyKeepsReadingPath();
        TestStabilityAcrossJitterPageAndGeometry();
        TestReadabilityMatchesMeasurement();
        TestVariantDiagnostics();
        TestFoldInteractionRegression();
        TestReviewChromeAndSingleLineOverflow();
    TestScreenshots();

        Require(gFailures == 0, [NSString stringWithFormat:@"%lu 条断言失败", (unsigned long)gFailures]);
        printf("PASS FoldAcceptanceTests: %lu 条断言；有空间不折叠（候选宽度/字号）/ 短译文不折叠 / 极小区域给入口 / 重复块几何+文本去重且同文不误删 / 总入口避让不压贴译 / 极端拥挤仍有阅读路径 / 抖动换页与几何稳定 / 测量绘制同一口径 / 候选诊断 / 折叠交互回归 / 三张对照图\n",
               (unsigned long)gChecks);
    }
    return 0;
}
