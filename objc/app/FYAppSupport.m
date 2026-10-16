#import "FYAppSupport.h"
#import "../FYAppDiagnostics.h"

void FYInlineDebugTracePerform(NSDictionary *trace, NSDictionary *layout, void (^work)(void)) {
    FYLayoutDebugPerform(layout, ^{ FYTracePerform(trace, work); });
}

NSString *FYAppearanceColorHex(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb) { return @"#593E2B"; }
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)lround(MIN(MAX(rgb.redComponent, 0), 1) * 255),
            (int)lround(MIN(MAX(rgb.greenComponent, 0), 1) * 255),
            (int)lround(MIN(MAX(rgb.blueComponent, 0), 1) * 255)];
}

NSColor *FYAppearanceColorFromHex(NSString *hex, NSColor *fallback) {
    if (![hex isKindOfClass:NSString.class] || hex.length != 7 || ![hex hasPrefix:@"#"]) { return fallback; }
    unsigned value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:[hex substringFromIndex:1]];
    if (![scanner scanHexInt:&value] || !scanner.isAtEnd) { return fallback; }
    return [NSColor colorWithSRGBRed:((value >> 16) & 255) / 255.0
                              green:((value >> 8) & 255) / 255.0 blue:(value & 255) / 255.0 alpha:1];
}

NSColor *FYAppearanceBackdropForText(NSColor *textColor) {
    NSColor *rgb = [textColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    CGFloat brightness = rgb ? 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent +
        0.0722 * rgb.blueComponent : 0;
    return brightness > 0.58 ? FYAdventureColor(@"ink") : FYAdventureColor(@"cream");
}

// ==== 临时诊断（设 FUYI_DIAG=1 或创建 /tmp/fuyi-diag-armed 时启用）====
// 统一的诊断开关。任何会落盘的诊断行为（写日志、保存屏幕截图）都必须经过它；
// 否则正式分发版会在用户不知情的情况下，把屏幕内容写入诊断文件。
BOOL FuyiDiagEnabled(void) {
#ifdef FY_TEST_DISABLE_LEGACY_DIAGNOSTICS
    return NO; // Isolated tests must not consume another running app's global switch.
#else
    static BOOL enabled = NO;
    static NSTimeInterval expiresAt = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct stat armedInfo;
        BOOL armed = lstat("/tmp/fuyi-diag-armed", &armedInfo) == 0 &&
            S_ISREG(armedInfo.st_mode) && armedInfo.st_uid == getuid();
        BOOL byEnv = [NSProcessInfo.processInfo.environment[@"FUYI_DIAG"] isEqualToString:@"1"];
        enabled = (armed || byEnv);
        if (enabled) { expiresAt = NSProcessInfo.processInfo.systemUptime + 60.0; }
    });
    return enabled && NSProcessInfo.processInfo.systemUptime < expiresAt;
#endif
}

void FYWritePrivateDiagnosticData(NSData *data, NSString *filename, BOOL append) {
    if (!data.length) { return; }
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    int fd = open(path.fileSystemRepresentation,
                  O_WRONLY | O_CREAT | O_NOFOLLOW | (append ? O_APPEND : 0), 0600);
    if (fd < 0) { return; }
    struct stat info;
    if (fstat(fd, &info) == 0 && S_ISREG(info.st_mode) && info.st_uid == getuid()) {
        if (fchmod(fd, 0600) == 0) {
            if (!append) { ftruncate(fd, 0); }
            const uint8_t *bytes = data.bytes;
            NSUInteger remaining = data.length;
            while (remaining > 0) {
                ssize_t count = write(fd, bytes, remaining);
                if (count <= 0) { break; }
                bytes += count;
                remaining -= (NSUInteger)count;
            }
        }
    }
    close(fd);
}

void FuyiDiagLog(NSString *format, ...) {
    // 仅在显式启用时记录有限的数值诊断，文件仅对当前用户可读。
    if (!FuyiDiagEnabled()) { return; }
    static NSInteger budget = 2000;
    static NSObject *lock;
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss.SSS";
    });

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    @synchronized (lock) {
        if (!FuyiDiagEnabled() || budget <= 0) { return; }
        budget -= 1;
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], message];
        FYWritePrivateDiagnosticData([line dataUsingEncoding:NSUTF8StringEncoding], @"yiya-diag.log", YES);
    }
}
NSString *FYDiagTextLength(NSString *value) {
    return [NSString stringWithFormat:@"len:%lu", (unsigned long)value.length];
}

