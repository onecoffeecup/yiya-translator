// 评审四组修复的验收（2026-10-06 晚 · 第三轮）
//
// 对应四组缺陷：
//   ① 全屏投影接管：取消"面积必须大 30%"的必要条件，改用「同 owner + 画面窗口 + 排在选中窗口前面
//      + 覆盖选中窗口 ≥60% + 面积 ≥ 原窗口 0.9 倍」；多个候选时只有"完全包含 + 接近整屏"的那个才接管，
//      否则 ambiguous=YES 返回 0。
//   ② 目标对象身份：解析出 9602 但 9602 不在下拉列表时必须现造同 ID 对象（windowItemForResolvedTargetID:），
//      不修改原选中对象，几何 token 跟着变、refresh 立即隐藏旧贴译。
//   ③ 「选择要读的译文」面板：documentView 有真实尺寸、行按钮 ≥100×24 且落在可见区内、
//      面板不出画面、有可见「关闭」按钮；单条溢出直接打开阅读卡。
//   ④ 展开互斥在真实渲染路径后仍成立；折叠入口卡不透明、提示深色且不截断。
//
// 走真实入口：resolveDisplayTargetWindowIDInWindowList: / refreshDisplayGeometryIfNeeded: /
// showInlineTranslations: / handleInlineTranslationResult: / showInlineOverflowChooser /
// openInlineOverflowRow: / card.onClick / collapseButton performClick / clearInlineTranslationPanels。

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

static NSString *const kRfBodyNeedle = @"校内でスリリング";
static NSString *const kRfBodyTranslation = @"在校内总做些刺激的事，他活泼又好奇心旺盛。讨厌无聊，总是挑战新事物。喜欢追求惊险刺激，静不下来。";

@interface RfApp : AppDelegate
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *liveBounds;
@property (nonatomic) uint32_t fixtureTargetID;
@property (nonatomic) BOOL fixtureTargetUnavailable;
@property (nonatomic) NSUInteger translateCallCount;
@property (nonatomic, copy) NSArray<NSString *> *fixtureTranslations;
@end

@implementation RfApp
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

static RfApp *RfFixtureApp(NSRect windowBounds, uint32_t windowID) {
    RfApp *app = [[RfApp alloc] init];
    [app createMainWindow];
    app.inlineTranslationPanels = [NSMutableArray array];
    app.inlineLongCardPanels = [NSMutableArray array];
    app.inlineTranslationCache = [NSMutableDictionary dictionary];
    app.captionFontSizeSlider = [NSSlider sliderWithValue:30 minValue:12 maxValue:48 target:nil action:nil];
    app.captionOpacitySlider = [NSSlider sliderWithValue:0.58 minValue:0 maxValue:1 target:nil action:nil];
    WindowItem *window = [[WindowItem alloc] init];
    window.windowID = windowID;
    window.displayName = @"RfFixture";
    window.bounds = windowBounds;
    app.windows = [NSMutableArray arrayWithObject:window];
    app.windowPopup = [[NSPopUpButton alloc] init];
    [app.windowPopup addItemWithTitle:@"RfFixture"];
    app.windowPopup.menu.itemArray.firstObject.representedObject = @(windowID);
    app.fixtureTargetID = windowID;
    app.fixtureTargetUnavailable = NO;
    app.liveBounds = [NSMutableDictionary dictionary];
    app.fixtureTranslations = @[];
    return app;
}

/// 解析策略用的干净 AppDelegate（不覆盖 resolve，走产品真实实现）。
static AppDelegate *RfResolutionApp(uint32_t selectedID, CGRect selectedBounds) {
    AppDelegate *app = [[AppDelegate alloc] init];
    [app createMainWindow];
    WindowItem *window = [[WindowItem alloc] init];
    window.windowID = selectedID;
    window.displayName = @"OBS";
    window.bounds = selectedBounds;
    app.windows = [NSMutableArray arrayWithObject:window];
    app.windowPopup = [[NSPopUpButton alloc] init];
    [app.windowPopup addItemWithTitle:@"OBS"];
    app.windowPopup.menu.itemArray.firstObject.representedObject = @(selectedID);
    return app;
}

static NSDictionary *RfWindowInfo(uint32_t windowID, pid_t pid, NSString *title, CGRect bounds) {
    return @{(id)kCGWindowNumber: @(windowID),
             (id)kCGWindowOwnerPID: @(pid),
             (id)kCGWindowOwnerName: @"OBS",
             (id)kCGWindowName: title ?: @"OBS",
             (id)kCGWindowLayer: @0,
             (id)kCGWindowBounds: CFBridgingRelease(CGRectCreateDictionaryRepresentation(bounds))};
}

