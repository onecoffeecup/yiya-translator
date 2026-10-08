// 采集卡坐标映射 + 贴译落位专项验证（2026-10-06）。
//
// 背景：自动定位把「像素网格（第 0 行 = 图像顶部）」的 y 直接加到 AppKit 窗口底部，
// 漏了纵坐标翻转，导致映射整体下移（OBS 预览靠上时贴译落到下方控制区）。
//
// 本套件只做**离线隔离**验证（合成窗口截图 + 合成采集帧 + 明确的几何夹具），
// 不会触碰真实屏幕内容、不会安装或重启正式应用：
//   · 网格朝向：构造「上白下黑」的像素缓冲，确认 FYGrayGridFromImage 第 0 行 = 图像顶部；
//   · 顶部/中部/底部三种非对称摆放 → 定位结果必须等于它被画进去的那个矩形；
//   · OBS 式窗口（上方预览 + 下方控制区）→ 不能被判成控制区；
//   · 窗口尺寸不变、内部画面移动 → 旧映射必须失效并重新定位；
//   · 旧版（mappingVersion=1）保存的错误自动映射 → 直接作废；
//   · 坐标链路：OCR 归一化框 → 视频显示区域 → 屏幕 AppKit 坐标 → 贴译落位。
//
// 输出诊断图：窗口截图 + 视频区域边界（青）+ 原文框（蓝）+ 译文框（黄/橙）。

#import "LearningAppTestSupport.h"
#import "FYTestCaptureCardInput.h"

static NSUInteger gFailures = 0;
static NSString *gOutputDirectory = nil;
static void Check(BOOL ok, NSString *message) {
    if (ok) {
        NSLog(@"PASS %@", message);
    } else {
        gFailures += 1;
        NSLog(@"FAIL %@", message);
    }
}

#pragma mark - 合成图

/// 上白下黑（或上黑下白）的像素缓冲：CGImage 数据第 0 行 = 图像顶部。
static CGImageRef AsymmetricBandImage(size_t size, BOOL whiteOnTop) {
    uint8_t *buf = calloc(size * size, 1);
    for (size_t y = 0; y < size; y++) {
        for (size_t x = 0; x < size; x++) {
            buf[y * size + x] = (whiteOnTop ? (y < size / 2) : (y >= size / 2)) ? 255 : 0;
        }
    }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(buf, size, size, 8, size, cs, kCGImageAlphaNone);
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
    free(buf);
    return image;
}

/// 有明确纵向特征的采集画面：随机色块 + 顶部一条亮带 + 底部一条暗带。
/// （纵向不对称，镜像摆放会给出完全不同的相关性，不会掩盖纵坐标错误。）
static CGImageRef CapturePatternImage(size_t width, size_t height, unsigned seed) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!ctx) { return NULL; }
    unsigned state = seed;
    size_t cols = 16, rows = 9;
    for (size_t j = 0; j < rows; j++) {
        for (size_t i = 0; i < cols; i++) {
            state = state * 1103515245u + 12345u;
            double v = ((state >> 16) & 0xFF) / 255.0;
            double v2 = ((state >> 8) & 0xFF) / 255.0;
            CGContextSetRGBFillColor(ctx, v, v2, 1.0 - v, 1);
            CGContextFillRect(ctx, CGRectMake(i * (CGFloat)width / cols, j * (CGFloat)height / rows,
                                              (CGFloat)width / cols + 1, (CGFloat)height / rows + 1));
        }
    }
    // 顶部亮带（CG 坐标里靠上）——镜像后会跑到下方
    CGContextSetRGBFillColor(ctx, 0.98, 0.95, 0.90, 1);
    CGContextFillRect(ctx, CGRectMake(0, (CGFloat)height * 0.86, (CGFloat)width, (CGFloat)height * 0.14));
    // 底部暗带
    CGContextSetRGBFillColor(ctx, 0.05, 0.05, 0.07, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height * 0.10));
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return image;
}

/// 合成目标窗口截图（CG 坐标：原点左下）。
/// chrome: 0 = QuickTime 式（顶部标题栏）；1 = OBS 式（顶部标题栏 + 下方控制区）。
static CGImageRef WindowScene(CGImageRef video, size_t width, size_t height, CGRect videoRectCG,
                              CGFloat titleBar, NSInteger chrome) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!ctx) { return NULL; }
    CGContextSetRGBFillColor(ctx, 0.08, 0.08, 0.09, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, width, height));
    // 标题栏
    CGContextSetRGBFillColor(ctx, 0.35, 0.35, 0.37, 1);
    CGContextFillRect(ctx, CGRectMake(0, height - titleBar, width, titleBar));
    CGContextSetRGBFillColor(ctx, 0.86, 0.30, 0.26, 1);
    CGContextFillEllipseInRect(ctx, CGRectMake(16, height - titleBar / 2 - 7, 14, 14));
    CGContextSetRGBFillColor(ctx, 0.95, 0.75, 0.25, 1);
    CGContextFillEllipseInRect(ctx, CGRectMake(38, height - titleBar / 2 - 7, 14, 14));
    // OBS 式：下方控制区（音频条/按钮），自动定位绝不能把它当画面
    if (chrome == 1) {
        CGFloat panelHeight = height * 0.26;
        CGContextSetRGBFillColor(ctx, 0.16, 0.16, 0.18, 1);
        CGContextFillRect(ctx, CGRectMake(0, 0, width, panelHeight));
        for (NSInteger i = 0; i < 6; i++) {
            CGContextSetRGBFillColor(ctx, 0.45, 0.55, 0.65, 1);
            CGContextFillRect(ctx, CGRectMake(width * 0.06, panelHeight * 0.15 + i * panelHeight * 0.12,
                                              width * (0.20 + 0.06 * i), panelHeight * 0.06));
            CGContextSetRGBFillColor(ctx, 0.30, 0.75, 0.45, 1);
            CGContextFillRect(ctx, CGRectMake(width * 0.62, panelHeight * 0.15 + i * panelHeight * 0.12,
                                              width * 0.30, panelHeight * 0.06));
        }
    }
    if (video) { CGContextDrawImage(ctx, videoRectCG, video); }
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return image;
}