void FYRemoveOwnedLegacyDiagnosticFiles(void) {
#ifndef FY_TEST_DISABLE_LEGACY_DIAGNOSTICS
    const char *paths[] = {"/tmp/fuyi-diag.log", "/tmp/fuyi-last-frame.png"};
    for (NSUInteger index = 0; index < 2; index++) {
        const char *path = paths[index];
        struct stat info;
        if (lstat(path, &info) == 0 && S_ISREG(info.st_mode) && info.st_uid == getuid()) {
            unlink(path);
        }
    }
#endif
}
// ==== 诊断结束 ====




static NSString * const FYTranslationServiceRetestHint = @"请前往「翻译服务」，点击「测试翻译」重新检查当前模型服务。";

NSString *FYTranslationModelForSettings(NSDictionary *settings) {
    return FYTranslationModelFromSettings(settings);
}

FYContentTextFilterObserver FYContentFilterDiagnosticObserver(void) {
    return ^(NSString *text, CGRect box, FYContentTextFilterReason reason) {
        if (reason == FYContentTextPunctuationOnly) {
            FuyiDiagLog(@"  DROP-PUNCTUATION-ONLY <%@> w=%.3f", FYDiagTextLength(text), box.size.width);
        }
    };
}





NSString *FYTranslationFailureMessage(NSError *error, NSUInteger reasonLimit) {
    NSString *reason = error.localizedDescription ?: @"未知错误";
    // Code 204 also covers truncation and empty responses; only an explicit
    // model refusal is unrelated to the service's availability/configuration.
    BOOL refusal = error.code == 204 && [reason isEqualToString:@"翻译模型拒绝翻译这段内容。"];
    if (reasonLimit) { reason = Shorten(reason, reasonLimit); }
    return refusal ? reason : [NSString stringWithFormat:@"%@\n%@", FYTranslationServiceRetestHint, reason];
}

double SimilarityRatio(NSString *left, NSString *right) {
    return [FYContentRouter similarityRatio:left comparedTo:right];
}

BOOL ContainsJapaneseText(NSString *value) {
    return [FYContentRouter containsJapaneseKana:value];
}

NSString *SourceLanguageLabel(NSInteger segment) {
    return segment == 1 ? @"英文" : @"日文";
}

// 排版结果：新建面板和原地更新已有面板共用这一份计算，避免两套逻辑走偏


// 采集卡画面区域校准层：盖在目标窗口上拖框选出真正的视频显示区域。
// 这是**测量**（现场框选）而不是把整窗等比猜测当映射。