static OCRTextItem *RfItem(NSString *text, CGRect box, InlineBlockKind kind, NSArray<NSValue *> *lineBoxes) {
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

static NSScrollView *RfScrollOf(NSView *view) {
    for (NSView *child in view.subviews) {
        if ([child isKindOfClass:NSScrollView.class]) { return (NSScrollView *)child; }
    }
    return nil;
}

static void RfCollectButtons(NSView *view, NSMutableArray<NSButton *> *buttons) {
    if ([view isKindOfClass:NSButton.class]) { [buttons addObject:(NSButton *)view]; }
    for (NSView *child in view.subviews) { RfCollectButtons(child, buttons); }
}

static NSButton *RfButtonWithTitle(NSView *view, NSString *title) {
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    RfCollectButtons(view, buttons);
    for (NSButton *button in buttons) {
        if ([button.title isEqualToString:title]) { return button; }
    }
    return nil;
}

static NSArray<NSPanel *> *RfPanels(RfApp *app) {
    return [app.inlineTranslationPanels arrayByAddingObjectsFromArray:app.inlineLongCardPanels];
}

static NSPanel *RfPanelForBlockID(RfApp *app, NSString *blockID) {
    if (blockID.length == 0) { return nil; }
    for (NSPanel *panel in RfPanels(app)) {
        if ([panel.identifier isEqualToString:blockID]) { return panel; }
    }
    return nil;
}

static FYInlinePlacement *RfPlacementFor(AppDelegate *app, NSString *needle) {
    for (FYInlinePlacement *placement in app.lastInlineLayoutResult.placements) {
        if ([placement.block.text containsString:needle]) { return placement; }
    }
    return nil;
}

static NSTextField *RfTitleLabel(FYInlineLongCardView *card) {
    for (NSView *sub in card.subviews) {
        if (![sub isKindOfClass:NSTextField.class]) { continue; }
        NSTextField *label = (NSTextField *)sub;
        if (label == card.foldedEntryHintLabel || label == card.foldedEntryActionLabel ||
            label == card.expandedFooterLabel) { continue; }
        if (label.stringValue.length == 0) { continue; }
        return label;
    }
    return nil;
}

#pragma mark - 场景

/// 现场资料页（拥挤）：长正文必然折叠，短标签若干。
static NSArray<OCRTextItem *> *RfCrowdedItems(void) {
    NSArray<NSValue *> *bodyLines = @[
        [NSValue valueWithRect:CGRectMake(0.178, 0.322, 0.215, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.296, 0.200, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.270, 0.205, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.244, 0.195, 0.026)],
        [NSValue valueWithRect:CGRectMake(0.178, 0.218, 0.170, 0.026)]
    ];
    return @[
        RfItem(@"◆桜井琉夏の好み◆", CGRectMake(0.178, 0.361, 0.180, 0.038), InlineBlockKindShort, nil),
        RfItem(@"身長", CGRectMake(0.513, 0.388, 0.050, 0.047), InlineBlockKindShort, nil),
        RfItem(@"体重", CGRectMake(0.513, 0.317, 0.050, 0.053), InlineBlockKindShort, nil),
        RfItem(@"バイト", CGRectMake(0.515, 0.263, 0.070, 0.041), InlineBlockKindShort, nil),
        RfItem(@"花屋アンネリー", CGRectMake(0.608, 0.263, 0.168, 0.041), InlineBlockKindShort, nil),
        RfItem(@"クラブ", CGRectMake(0.517, 0.201, 0.070, 0.041), InlineBlockKindShort, nil),
        RfItem(@"帰宅部\n桜井琥一の弟。\nスリルは彼の活力。", CGRectMake(0.608, 0.079, 0.204, 0.164), InlineBlockKindShort, nil),
        RfItem(@"みよのメモ", CGRectMake(0.180, 0.426, 0.098, 0.038), InlineBlockKindShort, nil),
        RfItem(@"校内でスリリングなことばかりしている彼は、\nアクティブで好奇心旺盛。退屈を嫌い、\nいつも何か新しいことに挑戦している。\nスリルを求めて行動するのが好きで、\nじっとしているのは苦手なのだ。",
                CGRectMake(0.178, 0.218, 0.215, 0.130), InlineBlockKindLong, bodyLines)
    ];
}

static NSArray<NSString *> *RfCrowdedTranslations(void) {
    // 入口专项测试使用长译文，避免短译文高度收紧后直接以完整长卡显示。
    NSString *longBody = [NSString stringWithFormat:@"%@\n%@\n%@", kRfBodyTranslation, kRfBodyTranslation, kRfBodyTranslation];
    return @[@"◆樱井琉夏的喜好◆", @"身高", @"体重", @"打工", @"花店安妮莉", @"社团",
             @"回家部\n桜井琥一的弟弟。刺激是他的活力。", @"美代的笔记", longBody];
}

static OCRTextItem *RfCrowdedBodyJittered(void) {
    OCRTextItem *item = RfCrowdedItems().lastObject;
    CGRect box = item.boundingBox;
    box.origin.x += 0.0015;
    box.origin.y -= 0.0015;
    OCRTextItem *moved = RfItem(item.text, box, InlineBlockKindLong, item.lineBoxes);
    moved.lineTexts = item.lineTexts;
    return moved;
}

static NSArray<OCRTextItem *> *RfCrowdedItemsJittered(void) {
    NSMutableArray<OCRTextItem *> *items = [RfCrowdedItems() mutableCopy];
    items[items.count - 1] = RfCrowdedBodyJittered();
    return items;
}

/// 「琉夏喜好」稀疏页：长正文 + 分散的短标签。
static NSArray<OCRTextItem *> *RfSparseItems(void) {
    NSArray<NSValue *> *bodyLines = @[
        [NSValue valueWithRect:CGRectMake(0.20, 0.86, 0.24, 0.05)],
        [NSValue valueWithRect:CGRectMake(0.20, 0.80, 0.24, 0.05)],
        [NSValue valueWithRect:CGRectMake(0.20, 0.74, 0.24, 0.05)],
        [NSValue valueWithRect:CGRectMake(0.20, 0.68, 0.24, 0.05)],
        [NSValue valueWithRect:CGRectMake(0.20, 0.62, 0.24, 0.05)]
    ];
    return @[
        RfItem(@"◆桜井琉夏の好み◆", CGRectMake(0.20, 0.94, 0.18, 0.04), InlineBlockKindShort, nil),
        RfItem(@"身長", CGRectMake(0.70, 0.72, 0.05, 0.05), InlineBlockKindShort, nil),
        RfItem(@"体重", CGRectMake(0.70, 0.60, 0.05, 0.05), InlineBlockKindShort, nil),
        RfItem(@"戻る", CGRectMake(0.88, 0.06, 0.08, 0.05), InlineBlockKindShort, nil),
        RfItem(@"校内でスリリングなことばかりしている彼は、\nアクティブで好奇心旺盛。退屈を嫌い、\nいつも何か新しいことに挑戦している。\nスリルを求めて行動するのが好きで、\nじっとしているのは苦手なのだ。",
                CGRectMake(0.20, 0.62, 0.24, 0.29), InlineBlockKindLong, bodyLines)
    ];
}

static NSArray<NSString *> *RfSparseTranslations(void) {
    return @[@"◆樱井琉夏的喜好◆", @"身高", @"体重", @"返回", kRfBodyTranslation];
}

/// 极小画面里塞 count 块长正文：用来制造「放不下」→ 总入口清单。
static NSArray<OCRTextItem *> *RfDenseItems(NSUInteger count) {
    NSMutableArray<OCRTextItem *> *items = [NSMutableArray array];
    CGFloat step = 0.9 / (CGFloat)MAX((NSUInteger)1, count);
    for (NSUInteger index = 0; index < count; index++) {
        NSString *text = [NSString stringWithFormat:@"長い説明文の%lu番目です。\n二行目の続きです。\n三行目の終わりです。",
                          (unsigned long)(index + 1)];
        CGRect box = CGRectMake(0.04, 0.05 + step * (CGFloat)index, 0.92, MAX((CGFloat)0.10, step * 0.8));
        [items addObject:RfItem(text, box, InlineBlockKindLong, nil)];
    }
    return items;
}

static NSArray<NSString *> *RfDenseTranslations(NSUInteger count) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSUInteger index = 0; index < count; index++) {
        [values addObject:[NSString stringWithFormat:@"这是第 %lu 段很长的说明文字，用来占满屏幕并验证兜底入口。",
                           (unsigned long)(index + 1)]];
    }
    return values;
}

static CGFloat RfRectDistance(NSRect a, NSRect b) {
    CGFloat dx = MAX(0, MAX(NSMinX(b) - NSMaxX(a), NSMinX(a) - NSMaxX(b)));
    CGFloat dy = MAX(0, MAX(NSMinY(b) - NSMaxY(a), NSMinY(a) - NSMaxY(b)));
    return hypot(dx, dy);
}

/// 短贴片是否真的锚在**自己的**原文上（按布局器给出的 anchor 方向判定）。
/// 只看"离哪个原文最近"会误判：下方锚点的贴片可能正好落在下一个字段上方。
static BOOL RfPlacementAnchoredToOwnSource(FYInlinePlacement *placement) {
    NSRect source = placement.sourceFrame;
    NSRect frame = placement.translationFrame;
    // 相邻锚点（下方/上方/左/右）与原文之间有几像素间隙，矩形交集必然为空；
    // 所以横/纵重叠要按各自的区间分别算，不能用 CGRectIntersection。
    CGFloat overlapX = MAX(0, MIN(NSMaxX(source), NSMaxX(frame)) - MAX(NSMinX(source), NSMinX(frame)));
    CGFloat overlapY = MAX(0, MIN(NSMaxY(source), NSMaxY(frame)) - MAX(NSMinY(source), NSMinY(frame)));
    CGFloat overlayArea = overlapX * overlapY;
    CGFloat minWidth = MIN(NSWidth(source), NSWidth(frame));
    CGFloat minHeight = MIN(NSHeight(source), NSHeight(frame));
    CGFloat gapX = MAX(0, MAX(NSMinX(source) - NSMaxX(frame), NSMinX(frame) - NSMaxX(source)));
    CGFloat gapY = MAX(0, MAX(NSMinY(source) - NSMaxY(frame), NSMinY(frame) - NSMaxY(source)));
    switch (placement.anchor) {
        case FYInlineAnchorBelow:
            return gapY <= 12 && overlapX >= minWidth * 0.4 && NSMinY(frame) <= NSMinY(source) + 1;
        case FYInlineAnchorAbove:
            return gapY <= 12 && overlapX >= minWidth * 0.4 && NSMaxY(frame) >= NSMaxY(source) - 1;
        case FYInlineAnchorRight:
            return gapX <= 12 && overlapY >= minHeight * 0.4 && NSMinX(frame) >= NSMinX(source) - 1;
        case FYInlineAnchorLeft:
            return gapX <= 12 && overlapY >= minHeight * 0.4 && NSMaxX(frame) <= NSMaxX(source) + 1;
        case FYInlineAnchorOverlay:
            return overlayArea >= NSWidth(frame) * NSHeight(frame) * 0.3;
        default:
            return RfRectDistance(frame, source) <= MAX(NSHeight(source), NSHeight(frame)) + 12;
    }
}

static BOOL RfFrameInside(NSRect frame, NSRect outer) {
    return NSMinX(frame) >= NSMinX(outer) - 1 && NSMaxX(frame) <= NSMaxX(outer) + 1 &&
           NSMinY(frame) >= NSMinY(outer) - 1 && NSMaxY(frame) <= NSMaxY(outer) + 1;
}

#pragma mark - ① 全屏投影接管策略