#pragma mark - 测试用 App

static WindowItem *FixtureWindow(CGRect bounds) {
    WindowItem *item = [WindowItem new];
    item.windowID = 777;
    item.displayName = @"合成分辨窗口";
    item.bounds = bounds;
    return item;
}

@interface MappingTestApp : AppDelegate
@property(nonatomic, strong) WindowItem *fixtureWindow;
@end
@implementation MappingTestApp
- (BOOL)hasUsableScreenCaptureAccess { return YES; }
- (WindowItem *)selectedWindowItem { return self.fixtureWindow; }
- (uint32_t)selectedWindowID { return self.fixtureWindow.windowID; }
@end

static MappingTestApp *MappingApp(CGRect windowBounds) {
    MappingTestApp *app = [MappingTestApp new];
    app.fixtureWindow = FixtureWindow(windowBounds);
    FYTestCaptureCardInput *input = [FYTestCaptureCardInput new];
    input.testAvailability = FYCaptureCardAvailabilityAuthorized;
    app.captureCardInput = input;
    app.inputSourceSegment = 1;                       // 采集卡模式
    app.selectedCaptureDeviceID = @"usb-video";
    app.captureCardVideoRects = [NSMutableDictionary dictionary];
    return app;
}

/// 采样「窗口坐标系（左下原点、点）」→ CG 位图坐标（左下原点）的换算：
/// CGContextDrawImage 在左下原点的位图上下文里绘制，给出的 rect 直接用即可。
static NSRect ExpectedScreenRect(NSRect windowFrame, CGRect videoRectCG, size_t sceneW, size_t sceneH) {
    return NSMakeRect(NSMinX(windowFrame) + videoRectCG.origin.x / sceneW * NSWidth(windowFrame),
                      NSMinY(windowFrame) + videoRectCG.origin.y / sceneH * NSHeight(windowFrame),
                      videoRectCG.size.width / sceneW * NSWidth(windowFrame),
                      videoRectCG.size.height / sceneH * NSHeight(windowFrame));
}

static BOOL RectNear(NSRect a, NSRect b, CGFloat tolerance) {
    return fabs(NSMinX(a) - NSMinX(b)) <= tolerance && fabs(NSMinY(a) - NSMinY(b)) <= tolerance &&
           fabs(NSWidth(a) - NSWidth(b)) <= tolerance * 1.5 && fabs(NSHeight(a) - NSHeight(b)) <= tolerance * 1.5;
}

#pragma mark - 诊断图

static void RenderMappingDiagnostics(CGImageRef scene, NSRect windowFrame, NSRect videoRect,
                                     NSArray<NSValue *> *sourceFrames, NSArray<NSValue *> *translationFrames,
                                     NSString *path) {
    if (!scene) { return; }
    // 用普通 CG 位图上下文绘制：与源截图同为「原点左下」，不经过 NSImage/backing 缩放，
    // 所以诊断图的方向和比例与真实截图一致（不会上下镜像或被 Retina 放大）。
    size_t width = CGImageGetWidth(scene), height = CGImageGetHeight(scene);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!ctx) { return; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), scene);

    NSRect (^pixelRect)(NSRect) = ^NSRect(NSRect frame) {
        return NSMakeRect((NSMinX(frame) - NSMinX(windowFrame)) / NSWidth(windowFrame) * width,
                          (NSMinY(frame) - NSMinY(windowFrame)) / NSHeight(windowFrame) * height,
                          NSWidth(frame) / NSWidth(windowFrame) * width,
                          NSHeight(frame) / NSHeight(windowFrame) * height);
    };
    void (^stroke)(NSRect, CGFloat, CGFloat, CGFloat) = ^(NSRect rect, CGFloat r, CGFloat g, CGFloat b) {
        CGContextSetRGBStrokeColor(ctx, r, g, b, 1);
        CGContextSetLineWidth(ctx, MAX(2.0, width / 400.0));
        CGContextStrokeRect(ctx, pixelRect(rect));
    };
    stroke(videoRect, 0, 0.85, 0.85);                       // 青：视频显示区域边界
    for (NSValue *value in sourceFrames) { stroke(value.rectValue, 0.15, 0.5, 1); }      // 蓝：原文框
    for (NSValue *value in translationFrames) { stroke(value.rectValue, 1, 0.75, 0.05); } // 黄：译文位置

    NSGraphicsContext *graphics = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:graphics];
    NSString *label = @"青=视频区域  蓝=原文框  黄=译文位置  （离线合成夹具：非真实采集画面）";
    [label drawAtPoint:NSMakePoint(10, height - 26)
        withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold],
                         NSForegroundColorAttributeName: NSColor.whiteColor}];
    [NSGraphicsContext restoreGraphicsState];

    CGImageRef composed = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    if (!composed) { return; }
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:composed];
    CGImageRelease(composed);
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

#pragma mark - 1. 网格朝向

static void TestGridOrientation(void) {
    CGImageRef whiteTop = AsymmetricBandImage(8, YES);
    double *grid = FYGrayGridFromImage(whiteTop, 8, 8);
    Check(grid != NULL, @"灰度网格可生成");
    if (grid) {
        Check(grid[0] > 200 && grid[7 * 8] < 50,
              [NSString stringWithFormat:@"网格第 0 行 = 图像顶部（上白下黑：row0=%.0f row7=%.0f）", grid[0], grid[7 * 8]]);
        free(grid);
    }
    CGImageRelease(whiteTop);
}

#pragma mark - 2. 顶部 / 中部 / 底部

