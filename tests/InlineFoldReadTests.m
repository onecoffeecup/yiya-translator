// 折叠入口 + 展开阅读交互 专项验证（2026-10-06 晚）
//
// 本轮实现新增了两级阅读路径：
//   · 一块长正文在可读尺寸下放不下时，不给细条、也不静默消失，而是在原文附近给一个
//     **折叠入口**面板（FYInlineLongCardView + compactEntry）：标题 / 收起原因 / 「点击展开 ▾」；
//   · 点击入口 → 打开**展开阅读卡**：卡内滚动读完译文、可见「收起」按钮、Esc 可收，
//     展开期间其它贴译与折叠入口一起隐藏且不接收鼠标事件（不能挡住游戏点击）；
//   · 收起/连续丢帧/换几何/清画面都有明确行为，展开与收起不得新增翻译请求；
//   · 连折叠入口都放不下时，画面边缘给「还有 N 条译文」，点开是可选的集中列表。
//
// 本套件走真实入口：showInlineTranslations / handleInlineTranslationResult → 面板 →
// card.onClick / collapseButton performClick / refreshDisplayGeometryIfNeeded:，
// 不手工塞 placement 或直接改 label。夹具全部离线合成，文本取自现场 OCR 片段。

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

#pragma mark - 夹具（真实几何接缝 + 可计数的翻译请求）

static NSString *const kFoldBodyNeedle = @"校内でスリリング";
static NSString *const kFoldBodyTranslation = @"在校内总做些刺激的事，他活泼又好奇心旺盛。讨厌无聊，总是挑战新事物。喜欢追求惊险刺激，静不下来。";

/// 测试用 AppDelegate：
///   · liveBoundsForWindowID: / resolveDisplayTargetWindowIDInWindowList: 两个真实接缝
///     用来模拟「窗口移动/缩放」与「目标窗口暂时定位不到」；
///   · translationTargetIsForeground 返回 YES，让 refreshOverlayVisibility 真的显示面板
///     （离线夹具没有前台游戏窗口，否则面板永远 orderOut，isVisible 断言全是假阴性）；
///   · translateInlineTextItems: 计数并直接返回夹具译文，用来证明展开/收起不触发翻译。
@interface FoldApp : AppDelegate
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *liveBounds;
@property (nonatomic) uint32_t fixtureTargetID;
@property (nonatomic) BOOL fixtureTargetUnavailable;
@property (nonatomic) NSUInteger translateCallCount;
@property (nonatomic, copy) NSArray<NSString *> *fixtureTranslations;
@end

@implementation FoldApp
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

static FoldApp *FoldFixtureApp(NSRect windowBounds) {
    FoldApp *app = [[FoldApp alloc] init];
    [app createMainWindow];
    app.inlineTranslationPanels = [NSMutableArray array];
    app.inlineLongCardPanels = [NSMutableArray array];
    app.inlineTranslationCache = [NSMutableDictionary dictionary];
    app.captionFontSizeSlider = [NSSlider sliderWithValue:30 minValue:12 maxValue:48 target:nil action:nil];
    app.captionOpacitySlider = [NSSlider sliderWithValue:0.58 minValue:0 maxValue:1 target:nil action:nil];
    WindowItem *window = [[WindowItem alloc] init];
    window.windowID = 9601;
    window.displayName = @"FoldFixture";
    window.bounds = windowBounds;
    app.windows = [NSMutableArray arrayWithObject:window];
    app.windowPopup = [[NSPopUpButton alloc] init];
    [app.windowPopup addItemWithTitle:@"FoldFixture"];
    app.windowPopup.menu.itemArray.firstObject.representedObject = @(9601);
    app.fixtureTargetID = 9601;
    app.fixtureTargetUnavailable = NO;
    app.liveBounds = [NSMutableDictionary dictionary];
    app.fixtureTranslations = @[];
    return app;
}

/// 现场映射出来的画面区域（14:27:00 CAPTURE-AUTO-LOCATE）。
static NSRect FoldViewport(void) { return NSMakeRect(457, 456, 1017, 572); }

static OCRTextItem *FoldItem(NSString *text, CGRect box, InlineBlockKind kind, NSArray<NSValue *> *lineBoxes) {
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

/// 角色资料页正文：五行喜好正文（与 tests/InlineLongBodyEntryTests.m 同一份现场比例）。
static OCRTextItem *FoldBodyItem(void) {
    NSArray<NSValue *> *boxes = @[
        [NSValue valueWithRect:CGRectMake(0.178, 0.322, 0.215, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.296, 0.200, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.270, 0.205, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.244, 0.195, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.218, 0.170, 0.026)]
    ];
    return FoldItem(@"校内でスリリングなことばかりしている彼は、\nアクティブで好奇心旺盛。退屈を嫌い、\nいつも何か新しいことに挑戦している。\nスリルを求めて行動するのが好きで、\nじっとしているのは苦手なのだ。",
                    CGRectMake(0.178, 0.218, 0.215, 0.130), InlineBlockKindLong, boxes);
}

static OCRTextItem *FoldBodyItemJittered(void) {
    OCRTextItem *item = FoldBodyItem();
    NSArray<NSValue *> *source = item.lineBoxes;
    NSMutableArray<NSValue *> *boxes = [NSMutableArray array];
    for (NSUInteger index = 0; index < source.count; index++) {
        CGRect box = source[index].rectValue;
        box.origin.x += (index % 2 == 0 ? 0.002 : -0.002);
        box.origin.y += (index % 3 == 0 ? 0.002 : -0.001);
        [boxes addObject:[NSValue valueWithRect:box]];
    }
    OCRTextItem *jittered = FoldItem(item.text, item.boundingBox, InlineBlockKindLong, boxes);
    jittered.lineTexts = item.lineTexts;
    return jittered;
}

static NSArray<OCRTextItem *> *FoldProfileItems(void) {
    return @[
        FoldItem(@"◆桜井琉夏の好み◆", CGRectMake(0.178, 0.361, 0.180, 0.038), InlineBlockKindShort, nil),
        FoldItem(@"身長", CGRectMake(0.513, 0.388, 0.050, 0.047), InlineBlockKindShort, nil),
        FoldItem(@"体重", CGRectMake(0.513, 0.317, 0.050, 0.053), InlineBlockKindShort, nil),
        FoldItem(@"バイト", CGRectMake(0.515, 0.263, 0.070, 0.041), InlineBlockKindShort, nil),
        FoldItem(@"花屋アンネリー", CGRectMake(0.608, 0.263, 0.168, 0.041), InlineBlockKindShort, nil),
        FoldItem(@"クラブ", CGRectMake(0.517, 0.201, 0.070, 0.041), InlineBlockKindShort, nil),
        FoldItem(@"帰宅部\n桜井琥一の弟。\nスリルは彼の活力。", CGRectMake(0.608, 0.079, 0.204, 0.164), InlineBlockKindShort, nil),
        FoldItem(@"みよのメモ", CGRectMake(0.180, 0.426, 0.098, 0.038), InlineBlockKindShort, nil),
        FoldBodyItem()
    ];
}

static NSArray<OCRTextItem *> *FoldProfileItemsJittered(void) {
    NSMutableArray<OCRTextItem *> *items = [FoldProfileItems() mutableCopy];
    items[items.count - 1] = FoldBodyItemJittered();
    return items;
}

static NSArray<NSString *> *FoldProfileTranslations(NSString *bodyTranslation) {
    // 短译文如今会按正文实际行数收紧并直接显示；折叠交互夹具需要确实较长的译文。
    if ([bodyTranslation isEqualToString:kFoldBodyTranslation]) {
        bodyTranslation = [NSString stringWithFormat:@"%@\n%@\n%@", bodyTranslation, bodyTranslation, bodyTranslation];
    }
    return @[@"◆樱井琉夏的喜好◆", @"身高", @"体重", @"打工", @"花店安妮莉", @"社团",
             @"回家部\n桜井琥一的弟弟。刺激是他的活力。", @"美代的笔记", bodyTranslation];
}

static NSString *FoldLongBodyTranslation(void) {
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger index = 0; index < 12; index++) {
        [text appendString:kFoldBodyTranslation];
        [text appendString:@"\n"];
    }
    return text;
}