@implementation FYCaptureCalibrationView {
    NSPoint _anchor;
    BOOL _dragging;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)drawRect:(NSRect)dirty {
    [[NSColor colorWithCalibratedWhite:0 alpha:0.45] setFill];
    NSRectFill(self.bounds);
    NSRect selection = NSIntersectionRect(self.selectionRect, self.bounds);
    if (!NSIsEmptyRect(selection)) {
        [[NSColor clearColor] setFill];
        NSRectFillUsingOperation(selection, NSCompositingOperationCopy);
        [[NSColor colorWithSRGBRed:0.98 green:0.72 blue:0.30 alpha:1] setStroke];
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSInsetRect(selection, 1, 1)];
        path.lineWidth = 2;
        [path stroke];
    }
    // 提示画在顶部深色带上：选中的区域是"挖空"的（露出真实画面），白字直接画在上面会看不清。
    NSRect band = NSMakeRect(0, NSHeight(self.bounds) - 46, NSWidth(self.bounds), 46);
    [[NSColor colorWithCalibratedWhite:0 alpha:0.72] setFill];
    NSRectFill(band);
    NSDictionary *attributes = @{NSFontAttributeName: FYUIFont(15, NSFontWeightSemibold),
                                 NSForegroundColorAttributeName: NSColor.whiteColor};
    [@"拖出采集卡画面在窗口里显示的区域 · 松开完成 · Esc 取消"
        drawAtPoint:NSMakePoint(24, NSHeight(self.bounds) - 33) withAttributes:attributes];
}
- (void)mouseDown:(NSEvent *)event {
    _anchor = [self convertPoint:event.locationInWindow fromView:nil];
    _dragging = YES;
    self.selectionRect = NSZeroRect;
    [self setNeedsDisplay:YES];
}
- (void)mouseDragged:(NSEvent *)event {
    if (!_dragging) { return; }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    self.selectionRect = NSMakeRect(MIN(_anchor.x, point.x), MIN(_anchor.y, point.y),
                                    fabs(point.x - _anchor.x), fabs(point.y - _anchor.y));
    [self setNeedsDisplay:YES];
}
- (void)mouseUp:(NSEvent *)event {
    if (!_dragging) { return; }
    _dragging = NO;
    [self mouseDragged:event];
    NSRect inView = NSIntersectionRect(self.selectionRect, self.bounds);
    if (NSWidth(inView) < 2 || NSHeight(inView) < 2) { if (self.onCancel) { self.onCancel(); } return; }
    NSRect inWindow = [self convertRect:inView toView:nil];
    NSRect onScreen = [self.window convertRectToScreen:inWindow];
    if (self.onFinish) { self.onFinish(onScreen); }
}
@end

// 点选长卡片时生成的不可变学习快照：绑定输入源、采集代次与块内容。



// One physical long-text batch may serve successive confirmed UI snapshots.
// The current snapshot owns delivery; the batch owns only its source keys.




// Vision boxes are normalized, with a bottom-left origin. These are text-only
// diagnostics of existing OCR results; this helper never obtains an image.
NSArray *FYTraceOCRLines(NSArray<OCRTextItem *> *items) {
    NSMutableArray *lines = [NSMutableArray array];
    for (OCRTextItem *item in items) {
        if (lines.count >= 101) { break; } // writer caps at 100 and marks truncation
        CGRect b = item.boundingBox;
        [lines addObject:@{@"text": item.text ?: @"", @"x": @(b.origin.x), @"y": @(b.origin.y),
                           @"w": @(b.size.width), @"h": @(b.size.height)}];
    }
    return lines;
}

// Compatibility adapters for existing fixture entry points; policy lives in FYOCRManager.
static NSArray<OCRTextItem *> *ResolveOverlappingOCRItems(NSArray<OCRTextItem *> *items) {
    return [FYOCRManager resolveOverlappingItems:items];
}

NSArray<OCRTextItem *> *MergeRefinedOCRItems(NSArray<OCRTextItem *> *coarse,
                                                  NSArray<OCRTextItem *> *refined) {
    return [FYOCRManager mergeCoarseItems:coarse refinedItems:refined];
}

NSInteger const ContentModeDialogue = FYContentModeDialogue;
NSInteger const ContentModeUI = FYContentModeUI;

// Compatibility fixture entry points; UI-frame classification is a pure OCR policy.
BOOL __attribute__((unused)) TextHitsUIToken(NSString *text) { return [FYContentRouter textHitsUIToken:text]; }
NSUInteger __attribute__((unused)) UITokenHitCount(NSArray<OCRTextItem *> *blocks) { return [FYContentRouter UITokenHitCount:blocks]; }
BOOL __attribute__((unused)) IsFuriganaNearLargerLine(OCRTextItem *small, NSArray<OCRTextItem *> *blocks) { return [FYContentRouter isFurigana:small nearLargerLineInItems:blocks]; }
BOOL LooksLikeUIFrame(NSArray<OCRTextItem *> *blocks) { return [FYContentRouter looksLikeUIFrame:blocks]; }

