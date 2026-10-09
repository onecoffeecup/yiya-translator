// 显示目标跟随 + 实时几何专项验证（2026-10-06）
//
// 背景：OBS 编辑器预览 ↔ 全屏投影切换后贴译不跟随。三条根因：
//   ① 显示目标与定位目标不一致：前台判定允许"同一 OBS 进程的别的窗口在前台"，
//      但 selectedWindowItem 仍然返回用户原来选中的编辑器窗口；
//   ② OCR 命中"文本未变化"时直接 return，跳过了窗口边界检查、映射复核和贴译重排；
//   ③ WindowItem.bounds 是下拉列表刷新时的旧快照。
//
// 本套件全部离线（合成窗口列表 + 合成实时边界 + 合成 OCR + mock HTTP），
// 并且**必须经过真实入口**：timerFired: → OCR → 文本去重分支 → 贴译布局，
// 不手工调用布局函数并塞一个正确矩形。
// 不触碰真实屏幕内容、不安装或重启正式应用。

#import "LearningAppTestSupport.h"
#import <objc/runtime.h>

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

#pragma mark - mock HTTP

static NSUInteger gRequests = 0;
static NSMutableArray<NSString *> *gSubmittedSources = nil;
static BOOL gHoldResponse = NO;
static void (^gPendingResponse)(void);

@interface FollowTask : NSObject
@property(nonatomic, copy) void (^response)(void);
@end
@implementation FollowTask
- (void)resume {
    if (gHoldResponse) { gPendingResponse = self.response; }
    else { self.response(); }
}
- (void)cancel {}
@end

@interface FollowSession : NSObject
- (id)dataTaskWithRequest:(NSURLRequest *)request
        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion;
@end

@implementation FollowSession
- (id)dataTaskWithRequest:(NSURLRequest *)request
        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    gRequests += 1;
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];
    NSString *source = [[body[@"messages"] lastObject] objectForKey:@"content"] ?: @"";
    [gSubmittedSources addObject:source];
    NSUInteger count = 0;
    for (NSString *line in [source componentsSeparatedByString:@"\n"]) {
        if (line.length > 2 && [line rangeOfString:@". "].location != NSNotFound) { count += 1; }
    }
    if (count == 0) { count = 1; }
    NSMutableString *translated = [NSMutableString string];
    for (NSUInteger index = 0; index < count; index++) {
        [translated appendFormat:@"%lu. 译文%lu\n", (unsigned long)(index + 1), (unsigned long)(index + 1)];
    }
    FollowTask *task = [FollowTask new];
    task.response = ^{ completion(Envelope(translated), Response(), nil); };
    return task;
}
@end

@interface FYTestURLSession (FollowTest)
+ (id)followTestSession;
@end
@implementation FYTestURLSession (FollowTest)
+ (id)followTestSession { return [FollowSession new]; }
@end

#pragma mark - 夹具

// 几何套件的 OCR 是已确认的固定夹具；连续帧纠错不属于本套件。
// 原启动路径初始化了新的帧确认器，这里显式提供同接口的稳定输入替身。
@interface FollowConfirmedOCR : FYInlineOCRFrameStabilizer
@end
@implementation FollowConfirmedOCR
- (BOOL)ready { return YES; }
- (NSArray<OCRTextItem *> *)observeItems:(NSArray<OCRTextItem *> *)items { return items; }
@end

@interface FollowApp : AppDelegate
@property(nonatomic, strong) NSArray<WindowItem *> *fixtureWindows;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *liveBounds;
@property(nonatomic) pid_t fixtureOwnerPID;
@property(nonatomic, strong) NSArray<OCRTextItem *> *ocrFixture;
// 脚本化"实际显示目标"：用于模拟 OBS 编辑器 → 全屏投影的切换。
@property(nonatomic) BOOL usesScriptedTarget;
@property(nonatomic) uint32_t scriptedTargetID;
@property(nonatomic) BOOL scriptedTargetAmbiguous;
@property(nonatomic, strong) NSDictionary<NSNumber *, NSValue *> *scriptedBounds;
@end

@implementation FollowApp
- (NSArray<WindowItem *> *)availableWindowItems { return self.fixtureWindows; }