#pragma mark - 面板读取

static FYInlinePlacement *FoldPlacementFor(FoldApp *app, NSString *needle) {
    for (FYInlinePlacement *placement in app.lastInlineLayoutResult.placements) {
        if ([placement.block.text containsString:needle]) { return placement; }
    }
    return nil;
}

static NSArray<NSPanel *> *FoldPanels(FoldApp *app) {
    return [app.inlineTranslationPanels arrayByAddingObjectsFromArray:app.inlineLongCardPanels];
}

static NSPanel *FoldPanelForBlockID(FoldApp *app, NSString *blockID) {
    if (blockID.length == 0) { return nil; }
    for (NSPanel *panel in FoldPanels(app)) {
        if ([panel.identifier isEqualToString:blockID]) { return panel; }
    }
    return nil;
}

/// 卡片上的标题行：排除折叠入口的提示/动作行与展开卡底部提示。
static NSTextField *FoldTitleLabel(FYInlineLongCardView *card) {
    for (NSView *sub in card.subviews) {
        if (![sub isKindOfClass:NSTextField.class]) { continue; }
        NSTextField *label = (NSTextField *)sub;
        if (label == card.foldedEntryHintLabel || label == card.foldedEntryActionLabel ||
            label == card.expandedFooterLabel) { continue; }
        return label;
    }
    return nil;
}

static NSScrollView *FoldScrollOf(NSView *view) {
    for (NSView *child in view.subviews) {
        if ([child isKindOfClass:NSScrollView.class]) { return (NSScrollView *)child; }
    }
    return nil;
}

static BOOL FoldScrollShows(NSScrollView *scroll, NSString *needle) {
    if (!scroll) { return NO; }
    if (![scroll.documentView isKindOfClass:NSTextField.class]) { return NO; }
    return [(NSTextField *)scroll.documentView stringValue] &&
           [[(NSTextField *)scroll.documentView stringValue] containsString:needle];
}

static void FoldCollectButtons(NSView *view, NSMutableArray<NSButton *> *buttons) {
    if ([view isKindOfClass:NSButton.class]) { [buttons addObject:(NSButton *)view]; }
    for (NSView *child in view.subviews) { FoldCollectButtons(child, buttons); }
}

static NSArray<NSButton *> *FoldChooserRows(FoldApp *app) {
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    if (app.inlineOverflowChoicePanel) {
        FoldCollectButtons(app.inlineOverflowChoicePanel.contentView, buttons);
    }
    // 面板底部有一个可见的「关闭」入口，不是待读条目：按标题剔除。
    for (NSButton *button in [buttons copy]) {
        if ([button.title isEqualToString:@"关闭"]) { [buttons removeObject:button]; }
    }
    [buttons sortUsingComparator:^NSComparisonResult(NSButton *left, NSButton *right) {
        if (left.tag < right.tag) { return NSOrderedAscending; }
        if (left.tag > right.tag) { return NSOrderedDescending; }
        return NSOrderedSame;
    }];
    return buttons;
}

static NSDictionary<NSString *, NSValue *> *FoldPanelFrames(FoldApp *app) {
    NSMutableDictionary<NSString *, NSValue *> *frames = [NSMutableDictionary dictionary];
    for (NSPanel *panel in FoldPanels(app)) {
        if (panel.identifier.length > 0) { frames[panel.identifier] = [NSValue valueWithRect:panel.frame]; }
    }
    return frames;
}

#pragma mark - 1/2. 折叠入口的外观与尺寸

static void TestFoldedEntryAppearance(void) {
    FoldApp *app = FoldFixtureApp(FoldViewport());
    [app showInlineTranslations:FoldProfileTranslations(kFoldBodyTranslation)
                       forItems:FoldProfileItems()
                  placementRect:FoldViewport()];
    FYInlinePlacement *placement = FoldPlacementFor(app, kFoldBodyNeedle);
    Check(placement != nil, @"折叠入口：正文块出现在布局结果里");
    if (!placement) { return; }
    Check(placement.mode == FYInlineDisplayModeCompactEntry,
          [NSString stringWithFormat:@"折叠入口：拥挤画面给折叠入口（mode=%ld，原因：%@）", (long)placement.mode, placement.reason]);
    if (placement.mode != FYInlineDisplayModeCompactEntry) { return; }

    NSPanel *panel = FoldPanelForBlockID(app, placement.blockID);
    Check(panel != nil, @"折叠入口：面板真的创建出来了（不是只在数据里）");
    if (!panel) { return; }
    Check([panel.contentView isKindOfClass:FYInlineLongCardView.class], @"折叠入口：内容视图是 FYInlineLongCardView");
    FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
    Check([card isKindOfClass:FYInlineLongCardView.class] && card.compactEntry, @"折叠入口：compactEntry == YES");

    // 三行可见文案：标题 / 收起原因 / 点击展开（不是只藏在 tooltip 里）。
    NSString *shortTitle = [FYInlineLayoutEngine shortTitleForBlockText:placement.block.text];
    NSString *expectedTitle = shortTitle.length > 0 ? shortTitle : app.inlineLayoutEngine.foldedEntryFallbackTitle;
    NSTextField *titleLabel = FoldTitleLabel(card);
    Check(titleLabel != nil && titleLabel.stringValue.length > 0 &&
          [titleLabel.stringValue isEqualToString:expectedTitle],
          [NSString stringWithFormat:@"折叠入口：标题 = 短标题或「这段译文」（实际 %@）", titleLabel.stringValue ?: @"(nil)"]);
    Check(![titleLabel.stringValue containsString:@"暂无"], @"折叠入口：标题不是「暂无」占位");
    NSString *hint = card.foldedEntryHintLabel.stringValue ?: @"";
    Check([hint isEqualToString:app.inlineLayoutEngine.foldedEntryHintTooLong] ||
          [hint isEqualToString:app.inlineLayoutEngine.foldedEntryHintCrowded],
          [NSString stringWithFormat:@"折叠入口：提示 = 「文本过长，已收起」或「空间不足，已收起」（实际 %@）", hint]);
    Check(hint.length > 0, @"折叠入口：提示不是空字符串（也不只存在于 tooltip）");
    NSString *action = card.foldedEntryActionLabel.stringValue ?: @"";
    Check([action containsString:@"点击展开"], [NSString stringWithFormat:@"折叠入口：动作文案含「点击展开」（实际 %@）", action]);
    Check([action containsString:@"▾"], [NSString stringWithFormat:@"折叠入口：动作行带向下箭头（实际 %@）", action]);
    Check(card.onClick != nil, @"折叠入口：整卡可点击（card.onClick != nil）");

    // 提示行宽度必须放得下这行字：与引擎同一份字体的 boundingRect 对照。
    NSFont *hintFont = [app.inlineLayoutEngine foldedEntryHintFont];
    NSRect natural = [hint boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
                                        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                     attributes:@{NSFontAttributeName: hintFont}];
    Check(NSWidth(card.foldedEntryHintLabel.frame) + 0.5 >= ceil(NSWidth(natural)),
          [NSString stringWithFormat:@"折叠入口：提示行宽 %.0f ≥ 文字宽 %.0f（不会被截断）",
           NSWidth(card.foldedEntryHintLabel.frame), ceil(NSWidth(natural))]);

    // 2. 尺寸 = 引擎按内容测量的折叠尺寸，且不继承长卡宽度。
    CGSize measured = [app.inlineLayoutEngine foldedEntrySizeForViewport:FoldViewport()
                                                                  title:placement.entryTitle
                                                                   hint:placement.entryHint];
    Check(fabs(NSWidth(panel.frame) - measured.width) < 1.5 && fabs(NSHeight(panel.frame) - measured.height) < 1.5,
          [NSString stringWithFormat:@"折叠入口：面板尺寸 = 引擎测量 %.0f×%.0f（实际 %.0f×%.0f）",
           measured.width, measured.height, NSWidth(panel.frame), NSHeight(panel.frame)]);
    Check(placement.longCardSize.width > 0 &&
          NSWidth(panel.frame) < placement.longCardSize.width,
          [NSString stringWithFormat:@"折叠入口：宽度不继承长卡（卡 %.0f，入口 %.0f）",
           placement.longCardSize.width, NSWidth(panel.frame)]);
    Check(panel.isVisible, @"折叠入口：面板真的显示在画面上");
}