static void TestResolveFullscreenTakeover(void) {
    const uint32_t selected = 9601;
    pid_t obsPID = 12345;
    CGRect selectedBounds = CGRectMake(0, 38, 1644, 961);
    AppDelegate *app = RfResolutionApp(selected, selectedBounds);
    BOOL ambiguous = NO;
    NSString *note = nil;

    // 主用例（评审探针）：选中 1644×961@(0,38)，前方 1710×1112@(0,0) → 必须接管。
    uint32_t got = [app resolveDisplayTargetWindowIDInWindowList:
                    @[RfWindowInfo(9602, obsPID, @"OBS", CGRectMake(0, 0, 1710, 1112)),
                      RfWindowInfo(selected, obsPID, @"OBS", selectedBounds)]
                                                     ambiguous:&ambiguous note:&note];
    Check(got == 9602 && !ambiguous,
          [NSString stringWithFormat:@"接管：全屏投影 1710×1112 接管选中的 1644×961（got=%u ambiguous=%d）", got, ambiguous]);

    // ① 小对话框：同 owner、在前面、面积小且没盖住 → 不接管。
    got = [app resolveDisplayTargetWindowIDInWindowList:
           @[RfWindowInfo(9603, obsPID, @"预览", CGRectMake(200, 160, 700, 500)),
             RfWindowInfo(selected, obsPID, @"OBS", selectedBounds)]
                                            ambiguous:&ambiguous note:&note];
    Check(got == selected && !ambiguous,
          [NSString stringWithFormat:@"接管：前面同 owner 的小对话框不接管（got=%u）", got]);

    // ③ 不同 owner 的大窗口：不接管。
    got = [app resolveDisplayTargetWindowIDInWindowList:
           @[RfWindowInfo(9604, 99999, @"OBS", CGRectMake(0, 0, 1710, 1112)),
             RfWindowInfo(selected, obsPID, @"OBS", selectedBounds)]
                                            ambiguous:&ambiguous note:&note];
    Check(got == selected && !ambiguous,
          [NSString stringWithFormat:@"接管：不同 owner 的大窗口不接管（got=%u）", got]);

    // ④ 没有候选：沿用用户选择。
    got = [app resolveDisplayTargetWindowIDInWindowList:@[RfWindowInfo(selected, obsPID, @"OBS", selectedBounds)]
                                            ambiguous:&ambiguous note:&note];
    Check(got == selected && !ambiguous, @"接管：没有候选时沿用用户选择");

    // ② 两个都「完全包含 + 接近整屏」→ 无法确定，ambiguous=YES 且返回 0。
    AppDelegate *twin = RfResolutionApp(9611, CGRectMake(100, 50, 900, 600));
    CGRect display = CGDisplayBounds(CGMainDisplayID());
    uint32_t gotTwin = [twin resolveDisplayTargetWindowIDInWindowList:
                        @[RfWindowInfo(9612, obsPID, @"OBS", display),
                          RfWindowInfo(9613, obsPID, @"OBS", CGRectInset(display, 6, 6)),
                          RfWindowInfo(9611, obsPID, @"OBS", CGRectMake(100, 50, 900, 600))]
                                                       ambiguous:&ambiguous note:&note];
    Check(gotTwin == 0 && ambiguous,
          [NSString stringWithFormat:@"接管：两个完全包含且接近整屏的候选 → ambiguous 且返回 0（got=%u ambiguous=%d）", gotTwin, ambiguous]);
    Check(note.length > 0, [NSString stringWithFormat:@"接管：无法确定时给出可操作提示（%@）", note ?: @"(nil)"]);
}

#pragma mark - ② 目标对象身份与几何跟随

static void TestResolvedTargetIdentityAndGeometry(void) {
    const uint32_t selected = 9601, projector = 9602;
    NSRect windowBounds = NSMakeRect(0, 38, 1644, 961);
    RfApp *app = RfFixtureApp(windowBounds, selected);
    app.liveBounds[@(selected)] = [NSValue valueWithRect:NSMakeRect(0, 38, 1644, 961)];
    app.liveBounds[@(projector)] = [NSValue valueWithRect:NSMakeRect(0, 0, 1710, 1112)];

    // 先在第一帧（9601）上渲染贴译。
    [app showInlineTranslations:RfSparseTranslations() forItems:RfSparseItems() placementRect:NSMakeRect(0, 38, 1644, 961)];
    NSUInteger visibleAtStart = 0;
    for (NSPanel *panel in RfPanels(app)) { if (panel.isVisible) { visibleAtStart += 1; } }
    Check(visibleAtStart >= 1, @"目标身份：9601 上先渲染出可见贴译");
    NSString *tokenBefore = app.lastDisplayGeometryToken;

    // 解析目标切到 9602（投影还没进下拉列表）。
    app.fixtureTargetID = projector;
    [app refreshDisplayGeometryIfNeeded:YES];
    Check([app displayTargetWindowID] == projector,
          [NSString stringWithFormat:@"目标身份：解析目标切到 9602（%u）", [app displayTargetWindowID]]);
    Check([app windowItemForWindowID:projector] == nil, @"目标身份：9602 确实不在下拉列表里");
    WindowItem *target = [app displayTargetWindowItem];
    Check(target != nil && target.windowID == projector,
          [NSString stringWithFormat:@"目标身份：为解析目标现造对象且 ID 一致（%@）",
           target ? @(target.windowID).stringValue : @"(nil)"]);
    if (target) {
        NSRect frame = [app appKitFrameForWindowItem:target];
        Check(fabs(NSWidth(frame) - 1710) < 1 && fabs(NSHeight(frame) - 1112) < 1,
              [NSString stringWithFormat:@"目标身份：现造对象拿到 9602 的实时框（%@）", NSStringFromRect(frame)]);
    }
    Check(app.selectedWindowItem.windowID == selected, @"目标身份：没有修改原选中对象（仍是 9601）");
    Check(NSEqualRects(app.selectedWindowItem.bounds, windowBounds), @"目标身份：原选中对象的 bounds 没被改写");
    Check(app.lastDisplayGeometryToken.length > 0 && ![app.lastDisplayGeometryToken isEqualToString:tokenBefore ?: @""],
          [NSString stringWithFormat:@"目标身份：几何 token 随目标变化（%@ → %@）",
           tokenBefore ?: @"(nil)", app.lastDisplayGeometryToken ?: @"(nil)"]);
    Check([app.lastDisplayGeometryToken containsString:@"t=9602"], @"目标身份：几何 token 指向 9602");

    // 换目标后 refresh 立即隐藏旧贴译（不依赖新一轮 OCR）。
    NSUInteger stillVisible = 0;
    for (NSPanel *panel in RfPanels(app)) { if (panel.isVisible) { stillVisible += 1; } }
    Check(stillVisible == 0,
          [NSString stringWithFormat:@"目标身份：换全屏投影后旧贴译立即隐藏（还剩 %lu）", (unsigned long)stillVisible]);

    // 同一静态画面来回切：贴译落在新窗口区域，且不新增翻译请求。
    app.fixtureTranslations = RfSparseTranslations();
    NSUInteger baseline = app.translateCallCount;
    [app translateInlineTextItems:RfSparseItems() completion:^(NSArray<NSString *> *translations, NSError *error) {}];
    Check(app.translateCallCount == baseline + 1, @"切换：翻译计数接缝可用（对照 +1）");
    NSUInteger afterControl = app.translateCallCount;

    NSRect projectorViewport = [app appKitFrameForWindowItem:target];
    [app showInlineTranslations:RfSparseTranslations() forItems:RfSparseItems() placementRect:projectorViewport];
    NSUInteger visibleOnProjector = 0, insideProjector = 0;
    for (NSPanel *panel in RfPanels(app)) {
        if (!panel.isVisible) { continue; }
        visibleOnProjector += 1;
        if (RfFrameInside(panel.frame, projectorViewport)) { insideProjector += 1; }
    }
    Check(visibleOnProjector >= 1 && insideProjector == visibleOnProjector,
          [NSString stringWithFormat:@"切换：贴译落在 9602 投影区域内（%lu/%lu）",
           (unsigned long)insideProjector, (unsigned long)visibleOnProjector]);

    // 切回 9601。
    app.fixtureTargetID = selected;
    [app refreshDisplayGeometryIfNeeded:YES];
    Check([app displayTargetWindowID] == selected, @"切换：解析目标切回 9601");
    NSRect editorViewport = [app appKitFrameForWindowItem:app.selectedWindowItem];
    [app showInlineTranslations:RfSparseTranslations() forItems:RfSparseItems() placementRect:editorViewport];
    NSUInteger visibleOnEditor = 0, insideEditor = 0;
    for (NSPanel *panel in RfPanels(app)) {
        if (!panel.isVisible) { continue; }
        visibleOnEditor += 1;
        if (RfFrameInside(panel.frame, editorViewport)) { insideEditor += 1; }
    }
    Check(visibleOnEditor >= 1 && insideEditor == visibleOnEditor,
          [NSString stringWithFormat:@"切换：切回 9601 后贴译落在编辑器区域内（%lu/%lu）",
           (unsigned long)insideEditor, (unsigned long)visibleOnEditor]);
    Check(app.translateCallCount == afterControl,
          [NSString stringWithFormat:@"切换：来回切投影不新增翻译请求（%lu）", (unsigned long)app.translateCallCount]);
    Check(!NSEqualRects(projectorViewport, editorViewport), @"切换：两个窗口区域确实不同（对照）");
}