static void TestAutoLocateTopMiddleBottom(void) {
    const size_t sceneW = 1000, sceneH = 700;
    // topInset = 画面顶部距窗口顶部的距离（场景像素）；三种摆放都保证画面完整落在窗口内。
    struct { const char *name; const char *file; CGFloat topInset; } cases[] = {
        {"顶部", "top", 20}, {"中部", "middle", 160}, {"底部", "bottom", 300}
    };
    for (size_t index = 0; index < 3; index++) {
        MappingTestApp *app = MappingApp(CGRectMake(100, 80, 800, 600));
        FYTestCaptureCardInput *input = (FYTestCaptureCardInput *)app.captureCardInput;
        CGImageRef frame = CapturePatternImage(320, 180, 4242 + (unsigned)index);
        // 画面必须按采集帧的真实比例（16:9）画：拉伸过的内容会让定点匹配退化，掩盖算法误差。
        const CGFloat videoW = 720, videoH = videoW * 180.0 / 320.0;
        // 屏幕上的「上」= CG 坐标里 y 大的一侧
        CGRect videoInScene = CGRectMake(140, sceneH - cases[index].topInset - videoH, videoW, videoH);
        CGImageRef scene = WindowScene(frame, sceneW, sceneH, videoInScene, 62, 0);
        FYTestSetWindowImage(scene);
        Check([input testStoreFrame:frame index:1], @"采集帧已注入");
        Check([app autoDetectCaptureCardVideoRectForWindow:app.fixtureWindow reason:NULL],
              [NSString stringWithFormat:@"%s摆放：自动定位成功", cases[index].name]);
        NSRect detected = NSZeroRect;
        Check([app captureCardDisplayRectForWindow:app.fixtureWindow outRect:&detected], @"定位结果立即可用");
        NSRect windowFrame = [app appKitFrameForWindowItem:app.fixtureWindow];
        NSRect expected = ExpectedScreenRect(windowFrame, videoInScene, sceneW, sceneH);
        Check(RectNear(detected, expected, MAX(12, NSHeight(windowFrame) * 0.03)),
              [NSString stringWithFormat:@"%s摆放：定位结果 = 画面被画进去的位置（detected=%s expected=%s）",
               cases[index].name, NSStringFromRect(detected).UTF8String, NSStringFromRect(expected).UTF8String]);
        // 明确排除「镜像」结果（旧 bug 会把上下翻过来）
        CGFloat mirroredY = NSMinY(windowFrame) + (sceneH - videoInScene.origin.y - videoInScene.size.height) / sceneH * NSHeight(windowFrame);
        Check(fabs(NSMinY(detected) - mirroredY) > 20 || fabs(mirroredY - NSMinY(expected)) < 20,
              [NSString stringWithFormat:@"%s摆放：结果不是上下镜像出来的（镜像 y=%.0f）", cases[index].name, mirroredY]);
        RenderMappingDiagnostics(scene, windowFrame, detected, @[], @[],
                                 [gOutputDirectory stringByAppendingPathComponent:
                                  [NSString stringWithFormat:@"mapping-%s.png", cases[index].file]]);
        CGImageRelease(frame);
        CGImageRelease(scene);
        FYTestSetWindowImage(NULL);
    }
}

#pragma mark - 3. OBS 式窗口：上方预览 + 下方控制区

static void TestOBSChromeDoesNotWin(void) {
    // 场景比例必须等于窗口比例（1.40625），画面按 16:9 画进去，否则内容被拉伸会影响定位精度。
    const size_t sceneW = 1080, sceneH = 768;
    MappingTestApp *app = MappingApp(CGRectMake(60, 40, 900, 640));
    FYTestCaptureCardInput *input = (FYTestCaptureCardInput *)app.captureCardInput;
    CGImageRef frame = CapturePatternImage(320, 180, 909);
    // 预览在窗口上方（CG：y 大），下方 26% 是控制区
    CGRect videoInScene = CGRectMake(135, sceneH - 40 - 455.6, 810, 455.6);
    CGImageRef scene = WindowScene(frame, sceneW, sceneH, videoInScene, 34, 1);
    FYTestSetWindowImage(scene);
    [input testStoreFrame:frame index:1];
    Check([app autoDetectCaptureCardVideoRectForWindow:app.fixtureWindow reason:NULL], @"OBS 式窗口：自动定位成功");
    NSRect detected = NSZeroRect;
    [app captureCardDisplayRectForWindow:app.fixtureWindow outRect:&detected];
    NSRect windowFrame = [app appKitFrameForWindowItem:app.fixtureWindow];
    NSRect expected = ExpectedScreenRect(windowFrame, videoInScene, sceneW, sceneH);
    Check(RectNear(detected, expected, MAX(12, NSHeight(windowFrame) * 0.03)),
          [NSString stringWithFormat:@"OBS 式窗口：定位到上方预览区（detected=%s expected=%s）",
           NSStringFromRect(detected).UTF8String, NSStringFromRect(expected).UTF8String]);
    // 预览占窗口高度约 71%，所以看**中心**是否在上半部，而不是看下边缘
    Check(NSMidY(detected) > NSMidY(windowFrame),
          [NSString stringWithFormat:@"OBS 式窗口：区域中心落在窗口上半部（中心=%.0f 窗口中线=%.0f）",
           NSMidY(detected), NSMidY(windowFrame)]);
    Check(NSMinY(detected) > NSMinY(windowFrame) + NSHeight(windowFrame) * 0.20,
          @"OBS 式窗口：没有把下方控制区算进画面（这是用户报的“译文掉到控制区”）");
    RenderMappingDiagnostics(scene, windowFrame, detected, @[], @[],
                             [gOutputDirectory stringByAppendingPathComponent:@"mapping-obs-chrome.png"]);
    CGImageRelease(frame);
    CGImageRelease(scene);
    FYTestSetWindowImage(NULL);
}

#pragma mark - 4. 窗口尺寸不变、内部画面移动 → 旧映射失效并重定位