#pragma mark - 3/4/5. 点击展开、展开互斥、按钮收起

static void TestExpandCollapseByRealControl(void) {
    FoldApp *app = FoldFixtureApp(FoldViewport());
    [app showInlineTranslations:FoldProfileTranslations(kFoldBodyTranslation)
                       forItems:FoldProfileItems()
                  placementRect:FoldViewport()];
    FYInlinePlacement *placement = FoldPlacementFor(app, kFoldBodyNeedle);
    Check(placement != nil && placement.mode == FYInlineDisplayModeCompactEntry,
          @"展开收起：正文块是折叠入口");
    if (!placement || placement.mode != FYInlineDisplayModeCompactEntry) { return; }
    NSPanel *entryPanel = FoldPanelForBlockID(app, placement.blockID);
    Check(entryPanel != nil, @"展开收起：折叠入口面板存在");
    if (!entryPanel) { return; }
    FYInlineLongCardView *entryCard = (FYInlineLongCardView *)entryPanel.contentView;

    NSDictionary<NSString *, NSValue *> *framesBefore = FoldPanelFrames(app);
    // 展开前其它面板是可见的（否则"展开后会隐藏"的断言没有意义）。
    NSUInteger visibleBefore = 0;
    for (NSPanel *panel in FoldPanels(app)) { if (panel.isVisible) { visibleBefore += 1; } }
    Check(visibleBefore >= 1, @"展开收起：展开前画面上的贴译可见");

    Check(entryCard.onClick != nil, @"展开收起：入口可点击");
    entryCard.onClick();

    // 3. 展开卡打开，其它贴译全部隐藏且不再接收鼠标事件。
    Check(app.inlineExpandedReadingPanel != nil, @"展开收起：点击入口打开了展开阅读卡");
    if (!app.inlineExpandedReadingPanel) { return; }
    NSUInteger others = 0, hiddenOthers = 0, mouseEnabledOthers = 0;
    for (NSPanel *panel in FoldPanels(app)) {
        others += 1;
        if (!panel.isVisible) { hiddenOthers += 1; }
        if (panel.ignoresMouseEvents) { mouseEnabledOthers += 1; }
    }
    Check(others >= 1 && hiddenOthers == others,
          [NSString stringWithFormat:@"展开互斥：其它贴译全部隐藏（%lu/%lu）", (unsigned long)hiddenOthers, (unsigned long)others]);
    Check(mouseEnabledOthers == others,
          [NSString stringWithFormat:@"展开互斥：其它贴译全部不接收鼠标事件（%lu/%lu）", (unsigned long)mouseEnabledOthers, (unsigned long)others]);

    FYInlineLongCardView *expanded = (FYInlineLongCardView *)app.inlineExpandedReadingPanel.contentView;
    Check([expanded isKindOfClass:FYInlineLongCardView.class], @"展开互斥：展开卡仍是 FYInlineLongCardView");
    if (![expanded isKindOfClass:FYInlineLongCardView.class]) { return; }

    // 4. 可见收起按钮 / 滚动区完整译文 / 底部提示 / 标题 / Esc 监视器。
    NSButton *collapse = expanded.collapseButton;
    Check(collapse != nil && !collapse.hidden && [collapse.title isEqualToString:@"收起"],
          [NSString stringWithFormat:@"展开卡：有可见「收起」按钮（%@）", collapse.title ?: @"(nil)"]);
    Check(collapse.window == app.inlineExpandedReadingPanel && NSWidth(collapse.frame) > 10 &&
          NSHeight(collapse.frame) > 10 && NSContainsRect(expanded.bounds, collapse.frame),
          @"展开卡：收起按钮真的在展开卡可视范围内（不是零尺寸/挂空）");    Check(expanded.showsCollapseControl, @"展开卡：收起控件已安装");
    Check(app.inlineExpandedReadingKeyMonitor != nil, @"展开卡：Esc 收起监视器已安装");
    NSScrollView *scroll = FoldScrollOf(expanded);
    Check(scroll != nil, @"展开卡：有滚动区（长译文可滚动）");
    Check(FoldScrollShows(scroll, @"好奇心旺盛") && FoldScrollShows(scroll, @"静不下来"),
          @"展开卡：滚动区里是完整译文（首尾都在，不是截断的）");
    NSString *footer = expanded.expandedFooterLabel.stringValue ?: @"";
    Check([footer containsString:@"其他贴译已暂时隐藏"] && [footer containsString:@"Esc 收起"],
          [NSString stringWithFormat:@"展开卡：底部提示写明其它贴译已隐藏 + Esc 收起（%@）", footer]);
    NSTextField *titleLabel = FoldTitleLabel(expanded);
    NSString *shortTitle = [FYInlineLayoutEngine shortTitleForBlockText:placement.block.text];
    NSString *expectedTitle = shortTitle.length > 0 ? shortTitle : @"这段译文";
    Check(titleLabel != nil && titleLabel.stringValue.length > 0 &&
          ([titleLabel.stringValue isEqualToString:expectedTitle] || [titleLabel.stringValue isEqualToString:@"这段译文"]),
          [NSString stringWithFormat:@"展开卡：标题 = 短标题或「这段译文」（实际 %@）", titleLabel.stringValue ?: @"(nil)"]);
    Check(![titleLabel.stringValue containsString:@"暂无"], @"展开卡：标题不是「暂无」占位");
    Check(expanded.stableBlockID.length > 0 && [expanded.stableBlockID isEqualToString:placement.blockID],
          @"展开卡：保留同一个稳定块身份");

    // 5. 用真实按钮收起：展开卡消失，当前帧仍在的贴译按原位置恢复。
    [collapse performClick:nil];
    Check(app.inlineExpandedReadingPanel == nil, @"收起：点「收起」按钮后展开卡关闭");
    Check(app.inlineExpandedReadingKeyMonitor == nil, @"收起：Esc 监视器已卸载");
    NSArray<NSPanel *> *present = [app inlinePanelsPresentInCurrentLayout];
    Check(present.count >= 1, @"收起：当前帧仍存在的贴译被识别出来");
    NSUInteger restoredVisible = 0, restoredFrames = 0;
    for (NSPanel *panel in present) {
        if (panel.isVisible) { restoredVisible += 1; }
        NSValue *before = framesBefore[panel.identifier];
        if (before && NSEqualRects(before.rectValue, panel.frame)) { restoredFrames += 1; }
    }
    Check(restoredVisible == present.count,
          [NSString stringWithFormat:@"收起：当前帧的贴译全部恢复可见（%lu/%lu）",
           (unsigned long)restoredVisible, (unsigned long)present.count]);
    Check(restoredFrames == present.count,
          [NSString stringWithFormat:@"收起：恢复没有移动面板（%lu/%lu 位置不变）",
           (unsigned long)restoredFrames, (unsigned long)present.count]);
    Check(!entryPanel.ignoresMouseEvents, @"收起：恢复的面板重新接收鼠标事件");

    // 5b. 换页后不复活：重新渲染一帧**没有这块正文**的场景，再收起。
    entryCard.onClick();
    Check(app.inlineExpandedReadingPanel != nil, @"收起·换页：重新展开");
    NSMutableArray<OCRTextItem *> *withoutBody = [FoldProfileItems() mutableCopy];
    [withoutBody removeLastObject];
    NSMutableArray<NSString *> *withoutBodyTranslations = [FoldProfileTranslations(kFoldBodyTranslation) mutableCopy];
    [withoutBodyTranslations removeLastObject];
    [app showInlineTranslations:withoutBodyTranslations forItems:withoutBody placementRect:FoldViewport()];
    Check(app.inlineExpandedReadingPanel != nil, @"收起·换页：单帧看不到这一块时仍保持展开");
    if (app.inlineExpandedReadingPanel) {
        FYInlineLongCardView *card = (FYInlineLongCardView *)app.inlineExpandedReadingPanel.contentView;
        [card.collapseButton performClick:nil];
    }
    Check(app.inlineExpandedReadingPanel == nil, @"收起·换页：收起后展开卡关闭");
    Check(!entryPanel.isVisible, @"收起·换页：已不在当前帧里的旧面板没有被复活（保持隐藏）");
    Check(FoldPanelForBlockID(app, placement.blockID) == nil, @"收起·换页：旧面板已从当前帧面板集合移除");
}