#pragma mark - ③ 「选择要读的译文」面板

static void TestChooserLayoutAndActions(void) {
    // 大窗口（决定选择面板的画面区域）+ 极小 placementRect（决定文字放不下）。
    RfApp *app = RfFixtureApp(NSMakeRect(457, 454, 1018, 574), 9701);
    NSRect tiny = NSMakeRect(457, 454, 260, 150);
    [app showInlineTranslations:RfDenseTranslations(3) forItems:RfDenseItems(3) placementRect:tiny];
    NSLog(@"DIAGNOSTIC 选择面板：placements=%lu unplaceable=%lu compactEntry=%lu overflow=%lu",
          (unsigned long)app.lastInlineLayoutResult.placements.count,
          (unsigned long)app.lastInlineUnplaceableCount,
          (unsigned long)app.lastInlineCompactEntryCount, (unsigned long)app.inlineOverflowCount);
    Check(app.inlineOverflowCount >= 2, [NSString stringWithFormat:@"选择面板：至少 2 条放不下（%lu）",
                                        (unsigned long)app.inlineOverflowCount]);
    Check(app.inlineOverflowPanel != nil, @"选择面板：总入口已建立");
    if (!app.inlineOverflowPanel) { return; }
    FYInlineLongCardView *overflowCard = (FYInlineLongCardView *)app.inlineOverflowPanel.contentView;
    overflowCard.onClick();
    Check(app.inlineOverflowChoicePanel != nil, @"选择面板：点总入口打开「选择要读的译文」");
    if (!app.inlineOverflowChoicePanel) { return; }

    NSRect viewport = NSZeroRect;
    BOOL hasViewport = [app inlinePlacementRect:&viewport reason:NULL];
    Check(hasViewport, @"选择面板：画面区域可用");
    NSRect panelFrame = app.inlineOverflowChoicePanel.frame;
    Check(RfFrameInside(panelFrame, viewport),
          [NSString stringWithFormat:@"选择面板：面板完整落在画面区域内（面板 %@ 区域 %@）",
           NSStringFromRect(panelFrame), NSStringFromRect(viewport)]);

    NSView *container = app.inlineOverflowChoicePanel.contentView;
    [container layoutSubtreeIfNeeded];
    NSScrollView *scroll = RfScrollOf(container);
    Check(scroll != nil, @"选择面板：有列表滚动区");
    if (!scroll) { return; }
    Check(scroll.documentView != nil && NSHeight(scroll.documentView.frame) > 0,
          [NSString stringWithFormat:@"选择面板：documentView 有真实高度（%@）",
           NSStringFromRect(scroll.documentView.frame)]);
    CGFloat expectedDocument = app.inlineOverflowEntries.count * 34;
    Check(NSHeight(scroll.documentView.frame) + 0.5 >= expectedDocument,
          [NSString stringWithFormat:@"选择面板：documentView 高 %.0f ≥ 行数×行高 %.0f",
           NSHeight(scroll.documentView.frame), expectedDocument]);

    NSMutableArray<NSButton *> *rows = [NSMutableArray array];
    RfCollectButtons(scroll.documentView, rows);
    [rows sortUsingComparator:^NSComparisonResult(NSButton *l, NSButton *r) { return l.tag < r.tag ? NSOrderedAscending : (l.tag > r.tag ? NSOrderedDescending : NSOrderedSame); }];
    Check(rows.count == app.inlineOverflowEntries.count,
          [NSString stringWithFormat:@"选择面板：每条一行（%lu/%lu）",
           (unsigned long)rows.count, (unsigned long)app.inlineOverflowEntries.count]);
    NSUInteger sized = 0, visibleRows = 0, titled = 0;
    for (NSButton *button in rows) {
        if (NSWidth(button.frame) >= 100 && NSHeight(button.frame) >= 24) { sized += 1; }
        NSRect inScroll = [button convertRect:button.bounds toView:scroll];
        NSRect shown = NSIntersectionRect(inScroll, scroll.contentView.bounds);
        CGFloat shownArea = CGRectIsNull(shown) ? 0 : shown.size.width * shown.size.height;
        CGFloat buttonArea = NSWidth(button.frame) * NSHeight(button.frame);
        if (buttonArea > 0 && shownArea / buttonArea >= 0.9) { visibleRows += 1; }
        if (button.title.length > 0) { titled += 1; }
    }
    Check(rows.count > 0 && sized == rows.count,
          [NSString stringWithFormat:@"选择面板：每个行按钮 ≥100×24（%lu/%lu）", (unsigned long)sized, (unsigned long)rows.count]);
    Check(rows.count > 0 && visibleRows == rows.count,
          [NSString stringWithFormat:@"选择面板：每个行按钮都在可见区内（%lu/%lu）", (unsigned long)visibleRows, (unsigned long)rows.count]);
    Check(rows.count > 0 && titled == rows.count, @"选择面板：行按钮标题非空（能看到原文/标题）");
    if (rows.count > 0) {
        NSDictionary *entry = app.inlineOverflowEntries.firstObject;
        NSString *title = entry[@"title"] ?: @"";
        Check(title.length > 0 && [rows.firstObject.title containsString:title],
              [NSString stringWithFormat:@"选择面板：行标题含这一条的标题（%@）", rows.firstObject.title]);
    }

    // 可见「关闭」按钮：尺寸、可见区、真实点击。
    NSButton *closeButton = RfButtonWithTitle(container, @"关闭");
    Check(closeButton != nil, @"选择面板：有「关闭」按钮");
    if (closeButton) {
        Check(NSWidth(closeButton.frame) > 0 && NSHeight(closeButton.frame) > 0,
              [NSString stringWithFormat:@"选择面板：关闭按钮尺寸有效（%@）", NSStringFromRect(closeButton.frame)]);
        Check(NSContainsRect(container.bounds, closeButton.frame), @"选择面板：关闭按钮在面板内");
        NSView *hit = [container hitTest:NSMakePoint(NSMidX(closeButton.frame), NSMidY(closeButton.frame))];
        Check(hit == closeButton || [hit isDescendantOf:closeButton],
              @"选择面板：关闭按钮在命中测试下可点到");
        Check(closeButton.target != nil && closeButton.action != NULL, @"选择面板：关闭按钮已接线");
        [closeButton performClick:nil];
        Check(app.inlineOverflowChoicePanel == nil, @"选择面板：点「关闭」后关闭");
    }

    // 可滚动：条目多时 documentView 高于可视区，滚到底后最后一行可见。
    RfApp *longList = RfFixtureApp(NSMakeRect(457, 454, 1018, 574), 9702);
    [longList showInlineTranslations:RfDenseTranslations(6) forItems:RfDenseItems(6) placementRect:tiny];
    NSLog(@"DIAGNOSTIC 可滚动：unplaceable=%lu overflow=%lu", (unsigned long)longList.lastInlineUnplaceableCount,
          (unsigned long)longList.inlineOverflowCount);
    Check(longList.inlineOverflowCount >= 5, [NSString stringWithFormat:@"选择面板：6 块场景至少 5 条放不下（%lu）",
                                              (unsigned long)longList.inlineOverflowCount]);
    FYInlineLongCardView *longCard = (FYInlineLongCardView *)longList.inlineOverflowPanel.contentView;
    longCard.onClick();
    if (longList.inlineOverflowChoicePanel) {
        NSScrollView *listScroll = RfScrollOf(longList.inlineOverflowChoicePanel.contentView);
        Check(listScroll != nil && NSHeight(listScroll.documentView.frame) > NSHeight(listScroll.contentView.bounds) + 0.5,
              [NSString stringWithFormat:@"选择面板：条目多时列表可滚动（doc %.0f > clip %.0f）",
               listScroll ? NSHeight(listScroll.documentView.frame) : 0,
               listScroll ? NSHeight(listScroll.contentView.bounds) : 0]);
        if (listScroll) {
            NSMutableArray<NSButton *> *many = [NSMutableArray array];
            RfCollectButtons(listScroll.documentView, many);
            [many sortUsingComparator:^NSComparisonResult(NSButton *l, NSButton *r) { return l.tag < r.tag ? NSOrderedAscending : (l.tag > r.tag ? NSOrderedDescending : NSOrderedSame); }];
            NSButton *last = many.lastObject;
            [listScroll.contentView scrollToPoint:NSMakePoint(0, MAX(0, NSHeight(listScroll.documentView.frame) - NSHeight(listScroll.contentView.bounds)))];
            [listScroll reflectScrolledClipView:listScroll.contentView];
            NSRect inScroll = [last convertRect:last.bounds toView:listScroll];
            NSRect shown = NSIntersectionRect(inScroll, listScroll.contentView.bounds);
            CGFloat ratio = NSWidth(last.frame) * NSHeight(last.frame) > 0
                ? (shown.size.width * shown.size.height) / (NSWidth(last.frame) * NSHeight(last.frame)) : 0;
            Check(last != nil && ratio >= 0.9,
                  [NSString stringWithFormat:@"选择面板：滚到底后最后一行可见（%.2f）", ratio]);
            // 点最后一行也能打开对应阅读卡。
            NSInteger tag = last.tag;
            NSString *expected = longList.inlineOverflowEntries[(NSUInteger)tag][@"translation"] ?: @"";
            [last performClick:nil];
            Check(longList.inlineOverflowChoicePanel == nil, @"选择面板：点行后选择面板关闭");
            Check(longList.inlineExpandedReadingPanel != nil, @"选择面板：点行后打开完整阅读卡");
            if (longList.inlineExpandedReadingPanel) {
                NSScrollView *reading = RfScrollOf(longList.inlineExpandedReadingPanel.contentView);
                BOOL shows = NO;
                if ([reading.documentView isKindOfClass:NSTextField.class] && expected.length > 0) {
                    shows = [[(NSTextField *)reading.documentView stringValue] containsString:
                             [expected substringToIndex:MIN((NSUInteger)10, expected.length)]];
                }
                Check(shows, @"选择面板：阅读卡内容对应点中的那一行");
            }
        }
    }
}

