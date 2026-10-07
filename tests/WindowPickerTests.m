// 窗口选择入口专项验证（2026-10-06）
//
// 用户需求：下拉框原来直接列出微信、输入法、访达、浏览器一大堆窗口，
// 名称也说不清它和"采集来源"的区别。本套件验证：
//   · 用途文案随识别输入源变化（采集卡 = 游戏画面所在窗口；窗口截图 = 要翻译的窗口）；
//   · 辅助窗口（译芽自己的浮层、输入法候选、工具提示）不进候选；无标题的有效窗口保留；
//   · 推荐窗口（OBS／QuickTime／全屏游戏）优先，应用名只作排序参考；
//   · 精简 ↔ 全部可切换、始终保留当前选择、关闭后提示重选而不是静默改绑；
//   · 「应用名 · 窗口标题」命名、重复名称可区分、按窗口 ID 绑定；
//   · 真实界面截图（精简列表 / 全部列表，直接抓我们自己进程的弹出菜单窗口）。
//
// 全部离线：窗口列表是合成条目；截图只抓本进程自己的窗口，不读取别人的屏幕内容。

#import "LearningAppTestSupport.h"
#import <objc/runtime.h>

// 测试隔离头把 CGWindowListCreateImage 换成了合成截图边界；截图证据需要真实函数，
// 所以在应用源码包含完毕之后取一次真实符号，再把宏还原，避免影响别的调用点。
#undef CGWindowListCreateImage
static CGImageRef (*FYRealWindowListCreateImage)(CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) = CGWindowListCreateImage;
#define CGWindowListCreateImage FYTestWindowImage

static NSUInteger gChecks = 0;
static NSUInteger gFailures = 0;
static void Check(BOOL ok, NSString *message) {
    if (ok) {
        gChecks += 1;
        NSLog(@"PASS %@", message);
    } else {
        gFailures += 1;
        NSLog(@"FAIL %@", message);
    }
}

static NSString *gOutputDirectory = nil;

#pragma mark - 合成窗口条目

static NSDictionary *PickerInfo(uint32_t windowID, pid_t pid, NSString *owner, NSString *title,
                                CGRect bounds, NSInteger layer) {
    return @{(id)kCGWindowNumber: @(windowID),
             (id)kCGWindowOwnerPID: @(pid),
             (id)kCGWindowOwnerName: owner,
             (id)kCGWindowName: title ?: @"",
             (id)kCGWindowLayer: @(layer),
             (id)kCGWindowBounds: @{@"X": @(bounds.origin.x), @"Y": @(bounds.origin.y),
                                    @"Width": @(bounds.size.width), @"Height": @(bounds.size.height)}};
}

static CGRect PickerScreenBounds(void) {
    NSRect screen = NSScreen.mainScreen.frame;
    return CGRectMake(NSMinX(screen), 0, NSWidth(screen), NSHeight(screen));
}

static CGRect PickerSmallBounds(void) {
    NSRect screen = NSScreen.mainScreen.frame;
    return CGRectMake(NSMinX(screen) + 80, 120, MIN(NSWidth(screen) - 160, 900), MIN(NSHeight(screen) - 320, 560));
}

@interface PickerApp : AppDelegate
@property(nonatomic, strong) NSArray<WindowItem *> *fixtureWindows;
@end

@implementation PickerApp
- (NSArray<WindowItem *> *)availableWindowItems { return self.fixtureWindows; }
@end

static WindowItem *PickerItem(uint32_t windowID, NSString *owner, NSString *title, CGRect bounds) {
    WindowItem *item = [[WindowItem alloc] init];
    item.windowID = windowID;
    item.ownerName = owner;
    item.title = title;
    item.displayName = title.length > 0 ? [NSString stringWithFormat:@"%@ · %@", owner, title] : owner;
    item.bounds = bounds;
    return item;
}