#pragma mark - 6. 抖动稳定：展开卡不闪、滚动位置保留

static void TestJitterKeepsExpandedCard(void) {
    FoldApp *app = FoldFixtureApp(FoldViewport());
    NSString *longTranslation = FoldLongBodyTranslation();
    [app showInlineTranslations:FoldProfileTranslations(longTranslation)
                       forItems:FoldProfileItems()
                  placementRect:FoldViewport()];
    FYInlinePlacement *placement = FoldPlacementFor(app, kFoldBodyNeedle);
    Check(placement != nil && placement.mode == FYInlineDisplayModeCompactEntry,
          @"抖动稳定：正文块是折叠入口");
    if (!placement || placement.mode != FYInlineDisplayModeCompactEntry) { return; }
    NSPanel *entryPanel = FoldPanelForBlockID(app, placement.blockID);
    FYInlineLongCardView *entryCard = (FYInlineLongCardView *)entryPanel.contentView;
    entryCard.onClick();
    Check(app.inlineExpandedReadingPanel != nil, @"抖动稳定：展开卡已打开");
    if (!app.inlineExpandedReadingPanel) { return; }
    FYInlineLongCardView *expanded = (FYInlineLongCardView *)app.inlineExpandedReadingPanel.contentView;
    NSScrollView *scroll = FoldScrollOf(expanded);
    Check(scroll != nil, @"抖动稳定：展开卡有滚动区");
    if (!scroll) { return; }
    NSString *contentBefore = [(NSTextField *)scroll.documentView stringValue];
    NSString *titleBefore = FoldTitleLabel(expanded).stringValue;

    // 把滚动位置挪到中间：重排后必须保持（不能跳回顶部）。
    NSPoint origin = NSMakePoint(0, 40);
    [scroll.contentView scrollToPoint:origin];
    [scroll reflectScrolledClipView:scroll.contentView];
    NSPoint saved = scroll.contentView.bounds.origin;
    Check(saved.y > 1, [NSString stringWithFormat:@"抖动稳定：滚动区真的能滚（y=%.0f）", saved.y]);

    NSUInteger visibleBefore = 0;
    for (NSPanel *panel in FoldPanels(app)) { if (panel.isVisible) { visibleBefore += 1; } }
    Check(visibleBefore == 0, @"抖动稳定：展开期间其它贴译保持隐藏");

    // 同一段文字、OCR 框整体抖动几个点：仍在同一页，展开卡不能关。
    [app showInlineTranslations:FoldProfileTranslations(longTranslation)
                       forItems:FoldProfileItemsJittered()
                  placementRect:FoldViewport()];
    Check(app.inlineExpandedReadingPanel != nil, @"抖动稳定：重排后展开卡仍然打开");
    if (!app.inlineExpandedReadingPanel) { return; }
    FYInlineLongCardView *after = (FYInlineLongCardView *)app.inlineExpandedReadingPanel.contentView;
    NSScrollView *scrollAfter = FoldScrollOf(after);
    Check(after == expanded, @"抖动稳定：展开卡面板是同一个（没有销毁重建）");
    Check([FoldTitleLabel(after).stringValue isEqualToString:titleBefore], @"抖动稳定：标题内容没变");
    Check(scrollAfter && [[(NSTextField *)scrollAfter.documentView stringValue] isEqualToString:contentBefore],
          @"抖动稳定：正文内容没变");
    Check(scrollAfter && fabs(scrollAfter.contentView.bounds.origin.y - saved.y) < 0.5,
          [NSString stringWithFormat:@"抖动稳定：滚动位置保留（%.0f → %.0f）",
           saved.y, scrollAfter ? scrollAfter.contentView.bounds.origin.y : -1]);
}

#pragma mark - 7. 单帧 OCR 丢块不关，两帧才关；清画面立刻关