// Dialogue policy compatibility seams; implementations live in FYOCRManager.
static BOOL __attribute__((unused)) IsFormedTextLine(OCRTextItem *block) { return [FYContentRouter isFormedTextLine:block]; }
static BOOL __attribute__((unused)) IsShortDialogueAnchorCandidate(OCRTextItem *block) { return [FYContentRouter isShortDialogueAnchor:block]; }
BOOL __attribute__((unused)) IsCornerHelpButton(OCRTextItem *block) { return [FYContentRouter isCornerHelpButton:block]; }
static BOOL __attribute__((unused)) IsSingleLineDialogue(OCRTextItem *block) { return [FYContentRouter isSingleLineDialogue:block]; }
static BOOL __attribute__((unused)) IsDialogueAnchorCandidate(OCRTextItem *block) { return [FYContentRouter isDialogueAnchor:block]; }
static BOOL __attribute__((unused)) IsUnpunctuatedSingleLineDialogue(NSString *text, CGRect box) { return [FYContentRouter isUnpunctuatedSingleLineDialogue:text box:box]; }

// Compatibility adapters; caller supplies snapshots, OCR module owns exclusion policy.
BOOL __attribute__((unused)) IsOwnOverlayText(NSString *raw) {
    return [FYOCRManager isOwnOverlayText:raw];
}

NSArray<OCRTextItem *> *OCRItemsExcludingOwnOverlay(NSArray<OCRTextItem *> *items,
                                                           NSSet<NSString *> *renderedTexts) {
    return [FYOCRManager itemsExcludingOwnOverlay:items renderedTexts:renderedTexts];
}

NSSet<NSString *> *RenderedTranslationSet(NSString *captionText, NSDictionary *inlineCache) {
    return [FYOCRManager renderedTranslationSetForCaption:captionText inlineCache:inlineCache];
}

NSString *__attribute__((unused)) DialogueTextWithoutTrailingButton(NSString *text) {
    return [FYContentRouter dialogueTextWithoutTrailingButton:text];
}

NSArray<OCRTextItem *> *SubtitleBandItemsFromBlocks(NSArray<OCRTextItem *> *blocks) {
    return [FYContentRouter subtitleBandItems:blocks];
}

// Speaker and dialogue/options compatibility seams; pure policy in OCR module.
static BOOL __attribute__((unused)) LooksLikeSpeakerNameText(NSString *raw) { return [FYContentRouter looksLikeSpeakerName:raw]; }
static BOOL __attribute__((unused)) LooksLikeSpeakerFuriganaText(NSString *raw) { return [FYContentRouter looksLikeSpeakerFurigana:raw]; }
static BOOL __attribute__((unused)) LooksLikeSpeakerLabelCluster(NSArray<OCRTextItem *> *cluster) { return [FYContentRouter looksLikeSpeakerLabelCluster:cluster]; }
static BOOL __attribute__((unused)) IsSpeakerLabelItem(OCRTextItem *item, NSArray<OCRTextItem *> *pool) { return [FYContentRouter isSpeakerLabelItem:item inPool:pool]; }
BOOL __attribute__((unused)) DialogueFrameIsSpeakerLabelOnly(NSArray<NSString *> *lines) { return [FYContentRouter dialogueFrameIsSpeakerLabelOnly:lines]; }
void SplitDialogueAndOptionsFromItems(NSArray<OCRTextItem *> *band,
                                     NSArray<OCRTextItem *> *allBlocks,
                                     NSMutableArray<OCRTextItem *> *outDialogue,
                                     NSMutableArray<OCRTextItem *> *outOptions) {
    [FYContentRouter splitDialogueAndOptions:band allBlocks:allBlocks dialogue:outDialogue options:outOptions];
}

typedef FYOCRPixelBuffer GrayBuffer;
static GrayBuffer GrayBufferFromImage(CGImageRef image) { return FYCreateOCRPixelBuffer(image); }
static void GrayBufferRelease(GrayBuffer *buffer) { FYReleaseOCRPixelBuffer(buffer); }

// Legacy pixel-policy entry points; modal enable/disable remains in coordinator.
static BOOL DetectBrightContentRegion(const unsigned char *pixels, size_t width, size_t height,
                                     size_t bytesPerRow, CGRect *outNormalizedRect, BOOL *outDimmedColumns,
                                     const CGRect *exclusions, size_t exclusionCount) {
    return FYDetectBrightOCRContentRegion(pixels, width, height, bytesPerRow,
                                         outNormalizedRect, outDimmedColumns, exclusions, exclusionCount);
}
BOOL BlockSitsOnBrightBackdrop(OCRTextItem *block, const unsigned char *pixels,
                              size_t width, size_t height, size_t bytesPerRow) {
    return FYOCRBlockSitsOnBrightBackdrop(block, pixels, width, height, bytesPerRow);
}