static PickerApp *PickerMakeApp(FYLearningStore *store, FYLearningAnalyzer *analyzer, FYGrammarCatalog *catalog) {
    PickerApp *app = [PickerApp new];
    app.learningStore = store;
    app.learningAnalyzer = analyzer;
    app.grammarCatalog = catalog;
    app.japaneseTokenizer = [FYJapaneseTokenizer new];
    app.learningCoordinator = [[FYLearningCoordinator alloc] initWithStore:store
                                                                  analyzer:analyzer
                                                                 tokenizer:app.japaneseTokenizer
                                                                   catalog:catalog];
    [app createMainWindow];
    app.fixtureWindows = @[];
    return app;
}

static NSArray<NSString *> *PickerMenuTitles(PickerApp *app) {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSMenuItem *item in app.windowPopup.menu.itemArray) { [titles addObject:item.title]; }
    return titles;
}

#pragma mark - 1. 过滤辅助窗口

static void TestAuxiliaryWindowFilter(void) {
    CGRect big = PickerSmallBounds();
    CGRect screen = PickerScreenBounds();
    CGRect tiny = CGRectMake(20, 20, 200, 150);

    Check(FYWindowItemFromInfo(PickerInfo(1, getpid(), @"译芽", @"字幕浮窗", big, 0)) == nil,
          @"译芽自己的浮层（同进程）不进候选列表");
    Check(FYWindowItemFromInfo(PickerInfo(2, 4242, @"译芽", @"贴译面板", big, 0)) == nil,
          @"按应用名识别出的译芽窗口不进候选列表");
    Check(FYWindowItemFromInfo(PickerInfo(3, 4242, @"Sogou输入法", @"候选", tiny, 0)) == nil,
          @"输入法候选窗不进候选列表");
    Check(FYWindowItemFromInfo(PickerInfo(4, 4242, @"Japanese Input Method", @"", tiny, 0)) == nil,
          @"日文输入法窗口不进候选列表");
    Check(FYWindowItemFromInfo(PickerInfo(5, 4242, @"OBS", @"游戏采集", big, 0)) != nil,
          @"普通应用窗口进候选列表");
    Check(FYWindowItemFromInfo(PickerInfo(6, 4242, @"Game", @"", screen, 0)) != nil,
          @"标题为空的大窗口（全屏游戏/投影）必须保留");
    Check(FYWindowItemFromInfo(PickerInfo(7, 4242, @"SomeApp", @"", tiny, 0)) == nil,
          @"标题为空且很小的工具提示类窗口被过滤");
    Check(FYWindowItemFromInfo(PickerInfo(8, 4242, @"OBS", @"预览", big, 101)) == nil,
          @"非普通层（菜单/候选/浮层）窗口不进候选列表");
    Check(FYWindowItemFromInfo(PickerInfo(9, 4242, @"OBS", @"预览", CGRectMake(0, 0, 100, 80), 0)) == nil,
          @"过小的窗口不进候选列表");
}

#pragma mark - 2. 建议排序与命名