/// 真实点击路径：命中测试 + 首次点击接受 + 真实鼠标事件（不只调状态变量）。
static void TestCollapseButtonTakesRealClick(void) {
    FoldApp *app = FoldFixtureApp(FoldViewport());
    [app showInlineTranslations:FoldProfileTranslations(kFoldBodyTranslation)
                       forItems:FoldProfileItems()
                  placementRect:FoldViewport()];
    FYInlinePlacement *placement = FoldPlacementFor(app, kFoldBodyNeedle);
    Check(placement != nil, @"真实点击：有正文块排版结果");
    if (!placement) { return; }
    NSPanel *entryPanel = FoldPanelForBlockID(app, placement.blockID);
    [(FYInlineLongCardView *)entryPanel.contentView onClick]();
    NSPanel *panel = app.inlineExpandedReadingPanel;
    Check(panel != nil, @"真实点击：展开卡已打开");
    if (!panel) { return; }
    Check([panel.contentView isKindOfClass:FYInlineLongCardView.class], @"真实点击：展开卡内容视图是长卡");
    if (![panel.contentView isKindOfClass:FYInlineLongCardView.class]) { return; }
    FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
    NSButton *button = card.collapseButton;
    Check(button != nil && !button.hidden, @"真实点击：收起按钮可见");
    if (!button) { return; }

    // ① 命中测试：按钮中心点必须命中按钮本身，而不是被卡片吞掉（卡片 mouseDown 在标题栏会走拖动）。
    // ① 命中测试：卡片自己接管整个卡面（按钮区域也由卡片判定，见 pointIsInCollapseControl:），
    //    所以"点按钮"必须命中卡片、且卡片必须接受首次点击。
    NSPoint buttonCenter = NSMakePoint(NSMidX(button.frame), NSMidY(button.frame));
    NSPoint inSuperview = [card convertPoint:buttonCenter toView:card.superview];
    Check([card hitTest:inSuperview] == card, @"真实点击：按钮区域命中卡片本身（卡片自己判定收起）");
    // ② 首次点击：贴译浮层不是 key window，视图必须接受 first mouse，否则第一次点击被吞。
    Check([card acceptsFirstMouse:nil], @"真实点击：卡片接受首次点击（不是 key window 时也能点）");
    Check([card pointIsInCollapseControl:buttonCenter], @"真实点击：按钮中心被判为收起控件区域");

    // ③ 真发鼠标事件给**卡片**（真实点击就是走卡片，因为浮层窗口的 contentView 就是它）：
    //    不调用 closeExpandedInlineReadingCard，只发 down/up。
    NSPoint windowPoint = [card convertPoint:buttonCenter toView:nil];
    NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:windowPoint modifierFlags:0
                                        timestamp:1 windowNumber:panel.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
    NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:windowPoint modifierFlags:0
                                      timestamp:1.1 windowNumber:panel.windowNumber context:nil eventNumber:2 clickCount:1 pressure:0];
    [card mouseDown:down];
    [card mouseUp:up];
    Check(app.inlineExpandedReadingPanel == nil, @"真实点击：真实鼠标事件能收起阅读卡");
    Check(app.inlineExpandedReadingKeyMonitor == nil, @"真实点击：收起后 Esc 监视器已卸载");

    // ④ 按下后拖走不应误触收起（阅读卡标题栏可以拖动）。
    FoldApp *dragApp = FoldFixtureApp(FoldViewport());
    [dragApp showInlineTranslations:FoldProfileTranslations(kFoldBodyTranslation)
                           forItems:FoldProfileItems()
                      placementRect:FoldViewport()];
    FYInlinePlacement *dragPlacement = FoldPlacementFor(dragApp, kFoldBodyNeedle);
    NSPanel *dragEntry = FoldPanelForBlockID(dragApp, dragPlacement.blockID);
    [(FYInlineLongCardView *)dragEntry.contentView onClick]();
    NSPanel *dragPanel = dragApp.inlineExpandedReadingPanel;
    FYInlineLongCardView *dragCard = (FYInlineLongCardView *)dragPanel.contentView;
    NSButton *dragButton = dragCard.collapseButton;
    NSPoint dragLocal = NSMakePoint(NSMidX(dragButton.frame), NSMidY(dragButton.frame));
    NSPoint dragWindowPoint = [dragCard convertPoint:dragLocal toView:nil];
    NSEvent *dragDown = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:dragWindowPoint modifierFlags:0
                                           timestamp:2 windowNumber:dragPanel.windowNumber context:nil eventNumber:3 clickCount:1 pressure:1];
    NSEvent *dragMove = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged location:NSMakePoint(dragWindowPoint.x - 40, dragWindowPoint.y - 30)
                                           modifierFlags:0 timestamp:2.05 windowNumber:dragPanel.windowNumber context:nil eventNumber:4 clickCount:1 pressure:1];
    NSEvent *dragUp = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:NSMakePoint(dragWindowPoint.x - 40, dragWindowPoint.y - 30)
                                         modifierFlags:0 timestamp:2.1 windowNumber:dragPanel.windowNumber context:nil eventNumber:5 clickCount:1 pressure:0];
    [dragCard mouseDown:dragDown];
    [dragCard mouseDragged:dragMove];
    [dragCard mouseUp:dragUp];
    Check(dragApp.inlineExpandedReadingPanel != nil, @"真实点击：按住按钮拖走不会误触收起");
}

static void TestMissingFrameClosesAfterTwo(void) {
    FoldApp *app = FoldFixtureApp(FoldViewport());
    [app showInlineTranslations:FoldProfileTranslations(kFoldBodyTranslation)
                       forItems:FoldProfileItems()
                  placementRect:FoldViewport()];
    FYInlinePlacement *placement = FoldPlacementFor(app, kFoldBodyNeedle);
    Check(placement != nil && placement.mode == FYInlineDisplayModeCompactEntry, @"丢帧：正文块是折叠入口");
    if (!placement || placement.mode != FYInlineDisplayModeCompactEntry) { return; }
    NSPanel *entryPanel = FoldPanelForBlockID(app, placement.blockID);
    [(FYInlineLongCardView *)entryPanel.contentView onClick]();
    Check(app.inlineExpandedReadingPanel != nil, @"丢帧：展开卡已打开");
    if (!app.inlineExpandedReadingPanel) { return; }

    NSMutableArray<OCRTextItem *> *withoutBody = [FoldProfileItems() mutableCopy];
    [withoutBody removeLastObject];
    NSMutableArray<NSString *> *withoutBodyTranslations = [FoldProfileTranslations(kFoldBodyTranslation) mutableCopy];
    [withoutBodyTranslations removeLastObject];
    [app showInlineTranslations:withoutBodyTranslations forItems:withoutBody placementRect:FoldViewport()];
    Check(app.inlineExpandedReadingPanel != nil, @"丢帧：第一帧看不到这一块时仍然保持展开");

    // 第二帧：仍在画面里的块有几像素 OCR 抖动（真实连续帧就是这样）。
    NSMutableArray<OCRTextItem *> *secondFrame = [withoutBody mutableCopy];
    OCRTextItem *moved = secondFrame.firstObject;
    CGRect movedBox = moved.boundingBox;
    movedBox.origin.x += 0.003;
    movedBox.origin.y -= 0.002;
    secondFrame[0] = FoldItem(moved.text, movedBox, moved.blockKind, nil);
    [app showInlineTranslations:withoutBodyTranslations forItems:secondFrame placementRect:FoldViewport()];
    Check(app.inlineExpandedReadingPanel == nil, @"丢帧：连续两帧看不到这一块后收起（不清空整页）");

    // 产线回归：块已消失、页面其余部分一字未变时（内容相同 → dedup 短路），
    // 展开态记账同样要推进 —— 否则阅读卡会一直留在画面上。
    FoldApp *identical = FoldFixtureApp(FoldViewport());
    [identical showInlineTranslations:FoldProfileTranslations(kFoldBodyTranslation)
                             forItems:FoldProfileItems()
                        placementRect:FoldViewport()];
    FYInlinePlacement *identicalPlacement = FoldPlacementFor(identical, kFoldBodyNeedle);
    NSPanel *identicalPanel = FoldPanelForBlockID(identical, identicalPlacement.blockID);
    [(FYInlineLongCardView *)identicalPanel.contentView onClick]();
    Check(identical.inlineExpandedReadingPanel != nil, @"丢帧：相同内容场景展开卡已打开");
    [identical showInlineTranslations:withoutBodyTranslations forItems:withoutBody placementRect:FoldViewport()];
    Check(identical.inlineExpandedReadingPanel != nil, @"丢帧：相同内容的第一帧仍然保持展开");
    // 第二帧与上一帧**逐字节相同**：没有新的渲染，但记账必须继续（这就是之前漏掉的那条路径）。
    [identical showInlineTranslations:withoutBodyTranslations forItems:withoutBody placementRect:FoldViewport()];
    Check(identical.inlineExpandedReadingPanel == nil,
          @"丢帧：内容完全相同的两帧后同样收起（dedup 短路不再跳过记账）");

    // clearInlineTranslationPanels 立即关闭。
    FoldApp *second = FoldFixtureApp(FoldViewport());
    [second showInlineTranslations:FoldProfileTranslations(kFoldBodyTranslation)
                          forItems:FoldProfileItems()
                     placementRect:FoldViewport()];
    FYInlinePlacement *secondPlacement = FoldPlacementFor(second, kFoldBodyNeedle);
    NSPanel *secondPanel = FoldPanelForBlockID(second, secondPlacement.blockID);
    [(FYInlineLongCardView *)secondPanel.contentView onClick]();
    Check(second.inlineExpandedReadingPanel != nil, @"丢帧：第二场景展开卡已打开");
    [second clearInlineTranslationPanels];
    Check(second.inlineExpandedReadingPanel == nil, @"丢帧：clearInlineTranslationPanels 立即关闭展开卡");
    Check(second.inlineTranslationPanels.count == 0 && second.inlineLongCardPanels.count == 0,
          @"丢帧：clearInlineTranslationPanels 同时清掉贴译面板");
}