- (BOOL)liveBoundsForWindowID:(uint32_t)windowID outBounds:(CGRect *)outBounds {
    NSValue *value = self.liveBounds[@(windowID)];
    if (!value) { return NO; }
    if (outBounds) { *outBounds = value.rectValue; }
    return YES;
}
- (pid_t)selectedWindowOwnerPID { return self.fixtureOwnerPID; }
- (BOOL)translationTargetIsForeground { return YES; }   // 浮窗可见性不是本套件的验证目标
- (NSInteger)effectiveModeSegment { return ContentModeUI; }
// 本套件验证几何跟随：让内容模式固定为"界面"，避免模式切换顺手清掉去重状态。
- (NSInteger)stableContentModeForBlocks:(NSArray<OCRTextItem *> *)blocks {
    self.detectedModeSegment = ContentModeUI;
    self.candidateModeSegment = ContentModeUI;
    self.candidateModeHits = 0;
    return ContentModeUI;
}
- (NSString *)recognizeTextBlocksInImage:(CGImageRef)image
                                 fastOCR:(BOOL)fastOCR
                         languageSegment:(NSInteger)languageSegment
                                  blocks:(NSArray<OCRTextItem *> **)blocks
                                   error:(NSError **)error {
    if (blocks) { *blocks = self.ocrFixture ?: @[]; }
    return [[self.ocrFixture valueForKey:@"text"] componentsJoinedByString:@"\n"] ?: @"";
}
- (NSArray<OCRTextItem *> *)blocksInsideModalIfPresent:(NSArray<OCRTextItem *> *)blocks
                                               inImage:(CGImageRef)image
                                  normalizedExclusions:(NSArray<NSValue *> *)exclusions { return blocks; }
- (NSArray<OCRTextItem *> *)mergedInlineTextItemsFromItems:(NSArray<OCRTextItem *> *)items { return items; }
- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items strict:(BOOL)strict { return items; }

- (uint32_t)resolveDisplayTargetWindowIDInWindowList:(NSArray<NSDictionary *> *)windowList
                                           ambiguous:(BOOL *)outAmbiguous
                                                note:(NSString **)outNote {
    if (!self.usesScriptedTarget) {
        return [super resolveDisplayTargetWindowIDInWindowList:windowList ambiguous:outAmbiguous note:outNote];
    }
    if (outAmbiguous) { *outAmbiguous = self.scriptedTargetAmbiguous; }
    if (outNote && self.scriptedTargetAmbiguous) { *outNote = @"检测到多个可能是游戏画面的窗口"; }
    return self.scriptedTargetID;
}
@end

static OCRTextItem *FollowItem(NSString *text, CGRect box) {
    OCRTextItem *item = [[OCRTextItem alloc] init];
    item.text = text;
    item.boundingBox = box;
    item.lineTexts = @[text];
    item.lineBoxes = @[[NSValue valueWithRect:box]];
    item.lineCount = 1;
    item.blockKind = InlineBlockKindShort;
    item.confidence = 0.95;
    item.groupingConfidence = 1.0;
    return item;
}

static NSDictionary *FollowWindowInfo(uint32_t windowID, pid_t pid, NSString *owner, NSString *title,
                                      CGRect bounds, NSInteger layer) {
    return @{(id)kCGWindowNumber: @(windowID),
             (id)kCGWindowOwnerPID: @(pid),
             (id)kCGWindowOwnerName: owner,
             (id)kCGWindowName: title ?: @"",
             (id)kCGWindowLayer: @(layer),
             (id)kCGWindowBounds: @{@"X": @(bounds.origin.x), @"Y": @(bounds.origin.y),
                                    @"Width": @(bounds.size.width), @"Height": @(bounds.size.height)}};
}

static CGRect FollowScreenQuartzBounds(void) {
    NSRect screen = NSScreen.mainScreen.frame;
    return CGRectMake(NSMinX(screen), 0, NSWidth(screen), NSHeight(screen));
}

// 编辑器窗口：明显小于一块屏幕。
static CGRect FollowEditorBounds(void) {
    NSRect screen = NSScreen.mainScreen.frame;
    return CGRectMake(NSMinX(screen) + 60, 90, MIN(NSWidth(screen) - 120, 980), MIN(NSHeight(screen) - 240, 640));
}