static void TestStaleMappingIsRelocated(void) {
    const size_t sceneW = 1000, sceneH = 700;
    MappingTestApp *app = MappingApp(CGRectMake(50, 50, 800, 560));
    FYTestCaptureCardInput *input = (FYTestCaptureCardInput *)app.captureCardInput;
    CGImageRef frame = CapturePatternImage(320, 180, 5150);
    const CGFloat videoW = 720, videoH = videoW * 180.0 / 320.0;
    CGRect firstRect = CGRectMake(140, sceneH - 40 - videoH, videoW, videoH);
    CGImageRef scene1 = WindowScene(frame, sceneW, sceneH, firstRect, 40, 0);
    FYTestSetWindowImage(scene1);
    [input testStoreFrame:frame index:1];
    Check([app autoDetectCaptureCardVideoRectForWindow:app.fixtureWindow reason:NULL], @"首次定位成功");
    NSRect first = NSZeroRect;
    [app captureCardDisplayRectForWindow:app.fixtureWindow outRect:&first];
    NSRect windowFrame = [app appKitFrameForWindowItem:app.fixtureWindow];

    // 同一个窗口（尺寸与比例完全不变），画面在窗口内部下移
    CGRect secondRect = CGRectMake(140, 60, videoW, videoH);
    CGImageRef scene2 = WindowScene(frame, sceneW, sceneH, secondRect, 40, 0);
    FYTestSetWindowImage(scene2);
    app.lastMappingValidationDate = nil;                 // 强制本轮做定点复核
    NSDictionary *entryBefore = app.captureCardVideoRects[@"777"];
    double movedScore = entryBefore ? [app captureCardMappingScoreForWindow:app.fixtureWindow entry:entryBefore] : -2;
    NSRect second = NSZeroRect;
    BOOL stillValid = [app captureCardDisplayRectForWindow:app.fixtureWindow outRect:&second];
    Check(!stillValid || fabs(NSMinY(second) - NSMinY(first)) > NSHeight(windowFrame) * 0.05,
          [NSString stringWithFormat:@"窗口没变、画面移动：旧映射必须失效或已更新（first=%.0f second=%.0f 旧位置得分=%.3f）",
           NSMinY(first), NSMinY(second), movedScore]);
    Check(!stillValid && app.captureCardVideoRects[@"777"] == nil,
          @"画面移动后旧映射被移除（不会继续用错位置）");
    // 上层入口应当自动重新定位到新位置
    NSRect relocated = NSZeroRect;
    Check([app inlinePlacementRect:&relocated reason:NULL], @"移动后 inlinePlacementRect 能重新定位");
    NSRect expectedSecond = ExpectedScreenRect(windowFrame, secondRect, sceneW, sceneH);
    Check(RectNear(relocated, expectedSecond, MAX(12, NSHeight(windowFrame) * 0.03)),
          [NSString stringWithFormat:@"重新定位到新位置（relocated=%s expected=%s）",
           NSStringFromRect(relocated).UTF8String, NSStringFromRect(expectedSecond).UTF8String]);
    Check(fabs(NSMinY(relocated) - NSMinY(first)) > NSHeight(windowFrame) * 0.05,
          @"重新定位后的位置确实和旧位置不同");
    CGImageRelease(frame);
    CGImageRelease(scene1);
    CGImageRelease(scene2);
    FYTestSetWindowImage(NULL);
}

#pragma mark - 5. 旧版保存的错误自动映射

static void TestOldVersionMappingDropped(void) {
    const size_t sceneW = 1000, sceneH = 700;
    MappingTestApp *app = MappingApp(CGRectMake(30, 30, 800, 600));
    FYTestCaptureCardInput *input = (FYTestCaptureCardInput *)app.captureCardInput;
    NSRect windowFrame = [app appKitFrameForWindowItem:app.fixtureWindow];
    // 旧版（没有 mappingVersion 字段）的自动映射：纵坐标是错的那种
    const CGFloat videoW = 780, videoH = videoW * 180.0 / 320.0;
    CGRect videoInScene = CGRectMake(100, sceneH - 30 - videoH, videoW, videoH);
    NSRect wrong = NSMakeRect(NSMinX(windowFrame) + videoInScene.origin.y / sceneH * NSWidth(windowFrame),
                              NSMinY(windowFrame) + videoInScene.origin.y / sceneH * NSHeight(windowFrame),
                              videoInScene.size.width / sceneW * NSWidth(windowFrame),
                              videoInScene.size.height / sceneH * NSHeight(windowFrame));
    app.captureCardVideoRects[@"777"] = @{
        @"nx": @((NSMinX(wrong) - NSMinX(windowFrame)) / NSWidth(windowFrame)),
        @"ny": @((NSMinY(wrong) - NSMinY(windowFrame)) / NSHeight(windowFrame)),
        @"nw": @(NSWidth(wrong) / NSWidth(windowFrame)),
        @"nh": @(NSHeight(wrong) / NSHeight(windowFrame)),
        @"windowAspect": @(NSWidth(windowFrame) / NSHeight(windowFrame)),
        @"videoAspect": @(320.0 / 180.0),
        @"deviceID": @"usb-video",
        @"source": @"auto",
        @"confidence": @(0.9)
    };
    NSString *reason = nil;
    Check(![app captureCardDisplayRectForWindow:app.fixtureWindow outRect:NULL reason:&reason],
          @"旧版自动映射（无版本号）直接被拒用");
    Check([reason containsString:@"旧版"], [NSString stringWithFormat:@"拒绝原因可读：%@", reason]);
    Check(app.captureCardVideoRects[@"777"] == nil, @"旧映射已从缓存里删除");

    // 随后应当自动重新定位到正确位置
    CGImageRef frame = CapturePatternImage(320, 180, 6621);
    CGImageRef scene = WindowScene(frame, sceneW, sceneH, videoInScene, 30, 0);
    FYTestSetWindowImage(scene);
    [input testStoreFrame:frame index:1];
    NSRect relocated = NSZeroRect;
    Check([app inlinePlacementRect:&relocated reason:NULL], @"旧映射作废后能自动重新定位");
    NSRect expected = ExpectedScreenRect(windowFrame, videoInScene, sceneW, sceneH);
    Check(RectNear(relocated, expected, 14),
          [NSString stringWithFormat:@"重新定位到正确位置（relocated=%s expected=%s）",
           NSStringFromRect(relocated).UTF8String, NSStringFromRect(expected).UTF8String]);
    CGImageRelease(frame);
    CGImageRelease(scene);
    FYTestSetWindowImage(NULL);
}