static void TestRankingAndNaming(FYLearningStore *store, FYLearningAnalyzer *analyzer, FYGrammarCatalog *catalog) {
    PickerApp *app = PickerMakeApp(store, analyzer, catalog);
    CGRect screen = PickerScreenBounds();
    CGRect small = PickerSmallBounds();
    app.fixtureWindows = @[
        PickerItem(1, @"Safari", @"文档", small),
        PickerItem(2, @"OBS", @"编辑器", small),
        PickerItem(3, @"OBS", @"全屏投影", screen),
        PickerItem(4, @"QuickTime Player", @"录影", small),
        PickerItem(5, @"QuickTime Player", @"打开", small),
        PickerItem(6, @"Indie Game", @"", screen),
        PickerItem(7, @"OBS", @"游戏采集", small),
        PickerItem(8, @"OBS", @"编辑器", small)
    ];
    [app refreshWindows:nil];
    NSArray<NSString *> *titles = PickerMenuTitles(app);
    Check(titles.count == 7, @"精简列表只列推荐窗口（Safari 不进精简列表）");
    Check(![titles containsObject:@"Safari · 文档"], @"非推荐应用默认不进精简列表");
    Check([titles.firstObject containsString:@"全屏投影"], @"OBS 全屏投影排在最前（最可能是画面窗口）");
    NSUInteger obsPreviewIndex = [titles indexOfObjectPassingTest:^BOOL(NSString *title, NSUInteger index, BOOL *stop) {
        return [title containsString:@"游戏采集"];
    }];
    NSUInteger safariIndex = [titles indexOfObjectPassingTest:^BOOL(NSString *title, NSUInteger index, BOOL *stop) {
        return [title containsString:@"Safari"];
    }];
    NSUInteger quickTimeIndex = [titles indexOfObjectPassingTest:^BOOL(NSString *title, NSUInteger index, BOOL *stop) {
        return [title containsString:@"QuickTime"];
    }];
    Check(obsPreviewIndex < quickTimeIndex && quickTimeIndex < safariIndex,
          @"排序：OBS → QuickTime → 其他应用（应用名只作参考，不删任何窗口）");
    Check([titles containsObject:@"OBS · 编辑器 (2)"], @"同一应用的重复名称补序号，仍然可区分");
    Check([titles containsObject:@"OBS · 全屏投影"], @"名称格式为「应用名 · 窗口标题」");
    [app toggleWindowListScope:nil];
    NSArray<NSString *> *allTitles = PickerMenuTitles(app);
    Check(allTitles.count == 8 && [allTitles containsObject:@"Safari · 文档"],
          @"「显示全部窗口」后浏览器等非推荐窗口可选");
    [app toggleWindowListScope:nil];

    // 应用名与标题相同：不显示成「X · X」。
    WindowItem *same = PickerItem(20, @"Finder", @"Finder", small);
    Check([[app windowMenuTitleForItem:same occurrence:1] isEqualToString:@"Finder"],
          @"应用名与标题相同时只显示一次");
    // 超长标题适当精简。
    WindowItem *longTitle = PickerItem(21, @"Safari", [@"" stringByPaddingToLength:80 withString:@"很长很长的标题" startingAtIndex:0], small);
    NSString *shortened = [app windowMenuTitleForItem:longTitle occurrence:1];
    Check(shortened.length < 70, @"超长标题被精简");
}

#pragma mark - 3. 选择保持与关闭提示

