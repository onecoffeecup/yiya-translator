#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <Vision/Vision.h>
#import "learning/FYLearningModels.h"
#import "learning/FYLearningStore.h"
#import "learning/FYLearningAnalyzer.h"
#import "learning/FYJapaneseTokenizer.h"
#import "learning/FYGrammarCatalog.h"
#import "learning/FYLearningCoordinator.h"
#import "learning/FYLearningViews.h"
#import "learning/FYReferenceDictionary.h"
#import "learning/FYSavedWordReferenceView.h"
#import "FYAppDiagnostics.h"
#import "FYTranslationTrace.h"
#import "FYCaptureCardInput.h"
#import "FYInlineLayout.h"
#import "learning/FYStudyChatSession.h"
#import "learning/FYStudyChatView.h"
#import "learning/FYStudyOverlayPanel.h"
#import "learning/FYGlobalShortcuts.h"

static NSString *const SettingsKey = @"LiveCaptionTranslator.settings.v1";

// ==== 临时诊断（设 FUYI_DIAG=1 或创建 /tmp/fuyi-diag-armed 时启用）====
// 统一的诊断开关。任何会落盘的诊断行为（写日志、保存屏幕截图）都必须经过它；
// 否则正式分发版会在用户不知情的情况下，把屏幕内容写到 /tmp 里。
static BOOL FuyiDiagEnabled(void) {
    static BOOL enabled = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BOOL armed = [[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/fuyi-diag-armed"];
        BOOL byEnv = [NSProcessInfo.processInfo.environment[@"FUYI_DIAG"] isEqualToString:@"1"];
        enabled = (armed || byEnv);
    });
    return enabled;
}

static void FuyiDiagLog(NSString *format, ...) {
    // 自动记录：只要 /tmp/fuyi-diag-armed 存在就写日志，写满 400 行自动停止并删除该文件。
    // 这样不需要用户设置任何环境变量。
    static NSInteger budget = -1;
    static NSString *path = @"/tmp/fuyi-diag.log";
    if (budget < 0) {
        // 预算原来只有 400 行；现在每轮要写 6~8 行，约 40 秒就写满停止 ——
        // 用户走到新界面时早就没记录了，多次排查都因此拿不到数据。放到 40000 行。
        budget = FuyiDiagEnabled() ? 40000 : 0;
    }
    if (budget <= 0) { return; }
    budget -= 1;
    if (budget == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:@"/tmp/fuyi-diag-armed" error:NULL];
    }

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    static NSDateFormatter *formatter = nil;
    if (!formatter) {
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss.SSS";
    }
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], message];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}
// ==== 诊断结束 ====


static NSString *Trim(NSString *value) {
    if (!value) { return @""; }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *StringFromJSONValue(id value) {
    if (![value isKindOfClass:NSString.class]) { return @""; }
    return (NSString *)value;
}

static NSString *NormalizeForComparison(NSString *value) {
    NSString *trimmed = Trim(value);
    NSMutableString *result = [NSMutableString stringWithCapacity:trimmed.length];
    NSCharacterSet *spaces = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    for (NSUInteger index = 0; index < trimmed.length; index++) {
        unichar character = [trimmed characterAtIndex:index];
        if (character == 0x3000 || [spaces characterIsMember:character]) {
            continue;
        }
        [result appendFormat:@"%C", character];
    }

    return result;
}

static NSString *Shorten(NSString *value, NSUInteger limit) {
    NSString *trimmed = Trim(value);
    if (trimmed.length <= limit) { return trimmed; }
    return [[trimmed substringToIndex:limit] stringByAppendingString:@"..."];
}

static NSUInteger LevenshteinDistance(NSString *left, NSString *right) {
    NSUInteger leftLength = left.length;
    NSUInteger rightLength = right.length;
    if (leftLength == 0) { return rightLength; }
    if (rightLength == 0) { return leftLength; }

    NSMutableArray<NSNumber *> *previous = [NSMutableArray arrayWithCapacity:rightLength + 1];
    NSMutableArray<NSNumber *> *current = [NSMutableArray arrayWithCapacity:rightLength + 1];
    for (NSUInteger column = 0; column <= rightLength; column++) {
        [previous addObject:@(column)];
        [current addObject:@0];
    }

    for (NSUInteger row = 1; row <= leftLength; row++) {
        current[0] = @(row);
        unichar leftCharacter = [left characterAtIndex:row - 1];
        for (NSUInteger column = 1; column <= rightLength; column++) {
            unichar rightCharacter = [right characterAtIndex:column - 1];
            NSUInteger cost = leftCharacter == rightCharacter ? 0 : 1;
            NSUInteger deletion = previous[column].unsignedIntegerValue + 1;
            NSUInteger insertion = current[column - 1].unsignedIntegerValue + 1;
            NSUInteger substitution = previous[column - 1].unsignedIntegerValue + cost;
            current[column] = @(MIN(MIN(deletion, insertion), substitution));
        }
        NSMutableArray<NSNumber *> *swap = previous;
        previous = current;
        current = swap;
    }

    return previous[rightLength].unsignedIntegerValue;
}

static double SimilarityRatio(NSString *left, NSString *right) {
    NSUInteger maxLength = MAX(left.length, right.length);
    if (maxLength == 0) { return 1.0; }
    NSUInteger distance = LevenshteinDistance(left, right);
    return 1.0 - ((double)distance / (double)maxLength);
}

static BOOL ContainsJapaneseText(NSString *value) {
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        if ((character >= 0x3040 && character <= 0x30ff) || (character >= 0x31f0 && character <= 0x31ff)) {
            return YES;
        }
    }
    return NO;
}

static NSString *SourceLanguageLabel(NSInteger segment) {
    return segment == 1 ? @"英文" : @"日文";
}

// 排版结果：新建面板和原地更新已有面板共用这一份计算，避免两套逻辑走偏
typedef struct {
    NSRect frame;
    NSRect labelFrame;
    NSFont *font;
    CGFloat cornerRadius;
} InlinePanelLayout;

@interface WindowItem : NSObject
@property(nonatomic) uint32_t windowID;
@property(nonatomic, copy) NSString *displayName;
@property(nonatomic) CGRect bounds;
@end

@implementation WindowItem
@end

// 贴译块分类：短条目保持穿透小贴片；连续正文用可点击的学习大卡。
typedef NS_ENUM(NSInteger, InlineBlockKind) {
    InlineBlockKindShort = 0,
    InlineBlockKindLong = 1,
};

@interface OCRTextItem : NSObject
@property(nonatomic, copy) NSString *text;
@property(nonatomic) CGRect boundingBox;
@property(nonatomic) CGRect lastLineBox;
// 合并前保留每行原始文本与矩形，供分组、分类和快照诊断使用。
@property(nonatomic, copy) NSArray<NSString *> *lineTexts;
@property(nonatomic, copy) NSArray<NSValue *> *lineBoxes;
@property(nonatomic) NSInteger lineCount;
@property(nonatomic) InlineBlockKind blockKind;
// 识别置信度与分组把握程度：布局只在诊断/排序里用，不拿来当几何证据。
@property(nonatomic) CGFloat confidence;
@property(nonatomic) CGFloat groupingConfidence;
// 分组器给出的块身份（与 inlineBlockIdentityForItem: 同格式），用于跨帧身份稳定。
@property(nonatomic, copy) NSString *sourceBlockID;
@end

@implementation OCRTextItem
@end

// 长译文卡：标题栏可拖动整卡；正文区域用于滚动与点击打开学习。
// 拖动与点击必须分开：标题栏按下即进入窗口拖动；正文按下后位移超过阈值就不再算点击。
@interface FYInlineLongCardView : NSView
@property(nonatomic, copy) void (^onClick)(void);
@property(nonatomic, copy) void (^onHover)(BOOL inside);
/// 拖动开始/结束：开始用于占住拖动状态（避免 Option 松开把面板变回穿透），结束用于记录新偏移。
@property(nonatomic, copy) void (^onDragBegan)(void);
@property(nonatomic, copy) void (^onDragEnded)(void);
// 当前是否展示了「已选中」标识（用于判断就地更新时要不要重建内容）。
@property(nonatomic) BOOL showsSelectedBadge;
// 紧凑入口（空间放不下可读正文时）：点击展开完整阅读卡，而不是生成细条。
@property(nonatomic) BOOL compactEntry;
// 标题栏高度（flipped 坐标，y < 该值算标题栏）；默认 55。
@property(nonatomic) CGFloat titleBarHeight;
// 布局器给出的稳定块身份（点击/选中/学习快照都用它）。
@property(nonatomic, copy) NSString *stableBlockID;
// 测试/无窗口环境下关闭真实窗口拖动，只走判定逻辑。
@property(nonatomic) BOOL windowDragEnabled;
@property(nonatomic) NSPoint pressPoint;
@property(nonatomic) BOOL pressMovedBeyondThreshold;
- (BOOL)pointIsInTitleBar:(NSPoint)localPoint;
@end
@implementation FYInlineLongCardView
- (BOOL)isFlipped { return YES; }
// 命中测试直接返回卡片本身：内部文本不会吞掉「打开学习」的点击。
- (NSView *)hitTest:(NSPoint)point {
    if (self.hidden) { return nil; }
    NSPoint local = [self convertPoint:point fromView:self.superview];
    return NSPointInRect(local, self.bounds) ? self : nil;
}
// 滚轮仍交给内部滚动视图，长译文可以滚动。
- (void)scrollWheel:(NSEvent *)event {
    for (NSView *child in self.subviews) {
        if ([child isKindOfClass:NSScrollView.class]) { [child scrollWheel:event]; return; }
    }
    [super scrollWheel:event];
}
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) { _titleBarHeight = 55; _windowDragEnabled = YES; }
    return self;
}
// 标题栏：内边距 + 标题带（flipped 坐标下 y 小的一侧）。
- (BOOL)pointIsInTitleBar:(NSPoint)localPoint {
    return localPoint.y >= 0 && localPoint.y <= self.titleBarHeight;
}
- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    self.pressPoint = point;
    self.pressMovedBeyondThreshold = NO;
    if ([self pointIsInTitleBar:point]) {
        // 标题栏按下 = 拖动整卡（AppKit 原生拖动循环，松手才返回）。
        if (self.onDragBegan) { self.onDragBegan(); }
        if (self.windowDragEnabled && self.window) { [self.window performWindowDragWithEvent:event]; }
        if (self.onDragEnded) { self.onDragEnded(); }
        return;
    }
    // 正文：等 mouseUp 再决定是点击（打开学习）还是拖动。
}
- (void)mouseDragged:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat distance = hypot(point.x - self.pressPoint.x, point.y - self.pressPoint.y);
    if (distance > 4.0) { self.pressMovedBeyondThreshold = YES; }
}
- (void)mouseUp:(NSEvent *)event {
    if (self.pressMovedBeyondThreshold) { return; }   // 拖动结束不触发学习
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if ([self pointIsInTitleBar:point]) { return; }
    if (self.onClick) { self.onClick(); }
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas.copy) { [self removeTrackingArea:area]; }
    NSTrackingArea *tracking = [[NSTrackingArea alloc] initWithRect:self.bounds options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect) owner:self userInfo:nil];
    [self addTrackingArea:tracking];
}
- (void)mouseEntered:(NSEvent *)event { if (self.onHover) { self.onHover(YES); } }
- (void)mouseExited:(NSEvent *)event { if (self.onHover) { self.onHover(NO); } }
@end

// 短贴片：平时鼠标穿透（窗口 ignoresMouseEvents=YES）；
// 按住 Option 时窗口改为可交互，这里再按下即拖动，并给出可拖动反馈（边框加粗）。
@interface FYInlinePatchView : NSView
@property(nonatomic, copy) void (^onDragBegan)(void);
@property(nonatomic, copy) void (^onDragEnded)(void);
@property(nonatomic) BOOL dragEnabled;
@property(nonatomic) BOOL showsDragHint;
@property(nonatomic) BOOL windowDragEnabled;
@end
@implementation FYInlinePatchView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) { _windowDragEnabled = YES; }
    return self;
}
- (void)setShowsDragHint:(BOOL)showsDragHint {
    _showsDragHint = showsDragHint;
    // 反馈：边框加粗 + 更深的描边色（不改背景不透明度，也不淡化文字）。
    self.layer.borderWidth = showsDragHint ? 2.5 : 1.5;
    self.layer.borderColor = (showsDragHint ? FYAdventureColor(@"ink") : FYAdventureColor(@"line")).CGColor;
    self.toolTip = showsDragHint ? @"按住 Option 拖动可调整贴译位置" : nil;
}
- (void)mouseDown:(NSEvent *)event {
    if (!self.dragEnabled) { return; }
    if (self.onDragBegan) { self.onDragBegan(); }
    if (self.windowDragEnabled && self.window) { [self.window performWindowDragWithEvent:event]; }
    if (self.onDragEnded) { self.onDragEnded(); }
}
@end

// 采集卡画面区域校准层：盖在目标窗口上拖框选出真正的视频显示区域。
// 这是**测量**（现场框选）而不是把整窗等比猜测当映射。
@interface FYCaptureCalibrationView : NSView
@property(nonatomic, copy) void (^onFinish)(NSRect screenRect);
@property(nonatomic, copy) void (^onCancel)(void);
@property(nonatomic) NSRect selectionRect;
@end
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
@interface FYInlineBlockSnapshot : NSObject
@property(nonatomic, copy) NSString *blockID;
@property(nonatomic, copy) NSString *sourceText;
@property(nonatomic, copy) NSString *translation;
@property(nonatomic, copy) NSArray<NSValue *> *lineBoxes;
@property(nonatomic) NSInteger inputSource;
@property(nonatomic) NSUInteger inputEpoch;
@property(nonatomic, copy) NSString *sentenceID;
@property(nonatomic) NSInteger version;
@end
@implementation FYInlineBlockSnapshot
@end

// Vision boxes are normalized, with a bottom-left origin. These are text-only
// diagnostics of existing OCR results; this helper never obtains an image.
static NSArray *FYTraceOCRLines(NSArray<OCRTextItem *> *items) {
    NSMutableArray *lines = [NSMutableArray array];
    for (OCRTextItem *item in items) {
        if (lines.count >= 101) { break; } // writer caps at 100 and marks truncation
        CGRect b = item.boundingBox;
        [lines addObject:@{@"text": item.text ?: @"", @"x": @(b.origin.x), @"y": @(b.origin.y),
                           @"w": @(b.size.width), @"h": @(b.size.height)}];
    }
    return lines;
}

static NSArray<OCRTextItem *> *MergeRefinedOCRItems(NSArray<OCRTextItem *> *coarse,
                                                  NSArray<OCRTextItem *> *refined) {
    if (!refined.count) { return coarse ?: @[]; }
    NSMutableArray<OCRTextItem *> *merged = [refined mutableCopy];
    for (OCRTextItem *original in coarse) {
        BOOL replaced = NO;
        for (OCRTextItem *better in refined) {
            CGRect a = original.boundingBox, b = better.boundingBox;
            CGFloat overlapY = MIN(CGRectGetMaxY(a), CGRectGetMaxY(b)) - MAX(CGRectGetMinY(a), CGRectGetMinY(b));
            CGFloat overlapX = MIN(CGRectGetMaxX(a), CGRectGetMaxX(b)) - MAX(CGRectGetMinX(a), CGRectGetMinX(b));
            // Match geometry from the SAME image, not text: a corrected word
            // replaces its coarse read, while an entirely missed line survives.
            if (b.size.height >= a.size.height * 0.6 &&
                overlapY > MIN(a.size.height,b.size.height) * 0.45 && overlapX > 0) {
                replaced = YES; break;
            }
        }
        if (!replaced) { [merged addObject:original]; }
    }
    [merged sortUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) {
        CGFloat delta = CGRectGetMaxY(left.boundingBox) - CGRectGetMaxY(right.boundingBox);
        if (fabs(delta) > 0.025) { return delta > 0 ? NSOrderedAscending : NSOrderedDescending; }
        if (left.boundingBox.origin.x < right.boundingBox.origin.x) { return NSOrderedAscending; }
        if (left.boundingBox.origin.x > right.boundingBox.origin.x) { return NSOrderedDescending; }
        return NSOrderedSame;
    }];
    return merged;
}

static NSInteger const ContentModeDialogue = 0;
static NSInteger const ContentModeUI = 1;

// 判定“这一帧看起来像功能界面”：小按钮、菜单词、密集短文本、贴边文字
// 画面里出现几个游戏 UI 特有的按钮/菜单词？
// 这是区分“功能 UI”和“剧情对白”最可靠的单一信号 ——
// 新闻、列表、菜单页一定带「戻る / 詳細 / メニュー」这类词，对白框不会。
//
// 匹配必须精确：早期用 containsString 会误判 ——
// 日文那边的 "River Books" 会命中 "ok"，对白 "これでプレゼントはOK。" 也会命中 "ok"。
static BOOL TextHitsUIToken(NSString *text) {
    NSString *normalized = NormalizeForComparison(text);
    if (normalized.length == 0) { return NO; }
    NSString *lower = normalized.lowercaseString;

    // 日文按钮词：整条相等，或者出现在开头（「詳細を見る」「戻る」这类）
    NSArray<NSString *> *japaneseTokens = @[@"戻る", @"戻", @"閉じる", @"詳細", @"次へ",
                                            @"決定", @"設定", @"メニュー", @"スキップ"];
    for (NSString *token in japaneseTokens) {
        if ([normalized isEqualToString:token] || [normalized hasPrefix:token]) { return YES; }
    }

    // 拉丁词：必须是独立词，不能在别的单词里（避免 "Books" → "ok"）
    NSArray<NSString *> *latinTokens = @[@"back", @"close", @"menu", @"next", @"ok",
                                         @"cancel", @"skip", @"setting", @"settings", @"web"];
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    for (NSString *token in latinTokens) {
        NSRange searchRange = NSMakeRange(0, lower.length);
        while (searchRange.length > 0) {
            NSRange found = [lower rangeOfString:token options:0 range:searchRange];
            if (found.location == NSNotFound) { break; }
            BOOL leftFree = (found.location == 0) ||
                            ![letters characterIsMember:[lower characterAtIndex:found.location - 1]];
            NSUInteger after = found.location + found.length;
            BOOL rightFree = (after >= lower.length) ||
                             ![letters characterIsMember:[lower characterAtIndex:after]];
            if (leftFree && rightFree) { return YES; }
            NSUInteger next = found.location + found.length;
            if (next >= lower.length) { break; }
            searchRange = NSMakeRange(next, lower.length - next);
        }
    }
    return NO;
}

static NSUInteger UITokenHitCount(NSArray<OCRTextItem *> *blocks) {
    NSUInteger tokenHitCount = 0;
    for (OCRTextItem *block in blocks) {
        if (TextHitsUIToken(block.text)) { tokenHitCount += 1; }
    }
    return tokenHitCount;
}

static BOOL IsFuriganaNearLargerLine(OCRTextItem *small, NSArray<OCRTextItem *> *blocks) {
    CGRect box = small.boundingBox;
    NSString *text = NormalizeForComparison(small.text);
    if (text.length < 2 || box.size.width > 0.14 || box.size.height > 0.035) { return NO; }
    NSUInteger kanaCount = 0;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if ((character >= 0x3040 && character <= 0x30ff) ||
            (character >= 0x31f0 && character <= 0x31ff)) { kanaCount += 1; }
    }
    if (kanaCount * 4 < text.length * 3) { return NO; }
    for (OCRTextItem *larger in blocks) {
        if (larger == small) { continue; }
        CGRect parent = larger.boundingBox;
        if (parent.size.width < box.size.width * 1.6 || parent.size.height < box.size.height * 1.5) { continue; }
        if (CGRectGetMidY(box) <= CGRectGetMidY(parent) || CGRectGetMidY(box) - CGRectGetMaxY(parent) > 0.05) { continue; }
        CGFloat overlap = MIN(CGRectGetMaxX(box), CGRectGetMaxX(parent)) - MAX(CGRectGetMinX(box), CGRectGetMinX(parent));
        if (overlap >= box.size.width * 0.65) { return YES; }
    }
    return NO;
}

static BOOL LooksLikeUIFrame(NSArray<OCRTextItem *> *blocks) {
    NSUInteger smallBoxCount = 0;
    NSUInteger edgeCount = 0;
    NSUInteger wideLineCount = 0;
    NSUInteger textBlockCount = 0;
    CGFloat totalWidth = 0;
    NSUInteger tokenHitCount = UITokenHitCount(blocks);

    for (OCRTextItem *block in blocks) {
        NSString *normalized = NormalizeForComparison(block.text);
        if (normalized.length == 0) { continue; }
        textBlockCount += 1;
        totalWidth += block.boundingBox.size.width;

        BOOL smallBox = normalized.length <= 8 && block.boundingBox.size.height < 0.036 &&
            block.boundingBox.size.width < 0.20 && !IsFuriganaNearLargerLine(block, blocks);
        if (smallBox) { smallBoxCount += 1; }
        if (block.boundingBox.size.width >= 0.32) { wideLineCount += 1; }

        BOOL nearEdge = block.boundingBox.origin.y < 0.10 || CGRectGetMaxY(block.boundingBox) > 0.90;
        if (nearEdge && normalized.length <= 12) { edgeCount += 1; }
    }

    if (tokenHitCount >= 2) { return YES; }
    if (tokenHitCount >= 1 && (smallBoxCount >= 2 || edgeCount >= 3)) { return YES; }
    if (smallBoxCount >= 4) { return YES; }
    if (blocks.count >= 5 && smallBoxCount >= 3) { return YES; }
    // 贴边文字很多、且完全没有宽行 —— 但这必须**同时**带上 UI 按钮词才算数。
    // 单独用贴边信号太弱：对白游戏的字幕框本身就贴着画面底部，
    // 实测城镇对白帧 edge=4（其中还包含我们自己浮窗的文字），会把对白误判成 UI。
    if (edgeCount >= 4 && wideLineCount == 0 && tokenHitCount >= 1) { return YES; }

    // 文本密集 = 列表 / 菜单 / 新闻页。
    // 判据用“实质行数”（够宽、够长的行），实测能干净分开：
    //   新闻列表页 8 行，对白帧 3 行。纯招牌画面只有 1~2 行。
    // 不用“平均宽度”，因为街景招牌会把平均值拉低，反而误伤对白帧。
    NSUInteger substantialLineCount = 0;
    for (OCRTextItem *block in blocks) {
        NSString *normalized = NormalizeForComparison(block.text);
        if (normalized.length == 0) { continue; }
        CGFloat width = block.boundingBox.size.width;
        if (width >= 0.15) { substantialLineCount += 1; continue; }
        if (normalized.length >= 8 && width >= 0.13 && block.boundingBox.size.height >= 0.030) {
            substantialLineCount += 1;
        }
    }
    if (substantialLineCount >= 6) { return YES; }

    (void)textBlockCount;
    (void)totalWidth;
    return NO;
}

// 从整窗 OCR 里挑出“对白框”那几行：取最低的一条长行当锚点，再收拢它附近的行。
// 目的：街景招牌、公告牌这类环境文本不该混进对白翻译。
// 对白/选项的文字块：幅面够大、字数够多。街景招牌、图标标签这类零碎短文本天然被排除。
static BOOL IsFormedTextLine(OCRTextItem *block) {
    NSString *normalized = NormalizeForComparison(block.text);
    if (normalized.length >= 8 && block.boundingBox.size.width >= 0.20) { return YES; }
    // 0.15 太贴近现实边缘：对白框被 UI 遮住一半时宽度会掉到 0.13 左右，
    // 只差一点点就被判成“不成型”，整条对白就丢了。放宽到 0.12。
    if (normalized.length >= 6 && block.boundingBox.size.width >= 0.12) { return YES; }
    return NO;
}

// 挑出“对白 + 选项”这些需要翻译的文字块。
// 做法：以画面**下半部**里最宽的一条成型行作锚点（视觉小说的对白框在下半部，而且通常最宽），
// 再把与它水平大幅重叠、纵向邻接的块一起收进来。
// 注意 Vision 的 boundingBox 是底左原点：y 越大越靠近画面顶端。
// 能不能当“对白框”的锚点。
// 对白框的现实特征：① 贴在画面很靠下的位置 ② 框里有一条像台词的宽行。
// 判得严一点很重要 —— 文本密集的功能 UI 里也有不少宽行，放松了就会把 UI 误判成对白、
// 于是整屏文字被塞进字幕窗，而该贴译的内容反而没人管。
// “短句对白”锚点：只在对白框通篇短句时兜底使用。
// 门槛刻意比 IsDialogueAnchorCandidate 低（实测「思い出した。」是 6 字 / 0.13 宽）。
static BOOL IsShortDialogueAnchorCandidate(OCRTextItem *block) {
    NSString *normalized = NormalizeForComparison(block.text);
    if (normalized.length < 4) { return NO; }
    if (block.boundingBox.size.height < 0.026) { return NO; }
    if (CGRectGetMidY(block.boundingBox) > 0.45) { return NO; }
    if (block.boundingBox.size.width < 0.06) { return NO; }
    // 纯数字/日期样式的一小串不当对白
    return YES;
}

static BOOL IsUnpunctuatedSingleLineDialogue(NSString *text, CGRect box) {
    NSString *normalized = NormalizeForComparison(text);
    return normalized.length >= 4 && normalized.length <= 14 && ContainsJapaneseText(normalized) &&
        box.size.height >= 0.043 && box.size.width >= 0.08 && box.size.width <= 0.30 &&
        CGRectGetMinX(box) >= 0.18 && CGRectGetMaxX(box) <= 0.78 &&
        CGRectGetMidY(box) >= 0.10 && CGRectGetMidY(box) <= 0.38;
}

static BOOL IsCornerHelpButton(OCRTextItem *block) {
    CGRect box = block.boundingBox;
    return CGRectGetMinX(box) >= 0.80 && CGRectGetMidY(box) <= 0.12 &&
        [NormalizeForComparison(block.text) containsString:@"操作説明"];
}

// 单行对白：整屏只有一句台词（没有名字框、没有第二行）。
// 之前“短句兜底”要求它和相邻行堆叠，于是单行对白被误杀（band=0 → 被判成界面贴译）。
// 台词几乎都以句末标点结尾，而街景招牌通常没有 —— 用这个区分。
static BOOL IsSingleLineDialogue(OCRTextItem *block) {
    NSString *normalized = NormalizeForComparison(block.text);
    if (normalized.length < 4) { return NO; }
    // 门槛放到 0.05：台词本来就短（实测「行くぞ。」只有 0.08 宽）。
    // 真正的防误判靠“必须以句末标点结尾”，不靠宽度。
    if (block.boundingBox.size.width < 0.05) { return NO; }
    if (block.boundingBox.size.height < 0.026) { return NO; }
    if (CGRectGetMidY(block.boundingBox) > 0.45) { return NO; }
    NSCharacterSet *enders = [NSCharacterSet characterSetWithCharactersInString:@"。！!？?…・、"];
    if ([enders characterIsMember:[normalized characterAtIndex:normalized.length - 1]]) { return YES; }
    // 视觉小说的单行台词不一定有标点；名字框也可能被 OCR 完全漏掉。
    return IsUnpunctuatedSingleLineDialogue(normalized, block.boundingBox);
}

static BOOL IsDialogueAnchorCandidate(OCRTextItem *block) {
    if (!IsFormedTextLine(block)) { return NO; }
    if (block.boundingBox.size.height < 0.026) { return NO; }
    CGFloat midY = CGRectGetMidY(block.boundingBox);
    if (midY > 0.32) { return NO; }
    CGFloat width = block.boundingBox.size.width;
    NSUInteger length = NormalizeForComparison(block.text).length;
    return width >= 0.22 || length >= 10;
}

// 这两串是「译芽」自己画在屏幕上的状态栏文字（状态行 + 句数行）。
// 它们常常正好压在目标窗口上（实测在左下角），于是被下一轮 OCR 读回来当成正文：
// 混进字幕带、占住锚点位置，把真正的对白行挤出字幕带（实测「平気。」就是这么丢的）。
static BOOL IsOwnOverlayText(NSString *raw) {
    NSString *t = Trim(raw);
    if (t.length == 0) { return NO; }
    NSString *lower = t.lowercaseString;
    // 翻译全失败时状态串会长成「翻译失败：<服务端报错>」，形状不固定，用前缀识别
    if ([t hasPrefix:@"翻译失败："] || [t hasPrefix:@"翻译失败:"]) { return YES; }
    NSArray<NSString *> *needles = @[@"译文已更新", @"自动判别", @"翻译界面", @"正在翻译",
                                     @"等待文本稳定", @"已暂停", @"本次 ", @"OCr ".lowercaseString];
    // 短且**完全没有日文假名/汉字**的碎片：`？？？` 之类的字形被误读成拉丁字母
    // （实测名字框读成 `iee`、`ことと`）。这类东西发去翻译只会得到编造的译文。
    if (t.length <= 6) {
        BOOL hasKanaOrKanji = NO;
        for (NSUInteger index = 0; index < t.length; index++) {
            unichar character = [t characterAtIndex:index];
            if ((character >= 0x3040 && character <= 0x30FF) ||
                (character >= 0x4E00 && character <= 0x9FFF)) { hasKanaOrKanji = YES; break; }
        }
        if (!hasKanaOrKanji) { return YES; }
    }

    // 状态行被 OCR 截断成片段时（实测 `翻译 0.6s 总 0.8s`）关键词会丢，但**计时格式**还在。
    // 游戏正文里不会出现 `0.6s` 这种「数字.数字s」的秒表写法，所以这条很安全。
    BOOL hasTimingPattern = NO;
    {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[0-9]+\\.[0-9]+s"
                                                                              options:0
                                                                                error:NULL];
        if (regex) {
            NSRange full = NSMakeRange(0, t.length);
            hasTimingPattern = [regex firstMatchInString:t options:0 range:full] != nil;
        }
    }
    if (hasTimingPattern) { return YES; }

    BOOL hasNeedle = NO;
    for (NSString *needle in needles) {
        if ([t containsString:needle] || [lower containsString:needle.lowercaseString]) { hasNeedle = YES; break; }
    }
    if (!hasNeedle) { return NO; }
    // 状态行一定带数字（秒数）。这里放宽到“含数字”即可：
    // OCR 常把它读花（实测 `译文已要新・OCR 0.25南译0.3550.55）。••`），
    // 原来要求含「秒/句/s」就漏过了 —— 于是这行乱码混进字幕带、被当成台词送去翻译，
    // 模型自然给出一句完全不相干的译文。
    BOOL hasDigit = NO;
    for (NSUInteger index = 0; index < t.length; index++) {
        unichar character = [t characterAtIndex:index];
        if (character >= '0' && character <= '9') { hasDigit = YES; break; }
    }
    if (hasDigit) { return YES; }

    BOOL looksStatus = [t containsString:@"s"] || [t containsString:@"S"] || [t containsString:@"秒"];
    BOOL looksCount = [t containsString:@"句"];
    return looksStatus || looksCount;
}

// 从 OCR 结果里剔除我们自己的浮窗文字。
// 两种来源：
//   ① 形状可辨的状态栏（IsOwnOverlayText）
//   ② 我们刚画上去的译文（由调用方传入已渲染过的文本）——
//      贴译面板会盖住原文，下一轮 OCR 必然把它们读回来；
//      若不过滤，这些中文会被当成“原文”再翻一次，对白框里就会混进重复/错位的句子。
static NSArray<OCRTextItem *> *OCRItemsExcludingOwnOverlay(NSArray<OCRTextItem *> *items,
                                                           NSSet<NSString *> *renderedTexts) {
    if (items.count == 0) { return items; }
    NSMutableArray<OCRTextItem *> *kept = [NSMutableArray arrayWithCapacity:items.count];
    for (OCRTextItem *item in items) {
        if (IsOwnOverlayText(item.text)) { continue; }
        if (renderedTexts.count > 0) {
            NSString *normalized = NormalizeForComparison(item.text);
            if (normalized.length > 0 && [renderedTexts containsObject:normalized]) { continue; }
        }
        [kept addObject:item];
    }
    return kept;
}

// 我们画过的所有译文（字幕窗 + 贴译面板），归一化后供 OCR 去重
static NSSet<NSString *> *RenderedTranslationSet(NSString *captionText, NSDictionary *inlineCache) {
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    NSString *normalizedCaption = NormalizeForComparison(captionText);
    if (normalizedCaption.length >= 2) { [set addObject:normalizedCaption]; }
    for (NSString *value in inlineCache.allValues) {
        if (![value isKindOfClass:NSString.class]) { continue; }
        NSString *normalized = NormalizeForComparison(value);
        if (normalized.length >= 2) { [set addObject:normalized]; }
    }
    return set;
}

// OCR 常把紧邻对白的小按钮粘进同一行：实测 `思い出した。` 被读成 `思い出した。使用`。
// 直接发去翻译，模型会照着输出「想起来了。使用」—— 按钮文字混进了字幕。
// 规则：句末标点之后只剩一小段**纯汉字**（2~4 字），且整串里有假名，就把它当按钮切掉。
static NSString *DialogueTextWithoutTrailingButton(NSString *text) {
    NSString *trimmed = Trim(text);
    if (trimmed.length == 0) { return trimmed; }

    NSCharacterSet *kanaSet = [NSCharacterSet characterSetWithCharactersInString:
        @"ぁあぃいぅうぇえぉおかがきぎくぐけげこごさざしじすずせぜそぞただちぢっつづてでとどなにぬねのはばぱひびぴふぶぷへべぺほぼぽまみむめもゃやゅゆょよらりるれろゎわゐゑをんァアィイゥウェエォオカガキギクグケゲコゴサザシジスズセゼソゾタダチヂッツヅテデトドナニヌネノハバパヒビピフブプヘベペホボポマミムメモャヤュユョヨラリルレロヮワヰヱヲンヴー"];
    BOOL hasKana = NO;
    for (NSUInteger index = 0; index < trimmed.length; index++) {
        if ([kanaSet characterIsMember:[trimmed characterAtIndex:index]]) { hasKana = YES; break; }
    }
    if (!hasKana) { return trimmed; }

    // 从末尾往前吃掉 2~4 个纯汉字，并要求它前面是句末标点
    NSUInteger end = trimmed.length;
    NSUInteger runStart = end;
    while (runStart > 0) {
        unichar character = [trimmed characterAtIndex:runStart - 1];
        if (character >= 0x4E00 && character <= 0x9FFF) { runStart -= 1; continue; }
        break;
    }
    NSUInteger hanRun = end - runStart;
    if (hanRun < 2 || hanRun > 4 || runStart == 0) { return trimmed; }

    NSCharacterSet *sentenceEnd = [NSCharacterSet characterSetWithCharactersInString:@"。．.!！?？、，,…」』）)"];
    if (![sentenceEnd characterIsMember:[trimmed characterAtIndex:runStart - 1]]) { return trimmed; }

    return Trim([trimmed substringToIndex:runStart]);
}

NSArray<OCRTextItem *> *SubtitleBandItemsFromBlocks(NSArray<OCRTextItem *> *blocks) {
    // 锚点不要只看“整屏最宽”：选项里出现「・・・・」这类省略号时可能比对白还宽，
    // 那样会把选项当锚点、真正的对白反而被排除。
    // 也**不再**退回“画面里最低的成型行” —— 那正是把密集文本 UI 误判成对白的元凶。
    // 找不到真正的对白锚点就返回空，让判别走 UI/贴译路线。
    OCRTextItem *anchor = nil;
    BOOL usedShortAnchorFallback = NO;
    for (OCRTextItem *block in blocks) {
        if (!IsDialogueAnchorCandidate(block)) { continue; }
        if (!anchor || block.boundingBox.size.width > anchor.boundingBox.size.width) { anchor = block; }
    }

    // 兜底：对白框里**通篇都是短句**时，上面一条都当不了锚点。
    // 真实例子：「思い出した。」6 字/0.13 宽 + 名字「？？？」——整框没有长行，
    // 结果字幕带为空、一个字都不翻。
    // 但不能见到短行就当对白（散落的街景招牌也是短行），
    // 所以要求它**和另一行紧挨着堆叠**：对白框的行距很紧，招牌之间不会这么近。
    // 注意：anchor 可能已经被设成一个“勉强合格”的错读（实测名字框的 `？？？`
    // 被 OCR 读成平假名 `ことと`，长度够格但其实是噪声）。
    // 这时也要走兜底 —— 否则真正的那句「思い出した。」永远进不来。
    // 判定标准是：当前 anchor **是否真的和相邻行堆叠**（孤零零一条不算对白）。
    // 只对**弱锚点**（短而窄）要求堆叠：孤零零一条短行不像对白框。
    // 长行锚点不受影响 —— 单行对白框本来就靠一条长行成立（有测试守着这一点）。
    if (anchor) {
        BOOL weakAnchor = anchor.boundingBox.size.width < 0.16
            && NormalizeForComparison(anchor.text).length < 10;
        if (weakAnchor) {
            BOOL anchorStacked = NO;
            for (OCRTextItem *other in blocks) {
                if (other == anchor) { continue; }
                if (NormalizeForComparison(other.text).length < 2) { continue; }
                if (fabs(CGRectGetMidY(other.boundingBox) - CGRectGetMidY(anchor.boundingBox)) >= 0.10) { continue; }
                CGFloat otherLeft = MAX(CGRectGetMinX(other.boundingBox), CGRectGetMinX(anchor.boundingBox));
                CGFloat otherRight = MIN(CGRectGetMaxX(other.boundingBox), CGRectGetMaxX(anchor.boundingBox));
                if (otherRight - otherLeft <= 0) { continue; }
                anchorStacked = YES;
                break;
            }
            // 没堆叠也要留意：它可能只是名字框，而真正的对白在下面更宽的那条
            if (!anchorStacked) {
                OCRTextItem *better = nil;
                for (OCRTextItem *other in blocks) {
                    if (other == anchor || !IsShortDialogueAnchorCandidate(other)) { continue; }
                    if (other.boundingBox.size.width <= anchor.boundingBox.size.width) { continue; }
                    if (!better || other.boundingBox.size.width > better.boundingBox.size.width) { better = other; }
                }
                if (better) {
                    anchor = better;
                    usedShortAnchorFallback = YES;
                } else {
                    anchor = nil;
                }
            }
        }
    }

    if (!anchor) {
        // 单行对白：允许单独一条以句末标点结尾的短句当锚点
        for (OCRTextItem *block in blocks) {
            if (!IsSingleLineDialogue(block)) { continue; }
            anchor = block;
            usedShortAnchorFallback = YES;
            break;
        }
    }

    if (!anchor) {
        for (OCRTextItem *block in blocks) {
            if (!IsShortDialogueAnchorCandidate(block)) { continue; }
            CGFloat midY = CGRectGetMidY(block.boundingBox);
            BOOL stacked = NO;
            for (OCRTextItem *other in blocks) {
                if (other == block) { continue; }
                if (NormalizeForComparison(other.text).length < 2) { continue; }
                if (fabs(CGRectGetMidY(other.boundingBox) - midY) >= 0.10) { continue; }
                // 同一组文字框水平上要对得上
                CGFloat overlapLeft = MAX(CGRectGetMinX(other.boundingBox), CGRectGetMinX(block.boundingBox));
                CGFloat overlapRight = MIN(CGRectGetMaxX(other.boundingBox), CGRectGetMaxX(block.boundingBox));
                if (overlapRight - overlapLeft <= 0) { continue; }
                stacked = YES;
                break;
            }
            if (!stacked) { continue; }
            if (!anchor || block.boundingBox.size.width > anchor.boundingBox.size.width) {
                anchor = block;
                usedShortAnchorFallback = YES;
            }
        }
    }
    if (!anchor) { return @[]; }

    // 兜底否决：这一组里如果没有任何“像对白”的实质长行（够宽或够长），
    // 那它就不是对白框，而是招牌/按钮之类，宁可不翻。
    BOOL hasSubstantialLine = NO;
    for (OCRTextItem *block in blocks) {
        if (block.boundingBox.size.width >= 0.20) { hasSubstantialLine = YES; break; }
        if (NormalizeForComparison(block.text).length >= 8 && block.boundingBox.size.width >= 0.15) {
            hasSubstantialLine = YES;
            break;
        }
    }
    // 短句兜底路径不能再用“必须有长行”否决 —— 整框都是短句正是它要处理的情况，
    // 它已经用“和相邻行紧挨堆叠”把散落的招牌挡在外面了。
    if (!hasSubstantialLine && !usedShortAnchorFallback) { return @[]; }

    NSMutableArray<OCRTextItem *> *candidates = [NSMutableArray array];
    for (OCRTextItem *block in blocks) {
        if (block == anchor) { continue; }
        if (NormalizeForComparison(block.text).length < 2) { continue; }
        // 宽度门槛故意放宽到 0.04：对白框里的短句本来就很窄
        // （实测「平気。」只有 0.06 宽、「それより、」0.10），
        // 旧门槛 0.10 会把它们直接剔除 —— 用户看到的就是“第一句没翻译”。
        // 真正防止把菜单/招牌收进来的是下面扩张循环里的“水平重叠 + 紧邻”双条件。
        if (block.boundingBox.size.width < 0.04) { continue; }
        [candidates addObject:block];
    }

    NSMutableArray<OCRTextItem *> *band = [NSMutableArray arrayWithObject:anchor];
    for (NSInteger direction = 0; direction < 2; direction++) {
        CGFloat frontierMidY = CGRectGetMidY(anchor.boundingBox);
        while (YES) {
            OCRTextItem *next = nil;
            CGFloat bestGap = CGFLOAT_MAX;
            for (OCRTextItem *candidate in candidates) {
                CGFloat gap = CGRectGetMidY(candidate.boundingBox) - frontierMidY;
                if (direction == 0 && gap >= 0) { continue; }
                if (direction == 1 && gap <= 0) { continue; }
                // 收拢窗口要“紧”：只把真正连续的相邻行算作一段。
                // 放太宽（曾经是 0.35）会把选项区和对白框连成一片，拆不分家。
                // 但仍需要一点余量：对白框里第一行常和后面几行隔得较开
                // （实测「平気。」与下一行差 0.062），窗口太紧会把首行切掉。
                if (fabs(gap) >= 0.20) { continue; }
                // 水平重叠要占较窄那一条的一半以上：同一组文字框通常对齐，
                // 而街景招牌/背景文字与对白框只是擦边重叠，会被这一条挡住。
                CGFloat overlapLeft = MAX(CGRectGetMinX(candidate.boundingBox), CGRectGetMinX(anchor.boundingBox));
                CGFloat overlapRight = MIN(CGRectGetMaxX(candidate.boundingBox), CGRectGetMaxX(anchor.boundingBox));
                CGFloat overlap = overlapRight - overlapLeft;
                CGFloat narrower = MIN(candidate.boundingBox.size.width, anchor.boundingBox.size.width);
                if (overlap <= 0 || overlap < narrower * 0.5) { continue; }
                if (fabs(gap) < bestGap) {
                    next = candidate;
                    bestGap = fabs(gap);
                }
            }
            if (!next) { break; }
            [band addObject:next];
            [candidates removeObject:next];
            frontierMidY = CGRectGetMidY(next.boundingBox);
        }
    }

    [band sortUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) {
        CGFloat leftMidY = CGRectGetMidY(left.boundingBox);
        CGFloat rightMidY = CGRectGetMidY(right.boundingBox);
        if (fabs(leftMidY - rightMidY) < 0.01) { return NSOrderedSame; }
        // 底左原点：midY 大的在画面上方，按从上到下输出
        return leftMidY > rightMidY ? NSOrderedAscending : NSOrderedDescending;
    }];
    return band;
}

// 说话人名字框：短、没有句末标点、不含平假名（实测 `萩尾九段` / `片霧秋兵` / `ルード`）。
// 这类框会被 OCR 单独读成一行，或单独成一簇被当成「选项」，
// 于是在学习库里各占一条「最近台词」，把 5 条额度从真台词那里挤掉。
static BOOL LooksLikeSpeakerNameText(NSString *raw) {
    NSString *text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length == 0 || text.length > 10) { return NO; }
    NSCharacterSet *enders = [NSCharacterSet characterSetWithCharactersInString:@"。．.！!？?"];
    if ([enders characterIsMember:[text characterAtIndex:text.length - 1]]) { return NO; }
    BOOL hasNameGlyph = NO;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        // 带平假名的一律不是名字行（`うん、空いてるよ` / `我の手落ちだ` 都要留作正文）。
        if (character >= 0x3040 && character <= 0x309F) { return NO; }
        if ((character >= 0x4E00 && character <= 0x9FFF) ||
            (character >= 0x30A0 && character <= 0x30FF)) { hasNameGlyph = YES; }
    }
    return hasNameGlyph;
}

// 名字框上方的假名注音被 OCR 单独读成一行（实测 `かたぎりし、ゆうの` / `＜だん`）。
static BOOL LooksLikeSpeakerFuriganaText(NSString *raw) {
    NSString *text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length < 2 || text.length > 12) { return NO; }
    NSCharacterSet *enders = [NSCharacterSet characterSetWithCharactersInString:@"。．.！!？?"];
    if ([enders characterIsMember:[text characterAtIndex:text.length - 1]]) { return NO; }
    NSUInteger kana = 0, glyphs = 0;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if (character == ' ' || character == '\t') { continue; }
        glyphs += 1;
        if ((character >= 0x3040 && character <= 0x30FF) ||
            (character >= 0x31F0 && character <= 0x31FF)) { kana += 1; }
    }
    return glyphs > 0 && kana * 10 >= glyphs * 6;
}

// 一簇全是名字/注音（且至少有一行是名字），才当成名字框 —— 宽度上限防止把整行正文吞进来。
static BOOL LooksLikeSpeakerLabelCluster(NSArray<OCRTextItem *> *cluster) {
    if (cluster.count == 0 || cluster.count > 3) { return NO; }
    BOOL hasName = NO;
    CGFloat widest = 0;
    for (OCRTextItem *item in cluster) {
        widest = MAX(widest, item.boundingBox.size.width);
        if (LooksLikeSpeakerNameText(item.text)) { hasName = YES; continue; }
        if (!LooksLikeSpeakerFuriganaText(item.text)) { return NO; }
    }
    return hasName && widest <= 0.35;
}

// 单独一行是不是名字框的一部分：名字本身，或紧贴其上方的假名注音。
static BOOL IsSpeakerLabelItem(OCRTextItem *item, NSArray<OCRTextItem *> *pool) {
    if (LooksLikeSpeakerNameText(item.text)) { return item.boundingBox.size.width <= 0.35; }
    if (!LooksLikeSpeakerFuriganaText(item.text)) { return NO; }
    for (OCRTextItem *other in pool) {
        if (other == item || !LooksLikeSpeakerNameText(other.text)) { continue; }
        // 底左原点：注音的 midY 更大（更靠上），名字紧贴在它下面。
        if (CGRectGetMidY(other.boundingBox) >= CGRectGetMidY(item.boundingBox)) { continue; }
        if (CGRectGetMidY(item.boundingBox) - CGRectGetMaxY(other.boundingBox) > 0.05) { continue; }
        CGFloat overlap = MIN(CGRectGetMaxX(item.boundingBox), CGRectGetMaxX(other.boundingBox)) -
                          MAX(CGRectGetMinX(item.boundingBox), CGRectGetMinX(other.boundingBox));
        if (overlap >= item.boundingBox.size.width * 0.5) { return YES; }
    }
    return NO;
}

// 整帧只有说话人名字（可以带注音）—— 正文没读到。这种帧写进学习库只会白占一条额度。
// 必须真的有一行是名字：短句 `はい` 也满足“假名行”的判定，不能被当成名字框丢掉。
static BOOL DialogueFrameIsSpeakerLabelOnly(NSArray<NSString *> *lines) {
    if (lines.count == 0) { return NO; }
    BOOL hasName = NO;
    for (NSString *line in lines) {
        if (LooksLikeSpeakerNameText(line)) { hasName = YES; continue; }
        if (LooksLikeSpeakerFuriganaText(line)) { continue; }
        return NO;
    }
    return hasName;
}

// 把 band 拆成「对白」和「选项」两组。
// 做法：先按垂直间距把 band 分成一簇一簇（连续的行 ≤0.12，隔开的就是不同簇），
// 再把位于画面下半部的簇判为对白框，其余在上方的簇判为选项。
// 依据：视觉小说的对白框固定在画面下方，选项浮在上方；
// 这样就算选项自身的行距比较大，也不会把两个选项拆到两组里去。
void SplitDialogueAndOptionsFromItems(NSArray<OCRTextItem *> *band,
                                      NSArray<OCRTextItem *> *allBlocks,
                                      NSMutableArray<OCRTextItem *> *outDialogue,
                                      NSMutableArray<OCRTextItem *> *outOptions) {
    if (band.count == 0) { return; }

    // band 已按从上到下排序；这里切成簇
    NSMutableArray<NSMutableArray<OCRTextItem *> *> *clusters = [NSMutableArray array];
    NSMutableArray<OCRTextItem *> *current = nil;
    for (OCRTextItem *item in band) {
        if (!current) {
            current = [NSMutableArray arrayWithObject:item];
            [clusters addObject:current];
            continue;
        }
        CGFloat gap = fabs(CGRectGetMidY(current.lastObject.boundingBox) - CGRectGetMidY(item.boundingBox));
        if (gap <= 0.12) {
            [current addObject:item];
        } else {
            current = [NSMutableArray arrayWithObject:item];
            [clusters addObject:current];
        }
    }

    // 簇里最宽的一条所在位置，就是这一簇贴在画面的哪一带
    NSMutableArray<NSNumber *> *clusterWidths = [NSMutableArray array];
    for (NSMutableArray<OCRTextItem *> *cluster in clusters) {
        CGFloat widest = 0;
        for (OCRTextItem *item in cluster) { widest = MAX(widest, item.boundingBox.size.width); }
        [clusterWidths addObject:@(widest)];
    }

    // 选“对白簇”：最宽的成型行在画面下半部的那个簇；没有就退回整屏最宽的一条所在的簇
    NSInteger dialogueCluster = -1;
    CGFloat bestWidth = -1;
    for (NSUInteger index = 0; index < clusters.count; index++) {
        NSMutableArray<OCRTextItem *> *cluster = clusters[index];
        for (OCRTextItem *item in cluster) {
            if (!IsFormedTextLine(item)) { continue; }
            if (CGRectGetMidY(item.boundingBox) > 0.42) { continue; }
            if (item.boundingBox.size.width > bestWidth) {
                bestWidth = item.boundingBox.size.width;
                dialogueCluster = (NSInteger)index;
            }
        }
    }
    if (dialogueCluster < 0) {
        for (NSUInteger index = 0; index < clusters.count; index++) {
            CGFloat widest = clusterWidths[index].doubleValue;
            if (widest > bestWidth) {
                bestWidth = widest;
                dialogueCluster = (NSInteger)index;
            }
        }
    }

    // 名字/注音框紧贴在对白框上方，却会被拆成独立一簇丢进「选项」。
    // 实测 `萩尾九段`（名字框）就被标成「选项」单独记了一条学习记录。
    // 这里把它连同紧邻上方的注音一起并回对白框。
    NSInteger labelRunStart = dialogueCluster;
    while (labelRunStart > 0 && LooksLikeSpeakerLabelCluster(clusters[labelRunStart - 1])) { labelRunStart -= 1; }

    for (NSUInteger index = 0; index < clusters.count; index++) {
        if ((NSInteger)index >= labelRunStart && (NSInteger)index <= dialogueCluster) {
            if (outDialogue) { [outDialogue addObjectsFromArray:clusters[index]]; }
        } else {
            if (outOptions) { [outOptions addObjectsFromArray:clusters[index]]; }
        }
    }

    // 选项区离对白框往往比较远，band 的“紧收拢”会把它整个漏掉。
    // 这里补一遍：把 band 之外、但和对白框**水平对齐**的行也当作选项收进来。
    // 对齐标准取得比较严（重叠 ≥ 较窄那条的 55%），因为街景招牌通常只和对白框擦边。
    if (outOptions && dialogueCluster >= 0) {
        OCRTextItem *dialogueAnchor = nil;
        CGFloat anchorWidth = 0;
        for (OCRTextItem *item in clusters[dialogueCluster]) {
            if (item.boundingBox.size.width > anchorWidth) {
                anchorWidth = item.boundingBox.size.width;
                dialogueAnchor = item;
            }
        }
        if (dialogueAnchor) {
            NSArray<OCRTextItem *> *pool = allBlocks ?: band;
            for (OCRTextItem *item in pool) {
                if ([outOptions containsObject:item]) { continue; }
                if ([clusters[dialogueCluster] containsObject:item]) { continue; }
                if (NormalizeForComparison(item.text).length < 2) { continue; }
                if (item.boundingBox.size.width < 0.10) { continue; }
                // 名字框/注音不是选项：实测 `萩尾九段` 会被这条补漏收进选项，单独占一条记录。
                if (IsSpeakerLabelItem(item, pool)) { continue; }
                // 只补对白框上方的
                if (CGRectGetMidY(item.boundingBox) <= CGRectGetMidY(dialogueAnchor.boundingBox)) { continue; }
                CGFloat overlapLeft = MAX(CGRectGetMinX(item.boundingBox), CGRectGetMinX(dialogueAnchor.boundingBox));
                CGFloat overlapRight = MIN(CGRectGetMaxX(item.boundingBox), CGRectGetMaxX(dialogueAnchor.boundingBox));
                CGFloat overlap = overlapRight - overlapLeft;
                CGFloat narrower = MIN(item.boundingBox.size.width, dialogueAnchor.boundingBox.size.width);
                if (overlap <= 0 || overlap < narrower * 0.55) { continue; }
                [outOptions addObject:item];
            }
        }
    }
}

// 把 CGImage 画进一块灰度缓冲，供上面那个“底色亮不亮”的采样使用。
// 缩到不超过 480 宽就够了：只是测底色明暗，不需要原分辨率。
typedef struct {
    unsigned char *pixels;
    size_t width;
    size_t height;
    size_t bytesPerRow;
    CGContextRef context;
} GrayBuffer;

static GrayBuffer GrayBufferFromImage(CGImageRef image) {
    GrayBuffer buffer = {NULL, 0, 0, 0, NULL};
    size_t imageWidth = CGImageGetWidth(image);
    size_t imageHeight = CGImageGetHeight(image);
    if (imageWidth < 2 || imageHeight < 2) { return buffer; }

    size_t width = MIN(imageWidth, (size_t)480);
    size_t height = MAX((size_t)2, (size_t)((double)imageHeight * ((double)width / (double)imageWidth)));

    // 用 RGBA 而不是纯灰度：CGBitmapContext 不支持 kCGImageAlphaNone 的灰度格式，
    // 之前传它导致 context 创建失败、缓冲变成 0x0，后面所有判断都退化成“亮底”。
    size_t stride = width * 4;
    unsigned char *pixels = (unsigned char *)calloc(height, stride);
    if (!pixels) { return buffer; }
    // 必须给颜色空间：第三个参数（colorspace）传 NULL 时 CGBitmapContextCreate 会直接失败，
    // 之前就是这样导致缓冲一直是 0x0、所有判断退化成“亮底”。
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, stride, space,
                                                 kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) {
        free(pixels);
        return buffer;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);

    buffer.pixels = pixels;
    buffer.width = width;
    buffer.height = height;
    buffer.bytesPerRow = CGBitmapContextGetBytesPerRow(context);
    buffer.context = context;
    return buffer;
}

static void GrayBufferRelease(GrayBuffer *buffer) {
    if (buffer->context) { CGContextRelease(buffer->context); }
    if (buffer->pixels) { free(buffer->pixels); }
    buffer->context = NULL;
    buffer->pixels = NULL;
}

// 找出画面里那块“大白矩形”（详情弹窗 / 模态窗），返回它在**归一化底左坐标**下的范围。
// 依据：模态窗一定是一块又大又亮、轮廓连续的矩形；
// 而被压暗的底层页面虽然也有亮像素，但成不了这种又大又连片的区域。
// 找不到就返回 NO（当帧不裁剪）。
static BOOL DetectBrightContentRegion(const unsigned char *pixels,
                                      size_t width,
                                      size_t height,
                                      size_t bytesPerRow,
                                      CGRect *outNormalizedRect,
                                      BOOL *outDimmedColumns,
                                      const CGRect *exclusions,
                                      size_t exclusionCount) {
    if (!pixels || width < 8 || height < 8) { return NO; }

    // 把自己浮窗覆盖的像素预先标进一张位图。
    // 之前是对每个像素遍历一遍所有面板（13 万像素 × 20 个面板 ≈ 260 万次循环），
    // 跑在主线程上直接让界面卡住十几秒。
    unsigned char *excludedMask = NULL;
    if (exclusionCount > 0) {
        excludedMask = (unsigned char *)calloc(width * height, 1);
        for (size_t i = 0; i < exclusionCount; i++) {
            CGRect r = exclusions[i];
            size_t x0 = (size_t)MAX(0, r.origin.x * width);
            size_t x1 = (size_t)MIN((CGFloat)width, CGRectGetMaxX(r) * width);
            size_t y0 = (size_t)MAX(0, (1.0 - CGRectGetMaxY(r)) * height);
            size_t y1 = (size_t)MIN((CGFloat)height, (1.0 - r.origin.y) * height);
            for (size_t y = y0; y < y1; y++) {
                for (size_t x = x0; x < x1; x++) { excludedMask[y * width + x] = 1; }
            }
        }
    }
    #define FUYI_EXCLUDED(px, py) (excludedMask != NULL && excludedMask[(py) * width + (px)] != 0)

    const double brightThreshold = 150.0;
    const double dimThreshold = 140.0;
    const double minColumnFraction = 0.45;
    const size_t minRunColumns = MAX((size_t)8, (size_t)(width * 0.15));
    const size_t minRunRows = MAX((size_t)8, (size_t)(height * 0.15));

    size_t bestX0 = 0, bestXLen = 0, run = 0;
    for (size_t x = 0; x <= width; x++) {
        BOOL ok = NO;
        if (x < width) {
            size_t bright = 0, considered = 0;
            for (size_t y = 0; y < height; y++) {
                if (FUYI_EXCLUDED(x, y)) { continue; }
                const unsigned char *pixel = pixels + y * bytesPerRow + x * 4;
                considered += 1;
                if ((pixel[0] + pixel[1] + pixel[2]) / 3.0 >= brightThreshold) { bright += 1; }
            }
            ok = (considered >= height / 4) && (((double)bright / (double)considered) >= minColumnFraction);
        }
        if (ok) {
            if (run == 0) { run = 1; } else { run += 1; }
        } else {
            if (run > bestXLen) { bestXLen = run; bestX0 = x - run; }
            run = 0;
        }
    }
    if (bestXLen < minRunColumns) { if (excludedMask) { free(excludedMask); } return NO; }

    // 纵向：仍然只在**已确定的列范围**里找最长连续亮段 —— 必须用“亮”而不是“没被压暗”。
    // 曾经为了不切掉橙色页眉，把判据改成“有没有被压暗”，结果上半屏（被压得较浅的页面）
    // 也满足条件，弹窗范围变成 y 0.09..0.83（几乎整屏），左边栏目的译文就又冒出来了。
    // 宁可靠外层把范围向下外扩一点来容纳页眉页脚。
    const double minRowBrightFraction = 0.55;
    size_t bestY0 = 0, bestYLen = 0;
    run = 0;
    for (size_t y = 0; y <= height; y++) {
        BOOL brightRow = NO;
        if (y < height) {
            const unsigned char *row = pixels + y * bytesPerRow;
            size_t bright = 0;
            size_t considered = 0;
            for (size_t x = bestX0; x < bestX0 + bestXLen; x++) {
                if (FUYI_EXCLUDED(x, y)) { continue; }
                const unsigned char *pixel = row + x * 4;
                if ((pixel[0] + pixel[1] + pixel[2]) / 3.0 >= brightThreshold) { bright += 1; }
                considered += 1;
            }
            brightRow = (considered >= bestXLen / 4) &&
                        (((double)bright / (double)considered) >= minRowBrightFraction);
        }
        if (brightRow) {
            if (run == 0) { run = 1; } else { run += 1; }
        } else {
            if (run > bestYLen) { bestYLen = run; bestY0 = y - run; }
            run = 0;
        }
    }
    if (bestYLen < minRunRows) { if (excludedMask) { free(excludedMask); } return NO; }

    // 压暗掩码：落在被压暗的列上、且位于弹窗之外的地方，属于“上一级残留文字”
    if (outDimmedColumns) {
        for (size_t x = 0; x < width; x++) { outDimmedColumns[x] = NO; }
        for (size_t x = 0; x < width; x++) {
            size_t dim = 0;
            for (size_t y = 0; y < height; y++) {
                if (FUYI_EXCLUDED(x, y)) { continue; }
                const unsigned char *pixel = pixels + y * bytesPerRow + x * 4;
                if ((pixel[0] + pixel[1] + pixel[2]) / 3.0 < dimThreshold) { dim += 1; }
            }
            outDimmedColumns[x] = ((double)dim / (double)height) > 0.62;
        }
    }

    // 位图 y 是从上往下，转回 Vision 的底左原点
    CGFloat nx0 = (CGFloat)bestX0 / (CGFloat)width;
    CGFloat nx1 = (CGFloat)(bestX0 + bestXLen) / (CGFloat)width;
    CGFloat nyTop = (CGFloat)bestY0 / (CGFloat)height;
    CGFloat nyBottom = (CGFloat)(bestY0 + bestYLen) / (CGFloat)height;

    *outNormalizedRect = CGRectMake(nx0, 1.0 - nyBottom, nx1 - nx0, nyBottom - nyTop);
    if (excludedMask) { free(excludedMask); }
    return YES;
}

// 判断某个文字块是不是压在半透明遮罩上（= 上一级页面残留的文字）。
// OCR 只给文字和坐标，读不出明暗，所以这里真的去采样像素：
//   弹窗正文是「深色字 + 亮底」，而被压暗的底层页面是「字和底都偏暗」。
// 用「文字外圈一点的平均亮度」近似底色：够亮才算当前这一层的内容。
BOOL BlockSitsOnBrightBackdrop(OCRTextItem *block,
                                      const unsigned char *gray,
                                      size_t width,
                                      size_t height,
                                      size_t bytesPerRow) {
    if (!gray || width < 4 || height < 4) { return YES; }

    CGFloat minX = CGRectGetMinX(block.boundingBox) * (CGFloat)width;
    CGFloat maxX = CGRectGetMaxX(block.boundingBox) * (CGFloat)width;
    // Vision 的 y 是底左原点，位图是从上往下存，所以这里要把 y 翻过来
    CGFloat minY = (1.0 - CGRectGetMaxY(block.boundingBox)) * (CGFloat)height;
    CGFloat maxY = (1.0 - CGRectGetMinY(block.boundingBox)) * (CGFloat)height;

    // 往上/下各扩一点作为“底色”采样带（避开文字本身的笔画）
    CGFloat bandTop = MAX(0, minY - 3.0);
    CGFloat bandBottom = MIN((CGFloat)height - 1, maxY + 3.0);
    size_t x0 = (size_t)MAX(0, MIN(minX, (CGFloat)width - 1));
    size_t x1 = (size_t)MAX(0, MIN(maxX, (CGFloat)width - 1));
    if (x1 <= x0) { return YES; }

    double sum = 0;
    size_t count = 0;
    for (size_t y = (size_t)bandTop; y <= (size_t)bandBottom; y += 2) {
        // 只取文字行上下那两条窄带，不统计文字笔画本身
        if (y > (size_t)minY + 1 && y + 1 < (size_t)maxY) { continue; }
        const unsigned char *row = gray + y * bytesPerRow;
        for (size_t x = x0; x <= x1; x += 2) {
            const unsigned char *pixel = row + x * 4;
            sum += (pixel[0] + pixel[1] + pixel[2]) / 3.0;
            count += 1;
        }
    }
    if (count == 0) { return YES; }
    double mean = sum / (double)count;
    return mean >= 150.0;
}

NSInteger DetectContentModeForBlocks(NSArray<OCRTextItem *> *blocks, NSInteger fallbackSegment) {
    if (blocks.count == 0) { return fallbackSegment; }

    // UI 特征优先否决：画面里有「戻る / 詳細 / メニュー」这类按钮，或者是文本密集的列表/菜单页，
    // 就走贴译整屏，而不是把某条宽行当对白。
    // 现实依据：列表页里也有很宽的行（实测 0.26），光凭“有没有宽行”分不出对白和列表。
    if (LooksLikeUIFrame(blocks)) { return ContentModeUI; }

    // 再看有没有成形的对白框：有就按对白处理，别被街景招牌/公告牌带偏
    if (SubtitleBandItemsFromBlocks(blocks).count > 0) { return ContentModeDialogue; }

    // 一帧只读到角落操作提示，或短台词被 OCR 截成 1~2 字时，不据此切换已确认的模式。
    if (blocks.count <= 2 && UITokenHitCount(blocks) == 0) {
        BOOL hasCentralDialogueFragment = NO;
        BOOL onlyCornerHints = YES;
        for (OCRTextItem *block in blocks) {
            CGRect box = block.boundingBox;
            if (ContainsJapaneseText(block.text) && CGRectGetMidY(box) >= 0.10 &&
                CGRectGetMidY(box) <= 0.38 && CGRectGetMinX(box) >= 0.18 &&
                CGRectGetMaxX(box) <= 0.78 && box.size.height >= 0.035) {
                hasCentralDialogueFragment = YES;
            }
            if (!(CGRectGetMinX(box) >= 0.80 && CGRectGetMidY(box) <= 0.12)) {
                onlyCornerHints = NO;
            }
        }
        if (hasCentralDialogueFragment || onlyCornerHints) { return fallbackSegment; }
    }

    return ContentModeUI;
}

@interface FlippedDocumentView : NSView
@end

@implementation FlippedDocumentView
- (BOOL)isFlipped { return YES; }
@end

typedef void (^RegionSelectionCompletion)(CGRect selectedRect, CGSize viewSize, BOOL cancelled);

@interface RegionSelectionView : NSView
@property(nonatomic) NSPoint startPoint;
@property(nonatomic) CGRect selectionRect;
@property(nonatomic, copy) RegionSelectionCompletion completion;
@end

@implementation RegionSelectionView

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithWhite:0 alpha:0.22] setFill];
    NSRectFill(self.bounds);

    NSDictionary *attributes = @{
        NSFontAttributeName: FYUIFont(24, NSFontWeightBold),
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    NSString *help = @"拖动框选 OCR 字幕区域，松手确认。按 Esc 取消";
    NSSize helpSize = [help sizeWithAttributes:attributes];
    [help drawAtPoint:NSMakePoint((NSWidth(self.bounds) - helpSize.width) / 2.0, 24) withAttributes:attributes];

    if (self.selectionRect.size.width <= 0 || self.selectionRect.size.height <= 0) {
        return;
    }

    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.selectionRect xRadius:8 yRadius:8];
    [[NSColor colorWithCalibratedRed:0.16 green:0.55 blue:1 alpha:0.16] setFill];
    [path fill];
    [[NSColor colorWithCalibratedRed:0.13 green:0.48 blue:1 alpha:1] setStroke];
    path.lineWidth = 4;
    [path stroke];

    NSString *sizeText = [NSString stringWithFormat:@"%.0f x %.0f", self.selectionRect.size.width, self.selectionRect.size.height];
    NSDictionary *sizeAttributes = @{
        NSFontAttributeName: FYUIFont(13, NSFontWeightBold),
        NSForegroundColorAttributeName: NSColor.whiteColor
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

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTextFieldDelegate>
@property(nonatomic, strong) NSWindow *mainWindow;
@property(nonatomic, strong) FYReferenceDictionary *referenceDictionary;
@property(nonatomic) NSUInteger sourceHoverGeneration;
@property(nonatomic) BOOL sourceHoverSuspended;
@property(nonatomic, strong) NSCache<NSString *,NSString *> *sourceHoverCache;
@property(nonatomic, strong) NSView *referenceCard;
@property(nonatomic, strong) NSTextField *referenceSearchField;
@property(nonatomic, strong) NSSegmentedControl *referenceTabs;
@property(nonatomic, strong) NSPopUpButton *referenceSensePopup;
@property(nonatomic, strong) NSStackView *referenceDetailStack;
@property(nonatomic, strong) NSStackView *referenceMoreExamples;
@property(nonatomic, copy) NSString *referenceActiveWord;
@property(nonatomic, strong) NSStackView *referenceStack;
@property(nonatomic, strong) NSPopUpButton *referenceEntryPopup;
@property(nonatomic, copy) NSArray<NSDictionary *> *referenceRecords;
@property(nonatomic) NSInteger referenceRequestGeneration;
@property(nonatomic, strong) NSPanel *captionPanel;
@property(nonatomic, strong) NSPanel *captionAppearancePreviewPanel;
@property(nonatomic, strong) FYAdventurePanel *captionAppearancePreviewContainer;
@property(nonatomic, strong) NSTextField *captionAppearancePreviewText;
@property(nonatomic, strong) NSTextField *captionAppearancePreviewBrand;
@property(nonatomic, strong) FYStudyChatSession *studyChatSession;
@property(nonatomic, strong) FYGlobalShortcuts *globalShortcuts;
@property(nonatomic, strong) NSStackView *mainWorkspaceRoot;
@property(nonatomic, strong) FYStudyChatView *mainStudyChatView;
@property(nonatomic, strong) FYStudyChatView *overlayStudyChatView;
@property(nonatomic, strong) FYStudyOverlayPanel *studyChatPanel;
@property(nonatomic, strong) FYStudyOverlayPanel *quickSentencePanel;
@property(nonatomic, strong) NSPanel *captionDockPanel;
@property(nonatomic) BOOL captionDockHasAnchor;
@property(nonatomic, strong) NSLayoutConstraint *workspaceWidth;
@property(nonatomic, strong) NSLayoutConstraint *mainChatWidth;
@property(nonatomic, strong) NSButton *mainChatToggle;
@property(nonatomic) BOOL studyChatOverlayRequested;
@property(nonatomic) BOOL quickSentenceRequested;
@property(nonatomic) NSInteger chatContextGeneration;
@property(nonatomic) BOOL chatResolvingSource;
@property(nonatomic) NSInteger quickSentenceGeneration;
@property(nonatomic, copy) NSString *quickSentenceSource;
@property(nonatomic, copy) NSString *quickSentenceTranslation;
@property(nonatomic, copy) NSString *quickSentenceID;
@property(nonatomic) NSInteger quickSentenceVersion;
// 贴译长卡片 → 语法学习 → AI 返回的不可变块快照与返回关系。
@property(nonatomic, strong) FYInlineBlockSnapshot *inlineBlockSnapshot;
@property(nonatomic, strong) FYInlineBlockSnapshot *inlineReturnSnapshot;
@property(nonatomic, copy) NSString *inlineReturnSourceText;
@property(nonatomic, strong) NSButton *inlineReturnButton;
// 贴译长卡片打开的学习卡（而非对白查句）：标题与底部操作按预览切换。
@property(nonatomic) BOOL quickSentenceIsInlineBlock;
@property(nonatomic) CGFloat quickSentenceScrollOffset;
@property(nonatomic) NSInteger quickSelectedGrammarIndex;
@property(nonatomic, strong) NSButton *quickSelectedGrammarButton;
@property(nonatomic, copy) NSArray<FYRequestIdentity *> *savedSentences;
@property(nonatomic, strong) NSStackView *savedSentenceStack;
@property(nonatomic, strong) NSStackView *learningCollectionHost;
@property(nonatomic, copy) NSArray<NSView *> *learningCollectionSections;
@property(nonatomic, copy) NSArray<NSButton *> *learningCollectionTabs;
@property(nonatomic) NSInteger learningCollectionIndex;
@property(nonatomic, strong) NSTextField *learningCollectionTitle;
@property(nonatomic, strong) NSTextField *learningCollectionCount;
@property(nonatomic, strong) NSMutableSet<NSString *> *expandedWordCards;
@property(nonatomic, strong) NSButton *quickSentenceBookmarkButton;
@property(nonatomic) BOOL sentenceBookmarkPending;
@property(nonatomic, copy) NSArray<NSButton *> *quickStructureButtons;
// 主界面结构图的节点按钮与横向滚动视图：点击节点只做局部高亮，不重建结构图。
@property(nonatomic, copy) NSArray<NSButton *> *mainStructureButtons;
@property(nonatomic, strong) NSScrollView *mainStructureScrollView;
@property(nonatomic, strong) NSScrollView *quickStructureScrollView;
@property(nonatomic, strong) NSStackView *sentenceStructureStack;
@property(nonatomic, strong) NSButton *quickGrammarBookmarkButton;
@property(nonatomic, strong) NSTextField *quickGrammarBookmarkStatus;
@property(nonatomic) BOOL quickGrammarBookmarkPending;
@property(nonatomic, strong) NSStackView *quickGrammarStack;
@property(nonatomic, strong) NSView *quickGrammarDetailCard;
@property(nonatomic, copy) NSArray<NSButton *> *quickGrammarChoices;
@property(nonatomic, strong) FYLearningAnalyzer *quickSentenceAnalyzer;
@property(nonatomic, strong) FYAnalysisResult *quickSentenceAnalysis;
@property(nonatomic, copy) NSString *quickSentenceAnalysisSource;
@property(nonatomic, copy) NSString *quickSentenceAnalysisTranslation;
@property(nonatomic, copy) NSString *quickSentenceAnalysisError;
@property(nonatomic) BOOL quickSentenceAnalyzing;
@property(nonatomic) NSInteger quickAnalysisGeneration;
@property(nonatomic, strong) NSPanel *regionSelectionPanel;
@property(nonatomic, strong) NSPanel *ocrPreviewPanel;
@property(nonatomic, strong) NSTextField *ocrPreviewLabel;
@property(nonatomic, strong) NSView *captionContainer;
@property(nonatomic, strong) NSTextField *captionTextLabel;
@property(nonatomic, strong) NSTextField *captionBrandLabel;

@property(nonatomic, strong) NSMutableArray<WindowItem *> *windows;
@property(nonatomic, strong) NSPopUpButton *windowPopup;
// 采集卡输入：识别输入源与"字幕显示窗口"分开选择。
// 输入源只决定 OCR 从哪里取画面；字幕始终跟随上面选中的 QuickTime／OBS 窗口。
@property(nonatomic, strong) FYCaptureCardInput *captureCardInput;
// 采集卡视频显示区域（屏幕坐标），由校准写入。没有它就认为映射不可用：
// 「有帧 + 有窗口」不等于映射有效（窗口标题栏／工具栏／OBS 面板／裁剪都会让整窗估算整体偏移）。
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *captureCardVideoRects;
@property(nonatomic, strong) NSPanel *inlineExpandedReadingPanel;
@property(nonatomic, strong) id inlineExpandedReadingKeyMonitor;
@property(nonatomic, strong) NSPanel *captureCalibrationPanel;
@property(nonatomic, strong) id captureCalibrationKeyMonitor;
@property(nonatomic, strong) NSDate *lastAutoLocateAttempt;
@property(nonatomic, strong) NSButton *captureCalibrateButton;
@property(nonatomic, strong) NSButton *captureCalibrateClearButton;
@property(nonatomic, strong) NSTextField *captureCalibrationLabel;
@property(nonatomic, strong) NSSegmentedControl *inputSourceControl;
@property(nonatomic, strong) NSPopUpButton *captureDevicePopup;
@property(nonatomic, strong) NSTextField *liveChipRecognition;
@property(nonatomic, strong) NSTextField *liveChipAutoTranslate;
@property(nonatomic, strong) NSTextField *liveChipPauseFollow;
@property(nonatomic, strong) NSTextField *liveScreenSpeakerLabel;
@property(nonatomic, strong) NSTextField *liveScreenDialogueLabel;
@property(nonatomic, strong) NSTextField *liveLevelTag;
@property(nonatomic, strong) NSLayoutConstraint *previewAspectConstraint;
@property(nonatomic, strong) NSTextField *permissionStatusLabel;
@property(nonatomic, strong) NSView *grammarStructureCard;
@property(nonatomic, copy) NSArray<NSButton *> *grammarTabButtons;
@property(nonatomic, copy) NSArray<NSView *> *grammarTabUnderlines;
@property(nonatomic) NSInteger selectedGrammarTab;
@property(nonatomic, strong) NSView *grammarPointsPane;
@property(nonatomic, strong) NSView *grammarTabRow;
@property(nonatomic, strong) NSView *grammarEmptyPane;
@property(nonatomic, strong) NSTextField *grammarEmptyTitle;
@property(nonatomic, strong) NSTextField *grammarEmptyHint;
@property(nonatomic, strong) NSButton *grammarEmptyAnalyzeButton;
@property(nonatomic, strong) NSTextField *grammarReferenceNote;
@property(nonatomic, copy) NSString *grammarAnalysisError;
@property(nonatomic, strong) NSView *grammarExamplesPane;
@property(nonatomic, strong) NSTextField *grammarExampleLabel;
@property(nonatomic, strong) NSView *grammarFollowupDisclosure;
@property(nonatomic, strong) NSTextField *captureStatusLabel;
@property(nonatomic, strong) NSTextField *inputSourceHintLabel;
@property(nonatomic, strong) NSView *captureCardControlsView;
@property(nonatomic, strong) NSButton *captureSettingsButton;
@property(nonatomic) NSInteger inputSourceSegment;
@property(nonatomic, copy, nullable) NSString *selectedCaptureDeviceID;
@property(nonatomic) BOOL captureDeviceListLoaded;
@property(nonatomic) uint64_t lastOCRedCaptureFrameIndex;
@property(nonatomic, strong) NSSegmentedControl *languageControl;
@property(nonatomic) NSInteger detectedModeSegment;
@property(nonatomic) NSInteger candidateModeSegment;
@property(nonatomic) NSInteger candidateModeHits;
@property(nonatomic) BOOL captionPanelShownByUser;
@property(nonatomic) BOOL captionSuppressedForUIMode;
@property(nonatomic) BOOL selectingCaptureRegion;
@property(nonatomic, strong) NSTimer *overlayVisibilityTimer;
@property(nonatomic, strong) NSButton *captionHideButton;
@property(nonatomic, strong) NSSlider *regionXSlider;
@property(nonatomic, strong) NSSlider *regionYSlider;
@property(nonatomic, strong) NSSlider *regionWidthSlider;
@property(nonatomic, strong) NSSlider *regionHeightSlider;
@property(nonatomic, strong) NSSlider *intervalSlider;
@property(nonatomic, strong) NSSlider *captionOpacitySlider;
@property(nonatomic, strong) NSSlider *captionFontSizeSlider;
@property(nonatomic, strong) NSSlider *captionHeightSlider;
@property(nonatomic, strong) NSSegmentedControl *captionThemeControl;
@property(nonatomic, strong) NSButton *stableTextCheckbox;
@property(nonatomic, strong) NSButton *fastOCRCheckbox;
@property(nonatomic, strong) NSButton *autoFitRegionCheckbox;
@property(nonatomic, strong) NSTextField *baseURLField;
@property(nonatomic, strong) NSTextField *modelField;
@property(nonatomic, strong) NSTextField *realtimeModelField;
@property(nonatomic, strong) NSSecureTextField *apiKeyField;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSTextField *currentWindowLabel;
@property(nonatomic, strong) NSTextField *translationCountLabel;
@property(nonatomic, strong) NSButton *runButton;
@property(nonatomic, strong) NSTextField *runStateLabel;
@property(nonatomic, strong) NSTextField *headerTitleLabel;
@property(nonatomic, strong) NSTextField *ocrDurationLabel;
@property(nonatomic, strong) NSTextField *translationDurationLabel;
@property(nonatomic, strong) NSTextField *latestTranslationLabel;
@property(nonatomic, strong) NSTextField *latestSourceLabel;
@property(nonatomic, strong) NSTextField *liveErrorLabel;
@property(nonatomic, strong) NSTextField *themeSummaryLabel;
@property(nonatomic, strong) NSArray<NSButton *> *themeSwatches;
@property(nonatomic, strong) NSTextField *serviceStatusLabel;
@property(nonatomic, strong) NSTextField *serviceErrorLabel;
@property(nonatomic, strong) NSImageView *framePreview;
@property(nonatomic, strong) NSTextField *previewPlaceholder;
@property(nonatomic, strong) NSArray<NSView *> *pages;
@property(nonatomic, strong) NSArray<NSButton *> *pageButtons;
@property(nonatomic, strong) NSMutableArray<NSView *> *disclosureViews;
@property(nonatomic, strong) NSTimer *saveTimer;
@property(nonatomic, strong) NSDate *lastPreviewDate;
@property(nonatomic, strong) NSDate *lastWindowRecoveryAttemptDate;
@property(nonatomic) BOOL captureUnavailable;
@property(nonatomic) BOOL loadingSettings;
@property(nonatomic) NSInteger selectedPage;
@property(nonatomic) NSInteger serviceTestGeneration;

@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSURLSessionDataTask *activeTranslationTask;
@property(nonatomic) NSInteger translationGeneration;
@property(nonatomic) BOOL running;
@property(nonatomic) BOOL inFlight;
@property(nonatomic) BOOL screenAccessRequestedDuringSession;
@property(nonatomic) BOOL mainWindowVisibleBeforeRegionSelection;
@property(nonatomic) BOOL captionPanelVisibleBeforeRegionSelection;
@property(nonatomic) BOOL ocrPreviewVisibleBeforeRegionSelection;
@property(nonatomic, copy) NSString *lastTranslatedNormalizedText;
@property(nonatomic, copy) NSString *lastSubmittedNormalizedText;
@property(nonatomic, copy) NSString *dialogueTranslationCacheKey;
@property(nonatomic, copy) NSString *dialogueTranslationCacheValue;
@property(nonatomic, strong) NSDate *lastTranslationAttemptDate;
@property(nonatomic, copy) NSString *stableCandidate;
@property(nonatomic) NSInteger stableCandidateCount;
@property(nonatomic) NSInteger translationCount;
@property(nonatomic, strong) NSMutableArray<NSPanel *> *inlineTranslationPanels;
@property(nonatomic, strong) NSMutableArray<NSPanel *> *inlineLongCardPanels;
@property(nonatomic, copy) NSString *lastInlineTranslationKey;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *inlineTranslationCache;
// 自适应分组与布局：分组器、布局引擎、上一帧结果、按块身份复用的面板表。
@property(nonatomic, strong) FYInlineGrouper *inlineGrouper;
@property(nonatomic, strong) FYInlineLayoutEngine *inlineLayoutEngine;
@property(nonatomic, strong) FYInlineLayoutResult *lastInlineLayoutResult;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSPanel *> *inlinePanelsByBlockID;
// 最近一帧的降级统计（状态区提示用，不写字幕框）。
@property(nonatomic) NSUInteger lastInlineUnplaceableCount;
@property(nonatomic) NSUInteger lastInlineCompactEntryCount;
// 本帧「原始身份 → 布局稳定身份」映射：让选中判定/快照在任何调用点都用稳定身份。
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *inlineStableBlockIDs;
// 用户手动拖动过的贴译位置：键 = 文本 + 原文锚点的粗分桶（抖动不换键），值 = 相对锚点的偏移。
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *inlineManualOffsets;
// 连续多少帧没再看到这个块：超过上限就丢弃偏移，绝不继承给别的块。
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *inlineManualOffsetAge;
// 「界面译文」集中查看列表：暂不可放置/改用入口的译文都在这里完整可读（可滚动、不截断）。
@property(nonatomic, strong) NSView *inlineTranslationListCard;
@property(nonatomic, strong) NSStackView *inlineTranslationListStack;
@property(nonatomic, strong) NSTextField *inlineTranslationListCount;
@property(nonatomic, copy) NSArray<FYInlineBlockSnapshot *> *inlineTranslationListSnapshots;
@property(nonatomic, copy) NSString *inlineTranslationListSignature;
// 按住 Option 才允许拖动短贴片：定时读一次修饰键状态，避免要求辅助功能权限。
@property(nonatomic, strong) NSTimer *inlineModifierTimer;
@property(nonatomic) BOOL inlineOptionDragArmed;
@property(nonatomic, weak) NSPanel *inlineDraggingPanel;

// 日语学习模块
@property(nonatomic, strong) FYLearningStore *learningStore;
@property(nonatomic, strong) FYLearningAnalyzer *learningAnalyzer;
@property(nonatomic, strong) FYJapaneseTokenizer *japaneseTokenizer;
@property(nonatomic, strong) FYGrammarCatalog *grammarCatalog;
@property(nonatomic, strong) FYLearningCoordinator *learningCoordinator;
@property(nonatomic, strong) NSTextField *learningModelField;
@property(nonatomic, strong) FYSelectableSourceTextView *learningSourceTextView;
@property(nonatomic, strong) NSTextField *learningTranslationLabel;
@property(nonatomic, strong) NSTextField *learningPinnedLabel;
@property(nonatomic, strong) NSButton *pinSentenceButton;
@property(nonatomic, strong) NSButton *followLatestButton;
@property(nonatomic, strong) NSButton *analyzeButton;
@property(nonatomic, strong) NSTextField *grammarStatusLabel;
@property(nonatomic, strong) NSTextField *grammarResultsLabel;
@property(nonatomic, strong) NSPopUpButton *grammarSelector;
@property(nonatomic, strong) NSTextField *vocabularyListLabel;
@property(nonatomic, strong) NSTextField *vocabularyStatusLabel;
@property(nonatomic, strong) NSTextField *lemmaField;
@property(nonatomic, strong) NSTextField *readingField;
@property(nonatomic, strong) NSTextField *meaningField;
@property(nonatomic, strong) NSTextField *reviewPromptLabel;
@property(nonatomic, strong) NSTextField *grammarSourceLabel;
@property(nonatomic, strong) NSTextField *grammarFollowupResultLabel;
@property(nonatomic, strong) NSTextField *grammarQuestionField;
@property(nonatomic) BOOL learningAnalysisBusy;
@property(nonatomic, strong) NSLayoutConstraint *sourceReadingHeight;
@property(nonatomic, strong) NSStackView *sentenceInsightStack;
@property(nonatomic, strong) NSTextField *sentenceInsightLabel;
@property(nonatomic, strong) NSArray<NSControl *> *grammarFollowupControls;
@property(nonatomic, strong) NSStackView *grammarBookmarkStack;
@property(nonatomic, strong) NSStackView *grammarFollowupStack;
@property(nonatomic, strong) FYAnalysisResult *currentAnalysis;
@property(nonatomic, strong) NSTextField *vocabularySelectionLabel;
@property(nonatomic, strong) NSTextField *reviewWordLabel;
@property(nonatomic, strong) NSTextField *reviewMeaningLabel;
@property(nonatomic, strong) NSPopUpButton *historyPopup;
@property(nonatomic, strong) NSArray<FYSentenceRecord *> *historyRecords;
@property(nonatomic, copy) NSString *displayedSentenceID;
@property(nonatomic) NSInteger displayedVersion;
@property(nonatomic, copy) NSString *displayedSourceText;
@property(nonatomic, copy, nullable) NSString *displayedTranslation;
@property(nonatomic, strong) NSButton *revealButton;
@property(nonatomic, strong) NSButton *knownButton;
@property(nonatomic, strong) NSButton *notYetButton;
@property(nonatomic, strong) FYVocabularyEntry *reviewingEntry;
@property(nonatomic, strong) NSArray<FYVocabularyEntry *> *reviewList;
@property(nonatomic) NSInteger reviewIndex;
@property(nonatomic) BOOL vocabCompletionFromAI;
@property(nonatomic) NSInteger vocabSelectionGeneration;
@property(nonatomic, strong) NSButton *grammarPageAnalyzeButton;
@property(nonatomic, strong) NSTextField *grammarBookmarkListLabel;
@property(nonatomic, strong) NSPopUpButton *grammarBookmarkPopup;
@property(nonatomic, strong) NSArray<FYGrammarBookmark *> *grammarBookmarks;
@property(nonatomic, strong) NSTextField *vocabularyExamplesLabel;
@property(nonatomic, strong) NSPopUpButton *vocabularyExamplesPopup;
@property(nonatomic, strong) NSArray<FYVocabularyEntry *> *vocabularyExamplesList;
// UI 还原新增：卡片/词条确认/历史列表/词卡/语法详情两列
@property(nonatomic, strong) NSStackView *wordPickArea;
@property(nonatomic, strong) NSTextField *wordPickSurfaceLabel;
@property(nonatomic, strong) NSStackView *historyListStack;
@property(nonatomic, strong) NSStackView *wordCardStack;
@property(nonatomic, strong) NSTextField *grammarDetailNameLabel;
@property(nonatomic, strong) NSTextField *grammarDetailLevelLabel;
@property(nonatomic, strong) NSTextField *grammarDetailBodyLabel;
@property(nonatomic, strong) NSButton *grammarDetailBookmarkButton;
@property(nonatomic, strong) NSStackView *grammarOtherStack;
@property(nonatomic, strong) NSTextField *grammarOtherEmptyLabel;
@property(nonatomic) NSInteger selectedGrammarIndex;
@property(nonatomic, strong) NSTextView *grammarSourceTextView;
@property(nonatomic, strong) NSButton *grammarBackToSourceButton;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *revealedMeanings;
@property(nonatomic, strong) NSView *learningPageHost;
@property(nonatomic, strong) NSTextField *headerDescriptionLabel;
@property(nonatomic, strong) NSTextField *grammarPinnedLabel;
@property(nonatomic, strong) NSView *vocabularyEmptyCard;
@property(nonatomic) BOOL savingVocabulary;
@property(nonatomic) NSInteger analysisRequestGeneration;
@property(nonatomic) NSInteger followupRequestGeneration;
@property(nonatomic, strong) NSStackView *grammarDetailFields;
@property(nonatomic, strong) NSStackView *grammarUsageBlock;
@property(nonatomic, strong) NSButton *grammarFollowupToggle;
@property(nonatomic, strong) NSStackView *savedGrammarCardStack;
@property(nonatomic, strong) NSButton *grammarSourceLinkButton;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *wordExampleIndices;
@property(nonatomic) NSInteger wordCardsGeneration;
@end

@implementation AppDelegate

// 贴译相关的可变状态在 init 里就建好：既可以由 applicationDidFinishLaunching 复用，
// 也让「直接 alloc/init 的 AppDelegate」（隔离测试、命令行工具）不会拿到 nil 字典。
- (instancetype)init {
    self = [super init];
    if (self) {
        _inlineTranslationPanels = [NSMutableArray array];
        _inlineLongCardPanels = [NSMutableArray array];
        _inlinePanelsByBlockID = [NSMutableDictionary dictionary];
        _inlineManualOffsets = [NSMutableDictionary dictionary];
        _inlineManualOffsetAge = [NSMutableDictionary dictionary];
        _inlineStableBlockIDs = [NSMutableDictionary dictionary];
        _inlineTranslationCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)createApplicationMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *applicationItem = [[NSMenuItem alloc] initWithTitle:@"译芽" action:nil keyEquivalent:@""];
    NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@"译芽"];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出译芽" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    quit.target = NSApp;
    [applicationMenu addItem:quit];
    applicationItem.submenu = applicationMenu;
    [mainMenu addItem:applicationItem];
    NSMenuItem *editItem=[[NSMenuItem alloc] initWithTitle:@"编辑" action:nil keyEquivalent:@""];
    NSMenu *editMenu=[[NSMenu alloc] initWithTitle:@"编辑"];
    for(NSArray *command in @[@[@"撤销",@"undo:",@"z"],@[@"重做",@"redo:",@"Z"],@[@"剪切",@"cut:",@"x"],@[@"复制",@"copy:",@"c"],@[@"粘贴",@"paste:",@"v"],@[@"全选",@"selectAll:",@"a"]]){
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:command[0] action:NSSelectorFromString(command[1]) keyEquivalent:command[2]];
        item.keyEquivalentModifierMask=NSEventModifierFlagCommand; // nil target routes to the focused editor.
        [editMenu addItem:item];
    }
    editItem.submenu=editMenu;[mainMenu addItem:editItem];
    NSApp.mainMenu = mainMenu;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.globalShortcuts=[FYGlobalShortcuts new];
    __weak typeof(self) shortcutOwner=self;
    self.globalShortcuts.onAction=^(NSInteger action){
        typeof(self) owner=shortcutOwner;if(![owner translationTargetIsForeground]){return;}
        if(action==1){[owner toggleCaptionCollapsed:nil];}
        else if(action==2){owner.quickSentenceRequested?[owner closeStudyOverlay:nil]:[owner showQuickSentence:nil];}
        else if(action==3){owner.studyChatOverlayRequested?[owner closeStudyOverlay:nil]:[owner showStudyChatOverlay:nil];}
    };
    [self.globalShortcuts start];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self createApplicationMenu];
    self.windows = [NSMutableArray array];
    self.inlineTranslationPanels = [NSMutableArray array];
    self.inlineLongCardPanels = [NSMutableArray array];
    self.inlinePanelsByBlockID = [NSMutableDictionary dictionary];
    self.inlineManualOffsets = [NSMutableDictionary dictionary];
    self.inlineManualOffsetAge = [NSMutableDictionary dictionary];
    self.inlineStableBlockIDs = [NSMutableDictionary dictionary];
    self.inlineTranslationCache = [NSMutableDictionary dictionary];
    self.lastTranslatedNormalizedText = @"";
    self.lastSubmittedNormalizedText = @"";
    self.stableCandidate = @"";

    [self createMainWindow];
    [self createCaptionWindow];
    [self loadSettings];
    [self setupLearning];
    [self refreshWindows:nil];
    [self updateCaptionWindowWithText:@"" status:@"已暂停"];

    [self.mainWindow makeKeyAndOrderFront:nil];
    NSNotificationCenter *workspaceCenter = NSWorkspace.sharedWorkspace.notificationCenter;
    for (NSString *name in @[NSWorkspaceDidActivateApplicationNotification, NSWorkspaceDidHideApplicationNotification, NSWorkspaceActiveSpaceDidChangeNotification]) {
        [workspaceCenter addObserver:self selector:@selector(refreshOverlayVisibility:) name:name object:nil];
    }
    self.overlayVisibilityTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refreshOverlayVisibility:) userInfo:nil repeats:YES];
    [self refreshOverlayVisibility:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    if (!visible) {
        [self.mainWindow makeKeyAndOrderFront:nil];
        FYCrashLifecycle(@"reopened-window");
    }
    return YES;
}

#pragma mark - Learning setup

- (NSURL *)learningCatalogURL {
    return [[NSBundle mainBundle] URLForResource:@"grammar-catalog" withExtension:@"json" subdirectory:@"learning"];
}

- (void)setupLearning {
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *directory = [appSupport stringByAppendingPathComponent:@"com.nanami.fuyi"];
    NSString *databasePath = [directory stringByAppendingPathComponent:@"learning.sqlite3"];
    self.learningStore = [[FYLearningStore alloc] initWithDatabasePath:databasePath];
    [self.learningStore configureHistoryRetentionWithLimit:FYRecentSentenceLimit completion:^(NSError *error) {
        if (error) { self.grammarStatusLabel.stringValue = [NSString stringWithFormat:@"清理历史台词失败：%@", error.localizedDescription]; }
    }];
    [self.learningStore openWithCompletion:^(NSError *error) {
        if (error) { self.grammarStatusLabel.stringValue = [NSString stringWithFormat:@"学习数据库打开失败：%@", error.localizedDescription]; }
    }];

    self.learningAnalyzer = [[FYLearningAnalyzer alloc] init];
    [self syncLearningAnalyzerConfig];

    self.grammarCatalog = [[FYGrammarCatalog alloc] initWithURL:[self learningCatalogURL]];
    NSError *catalogError = nil;
    if (![self.grammarCatalog loadWithError:&catalogError]) {
        self.grammarStatusLabel.stringValue = [NSString stringWithFormat:@"等级资料加载失败：%@", catalogError.localizedDescription];
    }
    self.learningAnalyzer.catalog = self.grammarCatalog;

    self.japaneseTokenizer = [[FYJapaneseTokenizer alloc] init];
    self.learningCoordinator = [[FYLearningCoordinator alloc] initWithStore:self.learningStore
                                                                  analyzer:self.learningAnalyzer
                                                                 tokenizer:self.japaneseTokenizer
                                                                   catalog:self.grammarCatalog];
    __weak typeof(self) weakSelf = self;
    self.learningCoordinator.persistenceErrorHandler = ^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.grammarStatusLabel.stringValue = [NSString stringWithFormat:@"学习记录保存失败：%@", error.localizedDescription];
        });
    };
    self.learningCoordinator.learningEnabled = YES;
    [self refreshHistory];
    [self refreshVocabularyList];
    [self refreshGrammarBookmarks:nil];
}

- (void)syncLearningAnalyzerConfig {
    self.learningAnalyzer.baseURL = self.baseURLField.stringValue ?: @"";
    self.learningAnalyzer.apiKey = self.apiKeyField.stringValue ?: @"";
    NSString *learningModel = Trim(self.learningModelField.stringValue);
    if (learningModel.length == 0) { learningModel = Trim(self.modelField.stringValue); }
    self.learningAnalyzer.model = learningModel;
}

- (NSString *)bundledLicenseNotes {
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"LICENSE-NOTES" withExtension:@"txt" subdirectory:@"learning"];
    if (!url) {
        return @"未找到随包的资料说明文件（App 未正确打包 resources/learning）。";
    }
    NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:NULL];
    return text.length > 0 ? text : @"资料说明文件为空。";
}

- (NSScrollView *)makeLicenseNotesView {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,560,240)];
    scroll.identifier = @"reference-license-notes";
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.borderType = NSNoBorder;
    scroll.backgroundColor = FYAdventureColor(@"panel");
    NSTextView *text = [[NSTextView alloc] initWithFrame:scroll.contentView.bounds];
    text.editable = NO;
    text.selectable = YES;
    text.font = FYUIFont(13, NSFontWeightRegular);
    text.textColor = FYAdventureColor(@"ink");
    text.backgroundColor = scroll.backgroundColor;
    text.textContainerInset = NSMakeSize(12,12);
    text.minSize = NSMakeSize(0,0);
    text.maxSize = NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX);
    text.verticallyResizable = YES;
    text.horizontallyResizable = NO;
    text.autoresizingMask = NSViewWidthSizable;
    text.textContainer.containerSize = NSMakeSize(NSWidth(scroll.contentView.bounds),CGFLOAT_MAX);
    text.textContainer.widthTracksTextView = YES;
    text.accessibilityLabel = @"资料来源与许可正文";
    scroll.documentView = text;
    text.string = [self bundledLicenseNotes];
    [scroll.heightAnchor constraintEqualToConstant:240].active = YES;
    return scroll;
}

#pragma mark - UI

- (void)createMainWindow {
    self.mainWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(140, 120, 1320, 1000)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    self.mainWindow.title = @"译芽";
    self.mainWindow.backgroundColor = FYAdventureColor(@"shell");
    self.mainWindow.minSize = NSMakeSize(980, 660);
    self.mainWindow.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];

    NSStackView *root = [[NSStackView alloc] init];
    root.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    root.spacing = 0;
    // 收起侧栏时把隐藏的聊天视图从布局中摘除，释放出的宽度直接给中间内容，不留空白占位。
    root.detachesHiddenViews = YES;
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *sidebar = [self makeSidebar];
    NSView *right = [[NSView alloc] init];
    right.translatesAutoresizingMaskIntoConstraints = NO;
    right.wantsLayer = YES;
    right.layer.backgroundColor = FYAdventureColor(@"canvas").CGColor;
    NSView *header = [self makeRunHeader];
    NSView *pageHost = [[NSView alloc] init];
    pageHost.translatesAutoresizingMaskIntoConstraints = NO;
    [right addSubview:header];
    [right addSubview:pageHost];

    NSScrollView *livePage = [self makePageScrollWithContent:[self makeLivePage]];
    NSScrollView *historyPage = [self makePageScrollWithContent:[self makeHistoryPage]];
    NSScrollView *vocabularyPage = [self makePageScrollWithContent:[self makeVocabularyPage]];
    NSScrollView *runSettingsPage = [self makePageScrollWithContent:[self makeRunSettingsPage]];
    NSScrollView *appearancePage = [self makePageScrollWithContent:[self makeAppearancePage]];
    NSScrollView *servicePage = [self makePageScrollWithContent:[self translationCard]];
    self.pages = @[livePage, historyPage, vocabularyPage, runSettingsPage, appearancePage, servicePage];
    // Only the selected page participates in layout. Hidden settings pages must
    // not impose their intrinsic minimum width on a learning page.
    self.learningPageHost = pageHost;

    [root addArrangedSubview:sidebar];
    [root addArrangedSubview:right];
    self.mainStudyChatView=[self makeStudyChatViewForOverlay:NO];
    [root addArrangedSubview:self.mainStudyChatView];
    self.workspaceWidth=[right.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-510];
    self.mainChatWidth=[self.mainStudyChatView.widthAnchor constraintEqualToConstant:320];

    self.mainWorkspaceRoot=root;
    // Keep document fitting sizes from driving the outer window. The workspace
    // fills a frame-driven content host, so native edge resizing stays usable.
    NSView *windowHost=[[NSView alloc] initWithFrame:self.mainWindow.contentView.bounds];
    windowHost.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    windowHost.wantsLayer=YES;windowHost.layer.backgroundColor=FYAdventureColor(@"canvas").CGColor;
    FYAdventureBanner *banner=[FYAdventureBanner new];
    banner.translatesAutoresizingMaskIntoConstraints=NO;
    [windowHost addSubview:banner];
    [windowHost addSubview:root];
    [NSLayoutConstraint activateConstraints:@[[banner.leadingAnchor constraintEqualToAnchor:windowHost.leadingAnchor],
        [banner.trailingAnchor constraintEqualToAnchor:windowHost.trailingAnchor],
        [banner.topAnchor constraintEqualToAnchor:windowHost.topAnchor],
        [banner.heightAnchor constraintEqualToConstant:72]]];
    self.mainWindow.contentView = windowHost;
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:windowHost.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:windowHost.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:banner.bottomAnchor],
        [root.bottomAnchor constraintEqualToAnchor:windowHost.bottomAnchor],
        [sidebar.widthAnchor constraintEqualToConstant:190],
        self.workspaceWidth, self.mainChatWidth,
        [self.mainStudyChatView.heightAnchor constraintEqualToAnchor:root.heightAnchor],
        [right.heightAnchor constraintEqualToAnchor:root.heightAnchor],
        [sidebar.heightAnchor constraintEqualToAnchor:root.heightAnchor],
        [header.leadingAnchor constraintEqualToAnchor:right.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:right.trailingAnchor],
        [header.topAnchor constraintEqualToAnchor:right.topAnchor],
        [header.heightAnchor constraintEqualToConstant:88],
        [pageHost.leadingAnchor constraintEqualToAnchor:right.leadingAnchor],
        [pageHost.trailingAnchor constraintEqualToAnchor:right.trailingAnchor],
        [pageHost.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [pageHost.bottomAnchor constraintEqualToAnchor:right.bottomAnchor]
    ]];
    [self updateMainChatToggle];
    [self selectPageAtIndex:0];
}

- (NSView *)makeSidebar {
    FYAdventurePanel *view=[FYAdventurePanel new];view.fillColor=FYAdventureColor(@"shell");
    view.translatesAutoresizingMaskIntoConstraints=NO;
    NSStackView *stack=[NSStackView new];stack.orientation=NSUserInterfaceLayoutOrientationVertical;
    stack.alignment=NSLayoutAttributeLeading;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;
    [view addSubview:stack];
    NSMutableArray *buttons=[NSMutableArray array];
    for(NSString *name in @[@"实时翻译",@"最近台词",@"单词学习",@"运行设置",@"字幕外观",@"翻译服务"]){
        if(buttons.count==3){NSView *line=[self separator];[stack addArrangedSubview:line];[line.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;}
        FYWorkspaceButton *button=[FYWorkspaceButton buttonWithTitle:name target:self action:@selector(selectPage:)];
        button.tag=buttons.count;button.navigation=YES;button.artworkIndex=buttons.count;
        button.bordered=NO;button.font=FYUIFont(15, NSFontWeightSemibold);
        button.accessibilityLabel=name;
        [stack addArrangedSubview:button];[button.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
        [button.heightAnchor constraintEqualToConstant:48].active=YES;[buttons addObject:button];
    }
    self.pageButtons=buttons;
    FYAdventureArtView *tree=[FYAdventureArtView new];tree.artwork=8;tree.translatesAutoresizingMaskIntoConstraints=NO;
    [view addSubview:tree];
    self.serviceStatusLabel=[self label:@"服务未测试" font:FYUIFont(11, NSFontWeightRegular) color:FYAdventureColor(@"quiet")];
    [view addSubview:self.serviceStatusLabel];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:view.topAnchor constant:24],
        [tree.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:10],
        [tree.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-10],
        [tree.bottomAnchor constraintEqualToAnchor:self.serviceStatusLabel.topAnchor constant:-10],
        [tree.topAnchor constraintGreaterThanOrEqualToAnchor:stack.bottomAnchor constant:12],
        [tree.heightAnchor constraintGreaterThanOrEqualToConstant:0],
        [self.serviceStatusLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:16],
        [self.serviceStatusLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-16],
        [self.serviceStatusLabel.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-16]]];
    NSLayoutConstraint *treeHeight=[tree.heightAnchor constraintEqualToConstant:166];treeHeight.priority=749;treeHeight.active=YES;
    return view;
}

- (NSView *)makeRunHeader {
    NSView *header = [[NSView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    NSStackView *content = [self horizontalStack];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:content];
    NSStackView *titles = [self verticalStack];
    titles.spacing = 4;
    self.headerTitleLabel = [self label:@"实时翻译" font:FYUIFont(27, NSFontWeightSemibold) color:[NSColor labelColor]];
    [titles addArrangedSubview:self.headerTitleLabel];
    self.headerDescriptionLabel = [self mutedLabel:@"画面、原句与学习入口放在一起"];
    [titles addArrangedSubview:self.headerDescriptionLabel];
    self.currentWindowLabel = [self label:@"当前窗口：未选择" font:FYUIFont(12, NSFontWeightRegular) color:[NSColor secondaryLabelColor]];
    self.currentWindowLabel.maximumNumberOfLines = 1;
    self.currentWindowLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [titles.widthAnchor constraintGreaterThanOrEqualToConstant:140].active = YES;
    self.headerDescriptionLabel.maximumNumberOfLines = 1;
    self.headerDescriptionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.headerDescriptionLabel setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [content addArrangedSubview:titles];
    [content addArrangedSubview:[self spacer]];
    self.runStateLabel = [self label:@"● 已暂停" font:FYUIFont(12, NSFontWeightSemibold) color:[NSColor secondaryLabelColor]];
    self.runStateLabel.maximumNumberOfLines=1;
    [self.runStateLabel setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [content addArrangedSubview:self.runStateLabel];
    self.runButton = [self workspaceButton:@"开始翻译" action:@selector(toggleRunning:) primary:YES];
    self.runButton.bezelStyle = NSBezelStyleRounded;
    self.runButton.bezelColor = self.uiAccent;
    self.runButton.contentTintColor = NSColor.whiteColor;
    [content addArrangedSubview:self.runButton];
    // 唯一的 AI 侧栏显隐开关：固定在主内容区头部（不随内容滚动、不属于侧栏），
    // 收起后依然可见，窄窗口下也不会被挤掉。
    self.mainChatToggle=[self workspaceButton:@"收起 AI 伙伴" action:@selector(toggleMainStudyChat:) primary:NO];
    self.mainChatToggle.accessibilityLabel=@"显示或隐藏 AI 伙伴侧栏";
    [self.mainChatToggle setContentHuggingPriority:999 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.mainChatToggle setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [content addArrangedSubview:self.mainChatToggle];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [content.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [content.centerYAnchor constraintEqualToAnchor:header.centerYAnchor]
    ]];
    return header;
}

- (NSScrollView *)makePageScrollWithContent:(NSView *)content {
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    NSView *document = [[FlippedDocumentView alloc] init];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = document;
    [document addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:16],
        [content.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-16],
        [content.topAnchor constraintEqualToAnchor:document.topAnchor constant:8],
        [content.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-16],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor]
    ]];
    return scroll;
}

- (void)selectPage:(NSButton *)sender {
    [self selectPageAtIndex:sender.tag];
}

- (void)selectPageAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.pages.count) { return; }
    if (self.pages[index].superview != self.learningPageHost) {
        for (NSView *page in self.pages) { [page removeFromSuperview]; }
        NSView *page = self.pages[index];
        page.translatesAutoresizingMaskIntoConstraints = NO;
        [self.learningPageHost addSubview:page];
        [NSLayoutConstraint activateConstraints:@[
            [page.leadingAnchor constraintEqualToAnchor:self.learningPageHost.leadingAnchor],
            [page.trailingAnchor constraintEqualToAnchor:self.learningPageHost.trailingAnchor],
            [page.topAnchor constraintEqualToAnchor:self.learningPageHost.topAnchor],
            [page.bottomAnchor constraintEqualToAnchor:self.learningPageHost.bottomAnchor]
        ]];
    }
    self.selectedPage = index;
    if (index != 4) { [self.captionAppearancePreviewPanel orderOut:nil]; }
    self.headerTitleLabel.stringValue = @[@"实时翻译", @"最近台词", @"单词学习", @"运行设置", @"字幕外观", @"翻译服务"][index];
    self.headerDescriptionLabel.stringValue = @[@"读懂当前对白，再看懂它的语法。", @"把之前没看懂的对白，再读一遍。", @"收藏词语，带着原句复习", @"选择画面来源并调整识别方式", @"调整悬浮字幕的阅读体验", @"配置翻译与学习分析服务"][index];
    self.currentWindowLabel.hidden = index != 0;
    if (index == 1) { [self refreshHistory]; }
    if (index == 2) { [self refreshVocabularyList]; }
    for (NSInteger i = 0; i < self.pages.count; i++) {
        self.pages[i].hidden = i != index;
        self.pageButtons[i].state = i == index ? NSControlStateValueOn : NSControlStateValueOff;
        self.pageButtons[i].needsDisplay = YES;
    }
}

- (NSView *)makeLivePage {
    NSStackView *page = [self verticalStack];
    page.spacing = 16;
    page.alignment = NSLayoutAttributeWidth;

    // 1) 游戏实时画面区
    NSStackView *screen = [self verticalStack];
    screen.spacing = 12;
    NSStackView *screenHeader = [self horizontalStack];
    [screenHeader addArrangedSubview:[self cardTitle:@"实时画面"]];
    [screenHeader addArrangedSubview:[self spacer]];
    [screenHeader addArrangedSubview:self.currentWindowLabel];
    [screen addArrangedSubview:screenHeader];

    NSView *previewShadow = [[NSView alloc] init];
    previewShadow.wantsLayer = YES;
    previewShadow.layer.backgroundColor = NSColor.clearColor.CGColor;
    previewShadow.layer.cornerRadius = 12;
    previewShadow.layer.shadowColor = FYAdventureColor(@"line").CGColor;
    previewShadow.layer.shadowOpacity = 0.35;
    previewShadow.layer.shadowRadius = 10;
    previewShadow.layer.shadowOffset = CGSizeMake(0, -3);
    NSView *preview = [[NSView alloc] init];
    preview.wantsLayer = YES;
    preview.layer.backgroundColor = FYAdventureColor(@"reading").CGColor;
    preview.layer.cornerRadius = 12;
    preview.layer.masksToBounds = YES;
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    [previewShadow addSubview:preview];
    [NSLayoutConstraint activateConstraints:@[
        [preview.leadingAnchor constraintEqualToAnchor:previewShadow.leadingAnchor],
        [preview.trailingAnchor constraintEqualToAnchor:previewShadow.trailingAnchor],
        [preview.topAnchor constraintEqualToAnchor:previewShadow.topAnchor],
        [preview.bottomAnchor constraintEqualToAnchor:previewShadow.bottomAnchor]]];
    FYCapturePreviewView *capturePreview = [[FYCapturePreviewView alloc] init];
    self.framePreview = capturePreview;
    self.framePreview.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self.framePreview setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.framePreview setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    self.framePreview.translatesAutoresizingMaskIntoConstraints = NO;
    [preview addSubview:self.framePreview];
    self.previewPlaceholder = [self label:@"选择窗口并开始翻译后显示画面" font:FYUIFont(13, NSFontWeightRegular) color:self.uiMuted];
    [preview addSubview:self.previewPlaceholder];
    [screen addArrangedSubview:previewShadow];
    [previewShadow.heightAnchor constraintGreaterThanOrEqualToConstant:1].active = YES;
    [previewShadow.heightAnchor constraintLessThanOrEqualToConstant:480].active = YES;
    NSLayoutConstraint *preferredPreviewHeight = [previewShadow.heightAnchor constraintEqualToConstant:480];
    preferredPreviewHeight.priority = 500;
    preferredPreviewHeight.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [self.framePreview.leadingAnchor constraintEqualToAnchor:preview.leadingAnchor],
        [self.framePreview.trailingAnchor constraintEqualToAnchor:preview.trailingAnchor],
        [self.framePreview.topAnchor constraintEqualToAnchor:preview.topAnchor],
        [self.framePreview.bottomAnchor constraintEqualToAnchor:preview.bottomAnchor],
        [self.previewPlaceholder.centerXAnchor constraintEqualToAnchor:preview.centerXAnchor],
        [self.previewPlaceholder.centerYAnchor constraintEqualToAnchor:preview.centerYAnchor]]];
    // 「翻译当前界面」入口已移除：它会把整屏文字汇总到字幕框，不符合实时翻译流程。
    // 只移除入口；截图 / OCR / 翻译方法仍被其他地方使用，保持不动。
    // 状态胶囊对象保留（refreshLiveChips 仍引用），只是不再排进布局。
    self.liveChipRecognition = [self chipLabel:@"识别中"];
    self.liveChipAutoTranslate = [self chipLabel:@"自动翻译"];
    self.liveChipPauseFollow = [self chipLabel:@"暂停跟读"];
    NSStackView *metrics = [self horizontalStack];
    self.ocrDurationLabel = [self label:@"最近识别 —" font:FYUIFont(12, NSFontWeightRegular) color:self.uiMuted];
    self.translationDurationLabel = [self label:@"翻译耗时 —" font:FYUIFont(12, NSFontWeightRegular) color:self.uiMuted];
    self.translationCountLabel = [self label:@"翻译轮次 0" font:FYUIFont(12, NSFontWeightRegular) color:self.uiMuted];
    [metrics addArrangedSubview:self.ocrDurationLabel];
    [metrics addArrangedSubview:self.translationDurationLabel];
    [metrics addArrangedSubview:self.translationCountLabel];
    metrics.hidden = YES;
    self.liveErrorLabel = [self label:@"" font:FYUIFont(12, NSFontWeightRegular) color:[NSColor systemRedColor]];
    self.liveErrorLabel.maximumNumberOfLines = 2;
    self.liveErrorLabel.hidden = YES;
    [screen addArrangedSubview:self.liveErrorLabel];
    [page addArrangedSubview:[self cardWithStack:screen]];

    // 2) 当前对白卡片
    NSStackView *sentence = [self verticalStack];
    sentence.spacing = 12;
    NSStackView *sentenceTitleRow = [self horizontalStack];
    [sentenceTitleRow addArrangedSubview:[self mutedLabel:@"当前对白"]];
    [sentenceTitleRow addArrangedSubview:[self spacer]];
    self.liveLevelTag = [self chipLabel:@"N3"];
    self.liveLevelTag.hidden = YES;
    [sentenceTitleRow addArrangedSubview:self.liveLevelTag];
    [sentence addArrangedSubview:sentenceTitleRow];
    NSScrollView *learningScroll = [[NSScrollView alloc] init];
    self.learningSourceTextView = [[FYSelectableSourceTextView alloc] init];
    FYConfigureSourceTextView(self.learningSourceTextView, learningScroll, 20);
    NSMutableParagraphStyle *sourceStyle = [NSMutableParagraphStyle new]; sourceStyle.lineSpacing = 7;
    self.learningSourceTextView.defaultParagraphStyle = sourceStyle;
    [sentence addArrangedSubview:learningScroll];
    self.sourceReadingHeight = [learningScroll.heightAnchor constraintEqualToConstant:48];
    self.sourceReadingHeight.active = YES;
    __weak typeof(self) weakSelf = self;
    self.learningSourceTextView.willBeginSelection = ^{ [weakSelf freezeLearningSentenceForSelection]; };
    self.learningSourceTextView.didFinishSelection = ^{ [weakSelf updateWordPickForSelection]; };
    self.learningSourceTextView.didClickAtCharacterIndex = ^(NSUInteger characterIndex) {
        [weakSelf selectWordAtCharacterIndex:characterIndex];
    };
    [[NSNotificationCenter defaultCenter] addObserverForName:NSTextViewDidChangeSelectionNotification
                                                      object:self.learningSourceTextView
                                                       queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(NSNotification *note) {
        if (weakSelf.learningSourceTextView.trackingSelection) { return; }
        weakSelf.lemmaField.stringValue = @"";
        weakSelf.readingField.stringValue = @"";
        weakSelf.meaningField.stringValue = @"";
        weakSelf.vocabCompletionFromAI = NO;
        weakSelf.vocabSelectionGeneration += 1;
        [weakSelf updateWordPickForSelection];
    }];
    [sentence addArrangedSubview:[self label:@"点击选词，或按住拖拽选择词语／短语" font:FYUIFont(11, NSFontWeightRegular) color:self.uiMuted]];
    // 固定此句 / 跟随最新：真正可点击的入口。
    // 未固定显示「固定此句」；固定后显示「跟随最新」，点击解除固定并切回最新识别内容。
    // 固定期间有新台词由 learningPinnedLabel 提示「已固定 · 有新台词」。
    NSStackView *sentenceActions = [self horizontalStack];
    sentenceActions.spacing = 10;
    self.pinSentenceButton = [self workspaceButton:@"固定此句" action:@selector(toggleLearningPin:) primary:NO];
    self.pinSentenceButton.bezelStyle = NSBezelStyleRounded;
    self.followLatestButton = [NSButton buttonWithTitle:@"跟随最新" target:self action:@selector(followLatestSentence:)];
    self.followLatestButton.bezelStyle = NSBezelStyleRounded;
    self.followLatestButton.hidden = YES;
    self.learningPinnedLabel = [self mutedLabel:@"跟随最新"];
    [sentenceActions addArrangedSubview:self.pinSentenceButton];
    [sentenceActions addArrangedSubview:self.learningPinnedLabel];
    [sentenceActions addArrangedSubview:[self spacer]];
    [sentence addArrangedSubview:sentenceActions];
    self.wordPickArea = [self verticalStack];
    self.wordPickArea.spacing = 10;
    self.wordPickArea.hidden = YES;
    NSStackView *pickTitleRow = [self horizontalStack];
    self.wordPickSurfaceLabel = [self label:@"" font:FYUIFont(15, NSFontWeightBold) color:self.uiInk];
    [pickTitleRow addArrangedSubview:self.wordPickSurfaceLabel];
    [pickTitleRow addArrangedSubview:[self spacer]];
    NSButton *pickClose = [NSButton buttonWithTitle:@"关闭" target:self action:@selector(closeWordPick:)];
    pickClose.bezelStyle = NSBezelStyleRounded;
    [pickTitleRow addArrangedSubview:pickClose];
    [self.wordPickArea addArrangedSubview:pickTitleRow];
    self.lemmaField = [self textField:@"原形（可留空）"];
    self.readingField = [self textField:@"读音（可留空）"];
    self.meaningField = [self textField:@"释义（可留空）"];
    for (NSTextField *field in @[self.lemmaField, self.readingField, self.meaningField]) {
        field.action = @selector(vocabularyFormChanged:);
    }
    [self.wordPickArea addArrangedSubview:[self rowWithLabel:@"原形" view:self.lemmaField]];
    [self.wordPickArea addArrangedSubview:[self rowWithLabel:@"读音" view:self.readingField]];
    [self.wordPickArea addArrangedSubview:[self rowWithLabel:@"释义" view:self.meaningField]];
    self.vocabularySelectionLabel = [self label:@"" font:FYUIFont(12, NSFontWeightRegular) color:self.uiMuted];
    [self.wordPickArea addArrangedSubview:self.vocabularySelectionLabel];
    NSStackView *pickButtons = [self horizontalStack];
    NSButton *completeWord = [NSButton buttonWithTitle:@"补全读音与释义" target:self action:@selector(completeSelectedVocabulary:)];
    completeWord.bezelStyle = NSBezelStyleRounded;
    NSButton *saveWord = [NSButton buttonWithTitle:@"收藏词条" target:self action:@selector(bookmarkSelectedVocabulary:)];
    saveWord.bezelStyle = NSBezelStyleRounded;
    [pickButtons addArrangedSubview:completeWord];
    [pickButtons addArrangedSubview:saveWord];
    [self.wordPickArea addArrangedSubview:pickButtons];
    self.vocabularyStatusLabel = [self label:@"" font:FYUIFont(12, NSFontWeightRegular) color:self.uiMuted];
    [self.wordPickArea addArrangedSubview:self.vocabularyStatusLabel];
    [sentence addArrangedSubview:self.wordPickArea];
    NSView *sourceCard = [self cardWithStack:sentence];
    ((FYAdventurePanel *)sourceCard).fillColor = FYAdventureColor(@"paper");
    ((FYAdventurePanel *)sourceCard).edgeColor = FYAdventureColor(@"line");
    [page addArrangedSubview:sourceCard];

    // 3) 中文翻译卡片
    NSStackView *translationBlock = [self verticalStack];
    translationBlock.spacing = 12;
    NSStackView *translationTitleRow = [self horizontalStack];
    [translationTitleRow addArrangedSubview:[self mutedLabel:@"中文翻译"]];
    [translationTitleRow addArrangedSubview:[self spacer]];
    [translationBlock addArrangedSubview:translationTitleRow];
    self.learningTranslationLabel = [self label:@"（暂无译文）" font:FYUIFont(16, NSFontWeightRegular) color:self.uiInk];
    self.learningTranslationLabel.selectable = YES;
    self.learningTranslationLabel.maximumNumberOfLines = 8;
    self.learningTranslationLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [translationBlock addArrangedSubview:self.learningTranslationLabel];
    NSView *translationCardOuter = [self cardWithStack:translationBlock];
    ((FYAdventurePanel *)translationCardOuter).fillColor = FYAdventureColor(@"cream");
    ((FYAdventurePanel *)translationCardOuter).edgeColor = FYAdventureColor(@"line");
    [page addArrangedSubview:translationCardOuter];

    [page addArrangedSubview:[self makeInlineTranslationListCard]];

    [page addArrangedSubview:[self makeIntegratedGrammarCard]];
    return page;
}

// 「界面译文」集中查看：画面里放不下的贴译（暂不可放置 / 改用紧凑入口）在这里全部列出，
// 每条保留原文、完整译文与稳定块身份，并可一键打开该块的原文与语法。
// 没有需要集中查看的内容时整张卡片隐藏，不影响正常画面与截图。
- (NSView *)makeInlineTranslationListCard {
    NSStackView *block = [self verticalStack];
    block.spacing = 10;
    NSStackView *titleRow = [self horizontalStack];
    [titleRow addArrangedSubview:[self mutedLabel:@"界面译文"]];
    [titleRow addArrangedSubview:[self spacer]];
    self.inlineTranslationListCount = [self mutedLabel:@""];
    [titleRow addArrangedSubview:self.inlineTranslationListCount];
    [block addArrangedSubview:titleRow];

    self.inlineTranslationListStack = [self verticalStack];
    self.inlineTranslationListStack.spacing = 10;
    NSScrollView *listScroll = [self makePageScrollWithContent:self.inlineTranslationListStack];
    [listScroll.heightAnchor constraintEqualToConstant:220].active = YES;
    [block addArrangedSubview:listScroll];
    [self pinFullWidth:listScroll toStack:block];

    NSView *card = [self cardWithStack:block];
    card.hidden = YES;
    self.inlineTranslationListCard = card;
    self.inlineTranslationListSnapshots = @[];
    self.inlineTranslationListSignature = @"";
    return card;
}

// 重建集中查看列表。签名相同就不重建，避免每帧重排整页。
- (void)refreshInlineTranslationList {
    if (!self.inlineTranslationListStack || !self.inlineTranslationListCard) { return; }
    NSMutableArray<FYInlinePlacement *> *degraded = [NSMutableArray array];
    NSUInteger unplaceable = 0;
    for (FYInlinePlacement *placement in self.lastInlineLayoutResult.placements) {
        if (Trim(placement.translation).length == 0) { continue; }
        BOOL isUnplaceable = placement.mode == FYInlineDisplayModeUnplaceable;
        BOOL isCompact = placement.mode == FYInlineDisplayModeCompactEntry;
        if (!isUnplaceable && !isCompact) { continue; }
        if (isUnplaceable) { unplaceable += 1; }
        [degraded addObject:placement];
    }
    NSMutableString *signature = [NSMutableString string];
    for (FYInlinePlacement *placement in degraded) {
        [signature appendFormat:@"%@|%ld|%@\n", placement.blockID, (long)placement.mode, placement.translation];
    }
    self.inlineTranslationListCard.hidden = degraded.count == 0;
    if (degraded.count == 0) {
        if (self.inlineTranslationListSignature.length == 0) { return; }
        self.inlineTranslationListSignature = @"";
        self.inlineTranslationListSnapshots = @[];
        [self clearArrangedSubviews:self.inlineTranslationListStack];
        return;
    }
    if ([self.inlineTranslationListSignature isEqualToString:signature]) { return; }
    self.inlineTranslationListSignature = [signature copy];
    [self clearArrangedSubviews:self.inlineTranslationListStack];
    self.inlineTranslationListCount.stringValue = unplaceable > 0
        ? [NSString stringWithFormat:@"%lu 条暂不可放置 · %lu 条用入口", (unsigned long)unplaceable,
           (unsigned long)(degraded.count - unplaceable)]
        : [NSString stringWithFormat:@"%lu 条改用「查看译文」入口", (unsigned long)degraded.count];

    NSMutableArray<FYInlineBlockSnapshot *> *snapshots = [NSMutableArray array];
    for (FYInlinePlacement *placement in degraded) {
        NSStackView *row = [self verticalStack];
        row.spacing = 6;
        NSTextField *sourceLabel = [self label:placement.block.text font:FYUIFont(13, NSFontWeightRegular) color:self.uiMuted];
        sourceLabel.maximumNumberOfLines = 3;
        [row addArrangedSubview:sourceLabel];
        NSTextField *translationLabel = [self label:placement.translation font:FYUIFont(15, NSFontWeightRegular) color:self.uiInk];
        translationLabel.selectable = YES;
        translationLabel.maximumNumberOfLines = 6;
        [row addArrangedSubview:translationLabel];

        NSStackView *footer = [self horizontalStack];
        NSString *tag = placement.mode == FYInlineDisplayModeUnplaceable ? @"暂不可放置" : @"已改为「查看译文」入口";
        [footer addArrangedSubview:[self mutedLabel:[NSString stringWithFormat:@"%@ · 原因：%@", tag, placement.reason ?: @""]]];
        [footer addArrangedSubview:[self spacer]];
        NSButton *open = [self workspaceButton:@"查看原文和语法" action:@selector(openInlineTranslationRow:) primary:NO];
        open.tag = (NSInteger)snapshots.count;
        [footer addArrangedSubview:open];
        [row addArrangedSubview:footer];

        NSView *rowCard = [self cardWithStack:row];
        [self.inlineTranslationListStack addArrangedSubview:rowCard];
        [self pinFullWidth:rowCard toStack:self.inlineTranslationListStack];
        [snapshots addObject:[self inlineSnapshotForBlock:placement.block
                                              translation:placement.translation
                                            stableBlockID:placement.blockID]];
    }
    self.inlineTranslationListSnapshots = snapshots;
}

- (void)openInlineTranslationRow:(NSButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)self.inlineTranslationListSnapshots.count) { return; }
    [self openInlineLearningWithSnapshot:self.inlineTranslationListSnapshots[(NSUInteger)index]];
}

- (NSView *)makeRunSettingsPage {
    NSStackView *page = [self verticalStack];
    page.spacing = 14;
    NSStackView *settings = [self verticalStack];
    settings.spacing = 10;
    [settings addArrangedSubview:[self cardTitle:@"识别与画面来源"]];
    [settings addArrangedSubview:[self recognitionCard]];
    [settings addArrangedSubview:[self windowCard]];
    [page addArrangedSubview:[self cardWithStack:settings]];

    NSStackView *status = [self verticalStack];
    [status addArrangedSubview:[self cardTitle:@"运行状态"]];
    self.statusLabel = [self label:@"已暂停" font:FYUIFont(12, NSFontWeightRegular) color:self.uiMuted];
    self.statusLabel.maximumNumberOfLines = 2;
    [status addArrangedSubview:self.statusLabel];
    [status addArrangedSubview:self.ocrDurationLabel];
    [status addArrangedSubview:self.translationDurationLabel];
    [status addArrangedSubview:self.translationCountLabel];
    [status addArrangedSubview:[self separator]];
    [status addArrangedSubview:[self permissionControls]];
    [page addArrangedSubview:[self cardWithStack:status]];
    return page;
}

- (NSView *)makeAppearancePage {
    NSStackView *page = [self verticalStack];
    NSStackView *appearance = [self verticalStack];
    appearance.spacing = 10;
    [appearance addArrangedSubview:[self cardTitle:@"悬浮字幕"]];
    [appearance addArrangedSubview:[self captionCard]];
    [appearance addArrangedSubview:[self workspaceButton:@"打开字幕预览" action:@selector(showCaptionAppearancePreview:) primary:NO]];
    [appearance addArrangedSubview:[self mutedLabel:@"预览使用示例文字，调整字号、配色和透明度会即时更新。"]];
    [appearance addArrangedSubview:[self mutedLabel:@"字幕仅在选中的 QuickTime／游戏应用位于前台时显示；切到其他应用会自动隐藏。"]];
    NSStackView *styleRow = [self horizontalStack];
    [styleRow addArrangedSubview:[self mutedLabel:@"配色"]];
    NSMutableArray<NSButton *> *swatches = [NSMutableArray array];
    NSArray<NSColor *> *colors = @[[NSColor colorWithWhite:0.15 alpha:1], [NSColor whiteColor],
                                  [NSColor colorWithRed:0.94 green:0.68 blue:0.78 alpha:1], FYAdventureColor(@"shell")];
    NSArray<NSString *> *names = @[@"黑底白字", @"白底黑字", @"粉底深字", @"译芽花境"];
    for (NSInteger index = 0; index < colors.count; index++) {
        NSButton *button = [NSButton buttonWithTitle:@"" target:self action:@selector(selectCaptionSwatch:)];
        button.tag = index;
        button.bordered = NO;
        button.wantsLayer = YES;
        button.layer.cornerRadius = 10;
        button.layer.backgroundColor = colors[index].CGColor;
        button.layer.borderWidth = 2;
        button.toolTip = names[index];
        [button.widthAnchor constraintEqualToConstant:22].active = YES;
        [button.heightAnchor constraintEqualToConstant:22].active = YES;
        [styleRow addArrangedSubview:button];
        [swatches addObject:button];
    }
    self.themeSwatches = swatches;
    self.themeSummaryLabel = [self label:@"30 pt / 58%" font:FYUIFont(12, NSFontWeightRegular) color:self.uiMuted];
    [styleRow addArrangedSubview:self.themeSummaryLabel];
    [appearance addArrangedSubview:styleRow];
    [page addArrangedSubview:[self cardWithStack:appearance]];

    return page;
}

- (void)focusWindowSelection:(id)sender {
    [self selectPageAtIndex:3];
    [self.mainWindow makeFirstResponder:self.windowPopup];
    [self.windowPopup performClick:nil];
}

#include "FYWorkspaceUI.inc"
#include "FYReferenceUI.inc"
#include "FYSourceHoverUI.inc"
#include "FYImmersiveUI.inc"

- (NSView *)makeVocabularyPage {
    NSStackView *page = [self verticalStack];
    page.spacing = 14;

    NSStackView *header = [self horizontalStack];
    NSStackView *titleCol = [self verticalStack];
    titleCol.spacing = 4;
    self.learningCollectionTitle=[self label:@"从原句留下来的词" font:FYUIFont(20, NSFontWeightSemibold) color:self.uiInk];
    [titleCol addArrangedSubview:self.learningCollectionTitle];
    self.learningCollectionCount=[self mutedLabel:@"0 个收藏"];
    [titleCol addArrangedSubview:self.learningCollectionCount];
    [titleCol.widthAnchor constraintGreaterThanOrEqualToConstant:210].active=YES;
    [header addArrangedSubview:titleCol];
    [header addArrangedSubview:[self spacer]];
    NSButton *goPick = [self workspaceButton:@"选词收藏" action:@selector(backToSourcePage:) primary:NO];
    [header addArrangedSubview:goPick];
    [page addArrangedSubview:header];

    NSStackView *tabs=[self horizontalStack];tabs.spacing=8;
    NSMutableArray *tabButtons=[NSMutableArray new];
    NSArray *tabTitles=@[@"词语",@"语法",@"句子",@"复习"];
    for(NSInteger index=0;index<4;index++){
        NSButton *button=[self workspaceButton:tabTitles[index] action:@selector(selectLearningCollection:) primary:NO];
        button.tag=index;[tabs addArrangedSubview:button];[tabButtons addObject:button];
    }
    self.learningCollectionTabs=tabButtons;[page addArrangedSubview:tabs];
    self.learningCollectionHost=[self verticalStack];[page addArrangedSubview:self.learningCollectionHost];
    NSStackView *words=[self verticalStack];words.spacing=12;

    self.vocabularyListLabel = [self label:@"暂无收藏" font:FYUIFont(13, NSFontWeightRegular) color:self.uiMuted];
    self.vocabularyListLabel.maximumNumberOfLines = 0;
    self.vocabularyListLabel.lineBreakMode = NSLineBreakByWordWrapping;
    NSStackView *empty = [self verticalStack];
    [empty addArrangedSubview:self.vocabularyListLabel];
    self.vocabularyEmptyCard = [self cardWithStack:empty];
    self.vocabularyListLabel.alignment = NSTextAlignmentCenter;
    [words addArrangedSubview:self.vocabularyEmptyCard];

    self.wordCardStack = [self verticalStack];
    self.wordCardStack.spacing = 12;
    [words addArrangedSubview:self.wordCardStack];

    // —— 简单复习（辅助入口）——
    NSStackView *reviewCard = [self verticalStack];
    reviewCard.spacing = 10;
    [reviewCard addArrangedSubview:[self cardTitle:@"简单复习"]];
    self.reviewPromptLabel = [self mutedLabel:@"点「下一个词」开始遮义复习"];
    [reviewCard addArrangedSubview:self.reviewPromptLabel];
    self.reviewWordLabel = [self label:@"" font:FYUIFont(18, NSFontWeightBold) color:self.uiInk];
    self.reviewWordLabel.hidden = YES;
    [reviewCard addArrangedSubview:self.reviewWordLabel];
    self.reviewMeaningLabel = [self label:@"" font:FYUIFont(13, NSFontWeightRegular) color:self.uiInk];
    self.reviewMeaningLabel.maximumNumberOfLines = 0;
    self.reviewMeaningLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.reviewMeaningLabel.hidden = YES;
    [reviewCard addArrangedSubview:self.reviewMeaningLabel];
    NSStackView *reviewButtons = [self horizontalStack];
    self.revealButton = [NSButton buttonWithTitle:@"揭晓释义" target:self action:@selector(revealReviewMeaning:)];
    self.revealButton.bezelStyle = NSBezelStyleRounded;
    self.knownButton = [NSButton buttonWithTitle:@"记住了" target:self action:@selector(markReviewKnown:)];
    self.knownButton.bezelStyle = NSBezelStyleRounded;
    self.notYetButton = [NSButton buttonWithTitle:@"还不熟" target:self action:@selector(markReviewLearning:)];
    self.notYetButton.bezelStyle = NSBezelStyleRounded;
    NSButton *nextWord = [NSButton buttonWithTitle:@"下一个词" target:self action:@selector(nextReviewWord:)];
    nextWord.bezelStyle = NSBezelStyleRounded;
    NSButton *removeWord = [NSButton buttonWithTitle:@"取消收藏" target:self action:@selector(removeReviewWord:)];
    removeWord.bezelStyle = NSBezelStyleRounded;
    [reviewButtons addArrangedSubview:self.revealButton];
    [reviewButtons addArrangedSubview:self.knownButton];
    [reviewButtons addArrangedSubview:self.notYetButton];
    [reviewCard addArrangedSubview:reviewButtons];
    NSStackView *reviewNavigation=[self horizontalStack];
    [reviewNavigation addArrangedSubview:nextWord];[reviewNavigation addArrangedSubview:removeWord];
    [reviewCard addArrangedSubview:reviewNavigation];
    NSView *reviewSection=[self cardWithStack:reviewCard];

    // —— 已收藏语法卡片 ——
    NSStackView *savedGrammarCard = [self verticalStack];
    savedGrammarCard.spacing = 10;
    [savedGrammarCard addArrangedSubview:[self cardTitle:@"已收藏语法"]];
    self.grammarBookmarkListLabel = [self mutedLabel:@"暂无收藏。在实时翻译或查句弹窗中收藏语法。"];
    self.grammarBookmarkListLabel.maximumNumberOfLines = 0;
    self.grammarBookmarkListLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [savedGrammarCard addArrangedSubview:self.grammarBookmarkListLabel];
    self.savedGrammarCardStack = [self verticalStack];
    self.savedGrammarCardStack.spacing = 12;
    [savedGrammarCard addArrangedSubview:self.savedGrammarCardStack];
    NSView *grammarSection=[self cardWithStack:savedGrammarCard];
    NSStackView *sentences=[self verticalStack];[sentences addArrangedSubview:[self cardTitle:@"已收藏句子"]];
    self.savedSentenceStack=[self verticalStack];[sentences addArrangedSubview:self.savedSentenceStack];
    self.learningCollectionSections=@[words,grammarSection,[self cardWithStack:sentences],reviewSection];
    [self selectLearningCollection:tabButtons.firstObject];

    return page;
}

- (void)updateLearningCollectionSummary {
    NSArray *titles=@[@"从原句留下来的词",@"留下来的语法",@"想再读一遍的句子",@"带着原句复习"];
    NSInteger index=self.learningCollectionIndex;
    if(index<0 || index>=4){return;}
    self.learningCollectionTitle.stringValue=titles[index];
    NSUInteger count=index==1?self.grammarBookmarks.count:index==2?self.savedSentences.count:self.reviewList.count;
    self.learningCollectionCount.stringValue=[NSString stringWithFormat:index==3?@"%lu 个词可复习":@"%lu 个收藏",(unsigned long)count];
}
- (void)selectLearningCollection:(NSButton *)sender {
    NSInteger index=sender.tag;if(index<0 || index>=(NSInteger)self.learningCollectionSections.count){return;}
    self.learningCollectionIndex=index;
    [self clearArrangedSubviews:self.learningCollectionHost];
    [self.learningCollectionHost addArrangedSubview:self.learningCollectionSections[index]];
    for(NSButton *button in self.learningCollectionTabs){button.state=button.tag==index?NSControlStateValueOn:NSControlStateValueOff;button.needsDisplay=YES;}
    [self updateLearningCollectionSummary];
}


#pragma mark - Learning actions

- (void)toggleLearningPin:(id)sender {
    if (self.learningCoordinator.isPinned) { [self followLatestSentence:sender]; }
    else { [self pinLearningSentence:sender]; }
}

- (void)vocabularyFormChanged:(id)sender {
    self.vocabSelectionGeneration += 1;
    self.vocabCompletionFromAI = NO;
    self.vocabularySelectionLabel.stringValue = @"手动填写；原形、读音和释义均可留空。";
}

- (void)freezeLearningSentenceForSelection {
    self.vocabSelectionGeneration += 1;
    self.referenceRequestGeneration += 1;
    self.referenceActiveWord = @"";
    if (self.displayedSentenceID.length == 0 || self.learningSourceTextView.string.length == 0) { return; }
    [self syncCoordinatorToDisplayed];
    [self.learningCoordinator pinCurrent];
    [self refreshLearningStatus];
}

- (void)selectWordAtCharacterIndex:(NSUInteger)characterIndex {
    NSString *text = self.learningSourceTextView.string ?: @"";
    NSString *sentenceID = self.displayedSentenceID;
    NSInteger version = self.displayedVersion;
    NSInteger generation = ++self.vocabSelectionGeneration;
    [self.japaneseTokenizer rangeForLocation:characterIndex inText:text completion:^(NSRange range) {
        if (generation != self.vocabSelectionGeneration || ![sentenceID isEqualToString:self.displayedSentenceID] ||
            version != self.displayedVersion || ![text isEqualToString:self.learningSourceTextView.string]) { return; }
        if (range.location != NSNotFound && range.length <= text.length && range.location <= text.length - range.length) {
            self.learningSourceTextView.selectedRange = range;
        }
    }];
}

- (void)updateWordPickForSelection {
    if (self.learningSourceTextView.trackingSelection) { return; }
    self.lemmaField.stringValue=@"";self.readingField.stringValue=@"";self.meaningField.stringValue=@"";self.vocabCompletionFromAI=NO;
    NSString *selected = [self selectedLearningText];
    if (selected.length == 0) {
        self.wordPickArea.hidden = YES;
        return;
    }
    self.wordPickArea.hidden = NO;
    self.wordPickSurfaceLabel.stringValue = [NSString stringWithFormat:@"遇到的词形：%@", selected];
}

- (void)closeWordPick:(id)sender {
    self.wordPickArea.hidden = YES;
    if (self.learningSourceTextView.selectedRange.length > 0) {
        self.learningSourceTextView.selectedRange = NSMakeRange(self.learningSourceTextView.selectedRange.location, 0);
    }
}

- (void)openHistoryAnalysis:(NSButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)self.historyRecords.count) { return; }
    FYSentenceRecord *record = self.historyRecords[index];
    if (sender.identifier.length && ![record.sentenceID isEqualToString:sender.identifier]) {
        record = nil;
        for (FYSentenceRecord *candidate in self.historyRecords) { if ([candidate.sentenceID isEqualToString:sender.identifier]) { record = candidate; break; } }
        if (!record) { return; }
    }
    [self.learningCoordinator selectHistorySentence:record];
    [self refreshLearningSource];
    [self refreshLearningStatus];
    [self clearAnalysisDisplay];
    [self selectPageAtIndex:0];
    [self analyzeCurrentSentence:nil];
}

- (void)grammarSelectorChanged:(id)sender {
    // 追问与收藏均按 selector 当前选中项执行；无需额外处理。
}

- (void)pinLearningSentence:(id)sender {
    [self syncCoordinatorToDisplayed];
    [self.learningCoordinator pinCurrent];
    [self refreshLearningStatus];
}

- (void)followLatestSentence:(id)sender {
    __weak typeof(self) weakSelf = self;
    [self clearAnalysisDisplay];
    [self.learningCoordinator followLatestWithCompletion:^{
        [weakSelf refreshLearningSource];
        [weakSelf refreshLearningStatus];

    }];
}

- (void)setAnalyzeBusy:(BOOL)busy {
    self.learningAnalysisBusy = busy;
    self.grammarPageAnalyzeButton.title = busy ? @"分析中…" : (self.currentAnalysis ? @"重新分析" : @"分析此句");
    self.analyzeButton.enabled = !busy;
    if (self.grammarPageAnalyzeButton) { self.grammarPageAnalyzeButton.enabled = !busy; }
    if (busy) { self.grammarStatusLabel.stringValue = @"正在分析…"; }
    [self applyGrammarTabSelection];
}

- (void)analyzeCurrentSentence:(id)sender {
    [self syncCoordinatorToDisplayed];
    if (self.learningCoordinator.currentSentenceID.length == 0) {
        self.grammarStatusLabel.stringValue = @"当前没有可分析的句子，请先开始翻译。";
        return;
    }
    [self clearAnalysisDisplay];
    // 分析开始时固定展示的身份，避免分析期间 OCR 换句导致结果串句。
    [self.learningCoordinator pinCurrent];
    [self refreshLearningStatus];
    NSString *analyzedSentenceID = self.learningCoordinator.currentSentenceID;
    NSInteger analyzedVersion = self.learningCoordinator.currentVersion;
    NSInteger requestGeneration = ++self.analysisRequestGeneration;
    [self selectPageAtIndex:0];
    [self setAnalyzeBusy:YES];
    [self.learningCoordinator analyzeCurrent:^(FYAnalysisResult *result, NSError *error) {
        if (requestGeneration != self.analysisRequestGeneration ||
            ![analyzedSentenceID isEqualToString:self.learningCoordinator.currentSentenceID] ||
            analyzedVersion != self.learningCoordinator.currentVersion) { return; }
        [self setAnalyzeBusy:NO];
        if (error) {
            self.grammarAnalysisError = error.localizedDescription;
            self.grammarStatusLabel.stringValue = [NSString stringWithFormat:@"分析失败：%@", error.localizedDescription];
            self.grammarStatusLabel.textColor = NSColor.systemRedColor;
            self.grammarDetailNameLabel.stringValue = @"本次分析未完成";
            self.grammarDetailBodyLabel.stringValue = @"本次未能取得可核实的语法结果。请检查原句是否识别正确，再点击「分析此句」重试。";
            [self applyGrammarTabSelection];
            return;
        }
        // 结果归属核对：仅当仍是分析时那一句才展示，防止旧分析串到新句。
        if (![result.sentenceID isEqualToString:analyzedSentenceID] || result.version != analyzedVersion) {
            return;
        }
        self.currentAnalysis = result;
        [self refreshGrammarResults];
    }];
}

- (void)refreshGrammarResults {
    FYAnalysisResult *result = self.currentAnalysis;
    self.grammarAnalysisError = nil;
    self.grammarStructureCard.hidden = result == nil;
    self.grammarDetailFields.hidden = result == nil;
    self.grammarStatusLabel.textColor = self.uiMuted;
    self.sentenceInsightLabel.stringValue = result.sentenceNote ?: @"";
    NSString *levelTag = [self currentSentenceLevelTag];
    self.liveLevelTag.stringValue = levelTag ?: @"";
    self.liveLevelTag.hidden = levelTag.length == 0;
    CGFloat keptStructureOffset = [self structureScrollOffsetForQuick:NO];
    [self clearArrangedSubviews:self.sentenceStructureStack];
    NSView *structure=[self structureViewForAnalysis:result source:self.learningCoordinator.currentSourceText quick:NO];
    if(structure){[self.sentenceStructureStack addArrangedSubview:structure];}
    else if(result){[self.sentenceStructureStack addArrangedSubview:[self mutedLabel:@"本次解析没有整句结构图，可重新分析获取。"]];}
    self.sentenceInsightStack.hidden = !result;
    for (NSControl *control in self.grammarFollowupControls) { control.enabled = result.grammar.count > 0 && [self analysisMatchesCurrentSentence]; }
    self.followupRequestGeneration += 1;
    [self clearArrangedSubviews:self.grammarOtherStack];
    self.grammarFollowupResultLabel.stringValue = @"";
    if (!result || result.grammar.count == 0) {
        self.grammarDetailBodyLabel.hidden = NO;
        self.grammarStatusLabel.stringValue = result ? @"没有识别到语法" : @"尚未分析";
        self.grammarDetailNameLabel.stringValue = result ? @"没有识别结果" : @"尚未分析";
        self.grammarDetailLevelLabel.stringValue = @"";
        self.grammarDetailBodyLabel.stringValue = result
            ? @"这一句没有识别到可高亮的语法（可能是基础表达）。"
            : @"请在实时翻译页选中一句并点「分析此句」。";
        self.grammarDetailBookmarkButton.hidden = YES;
        [self clearArrangedSubviews:self.grammarDetailFields];
        self.grammarSourceLinkButton.hidden = YES;
        self.grammarOtherEmptyLabel.stringValue = @"没有其他识别结果。";
        [self clearGrammarHighlight];
        [self applyGrammarTabSelection];
        return;
    }
    if (self.selectedGrammarIndex < 0 || self.selectedGrammarIndex >= (NSInteger)result.grammar.count) {
        self.selectedGrammarIndex = 0;
    }
    self.grammarStatusLabel.stringValue = [NSString stringWithFormat:@"识别到 %lu 条语法", (unsigned long)result.grammar.count];
    [self renderGrammarDetailAtIndex:self.selectedGrammarIndex];
    self.grammarOtherEmptyLabel.stringValue = @"选择一项查看含义、接续与命中位置。";
    for (NSUInteger i = 0; i < result.grammar.count; i++) {
        FYGrammarItem *item = result.grammar[i];
        NSString *level = item.referenceLevel.length ? [NSString stringWithFormat:@"参考 %@%@", item.referenceLevel, item.levelVerified ? @"" : @" · 待核实"] : @"等级待核实";
        NSString *title = item.name;
        NSButton *button = [self workspaceButton:title action:@selector(selectGrammarItem:) primary:NO];
        button.toolTip = level; button.state = i == (NSUInteger)self.selectedGrammarIndex ? NSControlStateValueOn : NSControlStateValueOff;
        button.bezelStyle = NSBezelStyleRegularSquare;
        button.bordered = NO;
        button.alignment = NSTextAlignmentLeft;
        button.font = FYUIFont(14, NSFontWeightRegular);
        button.wantsLayer = YES;
        button.layer.cornerRadius = 5;
        button.layer.backgroundColor = (i == (NSUInteger)self.selectedGrammarIndex ? self.uiSelected : self.uiSurface).CGColor;
        button.tag = i;
        button.lineBreakMode = NSLineBreakByTruncatingTail;
        button.cell.truncatesLastVisibleLine = YES;
        [self.grammarOtherStack addArrangedSubview:button];
        [button.widthAnchor constraintEqualToAnchor:self.grammarOtherStack.widthAnchor].active = YES;
    }
    [self highlightGrammarMatches];
    [self applyGrammarTabSelection];
    [self restoreStructureScrollOffset:keptStructureOffset quick:NO];
}

- (void)renderGrammarDetailAtIndex:(NSInteger)index {
    self.grammarPageAnalyzeButton.title = @"重新分析";
    FYGrammarItem *item = self.currentAnalysis.grammar[index];
    self.grammarDetailNameLabel.stringValue = item.name;
    self.grammarDetailLevelLabel.stringValue = item.referenceLevel.length
        ? [NSString stringWithFormat:@"参考 %@%@", item.referenceLevel, item.levelVerified ? @"" : @" · 待核实"] : @"等级待核实";
    self.grammarResultsLabel.hidden = YES;
    // 一句解释
    self.grammarDetailBodyLabel.hidden = NO;
    self.grammarDetailBodyLabel.stringValue = item.meaning.length ? item.meaning : @"这条语法暂无可核实的释义。";
    // 横向短字段：接续 / 语体（全部来自真实分析结果）
    [self clearArrangedSubviews:self.grammarDetailFields];
    NSMutableArray<NSArray *> *fields = [NSMutableArray array];
    if (item.connection.length) { [fields addObject:@[@"接续", item.connection]]; }
    if (item.registerNote.length) { [fields addObject:@[@"语体", item.registerNote]]; }
    if (fields.count == 0) { [fields addObject:@[@"接续", @"待补充"]]; }
    for (NSArray *field in fields) {
        NSStackView *chip = [self verticalStack]; chip.spacing = 2;
        [chip addArrangedSubview:[self mutedLabel:field[0]]];
        NSTextField *value = [self label:field[1] font:FYUIFont(13, NSFontWeightRegular) color:self.uiInk];
        value.maximumNumberOfLines = 3;
        [chip addArrangedSubview:value];
        [chip.widthAnchor constraintGreaterThanOrEqualToConstant:104].active = YES;
        [self.grammarDetailFields addArrangedSubview:chip];
    }
    // 用法或例句块
    [self clearArrangedSubviews:self.grammarUsageBlock];
    if (item.explanation.length) {
        [self.grammarUsageBlock addArrangedSubview:[self mutedLabel:@"本句用法"]];
        NSTextField *usage = [self label:item.explanation font:FYUIFont(13, NSFontWeightRegular) color:self.uiInk];
        usage.maximumNumberOfLines = 4;
        [self.grammarUsageBlock addArrangedSubview:usage];
    }
    NSString *example = Trim(self.grammarExampleLabel.stringValue);
    if (example.length && ![example isEqualToString:@"还没有例句。"]) {
        [self.grammarUsageBlock addArrangedSubview:[self mutedLabel:@"例句"]];
        NSTextField *exampleLabel = [self label:example font:FYUIFont(13, NSFontWeightRegular) color:self.uiInk];
        exampleLabel.maximumNumberOfLines = 4;
        [self.grammarUsageBlock addArrangedSubview:exampleLabel];
    }
    if (item.levelSourceTitle.length) {
        [self.grammarUsageBlock addArrangedSubview:[self mutedLabel:[NSString stringWithFormat:@"解释由 AI 生成；等级参考：%@", item.levelSourceTitle]]];
    }
    self.grammarSourceLinkButton.hidden = item.levelSourceURL.length == 0;
    self.grammarSourceLinkButton.toolTip = item.levelSourceURL;
    self.grammarDetailBookmarkButton.hidden = NO;
    self.grammarDetailBookmarkButton.enabled = YES;
    self.grammarDetailBookmarkButton.tag = index;
    self.grammarDetailBookmarkButton.title = [self bookmarkForCurrentGrammar] ? @"已收藏 · 取消收藏" : @"收藏此语法";
}

- (void)openGrammarSource:(id)sender {
    NSURL *url = [NSURL URLWithString:[self selectedGrammarItem].levelSourceURL ?: @""];
    if ([url.scheme.lowercaseString isEqualToString:@"https"] || [url.scheme.lowercaseString isEqualToString:@"http"]) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (FYGrammarBookmark *)bookmarkForCurrentGrammar {
    FYGrammarItem *item = [self selectedGrammarItem];
    for (FYGrammarBookmark *bookmark in self.grammarBookmarks) {
        if ([bookmark.name isEqualToString:item.name] && [bookmark.sentenceID isEqualToString:self.currentAnalysis.sentenceID] &&
            bookmark.version == self.currentAnalysis.version) { return bookmark; }
    }
    return nil;
}

- (BOOL)analysisMatchesCurrentSentence {
    return self.currentAnalysis && [self.currentAnalysis.sentenceID isEqualToString:self.learningCoordinator.currentSentenceID] &&
           self.currentAnalysis.version == self.learningCoordinator.currentVersion;
}

- (void)highlightGrammarMatches {
    NSColor *hl = self.uiSelected;
    [self applyHighlight:hl toTextView:self.learningSourceTextView];
    [self applyHighlight:hl toTextView:self.grammarSourceTextView];
    [self refreshSourceHoverTips];
}

- (void)applyHighlight:(NSColor *)color toTextView:(NSTextView *)textView {
    if (!textView) { return; }
    NSString *text = textView.string ?: @"";
    [textView.textStorage removeAttribute:NSBackgroundColorAttributeName range:NSMakeRange(0, text.length)];
    if (!color || !self.currentAnalysis) { return; }
    if (![self analysisMatchesCurrentSentence]) { return; }
    for (FYGrammarItem *item in self.currentAnalysis.grammar) {
        NSRange range = item.matchedRange;
        if (range.location != NSNotFound && range.length <= text.length && range.location <= text.length - range.length &&
            [[text substringWithRange:range] isEqualToString:item.matchedText]) {
            NSColor *highlight = item == [self selectedGrammarItem] ? [self.uiAccent colorWithAlphaComponent:0.23] : color;
            [textView.textStorage addAttribute:NSBackgroundColorAttributeName value:highlight range:range];
        }
    }
}

- (void)clearGrammarHighlight {
    [self applyHighlight:nil toTextView:self.learningSourceTextView];
    [self applyHighlight:nil toTextView:self.grammarSourceTextView];
    [self refreshSourceHoverTips];
}

// 切句时清理旧分析、旧高亮、旧语法列表与旧追问内容。
- (void)clearAnalysisDisplay {
    self.analysisRequestGeneration += 1;
    self.followupRequestGeneration += 1;
    self.currentAnalysis = nil;
    self.grammarAnalysisError = nil;
    [self setAnalyzeBusy:NO];
    [self clearArrangedSubviews:self.grammarDetailFields];
    self.grammarDetailBodyLabel.hidden = NO;
    self.grammarSourceLinkButton.hidden = YES;
    self.grammarStatusLabel.stringValue = @"尚未分析";
    self.currentAnalysis = nil;
    self.sentenceInsightLabel.stringValue = @""; self.sentenceInsightStack.hidden = YES;
    self.grammarStatusLabel.textColor = self.uiMuted;
    for (NSControl *control in self.grammarFollowupControls) { control.enabled = NO; }
    self.selectedGrammarIndex = 0;
    self.grammarResultsLabel.stringValue = @"";
    self.grammarFollowupResultLabel.stringValue = @"";
    [self clearArrangedSubviews:self.grammarOtherStack];
    self.grammarDetailNameLabel.stringValue = @"尚未分析";
    self.grammarDetailLevelLabel.stringValue = @"";
    self.grammarDetailBodyLabel.stringValue = @"分析句子后，这里显示选中语法的含义、接续、当前句用法与资料来源。";
    self.grammarDetailBookmarkButton.hidden = YES;
    self.grammarOtherEmptyLabel.stringValue = @"分析后这里列出这一句的其他语法。";
    [self clearGrammarHighlight];
}

- (void)bookmarkGrammarItem:(NSButton *)sender {
    if (![self analysisMatchesCurrentSentence]) { return; }
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)self.currentAnalysis.grammar.count) { return; }
    FYGrammarItem *item = self.currentAnalysis.grammar[index];
    [self.learningCoordinator bookmarkGrammar:item completion:^(NSError *error) {
        if (error) {
            self.grammarStatusLabel.stringValue = [NSString stringWithFormat:@"收藏失败：%@", error.localizedDescription];
        } else {
            self.grammarStatusLabel.stringValue = [NSString stringWithFormat:@"已收藏语法「%@」。", item.name];
            [self refreshGrammarBookmarks:nil];
        }
    }];
}

- (void)bookmarkSelectedGrammar:(id)sender {
    if (![self analysisMatchesCurrentSentence] || ![self selectedGrammarItem] || !self.grammarDetailBookmarkButton.enabled) { return; }
    FYGrammarItem *item = [self selectedGrammarItem];
    FYGrammarBookmark *existing = [self bookmarkForCurrentGrammar];
    self.grammarDetailBookmarkButton.enabled = NO;
    void (^finish)(NSError *) = ^(NSError *error) {
        if (item != [self selectedGrammarItem] || ![self analysisMatchesCurrentSentence]) { [self refreshGrammarBookmarks:nil]; return; }
        self.grammarDetailBookmarkButton.enabled = YES;
        self.grammarStatusLabel.stringValue = error ? [NSString stringWithFormat:@"收藏操作失败：%@", error.localizedDescription] : (existing ? @"已取消语法收藏。" : @"语法与原句已收藏。");
        [self refreshGrammarBookmarks:nil];
    };
    if (existing) { [self.learningStore deleteGrammarBookmark:existing.bookmarkID completion:finish]; }
    else { [self.learningCoordinator bookmarkGrammar:item completion:finish]; }
}

- (void)selectGrammarItem:(NSButton *)sender {
    if (!self.currentAnalysis) { return; }
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)self.currentAnalysis.grammar.count) { return; }
    self.selectedGrammarIndex = index;
    // 只更新高亮与详情：重建结构图会连带新建 NSScrollView，横向滚动位置会丢。
    [self applyGrammarSelectionLocally];
}

// 局部更新选中态：结构图节点高亮、左侧语法列表高亮、详情、原文命中高亮。
// 不触碰结构图本身，所以横向滚动位置、页面纵向位置都保持不动；被点的节点原地不动（已可见就不动）。
- (void)applyGrammarSelectionLocally {
    for (NSButton *node in self.mainStructureButtons) {
        node.layer.backgroundColor = (node.tag == self.selectedGrammarIndex ? self.uiSelected : FYAdventureColor(@"paper")).CGColor;
    }
    for (NSView *view in self.grammarOtherStack.arrangedSubviews) {
        if (![view isKindOfClass:NSButton.class]) { continue; }
        NSButton *button = (NSButton *)view;
        BOOL on = (NSInteger)button.tag == self.selectedGrammarIndex;
        button.state = on ? NSControlStateValueOn : NSControlStateValueOff;
        button.layer.backgroundColor = (on ? self.uiSelected : self.uiSurface).CGColor;
    }
    if (self.selectedGrammarIndex >= 0 && self.selectedGrammarIndex < (NSInteger)self.currentAnalysis.grammar.count) {
        [self renderGrammarDetailAtIndex:self.selectedGrammarIndex];
    }
    [self highlightGrammarMatches];
}

// 结构图的横向偏移：重建前后用它保持位置（有效范围由文档宽度约束）。
- (CGFloat)structureScrollOffsetForQuick:(BOOL)quick {
    NSScrollView *scroll = quick ? self.quickStructureScrollView : self.mainStructureScrollView;
    return scroll ? scroll.contentView.bounds.origin.x : 0;
}
- (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick {
    if (offset <= 0.5) { return; }
    NSScrollView *scroll = quick ? self.quickStructureScrollView : self.mainStructureScrollView;
    if (!scroll) { return; }
    // 立即在布局完成后恢复（不用延时跳回，避免闪动）。
    [scroll.documentView layoutSubtreeIfNeeded];
    [scroll layoutSubtreeIfNeeded];
    CGFloat maxX = MAX(0, NSWidth(scroll.documentView.frame) - NSWidth(scroll.contentView.bounds));
    CGFloat x = MIN(MAX(offset, 0), maxX);
    [scroll.contentView scrollToPoint:NSMakePoint(x, scroll.contentView.bounds.origin.y)];
    [scroll reflectScrolledClipView:scroll.contentView];
}

- (FYGrammarItem *)selectedGrammarItem {
    if (!self.currentAnalysis || self.currentAnalysis.grammar.count == 0) { return nil; }
    NSInteger index = self.selectedGrammarIndex;
    if (index < 0 || index >= (NSInteger)self.currentAnalysis.grammar.count) { index = 0; }
    return self.currentAnalysis.grammar[index];
}

- (void)backToSourcePage:(id)sender {
    [self selectPageAtIndex:0];
}

- (void)simplerExplanationForGrammar:(id)sender { [self requestGrammarFollowupExample:NO]; }

- (void)exampleSentenceForGrammar:(id)sender { [self requestGrammarFollowupExample:YES]; }

- (void)requestGrammarFollowupExample:(BOOL)example {
    FYGrammarItem *item = [self selectedGrammarItem];
    if (!item || ![self analysisMatchesCurrentSentence]) { self.grammarFollowupResultLabel.stringValue = @"请先分析当前句子。"; return; }
    NSInteger generation = ++self.followupRequestGeneration;
    NSString *sentenceID = self.currentAnalysis.sentenceID;
    NSInteger version = self.currentAnalysis.version;
    self.grammarFollowupResultLabel.stringValue = @"正在生成…";
    void (^finish)(NSString *, NSError *) = ^(NSString *answer, NSError *error) {
        if (generation != self.followupRequestGeneration || item != [self selectedGrammarItem] ||
            ![sentenceID isEqualToString:self.learningCoordinator.currentSentenceID] || version != self.learningCoordinator.currentVersion) { return; }
        self.grammarFollowupResultLabel.stringValue = error ? [NSString stringWithFormat:@"生成失败：%@；可以点击上方按钮重试。", error.localizedDescription] : [NSString stringWithFormat:@"AI 建议\n%@", answer ?: @""];
    };
    if (example) { [self.learningAnalyzer exampleSentenceForGrammar:item sentenceText:self.learningCoordinator.currentSourceText translation:self.learningCoordinator.currentTranslation completion:finish]; }
    else { [self.learningAnalyzer simplerExplanationForGrammar:item sentenceText:self.learningCoordinator.currentSourceText translation:self.learningCoordinator.currentTranslation completion:finish]; }
}

- (NSString *)selectedLearningText {
    NSRange range = self.learningSourceTextView.selectedRange;
    if (range.location == NSNotFound || range.length == 0) { return @""; }
    NSString *text = self.learningSourceTextView.string ?: @"";
    if (NSMaxRange(range) > text.length) { return @""; }
    return [text substringWithRange:range];
}

- (void)bookmarkSelectedVocabulary:(id)sender {
    [self syncCoordinatorToDisplayed];
    NSString *selected = [self selectedLearningText];
    if (selected.length == 0) {
        self.vocabularyStatusLabel.stringValue = @"请先在原句上点击或拖选一个词/短语。";
        return;
    }
    if (self.savingVocabulary) { return; }
    self.savingVocabulary = YES;
    FYVocabularyEntry *entry = [[FYVocabularyEntry alloc] init];
    entry.kind = FYVocabularyKindWord;
    entry.surface = selected;
    entry.lemma = Trim(self.lemmaField.stringValue);
    entry.reading = Trim(self.readingField.stringValue);
    entry.meaning = Trim(self.meaningField.stringValue);
    entry.completionSource = self.vocabCompletionFromAI ? FYCompletionSourceAI : FYCompletionSourceManual;
    entry.reviewStatus = FYReviewStatusNew;
    NSInteger saveGeneration = self.vocabSelectionGeneration;
    [self.learningCoordinator bookmarkVocabulary:entry selectedText:selected completion:^(FYVocabularyEntry *saved, BOOL wasDuplicate, NSError *error) {
        self.savingVocabulary = NO;
        if (saveGeneration != self.vocabSelectionGeneration) { [self refreshVocabularyList]; return; }
        if (error) { self.vocabularyStatusLabel.stringValue = error.localizedDescription; return; }
        self.vocabularyStatusLabel.stringValue = wasDuplicate
            ? [NSString stringWithFormat:@"已有词条「%@」，已追加例句。", saved.surface]
            : [NSString stringWithFormat:@"已收藏「%@」。", saved.surface];
        [self refreshVocabularyList];
    }];
}

- (void)completeSelectedVocabulary:(id)sender {
    [self syncCoordinatorToDisplayed];
    NSString *selected = [self selectedLearningText];
    if (selected.length == 0) {
        self.vocabularyStatusLabel.stringValue = @"请先选中一个词/短语。";
        return;
    }
    self.vocabSelectionGeneration += 1;
    self.vocabularyStatusLabel.stringValue = @"正在补全读音与释义…";
    NSString *requestedSelection = [selected copy];
    NSRange requestedRange = self.learningSourceTextView.selectedRange;
    NSInteger requestGeneration = self.vocabSelectionGeneration;
    NSString *requestSentenceID = self.learningCoordinator.currentSentenceID;
    NSInteger requestVersion = self.learningCoordinator.currentVersion;
    __weak typeof(self) weakSelf = self;
    [self.learningCoordinator completeVocabulary:selected context:self.learningCoordinator.currentSourceText completion:^(FYVocabularyEntry *entry, NSError *error) {
        // 选区、代际或句子任一变化都视为旧请求，丢弃结果（仅比较词形无法区分同句多次出现）。
        BOOL sameRange = NSEqualRanges(requestedRange, weakSelf.learningSourceTextView.selectedRange);
        BOOL sameSentence = [requestSentenceID isEqualToString:weakSelf.learningCoordinator.currentSentenceID]
                             && requestVersion == weakSelf.learningCoordinator.currentVersion;
        if (requestGeneration != weakSelf.vocabSelectionGeneration || !sameRange || !sameSentence) {
            return;
        }
        if (error) { weakSelf.vocabularyStatusLabel.stringValue = [NSString stringWithFormat:@"补全失败：%@", error.localizedDescription]; return; }
        weakSelf.lemmaField.stringValue = entry.lemma ?: @"";
        weakSelf.readingField.stringValue = entry.reading ?: @"";
        weakSelf.meaningField.stringValue = entry.meaning ?: @"";
        weakSelf.vocabCompletionFromAI = YES;
        weakSelf.vocabularySelectionLabel.stringValue = [NSString stringWithFormat:@"%@（AI 建议，可在下方修改后收藏）", requestedSelection];
        weakSelf.vocabularyStatusLabel.stringValue = @"已给出 AI 建议，可修改后点「收藏所选」。";
    }];
}

- (void)refreshLearningSource {
    [self refreshHistory];
    NSString *source = self.learningCoordinator.currentSourceText ?: @"";
    NSString *translation = self.learningCoordinator.currentTranslation;
    BOOL changed = ![self.displayedSentenceID ?: @"" isEqualToString:self.learningCoordinator.currentSentenceID ?: @""] || self.displayedVersion != self.learningCoordinator.currentVersion;
    if (changed) {
        [self clearAnalysisDisplay];
        self.vocabSelectionGeneration += 1;
        self.wordPickArea.hidden = YES;
    }
    self.displayedSentenceID = self.learningCoordinator.currentSentenceID;
    self.displayedVersion = self.learningCoordinator.currentVersion;
    self.displayedSourceText = source;
    self.displayedTranslation = translation;
    BOOL sourceChanged=![self.learningSourceTextView.string isEqualToString:source];
    if (sourceChanged) { self.learningSourceTextView.string = source; }
    CGFloat readingWidth = MAX(200, self.learningSourceTextView.enclosingScrollView.contentView.bounds.size.width - 10);
    NSDictionary *readingAttributes = @{NSFontAttributeName:self.learningSourceTextView.font,
        NSParagraphStyleAttributeName:self.learningSourceTextView.defaultParagraphStyle ?: NSParagraphStyle.defaultParagraphStyle};
    CGFloat readingHeight = [source boundingRectWithSize:NSMakeSize(readingWidth, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:readingAttributes].size.height;
    self.sourceReadingHeight.constant = MIN(190, MAX(42, ceil(readingHeight) + 20));
    if (![self.grammarSourceTextView.string isEqualToString:source]) { self.grammarSourceTextView.string = source; }
    self.learningTranslationLabel.stringValue = translation.length ? translation : (source.length ? @"等待该句译文" : @"开始翻译后，当前台词会显示在这里。");
    [self refreshLiveDialoguePresentation:source];
    self.grammarSourceLabel.stringValue = translation.length ? translation : (source.length ? @"暂无该句译文" : @"还没有选择要分析的句子。");
    [self refreshLearningStatus];
    if(changed || sourceChanged || self.sourceHoverSuspended){[self refreshSourceHoverTips];}
}

- (void)syncCoordinatorToDisplayed {
    if (self.displayedSentenceID.length > 0 &&
        (![self.learningCoordinator.currentSentenceID isEqualToString:self.displayedSentenceID] ||
         self.learningCoordinator.currentVersion != self.displayedVersion)) {
        [self.learningCoordinator selectSentenceID:self.displayedSentenceID
                                          version:self.displayedVersion
                                       sourceText:self.displayedSourceText
                                      translation:self.displayedTranslation];
    }
}

// 展示用：把 OCR 文本里单独占一行的说话人名字拆出来，不改动用于选择/收藏的原文。
- (void)splitSpeakerAndBody:(NSString *)text speaker:(NSString * _Nullable * _Nullable)outSpeaker body:(NSString * _Nullable * _Nullable)outBody {
    NSString *speaker = nil;
    NSString *body = text ?: @"";
    NSArray<NSString *> *lines = [body componentsSeparatedByString:@"\n"];
    if (lines.count >= 2) {
        NSString *first = Trim(lines.firstObject);
        if (first.length > 0 && (LooksLikeSpeakerNameText(first) || LooksLikeSpeakerFuriganaText(first))) {
            NSUInteger consumed = 1;
            speaker = first;
            if (lines.count >= 3) {
                NSString *second = Trim(lines[1]);
                if (LooksLikeSpeakerFuriganaText(first) && LooksLikeSpeakerNameText(second)) {
                    speaker = [NSString stringWithFormat:@"%@ %@", first, second];
                    consumed = 2;
                }
            }
            body = [[lines subarrayWithRange:NSMakeRange(consumed, lines.count - consumed)] componentsJoinedByString:@"\n"];
        }
    }
    if (outSpeaker) { *outSpeaker = speaker; }
    if (outBody) { *outBody = body; }
}

// 等级标签只取语法点自带的可核实参考等级；没有就隐藏，不编造整句等级。
- (nullable NSString *)currentSentenceLevelTag {
    for (FYGrammarItem *item in self.currentAnalysis.grammar) {
        if (item.referenceLevel.length > 0) { return item.referenceLevel; }
    }
    return nil;
}

- (void)refreshLiveDialoguePresentation:(NSString *)source {
    NSString *speaker = nil;
    NSString *body = source ?: @"";
    [self splitSpeakerAndBody:source speaker:&speaker body:&body];
    if (self.liveScreenSpeakerLabel) {
        self.liveScreenSpeakerLabel.stringValue = speaker.length ? speaker : @"";
        self.liveScreenSpeakerLabel.hidden = speaker.length == 0;
    }
    if (self.liveScreenDialogueLabel) {
        self.liveScreenDialogueLabel.stringValue = body.length ? body : @"等待识别对白";
    }
    [self refreshLiveChips];
}

- (void)refreshLearningStatus {
    BOOL pinned = self.learningCoordinator.isPinned;
    self.learningPinnedLabel.stringValue = pinned ? (self.learningCoordinator.hasNewerSentence ? @"已固定 · 有新台词" : @"已固定") : @"跟随最新";
    self.learningPinnedLabel.textColor = self.uiAccent;
    self.grammarPinnedLabel.stringValue = self.learningPinnedLabel.stringValue;
    self.pinSentenceButton.title = pinned ? @"跟随最新" : @"固定此句";
    BOOL hasSentence = self.learningCoordinator.currentSentenceID.length > 0 && self.learningCoordinator.currentSourceText.length > 0;
    self.pinSentenceButton.enabled = hasSentence;
    self.analyzeButton.enabled = hasSentence && !self.learningAnalysisBusy;
    self.grammarPageAnalyzeButton.enabled = self.analyzeButton.enabled;
    [self applyGrammarTabSelection];
}

- (void)refreshHistory {
    [self.learningStore fetchRecentSentencesWithLimit:FYRecentSentenceLimit completion:^(NSArray<FYSentenceRecord *> *records, NSError *error) {
        [self clearArrangedSubviews:self.historyListStack];
        if (error) { [self.historyListStack addArrangedSubview:[self mutedLabel:[NSString stringWithFormat:@"历史加载失败：%@", error.localizedDescription]]]; return; }
        NSMutableArray<FYSentenceRecord *> *unique = [NSMutableArray array];
        // Group equivalent reads of one dialogue (variable leading dot runs,
        // a missed speaker box, a clipped last line) plus duplicates already
        // saved by older versions or across app restarts. Collections, stable
        // IDs and source snapshots stay untouched; this never rewrites the store.
        NSMutableArray<NSMutableArray<FYSentenceRecord *> *> *groups = [NSMutableArray array];
        for (FYSentenceRecord *record in records) {
            NSMutableArray<NSMutableArray<FYSentenceRecord *> *> *matches = [NSMutableArray array];
            for (NSMutableArray<FYSentenceRecord *> *group in groups) {
                if (group.firstObject.kind != record.kind) { continue; }
                BOOL same = NO;
                if (record.kind != FYSentenceKindDialogue) {
                    // Options, UI text and snapshots only collapse on identical text.
                    same = record.latestText.length > 0 && [group.firstObject.latestText isEqualToString:record.latestText];
                } else {
                    for (FYSentenceRecord *member in group) {
                        if (FYDialogueTextsAreEquivalent(member.latestText, record.latestText)) { same = YES; break; }
                    }
                }
                if (same) { [matches addObject:group]; }
            }
            if (matches.count == 0) {
                [groups addObject:[NSMutableArray arrayWithObject:record]];
                continue;
            }
            // A record can be equivalent to two groups (the relation is not
            // transitive); join them instead of picking one arbitrarily.
            NSMutableArray<FYSentenceRecord *> *target = matches.firstObject;
            [target addObject:record];
            for (NSUInteger i = 1; i < matches.count; i++) {
                NSMutableArray<FYSentenceRecord *> *extra = matches[i];
                if (extra == target) { continue; }
                [target addObjectsFromArray:extra];
                [groups removeObjectIdenticalTo:extra];
            }
            [target sortUsingComparator:^NSComparisonResult(FYSentenceRecord *a, FYSentenceRecord *b) {
                return [b.occurredAt compare:a.occurredAt];
            }];
        }
        for (NSMutableArray<FYSentenceRecord *> *group in groups) {
            if (group.count == 1) { [unique addObject:group.firstObject]; continue; }
            // Show the newest record that is not a degraded read of another
            // member, so a complete dialogue wins over a clipped frame even
            // when the clipped frame arrived later. `group` is newest-first.
            FYSentenceRecord *representative = nil;
            for (FYSentenceRecord *candidate in group) {
                BOOL degraded = NO;
                for (FYSentenceRecord *other in group) {
                    if (other == candidate) { continue; }
                    if (FYDialogueIsIncompleteFrame(candidate.latestText, other.latestText) ||
                        FYDialogueIsFragmentOfDialogue(candidate.latestText, other.latestText)) { degraded = YES; break; }
                }
                if (!degraded) { representative = candidate; break; }
            }
            [unique addObject:representative ?: group.firstObject];
        }
        self.historyRecords = unique;
        if (self.historyRecords.count == 0) { [self.historyListStack addArrangedSubview:[self mutedLabel:@"暂无历史台词，开始翻译后自动记录日文句子。"]]; return; }
        NSDateFormatter *time = [NSDateFormatter new]; time.dateFormat = @"HH:mm";
        for (NSUInteger i = 0; i < self.historyRecords.count; i++) {
            FYSentenceRecord *record = self.historyRecords[i];
            NSStackView *row = [self horizontalStack]; row.spacing = 18;
            NSStackView *text = [self verticalStack]; text.spacing = 5;
            [text addArrangedSubview:[self label:record.latestText font:FYUIFont(14, NSFontWeightRegular) color:self.uiInk]];
            [text addArrangedSubview:[self mutedLabel:record.latestTranslation.length ? record.latestTranslation : @"暂无该句译文"]];
            NSString *kind = record.kind == FYSentenceKindDialogue ? @"对白" : record.kind == FYSentenceKindOption ? @"选项" : record.kind == FYSentenceKindUI ? @"界面" : @"快照";
            [text addArrangedSubview:[self mutedLabel:[NSString stringWithFormat:@"%@ · %@ · 版本 %ld", kind, [time stringFromDate:record.occurredAt], (long)record.latestVersion]]];
            [row addArrangedSubview:text];
            NSButton *analyze = [self workspaceButton:@"查看与分析 ↗" action:@selector(openHistoryAnalysis:) primary:NO];
            analyze.tag = i; analyze.identifier = record.sentenceID;
            [row addArrangedSubview:analyze];
            NSStackView *historyCard = [self verticalStack]; [historyCard addArrangedSubview:row];
            [self.historyListStack addArrangedSubview:[self cardWithStack:historyCard]];
        }
    }];
}

- (void)refreshHistoryAction:(id)sender {
    [self refreshHistory];
}

- (void)historyChanged:(id)sender {
    // 历史列表已改为行式入口，见 refreshHistory / openHistoryAnalysis:。
}

- (void)refreshVocabularyList {
    [self.learningStore fetchVocabularyListWithCompletion:^(NSArray<FYVocabularyEntry *> *entries, NSError *error) {
        if (error) {
            self.vocabularyEmptyCard.hidden = NO;
            self.vocabularyListLabel.hidden = NO;
            self.vocabularyListLabel.stringValue = [NSString stringWithFormat:@"加载收藏失败：%@", error.localizedDescription];
            return;
        }
        self.vocabularyEmptyCard.hidden = entries.count > 0;
        self.reviewList = entries ?: @[];
        [self updateLearningCollectionSummary];
        if (self.reviewingEntry) {
            FYVocabularyEntry *current = nil;
            for (FYVocabularyEntry *entry in self.reviewList) { if ([entry.vocabularyID isEqualToString:self.reviewingEntry.vocabularyID]) { current = entry; break; } }
            self.reviewingEntry = current;
            if (!current) {
                self.reviewWordLabel.hidden = YES; self.reviewMeaningLabel.hidden = YES;
                self.reviewWordLabel.stringValue = @""; self.reviewMeaningLabel.stringValue = @"";
                self.reviewPromptLabel.stringValue = @"这个词已取消收藏，请点「下一个词」。";
            }
        }
        if (self.reviewIndex >= self.reviewList.count) { self.reviewIndex = 0; }
        [self rebuildWordCards];
        if (entries.count == 0) {
            self.vocabularyListLabel.stringValue = @"还没有收藏的词语。\n回到实时翻译页，点击或拖选日文原句中的词语即可收藏。";
            self.vocabularyListLabel.hidden = NO;
            self.reviewIndex = 0;
            self.reviewingEntry = nil;
            self.reviewWordLabel.stringValue = @"";
            self.reviewMeaningLabel.stringValue = @"";
        } else {
            self.vocabularyListLabel.stringValue = @"";
            self.vocabularyListLabel.hidden = YES;
        }
        [self refreshGrammarBookmarks:nil];
    }];
}

- (void)rebuildWordCards {
    if (!self.revealedMeanings) { self.revealedMeanings = [NSMutableDictionary dictionary]; }
    NSInteger generation = ++self.wordCardsGeneration;
    [self clearArrangedSubviews:self.wordCardStack];
    for (NSUInteger i = 0; i < self.reviewList.count; i++) {
        FYVocabularyEntry *entry = self.reviewList[i];
        NSStackView *card = [self verticalStack];
        card.spacing = 6;
        NSStackView *titleRow = [self horizontalStack];
        NSString *lemma = entry.lemma.length > 0 ? entry.lemma : entry.surface;
        [titleRow addArrangedSubview:[self label:lemma font:FYUIFont(16, NSFontWeightBold) color:self.uiInk]];
        if (entry.reading.length > 0) {
            [titleRow addArrangedSubview:[self label:[NSString stringWithFormat:@"（%@）", entry.reading] font:FYUIFont(13, NSFontWeightRegular) color:self.uiMuted]];
        } else {
            [titleRow addArrangedSubview:[self mutedLabel:@"读音待补充"]];
        }
        [titleRow addArrangedSubview:[self spacer]];
        [card addArrangedSubview:titleRow];
        BOOL revealed = self.revealedMeanings[entry.vocabularyID]==nil || [self.revealedMeanings[entry.vocabularyID] boolValue];
        NSTextField *meaningLabel = [self label:(revealed ? (entry.meaning.length > 0 ? entry.meaning : @"释义待补充") : @"释义已遮住，先回忆它的意思。")
                                         font:FYUIFont(14, NSFontWeightRegular) color:self.uiInk];
        meaningLabel.maximumNumberOfLines = 0;
        meaningLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [card addArrangedSubview:meaningLabel];
        NSStackView *summaryActions=[self horizontalStack];
        NSButton *details=[self workspaceButton:[self.expandedWordCards containsObject:entry.vocabularyID]?@"收起详情":@"查看详情" action:@selector(toggleSavedWordDetails:) primary:NO];details.identifier=entry.vocabularyID;
        NSButton *toggle=[self workspaceButton:revealed?@"遮住释义":@"揭晓释义" action:@selector(toggleWordMeaning:) primary:NO];
        toggle.tag=i;toggle.identifier=entry.vocabularyID;
        [summaryActions addArrangedSubview:details];[summaryActions addArrangedSubview:toggle];[card addArrangedSubview:summaryActions];
        NSStackView *detail=[self verticalStack];detail.spacing=10;detail.hidden=![self.expandedWordCards containsObject:entry.vocabularyID];
        [card addArrangedSubview:detail];
        [detail addArrangedSubview:[self separator]];
        [detail addArrangedSubview:[self mutedLabel:entry.completionSource==FYCompletionSourceAI?@"释义来源 · AI 建议":@"释义来源 · 手动录入"]];
        NSTextField *sourceLabel = [self label:@"来源原句：—" font:FYUIFont(12, NSFontWeightRegular) color:self.uiMuted];
        sourceLabel.maximumNumberOfLines = 0;
        sourceLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [detail addArrangedSubview:sourceLabel];
        [detail addArrangedSubview:[self mutedLabel:[NSString stringWithFormat:@"遇到的词形：%@ · 自评：%@", entry.surface, entry.reviewStatus == FYReviewStatusKnown ? @"记住了" : @"还不熟"]]];
        NSButton *exampleButton = [NSButton buttonWithTitle:@"下一个来源例句" target:self action:@selector(nextWordExample:)];
        exampleButton.identifier = entry.vocabularyID; exampleButton.hidden = YES;
        [detail addArrangedSubview:exampleButton];
        NSString *vocabularyID = entry.vocabularyID;
        [self.learningStore fetchExamplesForVocabulary:vocabularyID completion:^(NSArray<FYVocabularyExample *> *examples, NSError *e) {
            if (generation != self.wordCardsGeneration) { return; }
            if (e) { sourceLabel.stringValue = [NSString stringWithFormat:@"例句加载失败：%@", e.localizedDescription]; return; }
            if (examples.count == 0) { sourceLabel.stringValue = @"没有关联例句。"; return; }
            NSUInteger index = [self.wordExampleIndices[vocabularyID] unsignedIntegerValue] % examples.count;
            FYVocabularyExample *example = examples[index];
            exampleButton.hidden = examples.count < 2;
            NSString *translation = example.translationSnapshot.length > 0 ? [NSString stringWithFormat:@"\n译文：%@", example.translationSnapshot] : @"";
            sourceLabel.stringValue = [NSString stringWithFormat:@"来源例句 %lu / %lu\n%@%@", (unsigned long)index + 1, (unsigned long)examples.count, example.sourceTextSnapshot, translation];
        }];
        NSStackView *actions = [self horizontalStack];
        NSButton *mastered = [NSButton buttonWithTitle:(entry.reviewStatus == FYReviewStatusKnown ? @"标记还不熟" : @"标记记住了") target:self action:@selector(toggleWordMastered:)];
        mastered.bezelStyle = NSBezelStyleRounded;
        mastered.tag = i; mastered.identifier = entry.vocabularyID;
        NSButton *remove = [NSButton buttonWithTitle:@"取消收藏" target:self action:@selector(removeWordCard:)];
        remove.bezelStyle = NSBezelStyleRounded;
        remove.tag = i; remove.identifier = entry.vocabularyID;
        [actions addArrangedSubview:mastered];
        [detail addArrangedSubview:actions];
        NSStackView *management=[self horizontalStack];
        NSButton *reference=[self workspaceButton:@"用法与等级参考" action:@selector(showSavedWordReference:) primary:NO];
        reference.identifier=entry.vocabularyID;
        [management addArrangedSubview:reference];
        [management addArrangedSubview:remove];
        [detail addArrangedSubview:management];
        FYSavedWordReferenceView *savedReference=[FYSavedWordReferenceView new];savedReference.hidden=YES;
        [detail addArrangedSubview:savedReference];
        [self.wordCardStack addArrangedSubview:[self cardWithStack:card]];
    }
}

- (void)toggleSavedWordDetails:(NSButton *)sender {
    FYVocabularyEntry *entry=[self wordForCardButton:sender];if(!entry){return;}
    if(!self.expandedWordCards){self.expandedWordCards=[NSMutableSet new];}
    BOOL expanded=[self.expandedWordCards containsObject:entry.vocabularyID];
    expanded?[self.expandedWordCards removeObject:entry.vocabularyID]:[self.expandedWordCards addObject:entry.vocabularyID];
    // Update the existing card in place; do not rebuild the list or reset scroll.
    NSStackView *card=(NSStackView *)sender.superview.superview;
    card.arrangedSubviews.lastObject.hidden=expanded;sender.title=expanded?@"查看详情":@"收起详情";
}
- (FYVocabularyEntry *)wordForCardButton:(NSButton *)sender {
    if (sender.identifier.length) {
        for (FYVocabularyEntry *entry in self.reviewList) { if ([entry.vocabularyID isEqualToString:sender.identifier]) { return entry; } }
        return nil;
    }
    return sender.tag >= 0 && sender.tag < (NSInteger)self.reviewList.count ? self.reviewList[sender.tag] : nil;
}

- (void)nextWordExample:(NSButton *)sender {
    if (!self.wordExampleIndices) { self.wordExampleIndices = [NSMutableDictionary dictionary]; }
    self.wordExampleIndices[sender.identifier] = @([self.wordExampleIndices[sender.identifier] unsignedIntegerValue] + 1);
    [self rebuildWordCards];
}

- (void)toggleWordMeaning:(NSButton *)sender {
    FYVocabularyEntry *entry = [self wordForCardButton:sender];
    if (!entry) { return; }
    BOOL currentlyRevealed=self.revealedMeanings[entry.vocabularyID]==nil || [self.revealedMeanings[entry.vocabularyID] boolValue];
    BOOL revealed = !currentlyRevealed;
    self.revealedMeanings[entry.vocabularyID] = @(revealed);
    NSStackView *card=(NSStackView *)sender.superview.superview;
    NSTextField *meaning=(NSTextField *)card.arrangedSubviews[1];
    meaning.stringValue=revealed?(entry.meaning.length?entry.meaning:@"释义待补充"):@"释义已遮住，先回忆它的意思。";
    sender.title=revealed?@"遮住释义":@"揭晓释义";
}

- (void)toggleWordMastered:(NSButton *)sender {
    FYVocabularyEntry *entry = [self wordForCardButton:sender];
    if (!entry) { return; }
    FYReviewStatus status = entry.reviewStatus == FYReviewStatusKnown ? FYReviewStatusLearning : FYReviewStatusKnown;
    [self.learningStore updateReviewStatus:status forVocabulary:entry.vocabularyID completion:^(NSError *e) {
        if (e) { self.reviewPromptLabel.stringValue = [NSString stringWithFormat:@"操作失败：%@", e.localizedDescription]; return; }
        [self refreshVocabularyList];
    }];
}

- (void)removeWordCard:(NSButton *)sender {
    FYVocabularyEntry *entry = [self wordForCardButton:sender];
    if (!entry) { return; }
    [self.learningStore deleteVocabulary:entry.vocabularyID completion:^(NSError *e) {
        if (e) { self.reviewPromptLabel.stringValue = [NSString stringWithFormat:@"操作失败：%@", e.localizedDescription]; return; }
        [self refreshVocabularyList];
    }];
}

- (void)nextReviewWord:(id)sender {
    if (!self.reviewList) {
        // 首次尚未加载完成：先触发加载，等数据返回后再点一次。
        self.reviewPromptLabel.stringValue = @"正在加载收藏…";
        [self refreshVocabularyList];
        return;
    }
    if (self.reviewList.count == 0) {
        self.reviewPromptLabel.stringValue = @"没有可复习的词条";
        return;
    }
    if (self.reviewIndex >= self.reviewList.count) { self.reviewIndex = 0; }
    self.reviewingEntry = self.reviewList[self.reviewIndex];
    self.reviewIndex += 1;
    self.reviewWordLabel.hidden = NO;
    self.reviewMeaningLabel.hidden = YES;
    self.reviewWordLabel.stringValue = self.reviewingEntry.surface;
    self.reviewMeaningLabel.stringValue = @"";
    self.reviewPromptLabel.stringValue = @"先回忆含义，再点「揭晓释义」。";
}

- (void)revealReviewMeaning:(id)sender {
    if (!self.reviewingEntry) { self.reviewPromptLabel.stringValue = @"请先点「下一个词」。"; return; }
    self.reviewMeaningLabel.hidden = NO;
    NSString *reading = self.reviewingEntry.reading.length > 0 ? [NSString stringWithFormat:@"（%@）", self.reviewingEntry.reading] : @"";
    self.reviewMeaningLabel.stringValue = [NSString stringWithFormat:@"%@ %@", reading, self.reviewingEntry.meaning ?: @"（暂无释义）"];
}

- (void)markReviewKnown:(id)sender {
    [self setReviewStatus:FYReviewStatusKnown];
}

- (void)markReviewLearning:(id)sender {
    [self setReviewStatus:FYReviewStatusLearning];
}

- (void)setReviewStatus:(FYReviewStatus)status {
    if (!self.reviewingEntry) { self.reviewPromptLabel.stringValue = @"请先点「下一个词」。"; return; }
    [self.learningStore updateReviewStatus:status forVocabulary:self.reviewingEntry.vocabularyID completion:^(NSError *e) {
        if (e) { self.reviewPromptLabel.stringValue = [NSString stringWithFormat:@"标记失败：%@", e.localizedDescription]; return; }
        [self refreshVocabularyList];
        self.reviewPromptLabel.stringValue = status == FYReviewStatusKnown ? @"已标记「记住了」" : @"已标记「还不熟」";
    }];
}

- (void)removeReviewWord:(id)sender {
    if (!self.reviewingEntry) { self.reviewPromptLabel.stringValue = @"请先点「下一个词」。"; return; }
    NSString *vocabularyID = self.reviewingEntry.vocabularyID;
    __weak typeof(self) weakSelf = self;
    [self.learningStore deleteVocabulary:vocabularyID completion:^(NSError *error) {
        if (error) {
            weakSelf.reviewPromptLabel.stringValue = [NSString stringWithFormat:@"取消收藏失败：%@", error.localizedDescription];
            return;
        }
        weakSelf.reviewWordLabel.stringValue = @"";
        weakSelf.reviewMeaningLabel.stringValue = @"";
        weakSelf.reviewingEntry = nil;
        [weakSelf refreshVocabularyList];
    }];
}

- (void)clearArrangedSubviews:(NSStackView *)stack {
    for (NSView *view in stack.arrangedSubviews.copy) {
        [stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}

#pragma mark - 收藏管理（语法收藏 / 词条例句）

- (void)refreshGrammarBookmarks:(id)sender {
    [self refreshSavedSentences];
    [self.learningStore fetchGrammarBookmarksWithCompletion:^(NSArray<FYGrammarBookmark *> *bookmarks, NSError *error) {
        if (error) { self.grammarBookmarkListLabel.stringValue = [NSString stringWithFormat:@"语法收藏加载失败：%@", error.localizedDescription]; return; }
        self.grammarBookmarks = bookmarks ?: @[];
        [self updateLearningCollectionSummary];
        [self updateQuickGrammarBookmark];
        [self clearArrangedSubviews:self.savedGrammarCardStack];
        self.grammarBookmarkListLabel.stringValue = bookmarks.count ? @"" : @"暂无收藏。在实时翻译或查句弹窗中收藏语法。";
        self.grammarBookmarkListLabel.hidden = bookmarks.count > 0;
        for (FYGrammarBookmark *bookmark in self.grammarBookmarks) {
            NSStackView *card = [self verticalStack]; card.spacing = 8;
            NSStackView *heading = [self horizontalStack];
            [heading addArrangedSubview:[self cardTitle:bookmark.name]];
            FYGrammarCatalogEntry *catalog = bookmark.catalogID.length ? [self.grammarCatalog entryForID:bookmark.catalogID] : [self.grammarCatalog entryForName:bookmark.name];
            [heading addArrangedSubview:[self mutedLabel:catalog.referenceLevel.length ? [NSString stringWithFormat:@"参考 %@ · %@", catalog.referenceLevel, [catalog.levelReviewStatus isEqualToString:@"verified"] ? @"已核实" : @"待核实"] : @"等级待核实"]];
            [card addArrangedSubview:heading];
            [card addArrangedSubview:[self label:bookmark.sourceTextSnapshot font:FYUIFont(14, NSFontWeightRegular) color:self.uiInk]];
            [card addArrangedSubview:[self mutedLabel:bookmark.translationSnapshot.length ? bookmark.translationSnapshot : @"暂无该句译文"]];
            NSButton *remove = [NSButton buttonWithTitle:@"取消收藏" target:self action:@selector(deleteGrammarBookmark:)];
            remove.identifier = bookmark.bookmarkID; [card addArrangedSubview:remove];
            [self.savedGrammarCardStack addArrangedSubview:[self cardWithStack:card]];
        }
        if ([self analysisMatchesCurrentSentence] && self.currentAnalysis.grammar.count) {
            self.grammarDetailBookmarkButton.title = [self bookmarkForCurrentGrammar] ? @"已收藏 · 取消收藏" : @"收藏此语法";
        }
    }];
}

- (void)grammarBookmarkChanged:(id)sender {
    // 删除按 popup 当前选中项执行。
}

- (void)deleteGrammarBookmark:(NSButton *)sender {
    NSString *bookmarkID = sender.identifier;
    if (!bookmarkID.length) { return; }
    [self.learningStore deleteGrammarBookmark:bookmarkID completion:^(NSError *error) {
        if (error) { self.grammarBookmarkListLabel.hidden = NO; self.grammarBookmarkListLabel.stringValue = [NSString stringWithFormat:@"取消收藏失败：%@", error.localizedDescription]; return; }
        [self refreshGrammarBookmarks:nil];
    }];
}

- (void)refreshVocabularyExamplesPopup {
    [self.vocabularyExamplesPopup removeAllItems];
    self.vocabularyExamplesList = self.reviewList ?: @[];
    if (self.vocabularyExamplesList.count == 0) {
        [self.vocabularyExamplesPopup addItemWithTitle:@"暂无词条"];
        return;
    }
    for (FYVocabularyEntry *entry in self.vocabularyExamplesList) {
        [self.vocabularyExamplesPopup addItemWithTitle:entry.surface];
    }
}

- (void)vocabularyExamplesChanged:(id)sender {
    // 例句按 popup 当前选中项读取。
}

- (void)showVocabularyExamples:(id)sender {
    NSInteger index = self.vocabularyExamplesPopup.indexOfSelectedItem;
    if (index < 0 || index >= (NSInteger)self.vocabularyExamplesList.count) { return; }
    NSString *vocabularyID = self.vocabularyExamplesList[index].vocabularyID;
    [self.learningStore fetchExamplesForVocabulary:vocabularyID completion:^(NSArray<FYVocabularyExample *> *examples, NSError *error) {
        if (error) {
            self.vocabularyExamplesLabel.stringValue = [NSString stringWithFormat:@"读取例句失败：%@", error.localizedDescription];
            return;
        }
        if (examples.count == 0) {
            self.vocabularyExamplesLabel.stringValue = @"该词条暂无例句。";
            return;
        }
        NSMutableString *text = [NSMutableString string];
        for (FYVocabularyExample *example in examples) {
            NSString *translation = example.translationSnapshot.length > 0 ? [NSString stringWithFormat:@"\n译文：%@", example.translationSnapshot] : @"";
            [text appendFormat:@"• %@%@\n", example.sourceTextSnapshot, translation];
        }
        self.vocabularyExamplesLabel.stringValue = text;
    }];
}

- (NSArray<NSString *> *)textsFromItems:(NSArray<OCRTextItem *> *)items {
    NSMutableArray<NSString *> *texts = [NSMutableArray arrayWithCapacity:items.count];
    for (OCRTextItem *item in items) {
        [texts addObject:item.text ?: @""];
    }
    return texts;
}

- (void)bindTranslations:(NSArray<NSString *> *)translations toIdentities:(NSArray<FYRequestIdentity *> *)identities {
    if (!translations || translations.count == 0) { return; }
    NSUInteger count = MIN(translations.count, identities.count);
    for (NSUInteger index = 0; index < count; index++) {
        FYRequestIdentity *identity = identities[index];
        NSString *translation = translations[index];
        if (identity && identity.sentenceID.length > 0 && translation.length > 0) {
            [self.learningCoordinator setTranslation:translation forIdentity:identity];
        }
    }
}

- (void)selectCaptionSwatch:(NSButton *)sender {
    self.captionThemeControl.selectedSegment = sender.tag;
    [self controlValueChanged:self.captionThemeControl];
}

- (void)updateThemeSummary {
    self.themeSummaryLabel.stringValue = [NSString stringWithFormat:@"%.0f pt / %.0f%%",
                                           self.captionFontSizeSlider.doubleValue,
                                           self.captionOpacitySlider.doubleValue * 100];
    for (NSButton *swatch in self.themeSwatches) {
        swatch.layer.borderColor = swatch.tag == self.captionThemeControl.selectedSegment
            ? [NSColor colorWithRed:0.04 green:0.47 blue:0.44 alpha:1].CGColor
            : [NSColor colorWithWhite:0.7 alpha:1].CGColor;
    }
}

- (NSView *)permissionControls {
    // 只有一个入口：先本机检查，缺哪个权限就打开对应的系统设置页。
    NSStackView *stack = [self verticalStack];
    [stack addArrangedSubview:[self label:@"权限" font:FYUIFont(15, NSFontWeightBold) color:[NSColor labelColor]]];
    __weak typeof(self) weakSelf = self;
    NSButton *oneButton = [NSButton buttonWithTitle:@"检查并打开权限设置" target:self action:@selector(openPermissionSettings:)];
    oneButton.bezelStyle = NSBezelStyleRounded;
    (void)weakSelf;
    [stack addArrangedSubview:oneButton];
    self.permissionStatusLabel = [self mutedLabel:@""];
    [stack addArrangedSubview:self.permissionStatusLabel];
    return stack;
}

// 单一权限入口：检测屏幕录制（采集卡模式下再看相机），打开需要处理的那一页。
- (void)openPermissionSettings:(id)sender {
    BOOL screenOK = [self hasScreenAccess];
    FYCaptureCardAvailability camera = [[FYCaptureCardInput new] availability];
    BOOL cameraNeeded = [self captureCardInputEnabled];
    NSString *state = [NSString stringWithFormat:@"屏幕录制：%@%@", screenOK ? @"已授权" : @"未授权",
                       cameraNeeded ? [NSString stringWithFormat:@" · 相机：%@", FYCaptureCardAvailabilityLabel(camera)] : @""];
    self.permissionStatusLabel.stringValue = state;
    [self setStatus:state];
    NSURL *url = nil;
    if (!screenOK) {
        url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"];
    } else if (cameraNeeded && camera != FYCaptureCardAvailabilityAuthorized) {
        url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"];
    }
    if (url) { [NSWorkspace.sharedWorkspace openURL:url]; }
}

- (NSView *)recognitionCard {
    NSStackView *stack = [self verticalStack];
    [stack addArrangedSubview:[self label:@"识别方式" font:FYUIFont(15, NSFontWeightBold) color:[NSColor labelColor]]];

    self.languageControl = [self segmentedWithLabels:@[@"日语", @"英语"] action:@selector(controlValueChanged:)];
    self.intervalSlider = [self sliderWithMin:0.5 max:4 value:1.2 action:@selector(controlValueChanged:)];
    self.stableTextCheckbox = [NSButton checkboxWithTitle:@"等待同一段 OCR 文本连续稳定后再翻译" target:self action:@selector(controlValueChanged:)];
    self.stableTextCheckbox.state = NSControlStateValueOn;
    self.fastOCRCheckbox = [NSButton checkboxWithTitle:@"快速 OCR（更实时，可能少量误识别）" target:self action:@selector(controlValueChanged:)];
    self.fastOCRCheckbox.state = NSControlStateValueOff;
    self.autoFitRegionCheckbox = [NSButton checkboxWithTitle:@"自动贴合文字识别（不依赖固定区域，小字更准）" target:self action:@selector(controlValueChanged:)];
    self.autoFitRegionCheckbox.state = NSControlStateValueOn;

    NSStackView *presetRow = [self horizontalStack];
    [presetRow addArrangedSubview:[NSButton buttonWithTitle:@"实时优先" target:self action:@selector(useRealtimePreset:)]];
    [presetRow addArrangedSubview:[NSButton buttonWithTitle:@"准确优先" target:self action:@selector(useAccuratePreset:)]];

    [stack addArrangedSubview:[self settingsRowWithLabel:@"原文语言" view:self.languageControl]];
    NSStackView *advanced = [self verticalStack];
    [advanced addArrangedSubview:[self settingsRowWithLabel:@"识别间隔" view:self.intervalSlider]];
    [advanced addArrangedSubview:presetRow];
    [advanced addArrangedSubview:self.stableTextCheckbox];
    [advanced addArrangedSubview:self.fastOCRCheckbox];
    [advanced addArrangedSubview:self.autoFitRegionCheckbox];
    return stack;
}

- (NSView *)windowCard {
    NSStackView *stack = [self verticalStack];
    [stack addArrangedSubview:[self separator]];
    [stack addArrangedSubview:[self label:@"画面来源" font:FYUIFont(15, NSFontWeightBold) color:[NSColor labelColor]]];

    // —— 识别输入源：OCR 从哪里取画面 ——
    self.inputSourceControl = [self segmentedWithLabels:@[@"窗口截图", @"采集卡"] action:@selector(inputSourceChanged:)];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"识别输入源" view:self.inputSourceControl]];
    self.inputSourceHintLabel = [self mutedLabel:@""];
    self.inputSourceHintLabel.maximumNumberOfLines = 3;
    self.inputSourceHintLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [stack addArrangedSubview:self.inputSourceHintLabel];

    // 采集卡专属控件整块收在一个容器里：窗口截图模式下整块隐藏，不再一次摊开"一坨"。
    NSStackView *captureControls = [self verticalStack];
    captureControls.spacing = 8;
    NSStackView *deviceRow = [self horizontalStack];
    self.captureDevicePopup = [[NSPopUpButton alloc] init];
    self.captureDevicePopup.target = self;
    self.captureDevicePopup.action = @selector(captureDeviceChanged:);
    [self.captureDevicePopup addItemWithTitle:@"点「刷新设备」检测采集卡"];
    self.captureDevicePopup.enabled = NO;
    NSButton *refreshDevicesButton = [NSButton buttonWithTitle:@"刷新设备" target:self action:@selector(refreshCaptureDevices:)];
    refreshDevicesButton.bezelStyle = NSBezelStyleRounded;
    NSButton *reconnectCaptureButton = [NSButton buttonWithTitle:@"重连采集卡" target:self action:@selector(reconnectCaptureDevice:)];
    reconnectCaptureButton.bezelStyle = NSBezelStyleRounded;
    [deviceRow addArrangedSubview:self.captureDevicePopup];
    [deviceRow addArrangedSubview:refreshDevicesButton];
    [deviceRow addArrangedSubview:reconnectCaptureButton];
    [captureControls addArrangedSubview:[self settingsRowWithLabel:@"采集卡设备" view:deviceRow]];

    self.captureStatusLabel = [self mutedLabel:@"采集卡未启动"];
    self.captureStatusLabel.maximumNumberOfLines = 4;
    self.captureStatusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [captureControls addArrangedSubview:self.captureStatusLabel];

    // —— 画面区域校准：真正决定「视频像素 → 屏幕」映射的就是这里框选的结果 ——
    NSStackView *calibrationRow = [self horizontalStack];
    self.captureCalibrateButton = [NSButton buttonWithTitle:@"调整贴译位置" target:self action:@selector(beginCaptureCardCalibration:)];
    self.captureCalibrateButton.bezelStyle = NSBezelStyleRounded;
    self.captureCalibrateClearButton = [NSButton buttonWithTitle:@"恢复自动定位" target:self action:@selector(clearCaptureCardCalibration:)];
    self.captureCalibrateClearButton.bezelStyle = NSBezelStyleRounded;
    [calibrationRow addArrangedSubview:self.captureCalibrateButton];
    [calibrationRow addArrangedSubview:self.captureCalibrateClearButton];
    [captureControls addArrangedSubview:[self settingsRowWithLabel:@"贴译位置" view:calibrationRow]];
    self.captureCalibrationLabel = [self mutedLabel:@""];
    self.captureCalibrationLabel.maximumNumberOfLines = 3;
    self.captureCalibrationLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [captureControls addArrangedSubview:self.captureCalibrationLabel];
    // 只有"已被明确拒绝"时系统才不会再次弹窗，这时才需要这个手动入口。
    self.captureSettingsButton = [NSButton buttonWithTitle:@"打开相机权限设置" target:self action:@selector(openCameraAccessSettings:)];
    self.captureSettingsButton.bezelStyle = NSBezelStyleRounded;
    NSStackView *settingsRow = [self horizontalStack];
    [settingsRow addArrangedSubview:self.captureSettingsButton];
    [captureControls addArrangedSubview:settingsRow];
    self.captureSettingsButton.hidden = YES;

    NSStackView *captureNotes = [self verticalStack];
    captureNotes.spacing = 4;
    [captureNotes addArrangedSubview:[self mutedLabel:@"只读取视频，不使用麦克风，也不采集屏幕音频。"]];
    [captureNotes addArrangedSubview:[self mutedLabel:@"不会自动改用内置或手机摄像头；设备不存在、被占用或权限被拒绝时会明确提示。"]];
    [captureNotes addArrangedSubview:[self mutedLabel:@"界面文字会按采集画面在目标窗口里的实际显示区域原位贴译；自动定位不到时可用「调整贴译位置」手动框一次。"]];
    self.captureCardControlsView = captureControls;
    [stack addArrangedSubview:captureControls];

    [stack addArrangedSubview:[self separator]];
    [stack addArrangedSubview:[self label:@"字幕显示窗口" font:FYUIFont(15, NSFontWeightBold) color:[NSColor labelColor]]];

    NSStackView *windowRow = [self horizontalStack];
    self.windowPopup = [[NSPopUpButton alloc] init];
    self.windowPopup.target = self;
    self.windowPopup.action = @selector(windowSelectionChanged:);
    NSButton *refreshButton = [NSButton buttonWithTitle:@"刷新窗口" target:self action:@selector(refreshWindows:)];
    refreshButton.bezelStyle = NSBezelStyleRounded;
    [windowRow addArrangedSubview:self.windowPopup];
    [windowRow addArrangedSubview:refreshButton];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"目标窗口" view:windowRow]];
    [stack addArrangedSubview:[self mutedLabel:@"字幕与前后台规则跟随这个窗口（QuickTime／OBS），与上面的识别输入源相互独立。"]];

    NSStackView *regionButtonRow = [self verticalStack];
    [regionButtonRow addArrangedSubview:[NSButton buttonWithTitle:@"手动框选 OCR 区域" target:self action:@selector(selectOCRRegion:)]];
    [regionButtonRow addArrangedSubview:[NSButton buttonWithTitle:@"显示 OCR 框" target:self action:@selector(showOCRPreview:)]];
    [regionButtonRow addArrangedSubview:[NSButton buttonWithTitle:@"隐藏 OCR 框" target:self action:@selector(hideOCRPreview:)]];
    NSStackView *advanced = [self verticalStack];
    [advanced addArrangedSubview:regionButtonRow];

    self.regionXSlider = [self sliderWithMin:0 max:1 value:0.05 action:@selector(controlValueChanged:)];
    self.regionYSlider = [self sliderWithMin:0 max:1 value:0.52 action:@selector(controlValueChanged:)];
    self.regionWidthSlider = [self sliderWithMin:0.05 max:1 value:0.90 action:@selector(controlValueChanged:)];
    self.regionHeightSlider = [self sliderWithMin:0.05 max:1 value:0.42 action:@selector(controlValueChanged:)];

    // 框选之后可以用这四个滑块微调；比例值以窗口左上角为原点
    NSStackView *fineTuneRow = [self verticalStack];
    NSArray<NSString *> *fineTuneNames = @[@"X", @"Y", @"宽", @"高"];
    NSArray<NSSlider *> *fineTuneSliders = @[self.regionXSlider, self.regionYSlider, self.regionWidthSlider, self.regionHeightSlider];
    for (NSUInteger index = 0; index < fineTuneSliders.count; index++) {
        NSSlider *slider = fineTuneSliders[index];
        slider.controlSize = NSControlSizeSmall;
        [fineTuneRow addArrangedSubview:[self settingsRowWithLabel:fineTuneNames[index] view:slider]];
    }
    [advanced addArrangedSubview:[self settingsRowWithLabel:@"区域微调" view:fineTuneRow]];

    NSStackView *regionPresetRow = [self horizontalStack];
    [regionPresetRow addArrangedSubview:[NSButton buttonWithTitle:@"底部字幕" target:self action:@selector(useDefaultSubtitleRegion:)]];
    [regionPresetRow addArrangedSubview:[NSButton buttonWithTitle:@"大字幕" target:self action:@selector(useLargeSubtitleRegion:)]];
    [regionPresetRow addArrangedSubview:[NSButton buttonWithTitle:@"整窗" target:self action:@selector(useFullWindowRegion:)]];
    [regionPresetRow addArrangedSubview:[NSButton buttonWithTitle:@"界面全文" target:self action:@selector(useInterfaceFullWindowPreset:)]];
    [advanced addArrangedSubview:regionPresetRow];
    [stack addArrangedSubview:[self disclosureWithTitle:@"调整识别区域" content:advanced]];
    return stack;
}

- (NSView *)translationCard {
    NSStackView *stack = [self verticalStack];

    self.baseURLField = [self textField:@"https://api.openai.com/v1"];
    self.modelField = [self textField:@"gpt-4.1-mini"];
    self.apiKeyField = [[NSSecureTextField alloc] init];
    self.apiKeyField.placeholderString = @"API Key";
    [self.apiKeyField.widthAnchor constraintGreaterThanOrEqualToConstant:240].active = YES;
    self.apiKeyField.delegate = self;

    NSStackView *apiKeyRow = [self horizontalStack];
    NSButton *pasteAPIKeyButton = [NSButton buttonWithTitle:@"从剪贴板粘贴" target:self action:@selector(pasteAPIKeyFromClipboard:)];
    NSButton *clearAPIKeyButton = [NSButton buttonWithTitle:@"清空" target:self action:@selector(clearAPIKey:)];
    pasteAPIKeyButton.bezelStyle = NSBezelStyleRounded;
    clearAPIKeyButton.bezelStyle = NSBezelStyleRounded;
    [apiKeyRow addArrangedSubview:self.apiKeyField];
    [apiKeyRow addArrangedSubview:pasteAPIKeyButton];
    [apiKeyRow addArrangedSubview:clearAPIKeyButton];

    [stack addArrangedSubview:[self settingsRowWithLabel:@"Base URL" view:self.baseURLField]];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"模型名" view:self.modelField]];
    self.realtimeModelField = [self textField:@"deepseek-flash"];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"实时模型" view:self.realtimeModelField]];
    self.learningModelField = [self textField:@"留空复用模型名"];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"学习模型" view:self.learningModelField]];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"API Key" view:apiKeyRow]];

    NSStackView *presetRow = [self horizontalStack];
    [presetRow addArrangedSubview:[NSButton buttonWithTitle:@"DeepSeek Pro" target:self action:@selector(useDeepSeekPreset:)]];
    [presetRow addArrangedSubview:[NSButton buttonWithTitle:@"DeepSeek Flash" target:self action:@selector(useDeepSeekFlashPreset:)]];
    [presetRow addArrangedSubview:[NSButton buttonWithTitle:@"OpenAI 预设" target:self action:@selector(useOpenAIPreset:)]];
    [stack addArrangedSubview:presetRow];

    NSStackView *row = [self horizontalStack];
    [row addArrangedSubview:[NSButton buttonWithTitle:@"测试翻译" target:self action:@selector(testTranslation:)]];
    [stack addArrangedSubview:row];
    [stack addArrangedSubview:[self label:@"实时翻译使用实时模型；翻译当前界面使用模型名；语法分析使用学习模型，留空则复用模型名。API Key 保存在本机 UserDefaults。" font:FYUIFont(12, NSFontWeightRegular) color:[NSColor secondaryLabelColor]]];
    [stack addArrangedSubview:[self label:@"服务状态以测试翻译的结果为准。" font:FYUIFont(12, NSFontWeightRegular) color:[NSColor secondaryLabelColor]]];
    self.serviceErrorLabel = [self label:@"" font:FYUIFont(12, NSFontWeightRegular) color:[NSColor systemRedColor]];
    self.serviceErrorLabel.maximumNumberOfLines = 3;
    [stack addArrangedSubview:self.serviceErrorLabel];
    [stack addArrangedSubview:[self separator]];
    [stack addArrangedSubview:[self cardTitle:@"离线学习资料"]];
    [stack addArrangedSubview:[self mutedLabel:@"词义来自 JMdict，日文例句来自 Tatoeba，参考等级来自 OpenJLPT。下面说明资料的作者和使用许可，与翻译接口配置无关。"]];
    NSStackView *licenseContent = [self verticalStack];
    [licenseContent addArrangedSubview:[self makeLicenseNotesView]];
    [licenseContent addArrangedSubview:[self workspaceButton:@"在 Finder 查看完整许可文件 ↗" action:@selector(showReferenceLicenses:) primary:NO]];
    [stack addArrangedSubview:[self disclosureWithTitle:@"资料来源与许可" content:licenseContent]];
    return stack;
}

- (NSView *)captionCard {
    NSStackView *stack = [self verticalStack];

    self.captionOpacitySlider = [self sliderWithMin:0 max:0.95 value:0.58 action:@selector(controlValueChanged:)];
    self.captionFontSizeSlider = [self sliderWithMin:18 max:56 value:30 action:@selector(controlValueChanged:)];
    self.captionHeightSlider = [self sliderWithMin:120 max:340 value:180 action:@selector(controlValueChanged:)];
    self.captionThemeControl = [self segmentedWithLabels:@[@"黑底白字", @"白底黑字", @"粉底深字", @"译芽花境"] action:@selector(controlValueChanged:)];
    self.captionThemeControl.selectedSegment = 3;
    [stack addArrangedSubview:[self settingsRowWithLabel:@"背景透明度" view:self.captionOpacitySlider]];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"字号" view:self.captionFontSizeSlider]];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"最小高度" view:self.captionHeightSlider]];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"样式" view:self.captionThemeControl]];
    [stack addArrangedSubview:[self label:@"字幕窗可以直接拖动；字号、透明度和样式也会同步到实时贴译。" font:FYUIFont(12, NSFontWeightRegular) color:[NSColor secondaryLabelColor]]];
    return stack;
}

- (void)createCaptionWindow {
    self.captionPanel = [[FYStudyOverlayPanel alloc] initWithContentRect:NSMakeRect(360, 92, 900, 180)
                                                   styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    self.captionPanel.backgroundColor = [NSColor clearColor];
    self.captionPanel.opaque = NO;
    self.captionPanel.hasShadow = YES;
    self.captionPanel.level = NSNormalWindowLevel;
    self.captionPanel.hidesOnDeactivate = NO;
    self.captionPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.captionPanel.movableByWindowBackground = YES;

    self.captionContainer = [[FYAdventurePanel alloc] initWithFrame:self.captionPanel.contentView.bounds];
    self.captionContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.captionContainer.wantsLayer = YES;

    [self.captionPanel.contentView addSubview:self.captionContainer];

    self.captionTextLabel = [self label:@"点击开始翻译" font:FYUIFont(30, NSFontWeightSemibold) color:[NSColor whiteColor]];
    self.captionTextLabel.alignment = NSTextAlignmentLeft;
    self.captionTextLabel.selectable = YES;
    self.captionTextLabel.maximumNumberOfLines = 5;
    self.captionTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.captionTextLabel.usesSingleLineMode = NO;
    self.captionTextLabel.cell.wraps = YES;
    self.captionTextLabel.cell.scrollable = NO;
    self.captionTextLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.captionContainer addSubview:self.captionTextLabel];
    self.captionBrandLabel = [self label:@"译芽 · 当前译文" font:FYUIFont(13, NSFontWeightSemibold) color:FYAdventureColor(@"quiet")];
    [self.captionContainer addSubview:self.captionBrandLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.captionBrandLabel.leadingAnchor constraintEqualToAnchor:self.captionContainer.leadingAnchor constant:24],
        [self.captionBrandLabel.topAnchor constraintEqualToAnchor:self.captionContainer.topAnchor constant:17]]];
    self.captionHideButton = [FYWorkspaceButton buttonWithTitle:@"⌄" target:self action:@selector(hideCaptionPanel:)];
    self.captionHideButton.translatesAutoresizingMaskIntoConstraints = NO;
    ((FYWorkspaceButton *)self.captionHideButton).darkSurface=YES;
    self.captionHideButton.bezelStyle = NSBezelStyleRounded;
    self.captionHideButton.font = FYUIFont(11, NSFontWeightRegular);
    self.captionHideButton.toolTip = @"收起字幕为快捷小条 · ⌃⌥T";
    self.captionHideButton.accessibilityLabel = @"收起字幕";
    [self.captionContainer addSubview:self.captionHideButton];
    [self createCaptionDock];
    NSButton *captionAsk=[self workspaceButton:@"问 AI" action:@selector(showStudyChatOverlay:) primary:NO];
    NSButton *captionSentence=[self workspaceButton:@"看原句" action:@selector(showQuickSentence:) primary:NO];
    captionAsk.translatesAutoresizingMaskIntoConstraints=NO;captionSentence.translatesAutoresizingMaskIntoConstraints=NO;
    [self.captionContainer addSubview:captionAsk];[self.captionContainer addSubview:captionSentence];
    [NSLayoutConstraint activateConstraints:@[[captionAsk.topAnchor constraintEqualToAnchor:self.captionContainer.topAnchor constant:8],[captionAsk.trailingAnchor constraintEqualToAnchor:self.captionHideButton.leadingAnchor constant:-8],[captionSentence.topAnchor constraintEqualToAnchor:captionAsk.topAnchor],[captionSentence.trailingAnchor constraintEqualToAnchor:captionAsk.leadingAnchor constant:-8]]];

    [NSLayoutConstraint activateConstraints:@[
        [self.captionHideButton.topAnchor constraintEqualToAnchor:self.captionContainer.topAnchor constant:8],
        [self.captionHideButton.trailingAnchor constraintEqualToAnchor:self.captionContainer.trailingAnchor constant:-12],
        [self.captionTextLabel.leadingAnchor constraintEqualToAnchor:self.captionContainer.leadingAnchor constant:24],
        [self.captionTextLabel.trailingAnchor constraintEqualToAnchor:self.captionContainer.trailingAnchor constant:-24],
        [self.captionTextLabel.topAnchor constraintGreaterThanOrEqualToAnchor:self.captionContainer.topAnchor constant:52],
        [self.captionTextLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.captionContainer.bottomAnchor constant:-22],
        [self.captionTextLabel.centerYAnchor constraintEqualToAnchor:self.captionContainer.centerYAnchor constant:12]
    ]];
}

- (void)showCaptionAppearancePreview:(id)sender {
    if (!self.captionAppearancePreviewPanel) {
        CGFloat width = MIN((CGFloat)900,NSWidth((self.mainWindow.screen ?: NSScreen.mainScreen).visibleFrame)-80);
        NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,MAX(480,width),180)
            styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        panel.title = @"字幕样式预览 · 示例文字";
        panel.releasedWhenClosed = NO;
        panel.hidesOnDeactivate = YES;
        panel.backgroundColor = NSColor.clearColor;
        panel.opaque = NO;
        panel.hasShadow = YES;
        self.captionAppearancePreviewPanel = panel;
        FYAdventurePanel *surface = [[FYAdventurePanel alloc] initWithFrame:panel.contentView.bounds];
        surface.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
        panel.contentView = surface;
        self.captionAppearancePreviewContainer = surface;
        self.captionAppearancePreviewBrand = [self label:@"译芽 · 字幕样式预览（示例）" font:FYUIFont(13,NSFontWeightSemibold) color:[self captionSecondaryTextColor]];
        self.captionAppearancePreviewText = [self label:@"这是字幕样式预览。\n调整字号、配色和透明度，即可看到变化。" font:FYUIFont(30,NSFontWeightRegular) color:[self captionTextColor]];
        self.captionAppearancePreviewText.selectable = YES;
        [surface addSubview:self.captionAppearancePreviewBrand];
        [surface addSubview:self.captionAppearancePreviewText];
        [NSLayoutConstraint activateConstraints:@[
            [self.captionAppearancePreviewBrand.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:24],
            [self.captionAppearancePreviewBrand.topAnchor constraintEqualToAnchor:surface.topAnchor constant:17],
            [self.captionAppearancePreviewText.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:24],
            [self.captionAppearancePreviewText.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-24],
            [self.captionAppearancePreviewText.topAnchor constraintGreaterThanOrEqualToAnchor:surface.topAnchor constant:52],
            [self.captionAppearancePreviewText.bottomAnchor constraintLessThanOrEqualToAnchor:surface.bottomAnchor constant:-22],
            [self.captionAppearancePreviewText.centerYAnchor constraintEqualToAnchor:surface.centerYAnchor constant:12]]];
        [self.mainWindow addChildWindow:panel ordered:NSWindowAbove];
    }
    [self updateCaptionAppearancePreview];
    NSRect visible=(self.mainWindow.screen ?: NSScreen.mainScreen).visibleFrame;
    [self.captionAppearancePreviewPanel setFrameOrigin:NSMakePoint(NSMidX(visible)-NSWidth(self.captionAppearancePreviewPanel.frame)/2,NSMinY(visible)+24)];
    [self.captionAppearancePreviewPanel orderFront:nil];
}

- (void)updateCaptionAppearancePreview {
    if (!self.captionAppearancePreviewPanel) { return; }
    self.captionAppearancePreviewContainer.fillColor = [self captionBackgroundColorWithAlpha:self.captionOpacitySlider.doubleValue];
    self.captionAppearancePreviewContainer.edgeColor = [self captionBorderColor];
    self.captionAppearancePreviewText.font = FYUIFont(self.captionFontSizeSlider.doubleValue,NSFontWeightRegular);
    self.captionAppearancePreviewText.textColor = [self captionTextColor];
    self.captionAppearancePreviewBrand.textColor = [self captionSecondaryTextColor];
    CGFloat width=NSWidth(self.captionAppearancePreviewPanel.contentView.bounds);
    NSRect measured=[self.captionAppearancePreviewText.stringValue boundingRectWithSize:NSMakeSize(MAX(1,width-48),CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
        attributes:@{NSFontAttributeName:self.captionAppearancePreviewText.font}];
    CGFloat height=MAX(MAX((CGFloat)140,self.captionHeightSlider.doubleValue),ceil(NSHeight(measured))+84);
    [self.captionAppearancePreviewPanel setContentSize:NSMakeSize(width,height)];
}

- (NSStackView *)verticalStack {
    NSStackView *stack = [[FYLearningStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.distribution = NSStackViewDistributionFill;
    [stack setContentHuggingPriority:750 forOrientation:NSLayoutConstraintOrientationVertical];
    return stack;
}

- (NSStackView *)horizontalStack {
    NSStackView *stack = [[FYLearningRowView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.distribution = NSStackViewDistributionFill;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = 10;
    return stack;
}

// Settings use labels above controls so fixed input/action widths do not
// resize the outer window when the AI sidebar leaves a narrow workspace.
- (NSView *)settingsRowWithLabel:(NSString *)label view:(NSView *)view {
    NSStackView *row = [self verticalStack]; row.spacing = 6;
    [row addArrangedSubview:[self label:label font:FYUIFont(13, NSFontWeightRegular) color:[NSColor secondaryLabelColor]]];
    view.accessibilityLabel = label;
    [row addArrangedSubview:view];
    return row;
}

- (NSView *)rowWithLabel:(NSString *)label view:(NSView *)view {
    NSStackView *row = [self horizontalStack];
    NSTextField *labelView = [self label:label font:FYUIFont(13, NSFontWeightRegular) color:[NSColor secondaryLabelColor]];
    [labelView.widthAnchor constraintEqualToConstant:88].active = YES;
    view.accessibilityLabel = label;
    [view.widthAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;
    [view setContentHuggingPriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addArrangedSubview:labelView];
    [row addArrangedSubview:view];
    return row;
}

- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.font = font;
    label.textColor = [color isEqual:NSColor.labelColor] ? FYAdventureColor(@"ink") : [color isEqual:NSColor.secondaryLabelColor] ? FYAdventureColor(@"muted") : color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.maximumNumberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    [label setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

- (NSTextField *)textField:(NSString *)placeholder {
    NSTextField *field = [[NSTextField alloc] init];
    field.placeholderString = placeholder;
    field.font = FYUIFont(13, NSFontWeightRegular);
    field.textColor = FYAdventureColor(@"ink");
    field.target = self;
    field.action = @selector(controlValueChanged:);
    field.delegate = self;
    return field;
}

- (NSView *)disclosureWithTitle:(NSString *)title content:(NSView *)content {
    NSStackView *container = [self verticalStack];
    NSButton *button = [NSButton buttonWithTitle:title target:self action:@selector(toggleDisclosure:)];
    button.bezelStyle = NSBezelStyleRounded;
    [button setButtonType:NSButtonTypePushOnPushOff];
    button.state = NSControlStateValueOff;
    if (!self.disclosureViews) { self.disclosureViews = [NSMutableArray array]; }
    button.tag = self.disclosureViews.count;
    [self.disclosureViews addObject:content];
    content.hidden = YES;
    [container addArrangedSubview:button];
    [container addArrangedSubview:content];
    return container;
}

- (void)toggleDisclosure:(NSButton *)sender {
    NSView *content = self.disclosureViews[sender.tag];
    content.hidden = sender.state != NSControlStateValueOn;
}

- (NSSlider *)sliderWithMin:(double)min max:(double)max value:(double)value action:(SEL)action {
    NSSlider *slider = [NSSlider sliderWithValue:value minValue:min maxValue:max target:self action:action];
    slider.continuous = YES;
    return slider;
}

- (NSSegmentedControl *)segmentedWithLabels:(NSArray<NSString *> *)labels action:(SEL)action {
    NSSegmentedControl *control = [[NSSegmentedControl alloc] init];
    control.segmentCount = labels.count;
    control.segmentStyle = NSSegmentStyleRounded;
    control.trackingMode = NSSegmentSwitchTrackingSelectOne;
    control.target = self;
    control.action = action;
    for (NSInteger i = 0; i < labels.count; i++) {
        [control setLabel:labels[i] forSegment:i];
    }
    control.selectedSegment = 0;
    return control;
}

- (NSView *)spacer {
    NSView *view = [[NSView alloc] init];
    [view setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return view;
}

- (NSView *)separator {
    NSBox *box = [[NSBox alloc] init];
    box.boxType = NSBoxSeparator;
    return box;
}

#pragma mark - UI theme helpers

- (NSColor *)uiInk { return FYAdventureColor(@"ink"); }
- (NSColor *)uiMuted { return FYAdventureColor(@"muted"); }
- (NSColor *)uiBorder { return FYAdventureColor(@"rim"); }
- (NSColor *)uiAccent { return FYAdventureColor(@"teal"); }
- (NSColor *)uiSelected { return FYAdventureColor(@"mint"); }
- (NSColor *)uiSurface { return FYAdventureColor(@"paper"); }

- (NSView *)card {
    FYAdventurePanel *card=[FYAdventurePanel new];
    card.translatesAutoresizingMaskIntoConstraints=NO;
    return card;
}

// 用统一卡片包裹内容，内边距 20。
- (NSView *)cardWithStack:(NSStackView *)stack {
    NSView *card = [self card];
    stack.edgeInsets = NSEdgeInsetsMake(0, 0, 0, 0);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card setContentHuggingPriority:750 forOrientation:NSLayoutConstraintOrientationVertical];
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14]
    ]];
    return card;
}

// 让子视图占满父 stack 的宽度（stack.alignment=Leading 时卡片需要显式拉伸）。
- (void)pinFullWidth:(NSView *)view toStack:(NSStackView *)stack {
    [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}

- (NSTextField *)cardTitle:(NSString *)text {
    return [self label:text font:FYUIFont(17, NSFontWeightSemibold) color:self.uiInk];
}

- (NSTextField *)mutedLabel:(NSString *)text {
    return [self label:text font:FYUIFont(12, NSFontWeightRegular) color:self.uiMuted];
}

#pragma mark - Actions

- (void)toggleRunning:(id)sender {
    self.running ? [self stop] : [self start];
}

- (void)start {
    if (self.running) { return; }

    if (![self selectedWindowID]) {
        [self setStatus:@"请先选择字幕显示窗口（QuickTime 或 OBS）"];
        return;
    }

    if ([self captureCardInputEnabled]) {
        // 采集卡模式不需要屏幕录制权限。相机权限在这里（用户点了「开始翻译」）按需申请：
        // 第一次弹系统提示，批准后自动继续；已被拒绝时系统不会再弹，只给设置入口。
        if ([self.captureCardInput availability] != FYCaptureCardAvailabilityAuthorized) {
            __weak typeof(self) weakSelf = self;
            [self ensureCaptureCardPermissionThen:^(BOOL granted) {
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) { return; }
                if (granted) { [strongSelf start]; } else { [strongSelf updateCaptureCardStatus]; }
            }];
            return;
        }
        if (![self startCaptureCardSessionIfPossible]) { return; }
    } else if (![self hasUsableScreenCaptureAccess]) {
        [self handleMissingScreenAccessForStart];
        return;
    }

    self.lastOCRedCaptureFrameIndex = 0;
    self.running = YES;
    self.captureUnavailable = NO;
    self.runButton.title = @"暂停翻译";
    [self updateRunState];
    self.translationGeneration += 1;
    self.lastTranslatedNormalizedText = @"";
    self.lastSubmittedNormalizedText = @"";
    self.lastTranslationAttemptDate = nil;
    self.stableCandidate = @"";
    self.stableCandidateCount = 0;
    [self setStatus:@"正在监测画面"];

    self.timer = [NSTimer scheduledTimerWithTimeInterval:MAX(0.5, self.intervalSlider.doubleValue)
                                                  target:self
                                                selector:@selector(timerFired:)
                                                userInfo:nil
                                                 repeats:YES];
    [self timerFired:self.timer];
}

- (void)stop {
    // 停采立刻释放采集会话并作废旧帧：暂停后不会再有画面进入 OCR。
    [self.captureCardInput stop];
    self.lastOCRedCaptureFrameIndex = 0;
    [self.timer invalidate];
    self.timer = nil;
    self.running = NO;
    self.captureUnavailable = NO;
    self.inFlight = NO;
    self.translationGeneration += 1;
    [self.activeTranslationTask cancel];
    self.activeTranslationTask = nil;
    if ([self.serviceStatusLabel.stringValue isEqualToString:@"正在测试服务"]) {
        self.serviceTestGeneration += 1;
        self.serviceStatusLabel.stringValue = @"服务未测试";
    }
    // 停止时把自己画在桌面上的东西收干净：贴译面板会留在屏幕上一直不走，
    // 因为它们由定时循环负责清理，循环一停就没人管了。
    [self clearInlineTranslationPanels];
    [self.inlineTranslationCache removeAllObjects];
    self.lastInlineTranslationKey = nil;
    [self setCaptionPanelVisibleForUIMode:NO];
    self.runButton.title = @"开始翻译";
    [self updateRunState];
    [self setStatus:@"已暂停"];
}

- (void)handleInlineTranslationResult:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items error:(NSError *)translationError failureStatus:(NSString *)failureStatus successPrefix:(NSString *)successPrefix {
    NSDictionary *trace = FYCurrentTrace();
    NSInteger generation = self.translationGeneration;
    NSInteger mode = [self effectiveModeSegment];
    NSUInteger inputEpoch = self.captureCardInput.sessionEpoch;
    // 先建立"画面 → 显示区域"的落位矩形：窗口截图用整个目标窗口，采集卡用视频帧适配后的可见矩形。
    NSRect placement = NSZeroRect;
    NSString *placementReason = nil;
    BOOL hasPlacement = [self inlinePlacementRect:&placement reason:&placementReason];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self.translationGeneration || inputEpoch != self.captureCardInput.sessionEpoch ||
            (self.running && mode != [self effectiveModeSegment])) {
            NSString *reason = generation != self.translationGeneration ? @"generation_changed"
                : (inputEpoch != self.captureCardInput.sessionEpoch ? @"input_session_changed" : @"mode_changed");
            FYTrace(trace, @"inline_drop", @{@"reason": reason});
            return;
        }
        if (translationError) {
            FYTrace(trace, @"inline_drop", @{@"reason": @"translation_error", @"error_code": @(translationError.code)});
            [self showError:translationError.localizedDescription];
            [self setStatus:failureStatus];
            return;
        }
        if (!hasPlacement) {
            // 映射不可用：明确提示，绝不静默把界面译文塞进对白框。
            [self clearInlineTranslationPanels];
            [self showInlineMappingUnavailableNotice:placementReason];
            FYTrace(trace, @"inline_drop", @{@"reason": @"mapping_unavailable", @"detail": placementReason ?: @""});
            return;
        }
        [self showError:@""];
        [self showInlineTranslations:translations forItems:items placementRect:placement];
        FYTrace(trace, @"inline_apply", @{@"source": [[items valueForKey:@"text"] componentsJoinedByString:@"\n"] ?: @"", @"translation": [translations componentsJoinedByString:@"\n"] ?: @"", @"blocks": @(items.count)});
        // 集中查看走实时页的「界面译文」列表（refreshInlineTranslationList，在 showInlineTranslations 里刷新），
        // 不再写 latestTranslationLabel/latestSourceLabel —— 那两个控件从未创建，用户根本看不到。
        [self refreshInlineTranslationList];
        NSUInteger shown = 0;
        for (NSString *value in translations) {
            if (Trim(value).length > 0) { shown += 1; }
        }
        NSString *statusText = [NSString stringWithFormat:@"%@：%lu 条", successPrefix, (unsigned long)shown];
        if (self.lastInlineCompactEntryCount > 0) {
            statusText = [statusText stringByAppendingFormat:@"，%lu 条用「查看译文」入口",
                          (unsigned long)self.lastInlineCompactEntryCount];
        }
        if (self.lastInlineUnplaceableCount > 0) {
            // 没有合法位置的块绝不能静默丢弃：状态区给条数**和第一条译文原文**，
            // 用户在主界面就能直接读到内容（完整译文也写进主界面译文区）。
            NSString *firstUnplaced = nil;
            for (FYInlinePlacement *placement in self.lastInlineLayoutResult.placements) {
                if (placement.mode != FYInlineDisplayModeUnplaceable) { continue; }
                if (Trim(placement.translation).length > 0) { firstUnplaced = Trim(placement.translation); break; }
            }
            statusText = firstUnplaced.length > 0
                ? [statusText stringByAppendingFormat:@"，%lu 条暂不可放置：%@",
                   (unsigned long)self.lastInlineUnplaceableCount, Shorten(firstUnplaced, 40)]
                : [statusText stringByAppendingFormat:@"，%lu 条暂不可放置", (unsigned long)self.lastInlineUnplaceableCount];
        }
        [self setStatus:statusText];
    });
}

// 目标窗口的所属进程。用 IncludingWindow 查询，**即使目标此刻不在屏幕上也要能查到**：
// OBS 的「全屏预览／预览投影」会把主窗口挤进独立空间，那时按窗口号反查不到所有者，
// 前后台规则就会误判成"目标不在前台"而把字幕窗藏起来。
- (pid_t)selectedWindowOwnerPID {
    uint32_t windowID = [self selectedWindowID];
    if (!windowID) { return 0; }
    NSArray *entries = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, windowID));
    for (NSDictionary *entry in entries) {
        if ([entry[(id)kCGWindowNumber] unsignedIntValue] == windowID) {
            return (pid_t)[entry[(id)kCGWindowOwnerPID] intValue];
        }
    }
    return 0;
}

// 纯策略：什么时候该显示浮窗。
// 原规则要求"选中的那个窗口本身在屏幕上且它的应用在前台"，遇到 OBS 全屏预览/投影时，
// 主窗口被投影窗接管、不再出现在屏幕上的窗口列表里，于是字幕被误隐藏。
// 现在改成：目标应用在前台，且（目标窗口在屏幕上，或该应用在屏幕上还有别的窗口）就算前台。
// 目标应用不在前台、或整个应用没有窗口在屏幕上（切到别的空间／最小化）仍然隐藏。
- (BOOL)targetQualifiesForOverlayWithFrontmostPID:(pid_t)frontPID
                                        targetPID:(pid_t)targetPID
                                   targetOnScreen:(BOOL)targetOnScreen
                         ownerHasOnScreenWindow:(BOOL)ownerHasOnScreenWindow
                            interactingWithOverlay:(BOOL)interactingWithOverlay {
    // 自己正在操作的辅助面板也算在目标上前台，避免点按钮时浮窗自己消失。
    if (interactingWithOverlay) { return YES; }
    if (frontPID <= 0 || targetPID <= 0 || frontPID != targetPID) { return NO; }
    return targetOnScreen || ownerHasOnScreenWindow;
}

// 纯策略：浮窗层级跟随目标应用自己用的最高层级。
// 实测 OBS 的预览/投影窗口在 101（NSPopUpMenuWindowLevel），固定用
// NSFloatingWindowLevel(3) 会被它压住。只按目标应用的窗口取层级，上限 102，
// 不越过系统的屏幕保护/告警层级。
- (NSWindowLevel)overlayLevelForTargetPID:(pid_t)targetPID inWindowList:(NSArray<NSDictionary *> *)windows {
    if (targetPID <= 0) { return NSFloatingWindowLevel; }
    NSInteger highest = 0;
    for (NSDictionary *info in windows) {
        if ((pid_t)[info[(id)kCGWindowOwnerPID] intValue] != targetPID) { continue; }
        highest = MAX(highest, [info[(id)kCGWindowLayer] integerValue]);
    }
    NSInteger level = MIN(highest + 1, (NSInteger)NSPopUpMenuWindowLevel + 1);
    return (NSWindowLevel)MAX((NSInteger)NSFloatingWindowLevel, level);
}

// Visibility is independent of OCR completion: late replies cannot raise overlays above another app.
- (BOOL)translationTargetIsForeground {
    NSArray *visibleWindows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    return [self translationTargetIsForegroundWithWindowList:visibleWindows];
}

- (BOOL)translationTargetIsForegroundWithWindowList:(NSArray<NSDictionary *> *)visibleWindows {
    uint32_t windowID = [self selectedWindowID];
    if (!windowID) { return NO; }
    pid_t frontPID = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    // Some AppKit controls activate the owner even in an auxiliary panel.
    // Keep explicitly used game panels visible; opening the main app still hides them.
    NSWindow *key = NSApp.keyWindow;
    BOOL interactingWithOverlay = frontPID == getpid() && key.isVisible &&
        (key == self.captionPanel || key == self.captionDockPanel || key == self.studyChatPanel || key == self.quickSentencePanel);
    pid_t targetPID = [self selectedWindowOwnerPID];
    BOOL targetOnScreen = NO;
    for (NSDictionary *info in visibleWindows) {
        if ([info[(id)kCGWindowNumber] unsignedIntValue] != windowID) { continue; }
        targetOnScreen = YES;
        if (targetPID <= 0) { targetPID = (pid_t)[info[(id)kCGWindowOwnerPID] intValue]; }
        break;
    }
    BOOL ownerHasOnScreenWindow = NO;
    if (targetPID > 0) {
        for (NSDictionary *info in visibleWindows) {
            if ((pid_t)[info[(id)kCGWindowOwnerPID] intValue] == targetPID) { ownerHasOnScreenWindow = YES; break; }
        }
    }
    return [self targetQualifiesForOverlayWithFrontmostPID:frontPID
                                                targetPID:targetPID
                                           targetOnScreen:targetOnScreen
                                 ownerHasOnScreenWindow:ownerHasOnScreenWindow
                                    interactingWithOverlay:interactingWithOverlay];
}

- (void)refreshOverlayVisibility:(id)sender {
    // 仍然走可覆盖的 translationTargetIsForeground（测试沿用同一个接缝）。
    BOOL targetActive = !self.selectingCaptureRegion && [self translationTargetIsForeground];
    NSArray *visibleWindows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    NSWindowLevel overlayLevel = [self overlayLevelForTargetPID:[self selectedWindowOwnerPID] inWindowList:visibleWindows];
    BOOL showCaption = targetActive && self.captionPanelShownByUser && !self.captionSuppressedForUIMode;
    self.captionPanel.level = showCaption ? overlayLevel : NSNormalWindowLevel;
    if (showCaption) {
        if (!self.captionPanel.isVisible) { [self.captionPanel orderFrontRegardless]; }
    } else if (self.captionPanel.isVisible) { [self.captionPanel orderOut:nil]; }
    BOOL showDock=targetActive && !self.captionPanelShownByUser && !self.captionSuppressedForUIMode;
    self.captionDockPanel.level = overlayLevel;
    if(showDock){
        if(!self.captionDockHasAnchor){[self anchorCaptionDockToCaption];}
        [self.captionDockPanel orderFrontRegardless];
    }else{[self.captionDockPanel orderOut:nil];}
    for(NSPanel *overlay in @[self.studyChatPanel ?: (id)NSNull.null,self.quickSentencePanel ?: (id)NSNull.null]){
        if(![overlay isKindOfClass:NSPanel.class]){continue;}
        overlay.level = overlayLevel;
        BOOL requested=overlay==self.studyChatPanel?self.studyChatOverlayRequested:self.quickSentenceRequested;
        if(targetActive && requested){[overlay orderFrontRegardless];}else{[overlay orderOut:nil];}
    }
    NSMutableArray<NSPanel *> *overlays = [[self.inlineTranslationPanels arrayByAddingObjectsFromArray:self.inlineLongCardPanels] mutableCopy];
    if (self.inlineExpandedReadingPanel) { [overlays addObject:self.inlineExpandedReadingPanel]; }
    for (NSPanel *panel in overlays) {
        panel.level = overlayLevel;
        if (targetActive) {
            if (!panel.isVisible) { [panel orderFrontRegardless]; }
        } else if (panel.isVisible) { [panel orderOut:nil]; }
    }
}

- (void)anchorCaptionDockToCaption {
    if(!self.captionPanel || !self.captionDockPanel){return;}
    NSRect frame=self.captionPanel.frame;
    NSRect visible=(self.captionPanel.screen ?: NSScreen.mainScreen).visibleFrame;
    NSSize size=self.captionDockPanel.frame.size;
    // Match the prototype's bottom baseline once when collapsing. Hidden OCR
    // updates may resize the caption; they must never move the recovery dock.
    NSPoint origin=NSMakePoint(NSMidX(frame)-size.width/2,NSMinY(frame));
    if(!NSIsEmptyRect(visible)){
        origin.x=MAX(NSMinX(visible),MIN(origin.x,NSMaxX(visible)-size.width));
        origin.y=MAX(NSMinY(visible),MIN(origin.y,NSMaxY(visible)-size.height));
    }
    [self.captionDockPanel setFrameOrigin:origin];self.captionDockHasAnchor=YES;
}

- (void)hideCaptionPanel:(id)sender {
    if(self.captionPanelShownByUser || !self.captionDockHasAnchor){[self anchorCaptionDockToCaption];}
    self.captionPanelShownByUser = NO;
    [self refreshOverlayVisibility:nil];
}

- (void)showCaptionPanel:(id)sender {
    if(!self.captionPanelShownByUser && self.captionDockHasAnchor){
        NSRect dock=self.captionDockPanel.frame,frame=self.captionPanel.frame;
        frame.origin=NSMakePoint(NSMidX(dock)-NSWidth(frame)/2,NSMinY(dock));
        [self.captionPanel setFrame:frame display:NO];
    }
    self.captionPanelShownByUser = YES;
    [self refreshOverlayVisibility:nil];
}

- (void)setCaptionPanelVisibleForUIMode:(BOOL)uiMode {
    self.captionSuppressedForUIMode = uiMode;
    if (uiMode) { self.captionTextLabel.stringValue = @""; }
    [self refreshOverlayVisibility:nil];
}

// 界面模式下字幕窗本来就不该显示
- (BOOL)captionPanelShouldBeHidden {
    return self.detectedModeSegment == ContentModeUI;
}

- (void)timerFired:(NSTimer *)timer {
    if (!self.running || self.inFlight) { return; }
    BOOL captureCard = [self captureCardInputEnabled];
    self.inFlight = YES;
    NSDate *cycleStart = [NSDate date];

    uint32_t windowID = [self selectedWindowID];
    NSDictionary *trace = [[FYTranslationTrace shared] beginCycleForWindow:windowID
                                                               generation:self.translationGeneration
                                                               inputEpoch:self.captureCardInput.sessionEpoch
                                                              inputSource:captureCard ? 1 : 0];
    // 采集会话代次：本轮 OCR/翻译用的画面属于哪一次采集会话。
    // 切源、停采、换设备、断连都会让它自增，迟到的结果据此被丢弃。
    NSUInteger inputEpoch = self.captureCardInput.sessionEpoch;
    uint64_t captureFrameIndex = 0;
    CGImageRef fullImage = NULL;
    if (captureCard) {
        // 采集卡模式：只用**新到的**帧。没有新帧就跳过本轮，
        // 绝不把上一次（可能已被录制条遮住或已断开的）画面再送一遍 OCR。
        uint64_t frameIndex = [self.captureCardInput latestFrameIndex];
        if (frameIndex == 0 || frameIndex == self.lastOCRedCaptureFrameIndex) {
            FYTrace(trace, @"skip", @{@"reason": @"capture_card_no_new_frame", @"input_epoch": @(inputEpoch)});
            self.inFlight = NO;
            [self updateCaptureCardStatus];
            if (self.captureCardInput.state == FYCaptureCardSessionStateRunning) {
                [self setStatus:@"等待采集卡新画面"];
            } else {
                [self setStatus:self.captureCardInput.stateDetail];
            }
            return;
        }
        fullImage = [self.captureCardInput copyLatestFrame];
        if (!fullImage) {
            FYTrace(trace, @"skip", @{@"reason": @"capture_card_no_frame", @"input_epoch": @(inputEpoch)});
            self.inFlight = NO;
            [self updateCaptureCardStatus];
            [self setStatus:@"采集卡暂无画面"];
            return;
        }
        self.lastOCRedCaptureFrameIndex = frameIndex;
        captureFrameIndex = frameIndex;
    } else {
        // 自动判别需要看整窗（否则菜单/弹窗不在字幕区域内就判不出来）
        // 这里曾经在截屏前 hide 掉自己的浮窗、截完再恢复。那是闪烁的来源：
        // hide / orderFront 每轮都执行一次，窗口会被合成器移出再移入。
        // 实际不需要：截屏用 CGWindowListCreateImage(IncludingWindow)，只取目标窗口自己的像素；
        // 我们的浮窗是独立窗口且 layer=3/25，目标窗口是 layer=0，本来就不会进截屏。
        fullImage = [self copyFullCapturedImageForWindow:windowID];
        if (!fullImage) {
            FYTrace(trace, @"skip", @{@"reason": @"capture_unavailable"});
            self.inFlight = NO;
            if ([self recoverWindowSelectionIfRecreated]) { return; }
            self.captureUnavailable = YES;
            [self updateRunState];
            [self setStatus:@"截取窗口失败"];
            [self showPreviewUnavailable:@"无法截取目标窗口"];
            return;
        }
    }

    self.captureUnavailable = NO;
    [self updateRunState];
    [self setStatus:@"正在 OCR"];
    NSInteger cycleGeneration = self.translationGeneration;
    [self updatePreviewFromImage:fullImage generation:cycleGeneration];
    BOOL fastOCR = self.fastOCRCheckbox.state == NSControlStateValueOn;
    NSInteger languageSegment = self.languageControl.selectedSegment;
    self.learningCoordinator.japaneseMode = (languageSegment == 0);

    // 在**主线程**上把几何快照好：后台线程不该读 AppKit 控件。
    // 采集卡模式下画面不是屏幕内容，浮窗不可能出现在视频里；
    // 而且视频像素坐标和屏幕坐标没有可靠换算，套用窗口比例会误排除真实对白，所以留空。
    NSMutableArray<NSValue *> *exclusionSnapshot = [NSMutableArray array];
    WindowItem *snapshotWindow = captureCard ? nil : [self selectedWindowItem];
    if (snapshotWindow) {
        NSRect windowFrame = [self appKitFrameForWindowItem:snapshotWindow];
        if (NSWidth(windowFrame) >= 2 && NSHeight(windowFrame) >= 2) {
            NSMutableArray<NSPanel *> *panels = [NSMutableArray array];
            if (self.captionPanel) { [panels addObject:self.captionPanel]; }
            [panels addObjectsFromArray:self.inlineTranslationPanels];
            [panels addObjectsFromArray:self.inlineLongCardPanels];
            for (NSPanel *panel in panels) {
                NSRect frame = panel.frame;
                CGFloat nx = (NSMinX(frame) - NSMinX(windowFrame)) / NSWidth(windowFrame);
                CGFloat ny = (NSMinY(frame) - NSMinY(windowFrame)) / NSHeight(windowFrame);
                CGFloat nw = NSWidth(frame) / NSWidth(windowFrame);
                CGFloat nh = NSHeight(frame) / NSHeight(windowFrame);
                if (nw <= 0 || nh <= 0) { continue; }
                [exclusionSnapshot addObject:[NSValue valueWithRect:NSMakeRect(nx, ny, nw, nh)]];
            }
        }
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDate *ocrStart = [NSDate date];
        NSError *error = nil;
        NSArray<OCRTextItem *> *ocrBlocks = @[];
        // 诊断：把实际送去 OCR 的整窗图存一份（覆盖式，只留最新一帧），
        // 用来看运行时画面和离线截图是否一致。
        // 注意：这会把用户屏幕内容落盘，只能在实际排查时开启（FUYI_DIAG=1），
        // 不能在正式分发版里无条件执行。
        if (FuyiDiagEnabled()) {
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:fullImage];
            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            [png writeToFile:@"/tmp/fuyi-last-frame.png" atomically:YES];
        }
        NSString *ocrText = [self recognizeTextBlocksInImage:fullImage fastOCR:fastOCR languageSegment:languageSegment blocks:&ocrBlocks error:&error];
        NSTimeInterval pass1Duration = [[NSDate date] timeIntervalSinceDate:ocrStart];
        FYTrace(trace, @"ocr", @{@"stage": @"pass1_filtered", @"ocr_lines": FYTraceOCRLines(ocrBlocks),
                                @"blocks": @(ocrBlocks.count), @"fast_ocr": @(fastOCR), @"language": @(languageSegment),
                                @"width": @(CGImageGetWidth(fullImage)), @"height": @(CGImageGetHeight(fullImage)),
                                @"frame_index": @(captureFrameIndex), @"elapsed_ms": @(pass1Duration * 1000)});

        // 自动贴合文字：第一遍先整窗定位文字在哪，然后把那一小块裁出来**放大再识别**。
        // 好处：① 不用用户预先框选固定区域，文字上移/下移都能跟上；
        //      ② 小字放大后识别率明显更好，也更容易扛住被控件切掉一点的情况。
        // 注意挡在文字上的不透明控件是物理遮挡，放大也读不到 —— 那部分救不回来。
        NSArray<OCRTextItem *> *fineBlocks = nil;
        NSString *fineText = nil;
        BOOL autoFit = self.autoFitRegionCheckbox == nil || self.autoFitRegionCheckbox.state == NSControlStateValueOn;
        // 第二遍 OCR 会让每轮耗时翻倍。只在“文字区域本身不大”时才值得放大识别：
        // 区域已经很大时，放大既没有精度收益，又白白多花一整个 OCR 周期。
        CGFloat fittedArea = 0;
        if (ocrBlocks.count > 0) {
            CGFloat fminX = 1.0, fminY = 1.0, fmaxX = 0.0, fmaxY = 0.0;
            BOOL fany = NO;
            for (OCRTextItem *block in ocrBlocks) {
                if (NormalizeForComparison(block.text).length < 2) { continue; }
                fminX = MIN(fminX, CGRectGetMinX(block.boundingBox));
                fminY = MIN(fminY, CGRectGetMinY(block.boundingBox));
                fmaxX = MAX(fmaxX, CGRectGetMaxX(block.boundingBox));
                fmaxY = MAX(fmaxY, CGRectGetMaxY(block.boundingBox));
                fany = YES;
            }
            if (fany) { fittedArea = (fmaxX - fminX) * (fmaxY - fminY); }
        }
        BOOL worthEnlarging = (fittedArea > 0 && fittedArea <= 0.16);
        if (autoFit && worthEnlarging && ocrBlocks.count > 0) {
            CGFloat minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
            BOOL any = NO;
            for (OCRTextItem *block in ocrBlocks) {
                if (NormalizeForComparison(block.text).length < 2) { continue; }
                CGRect b = block.boundingBox;
                minX = MIN(minX, CGRectGetMinX(b));
                minY = MIN(minY, CGRectGetMinY(b));
                maxX = MAX(maxX, CGRectGetMaxX(b));
                maxY = MAX(maxY, CGRectGetMaxY(b));
                any = YES;
            }
            if (any) {
                CGFloat padX = 0.03, padY = 0.03;
                minX = MAX(0, minX - padX);
                minY = MAX(0, minY - padY);
                maxX = MIN(1, maxX + padX);
                maxY = MIN(1, maxY + padY);

                NSError *fineError = nil;
                NSArray<OCRTextItem *> *blocks2 = nil;
                NSString *text2 = [self recognizeEnlargedRegionOfImage:fullImage
                                                             regionX:minX
                                                             regionY:minY
                                                         regionWidth:MAX((CGFloat)0.05, maxX - minX)
                                                        regionHeight:MAX((CGFloat)0.05, maxY - minY)
                                                              fastOCR:fastOCR
                                                      languageSegment:languageSegment
                                                               blocks:&blocks2
                                                                error:&fineError];
                if (!fineError && NormalizeForComparison(text2).length > 0) {
                    fineBlocks = blocks2;
                    fineText = text2;
                }
            }
        }
        NSTimeInterval pass2Duration = 0;
        if (fineText) {
            pass2Duration = [[NSDate date] timeIntervalSinceDate:ocrStart] - pass1Duration;
            ocrBlocks = MergeRefinedOCRItems(ocrBlocks, fineBlocks);
            ocrText = [[ocrBlocks valueForKey:@"text"] componentsJoinedByString:@"\n"];
        }
        FuyiDiagLog(@"  OCR pass1=%.2fs pass2=%.2fs total=%.2fs blocks=%lu",
                    pass1Duration, pass2Duration,
                    [[NSDate date] timeIntervalSinceDate:ocrStart], (unsigned long)ocrBlocks.count);

        // 必须在 CGImageRelease 之前、同一个线程上做完像素分析：
        // 主队列回调里 fullImage 已经被释放，之前把这段放在回调里是一个 use-after-free。
        NSDate *modalStart = [NSDate date];
        NSArray<OCRTextItem *> *modalScopedBlocks = [self blocksInsideModalIfPresent:ocrBlocks
                                                                            inImage:fullImage
                                                               normalizedExclusions:exclusionSnapshot];
        FuyiDiagLog(@"  MODAL %lu -> %lu blocks in %.3fs",
                    (unsigned long)ocrBlocks.count, (unsigned long)modalScopedBlocks.count,
                    [[NSDate date] timeIntervalSinceDate:modalStart]);

        FYTrace(trace, @"ocr", @{@"stage": @"merged", @"ocr_lines": FYTraceOCRLines(ocrBlocks), @"blocks": @(ocrBlocks.count)});
        FYTrace(trace, @"ocr", @{@"stage": @"modal_scoped", @"ocr_lines": FYTraceOCRLines(modalScopedBlocks), @"blocks": @(modalScopedBlocks.count)});
        NSTimeInterval ocrDuration = [[NSDate date] timeIntervalSinceDate:ocrStart];
        CGImageRelease(fullImage);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (cycleGeneration != self.translationGeneration || !self.running || windowID != [self selectedWindowID] ||
                inputEpoch != self.captureCardInput.sessionEpoch) {
                NSString *reason = cycleGeneration != self.translationGeneration ? @"generation_changed"
                    : (!self.running ? @"stopped"
                       : (windowID != [self selectedWindowID] ? @"window_changed" : @"input_session_changed"));
                FYTrace(trace, @"skip", @{@"reason": reason, @"input_epoch": @(inputEpoch)});
                self.inFlight = NO;
                return;
            }
            self.ocrDurationLabel.stringValue = [NSString stringWithFormat:@"最近识别  %.2f 秒", ocrDuration];
            if (error) {
                FYTrace(trace, @"skip", @{@"reason": @"ocr_error", @"error_code": @(error.code)});
                [self showError:error.localizedDescription];
                [self setStatus:@"OCR 出错"];
                self.inFlight = NO;
                return;
            }

            NSString *normalized = NormalizeForComparison(ocrText);
            if (normalized.length < 2) {
                FYTrace(trace, @"skip", @{@"reason": @"ocr_empty"});
                [self setStatus:[NSString stringWithFormat:@"等待识别字幕 · OCR %.1fs", ocrDuration]];
                self.inFlight = NO;
                return;
            }

            // 自动判别必须在这里、也就是**所有去重闸门之前**跑。
            // 之前它被放在闸门后面，而闸门一命中就 return —— 结果模式永远提交不了，
            // 一直卡在初始的「对白」，整屏新闻条目就被塞进字幕窗。
            // 判别本来就是用来决定“该不该翻译、走哪条路”的，不能依赖“这一帧要不要翻译”。
            NSInteger tracePreviousMode = self.detectedModeSegment;
            {
                NSInteger previousMode = self.detectedModeSegment;
                NSInteger committedMode = [self stableContentModeForBlocks:ocrBlocks];
                if (previousMode != committedMode) {
                    FYTrace(trace, @"caption_drop", @{@"reason": @"mode_changed", @"previous_mode": @(previousMode), @"mode": @(committedMode)});
                    NSString *switched = committedMode == ContentModeUI ? @"自动判别：功能界面 → 切换为贴译" : @"自动判别：剧情对白 → 切换为字幕";
                    [self setStatus:switched];
                    // 模式切换会改变译文的呈现方式（字幕窗 ↔ 贴译面板），必须清掉旧模式的产物，
                    // 并让当前文本重新翻一次。实测漏了这一步的后果：
                    // 从界面切到对白时，前一帧已经把整段对白贴成了 INLINE 面板；
                    // 切过来后对白分支因为“文本已翻译过”而跳过，面板又没人清 —— 屏幕上一直挂着那张贴译。
                    [self clearInlineTranslationPanels];
                    self.lastTranslatedNormalizedText = nil;
                    self.lastSubmittedNormalizedText = nil;
                    self.latestTranslationLabel.stringValue = @"等待译文";
                    self.latestSourceLabel.stringValue = @"";
                }
            }

            FYTrace(trace, @"mode", @{@"auto_mode": @YES, @"previous_mode": @(tracePreviousMode),
                                     @"mode": @([self effectiveModeSegment]), @"candidate_mode": @(self.candidateModeSegment),
                                     @"candidate_hits": @(self.candidateModeHits)});
            double translatedSimilarity = SimilarityRatio(normalized, self.lastTranslatedNormalizedText ?: @"");
            double submittedSimilarity = SimilarityRatio(normalized, self.lastSubmittedNormalizedText ?: @"");

            if ([self isSameSubtitleText:normalized comparedTo:self.lastTranslatedNormalizedText]) {
                FYTrace(trace, @"skip", @{@"reason": @"same_as_last_translated"});
                [self setStatus:[NSString stringWithFormat:@"文本未变化 · 相似 %.0f%% · OCR %.1fs", translatedSimilarity * 100, ocrDuration]];
                self.inFlight = NO;
                return;
            }

            // 节流阈值按模式分开：
            //   对白模式 4 秒 —— 防 OCR 抖动、防同一句台词反复请求
            //   界面模式 1.2 秒 —— 界面是**用户自己在动**（滑动、翻页），
            //                      让它等满 4 秒没道理，实测会变成“过了 5 秒才翻出来”
            NSInteger currentFrameMode = [self effectiveModeSegment];
            NSTimeInterval attemptThrottle = [self translationAttemptThrottleForMode:currentFrameMode];

            if ([self isSameSubtitleText:normalized comparedTo:self.lastSubmittedNormalizedText] &&
                self.lastTranslationAttemptDate &&
                [[NSDate date] timeIntervalSinceDate:self.lastTranslationAttemptDate] < attemptThrottle) {
                FYTrace(trace, @"skip", @{@"reason": @"submission_throttle"});
                [self setStatus:[NSString stringWithFormat:@"等待翻译返回 · 相似 %.0f%% · OCR %.1fs", submittedSimilarity * 100, ocrDuration]];
                self.inFlight = NO;
                return;
            }

            BOOL shouldWaitForStableText = self.stableTextCheckbox.state == NSControlStateValueOn || fastOCR;
            // 界面模式不等稳定：用户滑完就希望立刻看到译文，多等一帧就多一分延迟
            if (currentFrameMode == ContentModeUI) { shouldWaitForStableText = NO; }
            if (shouldWaitForStableText && ![self isStableText:normalized]) {
                FYTrace(trace, @"stable", @{@"reason": @"waiting", @"stable_required": @YES, @"stable_count": @(self.stableCandidateCount)});
                [self setStatus:[NSString stringWithFormat:@"等待文本稳定 · OCR %.1fs", ocrDuration]];
                self.inFlight = NO;
                return;
            }

            FYTrace(trace, @"stable", @{@"reason": shouldWaitForStableText ? @"accepted" : @"not_required",
                                       @"stable_required": @(shouldWaitForStableText), @"stable_count": @(self.stableCandidateCount)});
            self.lastSubmittedNormalizedText = normalized;
            self.lastTranslationAttemptDate = [NSDate date];

            {
                NSUInteger tokens = UITokenHitCount(ocrBlocks);
                NSUInteger substantial = 0;
                for (OCRTextItem *b in ocrBlocks) {
                    NSString *n = NormalizeForComparison(b.text);
                    if (n.length == 0) { continue; }
                    if (b.boundingBox.size.width >= 0.15) { substantial += 1; continue; }
                    if (n.length >= 8 && b.boundingBox.size.width >= 0.13 && b.boundingBox.size.height >= 0.030) { substantial += 1; }
                }
                NSArray<OCRTextItem *> *dbgBand = SubtitleBandItemsFromBlocks(ocrBlocks);
                FuyiDiagLog(@"CYCLE auto=%d blocks=%lu tokens=%lu substantial=%lu looksUI=%d band=%lu detected=%ld text=<%@>",
                            YES,
                            (unsigned long)ocrBlocks.count, (unsigned long)tokens, (unsigned long)substantial,
                            LooksLikeUIFrame(ocrBlocks), (unsigned long)dbgBand.count,
                            (long)self.detectedModeSegment, Shorten(ocrText, 60));
            }

            NSInteger frameMode = [self effectiveModeSegment];

            if (frameMode == ContentModeUI) {
                NSMutableArray<OCRTextItem *> *uiItems = [[self filteredInlineTextItems:[self mergedInlineTextItemsFromItems:modalScopedBlocks] strict:NO] mutableCopy];
                if (uiItems.count == 0) {
                    FYTrace(trace, @"skip", @{@"reason": @"ui_no_translatable_items", @"route": @"ui"});
                    if (captureCard) {
                        // 采集卡模式本来就没有贴译面板；字幕窗保留上一条，只更新状态。
                        [self setCaptionPanelVisibleForUIMode:NO];
                        [self setStatus:[NSString stringWithFormat:@"采集卡模式：界面暂无可译文字 · OCR %.1fs", ocrDuration]];
                        self.inFlight = NO;
                        return;
                    }
                    // 读不到文字（例如被 QuickTime 录制控件挡住）时，**保留上一帧的贴译面板**。
                    // 之前这里会 clearInlineTranslationPanels，于是控件一出现译文就消失、
                    // 控件淡出又重新贴出来 —— 看起来就是“闪/消失”。译文并没有变，不该清掉。
                    [self setCaptionPanelVisibleForUIMode:YES];
                    [self setStatus:[NSString stringWithFormat:@"自动判别：界面（暂无可译文字） · OCR %.1fs", ocrDuration]];
                    self.inFlight = NO;
                    return;
                }

                FuyiDiagLog(@"  -> ROUTE INLINE(UI) items=%lu", (unsigned long)uiItems.count);
                NSString *uiStatus = [NSString stringWithFormat:@"翻译界面 · OCR %.1fs", ocrDuration];
                [self setStatus:uiStatus];
                NSArray<OCRTextItem *> *uiItemsForRender = [uiItems copy];
                NSDate *uiTranslateStart = [NSDate date];
                NSArray<FYRequestIdentity *> *uiIdentities = [self.learningCoordinator recordItems:[self textsFromItems:uiItemsForRender] kind:FYSentenceKindUI];
                [self refreshLearningSource];
                [self refreshLearningStatus];
                NSDictionary *uiTrace = [[FYTranslationTrace shared] requestContextForCycle:trace];
                FYTracePerform(uiTrace, ^{
                [self translateInlineTextItems:uiItemsForRender completion:^(NSArray<NSString *> *translations, NSError *translationError) {
                    if (cycleGeneration != self.translationGeneration || !self.running || windowID != [self selectedWindowID] ||
                        inputEpoch != self.captureCardInput.sessionEpoch || [self effectiveModeSegment] != ContentModeUI) {
                        NSString *reason = cycleGeneration != self.translationGeneration ? @"generation_changed"
                            : (!self.running ? @"stopped"
                               : (windowID != [self selectedWindowID] ? @"window_changed"
                                  : (inputEpoch != self.captureCardInput.sessionEpoch ? @"input_session_changed" : @"mode_changed")));
                        FYTrace(uiTrace, @"inline_drop", @{@"reason": reason, @"route": @"ui", @"input_epoch": @(inputEpoch)});
                        self.inFlight = NO;
                        return;
                    }
                    self.translationDurationLabel.stringValue = [NSString stringWithFormat:@"翻译耗时  %.2f 秒", [[NSDate date] timeIntervalSinceDate:uiTranslateStart]];
                    FuyiDiagLog(@"  TRANSLATE(items=%lu) took %.2fs err=<%@>",
                                (unsigned long)uiItemsForRender.count,
                                [[NSDate date] timeIntervalSinceDate:uiTranslateStart],
                                translationError.localizedDescription ?: @"");
                    [self bindTranslations:translations toIdentities:uiIdentities];
                    [self refreshLearningSource];
                    [self refreshLearningStatus];
                    if (captureCard) {
                        // 采集卡与窗口截图走同一条界面贴译流程：
                        // 先建立"视频画面 → 显示区域"的坐标映射（inlinePlacementRect:）；
                        // 有映射就原位贴译，没有映射由 handleInlineTranslationResult 给出明确提示，
                        // 绝不静默把界面译文当成对白塞进字幕窗。
                        [self setCaptionPanelVisibleForUIMode:YES];
                        FYTracePerform(uiTrace, ^{
                            [self handleInlineTranslationResult:translations forItems:uiItemsForRender error:translationError failureStatus:@"采集卡：界面翻译出错" successPrefix:@"采集卡界面译文已更新"];
                        });
                        if (!translationError) {
                            self.lastTranslatedNormalizedText = normalized;
                            self.translationCount += 1;
                            [self updateTranslationCount];
                        }
                        self.inFlight = NO;
                        return;
                    }
                    FYTracePerform(uiTrace, ^{
                        [self handleInlineTranslationResult:translations forItems:uiItemsForRender error:translationError failureStatus:@"界面翻译出错" successPrefix:@"界面译文已更新"];
                    });
                    if (!translationError) {
                        self.lastTranslatedNormalizedText = normalized;
                        self.translationCount += 1;
                        [self updateTranslationCount];
                    }
                    // 界面模式下字幕窗默认收起；映射不可用时由提示逻辑重新显示它。
                    [self setCaptionPanelVisibleForUIMode:YES];
                    self.inFlight = NO;
                }];
                });
                return;
            }

            FYTrace(trace, @"dialogue", @{@"stage": @"route", @"route": @"dialogue"});
            [self setCaptionPanelVisibleForUIMode:NO];
            // 对白模式：对白框照常进悬浮字幕窗，上方的选项单独贴到原选项旁边。
            // 街景招牌、公告牌这类环境文本不会进 band，所以不会被翻译。
            FuyiDiagLog(@"  -> ROUTE DIALOGUE(caption)");
            // 断掉反馈环：字幕窗里正显示着的译文、以及贴译面板上的译文，
            // 都可能被这一轮 OCR 读回来当成“新的对白”。实测名字框旁的译文被读成
            // 一行新对白，屏幕上就多出莫名其妙的句子。
            NSSet<NSString *> *alreadyRendered = RenderedTranslationSet(self.captionTextLabel.stringValue,
                                                                       self.inlineTranslationCache);
            NSMutableArray<OCRTextItem *> *freshBlocks = [NSMutableArray arrayWithCapacity:ocrBlocks.count];
            for (OCRTextItem *block in ocrBlocks) {
                NSString *normalizedBlock = NormalizeForComparison(block.text);
                if (normalizedBlock.length > 0 && [alreadyRendered containsObject:normalizedBlock]) { continue; }
                [freshBlocks addObject:block];
            }
            NSArray<OCRTextItem *> *dialogueSource = freshBlocks;

            NSArray<OCRTextItem *> *bandItems = SubtitleBandItemsFromBlocks(dialogueSource);
            NSMutableArray<OCRTextItem *> *dialogueItems = [NSMutableArray array];
            NSMutableArray<OCRTextItem *> *optionItems = [NSMutableArray array];
            // 对白字幕与界面贴译是两条独立路径：
            //   窗口截图，或采集卡已建立坐标映射 → 选项照常贴到原选项旁边；
            //   采集卡映射不可用 → 不做原位贴译，对白照常进字幕窗（选项不单独贴）。
            BOOL optionsCanPasteInline = ![self captureCardInputEnabled] || [self inlinePlacementRect:NULL reason:NULL];
            if (optionsCanPasteInline) {
                SplitDialogueAndOptionsFromItems(bandItems, dialogueSource, dialogueItems, optionItems);
                if (optionItems.count == 0) { [self clearInlineTranslationPanels]; }
            } else {
                [dialogueItems addObjectsFromArray:bandItems];
            }

            BOOL speakerLabelOnlyFrame = NO;
            NSString *dialogueText = [self dialogueTextFromItems:dialogueItems.count > 0 ? dialogueItems : dialogueSource
                                              speakerLabelOnly:&speakerLabelOnlyFrame];

            // 选项：走贴译路线，贴在原选项文字旁边；有缓存时不会重复请求
            if (optionItems.count > 0) {
                NSArray<OCRTextItem *> *optionsToRender = [optionItems copy];
                NSArray<FYRequestIdentity *> *optionIdentities = [self.learningCoordinator recordItems:[self textsFromItems:optionsToRender] kind:FYSentenceKindOption];
                [self refreshLearningSource];
                [self refreshLearningStatus];
                NSDictionary *optionTrace = [[FYTranslationTrace shared] requestContextForCycle:trace];
                FYTracePerform(optionTrace, ^{
                [self translateInlineTextItems:optionsToRender completion:^(NSArray<NSString *> *translations, NSError *translationError) {
                    if (cycleGeneration != self.translationGeneration || !self.running || windowID != [self selectedWindowID] ||
                        inputEpoch != self.captureCardInput.sessionEpoch || [self effectiveModeSegment] != ContentModeDialogue) {
                        NSString *reason = cycleGeneration != self.translationGeneration ? @"generation_changed"
                            : (!self.running ? @"stopped"
                               : (windowID != [self selectedWindowID] ? @"window_changed"
                                  : (inputEpoch != self.captureCardInput.sessionEpoch ? @"input_session_changed" : @"mode_changed")));
                        FYTrace(optionTrace, @"inline_drop", @{@"reason": reason, @"route": @"option", @"input_epoch": @(inputEpoch)});
                        return;
                    }
                    [self bindTranslations:translations toIdentities:optionIdentities];
                    [self refreshLearningSource];
                    [self refreshLearningStatus];
                    FYTracePerform(optionTrace, ^{
                        [self handleInlineTranslationResult:translations forItems:optionsToRender error:translationError failureStatus:@"选项翻译出错" successPrefix:@"选项已贴译"];
                    });
                }];
                });
            }

            FYTrace(trace, @"dialogue", @{@"stage": @"extracted", @"source": dialogueText ?: @""});
            if (NormalizeForComparison(dialogueText).length < 2) {
                FYTrace(trace, @"skip", @{@"reason": @"dialogue_empty"});
                [self setStatus:@"对白框暂无可译文字"];
                self.inFlight = NO;
                return;
            }

            NSString *translatingStatus = [NSString stringWithFormat:@"翻译对白 · 自动判别 · OCR %.1fs", ocrDuration];
            [self setStatus:translatingStatus];
            NSDate *translationStart = [NSDate date];
            FYRequestIdentity *dialogueIdentity = speakerLabelOnlyFrame ? nil : [self.learningCoordinator recordText:dialogueText kind:FYSentenceKindDialogue];
            // Reused identities retain the complete source. Never overwrite its
            // translation with one generated from a degraded OCR frame.
            if (dialogueIdentity.sourceText.length) { dialogueText = dialogueIdentity.sourceText; }
            [self refreshLearningSource];
            [self refreshLearningStatus];
            NSDictionary *dialogueTrace = [[FYTranslationTrace shared] requestContextForCycle:trace];
            FYTrace(dialogueTrace, @"dialogue", @{@"stage": @"identity_source", @"source": dialogueText ?: @"",
                                                @"sentence_id": dialogueIdentity.sentenceID ?: @"", @"version": @(dialogueIdentity.version),
                                                @"identity_request_id": dialogueIdentity.requestID ?: @""});
            FYTracePerform(dialogueTrace, ^{
            [self translateDialogueText:dialogueText identity:dialogueIdentity systemPrompt:[self systemPrompt] completion:^(NSString *translated, NSError *translationError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (cycleGeneration != self.translationGeneration || !self.running || windowID != [self selectedWindowID] ||
                        inputEpoch != self.captureCardInput.sessionEpoch || [self effectiveModeSegment] != ContentModeDialogue) {
                        NSString *reason = cycleGeneration != self.translationGeneration ? @"generation_changed"
                            : (!self.running ? @"stopped"
                               : (windowID != [self selectedWindowID] ? @"window_changed"
                                  : (inputEpoch != self.captureCardInput.sessionEpoch ? @"input_session_changed" : @"mode_changed")));
                        FYTrace(dialogueTrace, @"caption_drop", @{@"reason": reason, @"input_epoch": @(inputEpoch)});
                        self.inFlight = NO;
                        return;
                    }
                    NSTimeInterval translationDuration = [[NSDate date] timeIntervalSinceDate:translationStart];
                    self.translationDurationLabel.stringValue = [NSString stringWithFormat:@"翻译耗时  %.2f 秒", translationDuration];
                    NSTimeInterval totalDuration = [[NSDate date] timeIntervalSinceDate:cycleStart];
                    if (translationError) {
                        NSString *errorText = translationError.localizedDescription ?: @"未知错误";
                        [self showError:errorText];
                        NSString *status = [NSString stringWithFormat:@"翻译出错 · OCR %.1fs 翻译 %.1fs", ocrDuration, translationDuration];
                        [self setStatus:status];
                        [self updateCaptionWindowWithText:[NSString stringWithFormat:@"翻译失败：%@", Shorten(errorText, 110)] status:status];
                        FYTrace(dialogueTrace, @"caption_apply", @{@"reason": @"translation_error", @"error_code": @(translationError.code), @"success": @NO});
                    } else {
                        [self.learningCoordinator setTranslation:translated forIdentity:dialogueIdentity];
                        [self refreshLearningSource];
                        [self refreshLearningStatus];
                        self.lastTranslatedNormalizedText = normalized;
                        self.lastSubmittedNormalizedText = normalized;
                        self.translationCount += 1;
                        [self showError:@""];
                        NSString *status = [NSString stringWithFormat:@"译文已更新 · OCR %.1fs 翻译 %.1fs 总 %.1fs", ocrDuration, translationDuration, totalDuration];
                        [self setStatus:status];
                        NSString *display = [self displayableTranslation:translated sourceText:dialogueText];
                        [self updateCaptionWindowWithText:display status:status];
                        FYTrace(dialogueTrace, @"caption_apply", @{@"reason": @"translated", @"source": dialogueText ?: @"", @"translation": display ?: @"", @"success": @YES, @"visible": @(self.captionPanel.isVisible)});
                        self.latestTranslationLabel.stringValue = display;
                        self.latestSourceLabel.stringValue = dialogueText;
                        [self updateTranslationCount];
                    }
                    self.inFlight = NO;
                });
            }];
            });
        });
    });
}

- (NSArray<WindowItem *> *)availableWindowItems {
    NSMutableArray<WindowItem *> *items = [NSMutableArray array];
    NSArray *windowInfos = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    for (NSDictionary *info in windowInfos) {
        NSNumber *number = info[(NSString *)kCGWindowNumber];
        NSNumber *layer = info[(NSString *)kCGWindowLayer];
        NSString *owner = info[(NSString *)kCGWindowOwnerName] ?: @"";
        NSString *title = info[(NSString *)kCGWindowName] ?: @"";
        NSDictionary *boundsDictionary = info[(NSString *)kCGWindowBounds];
        CGRect bounds = CGRectZero;

        if (!number || !layer || layer.integerValue != 0 || owner.length == 0) { continue; }
        if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)boundsDictionary, &bounds)) { continue; }
        if (bounds.size.width < 160 || bounds.size.height < 100) { continue; }

        WindowItem *item = [[WindowItem alloc] init];
        item.windowID = number.unsignedIntValue;
        item.bounds = bounds;
        item.displayName = title.length > 0 ? [NSString stringWithFormat:@"%@ - %@", owner, title] : owner;
        [items addObject:item];
    }

    [items sortUsingComparator:^NSComparisonResult(WindowItem *left, WindowItem *right) {
        return [left.displayName localizedCaseInsensitiveCompare:right.displayName];
    }];
    return items;
}

- (NSInteger)quickTimeCapturePriority:(WindowItem *)item {
    if (![item.displayName hasPrefix:@"QuickTime Player"]) { return 0; }
    NSString *title = [item.displayName componentsSeparatedByString:@" - "].lastObject;
    if ([@[@"打开", @"Open", @"存储", @"Save", @"导出", @"Export"] containsObject:title]) { return 1; }
    if ([@[@"录影", @"影片录制", @"Movie Recording", @"録画"] containsObject:title]) { return 4; }
    return 3;
}

- (void)refreshWindows:(id)sender {
    uint32_t previousSelection = [self selectedWindowID];
    NSString *previousName = [self selectedWindowItem].displayName;
    self.windows = [[self availableWindowItems] mutableCopy];
    [self.windowPopup removeAllItems];

    NSInteger selectedIndex = -1;
    NSInteger matchingNameIndex = -1;
    NSInteger quickTimeIndex = -1;
    NSInteger quickTimePriority = 0;
    for (NSInteger index = 0; index < self.windows.count; index++) {
        WindowItem *item = self.windows[index];
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:item.displayName action:nil keyEquivalent:@""];
        menuItem.representedObject = @(item.windowID);
        [self.windowPopup.menu addItem:menuItem];

        if (item.windowID == previousSelection) { selectedIndex = index; }
        if (matchingNameIndex < 0 && [item.displayName isEqualToString:previousName]) { matchingNameIndex = index; }
        NSInteger priority = [self quickTimeCapturePriority:item];
        if (priority > quickTimePriority) { quickTimeIndex = index; quickTimePriority = priority; }
    }

    if (selectedIndex >= 0) {
        [self.windowPopup selectItemAtIndex:selectedIndex];
    } else if (matchingNameIndex >= 0) {
        [self.windowPopup selectItemAtIndex:matchingNameIndex];
    } else if (quickTimeIndex >= 0) {
        [self.windowPopup selectItemAtIndex:quickTimeIndex];
    } else if (self.windows.count > 0) {
        [self.windowPopup selectItemAtIndex:0];
    }

    [self updateCurrentWindowLabel];
    if (previousSelection != [self selectedWindowID]) { [self resetForSelectedWindowChange]; }
}

- (BOOL)recoverWindowSelectionIfRecreated {
    WindowItem *selected = [self selectedWindowItem];
    if (!selected) { return NO; }
    NSDate *now = [NSDate date];
    if (self.lastWindowRecoveryAttemptDate && [now timeIntervalSinceDate:self.lastWindowRecoveryAttemptDate] < 2.0) {
        return NO;
    }
    self.lastWindowRecoveryAttemptDate = now;

    NSArray<WindowItem *> *available = [self availableWindowItems];
    BOOL selectedStillExists = NO;
    WindowItem *quickTimeCandidate = nil;
    NSInteger highestPriority = 1;
    BOOL ambiguous = NO;
    for (WindowItem *candidate in available) {
        if (candidate.windowID == selected.windowID) { selectedStillExists = YES; }
        if (candidate.windowID != selected.windowID && [candidate.displayName isEqualToString:selected.displayName]) {
            [self refreshWindows:nil];
            return [self selectedWindowID] == candidate.windowID;
        }
        NSInteger priority = [self quickTimeCapturePriority:candidate];
        if (priority > highestPriority) {
            highestPriority = priority; quickTimeCandidate = candidate; ambiguous = NO;
        } else if (priority == highestPriority && priority > 1) { ambiguous = YES; }
    }
    // QuickTime's open dialog can disappear when its recording window opens.
    // Rebind only a vanished QuickTime target and an unambiguous content window.
    if (!selectedStillExists && [self quickTimeCapturePriority:selected] > 0 && quickTimeCandidate && !ambiguous) {
        [self refreshWindows:nil];
        return [self selectedWindowID] == quickTimeCandidate.windowID;
    }
    return NO;
}

- (void)windowSelectionChanged:(id)sender {
    [self updateCurrentWindowLabel];
    [self updateOCRPreviewIfVisible];
    [self resetForSelectedWindowChange];
}

- (void)resetForSelectedWindowChange {
    self.translationGeneration += 1;
    [self.activeTranslationTask cancel];
    self.activeTranslationTask = nil;
    self.inFlight = NO;
    self.captureUnavailable = NO;
    self.lastWindowRecoveryAttemptDate = nil;
    [self updateRunState];
    [self showPreviewUnavailable:[self captureCardInputEnabled] ? @"等待采集卡画面" : @"选择窗口并开始翻译后显示画面"];
    self.lastPreviewDate = nil;
    self.latestTranslationLabel.stringValue = @"等待译文";
    self.latestSourceLabel.stringValue = @"";
    [self clearInlineTranslationPanels];
    // 换窗口后旧窗口的去重/稳定状态不再适用，重置避免第一句被误判为“文本未变化”
    self.lastTranslatedNormalizedText = @"";
    self.lastSubmittedNormalizedText = @"";
    self.lastTranslationAttemptDate = nil;
    self.stableCandidate = @"";
    self.stableCandidateCount = 0;
    [self.inlineTranslationCache removeAllObjects];
    if (self.running) { [self timerFired:self.timer]; }
}

#pragma mark - 采集卡输入

- (FYCaptureCardInput *)captureCardInput {
    if (!_captureCardInput) {
        _captureCardInput = [FYCaptureCardInput new];
        __weak typeof(self) weakSelf = self;
        _captureCardInput.stateChangeHandler = ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) { return; }
            [strongSelf updateCaptureCardStatus];
            // 断开/出错/被中断时只说明原因，绝不用旧帧继续翻译。
            if (strongSelf.running && [strongSelf captureCardInputEnabled] &&
                strongSelf.captureCardInput.state != FYCaptureCardSessionStateRunning &&
                strongSelf.captureCardInput.state != FYCaptureCardSessionStateStarting) {
                [strongSelf setStatus:strongSelf.captureCardInput.stateDetail];
            }
        };
    }
    return _captureCardInput;
}

- (BOOL)captureCardInputEnabled {
    return self.inputSourceSegment == 1;
}

- (void)updateCaptureCardStatus {
    BOOL enabled = [self captureCardInputEnabled];
    // 采集卡专属控件只在采集卡模式下出现；窗口截图模式只留一行说明。
    if (self.captureCardControlsView) { self.captureCardControlsView.hidden = !enabled; }
    if (self.inputSourceHintLabel) {
        self.inputSourceHintLabel.stringValue = enabled
            ? @"从采集卡直接读取 HDMI 画面：画面里没有 QuickTime／OBS 的控件，也不需要屏幕录制权限；第一次连接时会弹一次相机权限。"
            : @"截取下面选定的那个窗口（QuickTime／OBS）：需要屏幕录制权限，且窗口里的控件（例如 QuickTime 录制条）会一起被截进去。";
    }
    if (!self.captureStatusLabel) { return; }
    // 刻意用 ivar 而不是 getter：刷新状态行不应该为了显示"未启动"
    // 就去创建采集对象、查询相机权限（那是 XPC 调用，每次 loadSettings 都做没有意义）。
    FYCaptureCardInput *input = _captureCardInput;
    if (!enabled) {
        self.captureStatusLabel.stringValue = @"";
        if (self.captureSettingsButton) { self.captureSettingsButton.hidden = YES; }
        return;
    }
    if (!input) {
        self.captureStatusLabel.stringValue = @"识别输入源：采集卡 · 未启动 · 相机权限：连接时才会查询";
        if (self.captureSettingsButton) { self.captureSettingsButton.hidden = YES; }
        return;
    }
    FYCaptureCardAvailability availability = [input availability];
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"识别输入源：采集卡 · %@ · 相机权限：%@", FYCaptureCardSessionStateLabel(input.state),
                       FYCaptureCardAvailabilityLabel(availability)];
    if (input.activeDeviceName.length > 0) { [text appendFormat:@" · 设备：%@", input.activeDeviceName]; }
    if (input.state == FYCaptureCardSessionStateRunning) {
        [text appendFormat:@" · 已收帧 %llu（丢弃旧帧 %llu）",
                           (unsigned long long)input.receivedFrameCount,
                           (unsigned long long)input.skippedFrameCount];
    }
    if (input.stateDetail.length > 0) { [text appendFormat:@"\n%@", input.stateDetail]; }
    self.captureStatusLabel.stringValue = text;
    // 只有"已被明确拒绝/受限"时系统才不会再次弹窗，这时才需要手动设置入口。
    if (self.captureSettingsButton) {
        self.captureSettingsButton.hidden = !(availability == FYCaptureCardAvailabilityDenied ||
                                              availability == FYCaptureCardAvailabilityRestricted);
    }
}

// 相机权限按需申请：已授权直接继续；尚未决定时弹一次系统提示；已被拒绝只提示设置入口。
// 仍然由用户点击「开始翻译／重连采集卡」触发，不会在启动或空闲时自己弹窗。
- (void)ensureCaptureCardPermissionThen:(void (^)(BOOL granted))continuation {
    if (!continuation) { return; }
    FYCaptureCardAvailability availability = [self.captureCardInput availability];
    if (availability == FYCaptureCardAvailabilityAuthorized) { continuation(YES); return; }
    if (availability == FYCaptureCardAvailabilityNotDetermined) {
        [self setStatus:@"正在申请相机权限：请在系统提示里点「允许」"];
        __weak typeof(self) weakSelf = self;
        [self.captureCardInput requestAccessWithCompletion:^(FYCaptureCardAvailability result) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) { return; }
            [strongSelf updateCaptureCardStatus];
            continuation(result == FYCaptureCardAvailabilityAuthorized);
        }];
        return;
    }
    [self updateCaptureCardStatus];
    [self setStatus:[NSString stringWithFormat:@"相机权限%@：请点「打开相机权限设置」允许译芽后重试；不会改用其他摄像头",
                                               FYCaptureCardAvailabilityLabel(availability)]];
    continuation(NO);
}

// 采集卡模式下界面译文的呈现：按顺序取前几条，拼成字幕窗文本。
- (NSString *)captionLinesFromTranslations:(NSArray<NSString *> *)translations {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *value in translations) {
        NSString *clean = Trim(value);
        if (clean.length == 0) { continue; }
        [lines addObject:clean];
        if (lines.count >= 5) { break; }
    }
    return lines.count > 0 ? [lines componentsJoinedByString:@"\n"] : @"（本帧没有可显示的译文）";
}

- (nullable NSString *)captureDeviceIDFromPopup {    if (!self.captureDevicePopup || !self.captureDevicePopup.enabled) { return nil; }
    id represented = self.captureDevicePopup.selectedItem.representedObject;
    return [represented isKindOfClass:NSString.class] ? represented : nil;
}

// 只列外接采集设备；不做默认回退，也不会因此启动任何设备。
- (void)refreshCaptureDevices:(id)sender {
    if (!self.captureDevicePopup) { return; }
    NSArray<FYCaptureCardDeviceInfo *> *devices = [self.captureCardInput availableDevices];
    NSString *previous = self.selectedCaptureDeviceID;
    [self.captureDevicePopup removeAllItems];

    if (devices.count == 0) {
        [self.captureDevicePopup addItemWithTitle:@"未检测到采集卡"];
        self.captureDevicePopup.enabled = NO;
        self.selectedCaptureDeviceID = nil;
        self.captureDeviceListLoaded = YES;
        [self updateCaptureCardStatus];
        [self setStatus:@"未检测到采集卡：请连接采集卡后点「刷新设备」；不会自动改用内置或手机摄像头"];
        return;
    }

    self.captureDevicePopup.enabled = YES;
    NSInteger selection = 0;
    for (NSInteger index = 0; index < devices.count; index++) {
        FYCaptureCardDeviceInfo *info = devices[index];
        NSString *title = info.inUseByAnotherApplication
            ? [NSString stringWithFormat:@"%@（其他程序正在使用）", info.displayName]
            : info.displayName;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        item.representedObject = info.uniqueID;
        [self.captureDevicePopup.menu addItem:item];
        if (previous.length > 0 && [info.uniqueID isEqualToString:previous]) { selection = index; }
    }
    [self.captureDevicePopup selectItemAtIndex:selection];
    self.selectedCaptureDeviceID = [self captureDeviceIDFromPopup];
    self.captureDeviceListLoaded = YES;
    [self updateCaptureCardStatus];
    [self setStatus:[NSString stringWithFormat:@"检测到 %lu 台采集卡，请选择后点「开始翻译」",
                                               (unsigned long)devices.count]];
}

- (void)captureDeviceChanged:(id)sender {
    self.selectedCaptureDeviceID = [self captureDeviceIDFromPopup];
    [self scheduleSettingsSave];
    if ([self captureCardInputEnabled] && self.running) {
        // 换设备 = 换会话：先释放旧会话并作废旧帧，再按新设备重新开始。
        [self reconnectCaptureDevice:nil];
        return;
    }
    [self updateCaptureCardStatus];
}

- (void)inputSourceChanged:(id)sender {
    NSInteger segment = self.inputSourceControl.selectedSegment == 1 ? 1 : 0;
    if (segment == self.inputSourceSegment) { return; }
    self.inputSourceSegment = segment;
    [self resetForInputSourceChange];
    if (segment == 1) {
        [self refreshCaptureDevices:nil];
        if (self.running && ![self startCaptureCardSessionIfPossible]) {
            // 运行中切到采集卡但起不来（权限被拒／设备缺失／被占用）：停下来并说明原因，
            // 而不是继续显示"正在运行"却每轮空转。
            NSString *reason = self.captureCardInput.stateDetail;
            [self stop];
            [self setStatus:reason.length > 0 ? reason : @"采集卡未能启动"];
        } else if (self.running) {
            [self setStatus:@"识别输入源已切换为采集卡；字幕仍显示在下方选中的窗口上"];
        } else {
            [self setStatus:@"识别输入源已切换为采集卡；确认设备与权限后点「开始翻译」"];
        }
        [self updateCaptureCardStatus];
    } else {
        [self.captureCardInput stop];
        if (self.running) { [self timerFired:self.timer]; }
        [self setStatus:@"识别输入源已切换为窗口截图"];
        [self updateCaptureCardStatus];
    }
    [self scheduleSettingsSave];
}

// 切源/换设备/停止：作废所有在途结果与旧帧，清掉只能属于旧来源的产物。
- (void)resetForInputSourceChange {
    self.translationGeneration += 1;
    [self.activeTranslationTask cancel];
    self.activeTranslationTask = nil;
    self.inFlight = NO;
    self.captureUnavailable = NO;
    self.lastTranslatedNormalizedText = @"";
    self.lastSubmittedNormalizedText = @"";
    self.lastTranslationAttemptDate = nil;
    self.stableCandidate = @"";
    self.stableCandidateCount = 0;
    self.lastOCRedCaptureFrameIndex = 0;
    self.lastPreviewDate = nil;
    [self.inlineTranslationCache removeAllObjects];
    [self clearInlineTranslationPanels];
    self.latestTranslationLabel.stringValue = @"等待译文";
    self.latestSourceLabel.stringValue = @"";
    [self showPreviewUnavailable:[self captureCardInputEnabled] ? @"等待采集卡画面" : @"选择窗口并开始翻译后显示画面"];
    [self updateRunState];
}

// 开始/重连采集会话。权限、设备缺失或被占用都返回 NO 并给出明确状态，绝不改用其他设备。
- (BOOL)startCaptureCardSessionIfPossible {
    if (![self captureCardInputEnabled]) { return YES; }
    FYCaptureCardInput *input = self.captureCardInput;
    if (input.state == FYCaptureCardSessionStateRunning && self.selectedCaptureDeviceID.length > 0) { return YES; }

    if (!self.captureDeviceListLoaded) { [self refreshCaptureDevices:nil]; }
    if (self.selectedCaptureDeviceID.length == 0) { self.selectedCaptureDeviceID = [self captureDeviceIDFromPopup]; }
    if (self.selectedCaptureDeviceID.length == 0) {
        [self setStatus:@"未选择采集卡设备：请点「刷新设备」后选择；不会自动改用内置或手机摄像头"];
        [self updateCaptureCardStatus];
        return NO;
    }
    self.lastOCRedCaptureFrameIndex = 0;
    if (![input startWithDeviceUniqueID:self.selectedCaptureDeviceID]) {
        [self setStatus:input.stateDetail];
        [self updateCaptureCardStatus];
        return NO;
    }
    [self updateCaptureCardStatus];
    return YES;
}

- (void)reconnectCaptureDevice:(id)sender {
    // 重连 = 新会话：先释放旧会话并作废旧帧，避免断开期间继续用旧画面。
    [self.captureCardInput stop];
    self.lastOCRedCaptureFrameIndex = 0;
    if (![self captureCardInputEnabled]) {
        [self setStatus:@"当前识别输入源是「窗口截图」，重连采集卡前请先切到采集卡"];
        [self updateCaptureCardStatus];
        return;
    }
    [self refreshCaptureDevices:nil];
    if ([self.captureCardInput availability] != FYCaptureCardAvailabilityAuthorized) {
        __weak typeof(self) weakSelf = self;
        [self ensureCaptureCardPermissionThen:^(BOOL granted) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) { return; }
            if (granted) { [strongSelf reconnectCaptureDevice:nil]; }
        }];
        return;
    }
    if (![self startCaptureCardSessionIfPossible]) {
        NSString *reason = self.captureCardInput.stateDetail;
        if ([self.captureCardInput availability] != FYCaptureCardAvailabilityAuthorized) {
            reason = [NSString stringWithFormat:@"%@；可点「申请相机权限」", reason];
        }
        // 重连失败时不能停在"正在运行"却每轮空转。
        if (self.running) { [self stop]; }
        [self setStatus:reason.length > 0 ? reason : @"采集卡未能重连"];
        return;
    }
    if (self.running) { [self timerFired:self.timer]; }
    [self setStatus:[NSString stringWithFormat:@"已连接采集卡 %@", self.captureCardInput.activeDeviceName ?: @"外接采集设备"]];
}

- (void)openCameraAccessSettings:(id)sender {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"];
    if (!url) { return; }
    [NSWorkspace.sharedWorkspace openURL:url];
    [self setStatus:@"已打开系统设置的相机权限页：允许译芽后回到应用点「重连采集卡」"];
}

- (void)controlValueChanged:(id)sender {
    [self clampRegionSliders];
    [self updateCaptionAppearance];
    [self updateThemeSummary];
    [self updateOCRPreviewIfVisible];
    if (self.running && sender == self.intervalSlider) {
        [self restartTimerIfRunning];
    }
    [self scheduleSettingsSave];
}

- (void)selectOCRRegion:(id)sender {
    WindowItem *window = [self selectedWindowItem];
    if (!window) {
        [self setStatus:@"请先选择 QuickTime 或游戏窗口"];
        return;
    }

    NSScreen *targetScreen = [self screenForWindowItem:window] ?: NSScreen.mainScreen;
    NSRect panelFrame = targetScreen.frame;
    if (NSWidth(panelFrame) < 80 || NSHeight(panelFrame) < 80) {
        [self setStatus:@"当前屏幕太小，无法框选"];
        return;
    }

    [self hideInterfaceForRegionSelection];
    [self.regionSelectionPanel close];

    self.regionSelectionPanel = [[NSPanel alloc] initWithContentRect:panelFrame
                                                           styleMask:NSWindowStyleMaskBorderless
                                                             backing:NSBackingStoreBuffered
                                                               defer:NO];
    self.regionSelectionPanel.backgroundColor = [NSColor clearColor];
    self.regionSelectionPanel.opaque = NO;
    self.regionSelectionPanel.hasShadow = NO;
    self.regionSelectionPanel.level = NSScreenSaverWindowLevel;
    self.regionSelectionPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;

    RegionSelectionView *selectionView = [[RegionSelectionView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(panelFrame), NSHeight(panelFrame))];
    selectionView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    __weak typeof(self) weakSelf = self;
    selectionView.completion = ^(CGRect selectedRect, CGSize viewSize, BOOL cancelled) {
        AppDelegate *strongSelf = weakSelf;
        if (!strongSelf) { return; }

        [strongSelf.regionSelectionPanel close];
        strongSelf.regionSelectionPanel = nil;

        if (cancelled) {
            [strongSelf restoreInterfaceAfterRegionSelectionShowingOCRPreview:NO];
            [strongSelf setStatus:@"已取消框选"];
            return;
        }

        CGRect quartzSelection = [strongSelf quartzRectFromSelectionRect:selectedRect panelFrame:panelFrame];
        CGRect clippedSelection = CGRectIntersection(quartzSelection, window.bounds);

        if (CGRectIsNull(clippedSelection) || clippedSelection.size.width < 24 || clippedSelection.size.height < 24) {
            [strongSelf restoreInterfaceAfterRegionSelectionShowingOCRPreview:NO];
            [strongSelf setStatus:@"框选区域没有落在目标窗口里"];
            return;
        }

        double x = (clippedSelection.origin.x - window.bounds.origin.x) / window.bounds.size.width;
        double y = (clippedSelection.origin.y - window.bounds.origin.y) / window.bounds.size.height;
        double width = clippedSelection.size.width / window.bounds.size.width;
        double height = clippedSelection.size.height / window.bounds.size.height;

        strongSelf.regionXSlider.doubleValue = MAX(0, MIN(1, x));
        strongSelf.regionYSlider.doubleValue = MAX(0, MIN(1, y));
        strongSelf.regionWidthSlider.doubleValue = MAX(0.05, MIN(1, width));
        strongSelf.regionHeightSlider.doubleValue = MAX(0.05, MIN(1, height));
        [strongSelf controlValueChanged:nil];
        [strongSelf saveSettings:nil];
        [strongSelf restoreInterfaceAfterRegionSelectionShowingOCRPreview:YES];
        [strongSelf setStatus:[NSString stringWithFormat:@"OCR 区域已更新：x %.2f y %.2f w %.2f h %.2f",
                               strongSelf.regionXSlider.doubleValue,
                               strongSelf.regionYSlider.doubleValue,
                               strongSelf.regionWidthSlider.doubleValue,
                               strongSelf.regionHeightSlider.doubleValue]];
    };

    self.regionSelectionPanel.contentView = selectionView;
    [self.regionSelectionPanel makeKeyAndOrderFront:nil];
    [self.regionSelectionPanel makeFirstResponder:selectionView];
    [NSApp activateIgnoringOtherApps:YES];
    [self setStatus:@"拖动框选 QuickTime 里的字幕区域"];
}

- (void)hideInterfaceForRegionSelection {
    self.selectingCaptureRegion = YES;
    self.mainWindowVisibleBeforeRegionSelection = self.mainWindow.isVisible;
    self.captionPanelVisibleBeforeRegionSelection = self.captionPanel.isVisible;
    self.ocrPreviewVisibleBeforeRegionSelection = self.ocrPreviewPanel.isVisible;

    [self.mainWindow orderOut:nil];
    [self.captionPanel orderOut:nil];
    [self.ocrPreviewPanel orderOut:nil];
    [self.captionDockPanel orderOut:nil];
    [self.studyChatPanel orderOut:nil];
    [self.quickSentencePanel orderOut:nil];
}

- (void)restoreInterfaceAfterRegionSelectionShowingOCRPreview:(BOOL)showOCRPreview {
    if (self.mainWindowVisibleBeforeRegionSelection) {
        [self.mainWindow makeKeyAndOrderFront:nil];
    }

    self.selectingCaptureRegion = NO;
    [self refreshOverlayVisibility:nil];

    if (showOCRPreview || self.ocrPreviewVisibleBeforeRegionSelection) {
        [self updateOCRPreviewPanel];
    } else {
        [self.ocrPreviewPanel orderOut:nil];
    }

    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showOCRPreview:(id)sender {
    if ([self updateOCRPreviewPanel]) {
        [self setStatus:@"OCR 框已显示"];
    }
}

- (void)hideOCRPreview:(id)sender {
    [self.ocrPreviewPanel close];
    self.ocrPreviewPanel = nil;
    self.ocrPreviewLabel = nil;
    [self setStatus:@"OCR 框已隐藏"];
}

- (void)updateOCRPreviewIfVisible {
    if (self.ocrPreviewPanel) {
        [self updateOCRPreviewPanel];
    }
}

- (void)useDefaultSubtitleRegion:(id)sender {
    self.regionXSlider.doubleValue = 0.05;
    self.regionYSlider.doubleValue = 0.52;
    self.regionWidthSlider.doubleValue = 0.90;
    self.regionHeightSlider.doubleValue = 0.42;
    [self controlValueChanged:nil];
}

- (void)useLargeSubtitleRegion:(id)sender {
    self.regionXSlider.doubleValue = 0.02;
    self.regionYSlider.doubleValue = 0.42;
    self.regionWidthSlider.doubleValue = 0.96;
    self.regionHeightSlider.doubleValue = 0.52;
    [self controlValueChanged:nil];
}

- (void)useFullWindowRegion:(id)sender {
    self.regionXSlider.doubleValue = 0;
    self.regionYSlider.doubleValue = 0;
    self.regionWidthSlider.doubleValue = 1;
    self.regionHeightSlider.doubleValue = 1;
    [self controlValueChanged:nil];
}

- (void)useInterfaceFullWindowPreset:(id)sender {
    self.detectedModeSegment = ContentModeUI;
    self.candidateModeSegment = -1;
    self.candidateModeHits = 0;
    self.intervalSlider.doubleValue = 1.5;
    self.stableTextCheckbox.state = NSControlStateValueOn;
    self.fastOCRCheckbox.state = NSControlStateValueOff;
    [self controlValueChanged:nil];
    [self useFullWindowRegion:nil];
    [self restartTimerIfRunning];
    [self setStatus:@"已切换为界面全文模式"];
}

- (void)translateCurrentInterface:(id)sender {
    if (self.inFlight) {
        [self setStatus:@"正在处理上一条识别"];
        return;
    }

    BOOL captureCard = [self captureCardInputEnabled];
    if (![self selectedWindowID]) {
        [self setStatus:@"请先选择 QuickTime 或游戏窗口"];
        return;
    }
    if (!captureCard && ![self hasUsableScreenCaptureAccess]) {
        [self handleMissingScreenAccessForStart];
        return;
    }

    self.inFlight = YES;
    NSInteger cycleGeneration = self.translationGeneration;
    uint32_t windowID = [self selectedWindowID];
    NSUInteger inputEpoch = self.captureCardInput.sessionEpoch;
    CGImageRef image = captureCard ? [self.captureCardInput copyLatestFrame] : [self copyFullCapturedImageForWindow:windowID];
    if (!image) {
        self.inFlight = NO;
        if (!captureCard && [self recoverWindowSelectionIfRecreated]) {
            if (!self.running) { [self translateCurrentInterface:sender]; }
            return;
        }
        NSString *message = captureCard ? @"采集卡暂无可用画面，请等画面恢复后再翻译当前界面。"
                                        : @"无法截取目标窗口";
        [self showPreviewUnavailable:message];
        [self setStatus:message];
        return;
    }
    [self updatePreviewFromImage:image generation:cycleGeneration];

    NSInteger languageSegment = self.languageControl.selectedSegment;
    self.learningCoordinator.japaneseMode = (languageSegment == 0);
    [self setStatus:@"正在识别当前界面"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDate *ocrStart = [NSDate date];
        NSError *error = nil;
        NSArray<OCRTextItem *> *blocks = [self recognizeTextItemsInImage:image fastOCR:NO languageSegment:languageSegment error:&error];
        NSTimeInterval ocrDuration = [[NSDate date] timeIntervalSinceDate:ocrStart];
        CGImageRelease(image);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (cycleGeneration != self.translationGeneration || windowID != [self selectedWindowID] ||
                inputEpoch != self.captureCardInput.sessionEpoch) {
                self.inFlight = NO;
                return;
            }
            self.ocrDurationLabel.stringValue = [NSString stringWithFormat:@"最近识别  %.2f 秒", ocrDuration];
            if (error) {
                [self showError:error.localizedDescription];
                [self setStatus:@"当前界面 OCR 出错"];
                self.inFlight = NO;
                return;
            }

            // 「翻译当前界面」与实时界面路径同源：分块 → 过滤 → 贴译（长短卡 + 映射）。
            NSMutableArray<OCRTextItem *> *uiItems = [[self filteredInlineTextItems:[self mergedInlineTextItemsFromItems:blocks] strict:NO] mutableCopy];
            if (uiItems.count == 0) {
                [self setStatus:[NSString stringWithFormat:@"当前界面没有识别到可译文字 · OCR %.1fs", ocrDuration]];
                self.inFlight = NO;
                return;
            }
            NSArray<OCRTextItem *> *uiItemsForRender = [uiItems copy];
            NSArray<FYRequestIdentity *> *uiIdentities = [self.learningCoordinator recordItems:[self textsFromItems:uiItemsForRender] kind:FYSentenceKindUI];
            [self refreshLearningSource];
            [self refreshLearningStatus];
            NSDictionary *uiTrace = [[FYTranslationTrace shared] requestContextForCycle:FYCurrentTrace()];
            NSDate *translationStart = [NSDate date];
            [self setStatus:[NSString stringWithFormat:@"正在翻译当前界面 · OCR %.1fs", ocrDuration]];
            [self translateInlineTextItems:uiItemsForRender completion:^(NSArray<NSString *> *translations, NSError *translationError) {
                if (cycleGeneration != self.translationGeneration || windowID != [self selectedWindowID] ||
                    inputEpoch != self.captureCardInput.sessionEpoch) {
                    self.inFlight = NO;
                    return;
                }
                self.translationDurationLabel.stringValue = [NSString stringWithFormat:@"翻译耗时  %.2f 秒", [[NSDate date] timeIntervalSinceDate:translationStart]];
                [self bindTranslations:translations toIdentities:uiIdentities];
                [self refreshLearningSource];
                [self refreshLearningStatus];
                FYTracePerform(uiTrace, ^{
                    [self handleInlineTranslationResult:translations forItems:uiItemsForRender error:translationError failureStatus:@"界面翻译出错" successPrefix:@"界面译文已更新"];
                });
                if (!translationError) {
                    self.translationCount += 1;
                    [self updateTranslationCount];
                }
                self.inFlight = NO;
            }];
        });
    });
}

- (void)useRealtimePreset:(id)sender {
    self.intervalSlider.doubleValue = 0.5;
    self.stableTextCheckbox.state = NSControlStateValueOff;
    self.fastOCRCheckbox.state = NSControlStateValueOn;
    [self restartTimerIfRunning];
    [self setStatus:@"已切换为实时优先"];
    [self scheduleSettingsSave];
}

- (void)useAccuratePreset:(id)sender {
    self.intervalSlider.doubleValue = 1.2;
    self.stableTextCheckbox.state = NSControlStateValueOn;
    self.fastOCRCheckbox.state = NSControlStateValueOff;
    [self restartTimerIfRunning];
    [self setStatus:@"已切换为准确优先"];
    [self scheduleSettingsSave];
}

- (void)requestScreenAccess:(id)sender {
    if ([self hasScreenAccess]) {
        [self setStatus:@"屏幕录制权限已可用"];
        return;
    }

    self.screenAccessRequestedDuringSession = YES;
    BOOL granted = CGRequestScreenCaptureAccess();
    if (granted || [self hasScreenAccess]) {
        [self setStatus:@"屏幕录制权限已可用"];
    } else {
        [self setStatus:@"已打开授权；勾选“译芽”后点“重启 App”"];
        [self openScreenAccessSettings:nil];
    }
}

- (void)checkScreenAccess:(id)sender {
    if ([self canCaptureSelectedWindowOnce]) {
        [self setStatus:@"窗口捕获可用，可以开始翻译"];
        return;
    }

    if ([self hasScreenAccess]) {
        [self setStatus:@"权限已授予，但目标窗口无法截取；请刷新并重新选择窗口"];
    } else {
        [self setStatus:@"权限还未生效；授权后请点“重启 App”"];
    }
}

- (void)relaunchApp:(id)sender {
    NSURL *bundleURL = [self preferredBundleURLForRelaunch];
    if (!bundleURL) {
        [self setStatus:@"找不到 App 路径，请手动退出后重开"];
        return;
    }

    [self setStatus:@"正在重启 App"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:bundleURL
                                              configuration:configuration
                                          completionHandler:nil];
        [NSApp terminate:nil];
    });
}

- (void)openScreenAccessSettings:(id)sender {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)testTranslation:(id)sender {
    NSString *sample = self.languageControl.selectedSegment == 1
        ? @"Would you like to walk home together today?"
        : @"今日は一緒に帰りませんか？";
    [self setStatus:@"正在测试翻译"];
    self.serviceTestGeneration += 1;
    NSInteger testGeneration = self.serviceTestGeneration;
    self.serviceStatusLabel.stringValue = @"正在测试服务";
    [self translateText:sample completion:^(NSString *translated, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (testGeneration != self.serviceTestGeneration) { return; }
            if (error) {
                [self showError:error.localizedDescription];
                [self setStatus:@"翻译测试失败"];
                self.serviceStatusLabel.stringValue = @"服务测试失败";
                self.serviceErrorLabel.stringValue = error.localizedDescription ?: @"未知错误";
            } else {
                [self showError:@""];
                [self setStatus:@"翻译测试完成"];
                self.serviceStatusLabel.stringValue = @"服务测试成功";
                self.serviceErrorLabel.stringValue = @"";
                [self updateCaptionWindowWithText:[self displayableTranslation:translated sourceText:sample] status:@"翻译测试完成"];
            }
        });
    }];
}

- (void)useDeepSeekPreset:(id)sender {
    self.baseURLField.stringValue = @"https://api.deepseek.com";
    self.modelField.stringValue = @"deepseek-v4-pro";
    // 高质量预设只影响“翻译当前界面”，实时模型保持 Flash，否则实时字幕会被推理拖死
    if (Trim(self.realtimeModelField.stringValue).length == 0) {
        self.realtimeModelField.stringValue = @"deepseek-flash";
    }
    [self setStatus:@"已应用 DeepSeek Pro 预设（实时仍用 Flash）"];
    [self serviceSettingsChanged];
}

- (void)useDeepSeekFlashPreset:(id)sender {
    self.baseURLField.stringValue = @"https://api.deepseek.com";
    self.modelField.stringValue = @"deepseek-flash";
    self.realtimeModelField.stringValue = @"deepseek-flash";
    [self setStatus:@"已应用 DeepSeek Flash 预设"];
    [self serviceSettingsChanged];
}

- (void)useOpenAIPreset:(id)sender {
    self.baseURLField.stringValue = @"https://api.openai.com/v1";
    self.modelField.stringValue = @"gpt-4.1-mini";
    self.realtimeModelField.stringValue = @"gpt-4.1-mini";
    [self setStatus:@"已应用 OpenAI 预设"];
    [self serviceSettingsChanged];
}

- (void)pasteAPIKeyFromClipboard:(id)sender {
    NSString *clipboardText = Trim([[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]);
    if (clipboardText.length == 0) {
        [self setStatus:@"剪贴板里没有可粘贴的文本"];
        return;
    }

    self.apiKeyField.stringValue = clipboardText;
    [self setStatus:@"API Key 已从剪贴板填入"];
    [self serviceSettingsChanged];
}

- (void)clearAPIKey:(id)sender {
    self.apiKeyField.stringValue = @"";
    [self setStatus:@"API Key 已清空"];
    [self serviceSettingsChanged];
}

- (void)saveSettings:(id)sender {
    [self.saveTimer invalidate];
    self.saveTimer = nil;
    if (self.loadingSettings) { return; }
    NSDictionary *settings = @{
        @"language": @(self.languageControl.selectedSegment),
        @"regionX": @(self.regionXSlider.doubleValue),
        @"regionY": @(self.regionYSlider.doubleValue),
        @"regionWidth": @(self.regionWidthSlider.doubleValue),
        @"regionHeight": @(self.regionHeightSlider.doubleValue),
        @"interval": @(self.intervalSlider.doubleValue),
        @"captionOpacity": @(self.captionOpacitySlider.doubleValue),
        @"captionFontSize": @(self.captionFontSizeSlider.doubleValue),
        @"captionHeight": @(self.captionHeightSlider.doubleValue),
        @"captionTheme": @(self.captionThemeControl.selectedSegment),
        @"stableText": @(self.stableTextCheckbox.state == NSControlStateValueOn),
        @"fastOCR": @(self.fastOCRCheckbox.state == NSControlStateValueOn),
        @"autoFitRegion": @(self.autoFitRegionCheckbox.state == NSControlStateValueOn),
        @"baseURL": self.baseURLField.stringValue ?: @"",
        @"model": self.modelField.stringValue ?: @"",
        @"realtimeModel": self.realtimeModelField.stringValue ?: @"",
        @"learningModel": self.learningModelField.stringValue ?: @"",
        @"apiKey": self.apiKeyField.stringValue ?: @"",
        // 识别输入源（0 = 窗口截图，1 = 采集卡）与上次选择的采集卡设备。
        // 只记硬件标识用于恢复选择，不写入日志；启动时不会因此自动开始采集。
        @"inputSource": @(self.inputSourceSegment == 1 ? 1 : 0),
        @"captureDeviceID": self.selectedCaptureDeviceID ?: @"",
        // 采集卡画面区域校准（只存几何与设备标识，不存画面）。
        @"captureVideoRects": self.captureCardVideoRects ?: @{}
    };
    [[NSUserDefaults standardUserDefaults] setObject:settings forKey:SettingsKey];
}

- (void)scheduleSettingsSave {
    if (self.loadingSettings) { return; }
    [self.saveTimer invalidate];
    self.saveTimer = [NSTimer scheduledTimerWithTimeInterval:0.45
                                                    target:self
                                                  selector:@selector(saveSettings:)
                                                  userInfo:nil
                                                   repeats:NO];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    id field = notification.object;
    if (field == self.lemmaField || field == self.readingField || field == self.meaningField) {
        [self vocabularyFormChanged:field]; return;
    }
    [self scheduleSettingsSave];
    if (field == self.baseURLField || field == self.modelField || field == self.realtimeModelField || field == self.apiKeyField) {
        self.serviceTestGeneration += 1;
        self.serviceStatusLabel.stringValue = @"服务未测试";
        self.serviceErrorLabel.stringValue = @"";
    }
    if (field == self.learningModelField || field == self.baseURLField || field == self.modelField || field == self.apiKeyField) {
        [self syncLearningAnalyzerConfig];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.lemmaField || notification.object == self.readingField || notification.object == self.meaningField) { return; }
    [self saveSettings:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    FYCrashLifecycle(@"normal-termination");
    [self.overlayVisibilityTimer invalidate];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self saveSettings:nil];
    [self stop];
    [self.globalShortcuts stop];
    [self.studyChatSession cancel];
    [self cancelQuickSentenceAnalysis];
    [self.learningAnalyzer cancelAll];
}

- (void)serviceSettingsChanged {
    self.serviceTestGeneration += 1;
    self.serviceStatusLabel.stringValue = @"服务未测试";
    self.serviceErrorLabel.stringValue = @"";
    [self saveSettings:nil];
}

- (void)loadSettings {
    self.loadingSettings = YES;
    NSDictionary *settings = [[NSUserDefaults standardUserDefaults] objectForKey:SettingsKey];
    self.languageControl.selectedSegment = [settings[@"language"] integerValue] ?: 0;
    // 内容模式已彻底固定为自动判别：忽略旧存档里的手动模式（mode / autoModeEnabled / manualMode），
    // 每次启动都从对白开始，由判别逻辑按画面连续两帧一致来切换。
    self.detectedModeSegment = ContentModeDialogue;
    self.candidateModeSegment = -1;
    self.candidateModeHits = 0;
    self.captionPanelShownByUser = YES;
    self.regionXSlider.doubleValue = settings[@"regionX"] ? [settings[@"regionX"] doubleValue] : 0.05;
    self.regionYSlider.doubleValue = settings[@"regionY"] ? [settings[@"regionY"] doubleValue] : 0.52;
    self.regionWidthSlider.doubleValue = settings[@"regionWidth"] ? [settings[@"regionWidth"] doubleValue] : 0.90;
    self.regionHeightSlider.doubleValue = settings[@"regionHeight"] ? [settings[@"regionHeight"] doubleValue] : 0.42;
    self.intervalSlider.doubleValue = settings[@"interval"] ? [settings[@"interval"] doubleValue] : 1.2;
    self.captionOpacitySlider.doubleValue = settings[@"captionOpacity"] ? [settings[@"captionOpacity"] doubleValue] : 0.58;
    self.captionFontSizeSlider.doubleValue = settings[@"captionFontSize"] ? [settings[@"captionFontSize"] doubleValue] : 30;
    self.captionHeightSlider.doubleValue = settings[@"captionHeight"] ? [settings[@"captionHeight"] doubleValue] : 180;
    self.captionThemeControl.selectedSegment = settings[@"captionTheme"] ? [settings[@"captionTheme"] integerValue] : 3;
    self.stableTextCheckbox.state = settings[@"stableText"] ? ([settings[@"stableText"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff) : NSControlStateValueOn;
    self.fastOCRCheckbox.state = settings[@"fastOCR"] ? ([settings[@"fastOCR"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff) : NSControlStateValueOff;
    self.autoFitRegionCheckbox.state = settings[@"autoFitRegion"] ? ([settings[@"autoFitRegion"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff) : NSControlStateValueOn;
    self.baseURLField.stringValue = settings[@"baseURL"] ?: @"https://api.openai.com/v1";
    self.modelField.stringValue = settings[@"model"] ?: @"gpt-4.1-mini";
    // 老存档没有这个键 —— 默认给 Flash：实时翻译用推理模型会卡到没法用
    self.realtimeModelField.stringValue = settings[@"realtimeModel"] ?: @"deepseek-flash";
    self.learningModelField.stringValue = settings[@"learningModel"] ?: @"";
    self.apiKeyField.stringValue = settings[@"apiKey"] ?: @"";
    // 识别输入源与采集卡设备：只恢复选择，不自动启动采集（权限也不会在这里申请）。
    self.inputSourceSegment = [settings[@"inputSource"] integerValue] == 1 ? 1 : 0;
    if (self.inputSourceControl) { self.inputSourceControl.selectedSegment = self.inputSourceSegment; }
    self.selectedCaptureDeviceID = settings[@"captureDeviceID"];
    NSDictionary *savedRects = settings[@"captureVideoRects"];
    if ([savedRects isKindOfClass:NSDictionary.class] && savedRects.count > 0) {
        self.captureCardVideoRects = [savedRects mutableCopy];
    }
    if (self.inputSourceSegment == 1) {
        [self refreshCaptureDevices:nil];
        [self updateCaptureCardStatus];
    }
    [self clampRegionSliders];
    [self updateCaptionAppearance];
    [self updateThemeSummary];
    self.loadingSettings = NO;
}

// 把 OCR 行喂给独立分组器，再映射回应用的 OCRTextItem（字段语义保持不变）。
// 几何判定、联合去重与长短分类都在 FYInlineGrouper 里，这里不重复堆条件。
- (NSArray<OCRTextItem *> *)mergedInlineTextItemsFromItems:(NSArray<OCRTextItem *> *)items {
    if (items.count == 0) { return @[]; }
    NSMutableArray<FYInlineTextLine *> *lines = [NSMutableArray arrayWithCapacity:items.count];
    for (NSUInteger index = 0; index < items.count; index++) {
        OCRTextItem *item = items[index];
        [lines addObject:[FYInlineTextLine lineWithText:(item.text ?: @"")
                                                   rect:item.boundingBox
                                             confidence:item.confidence
                                            sourceIndex:(NSInteger)index]];
    }
    NSArray<FYInlineTextBlock *> *blocks = [self.inlineGrouper blocksFromLines:lines];
    NSMutableArray<OCRTextItem *> *result = [NSMutableArray arrayWithCapacity:blocks.count];
    for (FYInlineTextBlock *block in blocks) {
        OCRTextItem *item = [[OCRTextItem alloc] init];
        item.text = block.text;
        item.boundingBox = block.boundingBox;
        item.lastLineBox = block.lineBoxes.lastObject ? [block.lineBoxes.lastObject rectValue] : block.boundingBox;
        item.lineTexts = block.lineTexts;
        item.lineBoxes = block.lineBoxes;
        item.lineCount = block.lineCount;
        item.blockKind = block.kind == FYInlineBlockKindLong ? InlineBlockKindLong : InlineBlockKindShort;
        item.groupingConfidence = block.groupingConfidence;
        item.sourceBlockID = block.blockID;
        CGFloat confidenceSum = 0;
        for (NSNumber *value in block.lineConfidences) { confidenceSum += value.doubleValue; }
        item.confidence = block.lineConfidences.count > 0 ? confidenceSum / (CGFloat)block.lineConfidences.count : 0;
        [result addObject:item];
    }
    return result;
}

// 把应用的原文项转成布局器的输入块（分类用已经判定好的 blockKind，
// 身份沿用 inlineBlockIdentityForItem: 的格式，保证点击/选中绑定不变）。
- (FYInlineTextBlock *)inlineLayoutBlockForItem:(OCRTextItem *)item order:(NSInteger)order {
    FYInlineTextBlock *block = [FYInlineTextBlock new];
    block.text = item.text ?: @"";
    NSArray<NSValue *> *boxes = item.lineBoxes.count > 0 ? item.lineBoxes
        : (item.boundingBox.size.width > 0 ? @[[NSValue valueWithRect:item.boundingBox]] : @[]);
    block.lineBoxes = boxes;
    NSMutableArray<NSString *> *lineTexts = [NSMutableArray array];
    NSArray<NSString *> *split = [block.text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSUInteger index = 0; index < boxes.count; index++) {
        [lineTexts addObject:index < split.count ? split[index] : @""];
    }
    if (lineTexts.count == 0) { [lineTexts addObject:block.text]; }
    block.lineTexts = lineTexts;
    block.boundingBox = item.boundingBox;
    block.kind = item.blockKind == InlineBlockKindLong ? FYInlineBlockKindLong : FYInlineBlockKindShort;
    block.groupingConfidence = item.groupingConfidence > 0 ? item.groupingConfidence : 1.0;
    block.sourceIndices = @[];
    block.readingOrder = order;
    block.blockID = [FYInlineBlockMatcher blockIDForText:block.text lineBoxes:boxes];
    return block;
}

- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items {
    return [self filteredInlineTextItems:items strict:YES];
}

- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items strict:(BOOL)strict {
    NSMutableArray<OCRTextItem *> *candidates = [NSMutableArray array];
    NSMutableArray<OCRTextItem *> *accepted = [NSMutableArray array];

    for (OCRTextItem *item in items) {
        NSString *text = Trim(item.text);
        NSString *normalized = NormalizeForComparison(text);
        if (normalized.length < 2) { continue; }
        // 重复识别按**文字 + 位置**联合去重：同一处的同文只留一条，
        // 不同位置的同文内容必须各自保留（两篇文章里的同一句话不能被删掉一条）。
        BOOL duplicate = NO;
        for (OCRTextItem *kept in accepted) {
            if (![NormalizeForComparison(kept.text) isEqualToString:normalized]) { continue; }
            if ([FYInlineBlockMatcher overlapRatio:item.boundingBox right:kept.boundingBox] < 0.5) { continue; }
            duplicate = YES;
            if (item.confidence > kept.confidence) { kept.confidence = item.confidence; }
            break;
        }
        if (duplicate) { continue; }
        if (item.boundingBox.size.height < 0.015 && normalized.length < 5) { continue; }
        if ([self shouldIgnoreInlineText:text normalized:normalized boundingBox:item.boundingBox strict:strict]) { continue; }

        item.text = text;
        [accepted addObject:item];
        [candidates addObject:item];
    }

    [candidates sortUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) {
        // 第一关键字：正文优先、按钮垫底。这样上限截断时先牺牲按钮，不会挤掉正文。
        BOOL leftButton = [self isButtonLikeInlineText:NormalizeForComparison(left.text)];
        BOOL rightButton = [self isButtonLikeInlineText:NormalizeForComparison(right.text)];
        if (leftButton != rightButton) { return leftButton ? NSOrderedDescending : NSOrderedAscending; }

        double leftScore = [self inlinePriorityForText:left.text normalized:NormalizeForComparison(left.text) boundingBox:left.boundingBox];
        double rightScore = [self inlinePriorityForText:right.text normalized:NormalizeForComparison(right.text) boundingBox:right.boundingBox];
        if (leftScore > rightScore) { return NSOrderedAscending; }
        if (leftScore < rightScore) { return NSOrderedDescending; }
        CGFloat leftTop = CGRectGetMaxY(left.boundingBox);
        CGFloat rightTop = CGRectGetMaxY(right.boundingBox);
        if (fabs(leftTop - rightTop) > 0.025) {
            return leftTop > rightTop ? NSOrderedAscending : NSOrderedDescending;
        }
        return left.boundingBox.origin.x < right.boundingBox.origin.x ? NSOrderedAscending : NSOrderedDescending;
    }];

    // 两级上限：正文先占满 20 条，按钮只吃**剩下的**额度。
    // 这样按钮永远排在最后，且绝不会挤掉正文 —— 之前是按钮也占正文名额。
    NSUInteger contentLimit = MIN((NSUInteger)20, candidates.count);
    NSMutableArray<OCRTextItem *> *contentItems = [NSMutableArray array];
    NSMutableArray<OCRTextItem *> *buttonItems = [NSMutableArray array];
    for (OCRTextItem *item in candidates) {
        if ([self isButtonLikeInlineText:NormalizeForComparison(item.text)]) {
            [buttonItems addObject:item];
        } else {
            [contentItems addObject:item];
        }
    }
    NSMutableArray<OCRTextItem *> *selected = [NSMutableArray array];
    [selected addObjectsFromArray:[contentItems subarrayWithRange:NSMakeRange(0, MIN(contentLimit, contentItems.count))]];
    NSUInteger remaining = contentLimit > selected.count ? contentLimit - selected.count : 0;
    if (remaining > 0) {
        [selected addObjectsFromArray:[buttonItems subarrayWithRange:NSMakeRange(0, MIN(remaining, buttonItems.count))]];
    }
    NSArray<OCRTextItem *> *topItems = selected;
    NSArray<OCRTextItem *> *readingOrder = [topItems sortedArrayUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) {
        CGFloat leftTop = CGRectGetMaxY(left.boundingBox);
        CGFloat rightTop = CGRectGetMaxY(right.boundingBox);
        if (fabs(leftTop - rightTop) > 0.025) {
            return leftTop > rightTop ? NSOrderedAscending : NSOrderedDescending;
        }
        if (left.boundingBox.origin.x < right.boundingBox.origin.x) { return NSOrderedAscending; }
        if (left.boundingBox.origin.x > right.boundingBox.origin.x) { return NSOrderedDescending; }
        return NSOrderedSame;
    }];

    // 最后再按阅读顺序输出，但**按钮统一挪到队尾**：
    // 贴译是按这个顺序逐条生成的，按钮排最后就不会和正文抢显示位置。
    NSMutableArray<OCRTextItem *> *ordered = [NSMutableArray array];
    for (OCRTextItem *item in readingOrder) {
        if (![self isButtonLikeInlineText:NormalizeForComparison(item.text)]) { [ordered addObject:item]; }
    }
    for (OCRTextItem *item in readingOrder) {
        if ([self isButtonLikeInlineText:NormalizeForComparison(item.text)]) { [ordered addObject:item]; }
    }
    return ordered;
}

- (NSString *)dialogueTextFromItems:(NSArray<OCRTextItem *> *)items speakerLabelOnly:(BOOL *)speakerLabelOnly {
    NSMutableArray<NSString *> *lines=[NSMutableArray array];
    for(OCRTextItem *item in items){
        if(IsCornerHelpButton(item) || IsFuriganaNearLargerLine(item,items)){continue;}
        if([self shouldIgnoreInlineText:item.text normalized:NormalizeForComparison(item.text) boundingBox:item.boundingBox strict:YES]){continue;}
        [lines addObject:item.text];
    }
    // A frame containing only the speaker's name must not become a sentence.
    if(speakerLabelOnly){*speakerLabelOnly=DialogueFrameIsSpeakerLabelOnly(lines);}
    return DialogueTextWithoutTrailingButton([lines componentsJoinedByString:@"\n"]);
}

- (BOOL)shouldIgnoreInlineText:(NSString *)text normalized:(NSString *)normalized boundingBox:(CGRect)box strict:(BOOL)strict {
    if (normalized.length == 0) { return YES; }

    // 只有**完全没有假名/汉字**的行才算“没有可译内容”：纯省略号、纯标点、空白。
    // 只要含一个有效日文字符就必须保留 —— 「え……」只有一个字也必须留。
    //
    // 以前这里用「点号占比 ≥ 一半 + 实义部分 ≤ 3 字 + 框宽 < 0.16」判噪声，把
    // 「あれは・・・・・・」（框宽 0.115987）整行删掉，只剩「琥一／話し合いだ。」；
    // 「退学って……」「どれど……」也栽在同类判据上。按用户要求删掉这些
    // 字数/框宽/点号占比条件，不再用新的宽度阈值或词语表替代。
    {
        NSCharacterSet *dots = [NSCharacterSet characterSetWithCharactersInString:@"・…‥.．·"];
        NSUInteger dotCount = 0;
        BOOL hasJapanese = NO;
        for (NSUInteger index = 0; index < text.length; index++) {
            unichar character = [text characterAtIndex:index];
            if ([dots characterIsMember:character]) { dotCount += 1; continue; }
            if ((character >= 0x3040 && character <= 0x30FF) ||    // 平假名 / 片假名
                (character >= 0x4E00 && character <= 0x9FFF) ||    // 汉字
                (character >= 0xFF66 && character <= 0xFF9F)) {    // 半角片假名
                hasJapanese = YES;
                break;
            }
        }
        if (dotCount > 0 && !hasJapanese) {
            // 保留诊断：现场“少半句”时先看有没有这行，能直接区分“被过滤”和“OCR 漏读”。
            FuyiDiagLog(@"  DROP-PUNCTUATION-ONLY <%@> w=%.3f dots=%lu/%lu", text, box.size.width,
                        (unsigned long)dotCount, (unsigned long)text.length);
            return YES;
        }
        // 纯标点/符号行（同样没有假名汉字）也没有可译内容。
        if (!hasJapanese && text.length > 0) {
            NSCharacterSet *punct = [NSCharacterSet punctuationCharacterSet];
            NSCharacterSet *symbols = [NSCharacterSet symbolCharacterSet];
            NSCharacterSet *spaces = [NSCharacterSet whitespaceAndNewlineCharacterSet];
            BOOL onlyPunctuation = YES;
            for (NSUInteger index = 0; index < text.length; index++) {
                unichar character = [text characterAtIndex:index];
                if (character == 0x3000 || [spaces characterIsMember:character] ||
                    [punct characterIsMember:character] || [symbols characterIsMember:character]) { continue; }
                onlyPunctuation = NO;
                break;
            }
            if (onlyPunctuation) {
                FuyiDiagLog(@"  DROP-PUNCTUATION-ONLY <%@> w=%.3f", text, box.size.width);
                return YES;
            }
        }
    }

    NSString *lower = normalized.lowercaseString;
    if (strict) {
        // 对白模式：这些词基本是游戏 UI/环境噪声，不该混进字幕
        NSArray<NSString *> *ignoreTokens = @[
            @"today", @"web", @"back", @"戻る", @"戻", @"詳細", @"閉じる", @"ルームへ",
            @"更新", @"news", @"no.", @"no", @"ok", @"yes", @"skip", @"auto", @"menu"
        ];
        // 说明：这条“界面词表”规则保持不变（它需要同时命中词表与长度/宽度条件，
        // 不属于本轮要删除的“仅凭字数/框宽/省略号比例删除”的误删条件）。
        for (NSString *token in ignoreTokens) {
            if ([lower isEqualToString:token] || [lower containsString:token]) {
                if (normalized.length <= 8 || box.size.width < 0.16 || box.size.height < 0.06) {
                    return YES;
                }
            }
        }

        // 这里原本还有一条“短、窄、全平假名 = 名字框错读”的删除规则（`ことと` 之类）。
        // 按本轮要求删除：只要含有效日文文字，就不能凭字数少、框窄删掉 —— 「え」这种
        // 单字台词同样要保留。代价是名字框的错读可能被翻译出来；完整性优先。
    } else {
        // 这里原本还有一条“短且全是平假名/符号 = 噪声”的删除规则（同样会把
        // 「え……」这类短台词在贴译路径也删掉）。本轮删除：含有效日文文字就保留。
        // 下面只保留“完全没有假名/汉字”的纯字母碎片过滤 —— 那种行里没有可译的日文。

        // 短且**完全没有日文假名/汉字**的纯字母碎片，也是 `？？？` 之类的错读
        // （实测名字框被读成 `iee`），发去翻译只会得到编造的译文。
        if (!strict && normalized.length <= 6) {
            BOOL hasKanaOrKanji = NO;
            for (NSUInteger index = 0; index < normalized.length; index++) {
                unichar character = [normalized characterAtIndex:index];
                if ((character >= 0x3040 && character <= 0x30FF) ||   // 平假名 / 片假名
                    (character >= 0x4E00 && character <= 0x9FFF)) {   // 汉字
                    hasKanaOrKanji = YES;
                    break;
                }
            }
            if (!hasKanaOrKanji) { return YES; }
        }

        // 界面模式：按钮、日期、条目编号都是用户要看的文字，不能当成噪声丢掉。
        // 之前和上面共用同一张表，导致「No. 48 5/1更新」被 “更新” 命中而整条不翻，
        // 「詳細」「戻る」这类按钮也永远不会被翻译。
        // 这里只丢真正的装饰：版本号样式的一小串字符。
        NSArray<NSString *> *decorativeTokens = @[@"no.", @"no"];
        for (NSString *token in decorativeTokens) {
            if (([lower isEqualToString:token]) && normalized.length <= 3) { return YES; }
        }
    }

    NSCharacterSet *digitsAndMarks = [NSCharacterSet characterSetWithCharactersInString:@"0123456789/.-〜~年月日(月)(火)(水)(木)(金)(土)(日) "];
    BOOL onlyDigitsAndMarks = normalized.length > 0;
    for (NSUInteger index = 0; index < normalized.length; index++) {
        if (![digitsAndMarks characterIsMember:[normalized characterAtIndex:index]]) {
            onlyDigitsAndMarks = NO;
            break;
        }
    }
    if (onlyDigitsAndMarks) { return YES; }

    // 贴边且短：多半是画面边缘的按钮。
    // 但**必须同时够窄**才算按钮 —— 对白框本身就贴在画面下方，
    // 实测把它整句丢掉（`送ってく。` 宽 0.11、y=0.052）会让最后一行对白消失。
    BOOL nearBottomOrTop = box.origin.y < 0.08 || CGRectGetMaxY(box) > 0.94;
    // 必须**横向也贴边**才算角落按钮。对白框本身就贴在画面下方（实测「行くぞ。」y=0.053），
    // 只按纵向+窄度判定会把台词整句丢掉 —— 现在字幕为空就是这么来的。
    BOOL nearLeftOrRight = box.origin.x < 0.12 || CGRectGetMaxX(box) > 0.88;
    if (nearBottomOrTop && nearLeftOrRight && normalized.length <= 8 && box.size.width < 0.10) {
        return YES;
    }

    return NO;
}

// 按钮/导航类小标签（詳細・戻る・閉じる…）。
// 它们值得翻，但不该占掉正文的位置 —— 排序时排到最后，超上限时先牺牲它们。
- (BOOL)isButtonLikeInlineText:(NSString *)normalized {
    if (normalized.length == 0 || normalized.length > 8) { return NO; }
    NSString *lower = normalized.lowercaseString;
    NSArray<NSString *> *buttonTokens = @[@"詳細", @"閉じる", @"戻る", @"戻", @"次へ", @"決定",
                                          @"設定", @"メニュー", @"スキップ", @"ルームへ",
                                          @"back", @"close", @"menu", @"next", @"ok",
                                          @"cancel", @"skip", @"setting", @"settings"];
    for (NSString *token in buttonTokens) {
        if ([lower isEqualToString:token] || [lower hasPrefix:token]) { return YES; }
    }
    return NO;
}

- (double)inlinePriorityForText:(NSString *)text normalized:(NSString *)normalized boundingBox:(CGRect)box {
    double score = 0;
    NSUInteger length = normalized.length;
    score += MIN(40.0, (double)length * 2.2);

    double area = box.size.width * box.size.height;
    score += MIN(18.0, area * 240.0);

    double centerX = CGRectGetMidX(box);
    double centerY = CGRectGetMidY(box);
    double distanceFromCenter = hypot(centerX - 0.5, centerY - 0.5);
    score += MAX(0, 22.0 - distanceFromCenter * 45.0);

    if (length >= 16) { score += 18; }
    if (length >= 28) { score += 15; }
    if (box.size.width > 0.30) { score += 12; }
    if (box.size.height > 0.045) { score += 8; }
    if (box.origin.y > 0.18 && CGRectGetMaxY(box) < 0.86) { score += 10; }

    NSString *lower = normalized.lowercaseString;
    // 按钮类排到最后：正文/条目优先，只有还有余量时才翻按钮
    if ([self isButtonLikeInlineText:normalized]) { score -= 90; }
    if ([lower containsString:@"today"] || [lower containsString:@"news"] || [lower containsString:@"web"]) { score -= 25; }
    if (length <= 4) { score -= 18; }
    if (box.origin.y < 0.10 || CGRectGetMaxY(box) > 0.92) { score -= 20; }

    return score;
}

- (NSString *)inlineTranslationCacheKeyForItem:(OCRTextItem *)item {
    NSString *normalized = NormalizeForComparison(item.text);
    return item.blockKind == InlineBlockKindLong ? [@"L:" stringByAppendingString:normalized] : normalized;
}

- (void)translateInlineTextItems:(NSArray<OCRTextItem *> *)items completion:(void (^)(NSArray<NSString *> *translations, NSError *error))completion {
    NSDictionary *trace = FYCurrentTrace();
    NSMutableArray<NSString *> *translations = [NSMutableArray arrayWithCapacity:items.count];
    NSMutableArray<OCRTextItem *> *pendingItems = [NSMutableArray array];
    NSMutableArray<NSNumber *> *pendingIndexes = [NSMutableArray array];
    NSMutableArray<NSString *> *pendingKeys = [NSMutableArray array];

    for (NSUInteger index = 0; index < items.count; index++) {
        OCRTextItem *item = items[index];
        NSString *key = [self inlineTranslationCacheKeyForItem:item];
        NSString *cached = self.inlineTranslationCache[key];
        FYTrace(trace, @"cache", @{@"route": @"inline", @"source": item.text ?: @"", @"cache_hit": @(cached.length > 0)});
        if (cached.length > 0) {
            [translations addObject:cached];
        } else {
            [translations addObject:@""];
            [pendingItems addObject:item];
            [pendingIndexes addObject:@(index)];
            [pendingKeys addObject:key];
        }
    }

    if (pendingItems.count == 0) {
        completion(translations, nil);
        return;
    }

    // 长短块分开翻译：短标签要短、正文要完整，缓存键也按类型区分，避免正文复用旧的短译文。
    NSMutableArray<OCRTextItem *> *longItems = [NSMutableArray array], *shortItems = [NSMutableArray array];
    NSMutableArray<NSNumber *> *longIndexes = [NSMutableArray array], *shortIndexes = [NSMutableArray array];
    NSMutableArray<NSString *> *longKeys = [NSMutableArray array], *shortKeys = [NSMutableArray array];
    for (NSUInteger i = 0; i < pendingItems.count; i++) {
        if (pendingItems[i].blockKind == InlineBlockKindLong) {
            [longItems addObject:pendingItems[i]]; [longIndexes addObject:pendingIndexes[i]]; [longKeys addObject:pendingKeys[i]];
        } else {
            [shortItems addObject:pendingItems[i]]; [shortIndexes addObject:pendingIndexes[i]]; [shortKeys addObject:pendingKeys[i]];
        }
    }

    __block BOOL shortDone = shortItems.count == 0;
    __block BOOL longDone = longItems.count == 0;
    __block NSError *shortError = nil, *longError = nil;
    void (^maybeFinish)(void) = ^{
        if (!shortDone || !longDone) { return; }
        NSError *error = shortError ?: longError;
        completion(error ? nil : translations, error);
    };

    if (shortItems.count) {
        [self translateInlineBatch:shortItems indexes:shortIndexes keys:shortKeys translations:translations long:NO completion:^(NSError *error) {
            shortError = error; shortDone = YES; maybeFinish();
        }];
    }
    if (longItems.count) {
        [self translateInlineBatch:longItems indexes:longIndexes keys:longKeys translations:translations long:YES completion:^(NSError *error) {
            longError = error; longDone = YES; maybeFinish();
        }];
    }
}

// 翻译一批同类型的界面文字块，结果按 indexes 写回共享 translations 数组。
- (void)translateInlineBatch:(NSArray<OCRTextItem *> *)items
                     indexes:(NSArray<NSNumber *> *)indexes
                        keys:(NSArray<NSString *> *)keys
                translations:(NSMutableArray<NSString *> *)translations
                        long:(BOOL)isLong
                  completion:(void (^)(NSError *error))completion {
    NSMutableString *numberedText = [NSMutableString string];
    for (NSUInteger index = 0; index < items.count; index++) {
        [numberedText appendFormat:@"%lu. %@\n", (unsigned long)(index + 1), items[index].text];
    }

    NSString *source = SourceLanguageLabel(self.languageControl.selectedSegment);
    NSString *prompt = isLong
        ? [NSString stringWithFormat:@"你是游戏界面公告翻译器。把用户发来的%@界面正文逐条翻译成简体中文。输出必须保留编号，每行格式为“1. 译文”。译文要完整、通顺，保留段落结构和完整意思，不要压缩成短语；不要解释，不要输出原文。", source]
        : [NSString stringWithFormat:@"你是游戏界面贴译器。把用户发来的%@界面文字逐条翻译成简体中文。输出必须保留编号，每行格式为“1. 译文”。译文要短，适合贴在原文字旁边；不要解释，不要输出原文。按钮和菜单用短语，公告正文保持完整意思。", source];
    NSInteger maxTokens = isLong ? MAX(320, (NSInteger)items.count * 220) : MAX(240, (NSInteger)items.count * 80);

    [self translateTextRealtime:numberedText systemPrompt:prompt maxTokens:maxTokens completion:^(NSString *translated, NSError *error) {
        if (error) { completion(error); return; }

        NSArray<NSString *> *parsed = [self parseNumberedTranslations:translated expectedCount:items.count];
        if (parsed.count != items.count) {
            NSMutableArray<NSString *> *seenValues = [NSMutableArray array];
            BOOL allBlank = YES;
            for (NSUInteger index = 0; index < items.count; index++) {
                NSString *value = index < parsed.count ? Trim(parsed[index]) : @"";
                NSNumber *targetIndex = indexes[index];
                translations[targetIndex.unsignedIntegerValue] = value;
                if (value.length == 0) { continue; }
                allBlank = NO;
                if (![seenValues containsObject:value]) { [seenValues addObject:value]; }
            }

            if (allBlank) {
                NSError *parseError = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                                          code:205
                                                      userInfo:@{NSLocalizedDescriptionKey: @"贴译结果没有按编号返回，已跳过这一轮；请重试或改用更稳定的模型（如 DeepSeek Flash）。"}];
                completion(parseError);
                return;
            }

            BOOL looksLikeDuplicatedParagraph = seenValues.count == 1 && items.count >= 3 && [seenValues[0] length] > 24;
            if (looksLikeDuplicatedParagraph) {
                NSError *parseError = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                                          code:205
                                                      userInfo:@{NSLocalizedDescriptionKey: @"贴译结果像是一整段文字被重复返回，已跳过这一轮以避免整屏贴同一句。"}];
                completion(parseError);
                return;
            }

            for (NSUInteger index = 0; index < items.count; index++) {
                NSString *value = translations[indexes[index].unsignedIntegerValue];
                if (value.length == 0) { continue; }
                [self cacheInlineTranslation:value forKey:keys[index]];
            }
            completion(nil);
            return;
        }

        for (NSUInteger index = 0; index < items.count; index++) {
            NSString *value = index < parsed.count ? Trim(parsed[index]) : @"";
            NSNumber *targetIndex = indexes[index];
            translations[targetIndex.unsignedIntegerValue] = value;
            if (value.length == 0) { continue; }
            [self cacheInlineTranslation:value forKey:keys[index]];
        }
        completion(nil);
    }];
}

- (void)cacheInlineTranslation:(NSString *)value forKey:(NSString *)key {
    if (value.length == 0 || key.length == 0) { return; }
    if (self.inlineTranslationCache.count >= 4000 && self.inlineTranslationCache[key] == nil) {
        [self.inlineTranslationCache removeAllObjects];
    }
    self.inlineTranslationCache[key] = value;
}

- (NSArray<NSString *> *)parseNumberedTranslations:(NSString *)text expectedCount:(NSUInteger)count {
    NSMutableArray<NSString *> *results = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger index = 0; index < count; index++) {
        [results addObject:@""];
    }

    NSInteger currentIndex = -1;
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSString *rawLine in lines) {
        NSString *line = Trim(rawLine);
        if (line.length == 0) { continue; }

        NSUInteger cursor = 0;
        while (cursor < line.length && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[line characterAtIndex:cursor]]) {
            cursor++;
        }

        if (cursor > 0 && cursor < line.length) {
            NSInteger number = [[line substringToIndex:cursor] integerValue];
            if (number >= 1 && (NSUInteger)number <= count) {
                while (cursor < line.length) {
                    unichar character = [line characterAtIndex:cursor];
                    if (character == '.' || character == ')' || character == 0x3001 || character == 0xff0e || character == ':' || character == 0xff1a || [[NSCharacterSet whitespaceCharacterSet] characterIsMember:character]) {
                        cursor++;
                    } else {
                        break;
                    }
                }

                currentIndex = number - 1;
                results[currentIndex] = Trim([line substringFromIndex:cursor]);
                continue;
            }
        }

        if (currentIndex >= 0) {
            NSString *existing = results[currentIndex];
            results[currentIndex] = existing.length > 0 ? [existing stringByAppendingFormat:@"\n%@", line] : line;
        }
    }

    BOOL hasAnyNumbered = NO;
    for (NSString *result in results) {
        if (Trim(result).length > 0) {
            hasAnyNumbered = YES;
            break;
        }
    }

    if (!hasAnyNumbered) { return @[]; }

    return results;
}

- (void)clearInlineTranslationPanels {
    [self closeExpandedInlineReadingCard];
    for (NSPanel *panel in self.inlineTranslationPanels) {
        [panel close];
    }
    for (NSPanel *panel in self.inlineLongCardPanels) {
        [panel close];
    }
    [self.inlineTranslationPanels removeAllObjects];
    [self.inlineLongCardPanels removeAllObjects];
    [self.inlinePanelsByBlockID removeAllObjects];
    // 画面换页/停止/切换窗口时清掉手动位置：绝不把偏移继承给其它块或下一场景。
    [self.inlineManualOffsets removeAllObjects];
    [self.inlineManualOffsetAge removeAllObjects];
    [self.inlineStableBlockIDs removeAllObjects];
    self.inlineDraggingPanel = nil;
    [self stopInlineModifierMonitor];
    self.lastInlineLayoutResult = nil;
    self.lastInlineUnplaceableCount = 0;
    self.lastInlineCompactEntryCount = 0;
    self.lastInlineTranslationKey = nil;
    [self refreshInlineTranslationList];
}

// 内容指纹：译文 + 原文 + 位置。三者都没变就说明这一帧没有任何变化。
- (NSString *)inlineTranslationIdentityForTranslations:(NSArray<NSString *> *)translations
                                              forItems:(NSArray<OCRTextItem *> *)items {
    NSMutableString *identity = [NSMutableString string];
    NSUInteger count = MIN(translations.count, items.count);
    for (NSUInteger index = 0; index < count; index++) {
        OCRTextItem *item = items[index];
        [identity appendFormat:@"%@\n%@\n%.4f:%.4f:%.4f:%.4f\n",
         NormalizeForComparison(item.text), Trim(translations[index]),
         item.boundingBox.origin.x, item.boundingBox.origin.y,
         item.boundingBox.size.width, item.boundingBox.size.height];
    }
    return [identity copy];
}

// 就地更新一个已有贴译面板（不销毁、不重建窗口 → 不会闪）
- (void)updateInlinePanel:(NSPanel *)panel
              translation:(NSString *)translation
               sourceText:(NSString *)sourceText
              sourceFrame:(NSRect)sourceFrame
              windowFrame:(NSRect)windowFrame
                   layout:(InlinePanelLayout)layout {
    NSView *content = panel.contentView;
    NSView *firstSubview = content.subviews.firstObject;
    if (!content || ![firstSubview isKindOfClass:NSTextField.class]) { return; }
    NSTextField *label = (NSTextField *)firstSubview;

    // 先改窗口尺寸（display:NO 不立即重画），再改文字，最后一次性显示，避免中间态闪一下
    if (!NSEqualRects(panel.frame, layout.frame)) { [panel setFrame:layout.frame display:NO]; }
    if (!NSEqualRects(content.frame, NSMakeRect(0, 0, NSWidth(layout.frame), NSHeight(layout.frame)))) {
        content.frame = NSMakeRect(0, 0, NSWidth(layout.frame), NSHeight(layout.frame));
    }
    if (![label.stringValue isEqualToString:translation]) {
        label.attributedStringValue = [self inlinePanelAttributedText:translation font:layout.font];
    }
    if (!NSEqualRects(label.frame, layout.labelFrame)) { label.frame = layout.labelFrame; }
    [self applyInlineChromeToContent:content cornerRadius:layout.cornerRadius];
    [panel displayIfNeeded];
}

- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items {
    WindowItem *window = [self selectedWindowItem];
    if (!window) { return; }
    [self showInlineTranslations:translations forItems:items placementRect:[self appKitFrameForWindowItem:window]];
}

// placementRect：贴译面板的落位区域。窗口截图模式是整个目标窗口；
// 采集卡模式是「视频帧等比适配到目标显示窗口」后的可见矩形（见 captureCardDisplayRectForWindow:）。
//
// 布局流程（本帧统一安排，不逐张盲找空位）：
//   ① 全部原文块 + 待显示译文交给 FYInlineLayoutEngine：每块只生成有限候选，
//      先剔除超出可见区域／遮挡其它原文块／与本帧其它译文冲突／离原文过远／低于可读下限的候选；
//   ② 面板按**块身份**复用：位置或文字变了就地更新，只有模式切换才重建内容视图；
//   ③ 没有合法位置的块不伪造位置，只统计降级数量（提示走主界面状态区，不写字幕框）。
- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items placementRect:(NSRect)windowFrame {
    if (NSWidth(windowFrame) < 2 || NSHeight(windowFrame) < 2) { return; }
    // 正在拖动某一面板：这一帧先不重排，避免 OCR 循环把面板从用户手里拽回去。
    // 拖动结束会记录新偏移，下一帧按新位置渲染。
    if (self.inlineDraggingPanel) { return; }
    // 落位区域也进入内容指纹：窗口移动/缩放后即使页面文字没变，也必须重新布局，
    // 否则贴译会停在旧坐标上、跟原文错位（手动拖动过的位置同样要重新夹到可见区域内）。
    NSString *identity = [[self inlineTranslationIdentityForTranslations:translations forItems:items]
                          stringByAppendingFormat:@"|vp=%.1f,%.1f,%.1f,%.1f",
                          NSMinX(windowFrame), NSMinY(windowFrame), NSWidth(windowFrame), NSHeight(windowFrame)];
    // 页面文字没变：只把已有面板重新显示出来，绝不 close / 重建。
    // （旧实现每帧 clear + 新建 NSPanel，这正是贴译一闪一闪的原因。）
    if (self.lastInlineTranslationKey && [self.lastInlineTranslationKey isEqualToString:identity] &&
        self.lastInlineLayoutResult) {
        [self refreshOverlayVisibility:nil];
        return;
    }
    NSUInteger count = MIN(translations.count, items.count);
    FuyiDiagLog(@"  RENDER in=%lu panels", (unsigned long)count);

    NSMutableArray<FYInlineLayoutRequest *> *requests = [NSMutableArray array];
    NSMutableDictionary<NSString *, OCRTextItem *> *itemsByBlockID = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index < count; index++) {
        NSString *translation = Trim(translations[index]);
        if (translation.length == 0) { continue; }
        OCRTextItem *item = items[index];
        FYInlineTextBlock *block = [self inlineLayoutBlockForItem:item order:(NSInteger)index];
        NSRect sourceFrame = [self appKitFrameForOCRItem:item inWindowFrame:windowFrame];
        FYInlineLayoutRequest *request = [FYInlineLayoutRequest requestWithBlock:block translation:translation sourceFrame:sourceFrame];
        NSValue *manual = [self inlineManualOffsetForText:block.text normalizedBox:block.boundingBox];
        if (manual) {
            request.manuallyPlaced = YES;
            request.manualOffset = manual.sizeValue;
        }
        [requests addObject:request];
        itemsByBlockID[block.blockID] = item;
    }
    FYInlineLayoutResult *result = [self.inlineLayoutEngine layoutRequests:requests
                                                                 viewport:windowFrame
                                                                 previous:self.lastInlineLayoutResult];

    NSMutableArray<NSPanel *> *shortPanels = [NSMutableArray array];
    NSMutableArray<NSPanel *> *longPanels = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSPanel *> *keptPanels = [NSMutableDictionary dictionary];
    NSUInteger unplaceable = 0;
    NSUInteger compactEntries = 0;

    for (FYInlinePlacement *placement in result.placements) {
        OCRTextItem *item = itemsByBlockID[placement.sourceBlockID];
        if (!item) { continue; }
        if (placement.mode == FYInlineDisplayModeUnplaceable) {
            unplaceable += 1;
            FuyiDiagLog(@"    UNPLACEABLE <%@> %@", Shorten(item.text, 24), placement.reason);
            continue;
        }
        BOOL wantsLongCard = item.blockKind == InlineBlockKindLong;
        NSPanel *panel = self.inlinePanelsByBlockID[placement.blockID];
        if (panel && ([panel.contentView isKindOfClass:FYInlineLongCardView.class] != wantsLongCard)) {
            // 短贴片 ↔ 长卡切换：内容视图语义不同，只重建这一个面板。
            [panel close];
            panel = nil;
        }
        if (wantsLongCard) {
            if (panel) {
                [self updateInlineLongCard:panel
                               translation:placement.translation
                                      item:item
                                     frame:placement.translationFrame
                                   compact:placement.compactEntry
                                 placement:placement];
            } else {
                panel = [self inlineLongPanelForTranslation:placement.translation
                                                       item:item
                                                      frame:placement.translationFrame
                                                  placement:placement];
            }
            if (!panel) { continue; }
            [longPanels addObject:panel];
        } else {
            InlinePanelLayout layout = [self inlinePanelLayoutFromPlacement:placement];
            if (panel) {
                [self updateInlinePanel:panel
                            translation:placement.translation
                             sourceText:item.text
                            sourceFrame:placement.sourceFrame
                            windowFrame:windowFrame
                                 layout:layout];
            } else {
                panel = [self inlinePanelForTranslation:placement.translation
                                             sourceText:item.text
                                            sourceFrame:placement.sourceFrame
                                            windowFrame:windowFrame
                                                 layout:layout];
            }
            if (!panel) { continue; }
            [shortPanels addObject:panel];
        }
        panel.identifier = placement.blockID;
        [self wireInlinePanelDrag:panel placement:placement];
        keptPanels[placement.blockID] = panel;
        if (placement.mode == FYInlineDisplayModeCompactEntry) { compactEntries += 1; }
        FuyiDiagLog(@"    PANEL src=<%@> mode=%ld anchor=%ld x=%.0f y=%.0f w=%.0f h=%.0f reason=%@",
                    Shorten(item.text, 24), (long)placement.mode, (long)placement.anchor,
                    panel.frame.origin.x, panel.frame.origin.y, NSWidth(panel.frame), NSHeight(panel.frame),
                    placement.reason);
    }

    // 这一帧多出来的旧面板关掉。
    for (NSString *blockID in self.inlinePanelsByBlockID) {
        if (!keptPanels[blockID]) { [self.inlinePanelsByBlockID[blockID] close]; }
    }
    self.inlinePanelsByBlockID = [keptPanels mutableCopy];
    self.inlineTranslationPanels = shortPanels;
    self.inlineLongCardPanels = longPanels;
    self.lastInlineLayoutResult = result;
    // 记录本帧「原始身份 → 稳定身份」，供选中判定/快照使用（缺字典时按需创建）。
    if (!self.inlineStableBlockIDs) { self.inlineStableBlockIDs = [NSMutableDictionary dictionary]; }
    [self.inlineStableBlockIDs removeAllObjects];
    for (FYInlinePlacement *placement in result.placements) {
        if (placement.sourceBlockID.length == 0 || placement.blockID.length == 0) { continue; }
        self.inlineStableBlockIDs[placement.sourceBlockID] = placement.blockID;
    }
    // 手动位置：把这一帧仍然存在的块按当前锚点重新落键（抖动换桶也不会丢），
    // 连续多帧没出现的块直接丢弃 —— 换页时不把偏移继承给别的块。
    NSMutableSet<NSString *> *seenKeys = [NSMutableSet set];
    for (FYInlinePlacement *placement in result.placements) {
        if (!placement.manuallyPlaced || placement.block.text.length == 0) { continue; }
        CGSize offset = CGSizeMake(NSMinX(placement.translationFrame) - NSMinX(placement.sourceFrame),
                                   NSMinY(placement.translationFrame) - NSMinY(placement.sourceFrame));
        NSString *key = [self inlineManualOffsetKeyForText:placement.block.text normalizedBox:placement.block.boundingBox];
        self.inlineManualOffsets[key] = [NSValue valueWithSize:offset];
        self.inlineManualOffsetAge[key] = @0;
        [seenKeys addObject:key];
    }
    for (NSString *key in self.inlineManualOffsets.allKeys) {
        if ([seenKeys containsObject:key]) { continue; }
        NSInteger age = [self.inlineManualOffsetAge[key] integerValue] + 1;
        if (age > 2) {
            [self.inlineManualOffsets removeObjectForKey:key];
            [self.inlineManualOffsetAge removeObjectForKey:key];
        } else {
            self.inlineManualOffsetAge[key] = @(age);
        }
    }
    [self refreshInlineTranslationList];
    if (shortPanels.count + longPanels.count > 0) { [self startInlineModifierMonitor]; }
    self.lastInlineUnplaceableCount = unplaceable;
    self.lastInlineCompactEntryCount = compactEntries;
    self.lastInlineTranslationKey = identity;
    [self refreshOverlayVisibility:nil];
}

#pragma mark - 贴译手动位置（拖动）

// 键 = 归一化文本 + **归一化**原文框中心的粗分桶（0.01 ≈ 11px@1080）。
// 用归一化坐标而不是显示坐标：窗口移动/缩放时框的归一化位置不变，手动位置才能跟着窗口走；
// 键里带文本与位置，所以换页后即使出现别的块也不会继承偏移；抖动落进相邻桶时按邻域查找。
static const CGFloat kInlineManualOffsetBucket = 0.01;

- (NSString *)inlineManualOffsetKeyForText:(NSString *)text normalizedBox:(CGRect)box {
    NSInteger bucketX = (NSInteger)floor(CGRectGetMidX(box) / kInlineManualOffsetBucket);
    NSInteger bucketY = (NSInteger)floor(CGRectGetMidY(box) / kInlineManualOffsetBucket);
    return [NSString stringWithFormat:@"%@|%ld,%ld", NormalizeForComparison(text ?: @""), (long)bucketX, (long)bucketY];
}

- (NSValue *)inlineManualOffsetForText:(NSString *)text normalizedBox:(CGRect)box {
    for (NSInteger dx = -1; dx <= 1; dx++) {
        for (NSInteger dy = -1; dy <= 1; dy++) {
            NSInteger bucketX = (NSInteger)floor(CGRectGetMidX(box) / kInlineManualOffsetBucket) + dx;
            NSInteger bucketY = (NSInteger)floor(CGRectGetMidY(box) / kInlineManualOffsetBucket) + dy;
            NSString *key = [NSString stringWithFormat:@"%@|%ld,%ld", NormalizeForComparison(text ?: @""), (long)bucketX, (long)bucketY];
            NSValue *value = self.inlineManualOffsets[key];
            if (value) { return value; }
        }
    }
    return nil;
}

// 拖动结束：记录「相对原文锚点」的偏移，并把面板夹回可见区域。
- (void)recordInlineManualOffsetForPanel:(NSPanel *)panel {
    self.inlineDraggingPanel = nil;
    if (!panel || panel.identifier.length == 0) { return; }
    FYInlinePlacement *placement = [self.lastInlineLayoutResult placementForBlockID:panel.identifier];
    if (!placement) { return; }
    NSRect frame = panel.frame;
    NSRect viewport = NSZeroRect;
    if ([self inlinePlacementRect:&viewport reason:NULL]) {
        CGRect clamped = frame;
        clamped.origin.x = MIN(MAX(clamped.origin.x, NSMinX(viewport) + 4),
                               MAX(NSMinX(viewport) + 4, NSMaxX(viewport) - 4 - NSWidth(clamped)));
        clamped.origin.y = MIN(MAX(clamped.origin.y, NSMinY(viewport) + 4),
                               MAX(NSMinY(viewport) + 4, NSMaxY(viewport) - 4 - NSHeight(clamped)));
        frame = NSIntegralRect(clamped);
    }
    if (!NSEqualRects(frame, panel.frame)) { [panel setFrame:frame display:YES]; }
    CGSize offset = CGSizeMake(NSMinX(frame) - NSMinX(placement.sourceFrame),
                               NSMinY(frame) - NSMinY(placement.sourceFrame));
    NSString *text = placement.block.text ?: @"";
    NSString *key = [self inlineManualOffsetKeyForText:text normalizedBox:placement.block.boundingBox];
    self.inlineManualOffsets[key] = [NSValue valueWithSize:offset];
    self.inlineManualOffsetAge[key] = @0;
    FuyiDiagLog(@"    INLINE-MANUAL <%@> offset=(%.0f,%.0f)", Shorten(text, 20), offset.width, offset.height);
}

// 把拖动行为绑到面板上：长卡走标题栏，短贴片按住 Option 才可拖。
- (void)wireInlinePanelDrag:(NSPanel *)panel placement:(FYInlinePlacement *)placement {
    __weak typeof(self) weakSelf = self;
    __weak NSPanel *weakPanel = panel;
    if ([panel.contentView isKindOfClass:FYInlineLongCardView.class]) {
        FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
        // 紧凑入口点哪儿都是“点击展开”，所以不给它标题栏拖动区。
        card.titleBarHeight = placement.compactEntry ? 0 : (placement.panelPadding + placement.titleBandHeight);
        card.onDragBegan = ^{ weakSelf.inlineDraggingPanel = weakPanel; };
        card.onDragEnded = ^{ [weakSelf recordInlineManualOffsetForPanel:weakPanel]; };
    } else if ([panel.contentView isKindOfClass:FYInlinePatchView.class]) {
        FYInlinePatchView *patch = (FYInlinePatchView *)panel.contentView;
        patch.dragEnabled = weakSelf.inlineOptionDragArmed;
        patch.showsDragHint = weakSelf.inlineOptionDragArmed;
        patch.onDragBegan = ^{ weakSelf.inlineDraggingPanel = weakPanel; };
        patch.onDragEnded = ^{ [weakSelf recordInlineManualOffsetForPanel:weakPanel]; };
    }
}

#pragma mark - 短贴片拖动（按住 Option）

- (void)startInlineModifierMonitor {
    if (self.inlineModifierTimer) { return; }
    // 定时读修饰键状态，而不是全局事件监听：全局键盘监听需要辅助功能授权，
    // 而贴译面板本身是穿透窗口，拿不到 flagsChanged。
    self.inlineModifierTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                               target:self
                                                             selector:@selector(inlineModifierTick:)
                                                             userInfo:nil
                                                              repeats:YES];
}

- (void)stopInlineModifierMonitor {
    [self.inlineModifierTimer invalidate];
    self.inlineModifierTimer = nil;
    if (self.inlineOptionDragArmed) { [self applyInlineDragMode:NO]; }
}

- (void)inlineModifierTick:(NSTimer *)timer {
    BOOL option = (NSEvent.modifierFlags & NSEventModifierFlagOption) != 0;
    [self applyInlineDragMode:option];
}

// 按住 Option：短贴片从「鼠标穿透」切到「可拖动」并显示反馈；松开恢复穿透。
// 拖动过程中保持不变，避免松手瞬间面板变穿透、事件落到游戏上。
- (void)applyInlineDragMode:(BOOL)armed {
    self.inlineOptionDragArmed = armed;
    for (NSPanel *panel in self.inlineTranslationPanels) {
        if (panel == self.inlineDraggingPanel) { continue; }
        panel.ignoresMouseEvents = !armed;
        NSView *content = panel.contentView;
        if ([content isKindOfClass:FYInlinePatchView.class]) {
            FYInlinePatchView *patch = (FYInlinePatchView *)content;
            patch.dragEnabled = armed;
            patch.showsDragHint = armed;
        }
    }
}

// 布局结果 → 面板排版（新建与原地更新共用同一份测量结果）。
- (InlinePanelLayout)inlinePanelLayoutFromPlacement:(FYInlinePlacement *)placement {
    InlinePanelLayout layout;
    layout.frame = placement.translationFrame;
    layout.labelFrame = placement.labelFrame;
    layout.font = placement.font;
    layout.cornerRadius = placement.cornerRadius;
    return layout;
}

// 该块是否是当前正在学习（已选中）的块。
// 必须按块身份（原文 + 行框）判断：同一段文字出现在别处时不能算选中。
// 选中判定：先用布局器匹配出来的**稳定身份**比，再退回本帧原始身份。
// 这样 OCR 框抖动 1px 时，面板身份与选中态一起保持稳定（稳定身份来自 FYInlineBlockMatcher，
// 仍然带真实行框与输入源/代次边界，不是纯文本身份）。
- (BOOL)inlineBlockID:(NSString *)stableBlockID isSelectedForItem:(OCRTextItem *)item {
    FYInlineBlockSnapshot *current = self.inlineBlockSnapshot;
    if (!current || current.blockID.length == 0) { return NO; }
    if (stableBlockID.length > 0 && [current.blockID isEqualToString:stableBlockID]) { return YES; }
    return [current.blockID isEqualToString:[self inlineBlockIdentityForItem:item]];
}

- (BOOL)inlineBlockIsSelectedForItem:(OCRTextItem *)item {
    // 任何调用点都要能识别「上一帧匹配出来的稳定身份」：先查本帧映射，再退回原始身份。
    NSString *raw = [self inlineBlockIdentityForItem:item];
    NSString *stable = self.inlineStableBlockIDs[raw];
    return [self inlineBlockID:stable isSelectedForItem:item];
}

// 译文段落归一化：OCR 的单行折行不该变成译文段落 ——
// 单个换行并回同一段，空行保留为真正的段落分隔。
static NSString *InlineNormalizeTranslationParagraphs(NSString *text) {
    if (text.length == 0) { return @""; }
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSString *> *paragraphs = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    for (NSString *raw in lines) {
        NSString *line = Trim(raw);
        if (line.length == 0) {
            if (current.length > 0) { [paragraphs addObject:[current copy]]; [current setString:@""]; }
            continue;
        }
        [current appendString:line];
    }
    if (current.length > 0) { [paragraphs addObject:[current copy]]; }
    return [paragraphs componentsJoinedByString:@"\n\n"];
}

// 长卡正文的字体与段落样式：测量与绘制必须用同一份，
// 否则换文后文档高度不更新（滚到底看不全），行距也不会真正生效。
- (NSParagraphStyle *)inlineLongCardBodyStyle {
    // 段落样式由布局引擎给出：测量与绘制必须完全同一份。
    return [self.inlineLayoutEngine longBodyParagraphStyle];
}
- (NSFont *)inlineLongCardBodyFont {
    // 长卡正文用正常阅读字重；层级靠标题（半粗）和内边距来体现，不靠把正文加粗。
    return [self.inlineLayoutEngine longBodyFont];
}
// 长卡正文的单行高度（含行距）：用来保证"至少三行可读正文"。
- (CGFloat)inlineLongCardBodyLineHeight {
    NSFont *font = [self inlineLongCardBodyFont];
    return ceil(font.ascender - font.descender + font.leading) + 8;
}
// 长卡最小可读高度：标题 + 内边距 + 三行正文。
- (CGFloat)inlineLongCardMinimumHeight {
    return 18 * 2 + (24 + 13) + [self inlineLongCardBodyLineHeight] * 3.0;
}
// 长卡正文视口高度（给定卡片高度）。
- (CGFloat)inlineLongCardBodyViewportForHeight:(CGFloat)cardHeight {
    return MAX(0, cardHeight - 18 * 2 - (24 + 13));
}

- (void)applyInlineLongCardBody:(NSString *)translation toLabel:(NSTextField *)label cardWidth:(CGFloat)cardWidth {
    [self applyInlineLongCardBody:translation toLabel:label cardWidth:cardWidth placement:nil];
}

- (void)applyInlineLongCardBody:(NSString *)translation
                        toLabel:(NSTextField *)label
                       cardWidth:(CGFloat)cardWidth
                       placement:(FYInlinePlacement *)placement {
    translation = InlineNormalizeTranslationParagraphs(translation);
    CGFloat padding = placement.panelPadding > 0 ? placement.panelPadding : 18;
    CGFloat textWidth = MAX((CGFloat)80, cardWidth - padding * 2);
    NSFont *font = placement.font ?: [self inlineLongCardBodyFont];
    NSParagraphStyle *style = placement.paragraphStyle ?: [self inlineLongCardBodyStyle];
    NSRect measured = [translation boundingRectWithSize:NSMakeSize(textWidth, CGFLOAT_MAX)
                                               options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                            attributes:@{NSFontAttributeName: font, NSParagraphStyleAttributeName: style}];
    label.font = font;
    label.attributedStringValue = [[NSAttributedString alloc] initWithString:translation ?: @""
                                                                  attributes:@{NSFontAttributeName: font,
                                                                               NSForegroundColorAttributeName: [self inlinePanelTextColor],
                                                                               NSParagraphStyleAttributeName: style}];
    label.frame = NSMakeRect(0, 0, textWidth, MAX((CGFloat)22, ceil(NSHeight(measured)) + 4));
}

// 长阅读卡内容：顶部小标题「中文译文」+ 完整译文（奶油近实底、深棕圆体、浅棕细边、轻柔阴影）。
- (NSView *)inlineLongCardContentForTranslation:(NSString *)translation size:(NSSize)size selected:(BOOL)selected compact:(BOOL)compact {
    return [self inlineLongCardContentForTranslation:translation size:size selected:selected compact:compact placement:nil];
}

- (NSView *)inlineLongCardContentForTranslation:(NSString *)translation
                                           size:(NSSize)size
                                       selected:(BOOL)selected
                                        compact:(BOOL)compact
                                      placement:(FYInlinePlacement *)placement {
    CGFloat cardWidth = MAX((CGFloat)160, size.width);
    CGFloat cardHeight = MAX((CGFloat)34, size.height);
    FYInlineLongCardView *card = [[FYInlineLongCardView alloc] initWithFrame:NSMakeRect(0, 0, cardWidth, cardHeight)];
    card.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    card.showsSelectedBadge = selected;
    card.compactEntry = compact;
    [self applyInlineChromeToContent:card cornerRadius:compact ? 8 : 12];

    if (compact) {
        // 空间连三行正文都放不下时的**紧凑入口**：明确说明可展开，点击打开完整阅读卡。
        card.toolTip = @"点击展开完整译文";
        NSTextField *entry = [self label:@"中文译文 · 点击展开" font:[self inlinePanelFontOfSize:13 weight:NSFontWeightSemibold] color:[self inlinePanelTitleColor]];
        entry.alignment = NSTextAlignmentCenter;
        entry.frame = NSMakeRect(8, MAX((CGFloat)4, (cardHeight - 20) / 2.0), MAX((CGFloat)60, cardWidth - 16), 20);
        [card addSubview:entry];
        return card;
    }
    card.toolTip = @"点击查看原文和语法";

    // 内边距与标题带由布局引擎给出：与测量用的是同一组常量，避免“测出来”和“画出来”不一致。
    CGFloat padding = placement.panelPadding > 0 ? placement.panelPadding : 18;
    CGFloat titleBand = 24;
    // 注意：FYInlineLongCardView 是 flipped（y=0 在顶部），所以标题在 padding 处、正文在标题下方。
    // 顶部小标题：未选中时不显示「已选中」，避免把预览状态写死。
    NSTextField *title = [self label:@"中文译文" font:[self inlinePanelFontOfSize:14 weight:NSFontWeightSemibold] color:[self inlinePanelTitleColor]];
    title.frame = NSMakeRect(padding, padding + 2, cardWidth - padding * 2 - 70, titleBand);
    [card addSubview:title];
    if (selected) {
        NSView *badgeBox = [[NSView alloc] initWithFrame:NSMakeRect(cardWidth - padding - 72, padding, 72, titleBand + 2)];
        badgeBox.wantsLayer = YES;
        badgeBox.layer.backgroundColor = FYAdventureColor(@"mint").CGColor;
        badgeBox.layer.cornerRadius = (titleBand + 2) / 2.0;
        NSTextField *badge = [self label:@"已选中" font:[self inlinePanelFontOfSize:13] color:[self inlinePanelTextColor]];
        badge.alignment = NSTextAlignmentCenter;
        badge.frame = NSMakeRect(0, 4, 72, titleBand - 6);
        [badgeBox addSubview:badge];
        [card addSubview:badgeBox];
    }
    // 标题下的浅棕细分隔线（与预览一致），把标题层级和正文分开。
    NSView *rule = [[NSView alloc] initWithFrame:NSMakeRect(padding, padding + titleBand + 2, cardWidth - padding * 2, 1)];
    rule.wantsLayer = YES;
    rule.layer.backgroundColor = [FYAdventureColor(@"rim") colorWithAlphaComponent:0.95].CGColor;
    [card addSubview:rule];

    // 正文：清晰内边距 + 舒适行距；超长时在卡内滚动。
    CGFloat textWidth = MAX((CGFloat)80, cardWidth - padding * 2);
    CGFloat bodyTop = placement.titleBandHeight > 0 ? padding + placement.titleBandHeight : padding + titleBand + 13;
    CGFloat bodyHeight = MAX((CGFloat)24, cardHeight - bodyTop - padding);
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, textWidth, 22)];
    [self applyInlineLongCardBody:translation toLabel:label cardWidth:cardWidth placement:placement];
    label.selectable = NO;
    label.editable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.maximumNumberOfLines = 0;
    label.usesSingleLineMode = NO;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.cell.wraps = YES;
    label.cell.scrollable = NO;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(padding, bodyTop, textWidth, bodyHeight)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.scrollerStyle = NSScrollerStyleOverlay;
    scroll.borderType = NSNoBorder;
    scroll.documentView = label;
    [card addSubview:scroll];
    return card;
}

// 显式给定卡框时补齐绘制参数（测试与「展开完整阅读卡」用）：
// 字体/段落样式/内边距仍取自布局引擎，测量口径与 ShowInlineTranslations 完全一致。
- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(NSRect)frame translation:(NSString *)translation {
    FYInlinePlacement *placement = [FYInlinePlacement new];
    placement.mode = FYInlineDisplayModeScrollingCard;
    placement.panelPadding = 18;
    placement.titleBandHeight = 24 + 13;
    placement.cornerRadius = 12;
    placement.font = [self.inlineLayoutEngine longBodyFont];
    placement.paragraphStyle = [self.inlineLayoutEngine longBodyParagraphStyle];
    placement.translation = translation ?: @"";
    placement.translationFrame = frame;
    placement.measuredContentHeight = [self.inlineLayoutEngine measuredBodyHeight:translation placement:placement width:NSWidth(frame)];
    placement.bodyViewportHeight = [self inlineLongCardBodyViewportForHeight:NSHeight(frame)];
    placement.bodyViewportFrame = NSMakeRect(18, 18 + 37, MAX((CGFloat)80, NSWidth(frame) - 36), placement.bodyViewportHeight);
    placement.scrollable = placement.measuredContentHeight > placement.bodyViewportHeight + 0.5;
    return placement;
}

- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame {
    return [self inlineLongPanelForTranslation:translation item:item frame:frame
                                     placement:[self inlinePlacementForLongCardFrame:frame translation:translation]];
}

- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame placement:(FYInlinePlacement *)placement {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.backgroundColor = NSColor.clearColor;
    panel.opaque = NO;
    panel.hasShadow = YES;
    panel.ignoresMouseEvents = NO;
    panel.level = NSStatusWindowLevel;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    panel.contentView = [self inlineLongCardContentForTranslation:translation size:frame.size
                                                        selected:[self inlineBlockID:placement.blockID isSelectedForItem:item]
                                                         compact:placement.compactEntry
                                                       placement:placement];
    [self wireInlineLongCardPanel:panel item:item translation:translation frame:frame stableBlockID:placement.blockID];
    return panel;
}

// 兼容入口（独立验收测试仍在用）：不带 compact 的调用按完整长卡处理。
- (void)updateInlineLongCard:(NSPanel *)panel translation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame {
    [self updateInlineLongCard:panel translation:translation item:item frame:frame compact:NO placement:nil];
}

- (void)updateInlineLongCard:(NSPanel *)panel translation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame compact:(BOOL)compact {
    [self updateInlineLongCard:panel translation:translation item:item frame:frame compact:compact placement:nil];
}

- (void)updateInlineLongCard:(NSPanel *)panel
                 translation:(NSString *)translation
                        item:(OCRTextItem *)item
                       frame:(NSRect)frame
                     compact:(BOOL)compact
                   placement:(FYInlinePlacement *)placement {
    if (!placement) { placement = [self inlinePlacementForLongCardFrame:frame translation:translation]; }
    if (!NSEqualRects(panel.frame, frame)) { [panel setFrame:frame display:NO]; }
    NSView *existing = panel.contentView;
    BOOL selected = [self inlineBlockID:placement.blockID isSelectedForItem:item];
    if ([existing isKindOfClass:FYInlineLongCardView.class] && NSEqualSizes(existing.frame.size, frame.size) &&
        [(FYInlineLongCardView *)existing showsSelectedBadge] == selected &&
        [(FYInlineLongCardView *)existing compactEntry] == compact) {
        // 尺寸与选中态都没变：只换正文，保留滚动视图与点击目标，避免重建导致的闪烁与事件丢失。
        NSScrollView *scroll = nil;
        for (NSView *child in existing.subviews) { if ([child isKindOfClass:NSScrollView.class]) { scroll = (NSScrollView *)child; break; } }
        NSView *document = scroll.documentView;
        if ([document isKindOfClass:NSTextField.class]) {
            NSTextField *label = (NSTextField *)document;
            // 用同一份字体/段落样式重新测量：卡片尺寸没变但文章更长时，文档必须跟着长高。
            [self applyInlineLongCardBody:translation toLabel:label cardWidth:NSWidth(scroll.frame) + 36 placement:placement];
            NSPoint origin = scroll.contentView.bounds.origin;
            CGFloat maxY = MAX((CGFloat)0, NSHeight(label.frame) - NSHeight(scroll.contentView.bounds));
            if (origin.y > maxY) {
                origin.y = maxY;
                [scroll.contentView scrollToPoint:origin];
                [scroll reflectScrolledClipView:scroll.contentView];
            }
        }
    } else {
        panel.contentView = [self inlineLongCardContentForTranslation:translation size:frame.size selected:selected compact:compact placement:placement];
    }
    [self wireInlineLongCardPanel:panel item:item translation:translation frame:frame stableBlockID:placement.blockID];
    [panel displayIfNeeded];
}

// 由当前块生成不可变学习快照（含原始行框、内容身份与采集代次）。
// 块身份：原文 + 真实行框（跨帧稳定、不用随机 UUID）。
// 相同文字出现在不同位置时身份不同 —— 不能用纯文本当身份。
- (NSString *)inlineBlockIdentityForItem:(OCRTextItem *)item {
    NSArray<NSValue *> *boxes = item.lineBoxes.count ? item.lineBoxes : (item.boundingBox.size.width > 0 ? @[[NSValue valueWithRect:item.boundingBox]] : @[]);
    NSMutableString *key = [NSMutableString stringWithString:NormalizeForComparison(item.text ?: @"")];
    for (NSValue *value in boxes) {
        CGRect r = value.rectValue;
        [key appendFormat:@"|%.3f,%.3f,%.3f,%.3f", r.origin.x, r.origin.y, r.size.width, r.size.height];
    }
    return [key copy];
}

- (FYInlineBlockSnapshot *)inlineSnapshotForItem:(OCRTextItem *)item translation:(NSString *)translation {
    return [self inlineSnapshotForItem:item translation:translation stableBlockID:nil];
}

// stableBlockID：布局器跨帧匹配出来的块身份。点击/选中/学习快照都用它，
// 保证 OCR 框轻微抖动后面板、选中态与学习卡指向同一块；为空时退回本帧原始身份。
- (FYInlineBlockSnapshot *)inlineSnapshotForItem:(OCRTextItem *)item
                                     translation:(NSString *)translation
                                   stableBlockID:(NSString *)stableBlockID {
    FYInlineBlockSnapshot *snapshot = [FYInlineBlockSnapshot new];
    snapshot.sourceText = [item.text copy] ?: @"";
    snapshot.translation = [translation copy] ?: @"";
    NSArray<NSValue *> *boxes = item.lineBoxes.count ? item.lineBoxes : (item.boundingBox.size.width > 0 ? @[[NSValue valueWithRect:item.boundingBox]] : @[]);
    snapshot.lineBoxes = boxes;
    snapshot.inputSource = [self captureCardInputEnabled] ? 1 : 0;
    snapshot.inputEpoch = self.captureCardInput.sessionEpoch;
    snapshot.blockID = stableBlockID.length > 0 ? [stableBlockID copy] : [self inlineBlockIdentityForItem:item];
    return snapshot;
}

// 由布局器的块（而非 OCRTextItem）生成快照：集中查看列表用它保留每块的原文、译文与稳定身份。
- (FYInlineBlockSnapshot *)inlineSnapshotForBlock:(FYInlineTextBlock *)block
                                      translation:(NSString *)translation
                                    stableBlockID:(NSString *)stableBlockID {
    FYInlineBlockSnapshot *snapshot = [FYInlineBlockSnapshot new];
    snapshot.sourceText = [block.text copy] ?: @"";
    snapshot.translation = [translation copy] ?: @"";
    snapshot.lineBoxes = block.lineBoxes.count > 0 ? block.lineBoxes : @[];
    snapshot.inputSource = [self captureCardInputEnabled] ? 1 : 0;
    snapshot.inputEpoch = self.captureCardInput.sessionEpoch;
    snapshot.blockID = stableBlockID.length > 0 ? [stableBlockID copy]
        : [FYInlineBlockMatcher blockIDForText:block.text lineBoxes:block.lineBoxes];
    return snapshot;
}

- (void)wireInlineLongCardPanel:(NSPanel *)panel item:(OCRTextItem *)item translation:(NSString *)translation frame:(NSRect)frame {
    [self wireInlineLongCardPanel:panel item:item translation:translation frame:frame stableBlockID:nil];
}

- (void)wireInlineLongCardPanel:(NSPanel *)panel
                           item:(OCRTextItem *)item
                    translation:(NSString *)translation
                          frame:(NSRect)frame
                  stableBlockID:(NSString *)stableBlockID {
    FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
    if (![card isKindOfClass:FYInlineLongCardView.class]) { return; }
    __weak typeof(self) weakSelf = self;
    __weak FYInlineLongCardView *weakCard = card;
    FYInlineBlockSnapshot *snapshot = [self inlineSnapshotForItem:item translation:translation stableBlockID:stableBlockID];
    card.stableBlockID = stableBlockID;
    card.onClick = ^{
        // 用 weakCard 读状态：block 被 card.onClick 持有，捕获 card 会成环（关闭面板也不释放）。
        if (weakCard.compactEntry) {
            [weakSelf openFullInlineReadingCardForItem:item translation:translation stableBlockID:stableBlockID];
            return;
        }
        [weakSelf openInlineLearningWithSnapshot:snapshot];
    };
    card.onHover = ^(BOOL inside) {
        weakCard.layer.borderWidth = inside ? 2 : 1;
        weakCard.toolTip = inside ? @"点击查看原文和语法" : nil;
    };
}

// 紧凑入口 → 打开完整阅读卡（窗口内的浮层，卡内滚动，点击进入学习）。
- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item translation:(NSString *)translation {
    [self openFullInlineReadingCardForItem:item translation:translation stableBlockID:nil];
}

- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item
                             translation:(NSString *)translation
                           stableBlockID:(NSString *)stableBlockID {
    NSRect placement = NSZeroRect;
    if (![self inlinePlacementRect:&placement reason:NULL]) { return; }
    [self closeExpandedInlineReadingCard];
    CGFloat width = MIN((CGFloat)560, MAX((CGFloat)320, NSWidth(placement) * 0.5));
    CGFloat height = MIN((CGFloat)420, MAX((CGFloat)240, NSHeight(placement) * 0.6));
    CGFloat x = MIN(MAX(NSMidX(placement) - width / 2.0, NSMinX(placement) + 12), NSMaxX(placement) - width - 12);
    CGFloat y = MIN(MAX(NSMidY(placement) - height / 2.0, NSMinY(placement) + 12), NSMaxY(placement) - height - 12);
    FYInlinePlacement *cardPlacement = [self inlinePlacementForLongCardFrame:NSIntegralRect(NSMakeRect(x, y, width, height))
                                                                 translation:translation];
    if (stableBlockID.length > 0) { cardPlacement.blockID = stableBlockID; }
    NSPanel *panel = [self inlineLongPanelForTranslation:translation item:item
                                                    frame:cardPlacement.translationFrame
                                                placement:cardPlacement];
    if (!panel) { return; }
    self.inlineExpandedReadingPanel = panel;
    [panel orderFrontRegardless];
    __weak typeof(self) weakSelf = self;
    if (!self.inlineExpandedReadingKeyMonitor) {
        self.inlineExpandedReadingKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
            if (event.keyCode != 53) { return event; }
            [weakSelf closeExpandedInlineReadingCard];
            return nil;
        }];
    }
}

- (void)closeExpandedInlineReadingCard {
    if (self.inlineExpandedReadingKeyMonitor) {
        [NSEvent removeMonitor:self.inlineExpandedReadingKeyMonitor];
        self.inlineExpandedReadingKeyMonitor = nil;
    }
    [self.inlineExpandedReadingPanel close];
    self.inlineExpandedReadingPanel = nil;
}

#pragma mark - 长卡片 → 语法学习 → AI 返回

// 「点长卡片进入学习」的文字入口（保留给测试与外部调用）：没有行框时也能工作。
- (void)openInlineLearningForBlockText:(NSString *)source translation:(NSString *)translation {
    NSString *src = Trim(source);
    if (src.length < 2) { return; }
    FYInlineBlockSnapshot *snapshot = [FYInlineBlockSnapshot new];
    snapshot.sourceText = src;
    snapshot.translation = translation ?: @"";
    // 没有原始行框时，至少按真实分行保留行结构（几何为按行的高度的近似，不是伪造内容）。
    NSMutableArray<NSValue *> *lineBoxes = [NSMutableArray array];
    NSArray<NSString *> *lines = [src componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSUInteger kept = 0;
    for (NSString *line in lines) {
        if (Trim(line).length == 0) { continue; }
        [lineBoxes addObject:[NSValue valueWithRect:CGRectMake(0, MAX(0.0, 0.9 - kept * 0.05), 1, 0.05)]];
        kept += 1;
    }
    snapshot.lineBoxes = lineBoxes;
    snapshot.inputSource = [self captureCardInputEnabled] ? 1 : 0;
    snapshot.inputEpoch = self.captureCardInput.sessionEpoch;
    snapshot.blockID = NormalizeForComparison(src);
    [self openInlineLearningWithSnapshot:snapshot];
}

// 点长卡片进入学习：用不可变块快照打开学习卡；换块时建立独立上下文。
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot {
    if (!snapshot || snapshot.sourceText.length < 2) { return; }
    NSString *src = Trim(snapshot.sourceText);
    NSString *translation = snapshot.translation ?: @"";
    BOOL sameBlock = self.inlineBlockSnapshot != nil && [self.inlineBlockSnapshot.blockID isEqualToString:snapshot.blockID];
    // 记录 Snapshot 类型句子以获得真实 ID/version 供「收藏语法／收藏这段」绑定；
    // 同一界面文字在历史中折叠，不写进对白。
    if (snapshot.sentenceID.length == 0) {
        FYRequestIdentity *identity = [self.learningCoordinator recordText:src kind:FYSentenceKindSnapshot];
        snapshot.sentenceID = identity.sentenceID ?: @"";
        snapshot.version = identity.version;
    }
    snapshot.sourceText = src;
    snapshot.translation = translation;
    self.inlineBlockSnapshot = snapshot;
    self.inlineReturnSnapshot = snapshot;
    self.inlineReturnSourceText = src;
    self.quickSentenceIsInlineBlock = YES;

    self.quickSentenceRequested = YES;
    self.quickSentenceGeneration += 1;
    self.studyChatOverlayRequested = NO;
    [self.studyChatPanel orderOut:nil];
    self.quickSentenceSource = src;
    self.quickSentenceTranslation = translation;
    self.quickSentenceID = snapshot.sentenceID;
    self.quickSentenceVersion = snapshot.version;
    if (!sameBlock) {
        // 换成另一块：清掉上一块的分析、选中项、聊天与草稿，避免串块。
        [self cancelQuickSentenceAnalysis];
        self.quickSentenceAnalysis = nil;
        self.quickSentenceAnalysisError = nil;
        self.quickSelectedGrammarIndex = 0;
        self.quickSentenceAnalysisSource = @"";
        self.quickSentenceAnalysisTranslation = @"";
        [self bindInlineStudyChatToSource:src translation:translation];
        self.quickSentenceScrollOffset = 0;
    }
    BOOL first = self.quickSentencePanel == nil;
    [self renderQuickSentence];
    [self refreshSavedSentences];
    if (first) { [self.quickSentencePanel center]; }
    if (!self.selectingCaptureRegion && [self translationTargetIsForeground]) {
        [self.quickSentencePanel makeKeyWindow];
    }
    if (!self.quickSentenceAnalysis && !self.quickSentenceAnalyzing) { [self analyzeQuickSentence:nil]; }
}

// 换块时把独立 AI 会话切到新块：清空上一块的消息与未发送草稿，绑定新块引用。
- (void)bindInlineStudyChatToSource:(NSString *)source translation:(NSString *)translation {
    [self ensureStudyChatSession];
    [self.studyChatSession startNewConversationWithSource:source translation:translation];
    [self.mainStudyChatView setDraftText:@""];
    [self.overlayStudyChatView setDraftText:@""];
    [self refreshStudyChatViews];
}

// 「‹ 返回语法」：从独立 AI 恢复同一快照的语法卡；已完成分析不重跑，滚动位置恢复。
- (void)returnFromStudyChatToInlineLearning:(id)sender {
    FYInlineBlockSnapshot *snapshot = self.inlineReturnSnapshot;
    if (!snapshot || snapshot.sourceText.length == 0) { return; }
    self.studyChatOverlayRequested = NO;
    [self.studyChatPanel orderOut:nil];
    self.quickSentenceRequested = YES;
    BOOL sameBlock = self.inlineBlockSnapshot != nil && [self.inlineBlockSnapshot.blockID isEqualToString:snapshot.blockID] &&
                     [snapshot.sourceText isEqualToString:self.quickSentenceAnalysisSource];
    self.quickSentenceSource = snapshot.sourceText;
    self.quickSentenceTranslation = snapshot.translation ?: @"";
    self.quickSentenceID = snapshot.sentenceID ?: @"";
    self.quickSentenceVersion = snapshot.version;
    if (!sameBlock) {
        self.quickSentenceAnalysis = nil;
        self.quickSentenceAnalysisError = nil;
        self.quickSelectedGrammarIndex = 0;
    }
    [self renderQuickSentence];
    [self restoreQuickSentenceScrollPosition];
    if (!self.selectingCaptureRegion && [self translationTargetIsForeground]) {
        [self.quickSentencePanel makeKeyWindow];
    }
    if (!self.quickSentenceAnalysis && !self.quickSentenceAnalyzing) {
        [self analyzeQuickSentence:nil];
    }
}

- (NSScrollView *)quickSentenceScrollView {
    if (!self.quickSentencePanel) { return nil; }
    for (NSView *view in self.quickSentencePanel.contentView.subviews) {
        if ([view isKindOfClass:NSScrollView.class]) { return (NSScrollView *)view; }
    }
    return nil;
}

- (void)captureQuickSentenceScrollPosition {
    NSScrollView *scroll = [self quickSentenceScrollView];
    if (!scroll) { return; }
    self.quickSentenceScrollOffset = scroll.contentView.bounds.origin.y;
}

- (void)restoreQuickSentenceScrollPosition {
    NSScrollView *scroll = [self quickSentenceScrollView];
    if (!scroll) { return; }
    [scroll.documentView layoutSubtreeIfNeeded];
    CGFloat maxY = MAX((CGFloat)0, NSHeight(scroll.documentView.frame) - NSHeight(scroll.contentView.bounds));
    CGFloat y = MIN(MAX((CGFloat)0, self.quickSentenceScrollOffset), maxY);
    [scroll.contentView scrollToPoint:NSMakePoint(0, y)];
    [scroll reflectScrolledClipView:scroll.contentView];
}

- (void)updateInlineReturnButtonVisibility {
    BOOL hasReturn = self.inlineReturnSnapshot != nil && self.inlineReturnSnapshot.sourceText.length > 0;
    // 返回入口在聊天组件自己的导航行里；主窗口 AI 不显示该入口。
    [self.overlayStudyChatView setReturnVisible:hasReturn];
    self.inlineReturnButton = hasReturn ? self.overlayStudyChatView.returnButton : nil;
}

- (NSRect)appKitFrameForOCRItem:(OCRTextItem *)item inWindowFrame:(NSRect)windowFrame {
    CGRect box = item.boundingBox;
    CGFloat x = NSMinX(windowFrame) + box.origin.x * NSWidth(windowFrame);
    CGFloat y = NSMinY(windowFrame) + box.origin.y * NSHeight(windowFrame);
    CGFloat width = box.size.width * NSWidth(windowFrame);
    CGFloat height = box.size.height * NSHeight(windowFrame);
    return NSIntegralRect(NSMakeRect(x, y, width, height));
}

- (NSInteger)captionThemeIndex {
    NSInteger index = self.captionThemeControl ? self.captionThemeControl.selectedSegment : 3;
    if (index < 0 || index > 3) { index = 3; }
    return index;
}

- (NSColor *)captionBackgroundColorWithAlpha:(CGFloat)alpha {
    alpha = MIN(MAX(alpha, 0), 0.98);
    switch ([self captionThemeIndex]) {
        case 3: return [FYAdventureColor(@"cream") colorWithAlphaComponent:alpha];
        case 1:
            return [NSColor colorWithWhite:1 alpha:alpha];
        case 2:
            return [NSColor colorWithCalibratedRed:1.00 green:0.86 blue:0.93 alpha:alpha];
        default:
            return [NSColor colorWithWhite:0 alpha:alpha];
    }
}

- (NSColor *)captionTextColor {
    switch ([self captionThemeIndex]) {
        case 3: return FYAdventureColor(@"ink");
        case 1:
            return [NSColor colorWithWhite:0.08 alpha:1];
        case 2:
            return [NSColor colorWithCalibratedRed:0.22 green:0.10 blue:0.18 alpha:1];
        default:
            return NSColor.whiteColor;
    }
}

- (NSColor *)captionSecondaryTextColor {
    switch ([self captionThemeIndex]) {
        case 3: return FYAdventureColor(@"quiet");
        case 1:
            return [NSColor colorWithWhite:0.12 alpha:0.62];
        case 2:
            return [NSColor colorWithCalibratedRed:0.34 green:0.16 blue:0.27 alpha:0.70];
        default:
            return [NSColor colorWithWhite:1 alpha:0.72];
    }
}

- (NSColor *)captionBorderColor {
    switch ([self captionThemeIndex]) {
        case 3: return FYAdventureColor(@"line");
        case 1:
            return [NSColor colorWithWhite:0 alpha:0.14];
        case 2:
            return [NSColor colorWithCalibratedRed:0.88 green:0.28 blue:0.52 alpha:0.32];
        default:
            return [NSColor colorWithWhite:1 alpha:0.18];
    }
}

#pragma mark - 贴译主题（与字幕外观设置完全分开）

// 贴译（原位短贴片 + 长阅读卡）使用固定的「奶油棕花境」主题。
// 用户改字幕配色 / 主题 / 透明度时，贴译不能再跟着变成灰黑底白字。
// 分组器：几何判定在独立组件里，这里只注入“按钮词”这一项项目内约定。
- (FYInlineGrouper *)inlineGrouper {
    if (!_inlineGrouper) {
        FYInlineGrouper *grouper = [FYInlineGrouper defaultGrouper];
        __weak typeof(self) weakSelf = self;
        grouper.shortLabelDetector = ^BOOL(NSString *normalizedText) {
            return [weakSelf isButtonLikeInlineText:normalizedText];
        };
        _inlineGrouper = grouper;
    }
    return _inlineGrouper;
}

// 布局引擎：字体由主题注入，保证“测量与绘制共用同一份字体+段落样式”。
- (FYInlineLayoutEngine *)inlineLayoutEngine {
    if (!_inlineLayoutEngine) {
        FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
        engine.fontProvider = ^NSFont *(CGFloat size, NSFontWeight weight) {
            return FYUIFont(size, weight);
        };
        _inlineLayoutEngine = engine;
    }
    return _inlineLayoutEngine;
}

// 贴译背景不透明度：直接跟随现有「背景透明度」设置（与字幕同一数值），
// 不新增第二套透明度设置，也不重置用户已有偏好。文字颜色始终完全不透明。
- (CGFloat)inlinePanelFillAlpha {
    NSSlider *slider = self.captionOpacitySlider;
    if (!slider) { return 0.58; }   // 与设置里的默认值一致（测试/极早期调用）
    return MIN(MAX((CGFloat)slider.doubleValue, (CGFloat)0), (CGFloat)1);
}

- (NSColor *)inlinePanelFillColor {
    return [FYAdventureColor(@"cream") colorWithAlphaComponent:[self inlinePanelFillAlpha]];
}

// 透明度设置变化后，已经显示出来的贴译立即更新：只改背景，不动文字与位置。
- (void)refreshInlinePanelAppearance {
    NSColor *fill = [self inlinePanelFillColor];
    NSMutableArray<NSPanel *> *panels = [self.inlineTranslationPanels mutableCopy] ?: [NSMutableArray array];
    [panels addObjectsFromArray:self.inlineLongCardPanels ?: @[]];
    if (self.inlineExpandedReadingPanel) { [panels addObject:self.inlineExpandedReadingPanel]; }
    for (NSPanel *panel in panels) {
        NSView *content = panel.contentView;
        if (content.layer) { content.layer.backgroundColor = fill.CGColor; }
    }
}
- (NSColor *)inlinePanelBorderColor {
    return FYAdventureColor(@"line");
}
- (NSColor *)inlinePanelTextColor {
    return FYAdventureColor(@"ink");
}
- (NSColor *)inlinePanelTitleColor {
    return FYAdventureColor(@"quiet");
}
// 中文使用项目规定的华文圆体（短贴片正常字重；长卡正文与预览一致用粗圆体）。
- (NSFont *)inlinePanelFontOfSize:(CGFloat)size {
    return FYUIFont(size, NSFontWeightRegular);
}
- (NSFont *)inlinePanelFontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
    return FYUIFont(size, weight);
}

- (InlinePanelLayout)inlinePanelLayoutForTranslation:(NSString *)translation
                                          sourceText:(NSString *)sourceText
                                         sourceFrame:(NSRect)sourceFrame
                                         windowFrame:(NSRect)windowFrame {
    return [self inlinePanelLayoutForTranslation:translation
                                      sourceText:sourceText
                                     sourceFrame:sourceFrame
                                     windowFrame:windowFrame
                                   placedFrames:nil
                                   hugTextWidth:NO];
}

- (InlinePanelLayout)inlinePanelLayoutForTranslation:(NSString *)translation
                                          sourceText:(NSString *)sourceText
                                         sourceFrame:(NSRect)sourceFrame
                                         windowFrame:(NSRect)windowFrame
                                       placedFrames:(NSArray<NSValue *> *)placedFrames
                                       hugTextWidth:(BOOL)hugTextWidth {
    // 单块短贴片也走同一个布局引擎：同一份字体/段落样式、同一套候选顺序与边界判定，
    // 不再维护第二套“到处找空位”的算法。
    // placedFrames / hugTextWidth 保留签名兼容；本帧面板之间的冲突由
    // showInlineTranslations: 的统一安排负责（单块调用没有其它障碍物）。
    (void)placedFrames;
    (void)hugTextWidth;
    FYInlineTextBlock *block = [FYInlineTextBlock new];
    block.text = sourceText ?: @"";
    block.kind = FYInlineBlockKindShort;
    block.lineBoxes = @[[NSValue valueWithRect:CGRectMake(0, 0, 1, 1)]];
    block.lineTexts = @[block.text ?: @""];
    block.boundingBox = CGRectMake(0, 0, 1, 1);
    block.blockID = [FYInlineBlockMatcher blockIDForText:block.text lineBoxes:block.lineBoxes];
    FYInlineLayoutRequest *request = [FYInlineLayoutRequest requestWithBlock:block
                                                                translation:translation
                                                                sourceFrame:sourceFrame];
    FYInlineLayoutResult *result = [self.inlineLayoutEngine layoutRequests:@[request]
                                                                  viewport:windowFrame
                                                                  previous:nil];
    FYInlinePlacement *placement = result.placements.firstObject;
    if (placement && placement.mode != FYInlineDisplayModeUnplaceable) {
        return [self inlinePanelLayoutFromPlacement:placement];
    }
    // 极端情况（画面比贴片还小）：退回最小可用排版，不返回空帧。
    InlinePanelLayout layout;
    CGFloat width = MAX((CGFloat)80, MIN(NSWidth(windowFrame) - 16, 240));
    CGFloat height = 28;
    layout.font = [self.inlineLayoutEngine shortBodyFontForCover:NO];
    layout.cornerRadius = 7;
    layout.frame = NSMakeRect(NSMinX(sourceFrame), NSMinY(sourceFrame), width, height);
    layout.labelFrame = NSMakeRect(10, 5, MAX((CGFloat)20, width - 20), MAX((CGFloat)18, height - 10));
    return layout;
}

- (NSAttributedString *)inlinePanelAttributedText:(NSString *)translation font:(NSFont *)font {
    NSParagraphStyle *paragraphStyle = [self.inlineLayoutEngine shortParagraphStyle];
    return [[NSAttributedString alloc] initWithString:translation
                                           attributes:@{NSFontAttributeName: font,
                                                        NSForegroundColorAttributeName: [self inlinePanelTextColor],
                                                        NSParagraphStyleAttributeName: paragraphStyle}];
}

// 贴译外观：奶油近实底 + 浅棕细边 + 平滑圆角 + 轻柔阴影（与字幕主题无关）。
- (void)applyInlineChromeToContent:(NSView *)content cornerRadius:(CGFloat)cornerRadius {
    content.wantsLayer = YES;
    content.layer.backgroundColor = [self inlinePanelFillColor].CGColor;
    content.layer.cornerRadius = cornerRadius;
    content.layer.borderWidth = 1.5;
    content.layer.borderColor = [self inlinePanelBorderColor].CGColor;
    content.layer.shadowColor = FYAdventureColor(@"line").CGColor;
    content.layer.shadowOpacity = 0.32;
    content.layer.shadowRadius = 7;
    content.layer.shadowOffset = CGSizeMake(0, -2);
    content.layer.masksToBounds = NO;
}

- (NSPanel *)inlinePanelForTranslation:(NSString *)translation sourceText:(NSString *)sourceText sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame {
    return [self inlinePanelForTranslation:translation
                                sourceText:sourceText
                               sourceFrame:sourceFrame
                               windowFrame:windowFrame
                                    layout:[self inlinePanelLayoutForTranslation:translation
                                                                      sourceText:sourceText
                                                                     sourceFrame:sourceFrame
                                                                     windowFrame:windowFrame]];
}

- (NSPanel *)inlinePanelForTranslation:(NSString *)translation sourceText:(NSString *)sourceText sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame layout:(InlinePanelLayout)layout {

    NSPanel *panel = [[NSPanel alloc] initWithContentRect:layout.frame
                                                styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.backgroundColor = NSColor.clearColor;
    panel.opaque = NO;
    panel.hasShadow = YES;
    panel.ignoresMouseEvents = YES;
    panel.level = NSStatusWindowLevel;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;

    // 短贴片用专门的内容视图：平时穿透，按住 Option 时可拖动并给出反馈。
    FYInlinePatchView *content = [[FYInlinePatchView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(layout.frame), NSHeight(layout.frame))];
    content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    content.wantsLayer = YES;
    [self applyInlineChromeToContent:content cornerRadius:layout.cornerRadius];

    NSTextField *label = [self label:translation font:layout.font color:[self inlinePanelTextColor]];
    label.frame = layout.labelFrame;
    label.attributedStringValue = [self inlinePanelAttributedText:translation font:layout.font];
    label.maximumNumberOfLines = 0;
    label.lineBreakMode = NSLineBreakByCharWrapping;
    label.usesSingleLineMode = NO;
    label.cell.wraps = YES;
    label.cell.scrollable = NO;
    [content addSubview:label];

    panel.contentView = content;
    return panel;
}

#pragma mark - Capture and OCR

- (BOOL)hasScreenAccess {
    return CGPreflightScreenCaptureAccess();
}

- (BOOL)hasUsableScreenCaptureAccess {
    if ([self hasScreenAccess]) {
        return YES;
    }

    return [self canCaptureSelectedWindowOnce];
}

- (BOOL)canCaptureSelectedWindowOnce {
    uint32_t windowID = [self selectedWindowID];
    if (!windowID) { return NO; }

    CGImageRef image = [self copyFullCapturedImageForWindow:windowID];
    if (!image) { return NO; }

    BOOL usable = CGImageGetWidth(image) > 1 && CGImageGetHeight(image) > 1;
    if (usable) { [self updatePreviewFromImage:image generation:self.translationGeneration]; }
    CGImageRelease(image);
    return usable;
}

- (void)handleMissingScreenAccessForStart {
    [self showPreviewUnavailable:@"无法预览：请检查屏幕录制权限"];
    if (self.screenAccessRequestedDuringSession) {
        [self setStatus:@"权限还没对当前进程生效；请点“重启 App”"];
        return;
    }

    [self setStatus:@"需要屏幕录制权限"];
    [self requestScreenAccess:nil];
}

- (NSURL *)preferredBundleURLForRelaunch {
    NSString *installedPath = [@"~/Applications/译芽.app" stringByExpandingTildeInPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:installedPath]) {
        return [NSURL fileURLWithPath:installedPath];
    }

    NSURL *currentBundleURL = NSBundle.mainBundle.bundleURL;
    return [currentBundleURL.pathExtension.lowercaseString isEqualToString:@"app"] ? currentBundleURL : nil;
}

- (uint32_t)selectedWindowID {
    NSNumber *number = self.windowPopup.selectedItem.representedObject;
    return number.unsignedIntValue;
}

- (WindowItem *)selectedWindowItem {
    uint32_t windowID = [self selectedWindowID];
    for (WindowItem *item in self.windows) {
        if (item.windowID == windowID) {
            return item;
        }
    }
    return nil;
}

- (NSScreen *)screenForWindowItem:(WindowItem *)item {
    NSRect windowFrame = [self appKitFrameForWindowItem:item];
    NSScreen *bestScreen = NSScreen.mainScreen;
    CGFloat bestArea = 0;

    for (NSScreen *screen in NSScreen.screens) {
        NSRect intersection = NSIntersectionRect(screen.frame, windowFrame);
        CGFloat area = NSWidth(intersection) * NSHeight(intersection);
        if (area > bestArea) {
            bestArea = area;
            bestScreen = screen;
        }
    }

    return bestScreen;
}

- (NSRect)appKitFrameForWindowItem:(WindowItem *)item {
    CGRect bounds = item.bounds;
    NSScreen *screen = NSScreen.mainScreen;
    CGFloat y = NSMaxY(screen.frame) - bounds.origin.y - bounds.size.height;

    return NSMakeRect(bounds.origin.x, y, bounds.size.width, bounds.size.height);
}

#pragma mark - 采集卡坐标映射

#pragma mark - 采集卡画面区域：按内容自动定位

// CGImage → 小尺寸灰度网格。用于「按内容比对」，不是按宽高比猜。
static double *FYGrayGridFromImage(CGImageRef image, size_t gridW, size_t gridH) {
    if (!image || gridW < 4 || gridH < 4) { return NULL; }
    uint8_t *bytes = calloc(gridW * gridH, 1);
    if (!bytes) { return NULL; }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(bytes, gridW, gridH, 8, gridW, space, kCGImageAlphaNone);
    CGColorSpaceRelease(space);
    if (!ctx) { free(bytes); return NULL; }
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    CGContextDrawImage(ctx, CGRectMake(0, 0, gridW, gridH), image);
    CGContextRelease(ctx);
    double *grid = malloc(sizeof(double) * gridW * gridH);
    if (!grid) { free(bytes); return NULL; }
    for (size_t i = 0; i < gridW * gridH; i++) { grid[i] = bytes[i]; }
    free(bytes);
    return grid;
}

// 模板归一化成零均值、单位方差：这样比对只反映结构，不受亮度/色彩管线差异影响。
static void FYNormalizeSignature(double *values, size_t count) {
    if (!values || count == 0) { return; }
    double sum = 0;
    for (size_t i = 0; i < count; i++) { sum += values[i]; }
    double mean = sum / count;
    double var = 0;
    for (size_t i = 0; i < count; i++) { double d = values[i] - mean; var += d * d; }
    double sd = sqrt(var / count);
    if (sd < 1e-6) { sd = 1; }
    for (size_t i = 0; i < count; i++) { values[i] = (values[i] - mean) / sd; }
}

// 候选区域与模板的归一化互相关（模板已零均值单位方差）。
static double FYSignatureCorrelation(const double *scene, size_t sw, size_t sh,
                                     NSInteger x, NSInteger y, size_t cw, size_t ch,
                                     const double *templ, size_t tw, size_t th) {
    if (x < 0 || y < 0 || cw == 0 || ch == 0) { return -2; }
    if (x + (NSInteger)cw > (NSInteger)sw || y + (NSInteger)ch > (NSInteger)sh) { return -2; }
    double sum = 0, sum2 = 0, dot = 0;
    size_t n = tw * th;
    for (size_t j = 0; j < th; j++) {
        NSInteger sy = y + (NSInteger)((double)j * ch / th);
        if (sy >= (NSInteger)sh) { sy = (NSInteger)sh - 1; }
        const double *row = scene + (size_t)sy * sw;
        const double *trow = templ + j * tw;
        for (size_t i = 0; i < tw; i++) {
            NSInteger sx = x + (NSInteger)((double)i * cw / tw);
            if (sx >= (NSInteger)sw) { sx = (NSInteger)sw - 1; }
            double v = row[sx];
            sum += v; sum2 += v * v; dot += v * trow[i];
        }
    }
    double mean = sum / n;
    double var = sum2 / n - mean * mean;
    if (var < 1e-6) { return -1; }
    return dot / (n * sqrt(var));
}

// 自动定位：在目标窗口的**实际截屏**里按内容找出采集画面所在区域。
// 标题栏、工具栏、黑边与画面内容对不上，所以不会被选中；
// 「窗口存在 + 有帧」本身不构成成功，必须比对通过才算。
- (BOOL)autoDetectCaptureCardVideoRectForWindow:(WindowItem *)window reason:(NSString **)outReason {
    if (!window) { if (outReason) { *outReason = @"未选择目标窗口"; } return NO; }
    // 定位失败时不要每轮都重新抓一次整窗：失败的尝试限流，成功了会缓存映射。
    if (self.lastAutoLocateAttempt && -[self.lastAutoLocateAttempt timeIntervalSinceNow] < 3.0) {
        if (outReason) { *outReason = @"暂时无法定位游戏画面，可调整贴译位置"; }
        return NO;
    }
    CGSize frameSize = CGSizeZero;
    if (![self.captureCardInput latestFrameSize:&frameSize]) {
        if (outReason) { *outReason = @"采集卡暂无画面"; }
        return NO;
    }
    if (![self hasUsableScreenCaptureAccess]) {
        if (outReason) { *outReason = @"需要屏幕录制权限才能自动定位游戏画面"; }
        return NO;
    }
    NSRect windowFrame = [self appKitFrameForWindowItem:window];
    if (NSWidth(windowFrame) < 40 || NSHeight(windowFrame) < 40) {
        if (outReason) { *outReason = @"目标窗口太小"; }
        return NO;
    }
    CGImageRef frameImage = [self.captureCardInput copyLatestFrame];
    if (!frameImage) {
        if (outReason) { *outReason = @"采集卡暂无画面"; }
        return NO;
    }
    CGImageRef windowImage = [self copyFullCapturedImageForWindow:window.windowID];
    if (!windowImage) {
        CGImageRelease(frameImage);
        if (outReason) { *outReason = @"无法读取目标窗口画面"; }
        return NO;
    }

    CGFloat videoAspect = frameSize.width / MAX((CGFloat)1, frameSize.height);
    const size_t TW = 40;
    size_t TH = MAX((size_t)8, (size_t)lround(TW / MAX((CGFloat)0.1, videoAspect)));
    double *templ = FYGrayGridFromImage(frameImage, TW, TH);
    CGImageRelease(frameImage);

    const size_t WW = 320;
    CGFloat windowAspect = NSWidth(windowFrame) / MAX((CGFloat)1, NSHeight(windowFrame));
    size_t WH = MAX((size_t)40, (size_t)lround(WW / MAX((CGFloat)0.1, windowAspect)));
    double *scene = FYGrayGridFromImage(windowImage, WW, WH);
    CGImageRelease(windowImage);
    if (!templ || !scene) {
        free(templ); free(scene);
        if (outReason) { *outReason = @"无法读取画面像素"; }
        return NO;
    }
    FYNormalizeSignature(templ, TW * TH);
    double templVar = 0;
    for (size_t i = 0; i < TW * TH; i++) { templVar += templ[i] * templ[i]; }
    if (templVar < 1e-3) {   // 纯色画面：没有可比对的结构
        free(templ); free(scene);
        if (outReason) { *outReason = @"采集卡画面没有可用细节"; }
        return NO;
    }

    // ① 粗搜：画面在窗口里占 25%–100% 宽，位置按网格走
    double best = -2;
    NSRect bestRect = NSZeroRect;
    for (NSInteger step = 0; step <= 30; step++) {
        CGFloat fraction = 0.25 + 0.75 * (CGFloat)step / 30.0;
        size_t cw = MAX((size_t)12, (size_t)lround(WW * fraction));
        size_t ch = MAX((size_t)8, (size_t)lround(cw / MAX((CGFloat)0.1, videoAspect)));
        if (ch > WH || cw > WW) { continue; }
        NSInteger spanX = (NSInteger)WW - (NSInteger)cw;
        NSInteger spanY = (NSInteger)WH - (NSInteger)ch;
        NSInteger steps = 14;
        for (NSInteger iy = 0; iy <= steps; iy++) {
            NSInteger y = spanY <= 0 ? 0 : (NSInteger)llround((double)spanY * iy / steps);
            for (NSInteger ix = 0; ix <= steps; ix++) {
                NSInteger x = spanX <= 0 ? 0 : (NSInteger)llround((double)spanX * ix / steps);
                double score = FYSignatureCorrelation(scene, WW, WH, x, y, cw, ch, templ, TW, TH);
                if (score > best) { best = score; bestRect = NSMakeRect(x, y, cw, ch); }
            }
        }
    }
    // ② 细搜：在最佳候选附近 1 像素步长、更细的尺度
    if (best > 0.2) {
        NSInteger baseW = (NSInteger)bestRect.size.width;
        for (NSInteger dw = -12; dw <= 12; dw += 2) {
            size_t cw = (size_t)MAX((NSInteger)12, baseW + dw);
            size_t ch = MAX((size_t)8, (size_t)lround(cw / MAX((CGFloat)0.1, videoAspect)));
            if (cw > WW || ch > WH) { continue; }
            NSInteger spanX = (NSInteger)WW - (NSInteger)cw;
            NSInteger spanY = (NSInteger)WH - (NSInteger)ch;
            NSInteger cx = (NSInteger)llround(bestRect.origin.x * (CGFloat)spanX / MAX((CGFloat)1, (CGFloat)(WW - (NSInteger)bestRect.size.width)));
            NSInteger cy = (NSInteger)llround(bestRect.origin.y * (CGFloat)spanY / MAX((CGFloat)1, (CGFloat)(WH - (NSInteger)bestRect.size.height)));
            for (NSInteger dy = -10; dy <= 10; dy++) {
                NSInteger y = MAX((NSInteger)0, MIN(spanY, cy + dy));
                for (NSInteger dx = -10; dx <= 10; dx++) {
                    NSInteger x = MAX((NSInteger)0, MIN(spanX, cx + dx));
                    double score = FYSignatureCorrelation(scene, WW, WH, x, y, cw, ch, templ, TW, TH);
                    if (score > best) { best = score; bestRect = NSMakeRect(x, y, cw, ch); }
                }
            }
        }
    }
    free(templ);
    free(scene);
    self.lastAutoLocateAttempt = [NSDate date];

    if (best < 0.55) {
        if (outReason) { *outReason = @"暂时无法定位游戏画面"; }
        FuyiDiagLog(@"CAPTURE-AUTO-LOCATE miss confidence=%.3f frame=%.0fx%.0f window=%@",
                    best, frameSize.width, frameSize.height, NSStringFromRect(windowFrame));
        return NO;
    }
    NSRect rect = NSMakeRect(NSMinX(windowFrame) + bestRect.origin.x / (CGFloat)WW * NSWidth(windowFrame),
                             NSMinY(windowFrame) + bestRect.origin.y / (CGFloat)WH * NSHeight(windowFrame),
                             bestRect.size.width / (CGFloat)WW * NSWidth(windowFrame),
                             bestRect.size.height / (CGFloat)WH * NSHeight(windowFrame));
    [self storeCaptureCardMapping:rect
                      windowFrame:windowFrame
                      videoAspect:videoAspect
                         deviceID:self.selectedCaptureDeviceID
                           source:@"auto"
                       confidence:best
                      forWindowID:window.windowID];
    FuyiDiagLog(@"CAPTURE-AUTO-LOCATE hit confidence=%.3f rect=%@", best, NSStringFromRect(rect));
    return YES;
}

// 写入某个显示窗口的采集卡画面区域。
// 存**相对窗口的归一化矩形** + 校准时的窗口比例与视频比例 + 设备标识：
//   窗口移动 → 归一化映射仍正确；
//   等比缩放 → 仍正确；
//   窗口比例变化 / 画面比例变化 / 换设备 → 判定失效并提示重新校准。
- (void)storeCaptureCardMapping:(NSRect)screenRect
                     windowFrame:(NSRect)windowFrame
                     videoAspect:(CGFloat)videoAspect
                        deviceID:(NSString *)deviceID
                          source:(NSString *)source
                      confidence:(CGFloat)confidence
                     forWindowID:(uint32_t)windowID {
    if (NSWidth(screenRect) < 2 || NSHeight(screenRect) < 2) { return; }
    if (NSWidth(windowFrame) < 2 || NSHeight(windowFrame) < 2) { return; }
    if (!self.captureCardVideoRects) { self.captureCardVideoRects = [NSMutableDictionary dictionary]; }
    // 键用字符串：NSUserDefaults 的 plist 只接受字符串键，用 NSNumber 键存盘后读回来就对不上了。
    self.captureCardVideoRects[[NSString stringWithFormat:@"%u", windowID]] = @{
        @"nx": @((NSMinX(screenRect) - NSMinX(windowFrame)) / NSWidth(windowFrame)),
        @"ny": @((NSMinY(screenRect) - NSMinY(windowFrame)) / NSHeight(windowFrame)),
        @"nw": @(NSWidth(screenRect) / NSWidth(windowFrame)),
        @"nh": @(NSHeight(screenRect) / NSHeight(windowFrame)),
        @"windowAspect": @(NSWidth(windowFrame) / NSHeight(windowFrame)),
        @"videoAspect": @(videoAspect > 0 ? videoAspect : 1.0),
        @"deviceID": deviceID ?: @"",
        @"source": source ?: @"auto",
        @"confidence": @(confidence)
    };
}

// 用户手动调整（次要入口）：来源记为 manual，自动定位不再覆盖它。
- (void)calibrateCaptureCardVideoRect:(NSRect)screenRect
                          windowFrame:(NSRect)windowFrame
                          videoAspect:(CGFloat)videoAspect
                             deviceID:(NSString *)deviceID
                          forWindowID:(uint32_t)windowID {
    [self storeCaptureCardMapping:screenRect windowFrame:windowFrame videoAspect:videoAspect
                         deviceID:deviceID source:@"manual" confidence:1.0 forWindowID:windowID];
}
- (void)clearCaptureCardCalibrationForWindowID:(uint32_t)windowID {
    [self.captureCardVideoRects removeObjectForKey:[NSString stringWithFormat:@"%u", windowID]];
}
- (BOOL)captureCardHasCalibratedVideoRectForWindow:(WindowItem *)window {
    if (!window) { return NO; }
    NSRect rect = NSZeroRect;
    return [self captureCardDisplayRectForWindow:window outRect:&rect reason:NULL];
}
- (NSString *)captureCardCalibrationSummaryForWindow:(WindowItem *)window {
    if (!window) { return @"未选择目标窗口"; }
    NSDictionary *entry = self.captureCardVideoRects[[NSString stringWithFormat:@"%u", window.windowID]];
    NSRect rect = NSZeroRect;
    if (entry && [self captureCardDisplayRectForWindow:window outRect:&rect reason:NULL]) {
        BOOL manual = [entry[@"source"] isEqualToString:@"manual"];
        return [NSString stringWithFormat:@"%@ · 画面区域 %.0f×%.0f", manual ? @"已手动调整" : @"已自动定位", NSWidth(rect), NSHeight(rect)];
    }
    return @"暂时无法定位游戏画面，可调整贴译位置";
}

// 整窗等比估算：只用来解释「为什么位置会有偏差」，**不是有效映射**。
// 窗口有标题栏、工具栏、OBS 面板或画面被裁剪时，这个估算会整体偏移。
- (BOOL)captureCardEstimatedDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect {
    if (!window) { return NO; }
    CGSize frameSize = CGSizeZero;
    if (![self.captureCardInput latestFrameSize:&frameSize]) { return NO; }
    if (frameSize.width < 2 || frameSize.height < 2) { return NO; }
    NSRect windowFrame = [self appKitFrameForWindowItem:window];
    if (NSWidth(windowFrame) < 2 || NSHeight(windowFrame) < 2) { return NO; }
    CGFloat scale = MIN(NSWidth(windowFrame) / frameSize.width, NSHeight(windowFrame) / frameSize.height);
    if (!isfinite(scale) || scale <= 0) { return NO; }
    CGFloat width = frameSize.width * scale;
    CGFloat height = frameSize.height * scale;
    NSRect rect = NSMakeRect(NSMinX(windowFrame) + (NSWidth(windowFrame) - width) / 2.0,
                            NSMinY(windowFrame) + (NSHeight(windowFrame) - height) / 2.0,
                            width, height);
    if (NSWidth(rect) < 2 || NSHeight(rect) < 2) { return NO; }
    if (outRect) { *outRect = NSIntegralRect(rect); }
    return YES;
}

// 采集卡坐标映射：只有**校准过的视频显示区域**才算有效映射。
// 旧实现把「帧等比居中到整个目标窗口」当成映射并返回成功，等于宣称可靠原位映射 ——
// 有帧、有窗口都不足以证明映射有效，因此这里不再回退到估算。
- (BOOL)captureCardDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect {
    return [self captureCardDisplayRectForWindow:window outRect:outRect reason:NULL];
}
- (BOOL)captureCardDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect reason:(NSString **)outReason {
    if (!window) { if (outReason) { *outReason = @"未选择目标窗口。"; } return NO; }
    NSDictionary *entry = self.captureCardVideoRects[[NSString stringWithFormat:@"%u", window.windowID]];
    if (!entry) { if (outReason) { *outReason = @"该窗口还没有贴译位置。"; } return NO; }
    NSRect windowFrame = [self appKitFrameForWindowItem:window];
    if (NSWidth(windowFrame) < 2 || NSHeight(windowFrame) < 2) {
        if (outReason) { *outReason = @"目标窗口尺寸无效，无法定位画面区域。"; }
        return NO;
    }
    // 窗口比例变了（缩放/换显示器）→ 归一化矩形不再对应真实画面。
    CGFloat windowAspect = NSWidth(windowFrame) / NSHeight(windowFrame);
    if (fabs(windowAspect - [entry[@"windowAspect"] doubleValue]) > 0.02) {
        if (outReason) { *outReason = @"目标窗口比例已变化。"; }
        return NO;
    }
    // 输入源/设备换了 → 画面比例或设备标识对不上，校准同样失效。
    CGSize frameSize = CGSizeZero;
    if ([self.captureCardInput latestFrameSize:&frameSize] && frameSize.height > 1) {
        CGFloat videoAspect = frameSize.width / frameSize.height;
        if (fabs(videoAspect - [entry[@"videoAspect"] doubleValue]) > 0.02) {
            if (outReason) { *outReason = @"采集画面比例已变化（可能换了输入源或设备）。"; }
            return NO;
        }
    }
    NSString *calibratedDevice = entry[@"deviceID"] ?: @"";
    if (calibratedDevice.length > 0 && ![calibratedDevice isEqualToString:self.selectedCaptureDeviceID ?: @""]) {
        if (outReason) { *outReason = @"采集卡设备已变化。"; }
        return NO;
    }
    NSRect rect = NSMakeRect(NSMinX(windowFrame) + [entry[@"nx"] doubleValue] * NSWidth(windowFrame),
                            NSMinY(windowFrame) + [entry[@"ny"] doubleValue] * NSHeight(windowFrame),
                            [entry[@"nw"] doubleValue] * NSWidth(windowFrame),
                            [entry[@"nh"] doubleValue] * NSHeight(windowFrame));
    if (NSWidth(rect) < 2 || NSHeight(rect) < 2) {
        if (outReason) { *outReason = @"贴译位置无效。"; }
        return NO;
    }
    if (outRect) { *outRect = NSIntegralRect(rect); }
    return YES;
}

#pragma mark - 采集卡画面区域：手动调整（次要入口）

- (void)updateCaptureCalibrationStatus {
    if (!self.captureCalibrationLabel) { return; }
    BOOL captureCard = [self captureCardInputEnabled];
    WindowItem *window = [self selectedWindowItem];
    self.captureCalibrationLabel.stringValue = captureCard
        ? [self captureCardCalibrationSummaryForWindow:window]
        : @"切换到「采集卡」输入源后可以调整贴译位置。";
    self.captureCalibrateButton.enabled = captureCard && window != nil;
    // 「恢复自动定位」只在用户手动调整过之后才有意义。
    NSDictionary *entry = window ? self.captureCardVideoRects[[NSString stringWithFormat:@"%u", window.windowID]] : nil;
    self.captureCalibrateClearButton.enabled = captureCard && [entry[@"source"] isEqualToString:@"manual"];
    self.captureCalibrateClearButton.hidden = !self.captureCalibrateClearButton.enabled;
}

// 在目标窗口上盖一层拖框层：用户框出的矩形就是真实的视频显示区域。
- (void)beginCaptureCardCalibration:(id)sender {
    if (![self captureCardInputEnabled]) {
        [self setStatus:@"先切换到「采集卡」输入源，再调整贴译位置。"];
        return;
    }
    WindowItem *window = [self selectedWindowItem];
    if (!window) {
        [self setStatus:@"先选择一个显示画面的目标窗口，再调整贴译位置。"];
        return;
    }
    CGSize frameSize = CGSizeZero;
    if (![self.captureCardInput latestFrameSize:&frameSize]) {
        [self setStatus:@"采集卡暂无可用画面：先让采集卡出画，再调整贴译位置。"];
        return;
    }
    NSRect windowFrame = [self appKitFrameForWindowItem:window];
    if (NSWidth(windowFrame) < 40 || NSHeight(windowFrame) < 40) {
        [self setStatus:@"目标窗口太小，无法调整贴译位置。"];
        return;
    }
    [self endCaptureCardCalibration];
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:windowFrame
                                                styleMask:NSWindowStyleMaskBorderless
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.opaque = NO;
    panel.backgroundColor = NSColor.clearColor;
    panel.hasShadow = NO;
    panel.level = NSStatusWindowLevel + 1;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    FYCaptureCalibrationView *view = [[FYCaptureCalibrationView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(windowFrame), NSHeight(windowFrame))];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    __weak typeof(self) weakSelf = self;
    uint32_t windowID = window.windowID;
    CGFloat videoAspect = frameSize.width / MAX((CGFloat)1, frameSize.height);
    NSString *deviceID = self.selectedCaptureDeviceID;
    view.onFinish = ^(NSRect screenRect) {
        [weakSelf finishCaptureCardCalibration:screenRect windowFrame:windowFrame videoAspect:videoAspect deviceID:deviceID windowID:windowID];
    };
    view.onCancel = ^{
        [weakSelf endCaptureCardCalibration];
        [weakSelf setStatus:@"已取消调整贴译位置。"];
    };
    panel.contentView = view;
    self.captureCalibrationPanel = panel;
    [panel makeKeyAndOrderFront:nil];
    [panel makeFirstResponder:view];
    self.captureCalibrationKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (event.keyCode != 53) { return event; }
        [weakSelf endCaptureCardCalibration];
        [weakSelf setStatus:@"已取消调整贴译位置。"];
        return nil;
    }];
    [self setStatus:@"在目标窗口上拖出采集卡画面显示的区域，松开完成，Esc 取消。"];
}

- (void)endCaptureCardCalibration {
    if (self.captureCalibrationKeyMonitor) {
        [NSEvent removeMonitor:self.captureCalibrationKeyMonitor];
        self.captureCalibrationKeyMonitor = nil;
    }
    [self.captureCalibrationPanel close];
    self.captureCalibrationPanel = nil;
}

- (void)finishCaptureCardCalibration:(NSRect)screenRect
                         windowFrame:(NSRect)windowFrame
                         videoAspect:(CGFloat)videoAspect
                            deviceID:(NSString *)deviceID
                          windowID:(uint32_t)windowID {
    [self endCaptureCardCalibration];
    if (NSWidth(screenRect) < 40 || NSHeight(screenRect) < 40) {
        [self setStatus:@"框选区域太小，未保存。"];
        return;
    }
    [self calibrateCaptureCardVideoRect:screenRect windowFrame:windowFrame videoAspect:videoAspect deviceID:deviceID forWindowID:windowID];
    [self scheduleSettingsSave];
    [self updateCaptureCalibrationStatus];
    [self setStatus:[NSString stringWithFormat:@"已按你框选的区域贴译（%.0f×%.0f）。", NSWidth(screenRect), NSHeight(screenRect)]];
}

- (void)clearCaptureCardCalibration:(id)sender {
    WindowItem *window = [self selectedWindowItem];
    if (!window) { return; }
    [self clearCaptureCardCalibrationForWindowID:window.windowID];
    [self scheduleSettingsSave];
    [self updateCaptureCalibrationStatus];
    [self setStatus:@"已恢复自动定位。"];
}

// 当前识别输入源下界面贴译面板应落在哪里。
//   窗口截图：整个目标窗口；采集卡：视频帧适配后的可见矩形。
// 返回 NO 时 outReason 给出明确原因（用于提示，不能静默塞进对白框）。
- (BOOL)inlinePlacementRect:(NSRect *)outRect reason:(NSString **)outReason {
    WindowItem *window = [self selectedWindowItem];
    if (![self captureCardInputEnabled]) {
        if (!window) {
            if (outReason) { *outReason = @"未选择目标窗口，界面文字暂不贴译。"; }
            return NO;
        }
        if (outRect) { *outRect = [self appKitFrameForWindowItem:window]; }
        return YES;
    }
    CGSize frameSize = CGSizeZero;
    if (![self.captureCardInput latestFrameSize:&frameSize]) {
        if (outReason) { *outReason = @"采集卡暂无可用画面，出画后会自动贴上译文。"; }
        return NO;
    }
    if (!window) {
        if (outReason) { *outReason = @"暂时无法定位游戏画面，可调整贴译位置"; }
        return NO;
    }
    NSRect mapped = NSZeroRect;
    if ([self captureCardDisplayRectForWindow:window outRect:&mapped reason:NULL]) {
        if (outRect) { *outRect = mapped; }
        return YES;
    }
    // 没有可用的映射（首次使用 / 变了窗口或输入源）：自动定位一次，用户不需要先手动校准。
    if ([self autoDetectCaptureCardVideoRectForWindow:window reason:NULL] &&
        [self captureCardDisplayRectForWindow:window outRect:&mapped reason:NULL]) {
        if (outRect) { *outRect = mapped; }
        return YES;
    }
    if (outReason) { *outReason = @"暂时无法定位游戏画面，可调整贴译位置"; }
    return NO;
}

// 定位失败时只在**主界面状态区**给一句简短提示。
// 不写字幕框（字幕框只放对白译文，不能被提示覆盖），也不解释实现细节。
- (void)showInlineMappingUnavailableNotice:(NSString *)reason {
    [self setStatus:reason.length ? reason : @"暂时无法定位游戏画面，可调整贴译位置"];
    FuyiDiagLog(@"INLINE-MAPPING-UNAVAILABLE %@", reason ?: @"");
}

- (CGRect)quartzRectFromSelectionRect:(CGRect)selectionRect panelFrame:(NSRect)panelFrame {
    CGFloat globalTop = NSMaxY(NSScreen.mainScreen.frame);
    CGFloat quartzPanelTop = globalTop - NSMaxY(panelFrame);

    return CGRectMake(
        panelFrame.origin.x + selectionRect.origin.x,
        quartzPanelTop + selectionRect.origin.y,
        selectionRect.size.width,
        selectionRect.size.height
    );
}

- (NSRect)appKitOCRPreviewFrameForWindowItem:(WindowItem *)item {
    NSRect windowFrame = [self appKitFrameForWindowItem:item];

    CGFloat x = NSMinX(windowFrame) + self.regionXSlider.doubleValue * NSWidth(windowFrame);
    CGFloat width = self.regionWidthSlider.doubleValue * NSWidth(windowFrame);
    CGFloat height = self.regionHeightSlider.doubleValue * NSHeight(windowFrame);
    CGFloat y = NSMaxY(windowFrame) - (self.regionYSlider.doubleValue + self.regionHeightSlider.doubleValue) * NSHeight(windowFrame);

    return NSIntegralRect(NSMakeRect(x, y, width, height));
}

- (BOOL)updateOCRPreviewPanel {
    WindowItem *window = [self selectedWindowItem];
    if (!window) {
        [self setStatus:@"请先选择 QuickTime 或游戏窗口"];
        return NO;
    }

    NSRect frame = [self appKitOCRPreviewFrameForWindowItem:window];
    if (NSWidth(frame) < 24 || NSHeight(frame) < 24) {
        [self setStatus:@"OCR 框太小，无法显示"];
        return NO;
    }

    if (!self.ocrPreviewPanel) {
        self.ocrPreviewPanel = [[NSPanel alloc] initWithContentRect:frame
                                                          styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO];
        self.ocrPreviewPanel.backgroundColor = [NSColor clearColor];
        self.ocrPreviewPanel.opaque = NO;
        self.ocrPreviewPanel.hasShadow = NO;
        self.ocrPreviewPanel.ignoresMouseEvents = YES;
        // 取景框要“最底层”：用普通窗口层级，别压在其他东西上面。
        // 曾经是 NSStatusWindowLevel(25)，比悬浮字幕窗还高，会盖住游戏文字；
        // 而且它中间原来是 8% 蓝色填充，等于在游戏画面上多蒙了一层，
        // 让取景框里的字被染色 / 被 QuickTime 录制条和它一起遮挡。
        self.ocrPreviewPanel.level = NSNormalWindowLevel;
        self.ocrPreviewPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;

        NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame))];
        content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        content.wantsLayer = YES;
        // 中间完全透明，**一笔都不画**，只留边框：
        // 这样取景框不会给游戏画面增加任何遮挡，OCR 读到什么用户就看到什么。
        content.layer.backgroundColor = NSColor.clearColor.CGColor;
        content.layer.borderColor = [NSColor colorWithCalibratedRed:0.10 green:0.43 blue:1 alpha:1].CGColor;
        content.layer.borderWidth = 3;
        content.layer.cornerRadius = 8;

        self.ocrPreviewLabel = [self label:@"OCR 识别区域" font:FYUIFont(13, NSFontWeightBold) color:NSColor.whiteColor];
        self.ocrPreviewLabel.wantsLayer = YES;
        self.ocrPreviewLabel.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.10 green:0.43 blue:1 alpha:0.92].CGColor;
        self.ocrPreviewLabel.layer.cornerRadius = 5;
        self.ocrPreviewLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:self.ocrPreviewLabel];
        [NSLayoutConstraint activateConstraints:@[
            [self.ocrPreviewLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:10],
            [self.ocrPreviewLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:8]
        ]];

        self.ocrPreviewPanel.contentView = content;
    }

    [self.ocrPreviewPanel setFrame:frame display:YES];
    [self.ocrPreviewPanel orderFrontRegardless];
    return YES;
}

- (CGImageRef)copyCapturedImageForWindow:(uint32_t)windowID {
    return [self copyCapturedImageForWindow:windowID
                                    regionX:self.regionXSlider.doubleValue
                                    regionY:self.regionYSlider.doubleValue
                                regionWidth:self.regionWidthSlider.doubleValue
                               regionHeight:self.regionHeightSlider.doubleValue];
}

- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)windowID {
    return [self copyCapturedImageForWindow:windowID regionX:0 regionY:0 regionWidth:1 regionHeight:1];
}

- (CGImageRef)copyCapturedImageForWindow:(uint32_t)windowID regionX:(double)x regionY:(double)y regionWidth:(double)width regionHeight:(double)height {
    CGImageRef image = CGWindowListCreateImage(
        CGRectNull,
        kCGWindowListOptionIncludingWindow,
        (CGWindowID)windowID,
        kCGWindowImageBoundsIgnoreFraming | kCGWindowImageNominalResolution
    );
    if (!image) { return nil; }

    size_t imageWidth = CGImageGetWidth(image);
    size_t imageHeight = CGImageGetHeight(image);

    CGRect crop = CGRectMake(
        floor(x * imageWidth),
        floor(y * imageHeight),
        MAX(1, floor(width * imageWidth)),
        MAX(1, floor(height * imageHeight))
    );
    crop = CGRectIntersection(crop, CGRectMake(0, 0, imageWidth, imageHeight));
    CGImageRef cropped = CGImageCreateWithImageInRect(image, crop);
    CGImageRelease(image);
    return cropped;
}

- (NSString *)recognizeTextInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment error:(NSError **)error {
    __block NSString *recognizedText = @"";
    __block NSError *requestError = nil;

    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *innerError) {
        if (innerError) {
            requestError = innerError;
            return;
        }

        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (VNRecognizedTextObservation *observation in request.results) {
            VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
            NSString *line = Trim(candidate.string);
            if (line.length > 0) {
                [lines addObject:line];
            }
        }
        recognizedText = [lines componentsJoinedByString:@"\n"];
    }];

    request.recognitionLevel = fastOCR ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = !fastOCR;
    request.recognitionLanguages = languageSegment == 1 ? @[@"en-US"] : @[@"ja-JP"];
    // minimumTextHeight 是**相对图像高度的比例**，所以固定值会在不同窗口尺寸下失效：
    // 实测 2727×1536 截图时 0.02 正好，但运行时窗口是 1710×963（更小），
    // 对白文字占到归一化 0.054 —— 0.02 就把它当“太小的字”漏掉了，表现为整句对白消失。
    // 改成按“绝对像素”目标换算：至少要能读到约 28px 高的字，随图像高度自适应。
    CGFloat imageHeight = (CGFloat)CGImageGetHeight(image);
    // 实测：对白文字高 52px，但 minH 设成 28px 仍读不到，要设到 48px 才读到。
    // Vision 的这个阈值不是“小于就丢弃”的线性开关，实际有效值比文字高度略低几像素。
    CGFloat targetTextPixels = fastOCR ? 32.0 : 48.0;
    CGFloat adaptiveMinH = imageHeight > 0 ? (targetTextPixels / imageHeight) : 0.02;
    if (adaptiveMinH < 0.005) { adaptiveMinH = 0.005; }
    if (adaptiveMinH > 0.10) { adaptiveMinH = 0.10; }
    request.minimumTextHeight = adaptiveMinH;
    FuyiDiagLog(@"  OCRCFG seg=%ld fast=%d imgW=%zu imgH=%zu minH=%.4f",
                (long)languageSegment, fastOCR, CGImageGetWidth(image), CGImageGetHeight(image), adaptiveMinH);

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
    BOOL ok = [handler performRequests:@[request] error:error];
    if (!ok) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                         code:900
                                     userInfo:@{NSLocalizedDescriptionKey: @"OCR 引擎执行失败，已跳过这一轮。"}];
        }
        return @"";
    }
    if (requestError && error) { *error = requestError; }
    return recognizedText ?: @"";
}

// 对白模式需要整段文本，界面模式需要每块的坐标；这里一次请求同时给出两者
// 把画面中的一小块裁出来放大（2 倍）再识别，用于“自动贴合文字”。
// 放大能显著改善小字号识别，也能在小控件压掉一点文字时更容易读出剩余部分。
- (NSString *)recognizeEnlargedRegionOfImage:(CGImageRef)image
                                    regionX:(double)x
                                    regionY:(double)y
                                regionWidth:(double)width
                               regionHeight:(double)height
                                     fastOCR:(BOOL)fastOCR
                             languageSegment:(NSInteger)languageSegment
                                      blocks:(NSArray<OCRTextItem *> **)outBlocks
                                       error:(NSError **)error {
    size_t imageWidth = CGImageGetWidth(image);
    size_t imageHeight = CGImageGetHeight(image);
    if (imageWidth < 2 || imageHeight < 2) { return @""; }

    // Region and OCR boxes use Vision's bottom-left origin; CGImage cropping
    // uses the top-left origin. Convert both the crop and its returned boxes.
    CGRect crop = CGRectMake(floor(x * imageWidth),
                             floor((1.0 - y - height) * imageHeight),
                             MAX((size_t)2, floor(width * imageWidth)),
                             MAX((size_t)2, floor(height * imageHeight)));
    crop = CGRectIntersection(crop, CGRectMake(0, 0, imageWidth, imageHeight));
    if (crop.size.width < 2 || crop.size.height < 2) { return @""; }

    CGImageRef cropped = CGImageCreateWithImageInRect(image, crop);
    if (!cropped) { return @""; }

    // 放大 2 倍，但对最长边设硬上限：超过约 1800px 之后 OCR 精度基本不再提升，
    // 耗时却随像素数线性增长 —— 之前上限 4000 会跑出 3000x950 这种巨图，一轮好几秒。
    size_t scaledWidth = MIN((size_t)(crop.size.width * 2.0), (size_t)1800);
    size_t scaledHeight = MIN((size_t)(crop.size.height * 2.0), (size_t)1800);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, scaledWidth, scaledHeight, 8, 0, space,
                                                 kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) {
        CGImageRelease(cropped);
        return @"";
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, scaledWidth, scaledHeight), cropped);
    CGImageRef scaled = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGImageRelease(cropped);
    if (!scaled) { return @""; }

    NSArray<OCRTextItem *> *localBlocks = nil;
    NSString *text = [self recognizeTextBlocksInImage:scaled
                                              fastOCR:fastOCR
                                      languageSegment:languageSegment
                                               blocks:&localBlocks
                                                error:error];
    CGFloat baseX = crop.origin.x / imageWidth, baseY = 1.0 - CGRectGetMaxY(crop) / imageHeight;
    CGFloat scaleX = crop.size.width / imageWidth, scaleY = crop.size.height / imageHeight;
    for (OCRTextItem *block in localBlocks) {
        CGRect b = block.boundingBox;
        block.boundingBox = CGRectMake(baseX + b.origin.x * scaleX, baseY + b.origin.y * scaleY,
                                       b.size.width * scaleX, b.size.height * scaleY);
        CGRect last = block.lastLineBox;
        if (!CGRectIsEmpty(last)) {
            block.lastLineBox = CGRectMake(baseX + last.origin.x * scaleX, baseY + last.origin.y * scaleY,
                                          last.size.width * scaleX, last.size.height * scaleY);
        }
    }
    if (outBlocks) { *outBlocks = localBlocks; }
    CGImageRelease(scaled);
    return text;
}

- (NSString *)recognizeTextBlocksInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment blocks:(NSArray<OCRTextItem *> **)outBlocks error:(NSError **)error {
    NSArray<OCRTextItem *> *items = [self recognizeTextItemsInImage:image fastOCR:fastOCR languageSegment:languageSegment error:error];
    NSSet<NSString *> *rendered = RenderedTranslationSet(self.captionTextLabel.stringValue, self.inlineTranslationCache);
    items = OCRItemsExcludingOwnOverlay(items, rendered);
    if (outBlocks) { *outBlocks = items; }
    return [[items valueForKey:@"text"] componentsJoinedByString:@"\n"] ?: @"";
}

- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment error:(NSError **)error {
    __block NSMutableArray<OCRTextItem *> *items = [NSMutableArray array];
    __block NSError *requestError = nil;

    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *innerError) {
        if (innerError) {
            requestError = innerError;
            return;
        }

        for (VNRecognizedTextObservation *observation in request.results) {
            VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
            NSString *line = Trim(candidate.string);
            if (line.length < 2) { continue; }
            if (observation.boundingBox.size.width < 0.010 || observation.boundingBox.size.height < 0.006) { continue; }

            OCRTextItem *item = [[OCRTextItem alloc] init];
            item.text = line;
            item.boundingBox = observation.boundingBox;
            // 保留识别置信度：分组/布局只把它用于诊断，不当作几何证据。
            item.confidence = candidate.confidence;
            [items addObject:item];
        }
    }];

    request.recognitionLevel = fastOCR ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = !fastOCR;
    request.recognitionLanguages = languageSegment == 1 ? @[@"en-US"] : @[@"ja-JP"];
    // minimumTextHeight 是相对图像高度的比例，固定值会在不同窗口尺寸下失效：
    // 实测 2727×1536 截图时 0.02 正好，但运行时窗口 1710×963 里对白文字占 0.054，
    // 0.02 会把它当“太小的字”漏掉 → 整句对白凭空消失。
    // 改成按绝对像素换算：目标至少读到约 28px 高的字，随图像高度自适应。
    CGFloat imageHeight = (CGFloat)CGImageGetHeight(image);
    // 实测：对白文字高 52px，但 minH 设成 28px 仍读不到，要设到 48px 才读到。
    // Vision 的这个阈值不是“小于就丢弃”的线性开关，实际有效值比文字高度略低几像素。
    CGFloat targetTextPixels = fastOCR ? 32.0 : 48.0;
    CGFloat adaptiveMinH = imageHeight > 0 ? (targetTextPixels / imageHeight) : 0.02;
    if (adaptiveMinH < 0.005) { adaptiveMinH = 0.005; }
    if (adaptiveMinH > 0.10) { adaptiveMinH = 0.10; }
    request.minimumTextHeight = adaptiveMinH;
    FuyiDiagLog(@"  OCRCFG seg=%ld fast=%d imgW=%zu imgH=%zu minH=%.4f",
                (long)languageSegment, fastOCR, CGImageGetWidth(image), CGImageGetHeight(image), adaptiveMinH);

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
    BOOL ok = [handler performRequests:@[request] error:error];
    if (!ok) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                         code:900
                                     userInfo:@{NSLocalizedDescriptionKey: @"OCR 引擎执行失败，已跳过这一轮。"}];
        }
        return @[];
    }
    if (requestError && error) { *error = requestError; }

    [items sortUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) {
        CGFloat leftTop = CGRectGetMaxY(left.boundingBox);
        CGFloat rightTop = CGRectGetMaxY(right.boundingBox);
        if (fabs(leftTop - rightTop) > 0.025) {
            return leftTop > rightTop ? NSOrderedAscending : NSOrderedDescending;
        }
        if (left.boundingBox.origin.x < right.boundingBox.origin.x) { return NSOrderedAscending; }
        if (left.boundingBox.origin.x > right.boundingBox.origin.x) { return NSOrderedDescending; }
        return NSOrderedSame;
    }];

    return items;
}

#pragma mark - Translation

- (void)translateText:(NSString *)text completion:(void (^)(NSString *translated, NSError *error))completion {
    [self translateText:text
           systemPrompt:[self systemPrompt]
              maxTokens:240
             completion:completion];
}

- (void)translateText:(NSString *)text systemPrompt:(NSString *)systemPrompt maxTokens:(NSInteger)maxTokens completion:(void (^)(NSString *translated, NSError *error))completion {
    [self translateText:text
           systemPrompt:systemPrompt
              maxTokens:maxTokens
          modelOverride:nil
             completion:completion];
}

// OCR may change elsewhere in the frame while the dialogue identity stays the
// same. Reuse its successful translation so a pinned sentence cannot drift
// through repeated model paraphrases. A new occurrence/version or changed
// service/run gets a fresh request; failed requests remain retryable.
- (void)translateDialogueText:(NSString *)text
                     identity:(FYRequestIdentity *)identity
                 systemPrompt:(NSString *)systemPrompt
                   completion:(void (^)(NSString *translated, NSError *error))completion {
    NSDictionary *trace = FYCurrentTrace();
    NSInteger generation = self.translationGeneration;
    NSInteger serviceGeneration = self.serviceTestGeneration;
    NSString *key = identity.sentenceID.length ? [NSString stringWithFormat:@"%ld|%ld|%@|%ld|%@|%@",
        (long)generation, (long)serviceGeneration, identity.sentenceID, (long)identity.version, text, systemPrompt] : nil;
    if (key && [key isEqualToString:self.dialogueTranslationCacheKey] && self.dialogueTranslationCacheValue.length) {
        FYTrace(trace, @"cache", @{@"route": @"dialogue", @"cache_hit": @YES, @"sentence_id": identity.sentenceID ?: @"", @"version": @(identity.version)});
        completion(self.dialogueTranslationCacheValue, nil);
        return;
    }
    FYTrace(trace, @"cache", @{@"route": @"dialogue", @"cache_hit": @NO, @"reason": key ? @"key_or_value_miss" : @"no_sentence_identity", @"sentence_id": identity.sentenceID ?: @"", @"version": @(identity.version)});
    [self translateTextRealtime:text systemPrompt:systemPrompt maxTokens:240 completion:^(NSString *translated, NSError *error) {
        if (key && !error && Trim(translated).length && generation == self.translationGeneration &&
            serviceGeneration == self.serviceTestGeneration) {
            self.dialogueTranslationCacheKey = key;
            self.dialogueTranslationCacheValue = translated;
        }
        completion(translated, error);
    }];
}

// 实时路径专用：走界面上的“实时模型”（默认 deepseek-flash）。
// 推理模型（如 deepseek-v4-pro）会把时间全花在思考上、最后只回思考内容，
// 实时字幕用它等于没有译文 —— 所以实时路径不复用“模型名”那个字段。
- (void)translateTextRealtime:(NSString *)text
                 systemPrompt:(NSString *)systemPrompt
                    maxTokens:(NSInteger)maxTokens
                   completion:(void (^)(NSString *translated, NSError *error))completion {
    NSString *realtimeModel = Trim(self.realtimeModelField.stringValue);
    if (realtimeModel.length == 0) { realtimeModel = @"deepseek-flash"; }
    [self translateText:text
           systemPrompt:systemPrompt
              maxTokens:maxTokens
          modelOverride:realtimeModel
             completion:completion];
}

- (void)translateText:(NSString *)text
          systemPrompt:(NSString *)systemPrompt
             maxTokens:(NSInteger)maxTokens
         modelOverride:(NSString *)modelOverride
            completion:(void (^)(NSString *translated, NSError *error))completion {
    NSDictionary *trace = FYCurrentTrace();
    NSString *apiKey = Trim(self.apiKeyField.stringValue);
    if (apiKey.length == 0) {
        FYTrace(trace, @"request_complete", @{@"reason": @"missing_configuration", @"success": @NO, @"error_code": @401});
        NSError *error = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                             code:401
                                         userInfo:@{NSLocalizedDescriptionKey: @"还没有配置 API Key。"}];
        completion(nil, error);
        return;
    }

    NSURL *url = [self chatCompletionsURL];
    if (!url) {
        FYTrace(trace, @"request_complete", @{@"reason": @"invalid_configuration", @"success": @NO, @"error_code": @400});
        NSError *error = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                             code:400
                                         userInfo:@{NSLocalizedDescriptionKey: @"Base URL 无效，请在“翻译服务”中填写完整的 https:// 地址。"}];
        completion(nil, error);
        return;
    }

    // 实时路径传“实时模型”（默认 Flash）；快照/整屏留空，走界面上的“模型名”
    NSString *model = Trim(modelOverride);
    if (model.length == 0) { model = Trim(self.modelField.stringValue); }
    if (model.length == 0) { model = @"gpt-4.1-mini"; }

    NSMutableDictionary *payload = [@{
        @"model": model,
        @"messages": @[
            @{@"role": @"system", @"content": systemPrompt ?: [self systemPrompt]},
            @{@"role": @"user", @"content": Trim(text)}
        ],
        @"temperature": @0.2,
        @"max_tokens": @(MAX(120, maxTokens))
    } mutableCopy];

    if ([self isDeepSeekRequest]) {
        payload[@"reasoning_effort"] = @"none";
        payload[@"thinking"] = @{@"type": @"disabled"};
    }

    NSError *jsonError = nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (!body) {
        FYTrace(trace, @"request_complete", @{@"reason": @"serialization_error", @"success": @NO, @"error_code": @(jsonError.code)});
        completion(nil, jsonError);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 15;
    request.HTTPBody = body;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];

    NSInteger generation = self.translationGeneration;
    void (^deliver)(NSString *, NSError *) = ^(NSString *translated, NSError *error) {
        FYTrace(trace, @"request_complete", @{@"success": @(!error), @"error_code": @(error.code), @"translation": error ? @"" : (translated ?: @"")});
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.translationGeneration) {
                FYTrace(trace, @"caption_drop", @{@"reason": @"generation_changed_before_delivery"});
                return;
            }
            completion(translated, error);
        });
    };

    NSDate *httpStart = [NSDate date];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        FuyiDiagLog(@"    HTTP %ld in %.2fs err=<%@>", (long)[(NSHTTPURLResponse *)response statusCode],
                    [[NSDate date] timeIntervalSinceDate:httpStart], error.localizedDescription ?: @"");
        FYTrace(trace, @"http_complete", @{@"http_status": @([(NSHTTPURLResponse *)response statusCode]), @"elapsed_ms": @([[NSDate date] timeIntervalSinceDate:httpStart] * 1000), @"error_code": @(error.code)});
        if (error) {
            deliver(nil, error);
            return;
        }

        NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
        if (statusCode < 200 || statusCode >= 300) {
            NSString *body = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
            if (body.length > 500) { body = [[body substringToIndex:500] stringByAppendingString:@"..."]; }
            NSError *httpError = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                                     code:statusCode
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"翻译接口返回 %ld：%@", (long)statusCode, body]}];
            deliver(nil, httpError);
            return;
        }

        NSError *decodeError = nil;
        NSDictionary *decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:&decodeError];
        if (!decoded) {
            deliver(nil, decodeError);
            return;
        }

        NSArray *choices = decoded[@"choices"];
        NSDictionary *firstChoice = choices.firstObject;
        NSDictionary *message = firstChoice[@"message"];
        NSString *content = Trim(StringFromJSONValue(message[@"content"]));
        if (content.length == 0) {
            NSString *reasoningContent = Trim(StringFromJSONValue(message[@"reasoning_content"]));
            NSString *finishReason = Trim(StringFromJSONValue(firstChoice[@"finish_reason"]));
            NSString *description = @"翻译接口没有返回译文。";
            if (reasoningContent.length > 0) {
                description = @"接口只返回了思考内容，没有返回最终译文；请使用 DeepSeek Flash，或保持 reasoning_effort=none。";
            } else if ([finishReason isEqualToString:@"length"]) {
                description = @"接口输出被长度限制截断，没有返回译文；已提高输出额度，请再试一次。";
            } else if (finishReason.length > 0) {
                description = [NSString stringWithFormat:@"翻译接口没有返回译文；finish_reason=%@。", finishReason];
            }
            NSError *missing = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                                   code:204
                                               userInfo:@{NSLocalizedDescriptionKey: description}];
            deliver(nil, missing);
            return;
        }

        deliver(content, nil);
    }];
    self.activeTranslationTask = task;
    FYTrace(trace, @"request_submit", @{@"source": Trim(text), @"generation": @(generation)});
    [task resume];
}

- (NSURL *)chatCompletionsURL {
    NSString *baseURL = Trim(self.baseURLField.stringValue);
    NSURLComponents *components = [NSURLComponents componentsWithString:baseURL];
    NSString *scheme = components.scheme.lowercaseString;
    if (!([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]) ||
        components.host.length == 0 || components.user.length > 0 || components.password.length > 0 ||
        components.query.length > 0 || components.fragment.length > 0) {
        return nil;
    }
    while ([baseURL hasSuffix:@"/"]) {
        baseURL = [baseURL substringToIndex:baseURL.length - 1];
    }
    if (![baseURL hasSuffix:@"/chat/completions"]) {
        baseURL = [baseURL stringByAppendingString:@"/chat/completions"];
    }
    return [NSURL URLWithString:baseURL];
}

- (BOOL)isDeepSeekRequest {
    NSString *baseURL = Trim(self.baseURLField.stringValue).lowercaseString;
    NSString *model = Trim(self.modelField.stringValue).lowercaseString;
    return [baseURL containsString:@"deepseek"] || [model hasPrefix:@"deepseek-"];
}

- (NSString *)systemPrompt {
    return [self systemPromptForMode:[self effectiveModeSegment]];
}

- (BOOL)autoContentModeEnabled {
    // 内容模式已彻底固定为自动判别，手动指定已被移除。
    return YES;
}

// 同一句文本重复出现时，隔多久才允许再请求一次翻译。
// 界面模式要短：界面是用户在动，等久了会明显觉得“卡住不动”。
- (NSTimeInterval)translationAttemptThrottleForMode:(NSInteger)modeSegment {
    return modeSegment == ContentModeUI ? 1.2 : 4.0;
}

// 当画面里存在“详情弹窗/模态窗”时，丢掉不在它范围内的文字（那是上一级页面的残留）。
// 弹窗用像素找：中间一大块又亮又连片的矩形。找不到就原样返回（不影响普通画面）。
// 真弹窗会把背景压暗；普通界面里的大亮块（照片、邮件预览）周围仍是正常亮度。
// 这是区分“弹窗”和“就是一块亮区域”的本质特征 —— 只靠尺寸和位置分不开：
// 实测邮件界面 x=0.15..0.85（中心 0.50，够大也居中）却被误判成弹窗，说明被裁掉一半。
static BOOL ModalSurroundingsAreDimmer(unsigned char *pixels, size_t width, size_t height,
                                       size_t bytesPerRow, CGRect rect) {
    if (!pixels || width == 0 || height == 0) { return NO; }
    CGRect inner = CGRectIntersection(rect, CGRectMake(0, 0, 1, 1));
    if (CGRectIsNull(inner)) { return NO; }
    CGRect outer = CGRectInset(inner, -0.08, -0.08);
    outer = CGRectIntersection(outer, CGRectMake(0, 0, 1, 1));

    double innerSum = 0, outerSum = 0, innerCount = 0, outerCount = 0;
    size_t stepX = MAX((size_t)1, width / 160);
    size_t stepY = MAX((size_t)1, height / 160);
    for (size_t y = 0; y < height; y += stepY) {
        double normalizedY = (double)y / (double)height;
        if (normalizedY < outer.origin.y || normalizedY > CGRectGetMaxY(outer)) { continue; }
        const unsigned char *row = pixels + y * bytesPerRow;
        for (size_t x = 0; x < width; x += stepX) {
            double normalizedX = (double)x / (double)width;
            if (normalizedX < outer.origin.x || normalizedX > CGRectGetMaxX(outer)) { continue; }
            const unsigned char *pixel = row + x * 4;
            double brightness = (pixel[0] + pixel[1] + pixel[2]) / 3.0;
            BOOL insideInner = (normalizedX >= inner.origin.x && normalizedX <= CGRectGetMaxX(inner)
                                && normalizedY >= inner.origin.y && normalizedY <= CGRectGetMaxY(inner));
            if (insideInner) { innerSum += brightness; innerCount += 1; }
            else { outerSum += brightness; outerCount += 1; }
        }
    }
    if (innerCount < 20 || outerCount < 20) { return NO; }
    double innerMean = innerSum / innerCount;
    double outerMean = outerSum / outerCount;
    return (innerMean - outerMean) > 30.0;
}

// 检测到的亮矩形够不够格当“弹窗”。抽成函数是为了能直接测：
// 既要**够大**，也要**水平居中** —— 弹窗是居中的，普通界面里的大亮块（照片、插图）
// 往往偏在一边。实测「我的房间」那张房间照片 x=0.15..0.57（中心 0.36）被误判成弹窗，
// 12 条文字被裁到 4 条，底部说明整段消失。
static BOOL ModalRectQualifiesForCropping(CGRect rect) {
    if (rect.size.width < 0.35 || rect.size.height < 0.16) { return NO; }
    CGFloat centerX = CGRectGetMidX(rect);
    return centerX > 0.40 && centerX < 0.60;
}

// 弹窗裁剪（丢掉弹窗外文字）**默认关闭**。
// 原因：实测无法可靠区分「真弹窗」和「普通界面里的大亮块」——
//   详情弹窗(真)   x=0.20..0.80 y=0.17..0.46  区内均亮165 周围148 差17
//   我的房间(误判) x=0.15..0.57 y=0.33..0.67  区内195 周围168 差27
//   邮件界面(误判) x=0.15..0.85 y=0.29..0.97  区内222 周围172 差50
// 尺寸、是否居中、亮度差都分不开（真弹窗的亮度差反而最小）。
// 而误判代价很大：普通界面底部那两行说明会被整段裁掉（已发生 3 次）。
// 需要时把这里改成 YES 即可恢复（检测代码保留着）。
static const BOOL kModalScopingEnabled = NO;

- (NSArray<OCRTextItem *> *)blocksInsideModalIfPresent:(NSArray<OCRTextItem *> *)blocks
                                              inImage:(CGImageRef)image
                                    normalizedExclusions:(NSArray<NSValue *> *)exclusionValues {
    if (!kModalScopingEnabled) { return blocks; }
    if (blocks.count == 0 || !image) { return blocks; }
    NSUInteger exclusionCount = exclusionValues.count;
    CGRect *exclusions = NULL;
    if (exclusionCount > 0) {
        exclusions = (CGRect *)calloc(exclusionCount, sizeof(CGRect));
        for (NSUInteger index = 0; index < exclusionCount; index++) {
            exclusions[index] = exclusionValues[index].rectValue;
        }
    }

    GrayBuffer buffer = GrayBufferFromImage(image);
    CGRect modalRect = CGRectZero;
    BOOL found = NO;
    if (buffer.pixels) {
        found = DetectBrightContentRegion(buffer.pixels, buffer.width, buffer.height,
                                          buffer.bytesPerRow, &modalRect, NULL,
                                          exclusions, exclusionCount);
    }
    if (exclusions) { free(exclusions); }

    // 没找到弹窗就原样返回；对白框本身也常常是一块亮矩形，这里只要求“够大”才算弹窗
    if (!found) {
        FuyiDiagLog(@"    MODAL-DETAIL found=0 -> 不裁剪");
        return blocks;
    }
    // 除了“够大”，还要求**水平居中** —— 弹窗是居中的，而普通界面里的大亮块
    // （实测「我的房间」那张房间照片：x=0.15..0.57，中心 0.36）并不居中。
    // 不加这条会把整屏文字裁掉大半：实测 12 条被砍到 4 条，底部说明整段消失。
    CGFloat modalCenterX = CGRectGetMidX(modalRect);
    BOOL dimmedSurroundings = ModalSurroundingsAreDimmer(buffer.pixels, buffer.width, buffer.height,
                                                         buffer.bytesPerRow, modalRect);
    GrayBufferRelease(&buffer);
    if (!ModalRectQualifiesForCropping(modalRect) || !dimmedSurroundings) {
        FuyiDiagLog(@"    MODAL-DETAIL found=1 但不合格 x=%.2f..%.2f y=%.2f..%.2f 中心x=%.2f w=%.2f h=%.2f -> 不裁剪",
                    modalRect.origin.x, CGRectGetMaxX(modalRect), modalRect.origin.y, CGRectGetMaxY(modalRect),
                    modalCenterX, modalRect.size.width, modalRect.size.height);
        return blocks;
    }
    FuyiDiagLog(@"    MODAL-DETAIL found=1 x=%.2f..%.2f y=%.2f..%.2f 面板排除区=%lu",
                modalRect.origin.x, CGRectGetMaxX(modalRect), modalRect.origin.y, CGRectGetMaxY(modalRect),
                (unsigned long)exclusionValues.count);

    // 弹窗的橙色页眉/页脚不够亮，纵向外扩一点，避免把弹窗自己的标题丢掉。
    // 不能扩太多，否则上一层页面的文字会重新落进范围里（实测 0.18 会把左侧栏目带回来）。
    CGRect grown = CGRectInset(modalRect, -0.04, -0.13);
    NSMutableArray<OCRTextItem *> *kept = [NSMutableArray array];
    for (OCRTextItem *block in blocks) {
        if (!CGRectContainsRect(grown, block.boundingBox)) { continue; }
        // 我们自己贴的译文面板会盖在弹窗正文上，OCR 会把面板上的字也读出来。
        // 这一类是我们自己画的，直接按面板位置排除，不再当作页面内容。
        BOOL overlapsOwnPanel = NO;
        for (NSValue *value in exclusionValues) {
            CGRect panelRect = value.rectValue;
            CGRect intersection = CGRectIntersection(panelRect, block.boundingBox);
            if (CGRectIsNull(intersection)) { continue; }
            CGFloat blockArea = block.boundingBox.size.width * block.boundingBox.size.height;
            CGFloat overlapArea = intersection.size.width * intersection.size.height;
            if (blockArea > 0 && (overlapArea / blockArea) >= 0.5) { overlapsOwnPanel = YES; break; }
        }
        if (overlapsOwnPanel) { continue; }
        [kept addObject:block];
    }
    // 过滤后剩得太少说明判断不可靠，宁可不裁，避免整屏不翻
    if (kept.count < 2) { return blocks; }
    return kept;
}

- (NSInteger)effectiveModeSegment {
    return self.detectedModeSegment;
}

// 同样的判别结果连续出现两次才切换，避免单帧抖动导致模式来回跳
- (NSInteger)stableContentModeForBlocks:(NSArray<OCRTextItem *> *)blocks {
    NSInteger detected = DetectContentModeForBlocks(blocks, self.detectedModeSegment);

    if (detected == self.detectedModeSegment) {
        self.candidateModeSegment = detected;
        self.candidateModeHits = 0;
        return self.detectedModeSegment;
    }

    if (self.candidateModeSegment == detected) {
        self.candidateModeHits += 1;
    } else {
        self.candidateModeSegment = detected;
        self.candidateModeHits = 1;
    }

    if (self.candidateModeHits >= 2) {
        self.detectedModeSegment = detected;
        self.candidateModeHits = 0;
    }
    return self.detectedModeSegment;
}

- (NSString *)systemPromptForMode:(NSInteger)modeSegment {
    NSString *source = SourceLanguageLabel(self.languageControl.selectedSegment);
    if (modeSegment == 1) {
        return [NSString stringWithFormat:@"你是一个游戏界面与公告文本翻译器。把用户发来的%@ OCR 文本翻译成简体中文。只输出译文，不解释。保留标题、日期、正文、按钮等自然结构；去掉重复、残缺、装饰性或背景噪声文字；菜单和按钮要短，公告正文要完整准确。", source];
    }

    return [NSString stringWithFormat:@"你是一个游戏字幕实时翻译器。把用户发来的%@翻译成自然、准确、口语化的简体中文。只输出译文，不解释，不加引号。保留人名和专有名词。遇到多行文本，按原意合并成适合字幕阅读的短句。", source];
}

#pragma mark - State helpers

- (void)restartTimerIfRunning {
    if (!self.running) { return; }

    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:MAX(0.5, self.intervalSlider.doubleValue)
                                                  target:self
                                                selector:@selector(timerFired:)
                                                userInfo:nil
                                                 repeats:YES];
}

- (BOOL)isStableText:(NSString *)normalized {
    if ([self isSameSubtitleText:normalized comparedTo:self.stableCandidate]) {
        self.stableCandidateCount += 1;
    } else {
        self.stableCandidate = normalized;
        self.stableCandidateCount = 1;
    }
    return self.stableCandidateCount >= 2;
}

- (BOOL)isSameSubtitleText:(NSString *)text comparedTo:(NSString *)previous {
    NSString *left = text ?: @"";
    NSString *right = previous ?: @"";
    if (left.length < 2 || right.length < 2) { return NO; }
    if ([left isEqualToString:right]) { return YES; }
    if ([self effectiveModeSegment] == ContentModeDialogue && self.languageControl.selectedSegment == 0 &&
        [FYDialogueComparisonKey(left) isEqualToString:FYDialogueComparisonKey(right)]) { return YES; }

    NSUInteger maxLength = MAX(left.length, right.length);
    NSUInteger lengthDelta = left.length > right.length ? left.length - right.length : right.length - left.length;
    if (maxLength <= 6) {
        return lengthDelta == 0 && SimilarityRatio(left, right) >= 0.84;
    }

    return SimilarityRatio(left, right) >= 0.90;
}

- (NSString *)displayableTranslation:(NSString *)translated sourceText:(NSString *)sourceText {
    NSString *clean = Trim(translated);
    if (clean.length == 0) { return clean; }

    NSString *sourceNormalized = NormalizeForComparison(sourceText);
    NSArray<NSString *> *rawLines = [clean componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSString *> *keptLines = [NSMutableArray array];

    for (NSString *rawLine in rawLines) {
        NSString *line = Trim(rawLine);
        if (line.length == 0) { continue; }

        NSString *lineNormalized = NormalizeForComparison(line);
        BOOL isSourceEcho = sourceNormalized.length >= 2 && [self isSameSubtitleText:lineNormalized comparedTo:sourceNormalized];
        BOOL looksLikeJapaneseSource = self.languageControl.selectedSegment == 0 && ContainsJapaneseText(line);
        BOOL labeledAsSource = [line hasPrefix:@"原文"] || [line.lowercaseString hasPrefix:@"source"];

        if (isSourceEcho || looksLikeJapaneseSource || labeledAsSource) {
            continue;
        }

        [keptLines addObject:line];
    }

    if (keptLines.count > 0) {
        return [keptLines componentsJoinedByString:@"\n"];
    }

    // 所有行都像是原文回显：不要再把回显当译文显示
    return @"等待中文译文...";
}

- (void)setStatus:(NSString *)status {
    if (self.statusLabel) { self.statusLabel.stringValue = status ?: @""; }
}

- (void)updateRunState {
    if (!self.runStateLabel) { return; }
    self.runStateLabel.stringValue = !self.running ? @"● 已暂停" :
        (self.captureUnavailable ? @"● 等待目标窗口" : @"● 正在翻译");
    self.runStateLabel.textColor = !self.running ? [NSColor secondaryLabelColor] :
        (self.captureUnavailable ? [NSColor systemOrangeColor] :
         [NSColor colorWithRed:0.09 green:0.51 blue:0.43 alpha:1]);
    [self refreshLiveChips];
}

- (void)updateTranslationCount {
    self.translationCountLabel.stringValue = [NSString stringWithFormat:@"翻译轮次  %ld", (long)self.translationCount];
}

- (void)showPreviewUnavailable:(NSString *)message {
    self.framePreview.image = nil;
    self.previewPlaceholder.stringValue = message;
    self.previewPlaceholder.hidden = NO;
}

- (void)updatePreviewFromImage:(CGImageRef)image generation:(NSInteger)generation {
    if (!image || !self.framePreview) { return; }
    NSDate *now = [NSDate date];
    if (self.lastPreviewDate && [now timeIntervalSinceDate:self.lastPreviewDate] < 1.0) { return; }
    self.lastPreviewDate = now;
    CGImageRef retained = CGImageRetain(image);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        size_t sourceWidth = CGImageGetWidth(retained);
        size_t sourceHeight = CGImageGetHeight(retained);
        // Keep enough pixels for Retina previews; bound memory for large captures.
        double scale = MIN(1.0, 2560.0 / MAX((size_t)1, MAX(sourceWidth, sourceHeight)));
        size_t width = MAX((size_t)1, (size_t)llround(sourceWidth * scale));
        size_t height = MAX((size_t)1, (size_t)llround(sourceHeight * scale));
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, colorSpace,
                                                      kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        CGColorSpaceRelease(colorSpace);
        CGImageRef scaled = NULL;
        if (context) {
            CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
            CGContextDrawImage(context, CGRectMake(0, 0, width, height), retained);
            scaled = CGBitmapContextCreateImage(context);
            CGContextRelease(context);
        }
        CGImageRelease(retained);
        if (!scaled) { return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation == self.translationGeneration) {
                self.framePreview.image = [[NSImage alloc] initWithCGImage:scaled size:NSMakeSize(width, height)];
                self.previewPlaceholder.hidden = YES;
            }
            CGImageRelease(scaled);
        });
    });
}

- (void)showError:(NSString *)error {
    if (self.liveErrorLabel) {
        self.liveErrorLabel.stringValue = error ?: @"";
        self.liveErrorLabel.hidden = Trim(error).length == 0;
    }
}

- (void)updateCurrentWindowLabel {
    if (!self.currentWindowLabel) { return; }
    NSString *name = self.windowPopup.selectedItem.title ?: @"未选择";
    self.currentWindowLabel.stringValue = [NSString stringWithFormat:@"当前窗口：%@", name];
}

- (void)clampRegionSliders {
    double x = MIN(MAX(self.regionXSlider.doubleValue, 0), 0.95);
    double y = MIN(MAX(self.regionYSlider.doubleValue, 0), 0.95);
    double width = MIN(MAX(self.regionWidthSlider.doubleValue, 0.05), 1 - x);
    double height = MIN(MAX(self.regionHeightSlider.doubleValue, 0.05), 1 - y);
    self.regionXSlider.doubleValue = x;
    self.regionYSlider.doubleValue = y;
    self.regionWidthSlider.doubleValue = width;
    self.regionHeightSlider.doubleValue = height;
}

- (void)updateCaptionWindowWithText:(NSString *)text status:(NSString *)status {
    NSString *cleanText = Trim(text);
    if (cleanText.length == 0) {
        cleanText = self.running ? @"等待识别字幕..." : @"点击开始翻译";
    }

    NSString *currentText = self.captionTextLabel.stringValue ?: @"";
    // 同一个意思的轻微措辞变化不值得重画一次：模型每次可能换一种说法，
    // 逐帧重设文字就是字幕窗闪烁的来源。够相似就保留现有译文。
    BOOL textChanged = ![cleanText isEqualToString:currentText];
    if (textChanged && currentText.length >= 2 && cleanText.length >= 2) {
        NSString *left = NormalizeForComparison(cleanText);
        NSString *right = NormalizeForComparison(currentText);
        if (left.length >= 2 && right.length >= 2 && SimilarityRatio(left, right) >= 0.90) {
            textChanged = NO;
        }
    }
    // 游戏悬浮窗只显示译文；运行状态在主窗口中显示。
    if (!textChanged) { return; }
    self.captionTextLabel.stringValue = cleanText;
    [self updateCaptionAppearance];
}

- (void)updateCaptionAppearance {
    // 贴译与字幕共用「背景透明度」：改设置后已显示的贴译要立刻跟上（下一帧新建/复用的也读同一个值）。
    [self refreshInlinePanelAppearance];
    ((FYAdventurePanel *)self.captionContainer).fillColor = [self captionBackgroundColorWithAlpha:self.captionOpacitySlider.doubleValue];
    ((FYAdventurePanel *)self.captionContainer).edgeColor = [self captionBorderColor];
    self.captionTextLabel.font = FYUIFont(self.captionFontSizeSlider.doubleValue, NSFontWeightRegular);
    self.captionTextLabel.textColor = [self captionTextColor];
    self.captionBrandLabel.textColor = [self captionSecondaryTextColor];
    [self resizeCaptionWindowForText:self.captionTextLabel.stringValue];
    [self updateCaptionAppearancePreview];
}

- (void)resizeCaptionWindowForText:(NSString *)text {
    if (!self.captionPanel || !self.captionTextLabel) { return; }

    CGFloat minHeight = MAX(140, self.captionHeightSlider ? self.captionHeightSlider.doubleValue : 180);
    // 上限跟随字号与最大行数，避免大字号长译文被硬截断
    CGFloat fontSize = self.captionTextLabel.font ? self.captionTextLabel.font.pointSize : 30;
    NSUInteger maxLines = self.captionTextLabel.maximumNumberOfLines > 0 ? self.captionTextLabel.maximumNumberOfLines : 5;
    CGFloat screenLimit = NSScreen.mainScreen ? NSHeight(NSScreen.mainScreen.visibleFrame) * 0.75 : 900;
    CGFloat maxHeight = MIN(screenLimit, ceil(fontSize * 1.32) * maxLines + 96);
    CGFloat horizontalPadding = 48;
    CGFloat verticalPadding = 96;
    CGFloat availableWidth = MAX(240, NSWidth(self.captionPanel.frame) - horizontalPadding);

    NSDictionary *attributes = @{NSFontAttributeName: self.captionTextLabel.font ?: FYUIFont(30, NSFontWeightSemibold)};
    NSRect measured = [Trim(text) boundingRectWithSize:NSMakeSize(availableWidth, CGFLOAT_MAX)
                                              options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                           attributes:attributes];
    CGFloat desiredHeight = ceil(NSHeight(measured)) + verticalPadding;
    desiredHeight = MIN(maxHeight, MAX(minHeight, desiredHeight));

    NSRect frame = self.captionPanel.frame;
    CGFloat delta = desiredHeight - NSHeight(frame);
    if (fabs(delta) < 1) { return; }

    frame.origin.y -= delta;
    frame.size.height = desiredHeight;
    [self.captionPanel setFrame:frame display:YES animate:NO];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        FYInstallCrashMetadata();
        NSApplication *application = [FYApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