static void TestSingleOverflowOpensReadingCardDirectly(void) {
    RfApp *app = RfFixtureApp(NSMakeRect(457, 454, 1018, 574), 9703);
    OCRTextItem *only = RfItem(@"カレンのこと", CGRectMake(0.04, 0.42, 0.92, 0.30), InlineBlockKindLong, nil);
    app.inlineOverflowEntries = @[@{@"title": @"关于卡莲", @"source": only.text,
                                    @"translation": @"卡莲身边总是围满了女孩。", @"blockID": @"rf-only", @"item": only}];
    app.inlineOverflowCount = 1;
    [app buildInlineOverflowEntryForViewport:NSMakeRect(457, 454, 260, 150)];
    FYInlineLongCardView *card = (FYInlineLongCardView *)app.inlineOverflowPanel.contentView;
    Check([card isKindOfClass:FYInlineLongCardView.class], @"单条溢出：总入口卡片存在");
    if (![card isKindOfClass:FYInlineLongCardView.class]) { return; }
    // 诊断：单行总入口的实际高度 vs 只有一行文字时需要的高度。
    NSTextField *onlyTitle = RfTitleLabel(card);
    CGFloat oneLineHeight = 0;
    if (onlyTitle) {
        NSFont *titleFont = [app.inlineLayoutEngine compactEntryFont];
        oneLineHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading) + 14;
    }
    Check(oneLineHeight > 0 && NSHeight(app.inlineOverflowPanel.frame) <= oneLineHeight + 12,
          [NSString stringWithFormat:@"单条溢出：总入口高度按一行文字量（%.0f ≤ 一行 %.0f+12）",
           NSHeight(app.inlineOverflowPanel.frame), oneLineHeight]);
    card.onClick();
    Check(app.inlineOverflowChoicePanel == nil, @"单条溢出：不再多一步选择面板");
    Check(app.inlineExpandedReadingPanel != nil, @"单条溢出：直接打开该条的阅读卡");
    if (app.inlineExpandedReadingPanel) {
        NSScrollView *scroll = RfScrollOf(app.inlineExpandedReadingPanel.contentView);
        BOOL shows = NO;
        if ([scroll.documentView isKindOfClass:NSTextField.class]) {
            shows = [[(NSTextField *)scroll.documentView stringValue] containsString:@"卡莲身边总是围满了女孩"];
        }
        Check(shows, @"单条溢出：阅读卡里是这一条的完整译文");
        Check(app.inlineExpandedReadingBlockID.length > 0 && [app.inlineExpandedReadingBlockID isEqualToString:@"rf-only"],
              @"单条溢出：阅读卡绑定这一条的稳定身份");
    }
}

#pragma mark - ④ 展开互斥 + 入口可读性

static void TestExpandedExclusionAcrossRealRenders(void) {
    RfApp *app = RfFixtureApp(NSMakeRect(457, 454, 1018, 574), 9704);
    NSRect viewport = NSMakeRect(457, 454, 1018, 574);
    [app showInlineTranslations:RfCrowdedTranslations() forItems:RfCrowdedItems() placementRect:viewport];
    FYInlinePlacement *placement = RfPlacementFor(app, kRfBodyNeedle);
    Check(placement != nil && placement.mode == FYInlineDisplayModeCompactEntry, @"展开互斥：正文块是折叠入口");
    if (!placement || placement.mode != FYInlineDisplayModeCompactEntry) { return; }
    NSPanel *entryPanel = RfPanelForBlockID(app, placement.blockID);
    FYInlineLongCardView *entryCard = (FYInlineLongCardView *)entryPanel.contentView;
    entryCard.onClick();
    Check(app.inlineExpandedReadingPanel != nil, @"展开互斥：点击入口打开展开卡");
    if (!app.inlineExpandedReadingPanel) { return; }

    NSArray<NSPanel *> *(^others)(void) = ^NSArray<NSPanel *> *{
        NSMutableArray<NSPanel *> *list = [NSMutableArray array];
        for (NSPanel *panel in RfPanels(app)) { if (panel != app.inlineExpandedReadingPanel) { [list addObject:panel]; } }
        return list;
    };
    NSArray<NSPanel *> *first = others();
    NSUInteger hidden = 0, mouseOff = 0;
    for (NSPanel *panel in first) {
        if (!panel.isVisible) { hidden += 1; }
        if (panel.ignoresMouseEvents) { mouseOff += 1; }
    }
    Check(first.count >= 1 && hidden == first.count && mouseOff == first.count,
          [NSString stringWithFormat:@"展开互斥：展开后其它 %lu 个贴译全部隐藏且不接收鼠标（%lu/%lu）",
           (unsigned long)first.count, (unsigned long)hidden, (unsigned long)mouseOff]);

    // 真实渲染路径 1：新一帧 showInlineTranslations（抖动让身份变化，走完整布局）。
    [app showInlineTranslations:RfCrowdedTranslations() forItems:RfCrowdedItemsJittered() placementRect:viewport];
    Check(app.inlineExpandedReadingPanel != nil, @"展开互斥：新一帧重排后展开卡仍打开");
    NSUInteger hidden2 = 0, mouseOff2 = 0, total2 = 0;
    for (NSPanel *panel in others()) {
        total2 += 1;
        if (!panel.isVisible) { hidden2 += 1; }
        if (panel.ignoresMouseEvents) { mouseOff2 += 1; }
    }
    Check(total2 >= 1 && hidden2 == total2 && mouseOff2 == total2,
          [NSString stringWithFormat:@"展开互斥：showInlineTranslations 新一帧后仍互斥（%lu/%lu）",
           (unsigned long)hidden2, (unsigned long)total2]);

    // 真实渲染路径 2：handleInlineTranslationResult。
    [app handleInlineTranslationResult:RfCrowdedTranslations()
                              forItems:RfCrowdedItems()
                                 error:nil
                         failureStatus:@"界面翻译出错"
                         successPrefix:@"界面译文已更新"];
    Tick();
    Tick();
    Check(app.inlineExpandedReadingPanel != nil, @"展开互斥：翻译结果落位后展开卡仍打开");
    NSUInteger hidden3 = 0, mouseOff3 = 0, total3 = 0;
    for (NSPanel *panel in others()) {
        total3 += 1;
        if (!panel.isVisible) { hidden3 += 1; }
        if (panel.ignoresMouseEvents) { mouseOff3 += 1; }
    }
    Check(total3 >= 1 && hidden3 == total3 && mouseOff3 == total3,
          [NSString stringWithFormat:@"展开互斥：handleInlineTranslationResult 之后仍互斥（%lu/%lu）",
           (unsigned long)hidden3, (unsigned long)total3]);

    // 收起：按当前帧恢复。
    FYInlineLongCardView *expanded = (FYInlineLongCardView *)app.inlineExpandedReadingPanel.contentView;
    [expanded.collapseButton performClick:nil];
    Check(app.inlineExpandedReadingPanel == nil, @"展开互斥：收起后展开卡关闭");
    NSArray<NSPanel *> *present = [app inlinePanelsPresentInCurrentLayout];
    NSUInteger restored = 0;
    for (NSPanel *panel in present) { if (panel.isVisible) { restored += 1; } }
    Check(present.count >= 1 && restored == present.count,
          [NSString stringWithFormat:@"展开互斥：收起后按当前帧恢复（%lu/%lu）",
           (unsigned long)restored, (unsigned long)present.count]);

    // 换页：clear 不恢复旧内容。
    NSString *oldBlockID = placement.blockID;
    if (RfPanelForBlockID(app, oldBlockID)) {
        [(FYInlineLongCardView *)RfPanelForBlockID(app, oldBlockID).contentView onClick]();
    }
    Check(app.inlineExpandedReadingPanel != nil, @"展开互斥：换页前重新展开");
    [app clearInlineTranslationPanels];
    Check(app.inlineExpandedReadingPanel == nil, @"展开互斥：clearInlineTranslationPanels 关闭展开卡");
    Check(app.inlineTranslationPanels.count == 0 && app.inlineLongCardPanels.count == 0,
          @"展开互斥：clearInlineTranslationPanels 清空贴译面板");
    Check(RfPanelForBlockID(app, oldBlockID) == nil, @"展开互斥：换页后旧块面板不残留");
}