static void TestSelectionStability(FYLearningStore *store, FYLearningAnalyzer *analyzer, FYGrammarCatalog *catalog) {
    PickerApp *app = PickerMakeApp(store, analyzer, catalog);
    CGRect screen = PickerScreenBounds();
    CGRect small = PickerSmallBounds();
    WindowItem *obs = PickerItem(11, @"OBS", @"全屏投影", screen);
    WindowItem *quickTime = PickerItem(12, @"QuickTime Player", @"录影", small);
    WindowItem *safari = PickerItem(13, @"Safari", @"文档", small);
    app.fixtureWindows = @[safari, obs, quickTime];
    [app refreshWindows:nil];

    // 首次刷新：默认选推荐位最高的（OBS 全屏投影）。
    Check([app selectedWindowID] == 11, @"首次刷新按建议位选默认窗口");

    // 用户改选浏览器（非推荐窗口）：必须能在"显示全部窗口"里选到，之后精简列表也要保留它。
    [app toggleWindowListScope:nil];
    Check(app.showAllWindowsInPicker, @"展开全部窗口后可选择任意窗口");
    Check([app selectWindowWithID:13 notifyChange:NO] && [app selectedWindowID] == 13,
          @"用户可以选择浏览器等非推荐窗口");
    [app toggleWindowListScope:nil];
    Check(!app.showAllWindowsInPicker && [app selectedWindowID] == 13,
          @"恢复精简后选择不变，不跳到第一项");
    NSArray<NSString *> *compact = PickerMenuTitles(app);
    Check([compact containsObject:@"Safari · 文档"], @"精简列表始终保留当前选中的非推荐窗口");
    Check(compact.count == 3, @"精简列表 = 推荐窗口 + 当前选中窗口");

    // 展开全部 / 恢复精简：选择不变。
    [app toggleWindowListScope:nil];
    Check(app.showAllWindowsInPicker && [app selectedWindowID] == 13, @"展开全部后选择不变");
    [app toggleWindowListScope:nil];
    Check(!app.showAllWindowsInPicker && [app selectedWindowID] == 13, @"再次恢复精简后选择不变");

    // 刷新：仍然按 ID 保留选择。
    [app refreshWindows:nil];
    Check([app selectedWindowID] == 13, @"刷新窗口后按窗口 ID 保留选择");

    // 当前窗口关闭：明确提示重选，不静默改绑。
    app.fixtureWindows = @[obs, quickTime];
    [app refreshWindows:nil];
    Check([app selectedWindowID] == 0, @"当前窗口关闭后不静默绑定别的窗口");
    Check([[app.windowPopup.menu.itemArray.firstObject title] containsString:@"重新选择"],
          @"当前窗口关闭后给出明确的重选提示");
    Check([app.statusLabel.stringValue containsString:@"重新选择"], @"关闭后状态区也提示重新选择");
    Check([app selectWindowWithID:11 notifyChange:YES] && [app selectedWindowID] == 11,
          @"用户点选新窗口后恢复正常选择");

    // 没有推荐窗口时：列出全部，绝不出现空列表。
    app.fixtureWindows = @[safari, PickerItem(14, @"Finder", @"访达", small)];
    [app.windowPopup removeAllItems];
    app.windows = [NSMutableArray array];
    [app refreshWindows:nil];
    Check(PickerMenuTitles(app).count == 2, @"没有推荐窗口时列出全部窗口（列表不为空）");
    Check(app.windowScopeButton.hidden, @"没有推荐窗口时「显示全部窗口」入口收起（列表本来就是全部）");
    Check([app.windowCardNoteLabel.stringValue containsString:@"已列出全部窗口"],
          @"没有推荐窗口时在说明里明确告知已列出全部窗口");
}

#pragma mark - 4. 用途文案（采集卡 / 窗口截图）

static void TestModeSpecificCopy(FYLearningStore *store, FYLearningAnalyzer *analyzer, FYGrammarCatalog *catalog) {
    PickerApp *app = PickerMakeApp(store, analyzer, catalog);
    CGRect screen = PickerScreenBounds();
    CGRect small = PickerSmallBounds();
    app.fixtureWindows = @[PickerItem(31, @"OBS", @"全屏投影", screen), PickerItem(32, @"Safari", @"文档", small)];
    app.inputSourceSegment = 0;
    [app updateWindowCardCopy];
    [app refreshWindows:nil];
    Check([app.windowCardTitleLabel.stringValue isEqualToString:@"要翻译的窗口"],
          @"窗口截图模式下名称是「要翻译的窗口」（它同时决定识别来源）");
    Check([app.windowCardHintLabel.stringValue containsString:@"识别画面的来源"],
          @"窗口截图模式说明里点明它同时决定识别来源与贴译位置");
    Check([app.windowCardNoteLabel.stringValue containsString:@"识别来源就是这里选中的窗口"],
          @"窗口截图模式没有把选择说成只影响字幕位置");

    app.inputSourceSegment = 1;
    [app updateWindowCardCopy];
    Check([app.windowCardTitleLabel.stringValue isEqualToString:@"游戏画面所在窗口"],
          @"采集卡模式下名称是「游戏画面所在窗口」");
    Check([app.windowCardHintLabel.stringValue containsString:@"选择显示游戏画面的窗口，字幕和贴译将跟随它。"],
          @"采集卡模式使用需求里给定的说明文案");
    Check([app.windowCardNoteLabel.stringValue containsString:@"采集卡设备"],
          @"采集卡模式明确区分「采集设备」与「显示窗口」");
    Check(app.windowScopeButton.title.length > 0 && !app.windowScopeButton.hidden,
          @"有推荐窗口时保留可发现的「显示全部窗口」入口");
    app.inputSourceSegment = 0;
}

#pragma mark - 5. 真实界面截图

static void PickerPump(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.08]];
}