static FollowApp *FollowMakeApp(FYLearningStore *store, FYLearningAnalyzer *analyzer, FYGrammarCatalog *catalog) {
    FollowApp *app = [FollowApp new];
    app.learningStore = store;
    app.learningAnalyzer = analyzer;
    app.grammarCatalog = catalog;
    app.japaneseTokenizer = [FYJapaneseTokenizer new];
    app.learningCoordinator = [[FYLearningCoordinator alloc] initWithStore:store
                                                                  analyzer:analyzer
                                                                 tokenizer:app.japaneseTokenizer
                                                                   catalog:catalog];
    [app createMainWindow];
    // 本套件验证几何跟随，不验证"等待文本稳定/两遍放大 OCR"：关掉它们让每轮只做一次 OCR。
    app.stableTextCheckbox = [NSButton checkboxWithTitle:@"synthetic stability gate" target:nil action:NULL];
    app.stableTextCheckbox.state = NSControlStateValueOff;
    app.autoFitRegionCheckbox.state = NSControlStateValueOff;
    app.fixtureWindows = @[];
    app.liveBounds = [NSMutableDictionary dictionary];
    app.ocrFixture = @[];
    app.inlineTranslationCache = [NSMutableDictionary dictionary];
    app.inlineFrameStabilizer = [FollowConfirmedOCR new];
    app.running = YES;
    app.usesScriptedTarget = NO;
    app.scriptedTargetID = 0;
    app.scriptedTargetAmbiguous = NO;
    app.apiKeyField.stringValue = @"follow-dummy-key";
    app.baseURLField.stringValue = @"https://example.invalid/v1";
    app.modelField.stringValue = @"follow-model";
    app.realtimeModelField.stringValue = @"follow-model";
    return app;
}

static void FollowSetWindowSelection(FollowApp *app, uint32_t windowID, NSString *menuTitle) {
    app.windowPopup = [[NSPopUpButton alloc] init];
    [app.windowPopup addItemWithTitle:menuTitle];
    app.windowPopup.menu.itemArray.firstObject.representedObject = @(windowID);
}

static void FollowRefreshWindowItems(FollowApp *app, NSArray<WindowItem *> *items) {
    app.fixtureWindows = items;
    [app refreshWindows:nil];
}

static WindowItem *FollowWindowItem(uint32_t windowID, NSString *owner, NSString *title, CGRect bounds) {
    WindowItem *item = [[WindowItem alloc] init];
    item.windowID = windowID;
    item.ownerName = owner;
    item.title = title;
    item.displayName = title.length > 0 ? [NSString stringWithFormat:@"%@ · %@", owner, title] : owner;
    item.bounds = bounds;
    return item;
}

static NSArray<NSPanel *> *FollowPanels(FollowApp *app) {
    return [app.inlineTranslationPanels arrayByAddingObjectsFromArray:app.inlineLongCardPanels];
}

static void FollowRunCycle(FollowApp *app) {
    [app timerFired:nil];
    Pump(^BOOL { return !app.inFlight; });
    // handleInlineTranslationResult 还会往主队列派一次落位块：等它真正跑完再断言。
    Tick();
    Tick();
}

// 面板 frame 向量：用来判断"贴译是不是真的换了位置"。
static NSArray<NSValue *> *FollowPanelFrames(FollowApp *app) {
    NSMutableArray<NSValue *> *frames = [NSMutableArray array];
    for (NSPanel *panel in FollowPanels(app)) { [frames addObject:[NSValue valueWithRect:panel.frame]]; }
    return frames;
}

static BOOL FollowAnyFrameUnchanged(NSArray<NSValue *> *before, NSArray<NSValue *> *after) {
    for (NSValue *value in before) {
        for (NSValue *now in after) {
            if (NSEqualRects(value.rectValue, now.rectValue)) { return YES; }
        }
    }
    return NO;
}

// 对照证据：把某一阶段的「画面区域 / 原文框 / 译文框」原样打出来（写进套件日志）。
static void FollowLogGeometry(FollowApp *app, NSString *stage) {
    NSRect viewport = NSZeroRect;
    BOOL hasViewport = [app inlinePlacementRect:&viewport reason:NULL];
    NSMutableString *panels = [NSMutableString string];
    for (NSPanel *panel in FollowPanels(app)) {
        [panels appendFormat:@"%@(visible=%d) ", NSStringFromRect(panel.frame), panel.isVisible];
    }
    NSMutableString *sources = [NSMutableString string];
    for (OCRTextItem *item in app.ocrFixture) {
        NSRect frame = [app appKitFrameForOCRItem:item inWindowFrame:viewport];
        [sources appendFormat:@"<%@:%@> ", item.text, NSStringFromRect(frame)];
    }
    NSLog(@"GEOMETRY stage=%@ target=%u viewport=%@ sourceBoxes=[%@] panels=[%@]",
          stage, [app displayTargetWindowID],
          hasViewport ? NSStringFromRect(viewport) : @"(unavailable)", sources, panels);
}