#pragma mark - 6. 窗口移动 / 缩放 / 比例变化

static void TestWindowMoveResizeAspect(void) {
    const size_t sceneW = 1000, sceneH = 700;
    MappingTestApp *app = MappingApp(CGRectMake(100, 60, 800, 600));
    FYTestCaptureCardInput *input = (FYTestCaptureCardInput *)app.captureCardInput;
    CGImageRef frame = CapturePatternImage(320, 180, 7331);
    const CGFloat videoW = 720, videoH = videoW * 180.0 / 320.0;
    CGRect videoInScene = CGRectMake(140, sceneH - 40 - videoH, videoW, videoH);
    CGImageRef scene = WindowScene(frame, sceneW, sceneH, videoInScene, 40, 0);
    FYTestSetWindowImage(scene);
    [input testStoreFrame:frame index:1];
    Check([app autoDetectCaptureCardVideoRectForWindow:app.fixtureWindow reason:NULL], @"基准定位成功");
    NSRect base = NSZeroRect;
    [app captureCardDisplayRectForWindow:app.fixtureWindow outRect:&base];
    NSRect baseWindow = [app appKitFrameForWindowItem:app.fixtureWindow];

    // 窗口移动（尺寸不变）
    app.fixtureWindow = FixtureWindow(CGRectMake(300, 220, 800, 600));
    NSRect moved = NSZeroRect;
    Check([app captureCardDisplayRectForWindow:app.fixtureWindow outRect:&moved], @"窗口移动后映射仍有效");
    // bounds.y +160（屏幕坐标往下）→ AppKit 的 y 减少 160
    Check(fabs((NSMinX(moved) - NSMinX(base)) - 200) < 2 && fabs((NSMinY(moved) - NSMinY(base)) + 160) < 2,
          [NSString stringWithFormat:@"窗口移动后贴译区域跟着走（dx=%.0f dy=%.0f）",
           NSMinX(moved) - NSMinX(base), NSMinY(moved) - NSMinY(base)]);

    // 等比缩放（比例不变）
    app.fixtureWindow = FixtureWindow(CGRectMake(300, 220, 400, 300));
    NSRect scaled = NSZeroRect;
    Check([app captureCardDisplayRectForWindow:app.fixtureWindow outRect:&scaled], @"等比缩放后映射仍有效");
    Check(fabs(NSWidth(scaled) - NSWidth(base) / 2) < 3 && fabs(NSHeight(scaled) - NSHeight(base) / 2) < 3,
          [NSString stringWithFormat:@"等比缩放后区域同步缩小（w %.0f→%.0f）", NSWidth(base), NSWidth(scaled)]);

    // 比例变化（非等比）→ 失效
    app.fixtureWindow = FixtureWindow(CGRectMake(300, 220, 700, 300));
    Check(![app captureCardDisplayRectForWindow:app.fixtureWindow outRect:NULL], @"窗口比例变化 → 映射失效");
    Check(NSWidth(baseWindow) > 0, @"基准窗口有效");
    CGImageRelease(frame);
    CGImageRelease(scene);
    FYTestSetWindowImage(NULL);
}

#pragma mark - 7. 坐标链路：OCR 框 → 视频区域 → 屏幕坐标 → 贴译落位