static BOOL PickerWriteImage(CGImageRef image, NSString *path) {
    if (!image) { return NO; }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return png && [png writeToFile:path atomically:YES];
}

static void PickerScrollIntoView(NSView *view) {
    NSView *parent = view.superview;
    while (parent && ![parent isKindOfClass:NSScrollView.class]) { parent = parent.superview; }
    if (![parent isKindOfClass:NSScrollView.class]) { return; }
    NSScrollView *scroll = (NSScrollView *)parent;
    NSRect rect = [view convertRect:view.bounds toView:scroll.documentView];
    [scroll.documentView scrollRectToVisible:NSInsetRect(rect, -20, -20)];
    [scroll reflectScrolledClipView:scroll.contentView];
    [scroll layoutSubtreeIfNeeded];
}

// 当前属于本进程、层级 > 0 的窗口 ID（菜单窗口就是从无到有出现的）。
static NSSet<NSNumber *> *PickerOwnOverlayWindowIDs(void) {
    NSMutableSet<NSNumber *> *ids = [NSMutableSet set];
    NSArray *infos = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    for (NSDictionary *info in infos) {
        if ((pid_t)[info[(id)kCGWindowOwnerPID] intValue] != getpid()) { continue; }
        if ([info[(id)kCGWindowLayer] integerValue] <= 0) { continue; }
        [ids addObject:info[(id)kCGWindowNumber]];
    }
    return ids;
}

// 菜单窗口偶尔会在刚出现时抓到还没合成完的空白帧：按像素方差判一次，空白就重开一次。
static BOOL PickerImageLooksBlank(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) { return YES; }
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:data];
    if (!rep) { return YES; }
    NSInteger minValue = 255, maxValue = 0;
    for (NSInteger y = 0; y < 12; y++) {
        for (NSInteger x = 0; x < 12; x++) {
            NSInteger px = MIN(rep.pixelsWide - 1, x * rep.pixelsWide / 12);
            NSInteger py = MIN(rep.pixelsHigh - 1, y * rep.pixelsHigh / 12);
            NSColor *color = [rep colorAtX:px y:py];
            NSInteger value = (NSInteger)lround((color.redComponent + color.greenComponent + color.blueComponent) / 3.0 * 255.0);
            minValue = MIN(minValue, value);
            maxValue = MAX(maxValue, value);
        }
    }
    return (maxValue - minValue) < 10;
}

// 打开一次菜单并抓图（抓不到或抓到空白帧就由调用方重试）。
static BOOL PickerOpenMenuAndCapture(PickerApp *app, NSString *path) {
    NSPopUpButton *popup = app.windowPopup;
    if (popup.numberOfItems == 0) { return NO; }
    NSSet<NSNumber *> *preExisting = PickerOwnOverlayWindowIDs();
    __block BOOL captured = NO;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [NSThread sleepForTimeInterval:1.1];
        NSArray *infos = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
        uint32_t bestWindow = 0;
        CGFloat bestArea = 0;
        CGRect bestBounds = CGRectZero;
        for (NSDictionary *info in infos) {
            if ((pid_t)[info[(id)kCGWindowOwnerPID] intValue] != getpid()) { continue; }
            if ([info[(id)kCGWindowLayer] integerValue] <= 0) { continue; }
            CGRect bounds = CGRectZero;
            if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds)) { continue; }
            CGFloat area = bounds.size.width * bounds.size.height;
            if ([preExisting containsObject:info[(id)kCGWindowNumber]]) { continue; }   // 排除打开菜单前就存在的窗口
            if (area > bestArea) { bestArea = area; bestWindow = [info[(id)kCGWindowNumber] unsignedIntValue]; bestBounds = bounds; }
        }
        (void)bestBounds;
        if (bestWindow != 0) {
            // 只按**我们自己的窗口 ID** 截图：不合成屏幕区域，绝不包含用户桌面上别的内容。
            // 重建过菜单之后第一次打开偶尔会拿到还没画出来的空白帧，由调用方按像素方差重试。
            CGImageRef image = FYRealWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
                                                           (CGWindowID)bestWindow,
                                                           kCGWindowImageBoundsIgnoreFraming | kCGWindowImageNominalResolution);
            captured = PickerWriteImage(image, path);
            if (image) { CGImageRelease(image); }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ [popup.menu cancelTracking]; });
        dispatch_semaphore_signal(finished);
    });
    [popup.menu popUpMenuPositioningItem:popup.menu.itemArray.firstObject
                              atLocation:NSMakePoint(12, NSMidY(popup.bounds))
                                  inView:popup];
    dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)));
    PickerPump();
    return captured;
}