/// 复核补测（第二轮意见）：选择列表每次首次打开都要**从第一条开始**（不能停在文档底部），
/// 并且仍然能向下滚动读完所有条目；跨显示器的全屏投影（与原窗口零交叠）也要能接管。
static void TestChooserStartsAtFirstRow(void) {
    RfApp *app = RfFixtureApp(NSMakeRect(457, 454, 1018, 574), 9601);
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (NSInteger index = 1; index <= 6; index++) {
        [entries addObject:@{@"title": [NSString stringWithFormat:@"第%ld条译文", (long)index],
                             @"source": @"カレンのこと",
                             @"translation": [NSString stringWithFormat:@"第%ld条完整译文。", (long)index],
                             @"blockID": [NSString stringWithFormat:@"probe-%ld", (long)index]}];
    }
    app.inlineOverflowEntries = entries;
    app.inlineOverflowCount = entries.count;
    [app showInlineOverflowChooser];
    Tick();
    Check(app.inlineOverflowChoicePanel != nil, @"列表：多条时打开选择面板");
    if (!app.inlineOverflowChoicePanel) { return; }
    [app.inlineOverflowChoicePanel.contentView layoutSubtreeIfNeeded];
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    RfCollectButtons(app.inlineOverflowChoicePanel.contentView, buttons);
    for (NSButton *button in [buttons copy]) {
        if ([button.title isEqualToString:@"关闭"]) { [buttons removeObject:button]; }
    }
    Check(buttons.count == 6, [NSString stringWithFormat:@"列表：6 条各一行（%lu）", (unsigned long)buttons.count]);
    NSScrollView *scroll = RfScrollOf(app.inlineOverflowChoicePanel.contentView);
    Check(scroll != nil && scroll.documentView != nil, @"列表：滚动区与文档视图都在");
    if (!scroll || !scroll.documentView) { return; }
    Check(NSHeight(scroll.documentView.frame) > 0 && NSWidth(scroll.documentView.frame) > 0,
          [NSString stringWithFormat:@"列表：文档视图有真实尺寸 %@", NSStringFromRect(scroll.documentView.frame)]);
    // 第一条必须真的落在可视区域里（不是"按钮存在"就算过）。
    NSButton *first = nil;
    for (NSButton *button in buttons) { if ([button.title hasPrefix:@"第1条"]) { first = button; } }
    Check(first != nil, @"列表：能找到第一条");
    if (first) {
        NSRect inScroll = [first convertRect:first.bounds toView:scroll];
        CGFloat overlapH = MAX(0, MIN(NSMaxY(inScroll), NSMaxY(scroll.contentView.bounds)) -
                                  MAX(NSMinY(inScroll), NSMinY(scroll.contentView.bounds)));
        CGFloat visibleRatio = overlapH / MAX((CGFloat)1, NSHeight(first.bounds));
        Check(visibleRatio >= 0.95,
              [NSString stringWithFormat:@"列表：首次打开第一条就在可视区（可见比例 %.2f，clip=%@）",
               visibleRatio, NSStringFromRect(scroll.contentView.bounds)]);
    }
    // 向下滚到底，最后一条仍可见（仍能读完）。
    [scroll.contentView scrollToPoint:NSMakePoint(0, MAX(0, NSHeight(scroll.documentView.frame) - NSHeight(scroll.contentView.bounds)))];
    [scroll reflectScrolledClipView:scroll.contentView];
    [app.inlineOverflowChoicePanel.contentView layoutSubtreeIfNeeded];
    NSButton *last = nil;
    for (NSButton *button in buttons) { if ([button.title hasPrefix:@"第6条"]) { last = button; } }
    if (last) {
        NSRect inScroll = [last convertRect:last.bounds toView:scroll];
        CGFloat overlapH = MAX(0, MIN(NSMaxY(inScroll), NSMaxY(scroll.contentView.bounds)) -
                                  MAX(NSMinY(inScroll), NSMinY(scroll.contentView.bounds)));
        Check(overlapH / MAX((CGFloat)1, NSHeight(last.bounds)) >= 0.95,
              @"列表：滚到底最后一条可见（能读完）");
    }
}

/// 跨显示器投影：候选与原窗口**零交叠**（另一块屏上的全屏投影）也必须接管；
/// 若无法可靠判断则必须是 ambiguous（提示重选），不能静默沿用旧窗口。
static void TestCrossDisplayProjectorTakeover(void) {
    // 解析策略要用和既有接管用例同一套夹具（它才会设置 selectedWindowOwnerPID 等解析所需字段）。
    AppDelegate *app = RfResolutionApp(9601, CGRectMake(0, 38, 1644, 961));
    BOOL ambiguous = NO;
    NSString *note = nil;
    pid_t obsPID = 2001;
    NSDictionary *selected = RfWindowInfo(9601, obsPID, @"OBS 主窗口", CGRectMake(0, 38, 1644, 961));
    NSDictionary *projector = RfWindowInfo(9602, obsPID, @"OBS 全屏投影", CGRectMake(1710, 0, 1710, 1112));
    uint32_t got = [app resolveDisplayTargetWindowIDInWindowList:@[projector, selected] ambiguous:&ambiguous note:&note];
    Check(got == 9602 || ambiguous,
          [NSString stringWithFormat:@"跨屏投影：接管另一块屏上的全屏投影或明确提示（got=%u ambiguous=%d）", got, ambiguous ? 1 : 0]);
    Check(got != 9601,
          [NSString stringWithFormat:@"跨屏投影：不能静默沿用旧窗口（got=%u）", got]);

    // 同一个进程里前面还压着一个设置面板（不是画面窗口）时不能被它带偏。
    BOOL ambiguous2 = NO;
    NSDictionary *dialog = RfWindowInfo(9603, obsPID, @"OBS 设置面板", CGRectMake(1800, 200, 400, 300));
    uint32_t got2 = [app resolveDisplayTargetWindowIDInWindowList:@[dialog, projector, selected] ambiguous:&ambiguous2 note:NULL];
    Check(got2 == 9602 || ambiguous2, @"跨屏投影：忽略非画面窗口后仍能接管或明确提示");
}