static BOOL FollowAllPanelsHidden(FollowApp *app) {
    for (NSPanel *panel in FollowPanels(app)) { if (panel.isVisible) { return NO; } }
    return YES;
}

static BOOL FollowAnyPanelInside(FollowApp *app, NSRect frame) {
    for (NSPanel *panel in FollowPanels(app)) {
        if (NSWidth(frame) < 2) { continue; }
        if (NSIntersectsRect(panel.frame, NSInsetRect(frame, -2, -2))) { return YES; }
    }
    return NO;
}

#pragma mark - A. 实际显示目标解析（真实策略）

static void TestDisplayTargetPolicy(FYLearningStore *store, FYLearningAnalyzer *analyzer, FYGrammarCatalog *catalog) {
    FollowApp *app = FollowMakeApp(store, analyzer, catalog);
    const uint32_t editor = 9201, projector = 9202, settings = 9203;
    CGRect screen = FollowScreenQuartzBounds();
    CGRect editorBounds = FollowEditorBounds();
    CGRect smallPanel = CGRectMake(200, 160, 700, 500);
    pid_t obsPID = 7300;
    app.fixtureOwnerPID = obsPID;
    FollowSetWindowSelection(app, editor, @"OBS · 编辑器");
    FollowRefreshWindowItems(app, @[FollowWindowItem(editor, @"OBS", @"编辑器", editorBounds),
                                   FollowWindowItem(projector, @"OBS", @"全屏投影", screen),
                                   FollowWindowItem(settings, @"OBS", @"设置", smallPanel)]);

    BOOL ambiguous = NO;
    NSString *note = nil;

    // 只有编辑器：目标就是编辑器。
    uint32_t target = [app resolveDisplayTargetWindowIDInWindowList:@[FollowWindowInfo(editor, obsPID, @"OBS", @"编辑器", editorBounds, 0)]
                                                         ambiguous:&ambiguous note:&note];
    Check(target == editor && !ambiguous, @"选中窗口在屏幕上且没有投影 → 目标仍是编辑器");

    // 编辑器前面压着一个设置弹窗（同一进程、更小）：不能被当成投影目标。
    target = [app resolveDisplayTargetWindowIDInWindowList:@[FollowWindowInfo(settings, obsPID, @"OBS", @"设置", smallPanel, 0),
                                                            FollowWindowInfo(editor, obsPID, @"OBS", @"编辑器", editorBounds, 0)]
                                                 ambiguous:&ambiguous note:&note];
    Check(target == editor && !ambiguous, @"同一 PID 的设置弹窗不会把定位目标抢走");

    // 编辑器前面是一个全屏投影：贴译必须跟到投影窗口上。
    target = [app resolveDisplayTargetWindowIDInWindowList:@[FollowWindowInfo(projector, obsPID, @"OBS", @"全屏投影", screen, 0),
                                                            FollowWindowInfo(editor, obsPID, @"OBS", @"编辑器", editorBounds, 0)]
                                                 ambiguous:&ambiguous note:&note];
    Check(target == projector && !ambiguous, @"编辑器前面的全屏投影被识别为实际画面窗口");

    // 两个投影同时压在编辑器前面：无法确定 → 报歧义，不猜。
    target = [app resolveDisplayTargetWindowIDInWindowList:@[FollowWindowInfo(9205, obsPID, @"OBS", @"全屏投影 A", screen, 0),
                                                            FollowWindowInfo(9206, obsPID, @"OBS", @"全屏投影 B", screen, 0),
                                                            FollowWindowInfo(editor, obsPID, @"OBS", @"编辑器", editorBounds, 0)]
                                                 ambiguous:&ambiguous note:&note];
    Check(target == 0 && ambiguous, @"多个投影同时在前台时返回「无法确定」并标记歧义");

    // 用户选的是投影窗口，投影关掉、回到编辑器：跟随唯一的画面窗口。
    FollowSetWindowSelection(app, projector, @"OBS · 全屏投影");
    FollowRefreshWindowItems(app, @[FollowWindowItem(editor, @"OBS", @"编辑器", editorBounds),
                                   FollowWindowItem(projector, @"OBS", @"全屏投影", screen)]);
    target = [app resolveDisplayTargetWindowIDInWindowList:@[FollowWindowInfo(editor, obsPID, @"OBS", @"编辑器", editorBounds, 0)]
                                                 ambiguous:&ambiguous note:&note];
    Check(target == editor && !ambiguous, @"投影关闭后回到编辑器：跟随唯一剩下的画面窗口");

    // 选中窗口不在屏幕上，只剩一个设置弹窗：不接管。
    target = [app resolveDisplayTargetWindowIDInWindowList:@[FollowWindowInfo(settings, obsPID, @"OBS", @"设置", smallPanel, 0)]
                                                 ambiguous:&ambiguous note:&note];
    Check(target == 0 && !ambiguous && note.length > 0, @"只剩设置弹窗时明确报「找不到」，不把贴译贴到弹窗上");

    // 选中窗口不在屏幕上、列表里有两个同尺寸投影：歧义。
    target = [app resolveDisplayTargetWindowIDInWindowList:@[FollowWindowInfo(9205, obsPID, @"OBS", @"全屏投影 A", screen, 0),
                                                            FollowWindowInfo(9206, obsPID, @"OBS", @"全屏投影 B", screen, 0)]
                                                 ambiguous:&ambiguous note:&note];
    Check(target == 0 && ambiguous, @"两个同尺寸投影无法区分时报歧义");

    // 选中窗口不在屏幕上，一个全屏投影 + 一个设置弹窗：主画面明显更大 → 跟随投影。
    target = [app resolveDisplayTargetWindowIDInWindowList:@[FollowWindowInfo(projector, obsPID, @"OBS", @"全屏投影", screen, 0),
                                                            FollowWindowInfo(settings, obsPID, @"OBS", @"设置", smallPanel, 0)]
                                                 ambiguous:&ambiguous note:&note];
    Check(target == projector && !ambiguous, @"唯一的大画面窗口 + 小弹窗时跟随大画面");

    // 观察不到选中窗口（离线夹具/窗口列表查不到所有者）：沿用用户选择，保持既有行为。
    app.fixtureOwnerPID = 0;
    FollowSetWindowSelection(app, editor, @"OBS · 编辑器");
    target = [app resolveDisplayTargetWindowIDInWindowList:@[] ambiguous:&ambiguous note:&note];
    Check(target == editor && !ambiguous, @"观察不到窗口时沿用用户选择（不改既有行为）");
}