// 真正打开下拉菜单，抓**我们自己进程的菜单窗口**（不读别人的屏幕内容），然后关掉菜单。
static BOOL PickerCaptureOpenMenu(PickerApp *app, NSString *path) {
    // 机器负载高时菜单窗口会晚一两帧才画出来，重试要多给几次（单跑必过、全量并发时偶发空白帧）。
    for (NSInteger attempt = 0; attempt < 12; attempt++) {
        if (PickerOpenMenuAndCapture(app, path) && !PickerImageLooksBlank(path)) { return YES; }
        PickerPump();
        usleep(120 * 1000);
    }
    return NO;
}

static BOOL PickerWriteView(NSView *view, NSRect rect, NSString *path) {
    [view layoutSubtreeIfNeeded];
    if (NSWidth(rect) < 4 || NSHeight(rect) < 4) { return NO; }
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:rect];
    if (!rep) { return NO; }
    [view cacheDisplayInRect:rect toBitmapImageRep:rep];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return png && [png writeToFile:path atomically:YES];
}

// 窗口选择卡片的完整矩形：从卡片标题一直算到卡片底部说明，别用可能还没布局的 bounds。
static NSRect PickerCardRectInContentView(PickerApp *app, NSView *content) {
    NSView *row = app.windowPopup.superview;
    NSView *card = row;
    while (card.superview && ![app.windowCardTitleLabel isDescendantOf:card]) {
        card = card.superview;
    }
    [card layoutSubtreeIfNeeded];
    NSRect unionRect = NSUnionRect([app.windowCardTitleLabel convertRect:app.windowCardTitleLabel.bounds toView:card],
                                   [row convertRect:row.bounds toView:card]);
    if (app.windowCardNoteLabel) {
        unionRect = NSUnionRect(unionRect, [app.windowCardNoteLabel convertRect:app.windowCardNoteLabel.bounds toView:card]);
    }
    if (NSIsEmptyRect(unionRect)) { unionRect = card.bounds; }
    NSRect rect = [card convertRect:unionRect toView:content];
    return NSInsetRect(rect, -8, -8);
}