#pragma mark - 8. 展开/收起不新增翻译请求

static void TestNoExtraTranslationRequests(void) {
    FoldApp *app = FoldFixtureApp(FoldViewport());
    app.fixtureTranslations = FoldProfileTranslations(kFoldBodyTranslation);
    NSUInteger baseline = app.translateCallCount;
    // 对照：计数接缝确实会被 translateInlineTextItems: 触发（否则"没新增"是空断言）。
    [app translateInlineTextItems:FoldProfileItems() completion:^(NSArray<NSString *> *translations, NSError *error) {}];
    Check(app.translateCallCount == baseline + 1, @"翻译请求：计数接缝可用（对照 +1）");
    NSUInteger afterControl = app.translateCallCount;

    [app showInlineTranslations:app.fixtureTranslations forItems:FoldProfileItems() placementRect:FoldViewport()];
    Check(app.translateCallCount == afterControl, @"翻译请求：渲染贴译本身不新增翻译请求");
    FYInlinePlacement *placement = FoldPlacementFor(app, kFoldBodyNeedle);
    NSPanel *entryPanel = FoldPanelForBlockID(app, placement.blockID);
    FYInlineLongCardView *entryCard = (FYInlineLongCardView *)entryPanel.contentView;
    entryCard.onClick();
    Check(app.inlineExpandedReadingPanel != nil, @"翻译请求：展开卡已打开");
    Check(app.translateCallCount == afterControl, @"翻译请求：展开不新增翻译请求");
    FYInlineLongCardView *expanded = (FYInlineLongCardView *)app.inlineExpandedReadingPanel.contentView;
    [expanded.collapseButton performClick:nil];
    Check(app.inlineExpandedReadingPanel == nil, @"翻译请求：展开卡已收起");
    Check(app.translateCallCount == afterControl, @"翻译请求：收起不新增翻译请求");

    // 真实结果入口（handleInlineTranslationResult）也走一遍：展开/收起仍不请求。
    FoldApp *real = FoldFixtureApp(FoldViewport());
    real.fixtureTranslations = FoldProfileTranslations(kFoldBodyTranslation);
    [real handleInlineTranslationResult:real.fixtureTranslations
                               forItems:FoldProfileItems()
                                  error:nil
                          failureStatus:@"界面翻译出错"
                          successPrefix:@"界面译文已更新"];
    Tick();
    Tick();
    NSUInteger afterResult = real.translateCallCount;
    FYInlinePlacement *realPlacement = FoldPlacementFor(real, kFoldBodyNeedle);
    Check(realPlacement != nil && realPlacement.mode == FYInlineDisplayModeCompactEntry,
          @"翻译请求：handleInlineTranslationResult 路径也给出折叠入口");
    if (realPlacement) {
        NSPanel *panel = FoldPanelForBlockID(real, realPlacement.blockID);
        [(FYInlineLongCardView *)panel.contentView onClick]();
        if (real.inlineExpandedReadingPanel) {
            FYInlineLongCardView *card = (FYInlineLongCardView *)real.inlineExpandedReadingPanel.contentView;
            [card.collapseButton performClick:nil];
        }
        Check(real.translateCallCount == afterResult, @"翻译请求：真实结果路径的展开/收起不新增请求");
    }
}

#pragma mark - 9. 同一段文字出现在两处不串块

static void TestSameTextTwoPlaces(void) {
    NSString *sharedText = @"同じテキストの長い段落です。\n二行目の続きです。\n三行目の終わりです。";
    NSArray<NSValue *> *boxesA = @[[NSValue valueWithRect:CGRectMake(0.06, 0.62, 0.86, 0.08)],
                                   [NSValue valueWithRect:CGRectMake(0.06, 0.52, 0.84, 0.08)],
                                   [NSValue valueWithRect:CGRectMake(0.06, 0.42, 0.80, 0.08)]];
    NSArray<NSValue *> *boxesB = @[[NSValue valueWithRect:CGRectMake(0.06, 0.20, 0.86, 0.08)],
                                   [NSValue valueWithRect:CGRectMake(0.06, 0.10, 0.84, 0.08)],
                                   [NSValue valueWithRect:CGRectMake(0.06, 0.01, 0.80, 0.08)]];
    OCRTextItem *first = FoldItem(sharedText, CGRectMake(0.06, 0.42, 0.86, 0.28), InlineBlockKindLong, boxesA);
    OCRTextItem *second = FoldItem(sharedText, CGRectMake(0.06, 0.01, 0.86, 0.27), InlineBlockKindLong, boxesB);
    NSString *translationA = @"译文甲：这是第一处相同原文的译文。";
    NSString *translationB = @"译文乙：这是第二处相同原文的译文。这里还有很多需要展开后阅读的说明，继续说明第二处原文的区别，以及后续的细节。";
    NSRect viewport = NSMakeRect(0, 0, 420, 300);
    FoldApp *app = FoldFixtureApp(viewport);
    [app showInlineTranslations:@[translationA, translationB] forItems:@[first, second] placementRect:viewport];

    NSArray<FYInlinePlacement *> *placements = app.lastInlineLayoutResult.placements;
    Check(placements.count == 2, [NSString stringWithFormat:@"同文两处：两块都进了布局（%lu）", (unsigned long)placements.count]);
    FYInlinePlacement *placementA = placements.count > 0 ? placements[0] : nil;
    FYInlinePlacement *placementB = placements.count > 1 ? placements[1] : nil;
    Check(placementA && placementB && ![placementA.blockID isEqualToString:placementB.blockID],
          @"同文两处：同一段文字在两个位置的块身份不同");
    NSPanel *panelB = FoldPanelForBlockID(app, placementB.blockID);
    Check(panelB != nil, @"同文两处：第二处的面板存在");
    if (!panelB) { return; }
    FYInlineLongCardView *cardB = (FYInlineLongCardView *)panelB.contentView;
    Check([cardB isKindOfClass:FYInlineLongCardView.class] && cardB.compactEntry,
          @"同文两处：第二处以折叠入口呈现");
    if (!cardB.compactEntry) { return; }
    cardB.onClick();
    Check(app.inlineExpandedReadingBlockID &&
          [app.inlineExpandedReadingBlockID isEqualToString:placementB.blockID],
          [NSString stringWithFormat:@"同文两处：展开的是第二处（blockID 对得上：%@）",
           app.inlineExpandedReadingBlockID ?: @"(nil)"]);
    FYInlineLongCardView *expanded = (FYInlineLongCardView *)app.inlineExpandedReadingPanel.contentView;
    NSScrollView *scroll = FoldScrollOf(expanded);
    Check(FoldScrollShows(scroll, @"译文乙"), @"同文两处：展开卡显示第二处的译文");
    Check(!FoldScrollShows(scroll, @"译文甲"), @"同文两处：展开卡没有串到第一处的译文");
}

#pragma mark - 10. 几何变化：展开卡跟着走 / 定位不可用就收起