#pragma mark - B. 实时窗口几何

static void TestLiveWindowBounds(FYLearningStore *store, FYLearningAnalyzer *analyzer, FYGrammarCatalog *catalog) {
    FollowApp *app = FollowMakeApp(store, analyzer, catalog);
    CGRect stale = CGRectMake(0, 0, 800, 600);
    WindowItem *item = FollowWindowItem(9301, @"OBS", @"编辑器", stale);
    app.windows = [NSMutableArray arrayWithObject:item];
    FollowSetWindowSelection(app, 9301, @"OBS · 编辑器");

    NSRect fromStale = [app appKitFrameForWindowItem:item];
    CGRect live = CGRectMake(310, 220, 1024, 700);
    app.liveBounds[@(9301)] = [NSValue valueWithRect:NSRectFromCGRect(live)];
    NSRect fromLive = [app appKitFrameForWindowItem:item];
    CGFloat expectedY = NSMaxY(NSScreen.mainScreen.frame) - live.origin.y - live.size.height;
    Check(NSEqualRects(fromLive, NSMakeRect(live.origin.x, expectedY, live.size.width, live.size.height)),
          @"窗口移动/缩放后按实时边界换算（含 AppKit 纵坐标翻转）");
    Check(!NSEqualRects(fromLive, fromStale), @"实时边界不再使用下拉列表里的旧快照");

    // 只在尺寸不变时移动：同样必须跟随。
    CGRect moved = CGRectMake(live.origin.x + 120, live.origin.y - 40, live.size.width, live.size.height);
    app.liveBounds[@(9301)] = [NSValue valueWithRect:NSRectFromCGRect(moved)];
    NSRect fromMoved = [app appKitFrameForWindowItem:item];
    Check(fabs(NSMinX(fromMoved) - (live.origin.x + 120)) < 0.5 && fabs(NSMinY(fromMoved) - (NSMaxY(NSScreen.mainScreen.frame) - moved.origin.y - moved.size.height)) < 0.5,
          @"窗口尺寸不变、位置变化时仍按实时边界定位");

    // 查不到实时边界（窗口已关闭 / 离线夹具）时退回快照，不把几何丢成 0。
    [app.liveBounds removeAllObjects];
    Check(NSEqualRects([app appKitFrameForWindowItem:item], fromStale), @"实时查询不可用时退回列表快照（不塌成 0）");
}