NSInteger DetectContentModeForBlocks(NSArray<OCRTextItem *> *blocks, NSInteger fallbackSegment) {
    return [FYContentRouter contentModeForItems:blocks fallback:fallbackSegment];
}





// Window geometry drives the layout canvas. Its size constraints are internal
// to that canvas, so page fitting cannot become the native window's min/max.






@implementation FYRegionSelectionPanel
- (BOOL)canBecomeKeyWindow { return YES; }
@end



@implementation RegionSelectionView

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithWhite:0 alpha:0.12] setFill];
    NSRectFill(self.bounds);

    CGFloat size = MIN((CGFloat)56, MAX((CGFloat)14, self.helpFontSize));
    NSColor *ink = self.helpTextColor ?: FYAdventureColor(@"ink");
    NSString *help = @"在游戏画面内拖动框选 · Esc 取消";
    while (size > 14 && [help sizeWithAttributes:@{NSFontAttributeName: FYUIFont(size, NSFontWeightBold)}].width > NSWidth(self.bounds) - 40) {
        size -= 1;
    }
    NSDictionary *attributes = @{
        NSFontAttributeName: FYUIFont(size, NSFontWeightBold),
        NSForegroundColorAttributeName: ink
    };
    NSSize helpSize = [help sizeWithAttributes:attributes];
    NSRect helpFrame = NSMakeRect(MAX((CGFloat)8, (NSWidth(self.bounds) - helpSize.width) / 2.0 - 12),
        8, MIN(NSWidth(self.bounds) - 16, helpSize.width + 24), helpSize.height + 16);
    [[FYAppearanceBackdropForText(ink) colorWithAlphaComponent:0.96] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:helpFrame xRadius:9 yRadius:9] fill];
    [help drawAtPoint:NSMakePoint(NSMinX(helpFrame) + 12, NSMinY(helpFrame) + 8) withAttributes:attributes];

    if (self.selectionRect.size.width <= 0 || self.selectionRect.size.height <= 0) {
        return;
    }

    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.selectionRect xRadius:8 yRadius:8];
    [[FYAdventureColor(@"leaf") colorWithAlphaComponent:0.18] setFill];
    [path fill];
    [ink setStroke];
    path.lineWidth = 4;
    [path stroke];

    NSString *sizeText = [NSString stringWithFormat:@"%.0f x %.0f", self.selectionRect.size.width, self.selectionRect.size.height];
    NSDictionary *sizeAttributes = @{
        NSFontAttributeName: FYUIFont(MAX((CGFloat)12, size * 0.65), NSFontWeightBold),
        NSForegroundColorAttributeName: ink
    };
    [sizeText drawAtPoint:NSMakePoint(NSMinX(self.selectionRect) + 10, NSMinY(self.selectionRect) + 10) withAttributes:sizeAttributes];
}

- (void)mouseDown:(NSEvent *)event {
    self.startPoint = [self convertPoint:event.locationInWindow fromView:nil];
    self.selectionRect = CGRectMake(self.startPoint.x, self.startPoint.y, 0, 0);
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat x = MIN(self.startPoint.x, point.x);
    CGFloat y = MIN(self.startPoint.y, point.y);
    CGFloat width = fabs(point.x - self.startPoint.x);
    CGFloat height = fabs(point.y - self.startPoint.y);
    self.selectionRect = CGRectIntersection(CGRectMake(x, y, width, height), self.bounds);
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (self.completion) {
        BOOL tooSmall = self.selectionRect.size.width < 24 || self.selectionRect.size.height < 24;
        self.completion(self.selectionRect, self.bounds.size, tooSmall);
    }
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) {
        if (self.completion) {
            self.completion(CGRectZero, self.bounds.size, YES);
        }
    } else {
        [super keyDown:event];
    }
}

@end