static void TestGeometryChangeForExpandedCard(void) {
    FoldApp *app = FoldFixtureApp(FoldViewport());
    [app showInlineTranslations:FoldProfileTranslations(kFoldBodyTranslation)
                       forItems:FoldProfileItems()
                  placementRect:FoldViewport()];
    FYInlinePlacement *placement = FoldPlacementFor(app, kFoldBodyNeedle);
    if (!placement || placement.mode != FYInlineDisplayModeCompactEntry) {
        Check(NO, @"几何跟随：正文块是折叠入口");
        return;
    }
    NSPanel *entryPanel = FoldPanelForBlockID(app, placement.blockID);
    [(FYInlineLongCardView *)entryPanel.contentView onClick]();
    Check(app.inlineExpandedReadingPanel != nil, @"几何跟随：展开卡已打开");
    if (!app.inlineExpandedReadingPanel) { return; }

    // 目标窗口移到别处并缩小：真实接缝 liveBoundsForWindowID: 给新边界。
    CGRect moved = CGRectMake(180, 90, 700, 460);
    app.liveBounds[@(app.fixtureTargetID)] = [NSValue valueWithRect:NSRectFromCGRect(moved)];
    [app refreshDisplayGeometryIfNeeded:YES];
    NSRect newViewport = [app appKitFrameForWindowItem:app.windows.firstObject];
    Check(NSWidth(newViewport) > 100, @"几何跟随：新画面区域可用");
    Check(app.inlineExpandedReadingPanel != nil, @"几何跟随：几何变化后展开卡仍然打开");
    if (app.inlineExpandedReadingPanel) {
        NSRect frame = app.inlineExpandedReadingPanel.frame;
        Check(NSMinX(frame) >= NSMinX(newViewport) - 0.5 && NSMaxX(frame) <= NSMaxX(newViewport) + 0.5 &&
              NSMinY(frame) >= NSMinY(newViewport) - 0.5 && NSMaxY(frame) <= NSMaxY(newViewport) + 0.5,
              [NSString stringWithFormat:@"几何跟随：展开卡重新落进新画面区域（卡 %@ / 区域 %@）",
               NSStringFromRect(frame), NSStringFromRect(newViewport)]);
    }
    // 下一帧用新几何重排：展开卡仍在，且仍在画面内。
    [app showInlineTranslations:FoldProfileTranslations(kFoldBodyTranslation)
                       forItems:FoldProfileItems()
                  placementRect:newViewport];
    Check(app.inlineExpandedReadingPanel != nil, @"几何跟随：新几何重排后展开卡仍在");
    if (app.inlineExpandedReadingPanel) {
        NSRect frame = app.inlineExpandedReadingPanel.frame;
        Check(NSMinX(frame) >= NSMinX(newViewport) - 0.5 && NSMaxX(frame) <= NSMaxX(newViewport) + 0.5 &&
              NSMinY(frame) >= NSMinY(newViewport) - 0.5 && NSMaxY(frame) <= NSMaxY(newViewport) + 0.5,
              @"几何跟随：重排后展开卡仍在画面内");
    }

    // 定位不可用（目标窗口暂时找不到）：展开卡必须收起，不能留在旧坐标。
    NSRect stale = app.inlineExpandedReadingPanel ? app.inlineExpandedReadingPanel.frame : NSZeroRect;
    app.fixtureTargetUnavailable = YES;
    [app refreshDisplayGeometryIfNeeded:YES];
    Check(app.inlineExpandedReadingPanel == nil, @"几何跟随：定位不可用时展开卡收起（不留在旧坐标）");
    Check(app.inlineExpandedReadingKeyMonitor == nil, @"几何跟随：收起后 Esc 监视器已卸载");
    Check(NSWidth(stale) > 0, @"几何跟随：对照成立（收起前确实有一个旧坐标）");
}

#pragma mark - 11. 极端降级：「还有 N 条译文」+ 集中选择

static void TestOverflowEntryAndChooser(void) {
    // 极小画面塞三块长正文：必然有人连折叠入口都放不下。
    NSRect viewport = NSMakeRect(0, 0, 260, 150);
    FoldApp *app = FoldFixtureApp(viewport);
    OCRTextItem *first = FoldItem(@"校内でスリリングなことばかりしている彼は、\nアクティブで好奇心旺盛。退屈を嫌い、\nいつも何か新しいことに挑戦している。",
                                  CGRectMake(0.04, 0.42, 0.92, 0.30), InlineBlockKindLong, nil);
    OCRTextItem *second = FoldItem(@"スリルを求めて行動するのが好きで、\nじっとしているのは苦手なのだ。\n海とドライブが大好きです。",
                                   CGRectMake(0.04, 0.06, 0.92, 0.30), InlineBlockKindLong, nil);
    OCRTextItem *third = FoldItem(@"その他のかなり長い説明文がここに続きます。\n読み飛ばさないでください。",
                                  CGRectMake(0.30, 0.66, 0.66, 0.22), InlineBlockKindLong, nil);
    NSArray<NSString *> *translations = @[kFoldBodyTranslation,
                                          @"喜欢追求惊险刺激，静不下来。喜欢大海和兜风。",
                                          @"其它的长说明文在这里继续，请不要跳过。"];
    [app showInlineTranslations:translations forItems:@[first, second, third] placementRect:viewport];
    Check(app.inlineOverflowPanel != nil, @"极端降级：画面边缘出现总入口面板");
    if (!app.inlineOverflowPanel) { return; }
    Check(app.inlineOverflowCount >= 1 && app.inlineOverflowEntries.count == app.inlineOverflowCount,
          [NSString stringWithFormat:@"极端降级：总入口记录了 %lu 条放不下的译文", (unsigned long)app.inlineOverflowCount]);
    FYInlineLongCardView *overflowCard = (FYInlineLongCardView *)app.inlineOverflowPanel.contentView;
    Check([overflowCard isKindOfClass:FYInlineLongCardView.class], @"极端降级：总入口是卡片视图");
    BOOL hasCountLabel = NO;
    if ([overflowCard isKindOfClass:FYInlineLongCardView.class]) {
        for (NSView *sub in overflowCard.subviews) {
            if (![sub isKindOfClass:NSTextField.class]) { continue; }
            NSString *text = [(NSTextField *)sub stringValue] ?: @"";
            if ([text containsString:@"还有"] && [text containsString:@"条译文"]) { hasCountLabel = YES; }
        }
    }
    Check(hasCountLabel, @"极端降级：总入口有「还有 N 条译文」这样的可见文案");
    Check(overflowCard.onClick != nil, @"极端降级：总入口可点击");
    overflowCard.onClick();
    Check(app.inlineOverflowChoicePanel != nil, @"极端降级：点击总入口打开集中选择面板");
    if (!app.inlineOverflowChoicePanel) { return; }
    NSArray<NSButton *> *rows = FoldChooserRows(app);
    Check(rows.count == app.inlineOverflowEntries.count,
          [NSString stringWithFormat:@"极端降级：集中选择每一条放不下的译文一行（%lu/%lu）",
           (unsigned long)rows.count, (unsigned long)app.inlineOverflowEntries.count]);
    if (rows.count == 0) { return; }
    NSString *expected = app.inlineOverflowEntries.firstObject[@"translation"] ?: @"";
    NSString *blockID = app.inlineOverflowEntries.firstObject[@"blockID"] ?: @"";
    [rows.firstObject performClick:nil];
    Check(app.inlineOverflowChoicePanel == nil, @"极端降级：选中后集中选择面板关闭");
    Check(app.inlineExpandedReadingPanel != nil, @"极端降级：点某一行打开完整阅读卡");
    if (app.inlineExpandedReadingPanel) {
        FYInlineLongCardView *expanded = (FYInlineLongCardView *)app.inlineExpandedReadingPanel.contentView;
        NSScrollView *scroll = FoldScrollOf(expanded);
        Check(FoldScrollShows(scroll, [expected substringToIndex:MIN((NSUInteger)12, expected.length)]),
              @"极端降级：展开卡里是这一条的完整译文");
        Check(app.inlineExpandedReadingBlockID && [app.inlineExpandedReadingBlockID isEqualToString:blockID],
              @"极端降级：展开卡对应选中的那一条（blockID 对得上）");
    }

    // 反面：空间充足时不该有这个总入口。
    FoldApp *roomy = FoldFixtureApp(NSMakeRect(0, 0, 1000, 700));
    NSRect roomyViewport = NSMakeRect(0, 0, 1000, 700);
    [roomy showInlineTranslations:@[@"返回"]
                        forItems:@[FoldItem(@"戻る", CGRectMake(0.10, 0.60, 0.12, 0.06), InlineBlockKindShort, nil)]
                   placementRect:roomyViewport];
    Check(roomy.inlineOverflowPanel == nil || !roomy.inlineOverflowPanel.isVisible,
          @"极端降级：空间充足时没有「还有 N 条译文」总入口");
    Check(roomy.inlineOverflowCount == 0, @"极端降级：空间充足时放不下条数为 0");
}