#pragma mark - C. 真实入口：文本未变化时几何仍要跟随

static void TestSameTextGeometryFollow(FYLearningStore *store, FYLearningAnalyzer *analyzer, FYGrammarCatalog *catalog) {
    gRequests = 0;
    gSubmittedSources = [NSMutableArray array];
    gHoldResponse = NO;
    FollowApp *app = FollowMakeApp(store, analyzer, catalog);
    const uint32_t editor = 9401, projector = 9402;
    CGRect editorBounds = FollowEditorBounds();
    CGRect screenBounds = FollowScreenQuartzBounds();
    app.fixtureOwnerPID = 0;
    WindowItem *editorItem = FollowWindowItem(editor, @"OBS", @"编辑器", editorBounds);
    WindowItem *projectorItem = FollowWindowItem(projector, @"OBS", @"全屏投影", screenBounds);
    FollowSetWindowSelection(app, editor, @"OBS · 编辑器");
    app.windows = [NSMutableArray arrayWithObjects:editorItem, projectorItem, nil];
    [app.windowPopup removeAllItems];
    [app.windowPopup addItemWithTitle:@"OBS · 编辑器"];
    [app.windowPopup addItemWithTitle:@"OBS · 全屏投影"];
    app.windowPopup.menu.itemArray[0].representedObject = @(editor);
    app.windowPopup.menu.itemArray[1].representedObject = @(projector);
    [app.windowPopup selectItemAtIndex:0];
    app.liveBounds[@(editor)] = [NSValue valueWithRect:NSRectFromCGRect(editorBounds)];
    app.liveBounds[@(projector)] = [NSValue valueWithRect:NSRectFromCGRect(screenBounds)];
    app.ocrFixture = @[FollowItem(@"設定を開きます", CGRectMake(0.30, 0.62, 0.30, 0.055)),
                       FollowItem(@"保存して戻る", CGRectMake(0.30, 0.52, 0.28, 0.055))];

    FollowRunCycle(app);
    NSUInteger requestsAfterFirst = gRequests;
    Check(requestsAfterFirst > 0, @"第一轮真的走过了网络翻译路径（mock 请求被记录）");
    Check(FollowPanels(app).count > 0, @"第一轮按编辑器几何渲染出了贴译面板");
    NSRect editorFrame = [app appKitFrameForWindowItem:editorItem];
    Check(FollowAnyPanelInside(app, editorFrame), @"面板落在编辑器窗口范围内");
    NSUInteger panelsAfterFirst = FollowPanels(app).count;
    NSArray<NSValue *> *framesAfterFirst = FollowPanelFrames(app);

    // —— ① 同一文本、窗口移动/缩放：文本完全没变，但几何必须重新布局 ——
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];   // 越过几何查询限流
    CGRect movedEditor = CGRectMake(editorBounds.origin.x + 140, editorBounds.origin.y + 60,
                                    editorBounds.size.width - 200, editorBounds.size.height - 90);
    app.liveBounds[@(editor)] = [NSValue valueWithRect:NSRectFromCGRect(movedEditor)];
    FollowRunCycle(app);
    Check(gRequests == requestsAfterFirst, @"文本未变化时不重新请求翻译（复用已有译文）");
    Check([app.statusLabel.stringValue containsString:@"文本未变化"], [NSString stringWithFormat:@"第二轮确实命中了「文本未变化」的提前返回分支（status=<%@>）", app.statusLabel.stringValue ?: @"(nil)"]);
    NSRect movedFrame = [app appKitFrameForWindowItem:editorItem];
    Check(FollowPanels(app).count == panelsAfterFirst, @"面板数量不变（不是清掉重建）");
    Check(FollowAnyPanelInside(app, movedFrame), @"窗口移动后贴译跟到新位置");
    NSArray<NSValue *> *framesAfterMove = FollowPanelFrames(app);
    Check(!FollowAnyFrameUnchanged(framesAfterFirst, framesAfterMove), @"窗口移动后没有任何面板停在旧坐标（同文本也必须重排）");
    Check(app.geometryGeneration > 0, @"几何代次随画面区域变化自增");
    FollowLogGeometry(app, @"editor-same-text-moved");

    // —— ② 文本不变、目标切到全屏投影：贴译跟到投影窗口 ——
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    NSUInteger requestsBeforeSwitch = gRequests;
    app.usesScriptedTarget = YES;
    app.scriptedTargetID = projector;
    FollowRunCycle(app);
    Check(gRequests == requestsBeforeSwitch, @"切到全屏投影不需要重新翻译");
    NSRect projectorFrame = [app appKitFrameForWindowItem:projectorItem];
    Check(FollowAnyPanelInside(app, projectorFrame), @"切到全屏投影后贴译落在投影窗口上");
    NSArray<NSValue *> *framesAfterSwitch = FollowPanelFrames(app);
    Check(!FollowAnyFrameUnchanged(framesAfterMove, framesAfterSwitch), @"切到全屏投影后没有任何面板停在编辑器坐标上");
    FollowLogGeometry(app, @"fullscreen-projector");

    // —— ③ 再切回编辑器（投影窗口关闭）：恢复正确位置 ——
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    app.scriptedTargetID = editor;
    FollowRunCycle(app);
    Check(FollowAnyPanelInside(app, movedFrame), @"回到编辑器后恢复正确贴译位置");
    NSArray<NSValue *> *framesAfterReturn = FollowPanelFrames(app);
    Check(!FollowAnyFrameUnchanged(framesAfterSwitch, framesAfterReturn), @"回到编辑器后没有任何面板停在投影坐标上");
    FollowLogGeometry(app, @"back-to-editor");

    // —— ④ 多个投影无法确定：隐藏旧贴译并提示选择 ——
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    app.scriptedTargetAmbiguous = YES;
    FollowRunCycle(app);
    Check(FollowAllPanelsHidden(app), @"目标无法确定时隐藏旧位置的贴译");
    Check([app.statusLabel.stringValue containsString:@"请重新选择"], @"目标无法确定时明确提示重新选择");
    Check(app.displayTargetAmbiguous, @"歧义状态被记录");

    // —— ⑤ 歧义解除：缓存译文按新几何恢复，不需要重新翻译 ——
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    NSUInteger requestsBeforeRecover = gRequests;
    app.scriptedTargetAmbiguous = NO;
    app.scriptedTargetID = editor;
    FollowRunCycle(app);
    Check(gRequests == requestsBeforeRecover, @"歧义解除后复用缓存译文，不重复请求");
    Check(FollowAnyPanelInside(app, movedFrame), @"歧义解除后贴译回到当前画面位置");
}