static void TestCompactEntryReadability(void) {
    RfApp *app = RfFixtureApp(NSMakeRect(457, 454, 1018, 574), 9705);
    NSRect viewport = NSMakeRect(457, 454, 1018, 574);
    [app showInlineTranslations:RfCrowdedTranslations() forItems:RfCrowdedItems() placementRect:viewport];
    FYInlinePlacement *placement = RfPlacementFor(app, kRfBodyNeedle);
    if (!placement || placement.mode != FYInlineDisplayModeCompactEntry) {
        Check(NO, @"入口可读性：正文块是折叠入口");
        return;
    }
    NSPanel *panel = RfPanelForBlockID(app, placement.blockID);
    FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
    Check([card isKindOfClass:FYInlineLongCardView.class] && card.compactEntry, @"入口可读性：是折叠入口卡片");

    // 背景不透明度必须**跟随用户设置**（不能像上一版那样强制 ≥0.94 把用户设置顶掉）；
    // 可读性靠文字颜色/描边/阴影，不靠提高底不透明度。
    CGColorRef background = card.layer.backgroundColor;
    CGFloat alpha = 0;
    if (background) {
        size_t count = CGColorGetNumberOfComponents(background);
        const CGFloat *components = CGColorGetComponents(background);
        if (count >= 1 && components) { alpha = components[count - 1]; }
    }
    CGFloat userAlpha = app.inlinePanelFillAlpha;
    Check(background != NULL && fabs(alpha - userAlpha) <= 0.02,
          [NSString stringWithFormat:@"入口可读性：卡片底不透明度 %.2f 跟随现有设置 %.2f", alpha, userAlpha]);
    Check(card.layer.borderWidth >= 1.5 && card.layer.shadowOpacity > 0,
          @"入口可读性：描边与阴影在位（低不透明度下也有边界）");

    // 提示文字必须深色，和卡片底色对比明显。
    NSTextField *hintLabel = card.foldedEntryHintLabel;
    Check(hintLabel != nil && hintLabel.stringValue.length > 0, @"入口可读性：提示行可见且非空");
    if (hintLabel) {
        NSColor *textColor = [hintLabel.textColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        NSColor *fillColor = [FYAdventureColor(@"cream") colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        CGFloat tr = 0, tg = 0, tb = 0, ta = 0, fr = 0, fg = 0, fb = 0, fa = 0;
        [textColor getRed:&tr green:&tg blue:&tb alpha:&ta];
        [fillColor getRed:&fr green:&fg blue:&fb alpha:&fa];
        CGFloat textBrightness = (tr + tg + tb) / 3.0;
        CGFloat fillBrightness = (fr + fg + fb) / 3.0;
        Check(textBrightness < 0.5, [NSString stringWithFormat:@"入口可读性：提示文字是深色（亮度 %.2f）", textBrightness]);
        Check(fillBrightness - textBrightness > 0.3,
              [NSString stringWithFormat:@"入口可读性：提示与底色对比明显（%.2f vs %.2f）",
               textBrightness, fillBrightness]);
        Check([hintLabel.textColor isEqual:[app uiInk]], @"入口可读性：提示用的是 uiInk");
        NSFont *font = [app.inlineLayoutEngine foldedEntryHintFont];
        NSRect natural = [hintLabel.stringValue boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
                                                             options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                          attributes:@{NSFontAttributeName: font}];
        CGFloat padding = app.inlineLayoutEngine.compactEntryHorizontalPadding;
        Check(padding + ceil(NSWidth(natural)) <= NSWidth(panel.frame) + 0.5,
              [NSString stringWithFormat:@"入口可读性：提示文字实际占位 %.0f 落在面板宽 %.0f 内（不截断）",
               padding + ceil(NSWidth(natural)), NSWidth(panel.frame)]);
        Check(NSWidth(hintLabel.frame) + 0.5 >= ceil(NSWidth(natural)),
              [NSString stringWithFormat:@"入口可读性：提示行宽 %.0f ≥ 文字宽 %.0f（不截断）",
               NSWidth(hintLabel.frame), ceil(NSWidth(natural))]);
        // 测量与绘制必须同一口径：label 的 frame 必须真的落在卡片里（不是"靠窗口裁切"）。
        Check(NSContainsRect(card.bounds, hintLabel.frame),
              [NSString stringWithFormat:@"入口可读性：提示 label 在卡片内（label %@ / 卡 %@）",
               NSStringFromRect(hintLabel.frame), NSStringFromRect(card.bounds)]);
    }
}

#pragma mark - 长正文 + 短标签各自贴在自己原文附近

static void TestShortLabelsStayNearOwnSource(void) {
    RfApp *app = RfFixtureApp(NSMakeRect(457, 454, 1018, 574), 9706);
    NSRect viewport = NSMakeRect(457, 454, 1018, 574);
    NSArray<OCRTextItem *> *items = RfSparseItems();
    [app showInlineTranslations:RfSparseTranslations() forItems:items placementRect:viewport];

    FYInlinePlacement *body = RfPlacementFor(app, kRfBodyNeedle);
    Check(body != nil && body.mode != FYInlineDisplayModeUnplaceable,
          [NSString stringWithFormat:@"短标签：长正文正常贴出（mode=%ld）", body ? (long)body.mode : -1]);

    NSMutableArray<FYInlinePlacement *> *shorts = [NSMutableArray array];
    for (FYInlinePlacement *placement in app.lastInlineLayoutResult.placements) {
        if (placement.mode == FYInlineDisplayModeShortLabel && !CGRectIsEmpty(placement.translationFrame)) {
            [shorts addObject:placement];
        }
    }
    Check(shorts.count >= 3, [NSString stringWithFormat:@"短标签：至少有 3 个短贴片（%lu）", (unsigned long)shorts.count]);
    NSUInteger anchored = 0, noOverlapOther = 0;
    for (FYInlinePlacement *placement in shorts) {
        if (RfPlacementAnchoredToOwnSource(placement)) { anchored += 1; }
        NSLog(@"DIAGNOSTIC 短贴片 <%@> anchor=%ld src=%@ frame=%@",
              Shorten(placement.block.text, 12), (long)placement.anchor,
              NSStringFromRect(placement.sourceFrame), NSStringFromRect(placement.translationFrame));
        BOOL overlapsOtherSource = NO;
        for (FYInlinePlacement *other in app.lastInlineLayoutResult.placements) {
            if (other == placement) { continue; }
            CGRect hit = CGRectIntersection(placement.translationFrame, other.sourceFrame);
            CGFloat depth = CGRectIsNull(hit) || CGRectIsEmpty(hit) ? 0 : MIN(hit.size.width, hit.size.height);
            if (depth > 10.0 + 0.001) { overlapsOtherSource = YES; }
        }
        if (!overlapsOtherSource) { noOverlapOther += 1; }
    }
    Check(anchored == shorts.count,
          [NSString stringWithFormat:@"短标签：每个短贴片都锚在自己原文方向（%lu/%lu）",
           (unsigned long)anchored, (unsigned long)shorts.count]);
    Check(noOverlapOther == shorts.count,
          [NSString stringWithFormat:@"短标签：没有一个短贴片压到别的字段（%lu/%lu）",
           (unsigned long)noOverlapOther, (unsigned long)shorts.count]);

    // 拥挤资料页同样成立。
    RfApp *crowded = RfFixtureApp(NSRectFromCGRect(CGRectMake(457, 454, 1017, 572)), 9707);
    [crowded showInlineTranslations:RfCrowdedTranslations() forItems:RfCrowdedItems()
                      placementRect:NSMakeRect(457, 454, 1017, 572)];
    NSUInteger crowdedShorts = 0, crowdedAnchored = 0, crowdedNoOverlap = 0;
    for (FYInlinePlacement *placement in crowded.lastInlineLayoutResult.placements) {
        if (placement.mode != FYInlineDisplayModeShortLabel || CGRectIsEmpty(placement.translationFrame)) { continue; }
        crowdedShorts += 1;
        if (RfPlacementAnchoredToOwnSource(placement)) { crowdedAnchored += 1; }
        BOOL overlapsOtherSource = NO;
        for (FYInlinePlacement *other in crowded.lastInlineLayoutResult.placements) {
            if (other == placement) { continue; }
            CGRect hit = CGRectIntersection(placement.translationFrame, other.sourceFrame);
            CGFloat depth = CGRectIsNull(hit) || CGRectIsEmpty(hit) ? 0 : MIN(hit.size.width, hit.size.height);
            if (depth > 10.0 + 0.001) { overlapsOtherSource = YES; }
        }
        if (!overlapsOtherSource) { crowdedNoOverlap += 1; }
    }
    Check(crowdedShorts >= 3 && crowdedAnchored == crowdedShorts,
          [NSString stringWithFormat:@"短标签：拥挤页也各自锚在自己字段（%lu/%lu）",
           (unsigned long)crowdedAnchored, (unsigned long)crowdedShorts]);
    Check(crowdedNoOverlap == crowdedShorts,
          [NSString stringWithFormat:@"短标签：拥挤页没有贴片压到别的字段（%lu/%lu）",
           (unsigned long)crowdedNoOverlap, (unsigned long)crowdedShorts]);
}

#pragma mark - 截图

static void RfSaveCanvas(NSImage *image, NSString *path) {
    if (!image || path.length == 0) { return; }
    CGImageRef cg = [image CGImageForProposedRect:NULL context:NULL hints:NULL];
    if (!cg) { return; }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (png) { [png writeToFile:path atomically:YES]; }
}

static void RfDrawRect(NSRect rect, NSRect offset, NSColor *fill, NSColor *stroke, CGFloat width) {
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

static void RfDrawState(RfApp *app, NSArray<OCRTextItem *> *items, NSRect viewport,
                        NSArray<NSPanel *> *extraPanels, NSString *path) {
    NSMutableArray<NSPanel *> *panels = [RfPanels(app) mutableCopy];
    if (app.inlineExpandedReadingPanel) { [panels addObject:app.inlineExpandedReadingPanel]; }
    if (app.inlineOverflowPanel) { [panels addObject:app.inlineOverflowPanel]; }
    if (app.inlineOverflowChoicePanel) { [panels addObject:app.inlineOverflowChoicePanel]; }
    [panels addObjectsFromArray:extraPanels ?: @[]];

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
        BOOL body = [item.text containsString:kRfBodyNeedle];
        RfDrawRect(source, offset,
                   [NSColor colorWithCalibratedRed:0.16 green:0.42 blue:0.95 alpha:body ? 0.22 : 0.10],
                   [NSColor colorWithCalibratedRed:0.10 green:0.30 blue:0.80 alpha:body ? 0.95 : 0.45],
                   body ? 2.0 : 1.0);
    }
    for (NSPanel *panel in panels) {
        if (!panel.isVisible) {
            RfDrawRect(panel.frame, offset, nil, [NSColor colorWithCalibratedWhite:0.55 alpha:0.55], 1.0);
            continue;
        }
        BOOL isCard = [panel.contentView isKindOfClass:FYInlineLongCardView.class];
        RfDrawRect(panel.frame, offset,
                   isCard ? [NSColor colorWithCalibratedRed:0.08 green:0.62 blue:0.33 alpha:0.85]
                          : [NSColor colorWithCalibratedRed:0.95 green:0.78 blue:0.15 alpha:0.85],
                   isCard ? [NSColor colorWithCalibratedRed:0.04 green:0.42 blue:0.22 alpha:1.0]
                          : [NSColor colorWithCalibratedRed:0.72 green:0.55 blue:0.05 alpha:1.0],
                   1.5);
        NSMutableArray<NSTextField *> *labels = [NSMutableArray array];
        NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
        RfCollectButtons(panel.contentView, buttons);
        for (NSView *sub in panel.contentView.subviews) {
            if ([sub isKindOfClass:NSTextField.class]) { [labels addObject:(NSTextField *)sub]; }
        }
        NSMutableArray<NSArray *> *rows = [NSMutableArray array];
        for (NSTextField *label in labels) {
            if (label.stringValue.length == 0 || label.hidden) { continue; }
            NSRect inWindow = [label convertRect:label.bounds toView:nil];
            [rows addObject:@[label.stringValue, [NSValue valueWithRect:NSOffsetRect(inWindow, NSMinX(panel.frame), NSMinY(panel.frame))],
                              label.font ?: [NSFont systemFontOfSize:11]]];
        }
        for (NSButton *button in buttons) {
            if (button.title.length == 0 || button.hidden) { continue; }
            NSRect inWindow = [button convertRect:button.bounds toView:nil];
            [rows addObject:@[button.title, [NSValue valueWithRect:NSOffsetRect(inWindow, NSMinX(panel.frame), NSMinY(panel.frame))],
                              [NSFont systemFontOfSize:11]]];
        }
        for (NSArray *row in rows) {
            NSRect global = [row[1] rectValue];
            NSPoint point = NSMakePoint(NSMinX(global) - NSMinX(offset), NSMinY(global) - NSMinY(offset));
            [row[0] drawAtPoint:point withAttributes:@{NSFontAttributeName: row[2],
                                                       NSForegroundColorAttributeName: NSColor.blackColor}];
        }
    }
    [image unlockFocus];
    RfSaveCanvas(image, path);
}

static void TestScreenshots(void) {
    if (gOutputDirectory.length == 0) { return; }
    [[NSFileManager defaultManager] createDirectoryAtPath:gOutputDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    const uint32_t selected = 9601, projector = 9602;
    NSRect editorViewport = NSMakeRect(0, 38, 1644, 961);

    RfApp *app = RfFixtureApp(editorViewport, selected);
    app.liveBounds[@(selected)] = [NSValue valueWithRect:editorViewport];
    app.liveBounds[@(projector)] = [NSValue valueWithRect:NSMakeRect(0, 0, 1710, 1112)];
    [app showInlineTranslations:RfSparseTranslations() forItems:RfSparseItems() placementRect:editorViewport];
    NSString *windowPath = [gOutputDirectory stringByAppendingPathComponent:@"review-window-mode.png"];
    RfDrawState(app, RfSparseItems(), editorViewport, nil, windowPath);

    // 同一静态画面切到全屏投影。
    app.fixtureTargetID = projector;
    [app refreshDisplayGeometryIfNeeded:YES];
    WindowItem *target = [app displayTargetWindowItem];
    NSRect projectorViewport = [app appKitFrameForWindowItem:target];
    [app showInlineTranslations:RfSparseTranslations() forItems:RfSparseItems() placementRect:projectorViewport];
    NSString *fullscreenPath = [gOutputDirectory stringByAppendingPathComponent:@"review-fullscreen-mode.png"];
    RfDrawState(app, RfSparseItems(), projectorViewport, nil, fullscreenPath);

    // 多条溢出的选择面板。
    RfApp *chooser = RfFixtureApp(NSMakeRect(457, 454, 1018, 574), 9708);
    [chooser showInlineTranslations:RfDenseTranslations(3) forItems:RfDenseItems(3)
                      placementRect:NSMakeRect(457, 454, 260, 150)];
    FYInlineLongCardView *overflowCard = (FYInlineLongCardView *)chooser.inlineOverflowPanel.contentView;
    overflowCard.onClick();
    NSString *chooserPath = [gOutputDirectory stringByAppendingPathComponent:@"review-chooser.png"];
    RfDrawState(chooser, RfDenseItems(3), NSMakeRect(457, 454, 1018, 574), nil, chooserPath);

    // 展开态：其它贴译已隐藏。
    RfApp *expanded = RfFixtureApp(NSMakeRect(457, 454, 1018, 574), 9709);
    NSRect viewport = NSMakeRect(457, 454, 1018, 574);
    [expanded showInlineTranslations:RfCrowdedTranslations() forItems:RfCrowdedItems() placementRect:viewport];
    FYInlinePlacement *placement = RfPlacementFor(expanded, kRfBodyNeedle);
    NSPanel *entryPanel = RfPanelForBlockID(expanded, placement.blockID);
    [(FYInlineLongCardView *)entryPanel.contentView onClick]();
    NSString *expandedPath = [gOutputDirectory stringByAppendingPathComponent:@"review-expanded.png"];
    RfDrawState(expanded, RfCrowdedItems(), viewport, nil, expandedPath);

    NSFileManager *manager = [NSFileManager defaultManager];
    Check([manager fileExistsAtPath:windowPath] && [manager fileExistsAtPath:fullscreenPath] &&
          [manager fileExistsAtPath:chooserPath] && [manager fileExistsAtPath:expandedPath],
          @"截图：写出窗口模式 / 全屏模式 / 选择面板 / 展开态四张对照图");
    Check(chooser.inlineOverflowChoicePanel != nil, @"截图：选择面板确实打开着（图里有内容）");
    Check(expanded.inlineExpandedReadingPanel != nil, @"截图：展开态确实打开着（图里有内容）");
}

#pragma mark - main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        unsetenv("FUYI_DIAG");
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if (argc > 1) { gOutputDirectory = [NSString stringWithUTF8String:argv[1]]; }

        TestResolveFullscreenTakeover();
        TestResolvedTargetIdentityAndGeometry();
        TestChooserLayoutAndActions();
        TestSingleOverflowOpensReadingCardDirectly();
        TestExpandedExclusionAcrossRealRenders();
        TestChooserStartsAtFirstRow();
    TestCrossDisplayProjectorTakeover();
    TestCompactEntryReadability();
        TestShortLabelsStayNearOwnSource();
        TestScreenshots();

        Require(gFailures == 0, [NSString stringWithFormat:@"%lu 条断言失败", (unsigned long)gFailures]);
        printf("PASS ReviewFixesTests: %lu 条断言；全屏投影接管策略 / 目标对象身份与几何跟随 / 「选择要读的译文」尺寸与关闭 / 单条溢出直达阅读卡 / 真实渲染路径下的展开互斥 / 折叠入口不透明度与深色提示 / 短标签贴在自己字段附近 / 四张对照图\n",
               (unsigned long)gChecks);
    }
    return 0;
}