#pragma mark - 12. 样式/范围守卫

static void TestStyleScopeGuard(void) {
    Check(FYAdventureColor(@"mint") != nil && FYAdventureColor(@"rim") != nil,
          @"样式守卫：折叠入口/展开卡复用的主题色仍可取得（没有新增设置页或透明度控件）");
    // 折叠入口与展开卡都必须是同一套长卡视图渲染，没有另起一套设置界面。
    FoldApp *app = FoldFixtureApp(FoldViewport());
    Check([app.inlineLayoutEngine.foldedEntryFallbackTitle isEqualToString:@"这段译文"],
          @"样式守卫：占位标题仍是「这段译文」");
    BOOL hintsOk = [app.inlineLayoutEngine.foldedEntryHintTooLong isEqualToString:@"文本过长，已收起"] &&
                   [app.inlineLayoutEngine.foldedEntryHintCrowded isEqualToString:@"空间不足，已收起"];
    Check(hintsOk, @"样式守卫：两种收起原因文案稳定（可被用户与测试对上）");
}

#pragma mark - 截图

static void FoldSaveCanvas(NSImage *image, NSString *path) {
    if (!image || path.length == 0) { return; }
    CGImageRef cg = [image CGImageForProposedRect:NULL context:NULL hints:NULL];
    if (!cg) { return; }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (png) { [png writeToFile:path atomically:YES]; }
}

static void FoldDrawRect(NSRect rect, NSRect offset, NSColor *fill, NSColor *stroke, CGFloat width) {
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

/// 三个状态的对照图：灰底=画面、蓝框=OCR 原文块、绿=折叠入口/展开卡、黄=短贴片。
/// 位置全部来自**真实面板 frame** 与真实原文框；标签用 NSString drawAtPoint: 画进图里。
static void FoldDrawState(FoldApp *app, NSArray<OCRTextItem *> *items, NSRect viewport, NSString *path) {
    NSMutableArray<NSPanel *> *panels = [FoldPanels(app) mutableCopy];
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

    // 原文框：蓝色（正文块加粗）。
    for (OCRTextItem *item in items) {
        NSRect source = [app appKitFrameForOCRItem:item inWindowFrame:viewport];
        BOOL body = [item.text containsString:kFoldBodyNeedle];
        NSColor *fill = [NSColor colorWithCalibratedRed:0.16 green:0.42 blue:0.95 alpha:body ? 0.22 : 0.10];
        NSColor *stroke = [NSColor colorWithCalibratedRed:0.10 green:0.30 blue:0.80 alpha:body ? 0.95 : 0.45];
        FoldDrawRect(source, offset, fill, stroke, body ? 2.0 : 1.0);
    }

    // 面板：绿=长卡/折叠入口/展开卡，黄=短贴片；已隐藏的画成虚线感的细灰框。
    for (NSPanel *panel in panels) {
        BOOL visible = panel.isVisible;
        BOOL isCard = [panel.contentView isKindOfClass:FYInlineLongCardView.class];
        NSColor *fill = isCard ? [NSColor colorWithCalibratedRed:0.08 green:0.62 blue:0.33 alpha:0.85]
                               : [NSColor colorWithCalibratedRed:0.95 green:0.78 blue:0.15 alpha:0.85];
        NSColor *stroke = isCard ? [NSColor colorWithCalibratedRed:0.04 green:0.42 blue:0.22 alpha:1.0]
                                 : [NSColor colorWithCalibratedRed:0.72 green:0.55 blue:0.05 alpha:1.0];
        if (!visible) {
            FoldDrawRect(panel.frame, offset, nil, [NSColor colorWithCalibratedWhite:0.55 alpha:0.55], 1.0);
            continue;
        }
        FoldDrawRect(panel.frame, offset, fill, stroke, 1.5);
        // 把卡上每一行可见文字原样画进图里（位置取真实 label frame）。
        NSView *content = panel.contentView;
        if ([content isKindOfClass:FYInlineLongCardView.class]) {
            for (NSView *sub in content.subviews) {
                if (![sub isKindOfClass:NSTextField.class]) { continue; }
                NSTextField *label = (NSTextField *)sub;
                if (label.stringValue.length == 0) { continue; }
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
    FoldSaveCanvas(image, path);
}

static void TestScreenshots(void) {
    if (gOutputDirectory.length == 0) { return; }
    [[NSFileManager defaultManager] createDirectoryAtPath:gOutputDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    FoldApp *app = FoldFixtureApp(FoldViewport());
    NSArray<OCRTextItem *> *items = FoldProfileItems();
    [app showInlineTranslations:FoldProfileTranslations(FoldLongBodyTranslation())
                       forItems:items
                  placementRect:FoldViewport()];
    NSString *folded = [gOutputDirectory stringByAppendingPathComponent:@"fold-state-folded.png"];
    FoldDrawState(app, items, FoldViewport(), folded);

    FYInlinePlacement *placement = FoldPlacementFor(app, kFoldBodyNeedle);
    NSPanel *entryPanel = FoldPanelForBlockID(app, placement.blockID);
    [(FYInlineLongCardView *)entryPanel.contentView onClick]();
    NSString *expanded = [gOutputDirectory stringByAppendingPathComponent:@"fold-state-expanded.png"];
    FoldDrawState(app, items, FoldViewport(), expanded);

    if (app.inlineExpandedReadingPanel) {
        FYInlineLongCardView *card = (FYInlineLongCardView *)app.inlineExpandedReadingPanel.contentView;
        [card.collapseButton performClick:nil];
    }
    NSString *restored = [gOutputDirectory stringByAppendingPathComponent:@"fold-state-restored.png"];
    FoldDrawState(app, items, FoldViewport(), restored);

    NSFileManager *manager = [NSFileManager defaultManager];
    Check([manager fileExistsAtPath:folded] && [manager fileExistsAtPath:expanded] && [manager fileExistsAtPath:restored],
          @"截图：写出折叠 / 展开 / 恢复三个状态的对照图");
}

#pragma mark - main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        unsetenv("FUYI_DIAG");
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if (argc > 1) { gOutputDirectory = [NSString stringWithUTF8String:argv[1]]; }

        TestFoldedEntryAppearance();
        TestExpandCollapseByRealControl();
        TestJitterKeepsExpandedCard();
        TestCollapseButtonTakesRealClick();
    TestMissingFrameClosesAfterTwo();
        TestNoExtraTranslationRequests();
        TestSameTextTwoPlaces();
        TestGeometryChangeForExpandedCard();
        TestOverflowEntryAndChooser();
        TestStyleScopeGuard();
        TestScreenshots();

        Require(gFailures == 0, [NSString stringWithFormat:@"%lu 条断言失败", (unsigned long)gFailures]);
        printf("PASS InlineFoldReadTests: %lu 条断言；折叠入口三行文案与按内容测量 / 点击展开 / 展开互斥不挡鼠标 / 按钮收起恢复原位 / 抖动与丢帧稳定 / 展开收起零翻译请求 / 同文两处不串 / 几何跟随与定位不可用收起 / 「还有 N 条译文」集中选择 / 三态对照图\n",
               (unsigned long)gChecks);
    }
    return 0;
}