#pragma mark - D. 异步翻译返回时校验目标与几何代次

static void TestStaleCallbackDoesNotRestoreOldPosition(FYLearningStore *store, FYLearningAnalyzer *analyzer, FYGrammarCatalog *catalog) {
    gRequests = 0;
    gSubmittedSources = [NSMutableArray array];
    gHoldResponse = NO;
    FollowApp *app = FollowMakeApp(store, analyzer, catalog);
    const uint32_t editor = 9501, projector = 9502;
    CGRect editorBounds = FollowEditorBounds();
    CGRect screenBounds = FollowScreenQuartzBounds();
    WindowItem *editorItem = FollowWindowItem(editor, @"OBS", @"编辑器", editorBounds);
    WindowItem *projectorItem = FollowWindowItem(projector, @"OBS", @"全屏投影", screenBounds);
    FollowSetWindowSelection(app, editor, @"OBS · 编辑器");
    app.windows = [NSMutableArray arrayWithObjects:editorItem, projectorItem, nil];
    app.liveBounds[@(editor)] = [NSValue valueWithRect:NSRectFromCGRect(editorBounds)];
    app.liveBounds[@(projector)] = [NSValue valueWithRect:NSRectFromCGRect(screenBounds)];

    // 预热：让页面 A 的译文进缓存并渲染在编辑器几何上。
    app.ocrFixture = @[FollowItem(@"通話へ", CGRectMake(0.10, 0.70, 0.20, 0.05))];
    FollowRunCycle(app);
    NSUInteger afterWarmup = gRequests;
    Check(afterWarmup > 0, @"预热轮发出过翻译请求");
    NSArray<NSValue *> *cachedEditorFrames = FollowPanelFrames(app);
    Check(cachedEditorFrames.count > 0, @"预热轮在编辑器几何上渲染出面板（陈旧回调的对照物）");
    Check([app.statusLabel.stringValue containsString:@"界面译文已更新"], @"预热轮确实渲染了贴译");

    // 第二轮：换一段**没有缓存**的文字（否则不会有在途请求），扣住响应不返回。
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    app.ocrFixture = @[FollowItem(@"別の画面です", CGRectMake(0.18, 0.64, 0.26, 0.05))];
    gHoldResponse = YES;
    [app timerFired:nil];
    Pump(^BOOL { return gPendingResponse != nil; });
    Check(gPendingResponse != nil, @"第二轮的网络请求被扣住在途（真实异步路径）");
    Check(app.inFlight, @"翻译在途时 inFlight 为真");

    // 响应回来之前切到全屏投影，并让几何复核发现这次切换（真实应用里由 0.5 秒轮询触发）。
    app.usesScriptedTarget = YES;
    app.scriptedTargetID = projector;
    [app refreshDisplayGeometryIfNeeded:YES];
    NSRect projectorFrame = [app appKitFrameForWindowItem:projectorItem];
    Check(app.geometryGeneration > 0 && FollowAllPanelsHidden(app),
          @"换了承载画面的窗口后先隐藏旧贴译（旧原文块属于另一个窗口的坐标系）");
    Check(!FollowAnyFrameUnchanged(cachedEditorFrames, FollowPanelFrames(app)) || FollowAllPanelsHidden(app),
          @"切换目标后编辑器坐标上的贴译不再保留");
    FollowLogGeometry(app, @"stale-callback-target-switched-hidden");

    void (^pending)(void) = gPendingResponse;
    gPendingResponse = nil;
    if (pending) { pending(); }
    gHoldResponse = NO;
    Pump(^BOOL { return !app.inFlight; });
    Tick();

    Check(!FollowAnyFrameUnchanged(cachedEditorFrames, FollowPanelFrames(app)) || FollowAllPanelsHidden(app),
          @"过期回调没有把贴译按旧几何放回编辑器");
    Check(FollowAnyPanelInside(app, projectorFrame) || FollowAllPanelsHidden(app),
          @"过期回调之后贴译位于当前投影窗口或暂时隐藏");
    Check(![app.statusLabel.stringValue containsString:@"界面译文已更新：1 条"] ||
          [app.statusLabel.stringValue containsString:@"投影"],
          @"过期回调没有把这一批当成本轮结果应用（状态未被旧回调改写为编辑器几何的结果）");

    // 再来一轮：用**当前帧的原文块 + 缓存译文**按投影几何重排，不重复请求翻译。
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    NSUInteger before = gRequests;
    FollowRunCycle(app);
    Check(gRequests == before, @"陈旧回调之后的续跑不重复请求翻译（走缓存重排）");
    Check(FollowAnyPanelInside(app, projectorFrame), @"续跑后贴译按投影窗口的原文块重新贴好");
    FollowLogGeometry(app, @"stale-callback-after-cache-rerender");
}