static void TestCoordinateChainToLayout(void) {
    const size_t sceneW = 1000, sceneH = 700;
    MappingTestApp *app = MappingApp(CGRectMake(80, 40, 900, 640));
    FYTestCaptureCardInput *input = (FYTestCaptureCardInput *)app.captureCardInput;
    CGImageRef frame = CapturePatternImage(1920, 1080, 8080);
    // OBS 式：预览在上（y 大），控制区在下
    const CGFloat videoW = 780, videoH = videoW * 180.0 / 320.0;
    CGRect videoInScene = CGRectMake(70, sceneH - 30 - videoH, videoW, videoH);
    CGImageRef scene = WindowScene(frame, sceneW, sceneH, videoInScene, 30, 1);
    FYTestSetWindowImage(scene);
    [input testStoreFrame:frame index:1];
    NSRect viewport = NSZeroRect;
    Check([app inlinePlacementRect:&viewport reason:NULL], @"拿到视频显示区域");
    NSRect windowFrame = [app appKitFrameForWindowItem:app.fixtureWindow];
    NSRect expectedVideo = ExpectedScreenRect(windowFrame, videoInScene, sceneW, sceneH);
    Check(RectNear(viewport, expectedVideo, 14), @"视频显示区域 = 预览被画进去的位置");

    // 三个选项的 OCR 框（归一化、Vision 坐标：原点左下）：上下三行，偏画面中上部
    NSArray<NSValue *> *boxes = @[
        [NSValue valueWithRect:CGRectMake(0.30, 0.68, 0.22, 0.045)],
        [NSValue valueWithRect:CGRectMake(0.30, 0.60, 0.24, 0.045)],
        [NSValue valueWithRect:CGRectMake(0.30, 0.52, 0.20, 0.045)]
    ];
    NSMutableArray<NSValue *> *sourceFrames = [NSMutableArray array];
    NSArray<NSString *> *texts = @[@"はい", @"いいえ", @"わからない"];
    NSMutableArray<OCRTextItem *> *items = [NSMutableArray array];
    for (NSUInteger index = 0; index < boxes.count; index++) {
        OCRTextItem *item = [OCRTextItem new];
        item.text = texts[index];
        item.boundingBox = boxes[index].rectValue;
        item.blockKind = InlineBlockKindShort;
        [items addObject:item];
        NSRect source = [app appKitFrameForOCRItem:item inWindowFrame:viewport];
        [sourceFrames addObject:[NSValue valueWithRect:source]];
        // 原文框必须落在视频区域内（不是窗口下方控制区）
        Check(NSContainsRect(NSInsetRect(viewport, -1, -1), source),
              [NSString stringWithFormat:@"选项 %lu 的原文框落在视频区域内（%.0f,%.0f）",
               (unsigned long)(index + 1), NSMinX(source), NSMinY(source)]);
        Check(NSMidY(source) > NSMidY(viewport),
              [NSString stringWithFormat:@"选项 %lu 的原文框位于视频区域上半部（不在控制区）", (unsigned long)(index + 1)]);
    }

    // 交给布局引擎：译文必须贴着自己的原文，且不越出视频区域
    NSMutableArray<FYInlineLayoutRequest *> *requests = [NSMutableArray array];
    for (NSUInteger index = 0; index < items.count; index++) {
        FYInlineTextBlock *block = [FYInlineTextBlock new];
        block.text = texts[index];
        block.kind = FYInlineBlockKindShort;
        block.lineBoxes = @[[NSValue valueWithRect:items[index].boundingBox]];
        block.lineTexts = @[texts[index]];
        block.boundingBox = items[index].boundingBox;
        block.blockID = [FYInlineBlockMatcher blockIDForText:block.text lineBoxes:block.lineBoxes];
        [requests addObject:[FYInlineLayoutRequest requestWithBlock:block
                                                        translation:[NSString stringWithFormat:@"译文%lu", (unsigned long)(index + 1)]
                                                        sourceFrame:sourceFrames[index].rectValue]];
    }
    FYInlineLayoutResult *result = [[FYInlineLayoutEngine defaultEngine] layoutRequests:requests
                                                                              viewport:viewport previous:nil];
    NSMutableArray<NSValue *> *translationFrames = [NSMutableArray array];
    Check(result.placements.count == 3, @"三个选项都拿到排版结果");
    for (NSUInteger index = 0; index < result.placements.count; index++) {
        FYInlinePlacement *placement = result.placements[index];
        NSRect panel = placement.translationFrame;
        [translationFrames addObject:[NSValue valueWithRect:panel]];
        NSRect source = sourceFrames[index].rectValue;
        // 与自己的原文距离有界（短贴片：下方近邻为主，最多一行）
        CGFloat drift = MAX(0, MAX(NSMinY(source) - NSMaxY(panel), NSMinY(panel) - NSMaxY(source)));
        Check(drift <= NSHeight(source) + NSHeight(panel) + 8,
              [NSString stringWithFormat:@"选项 %lu 的译文贴着自己的原文（垂直偏移 %.0f）", (unsigned long)(index + 1), drift]);
        // 不能漂到别的选项上：与其它原文框不相交
        for (NSUInteger other = 0; other < sourceFrames.count; other++) {
            if (other == index) { continue; }
            Check(!CGRectIntersectsRect(panel, sourceFrames[other].rectValue),
                  [NSString stringWithFormat:@"选项 %lu 的译文没有盖住选项 %lu 的原文",
                   (unsigned long)(index + 1), (unsigned long)(other + 1)]);
        }
        Check(NSMinY(panel) > NSMidY(viewport) - 40,
              [NSString stringWithFormat:@"选项 %lu 的译文留在视频区域上半部（minY=%.0f，视频中线=%.0f）",
               (unsigned long)(index + 1), NSMinY(panel), NSMidY(viewport)]);
    }
    // 说明弹窗：一段很长的译文卡，必须不遮挡其他译文/原文；放不下就降级，不能压上去
    {
        FYInlineTextBlock *longBlock = [FYInlineTextBlock new];
        longBlock.text = @"ここは説明文です。主人公の状況と選択肢の意味を長く説明します。";
        longBlock.kind = FYInlineBlockKindLong;
        CGRect longBox = CGRectMake(0.26, 0.30, 0.46, 0.14);
        longBlock.boundingBox = longBox;
        longBlock.lineBoxes = @[[NSValue valueWithRect:longBox]];
        longBlock.lineTexts = @[longBlock.text];
        longBlock.blockID = [FYInlineBlockMatcher blockIDForText:longBlock.text lineBoxes:longBlock.lineBoxes];
        NSRect longSource = [app appKitFrameForOCRItem:({
            OCRTextItem *item = [OCRTextItem new];
            item.text = longBlock.text;
            item.boundingBox = longBox;
            item;
        }) inWindowFrame:viewport];
        FYInlineLayoutRequest *longRequest = [FYInlineLayoutRequest requestWithBlock:longBlock
                                                                        translation:@"这里是说明文。主人公的状况以及各个选项的含义都会在这里比较长地说明一遍，方便理解。"
                                                                        sourceFrame:longSource];
        NSMutableArray<FYInlineLayoutRequest *> *allRequests = [requests mutableCopy];
        [allRequests addObject:longRequest];
        FYInlineLayoutResult *withLong = [[FYInlineLayoutEngine defaultEngine] layoutRequests:allRequests
                                                                                    viewport:viewport previous:result];
        FYInlinePlacement *longPlacement = nil;
        for (FYInlinePlacement *placement in withLong.placements) {
            if ([placement.blockID isEqualToString:longBlock.blockID]) { longPlacement = placement; }
        }
        Check(longPlacement != nil, @"说明弹窗拿到了排版结果");
        if (longPlacement) {
            // 当前布局允许所属字段内的覆盖锚点；其它字段仍须保持零重叠。
            // 联合避让会移动已有短贴片，必须检查这一轮 withLong 的最终位置。
            BOOL degradedLong = longPlacement.mode == FYInlineDisplayModeCompactEntry ||
                                longPlacement.mode == FYInlineDisplayModeUnplaceable;
            Check(!CGRectIntersectsRect(longPlacement.translationFrame, longSource) || degradedLong ||
                  longPlacement.anchor == FYInlineAnchorOverlay,
                  @"长卡覆盖自身时使用所属字段的覆盖锚点，其它锚点不跨入原文");
            for (NSUInteger other = 0; other < requests.count; other++) {
                FYInlinePlacement *shortPlacement = [withLong placementForBlockID:result.placements[other].blockID];
                Check(shortPlacement != nil, @"联合布局保留原有选项身份");
                if (!shortPlacement) { continue; }
                BOOL overlapsOther = CGRectIntersectsRect(longPlacement.translationFrame, shortPlacement.translationFrame);
                BOOL overlapsSource = CGRectIntersectsRect(longPlacement.translationFrame, sourceFrames[other].rectValue);
                Check(!overlapsOther || longPlacement.mode == FYInlineDisplayModeCompactEntry ||
                      longPlacement.mode == FYInlineDisplayModeUnplaceable,
                      [NSString stringWithFormat:@"长卡与短译文 %lu 不重叠（mode=%ld）",
                       (unsigned long)(other + 1), (long)longPlacement.mode]);
                Check(!overlapsSource || longPlacement.mode == FYInlineDisplayModeCompactEntry ||
                      longPlacement.mode == FYInlineDisplayModeUnplaceable,
                      [NSString stringWithFormat:@"长卡没有压住选项 %lu 的原文", (unsigned long)(other + 1)]);
            }
            Check(NSContainsRect(NSInsetRect(viewport, -1, -1), longPlacement.translationFrame) ||
                  longPlacement.mode == FYInlineDisplayModeCompactEntry ||
                  longPlacement.mode == FYInlineDisplayModeUnplaceable,
                  @"长卡落在视频区域内，或明确降级（不漂到画面外）");
            [translationFrames addObject:[NSValue valueWithRect:longPlacement.translationFrame]];
        }
        // 所有译文两两不重叠
        for (NSUInteger i = 0; i < withLong.placements.count; i++) {
            for (NSUInteger j = i + 1; j < withLong.placements.count; j++) {
                FYInlinePlacement *a = withLong.placements[i];
                FYInlinePlacement *b = withLong.placements[j];
                BOOL degraded = a.mode == FYInlineDisplayModeCompactEntry || a.mode == FYInlineDisplayModeUnplaceable ||
                                b.mode == FYInlineDisplayModeCompactEntry || b.mode == FYInlineDisplayModeUnplaceable;
                Check(degraded || !CGRectIntersectsRect(a.translationFrame, b.translationFrame),
                      [NSString stringWithFormat:@"译文 %lu 与 %lu 不互相遮挡", (unsigned long)(i + 1), (unsigned long)(j + 1)]);
            }
        }
    }
    // 诊断图：窗口 + 视频边界 + 原文框 + 译文位置
    RenderMappingDiagnostics(scene, windowFrame, viewport, sourceFrames, translationFrames,
                             [gOutputDirectory stringByAppendingPathComponent:@"mapping-options-chain.png"]);
    CGImageRelease(frame);
    CGImageRelease(scene);
    FYTestSetWindowImage(NULL);
}