static void TestInterfaceScreenshots(FYLearningStore *store, FYLearningAnalyzer *analyzer, FYGrammarCatalog *catalog) {
    PickerApp *app = PickerMakeApp(store, analyzer, catalog);
    app.fixtureWindows = @[
        PickerItem(41, @"OBS", @"游戏采集", PickerSmallBounds()),
        PickerItem(42, @"OBS", @"全屏投影", PickerScreenBounds()),
        PickerItem(43, @"QuickTime Player", @"录影", PickerSmallBounds()),
        PickerItem(44, @"Indie Game", @"", PickerScreenBounds()),
        PickerItem(45, @"Safari", @"文档", PickerSmallBounds()),
        PickerItem(46, @"微信", @"微信", PickerSmallBounds())
    ];
    [NSApp activateIgnoringOtherApps:YES];
    [app.mainWindow makeKeyAndOrderFront:nil];
    PickerPump();
    // 走真实的页面切换入口。
    [app.pageButtons[3] performClick:nil];
    PickerPump();
    [app refreshWindows:nil];
    Check([app selectWindowWithID:43 notifyChange:NO], @"截图场景：选中 QuickTime 录影窗口");
    [app updateWindowCardCopy];
    NSView *content = app.mainWindow.contentView;
    NSView *card = app.windowPopup.superview.superview;
    [content layoutSubtreeIfNeeded];
    [card layoutSubtreeIfNeeded];
    PickerScrollIntoView(card);
    PickerPump();
    [content layoutSubtreeIfNeeded];

    if (gOutputDirectory.length > 0) {
        [[NSFileManager defaultManager] createDirectoryAtPath:gOutputDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
        NSRect cardRect = PickerCardRectInContentView(app, content);
        NSRect fullRect = content.bounds;
        Check(PickerWriteView(content, cardRect, [gOutputDirectory stringByAppendingPathComponent:@"picker-card-window-mode.png"]),
              @"写出窗口截图模式的窗口选择卡片截图");
        Check(PickerWriteView(content, fullRect, [gOutputDirectory stringByAppendingPathComponent:@"picker-settings-window-mode.png"]),
              @"写出窗口截图模式的运行设置整页截图");

        NSString *compactPath = [gOutputDirectory stringByAppendingPathComponent:@"picker-menu-compact.png"];
        BOOL compact = PickerCaptureOpenMenu(app, compactPath);
        Check(compact && !PickerImageLooksBlank(compactPath), @"截到真实的精简列表弹出菜单（非空白帧）");

        // 展开全部窗口后再截一次：与精简列表对照。
        [app toggleWindowListScope:nil];
        PickerPump();
        NSString *allPath = [gOutputDirectory stringByAppendingPathComponent:@"picker-menu-all.png"];
        BOOL all = PickerCaptureOpenMenu(app, allPath);
        Check(all && !PickerImageLooksBlank(allPath), @"截到真实的全部窗口列表弹出菜单（非空白帧）");
        Check(PickerMenuTitles(app).count == 6, @"全部列表包含 6 个窗口（含浏览器与微信）");
        Check([app selectedWindowID] == 43, @"切换列表后仍然保持原选择");

        // 采集卡模式：名称与说明应变成「游戏画面所在窗口」。
        [app.inputSourceControl setSelectedSegment:1];
        [app inputSourceChanged:app.inputSourceControl];
        PickerPump();
        [app.mainWindow makeKeyAndOrderFront:nil];
        PickerPump();
        [content layoutSubtreeIfNeeded];
        [card layoutSubtreeIfNeeded];
        PickerScrollIntoView(card);
        PickerPump();
        [content layoutSubtreeIfNeeded];
        Check([app.windowCardTitleLabel.stringValue isEqualToString:@"游戏画面所在窗口"],
              @"截图场景：采集卡模式卡片标题正确");
        Check(PickerWriteView(content, PickerCardRectInContentView(app, content),
                              [gOutputDirectory stringByAppendingPathComponent:@"picker-card-capture-mode.png"]),
              @"写出采集卡模式的窗口选择卡片截图");
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        unsetenv("FUYI_DIAG");
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if (argc > 1) {
            gOutputDirectory = [NSString stringWithUTF8String:argv[1]];
        } else {
            gOutputDirectory = @"handoff/window-picker-20261006/evidence";
        }

        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        Require([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL],
                @"temporary directory failed");
        FYLearningStore *store = Store([directory stringByAppendingPathComponent:@"picker.sqlite3"]);
        FYGrammarCatalog *catalog = [[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]];
        Require([catalog loadWithError:NULL], @"grammar catalog failed");
        FYLearningAnalyzer *analyzer = Analyzer(catalog);

        TestAuxiliaryWindowFilter();
        TestRankingAndNaming(store, analyzer, catalog);
        TestSelectionStability(store, analyzer, catalog);
        TestModeSpecificCopy(store, analyzer, catalog);
        TestInterfaceScreenshots(store, analyzer, catalog);

        Require(gFailures == 0, [NSString stringWithFormat:@"%lu 条断言失败", (unsigned long)gFailures]);
        printf("PASS WindowPickerTests: %lu 条断言；辅助窗口过滤 / 推荐排序 / 「应用名 · 标题」命名 / 选择保持 / 关闭重选 / 用途文案 / 真实列表截图\n",
               (unsigned long)gChecks);
    }
    return 0;
}