int main(void) {
    @autoreleasepool {
        unsetenv("FUYI_DIAG");
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

        method_exchangeImplementations(class_getClassMethod(FYTestURLSession.class, @selector(sharedSession)),
                                       class_getClassMethod(FYTestURLSession.class, @selector(followTestSession)));

        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        Require([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL],
                @"temporary directory failed");
        FYLearningStore *store = Store([directory stringByAppendingPathComponent:@"follow.sqlite3"]);
        FYGrammarCatalog *catalog = [[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]];
        Require([catalog loadWithError:NULL], @"grammar catalog failed");
        FYLearningAnalyzer *analyzer = Analyzer(catalog);

        TestDisplayTargetPolicy(store, analyzer, catalog);
        TestLiveWindowBounds(store, analyzer, catalog);
        TestSameTextGeometryFollow(store, analyzer, catalog);
        TestStaleCallbackDoesNotRestoreOldPosition(store, analyzer, catalog);

        Require(gFailures == 0, [NSString stringWithFormat:@"%lu 条断言失败", (unsigned long)gFailures]);
        printf("PASS DisplayTargetFollowTests: %lu 条断言；显示目标解析 / 实时几何 / 同文本跟随 / 切换回编辑器 / 歧义处理 / 陈旧回调丢弃（合成夹具 + mock HTTP）\n",
               (unsigned long)gChecks);
    }
    return 0;
}