#pragma mark - 7b. 画面铺满窗口（整窗适配候选）与「锁到更小一份」的守卫

static void TestFullWindowPictureAndDuplicateGuard(void) {
    // ① 画面铺满窗口（只有上下黑边）：定位结果必须等于整窗等比适配的那块
    {
        const size_t sceneW = 1000, sceneH = 600;
        MappingTestApp *app = MappingApp(CGRectMake(100, 100, 1000, 600));
        FYTestCaptureCardInput *input = (FYTestCaptureCardInput *)app.captureCardInput;
        CGImageRef frame = CapturePatternImage(320, 180, 3131);
        CGFloat videoH = sceneW * 180.0 / 320.0;                 // 1000 → 562.5
        CGRect videoInScene = CGRectMake(0, (sceneH - videoH) / 2.0, sceneW, videoH);
        CGImageRef scene = WindowScene(frame, sceneW, sceneH, videoInScene, 0, 0);
        FYTestSetWindowImage(scene);
        [input testStoreFrame:frame index:1];
        Check([app autoDetectCaptureCardVideoRectForWindow:app.fixtureWindow reason:NULL], @"铺满窗口：定位成功");
        NSRect detected = NSZeroRect;
        [app captureCardDisplayRectForWindow:app.fixtureWindow outRect:&detected];
        NSRect windowFrame = [app appKitFrameForWindowItem:app.fixtureWindow];
        NSRect expected = ExpectedScreenRect(windowFrame, videoInScene, sceneW, sceneH);
        // 铺满窗口的关键性质是**尺度**：必须接近整窗宽度，而不是缩在某个角落的小块。
        // 上下黑边只占 3%，检索结果在黑边内平移几像素属于正常误差，因此按覆盖率断言。
        Check(NSWidth(detected) > NSWidth(windowFrame) * 0.95 && NSHeight(detected) > NSHeight(expected) * 0.95,
              [NSString stringWithFormat:@"铺满窗口：定位到整窗尺度（detected=%s）", NSStringFromRect(detected).UTF8String]);
        Check(CGRectIntersectsRect(detected, expected) &&
              fabs(NSMinY(detected) - NSMinY(expected)) < NSHeight(windowFrame) * 0.06,
              [NSString stringWithFormat:@"铺满窗口：结果覆盖画面区域（detected=%s expected=%s）",
               NSStringFromRect(detected).UTF8String, NSStringFromRect(expected).UTF8String]);
        CGImageRelease(frame);
        CGImageRelease(scene);
        FYTestSetWindowImage(NULL);
    }
    // ② 窗口里同时出现两份同样的画面（大份 + 角落小份）时，不能把已经对得上的映射换成更小的一份
    {
        const size_t sceneW = 1000, sceneH = 700;
        MappingTestApp *app = MappingApp(CGRectMake(60, 60, 900, 630));
        FYTestCaptureCardInput *input = (FYTestCaptureCardInput *)app.captureCardInput;
        CGImageRef frame = CapturePatternImage(320, 180, 4242);
        const CGFloat videoW = 760, videoH = videoW * 180.0 / 320.0;
        CGRect full = CGRectMake(70, sceneH - 40 - videoH, videoW, videoH);
        CGImageRef clean = WindowScene(frame, sceneW, sceneH, full, 40, 0);
        FYTestSetWindowImage(clean);
        [input testStoreFrame:frame index:1];
        Check([app autoDetectCaptureCardVideoRectForWindow:app.fixtureWindow reason:NULL], @"重复画面：先定位成功");
        NSRect good = NSZeroRect;
        [app captureCardDisplayRectForWindow:app.fixtureWindow outRect:&good];
        NSRect windowFrame = [app appKitFrameForWindowItem:app.fixtureWindow];
        NSRect expected = ExpectedScreenRect(windowFrame, full, sceneW, sceneH);
        Check(RectNear(good, expected, MAX(12, NSHeight(windowFrame) * 0.03)), @"重复画面：首个映射正确");

        // 同一场景里再加一份缩小的同样画面（模拟 OBS 预览 + 投影/缩略图）
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(NULL, sceneW, sceneH, 8, sceneW * 4, space, kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(space);
        CGContextDrawImage(ctx, CGRectMake(0, 0, sceneW, sceneH), clean);
        CGContextDrawImage(ctx, CGRectMake(20, 20, 240, 135), frame);         // 角落小份（同样内容）
        CGImageRef duplicated = CGBitmapContextCreateImage(ctx);
        CGContextRelease(ctx);
        FYTestSetWindowImage(duplicated);
        app.lastAutoLocateAttempt = nil;
        app.lastMappingValidationDate = nil;
        BOOL replaced = [app autoDetectCaptureCardVideoRectForWindow:app.fixtureWindow reason:NULL];
        NSRect after = NSZeroRect;
        [app captureCardDisplayRectForWindow:app.fixtureWindow outRect:&after];
        Check(!replaced, @"重复画面：缓存映射仍然对得上时不做重新定位");
        Check(RectNear(after, good, 6),
              [NSString stringWithFormat:@"重复画面：映射仍是那份正确的（after=%s good=%s）",
               NSStringFromRect(after).UTF8String, NSStringFromRect(good).UTF8String]);
        Check(NSWidth(after) > 240 * NSWidth(windowFrame) / sceneW * 1.5,
              @"重复画面：没有退化成角落里的那一小份");
        CGImageRelease(frame);
        CGImageRelease(clean);
        CGImageRelease(duplicated);
        FYTestSetWindowImage(NULL);
    }
}

#pragma mark - 8. 映射更新后布局缓存要一起失效

static void TestLayoutCacheResetOnMappingChange(void) {
    MappingTestApp *app = MappingApp(CGRectMake(0, 0, 800, 600));
    FYTestCaptureCardInput *input = (FYTestCaptureCardInput *)app.captureCardInput;
    CGImageRef frame = CapturePatternImage(320, 180, 1212);
    CGImageRef scene = WindowScene(frame, 800, 600, CGRectMake(40, 300, 720, 240), 40, 0);
    FYTestSetWindowImage(scene);
    [input testStoreFrame:frame index:1];
    [app autoDetectCaptureCardVideoRectForWindow:app.fixtureWindow reason:NULL];

    // 模拟已有贴译渲染结果
    FYInlineLayoutResult *fake = [FYInlineLayoutResult new];
    app.lastInlineLayoutResult = fake;
    app.lastInlineTranslationKey = @"some-identity";
    Check(app.lastInlineTranslationKey.length > 0, @"前置：已有布局缓存");
    [app storeCaptureCardMapping:NSMakeRect(100, 100, 200, 120)
                     windowFrame:[app appKitFrameForWindowItem:app.fixtureWindow]
                     videoAspect:16.0 / 9.0
                        deviceID:@"usb-video"
                          source:@"auto"
                      confidence:0.9
                     forWindowID:app.fixtureWindow.windowID];
    Check(app.lastInlineTranslationKey == nil && app.lastInlineLayoutResult == nil,
          @"写入新映射后贴译布局缓存立即失效（否则面板会停在旧坐标）");
    CGImageRelease(frame);
    CGImageRelease(scene);
    FYTestSetWindowImage(NULL);
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];
    gOutputDirectory = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : NSTemporaryDirectory();
    [[NSFileManager defaultManager] createDirectoryAtPath:gOutputDirectory withIntermediateDirectories:YES attributes:nil error:NULL];

    NSLog(@"== 1. 灰度网格朝向 ==");
    TestGridOrientation();
    NSLog(@"== 2. 顶部/中部/底部非对称摆放 ==");
    TestAutoLocateTopMiddleBottom();
    NSLog(@"== 3. OBS 式窗口（预览在上、控制区在下） ==");
    TestOBSChromeDoesNotWin();
    NSLog(@"== 4. 窗口尺寸不变、画面移动 ==");
    TestStaleMappingIsRelocated();
    NSLog(@"== 5. 旧版自动映射作废 ==");
    TestOldVersionMappingDropped();
    NSLog(@"== 6. 窗口移动/缩放/比例变化 ==");
    TestWindowMoveResizeAspect();
    NSLog(@"== 7. 坐标链路到贴译落位 ==");
    TestCoordinateChainToLayout();
    NSLog(@"== 7b. 铺满窗口 / 重复画面守卫 ==");
    TestFullWindowPictureAndDuplicateGuard();
    NSLog(@"== 8. 映射变化让布局缓存失效 ==");
    TestLayoutCacheResetOnMappingChange();

    if (gFailures == 0) {
        NSLog(@"采集卡映射回归通过：纵坐标翻转、旧映射作废、内部画面移动重定位、坐标链路与贴译落位都正确（离线合成夹具）。");
        return 0;
    }
    NSLog(@"采集卡映射回归失败：%lu 项", (unsigned long)gFailures);
    return 1;
} }
