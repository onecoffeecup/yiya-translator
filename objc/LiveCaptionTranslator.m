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
#import "FYRuntimeDiagnostics.h"
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "FYCaptureCardInput.h"
#import "FYInlineLayout.h"
#import "FYWindowManager.h"
#import "FYOCRManager.h"
#import "FYGeometryManager.h"
#import "FYTranslationManager.h"
#import "learning/FYStudyChatSession.h"
#import "learning/FYStudyChatView.h"
#import "learning/FYStudyOverlayPanel.h"
#import "learning/FYGlobalShortcuts.h"

static NSString *const SettingsKey = @"LiveCaptionTranslator.settings.v1";

static NSString *FYAppearanceColorHex(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb) { return @"#593E2B"; }
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)lround(MIN(MAX(rgb.redComponent, 0), 1) * 255),
            (int)lround(MIN(MAX(rgb.greenComponent, 0), 1) * 255),
            (int)lround(MIN(MAX(rgb.blueComponent, 0), 1) * 255)];
}

static NSColor *FYAppearanceColorFromHex(NSString *hex, NSColor *fallback) {
    if (![hex isKindOfClass:NSString.class] || hex.length != 7 || ![hex hasPrefix:@"#"]) { return fallback; }
    unsigned value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:[hex substringFromIndex:1]];
    if (![scanner scanHexInt:&value] || !scanner.isAtEnd) { return fallback; }
    return [NSColor colorWithSRGBRed:((value >> 16) & 255) / 255.0
                              green:((value >> 8) & 255) / 255.0 blue:(value & 255) / 255.0 alpha:1];
}

static NSColor *FYAppearanceBackdropForText(NSColor *textColor) {
    NSColor *rgb = [textColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    CGFloat brightness = rgb ? 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent +
        0.0722 * rgb.blueComponent : 0;
    return brightness > 0.58 ? FYAdventureColor(@"ink") : FYAdventureColor(@"cream");
}

// ==== 临时诊断（设 FUYI_DIAG=1 或创建 /tmp/fuyi-diag-armed 时启用）====
// 统一的诊断开关。任何会落盘的诊断行为（写日志、保存屏幕截图）都必须经过它；
// 否则正式分发版会在用户不知情的情况下，把屏幕内容写到 /tmp 里。
static BOOL FuyiDiagEnabled(void) {
#ifdef FY_TEST_DISABLE_LEGACY_DIAGNOSTICS
    return NO; // Isolated tests must not consume another running app's global switch.
#else
    static BOOL enabled = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BOOL armed = [[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/fuyi-diag-armed"];
        BOOL byEnv = [NSProcessInfo.processInfo.environment[@"FUYI_DIAG"] isEqualToString:@"1"];
        enabled = (armed || byEnv);
    });
    return enabled;
#endif
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

static NSString *NormalizeForComparison(NSString *value) {
    return FYNormalizeOCRTextForComparison(value);
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
    return [FYOCRManager containsJapaneseKana:value];
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

// Compatibility adapters for existing fixture entry points; policy lives in FYOCRManager.
static NSArray<OCRTextItem *> *ResolveOverlappingOCRItems(NSArray<OCRTextItem *> *items) {
    return [FYOCRManager resolveOverlappingItems:items];
}

static NSArray<OCRTextItem *> *MergeRefinedOCRItems(NSArray<OCRTextItem *> *coarse,
                                                  NSArray<OCRTextItem *> *refined) {
    return [FYOCRManager mergeCoarseItems:coarse refinedItems:refined];
}

static NSInteger const ContentModeDialogue = 0;
static NSInteger const ContentModeUI = 1;

// Compatibility fixture entry points; UI-frame classification is a pure OCR policy.
static BOOL __attribute__((unused)) TextHitsUIToken(NSString *text) { return [FYOCRManager textHitsUIToken:text]; }
static NSUInteger __attribute__((unused)) UITokenHitCount(NSArray<OCRTextItem *> *blocks) { return [FYOCRManager UITokenHitCount:blocks]; }
static BOOL __attribute__((unused)) IsFuriganaNearLargerLine(OCRTextItem *small, NSArray<OCRTextItem *> *blocks) { return [FYOCRManager isFurigana:small nearLargerLineInItems:blocks]; }
static BOOL LooksLikeUIFrame(NSArray<OCRTextItem *> *blocks) { return [FYOCRManager looksLikeUIFrame:blocks]; }

// Dialogue policy compatibility seams; implementations live in FYOCRManager.
static BOOL __attribute__((unused)) IsFormedTextLine(OCRTextItem *block) { return [FYOCRManager isFormedTextLine:block]; }
static BOOL __attribute__((unused)) IsShortDialogueAnchorCandidate(OCRTextItem *block) { return [FYOCRManager isShortDialogueAnchor:block]; }
static BOOL __attribute__((unused)) IsCornerHelpButton(OCRTextItem *block) { return [FYOCRManager isCornerHelpButton:block]; }
static BOOL __attribute__((unused)) IsSingleLineDialogue(OCRTextItem *block) { return [FYOCRManager isSingleLineDialogue:block]; }
static BOOL __attribute__((unused)) IsDialogueAnchorCandidate(OCRTextItem *block) { return [FYOCRManager isDialogueAnchor:block]; }
static BOOL __attribute__((unused)) IsUnpunctuatedSingleLineDialogue(NSString *text, CGRect box) { return [FYOCRManager isUnpunctuatedSingleLineDialogue:text box:box]; }

// Compatibility adapters; caller supplies snapshots, OCR module owns exclusion policy.
static BOOL __attribute__((unused)) IsOwnOverlayText(NSString *raw) {
    return [FYOCRManager isOwnOverlayText:raw];
}

static NSArray<OCRTextItem *> *OCRItemsExcludingOwnOverlay(NSArray<OCRTextItem *> *items,
                                                           NSSet<NSString *> *renderedTexts) {
    return [FYOCRManager itemsExcludingOwnOverlay:items renderedTexts:renderedTexts];
}

static NSSet<NSString *> *RenderedTranslationSet(NSString *captionText, NSDictionary *inlineCache) {
    return [FYOCRManager renderedTranslationSetForCaption:captionText inlineCache:inlineCache];
}

static NSString *DialogueTextWithoutTrailingButton(NSString *text) {
    return [FYOCRManager dialogueTextWithoutTrailingButton:text];
}

NSArray<OCRTextItem *> *SubtitleBandItemsFromBlocks(NSArray<OCRTextItem *> *blocks) {
    return [FYOCRManager subtitleBandItems:blocks];
}

// Speaker and dialogue/options compatibility seams; pure policy in OCR module.
static BOOL __attribute__((unused)) LooksLikeSpeakerNameText(NSString *raw) { return [FYOCRManager looksLikeSpeakerName:raw]; }
static BOOL __attribute__((unused)) LooksLikeSpeakerFuriganaText(NSString *raw) { return [FYOCRManager looksLikeSpeakerFurigana:raw]; }
static BOOL __attribute__((unused)) LooksLikeSpeakerLabelCluster(NSArray<OCRTextItem *> *cluster) { return [FYOCRManager looksLikeSpeakerLabelCluster:cluster]; }
static BOOL __attribute__((unused)) IsSpeakerLabelItem(OCRTextItem *item, NSArray<OCRTextItem *> *pool) { return [FYOCRManager isSpeakerLabelItem:item inPool:pool]; }
static BOOL DialogueFrameIsSpeakerLabelOnly(NSArray<NSString *> *lines) { return [FYOCRManager dialogueFrameIsSpeakerLabelOnly:lines]; }
void SplitDialogueAndOptionsFromItems(NSArray<OCRTextItem *> *band,
                                     NSArray<OCRTextItem *> *allBlocks,
                                     NSMutableArray<OCRTextItem *> *outDialogue,
                                     NSMutableArray<OCRTextItem *> *outOptions) {
    [FYOCRManager splitDialogueAndOptions:band allBlocks:allBlocks dialogue:outDialogue options:outOptions];
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
    return [FYOCRManager contentModeForItems:blocks fallback:fallbackSegment];
}

@interface FlippedDocumentView : NSView
@end

@implementation FlippedDocumentView
- (BOOL)isFlipped { return YES; }
@end

typedef void (^RegionSelectionCompletion)(CGRect selectedRect, CGSize viewSize, BOOL cancelled);

@interface FYRegionSelectionPanel : NSPanel
@end
@implementation FYRegionSelectionPanel
- (BOOL)canBecomeKeyWindow { return YES; }
@end

@interface RegionSelectionView : NSView
@property(nonatomic) NSPoint startPoint;
@property(nonatomic) CGRect selectionRect;
@property(nonatomic, copy) RegionSelectionCompletion completion;
@property(nonatomic) CGFloat helpFontSize;
@property(nonatomic, strong) NSColor *helpTextColor;
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

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate, NSSharingServiceDelegate>
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
@property(nonatomic, strong) NSLayoutConstraint *mainWindowContentWidth;
@property(nonatomic) BOOL mainChatWantsVisible;
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
@property(nonatomic, strong) id regionSelectionKeyMonitor;
@property(nonatomic) BOOL selectOCRRegionAfterCaptureCalibration;
@property(nonatomic, strong) NSPanel *ocrPreviewPanel;
@property(nonatomic, strong) NSTextField *ocrPreviewLabel;
@property(nonatomic, strong) NSView *captionContainer;
@property(nonatomic, strong) NSTextField *captionTextLabel;
@property(nonatomic, strong) NSTextField *captionBrandLabel;

@property(nonatomic, strong) FYWindowManager *windowManager;
@property(nonatomic, strong) FYOCRManager *ocrManager;
@property(nonatomic, strong) NSMutableArray<WindowItem *> *windows;
@property(nonatomic, strong) NSTextField *diagnosticStatusLabel;
@property(nonatomic, strong) NSDate *lastDiagnosticCheckDate;
@property(nonatomic) BOOL exportingDiagnostics;
@property(nonatomic, strong) NSSharingService *diagnosticMailService;
@property(nonatomic, strong) NSPopUpButton *windowPopup;
// 窗口选择卡片：标题/说明随「识别输入源」变化；"显示全部窗口"只在有推荐窗口时才有意义。
@property(nonatomic, strong) NSTextField *windowCardTitleLabel;
@property(nonatomic, strong) NSTextField *windowCardHintLabel;
@property(nonatomic, strong) NSTextField *windowCardNoteLabel;
@property(nonatomic, strong) NSButton *windowScopeButton;
// 列表当前是否展开了全部窗口（默认精简）。
@property(nonatomic) BOOL showAllWindowsInPicker;
// 下拉框里的占位提示（例如「原窗口已关闭，请重新选择」）。
@property(nonatomic, copy) NSString *windowPickerPlaceholder;
// 占位提示是不是"原来的窗口没了"这一类：只有这一种才该盖掉贴译定位的通用原因，
// 「没有找到可用窗口」之类的提示不该改变定位原因文案。
@property(nonatomic) BOOL windowSelectionLost;
// 用户选择 vs 实际承载游戏画面的窗口。
// OBS 的「全屏投影」是另一个窗口：用户选编辑器时画面可能已经不在编辑器里，
// 继续按编辑器算映射就是贴译不跟随的根因，所以这里单独解析"实际显示目标"。
@property(nonatomic) BOOL displayTargetResolved;
@property(nonatomic) BOOL displayTargetAmbiguous;
@property(nonatomic) uint32_t resolvedDisplayTargetID;
@property(nonatomic, strong) NSDate *lastDisplayTargetProbeDate;
// 几何代次：实际显示目标或画面区域每变化一次就 +1。
// 异步翻译回来时校验它，避免旧回调把贴译按旧几何放回去。
@property(nonatomic) NSInteger geometryGeneration;
@property(nonatomic, copy) NSString *lastDisplayGeometryToken;
// 最近一次真正渲染过的译文/原文块：几何变化时用它重排，不重新请求翻译。
@property(nonatomic, copy) NSArray<NSString *> *lastInlineRenderedTranslations;
@property(nonatomic, copy) NSArray<OCRTextItem *> *lastInlineRenderedItems;
// 最近一次渲染时用的几何上下文。和 lastDisplayGeometryToken 不一致 =
// 画面目标/区域已经变了但贴译还是按旧几何渲染的 → 必须重排（哪怕文本一个字都没变）。
@property(nonatomic, copy) NSString *lastInlineRenderGeometryToken;
// 本轮 OCR 用的显示目标与几何代次（异步回调据此判断是否已过期）。
@property(nonatomic) NSInteger ocrGeometryGeneration;
@property(nonatomic) uint32_t ocrDisplayTargetWindowID;
// 采集卡输入：识别输入源与"字幕显示窗口"分开选择。
// 输入源只决定 OCR 从哪里取画面；字幕始终跟随上面选中的 QuickTime／OBS 窗口。
@property(nonatomic, strong) FYCaptureCardInput *captureCardInput;
// 采集卡视频显示区域（屏幕坐标），由校准写入。没有它就认为映射不可用：
// 「有帧 + 有窗口」不等于映射有效（窗口标题栏／工具栏／OBS 面板／裁剪都会让整窗估算整体偏移）。
@property(nonatomic, strong) FYCaptureMappingCache *captureMappingCache;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *captureCardVideoRects;
// 上一次对缓存映射做「定点复核」的时间：限流用，避免每帧都截屏。
@property(nonatomic, strong) FYMappingValidationSchedule *mappingValidationSchedule;
@property(nonatomic, strong) NSDate *lastMappingValidationDate;
@property(nonatomic, strong) NSPanel *inlineExpandedReadingPanel;
// 展开态的稳定性：按**稳定块身份**管理；单帧 OCR 漏读不算换页（连续丢 2 帧才收起）。
@property(nonatomic) NSUInteger inlineExpandedMissingFrames;
// 极端降级：连折叠入口都贴不到原文附近时，在游戏显示区域边缘给「还有 N 条译文」。
@property(nonatomic, strong) NSPanel *inlineOverflowPanel;
@property(nonatomic, strong) NSPanel *inlineOverflowChoicePanel;
@property(nonatomic) NSUInteger inlineOverflowCount;
@property(nonatomic) NSUInteger inlineOverflowPanelCount;
@property(nonatomic, strong) NSArray<NSDictionary *> *inlineOverflowEntries;
@property(nonatomic, strong) id inlineOverflowChoiceKeyMonitor;
@property(nonatomic, strong) id inlineExpandedReadingKeyMonitor;
@property(nonatomic, strong) NSPanel *captureCalibrationPanel;
@property(nonatomic, strong) id captureCalibrationKeyMonitor;
@property(nonatomic, strong) FYAutoLocateSchedule *autoLocateSchedule;
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
@property(nonatomic, strong) FYContentModeStability *contentModeStability;
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
@property(nonatomic, strong) NSSlider *captionWidthSlider;
@property(nonatomic, strong) NSColorWell *captionTextColorWell;
@property(nonatomic) BOOL captionTextColorCustomized;
@property(nonatomic, strong) NSSlider *batchFontSizeSlider;
@property(nonatomic, strong) NSSlider *batchWidthSlider;
@property(nonatomic, strong) NSSlider *batchHeightSlider;
@property(nonatomic, strong) NSColorWell *batchTextColorWell;
@property(nonatomic, strong) NSSegmentedControl *captionThemeControl;
@property(nonatomic, strong) NSButton *stableTextCheckbox;
@property(nonatomic, strong) NSButton *fastOCRCheckbox;
@property(nonatomic, strong) NSButton *autoFitRegionCheckbox;
@property(nonatomic, strong) NSButton *manualOCRScopeCheckbox;
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
@property(nonatomic, strong) FYTranslationTaskOwner *translationTaskOwner;
@property(nonatomic) NSInteger translationGeneration;
@property(nonatomic) BOOL running;
@property(nonatomic) BOOL inFlight;
@property(nonatomic) BOOL screenAccessRequestedDuringSession;
@property(nonatomic) BOOL mainWindowVisibleBeforeRegionSelection;
@property(nonatomic) BOOL captionPanelVisibleBeforeRegionSelection;
@property(nonatomic) BOOL ocrPreviewVisibleBeforeRegionSelection;
@property(nonatomic, strong) FYTranslationRunState *translationRunState;
@property(nonatomic, copy) NSString *lastTranslatedNormalizedText;
@property(nonatomic, copy) NSString *lastSubmittedNormalizedText;
@property(nonatomic, strong) FYTranslationCache *dialogueTranslationCache;
@property(nonatomic, strong) NSDate *lastTranslationAttemptDate;
@property(nonatomic, strong) FYOCRStabilityOwner *ocrStabilityOwner;
@property(nonatomic, copy) NSString *stableCandidate;
@property(nonatomic) NSInteger stableCandidateCount;
@property(nonatomic) NSInteger translationCount;
@property(nonatomic, strong) NSMutableArray<NSPanel *> *inlineTranslationPanels;
@property(nonatomic, strong) NSMutableArray<NSPanel *> *inlineLongCardPanels;
@property(nonatomic, copy) NSString *lastInlineTranslationKey;
@property(nonatomic, strong) FYInlineTranslationCache *inlineCacheOwner;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *inlineTranslationCache;
// 自适应分组与布局：分组器、布局引擎、上一帧结果、按块身份复用的面板表。
@property(nonatomic, strong) FYInlineGrouper *inlineGrouper;
@property(nonatomic, strong) FYInlineLayoutEngine *inlineLayoutEngine;
@property(nonatomic, strong) FYInlineLayoutResult *lastInlineLayoutResult;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSPanel *> *inlinePanelsByBlockID;
// 最近一帧的降级统计（状态区提示用，不写字幕框）。
@property(nonatomic) NSUInteger lastInlineUnplaceableCount;
@property(nonatomic) NSUInteger lastInlineCompactEntryCount;
// 当前展开的完整阅读卡属于哪个块（再点同一个紧凑入口要收起它）。
@property(nonatomic, copy) NSString *inlineExpandedReadingBlockID;
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
- (NSURLSessionDataTask *)activeTranslationTask { return self.translationTaskOwner.activeTask; }
- (void)setActiveTranslationTask:(NSURLSessionDataTask *)task {
    if (!self.translationTaskOwner) { self.translationTaskOwner = [FYTranslationTaskOwner new]; }
    self.translationTaskOwner.activeTask = task;
}

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
        self.inlineTranslationCache = [NSMutableDictionary dictionary];
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
    [self updateMainChatForWindowWidth];
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

- (void)windowDidResize:(NSNotification *)notification {
    if (notification.object != self.mainWindow) { return; }
    self.mainWindowContentWidth.constant=NSWidth(self.mainWindow.contentView.bounds);
    [self updateMainChatForWindowWidth];
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
    self.mainWindow.minSize = NSMakeSize(720, 660);
    self.mainWindow.contentMinSize = NSMakeSize(720, 660);
    self.mainWindow.delegate = self;
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
    self.mainChatWantsVisible = YES;
    self.workspaceWidth=[right.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-510];
    self.mainChatWidth=[self.mainStudyChatView.widthAnchor constraintEqualToConstant:320];

    self.mainWorkspaceRoot=root;
    // Keep document fitting sizes from changing the outer window after a page
    // mounts. Update this constraint from windowDidResize for user resizing.
    NSView *windowHost=[[NSView alloc] initWithFrame:self.mainWindow.contentView.bounds];
    windowHost.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    self.mainWindowContentWidth=[windowHost.widthAnchor constraintEqualToConstant:NSWidth(windowHost.bounds)];
    self.mainWindowContentWidth.priority=1000;
    self.mainWindowContentWidth.active=YES;
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
    FYMountLearningPage(self.pages, self.learningPageHost, index);
    self.selectedPage = index;
    if (index != 4) { [self.captionAppearancePreviewPanel orderOut:nil]; }
    self.headerTitleLabel.stringValue = @[@"实时翻译", @"最近台词", @"单词学习", @"运行设置", @"字幕外观", @"翻译服务"][index];
    self.headerDescriptionLabel.stringValue = @[@"读懂当前对白，再看懂它的语法。", @"把之前没看懂的对白，再读一遍。", @"收藏词语，带着原句复习", @"选择画面来源并调整识别方式", @"调整悬浮字幕的阅读体验", @"配置翻译与学习分析服务"][index];
    self.currentWindowLabel.hidden = index != 0;
    if (index == 1) { [self refreshHistory]; }
    if (index == 2) { [self refreshVocabularyList]; }
    FYUpdateLearningPageSelection(self.pages, self.pageButtons, index);
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
    [page addArrangedSubview:[self cardWithStack:(NSStackView *)[self diagnosticControls]]];
    return page;
}

- (NSView *)makeAppearancePage {
    NSStackView *page = [self verticalStack];
    NSStackView *appearance = [self verticalStack];
    appearance.spacing = 10;
    [appearance addArrangedSubview:[self cardTitle:@"框选字幕 · 单条悬浮译文"]];
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

    NSStackView *batch = [self verticalStack];
    [batch addArrangedSubview:[self cardTitle:@"批量字幕 · 界面贴译"]];
    [batch addArrangedSubview:[self batchCaptionCard]];
    [page addArrangedSubview:[self cardWithStack:batch]];

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
        if ([FYLearningCoordinator selectionRange:range appliesToText:text sentenceID:sentenceID version:version generation:generation
            currentText:self.learningSourceTextView.string currentSentenceID:self.displayedSentenceID
            currentVersion:self.displayedVersion currentGeneration:self.vocabSelectionGeneration]) {
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
    FYSentenceRecord *record = [FYLearningCoordinator historyRecordInList:self.historyRecords index:sender.tag identifier:sender.identifier];
    if (!record) { return; }
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
        if (![FYLearningCoordinator requestSentenceID:analyzedSentenceID version:analyzedVersion generation:requestGeneration
            matchesSentenceID:self.learningCoordinator.currentSentenceID version:self.learningCoordinator.currentVersion generation:self.analysisRequestGeneration]) { return; }
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
        if (![FYLearningCoordinator requestSentenceID:result.sentenceID version:result.version generation:requestGeneration
            matchesSentenceID:analyzedSentenceID version:analyzedVersion generation:requestGeneration]) {
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
    return [FYLearningCoordinator bookmarkInList:self.grammarBookmarks grammarName:item.name
        sentenceID:self.currentAnalysis.sentenceID version:self.currentAnalysis.version];
}

- (BOOL)analysisMatchesCurrentSentence {
    return self.currentAnalysis && [FYLearningCoordinator analysisMatchesSentenceID:self.currentAnalysis.sentenceID version:self.currentAnalysis.version
        currentSentenceID:self.learningCoordinator.currentSentenceID currentVersion:self.learningCoordinator.currentVersion];
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
    for (FYGrammarItem *item in [FYLearningCoordinator applicableGrammarItems:self.currentAnalysis.grammar text:text]) {
        NSColor *highlight = item == [self selectedGrammarItem] ? [self.uiAccent colorWithAlphaComponent:0.23] : color;
        [textView.textStorage addAttribute:NSBackgroundColorAttributeName value:highlight range:item.matchedRange];
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
    FYGrammarItem *item = [FYLearningCoordinator grammarItemInList:self.currentAnalysis.grammar index:sender.tag fallbackToFirst:NO];
    if (!item) { return; }
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
    return [FYLearningCoordinator grammarItemInList:self.currentAnalysis.grammar index:self.selectedGrammarIndex fallbackToFirst:YES];
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
        if (![FYLearningCoordinator followupBelongsToItem:[self selectedGrammarItem] requestedItem:item requestGeneration:generation currentGeneration:self.followupRequestGeneration
            sentenceID:sentenceID version:version currentSentenceID:self.learningCoordinator.currentSentenceID currentVersion:self.learningCoordinator.currentVersion]) { return; }
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
        if (![FYLearningCoordinator vocabularyCompletionBelongsToSelection:requestedRange currentRange:weakSelf.learningSourceTextView.selectedRange
            requestGeneration:requestGeneration currentGeneration:weakSelf.vocabSelectionGeneration sentenceID:requestSentenceID version:requestVersion
            currentSentenceID:weakSelf.learningCoordinator.currentSentenceID currentVersion:weakSelf.learningCoordinator.currentVersion]) {
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
    [FYOCRManager splitSpeakerAndBody:text speaker:outSpeaker body:outBody];
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
        self.historyRecords = [FYLearningCoordinator displayHistoryRecords:records];
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
            exampleButton.hidden = examples.count < 2;
            sourceLabel.stringValue = [FYLearningCoordinator vocabularyExampleText:examples requestedIndex:[self.wordExampleIndices[vocabularyID] unsignedIntegerValue]];
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
    return [FYLearningCoordinator vocabularyInList:self.reviewList identifier:sender.identifier fallbackIndex:sender.tag];
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
    NSInteger nextIndex = self.reviewIndex;
    self.reviewingEntry = [FYLearningCoordinator nextReviewVocabularyInList:self.reviewList index:self.reviewIndex nextIndex:&nextIndex];
    self.reviewIndex = nextIndex;
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

- (void)resetCaptionTextColor:(id)sender {
    self.captionTextColorCustomized = NO;
    self.captionTextColorWell.color = [self captionThemeTextColor];
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
    // 这个选择的**用途**随识别输入源变化：采集卡模式下它只决定译文跟随谁；
    // 窗口截图模式下它同时决定 OCR 从哪个窗口取画面。名称与说明必须跟着变，
    // 不能一概叫「字幕显示窗口」（用户看不出和上面采集来源的区别）。
    self.windowCardTitleLabel = [self label:@"要翻译的窗口" font:FYUIFont(15, NSFontWeightBold) color:[NSColor labelColor]];
    [stack addArrangedSubview:self.windowCardTitleLabel];

    NSStackView *windowRow = [self horizontalStack];
    self.windowPopup = [[NSPopUpButton alloc] init];
    self.windowPopup.target = self;
    self.windowPopup.action = @selector(windowSelectionChanged:);
    // 这一行现在有三个控件（下拉 + 刷新 + 显示全部）：必须允许它们横向压缩，
    // 否则窄窗口下这一行的最小宽度会把整个窗口顶宽（PreviewLayoutTests 抓到的回归）。
    [self.windowPopup.widthAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;
    [self.windowPopup setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSButton *refreshButton = [NSButton buttonWithTitle:@"刷新窗口" target:self action:@selector(refreshWindows:)];
    refreshButton.bezelStyle = NSBezelStyleRounded;
    [refreshButton setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.windowScopeButton = [NSButton buttonWithTitle:@"显示全部窗口" target:self action:@selector(toggleWindowListScope:)];
    self.windowScopeButton.bezelStyle = NSBezelStyleRounded;
    [self.windowScopeButton setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    [windowRow addArrangedSubview:self.windowPopup];
    [windowRow addArrangedSubview:refreshButton];
    [windowRow addArrangedSubview:self.windowScopeButton];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"窗口" view:windowRow]];
    self.windowCardHintLabel = [self mutedLabel:@"这个窗口既是识别画面的来源，也是字幕和贴译跟随的位置；换窗口会重新识别。"];
    self.windowCardHintLabel.maximumNumberOfLines = 3;
    self.windowCardHintLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [stack addArrangedSubview:self.windowCardHintLabel];
    self.windowCardNoteLabel = [self mutedLabel:@""];
    self.windowCardNoteLabel.maximumNumberOfLines = 3;
    self.windowCardNoteLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [stack addArrangedSubview:self.windowCardNoteLabel];

    self.manualOCRScopeCheckbox=[NSButton checkboxWithTitle:@"仅翻译手动框选区域（默认关闭）" target:self action:@selector(controlValueChanged:)];
    self.manualOCRScopeCheckbox.state=NSControlStateValueOff;
    [stack addArrangedSubview:self.manualOCRScopeCheckbox];
    NSTextField *scopeHint=[self mutedLabel:@"关闭时自动识别整画面；开启后实时翻译和当前界面只读框内。这不是视频画面校准。"];
    scopeHint.maximumNumberOfLines=0;
    [stack addArrangedSubview:scopeHint];
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
    self.captionWidthSlider = [self sliderWithMin:360 max:1200 value:900 action:@selector(controlValueChanged:)];
    self.captionThemeControl = [self segmentedWithLabels:@[@"黑底白字", @"白底黑字", @"粉底深字", @"译芽花境"] action:@selector(controlValueChanged:)];
    self.captionThemeControl.selectedSegment = 3;
    self.captionTextColorWell = [[NSColorWell alloc] init];
    self.captionTextColorWell.color = FYAdventureColor(@"ink");
    self.captionTextColorWell.target = self;
    self.captionTextColorWell.action = @selector(controlValueChanged:);
    [self.captionTextColorWell.widthAnchor constraintEqualToConstant:60].active = YES;
    [self.captionTextColorWell.heightAnchor constraintEqualToConstant:30].active = YES;
    [stack addArrangedSubview:[self settingsRowWithLabel:@"背景透明度" view:self.captionOpacitySlider]];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"字号" view:self.captionFontSizeSlider]];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"字幕框宽度" view:self.captionWidthSlider]];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"字幕框最小高度" view:self.captionHeightSlider]];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"样式" view:self.captionThemeControl]];
    NSStackView *colorRow = [self horizontalStack];
    [colorRow addArrangedSubview:self.captionTextColorWell];
    [colorRow addArrangedSubview:[NSButton buttonWithTitle:@"跟随样式" target:self action:@selector(resetCaptionTextColor:)]];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"译文字色" view:colorRow]];
    [stack addArrangedSubview:[self mutedLabel:@"字号与字色控制单条悬浮译文和框选提示；字幕窗可直接拖动，长句会自动增高。"]];
    return stack;
}

- (NSView *)batchCaptionCard {
    NSStackView *stack = [self verticalStack];
    self.batchFontSizeSlider = [self sliderWithMin:13 max:30 value:16 action:@selector(controlValueChanged:)];
    self.batchWidthSlider = [self sliderWithMin:240 max:720 value:560 action:@selector(controlValueChanged:)];
    self.batchHeightSlider = [self sliderWithMin:160 max:500 value:330 action:@selector(controlValueChanged:)];
    self.batchTextColorWell = [[NSColorWell alloc] init];
    self.batchTextColorWell.color = FYAdventureColor(@"ink");
    self.batchTextColorWell.target = self;
    self.batchTextColorWell.action = @selector(controlValueChanged:);
    [self.batchTextColorWell.widthAnchor constraintEqualToConstant:60].active = YES;
    [self.batchTextColorWell.heightAnchor constraintEqualToConstant:30].active = YES;
    [stack addArrangedSubview:[self settingsRowWithLabel:@"译文字号" view:self.batchFontSizeSlider]];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"最大宽度" view:self.batchWidthSlider]];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"长卡最大高度" view:self.batchHeightSlider]];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"译文字色" view:self.batchTextColorWell]];
    [stack addArrangedSubview:[self mutedLabel:@"批量贴译继续使用奶油底和圆体；短贴片、长卡共用这里的字号和字色。空间不足时仍会收起为查看入口。"]];
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
        CGFloat width = MIN(self.captionWidthSlider.doubleValue, NSWidth((self.mainWindow.screen ?: NSScreen.mainScreen).visibleFrame) - 80);
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
    NSRect visible = (self.mainWindow.screen ?: NSScreen.mainScreen).visibleFrame;
    CGFloat desiredWidth = MAX((CGFloat)320, MIN(self.captionWidthSlider.doubleValue, NSWidth(visible) - 80));
    if (fabs(NSWidth(self.captionAppearancePreviewPanel.frame) - desiredWidth) >= 1) {
        [self.captionAppearancePreviewPanel setContentSize:NSMakeSize(desiredWidth, NSHeight(self.captionAppearancePreviewPanel.contentView.bounds))];
    }
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

#include "FYDiagnosticsUI.inc"

#pragma mark - Actions

- (void)toggleRunning:(id)sender {
    self.running ? [self stop] : [self start];
}

- (void)start {
    if (self.running) { return; }
    [self updateRuntimeDiagnostics];
    [[FYRuntimeDiagnostics shared] recordEvent:@"start" fields:@{@"window_id": @([self selectedWindowID]), @"input_source": @([self captureCardInputEnabled] ? 1 : 0)}];
    if ([self selectedWindowID] && (FYWindowOwnerIsYiya([self selectedWindowItem].effectiveOwnerName) || [self selectedWindowOwnerPID] == getpid())) {
        [self setStatus:@"不能把译芽自身作为画面来源。请刷新列表，重新选择 QuickTime／OBS 或游戏窗口。"];
        return;
    }
    if (![self captureCardInputEnabled] && ![self hasScreenAccess] && ![self selectedWindowID]) {
        [self handleMissingScreenAccessForStart];
        return;
    }

    if (![self selectedWindowID]) {
        [self setStatus:[self captureCardInputEnabled] ? @"请先选择游戏画面所在的显示窗口（QuickTime／OBS）"
                                                       : @"请先选择要翻译的窗口（QuickTime／OBS）"];
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
    [[self translationState] reset];
    [[self stabilityOwner] reset];
    [self setStatus:@"正在监测画面"];

    self.timer = [NSTimer scheduledTimerWithTimeInterval:MAX(0.5, self.intervalSlider.doubleValue)
                                                  target:self
                                                selector:@selector(timerFired:)
                                                userInfo:nil
                                                 repeats:YES];
    [self timerFired:self.timer];
}

- (void)stop {
    [[FYRuntimeDiagnostics shared] recordEvent:@"stop" fields:@{@"window_id": @([self selectedWindowID])}];
    // 停采立刻释放采集会话并作废旧帧：暂停后不会再有画面进入 OCR。
    [self.captureCardInput stop];
    self.lastOCRedCaptureFrameIndex = 0;
    [self.timer invalidate];
    self.timer = nil;
    self.running = NO;
    self.captureUnavailable = NO;
    self.inFlight = NO;
    self.translationGeneration += 1;
    [self.translationTaskOwner cancelActiveTask];
    if ([self.serviceStatusLabel.stringValue isEqualToString:@"正在测试服务"]) {
        self.serviceTestGeneration += 1;
        self.serviceStatusLabel.stringValue = @"服务未测试";
    }
    // 停止时把自己画在桌面上的东西收干净：贴译面板会留在屏幕上一直不走，
    // 因为它们由定时循环负责清理，循环一停就没人管了。
    [self clearInlineTranslationPanels];
    [[self inlineCache] clear];
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
    // 这一批 OCR 块属于哪一帧画面：几何代次 + 显示目标都是**发出请求时**记下的。
    // 翻译期间切了窗口/投影的话，这些块对应的坐标系已经失效，绝不能把旧位置的贴译放回去。
    NSInteger cycleGeometry = self.ocrGeometryGeneration;
    uint32_t cycleTarget = self.ocrDisplayTargetWindowID;
    // 先建立"画面 → 显示区域"的落位矩形：窗口截图用整个目标窗口，采集卡用视频帧适配后的可见矩形。
    NSRect placement = NSZeroRect;
    NSString *placementReason = nil;
    BOOL hasPlacement = [self inlinePlacementRect:&placement reason:&placementReason];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *reason = FYInlineDeliveryDropReason(generation, self.translationGeneration, inputEpoch,
            self.captureCardInput.sessionEpoch, self.running, mode,
            (generation == self.translationGeneration && inputEpoch == self.captureCardInput.sessionEpoch && self.running) ? [self effectiveModeSegment] : mode);
        if (reason) {
            FYTrace(trace, @"inline_drop", @{@"reason": reason});
            return;
        }
        if (FYGeometryDeliveryIsStale(cycleGeometry, self.geometryGeneration, cycleTarget,
            (cycleGeometry == self.geometryGeneration && cycleTarget != 0) ? [self displayTargetWindowID] : cycleTarget)) {
            // 画面目标/画面区域在翻译返回前变了：这批块对应的坐标系已经失效，直接丢弃。
            // 不在这里动面板 —— 几何复核（refreshDisplayGeometryIfNeeded:）已经把它们
            // 按新几何重排到正确位置，或者在新位置定不下来时收起来了；
            // 再 hide 一次会把刚排好的正确贴译也一起藏掉。
            self.lastInlineTranslationKey = nil;
            self.lastInlineLayoutResult = nil;
            FYTrace(trace, @"inline_drop", @{@"reason": @"geometry_changed"});
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
                ? [statusText stringByAppendingFormat:@"，%lu 条译文未在画面显示（暂不可放置）：%@",
                   (unsigned long)self.lastInlineUnplaceableCount, Shorten(firstUnplaced, 40)]
                : [statusText stringByAppendingFormat:@"，%lu 条译文未在画面显示（暂不可放置）",
                   (unsigned long)self.lastInlineUnplaceableCount];
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
    return FYTargetQualifiesForOverlay(frontPID, targetPID, targetOnScreen, ownerHasOnScreenWindow, interactingWithOverlay);
}

// 纯策略：浮窗层级跟随目标应用自己用的最高层级。
// 实测 OBS 的预览/投影窗口在 101（NSPopUpMenuWindowLevel），固定用
// NSFloatingWindowLevel(3) 会被它压住。只按目标应用的窗口取层级，上限 102，
// 不越过系统的屏幕保护/告警层级。
- (NSWindowLevel)overlayLevelForTargetPID:(pid_t)targetPID inWindowList:(NSArray<NSDictionary *> *)windows {
    return FYOverlayLevelForTarget(targetPID, windows);
}

// Visibility is independent of OCR completion: late replies cannot raise overlays above another app.
- (BOOL)translationTargetIsForeground {
    NSArray *visibleWindows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    return [self translationTargetIsForegroundWithWindowList:visibleWindows];
}

- (BOOL)translationTargetIsForegroundWithWindowList:(NSArray<NSDictionary *> *)visibleWindows {
    uint32_t selectedID = [self selectedWindowID];
    if (!selectedID) { return NO; }
    // 可见性也跟着**实际显示目标**走：OBS 切到全屏投影后画面在投影窗口上，
    // 如果继续拿编辑器窗口判断，就会出现"贴译跟过去了、字幕却以为目标不在了"的错配。
    uint32_t windowID = selectedID;
    if (self.displayTargetResolved) {
        if (self.displayTargetAmbiguous || self.resolvedDisplayTargetID == 0) { return NO; }
        windowID = self.resolvedDisplayTargetID;
    }
    pid_t frontPID = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    // Some AppKit controls activate the owner even in an auxiliary panel.
    // Keep explicitly used game panels visible; opening the main app still hides them.
    NSWindow *key = NSApp.keyWindow;
    BOOL interactingWithOverlay = frontPID == getpid() && key.isVisible &&
        (key == self.captionPanel || key == self.captionDockPanel || key == self.studyChatPanel || key == self.quickSentencePanel);
    FYWindowVisibilitySnapshot visibility=FYWindowVisibilityInList(windowID, [self selectedWindowOwnerPID], visibleWindows);
    return [self targetQualifiesForOverlayWithFrontmostPID:frontPID
                                                targetPID:visibility.targetPID
                                           targetOnScreen:visibility.targetOnScreen
                                 ownerHasOnScreenWindow:visibility.ownerHasOnScreenWindow
                                    interactingWithOverlay:interactingWithOverlay];
}

- (void)refreshOverlayVisibility:(id)sender {
    // 0.5 秒一次的几何复核（内部还有 0.4 秒限流）：翻译在途时 OCR 循环不推进，
    // 这条轮询保证"切到全屏投影"能在一拍之内被发现，而不是等下次 OCR 回调。
    // 正在手动框选识别区域时不重排，避免和用户的操作抢面板。
    if (self.running && !self.selectingCaptureRegion) { [self refreshDisplayGeometryIfNeeded:NO]; }
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
    if (self.inlineOverflowPanel) { [overlays addObject:self.inlineOverflowPanel]; }
    if (self.inlineOverflowChoicePanel) { [overlays addObject:self.inlineOverflowChoicePanel]; }
    if (self.inlineExpandedReadingPanel) { [overlays addObject:self.inlineExpandedReadingPanel]; }
    // 阅读卡展开期间：其它贴译与折叠入口**保持隐藏**，只留当前展开的那一块
    // （否则每帧的可见性刷新会把它们又排到前面，阅读卡被盖住、遮挡游戏点击）。
    BOOL expanded = self.inlineExpandedReadingPanel != nil;
    for (NSPanel *panel in overlays) {
        panel.level = overlayLevel;
        if (FYOverlayShouldShow(targetActive, expanded, panel == self.inlineExpandedReadingPanel)) {
            if (!panel.isVisible) { [panel orderFrontRegardless]; }
        } else if (panel.isVisible) {
            [panel orderOut:nil];
        }
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
    if (!self.running) { return; }
    if (!self.lastDiagnosticCheckDate || [NSDate.date timeIntervalSinceDate:self.lastDiagnosticCheckDate] >= 5) {
        [self updateRuntimeDiagnostics];
    }
    // 几何复核放在**所有提前返回之前**：即使这一轮 OCR 文本和上一轮完全一样
    //（会被 same_as_last_translated 直接 return），窗口边界检查、映射有效性检查和贴译重排也必须跑。
    [self refreshDisplayGeometryIfNeeded:NO];
    if (self.inFlight) { return; }
    BOOL captureCard = [self captureCardInputEnabled];
    self.inFlight = YES;
    NSDate *cycleStart = [NSDate date];

    // 用**实际承载游戏画面的窗口**（OBS 全屏投影时不是用户选中的编辑器窗口）取画面、算映射：
    // 识别来源、映射坐标系、贴译落位必须全部落在同一个窗口上，否则贴译会跟着旧窗口算。
    uint32_t windowID = [self displayTargetWindowID];
    if (windowID == 0) {
        self.inFlight = NO;
        [self hideInlineTranslationPanelsForGeometryChange];
        [self setStatus:@"检测到多个可能是游戏画面的窗口，请重新选择显示窗口"];
        return;
    }
    // 本轮 OCR 用的几何代次：异步翻译回来时据此判断"这帧是否已经过期"。
    self.ocrDisplayTargetWindowID = windowID;
    self.ocrGeometryGeneration = self.geometryGeneration;
    [[FYRuntimeDiagnostics shared] recordEvent:@"cycle" fields:@{@"window_id": @(windowID), @"generation": @(self.translationGeneration), @"input_source": @(captureCard ? 1 : 0)}];
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
        if (!FYCaptureFrameNeedsRecognition(frameIndex, self.lastOCRedCaptureFrameIndex)) {
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
            [[FYRuntimeDiagnostics shared] recordEvent:@"capture" fields:@{@"window_id": @(windowID), @"generation": @(self.translationGeneration), @"success": @NO}];
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
    [[FYRuntimeDiagnostics shared] recordEvent:@"capture" fields:@{@"window_id": @(windowID), @"generation": @(self.translationGeneration), @"success": @YES}];
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
    WindowItem *snapshotWindow = captureCard ? nil : [self displayTargetWindowItem];
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

    CGRect ocrScope=[self selectedOCRScope];
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
        NSString *ocrText;
        if (CGRectEqualToRect(ocrScope,CGRectMake(0,0,1,1))) {
            ocrText=[self recognizeTextBlocksInImage:fullImage fastOCR:fastOCR languageSegment:languageSegment blocks:&ocrBlocks error:&error];
        } else {
            NSArray *scoped=[FYOCRManager recognizeImage:fullImage topLeftScope:ocrScope recognizer:^NSArray *(CGImageRef cropped,NSError **innerError) {
                return [self recognizeTextItemsInImage:cropped fastOCR:fastOCR languageSegment:languageSegment error:innerError];
            } error:&error];
            ocrText=[FYOCRManager postprocessedTextForItems:scoped renderedTexts:RenderedTranslationSet(self.captionTextLabel.stringValue,self.inlineTranslationCache) blocks:&ocrBlocks];
        }
        NSTimeInterval pass1Duration = [[NSDate date] timeIntervalSinceDate:ocrStart];
        [[FYRuntimeDiagnostics shared] recordEvent:@"ocr" fields:@{@"window_id": @(windowID), @"generation": @(cycleGeneration), @"blocks": @(ocrBlocks.count), @"error_code": @(error.code), @"elapsed_ms": @(pass1Duration * 1000), @"width": @(CGImageGetWidth(fullImage)), @"height": @(CGImageGetHeight(fullImage))}];
        FYTrace(trace, @"ocr", @{@"stage": @"pass1_filtered", @"ocr_lines": FYTraceOCRLines(ocrBlocks),
                                @"blocks": @(ocrBlocks.count), @"fast_ocr": @(fastOCR), @"language": @(languageSegment),
                                @"width": @(CGImageGetWidth(fullImage)), @"height": @(CGImageGetHeight(fullImage)),
                                @"frame_index": @(captureFrameIndex), @"elapsed_ms": @(pass1Duration * 1000)});

        // 自动贴合文字：第一遍先整窗定位文字在哪，然后把那一小块裁出来**放大再识别**。
        // 好处：① 不用用户预先框选固定区域，文字上移/下移都能跟上；
        //      ② 小字放大后识别率明显更好，也更容易扛住被控件切掉一点的情况。
        // 注意挡在文字上的不透明控件是物理遮挡，放大也读不到 —— 那部分救不回来。
        __block NSTimeInterval pass2Duration = 0;
        BOOL autoFit = self.autoFitRegionCheckbox == nil || self.autoFitRegionCheckbox.state == NSControlStateValueOn;
        // 第二遍 OCR 会让每轮耗时翻倍。只在“文字区域本身不大”时才值得放大识别：
        // 区域已经很大时，放大既没有精度收益，又白白多花一整个 OCR 周期。
        FYApplyOCRRefinement(ocrBlocks, autoFit,
            ^NSString *(CGRect region, NSArray<OCRTextItem *> **blocks, NSError **error) {
                CGRect visionScope=CGRectMake(ocrScope.origin.x,1-CGRectGetMaxY(ocrScope),ocrScope.size.width,ocrScope.size.height);
                region=CGRectIntersection(region,visionScope);
                if (CGRectIsNull(region) || CGRectIsEmpty(region)) return nil;
                return [self recognizeEnlargedRegionOfImage:fullImage
                    regionX:region.origin.x regionY:region.origin.y
                    regionWidth:region.size.width regionHeight:region.size.height
                    fastOCR:fastOCR languageSegment:languageSegment blocks:blocks error:error];
            }, ^{ pass2Duration = [[NSDate date] timeIntervalSinceDate:ocrStart] - pass1Duration; },
            &ocrText, &ocrBlocks);
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
            if (cycleGeneration != self.translationGeneration || !self.running || windowID != [self displayTargetWindowID] ||
                inputEpoch != self.captureCardInput.sessionEpoch) {
                NSString *reason = cycleGeneration != self.translationGeneration ? @"generation_changed"
                    : (!self.running ? @"stopped"
                       : (windowID != [self displayTargetWindowID] ? @"window_changed" : @"input_session_changed"));
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
            NSInteger currentFrameMode = [self effectiveModeSegment];

            // 「文本相同」只能跳过**网络翻译**，不能跳过窗口边界/映射复核和贴译重排。
            // 实际显示目标（OBS 编辑器 ↔ 全屏投影）换过、而渲染还是按旧目标做的时候，
            // 必须继续往下走：走的是缓存命中路径（translateInlineTextItems 直接命中缓存），
            // 不会重新请求翻译，但会用**这一帧**的原文块把贴译排到新位置上。
            BOOL sameTextAsRendered = [self isSameSubtitleText:normalized comparedTo:self.lastTranslatedNormalizedText];
            BOOL geometryChangedSinceRender = currentFrameMode == ContentModeUI &&
                ![(self.lastInlineRenderGeometryToken ?: @"") isEqualToString:(self.lastDisplayGeometryToken ?: @"")];

            if (sameTextAsRendered && !geometryChangedSinceRender) {
                // 文本没变时不再走渲染路径，展开态记账要在这里补一次：
                // 否则"这一块已从页面消失"会停在第一帧，阅读卡一直留在画面上。
            [self advanceExpandedReadingState];
                FYTrace(trace, @"skip", @{@"reason": @"same_as_last_translated"});
                [self setStatus:[NSString stringWithFormat:@"文本未变化 · 相似 %.0f%% · OCR %.1fs", translatedSimilarity * 100, ocrDuration]];
                self.inFlight = NO;
                return;
            }
            if (sameTextAsRendered) {
                FYTrace(trace, @"skip", @{@"reason": @"same_as_last_translated_geometry_changed"});
                [self setStatus:[NSString stringWithFormat:@"画面位置变化 · 用已有译文重排 · OCR %.1fs", ocrDuration]];
            }

            // 节流阈值按模式分开：
            //   对白模式 4 秒 —— 防 OCR 抖动、防同一句台词反复请求
            //   界面模式 1.2 秒 —— 界面是**用户自己在动**（滑动、翻页），
            //                      让它等满 4 秒没道理，实测会变成“过了 5 秒才翻出来”
            NSTimeInterval attemptThrottle = [self translationAttemptThrottleForMode:currentFrameMode];

            if ([[self translationState] shouldThrottleText:normalized geometryChanged:geometryChangedSinceRender interval:attemptThrottle
                equivalent:^BOOL(NSString *current, NSString *previous) { return [self isSameSubtitleText:current comparedTo:previous]; }
                now:^NSDate *{ return [NSDate date]; }]) {
            [self advanceExpandedReadingState];
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
                    if (cycleGeneration != self.translationGeneration || !self.running || windowID != [self displayTargetWindowID] ||
                        inputEpoch != self.captureCardInput.sessionEpoch || [self effectiveModeSegment] != ContentModeUI) {
                        NSString *reason = cycleGeneration != self.translationGeneration ? @"generation_changed"
                            : (!self.running ? @"stopped"
                               : (windowID != [self displayTargetWindowID] ? @"window_changed"
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
                    if (cycleGeneration != self.translationGeneration || !self.running || windowID != [self displayTargetWindowID] ||
                        inputEpoch != self.captureCardInput.sessionEpoch || [self effectiveModeSegment] != ContentModeDialogue) {
                        NSString *reason = cycleGeneration != self.translationGeneration ? @"generation_changed"
                            : (!self.running ? @"stopped"
                               : (windowID != [self displayTargetWindowID] ? @"window_changed"
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
                    if (cycleGeneration != self.translationGeneration || !self.running || windowID != [self displayTargetWindowID] ||
                        inputEpoch != self.captureCardInput.sessionEpoch || [self effectiveModeSegment] != ContentModeDialogue) {
                        NSString *reason = cycleGeneration != self.translationGeneration ? @"generation_changed"
                            : (!self.running ? @"stopped"
                               : (windowID != [self displayTargetWindowID] ? @"window_changed"
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
                        [[FYRuntimeDiagnostics shared] recordEvent:@"caption" fields:@{@"window_id": @(windowID), @"generation": @(cycleGeneration), @"success": @YES, @"visible": @(self.captionPanel.isVisible)}];
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

- (FYOCRManager *)ocrManager {
    if (!_ocrManager) {
        _ocrManager = [FYOCRManager new];
        _ocrManager.configurationObserver = ^(BOOL fast, NSInteger segment, size_t width, size_t height, CGFloat minimum) {
            FuyiDiagLog(@"  OCRCFG seg=%ld fast=%d imgW=%zu imgH=%zu minH=%.4f", (long)segment, fast, width, height, minimum);
        };
    }
    return _ocrManager;
}

- (FYWindowManager *)windowManager {
    if (!_windowManager) { _windowManager = [FYWindowManager new]; }
    return _windowManager;
}

- (NSArray<WindowItem *> *)availableWindowItems {
    return [[self windowManager] availableWindowItems];
}

- (NSInteger)quickTimeCapturePriority:(WindowItem *)item {
    if (item.effectiveOwnerName.length == 0 || ![item.effectiveOwnerName hasPrefix:@"QuickTime Player"]) { return 0; }
    NSString *title = item.effectiveTitle;
    if ([@[@"打开", @"Open", @"存储", @"Save", @"导出", @"Export"] containsObject:title]) { return 1; }
    if ([@[@"录影", @"影片录制", @"Movie Recording", @"録画"] containsObject:title]) { return 4; }
    return 3;
}

// 精简列表：推荐窗口 + **始终保留当前选中的窗口**（浏览器、模拟器也照样保留）。
// 没有推荐窗口时退回全部窗口 —— 绝不给用户一个空的、什么都选不了的列表。
- (NSArray<WindowItem *> *)displayedWindowItems {
    return [[self windowManager] displayedWindowItems:self.windows showingAll:self.showAllWindowsInPicker selectedID:[self selectedWindowID]];
}

- (BOOL)hasRecommendedWindowItems {
    return [[self windowManager] hasRecommendedWindowItems:self.windows];
}

// 菜单项的稳定基础名（不含重复序号）：应用名与标题相同就只留一个，避免「Finder · Finder」。
- (NSString *)windowBaseTitleForItem:(WindowItem *)item {
    return [[self windowManager] windowBaseTitleForItem:item];
}

// 「应用名 · 窗口标题」，同一应用的重复名称补 (2)(3)…，保证每一项都能区分。
- (NSString *)windowMenuTitleForItem:(WindowItem *)item occurrence:(NSUInteger)occurrence {
    return [[self windowManager] windowMenuTitleForItem:item occurrence:occurrence];
}

// 重建下拉框。核心约束：**按窗口 ID 绑定**，刷新/排序/切换精简↔全部都不改选择，也不自动跳到第一项。
- (void)rebuildWindowMenuPreservingSelection {
    uint32_t previousSelection = [self selectedWindowID];
    NSArray<WindowItem *> *displayed = [self displayedWindowItems];
    [self.windowPopup removeAllItems];
    self.windowPickerPlaceholder = nil;

    NSMutableDictionary<NSString *, NSNumber *> *labelCounts = [NSMutableDictionary dictionary];
    NSInteger selectedIndex = -1;
    for (NSUInteger index = 0; index < displayed.count; index++) {
        WindowItem *item = displayed[index];
        NSString *base = [self windowBaseTitleForItem:item];
        NSUInteger occurrence = (labelCounts[base] ?: @0).unsignedIntegerValue + 1;
        labelCounts[base] = @(occurrence);
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[self windowMenuTitleForItem:item occurrence:occurrence]
                                                          action:nil
                                                   keyEquivalent:@""];
        menuItem.representedObject = @(item.windowID);
        [self.windowPopup.menu addItem:menuItem];
        if (item.windowID == previousSelection) { selectedIndex = (NSInteger)index; }
    }

    if (selectedIndex >= 0) {
        [self.windowPopup selectItemAtIndex:selectedIndex];
        self.windowSelectionLost = NO;
        return;
    }

    // 已经丢过选择（窗口关闭）时，占位提示要一直保留到用户重新点选，
    // 刷新/切换精简↔全部都不许顺手把别的窗口选上。
    BOOL lostSelection = previousSelection != 0 || self.windowPickerPlaceholder.length > 0;
    NSString *placeholder = lostSelection
        ? @"原窗口已关闭，请重新选择"
        : (displayed.count == 0 ? @"没有找到可用窗口，点「刷新窗口」重试" : nil);
    if (placeholder.length > 0) {
        // 选中的窗口不在了：给一条明确提示，**不静默绑到别的窗口**上。
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:placeholder action:nil keyEquivalent:@""];
        item.representedObject = @0;
        item.enabled = NO;
        [self.windowPopup.menu insertItem:item atIndex:0];
        [self.windowPopup selectItemAtIndex:0];
        self.windowPickerPlaceholder = placeholder;
        self.windowSelectionLost = lostSelection;
        return;
    }

    // 用户还没选过（首次刷新）：用排序里的第一个（推荐位最高）作为默认。
    // 之后刷新永远保持这个选择，不会再自动跳到第一项。
    [self.windowPopup selectItemAtIndex:0];
}

- (void)refreshWindows:(id)sender {
    uint32_t previousSelection = [self selectedWindowID];
    self.windows = [[self availableWindowItems] mutableCopy];
    // 排序在这里再统一做一次：列表的来源可能是被测试或别的入口替换过的数组，
    // 但"更可能相关的窗口排在前面"这个规则必须对所有来源一致。
    [self.windows sortUsingComparator:^NSComparisonResult(WindowItem *left, WindowItem *right) {
        return FYWindowItemSort(left, right);
    }];
    [self rebuildWindowMenuPreservingSelection];

    uint32_t currentSelection = [self selectedWindowID];
    if (previousSelection != 0 && currentSelection == 0) {
        [self setStatus:@"原来的显示窗口已关闭，请重新选择窗口。"];
    }
    [self updateWindowCardCopy];
    [self updateCurrentWindowLabel];
    if (previousSelection != currentSelection) { [self resetForSelectedWindowChange]; }
    // 刷新窗口就是让用户能立刻看到位置变化：几何复核强制跑一次。
    [self refreshDisplayGeometryIfNeeded:YES];
    [self updateRuntimeDiagnostics];
    if (![self captureCardInputEnabled] && ![self hasScreenAccess] && self.windows.count == 0) {
        [self setStatus:@"没有可选窗口：屏幕录制权限尚未生效，请检查权限后重启译芽。可导出诊断包反馈。"];
    }
}

// 精简↔全部只换显示范围：选择按 ID 保留，不触发"换窗口"重置。
- (void)toggleWindowListScope:(id)sender {
    self.showAllWindowsInPicker = !self.showAllWindowsInPicker;
    [self rebuildWindowMenuPreservingSelection];
    [self updateWindowCardCopy];
    [self updateCurrentWindowLabel];
    [self refreshDisplayGeometryIfNeeded:YES];
}

// 按 ID 选中某一项（列表必须已经重建过）。找不到就返回 NO，绝不按标题猜。
- (BOOL)selectWindowWithID:(uint32_t)windowID notifyChange:(BOOL)notify {
    if (windowID == 0) { return NO; }
    NSInteger index = -1;
    for (NSInteger itemIndex = 0; itemIndex < (NSInteger)self.windowPopup.numberOfItems; itemIndex++) {
        NSNumber *represented = [self.windowPopup.menu itemAtIndex:itemIndex].representedObject;
        if (represented.unsignedIntValue == windowID) { index = itemIndex; break; }
    }
    if (index < 0) { return NO; }
    uint32_t previous = [self selectedWindowID];
    [self.windowPopup selectItemAtIndex:index];
    self.windowPickerPlaceholder = nil;
    self.windowSelectionLost = NO;
    [self updateCurrentWindowLabel];
    [self updateWindowCardCopy];
    if (notify && previous != windowID) { [self resetForSelectedWindowChange]; }
    return YES;
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
            // 同一个窗口被系统重建（ID 变了、名字没变）：这是"同一个目标"，可以明确绑定。
            [self refreshWindows:nil];
            return [self selectWindowWithID:candidate.windowID notifyChange:YES];
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
        return [self selectWindowWithID:quickTimeCandidate.windowID notifyChange:YES];
    }
    return NO;
}

- (void)windowSelectionChanged:(id)sender {
    // 用户主动换窗口：清掉旧窗口的产物，并立刻按新窗口复核几何。
    self.displayTargetResolved = NO;
    self.displayTargetAmbiguous = NO;
    self.resolvedDisplayTargetID = 0;
    [self updateCurrentWindowLabel];
    [self updateWindowCardCopy];
    [self updateOCRPreviewIfVisible];
    [self resetForSelectedWindowChange];
    [self refreshDisplayGeometryIfNeeded:YES];
}

- (void)resetForSelectedWindowChange {
    self.translationGeneration += 1;
    [self.translationTaskOwner cancelActiveTask];
    self.inFlight = NO;
    self.captureUnavailable = NO;
    self.lastWindowRecoveryAttemptDate = nil;
    // 换窗口 = 换显示目标：重新解析（并在解析完成前隐藏旧贴译）。
    self.displayTargetResolved = NO;
    self.displayTargetAmbiguous = NO;
    self.resolvedDisplayTargetID = 0;
    self.lastDisplayGeometryToken = nil;
    [self updateRunState];
    [self showPreviewUnavailable:[self captureCardInputEnabled] ? @"等待采集卡画面" : @"选择窗口并开始翻译后显示画面"];
    self.lastPreviewDate = nil;
    self.latestTranslationLabel.stringValue = @"等待译文";
    self.latestSourceLabel.stringValue = @"";
    [self clearInlineTranslationPanels];
    // 换窗口后旧窗口的去重/稳定状态不再适用，重置避免第一句被误判为“文本未变化”
    [[self translationState] reset];
    [[self stabilityOwner] reset];
    [[self inlineCache] clear];
    if (self.running) { [self timerFired:self.timer]; }
}

#pragma mark - 几何复核（与翻译解耦）

// 把贴译面板从旧位置收起来（不销毁）：实际显示目标/画面区域变了、或者定位暂时不可用时，
// 绝不能把面板继续留在旧坐标上冒充"跟着走"。
- (void)hideInlineTranslationPanelsForGeometryChange {
    NSMutableArray<NSPanel *> *panels = [[self.inlineTranslationPanels arrayByAddingObjectsFromArray:self.inlineLongCardPanels] mutableCopy];
    if (self.inlineExpandedReadingPanel) { [panels addObject:self.inlineExpandedReadingPanel]; }
    for (NSPanel *panel in panels) {
        if (panel.isVisible) { [panel orderOut:nil]; }
    }
}

// 几何复核：**和文本有没有变化无关**。
// 「文本未变化」的提前返回分支过去直接 return，把窗口边界检查、映射有效性检查和贴译重排
// 一起跳过了 —— 这就是同一句台词时切到全屏投影、贴译不跟随的根因。
// 成本控制：窗口列表最多 0.4 秒查一次（force=YES 用于用户主动刷新/换窗口），
// 画面区域的定点复核另有 2 秒限流（见 captureCardDisplayRectForWindow:），不做每帧全窗搜索。
- (void)refreshDisplayGeometryIfNeeded:(BOOL)force {
    NSDate *now = [NSDate date];
    if (!force && self.lastDisplayTargetProbeDate &&
        [now timeIntervalSinceDate:self.lastDisplayTargetProbeDate] < 0.4) {
        return;
    }
    self.lastDisplayTargetProbeDate = now;

    NSArray *windowList = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    BOOL ambiguous = NO;
    NSString *note = nil;
    uint32_t resolved = [self resolveDisplayTargetWindowIDInWindowList:windowList ambiguous:&ambiguous note:&note];
    BOOL targetChanged = !self.displayTargetResolved || self.resolvedDisplayTargetID != resolved ||
                         self.displayTargetAmbiguous != ambiguous;
    self.displayTargetResolved = YES;
    self.displayTargetAmbiguous = ambiguous;
    self.resolvedDisplayTargetID = resolved;

    if (targetChanged) {
        CGRect targetBounds = CGRectZero;
        BOOL hasTargetBounds = resolved != 0 && [self liveBoundsForWindowID:resolved outBounds:&targetBounds];
        FuyiDiagLog(@"  TARGET id=%u ambiguous=%d bounds=%@ note=<%@>",
                    resolved, ambiguous ? 1 : 0,
                    hasTargetBounds ? NSStringFromRect(targetBounds) : @"(未知)", note ?: @"");
    }
    if (ambiguous) {
        // 多个投影、无法确定画面在哪一块：先隐藏旧贴译并提示选择，绝不猜一个窗口。
        self.geometryGeneration += 1;
        self.lastDisplayGeometryToken = nil;
        [self resetInlineLayoutCacheAfterMappingChange];
        [self hideInlineTranslationPanelsForGeometryChange];
        [self showInlineMappingUnavailableNotice:note ?: @"检测到多个可能是游戏画面的窗口，请重新选择显示窗口"];
        return;
    }

    NSRect placement = NSZeroRect;
    NSString *placementReason = nil;
    BOOL hasPlacement = [self inlinePlacementRect:&placement reason:&placementReason];
    NSString *token = hasPlacement
        ? [NSString stringWithFormat:@"t=%u|vp=%.1f,%.1f,%.1f,%.1f",
           [self displayTargetWindowID], NSMinX(placement), NSMinY(placement), NSWidth(placement), NSHeight(placement)]
        : [NSString stringWithFormat:@"t=%u|none", [self displayTargetWindowID]];
    if (!targetChanged && [self.lastDisplayGeometryToken isEqualToString:token]) { return; }

    self.lastDisplayGeometryToken = token;
    self.geometryGeneration += 1;
    if (targetChanged) { [self resetInlineLayoutCacheAfterMappingChange]; }

    if (self.inlineExpandedReadingPanel) {
        // 展开卡跟着最新有效映射走；定位暂时不可用就收起，绝不留在旧坐标。
        if (hasPlacement) {
            [self repositionExpandedInlineReadingCardInRect:placement];
        } else {
            [self closeExpandedInlineReadingCard];
        }
    }
    if (!hasPlacement) {
        [self hideInlineTranslationPanelsForGeometryChange];
        // 选中的窗口已经关闭时用下拉框那条更具体的提示（「原窗口已关闭，请重新选择」），
        // 不要被笼统的"请先选择显示窗口"盖掉。
        NSString *message = (self.windowSelectionLost && self.windowPickerPlaceholder.length > 0)
            ? self.windowPickerPlaceholder : note;
        if (message.length > 0) { [self showInlineMappingUnavailableNotice:message]; }
        return;
    }
    if (targetChanged) {
        // 换了承载画面的窗口（OBS 编辑器 ↔ 全屏投影）：旧原文块是**另一个窗口的坐标系**，
        // 拿它们按新窗口重排只会得到一个位置错误但看起来"跟过去了"的假象。
        // 先隐藏旧贴译，等这一轮 OCR 用新窗口的画面重新出块，再用缓存译文按正确位置贴回来。
        [self hideInlineTranslationPanelsForGeometryChange];
        return;
    }
    // 同一个窗口只是移动/缩放：原文块的归一化坐标仍然有效，直接用**已有译文**按新几何重排。
    if (self.lastInlineRenderedTranslations.count > 0 && self.lastInlineRenderedItems.count > 0 &&
        self.lastInlineRenderedTranslations.count == self.lastInlineRenderedItems.count) {
        [self showInlineTranslations:self.lastInlineRenderedTranslations
                            forItems:self.lastInlineRenderedItems
                       placementRect:placement];
    }
}

// 窗口选择卡片的文案随「识别输入源」变化：
//   · 采集卡：这里只决定译文跟随谁 → 「游戏画面所在窗口」
//   · 窗口截图：这里同时决定 OCR 从哪取画面 → 「要翻译的窗口」
// 两者不能共用一个含糊的「字幕显示窗口」，否则用户分不清采集设备与显示窗口。
- (void)updateWindowCardCopy {
    BOOL captureCard = [self captureCardInputEnabled];
    if (self.windowCardTitleLabel) {
        self.windowCardTitleLabel.stringValue = captureCard ? @"游戏画面所在窗口" : @"要翻译的窗口";
    }
    if (self.windowCardHintLabel) {
        self.windowCardHintLabel.stringValue = captureCard
            ? @"选择显示游戏画面的窗口，字幕和贴译将跟随它。"
            : @"这个窗口既是识别画面的来源，也是字幕和贴译跟随的位置；换窗口会重新识别。";
    }
    if (self.windowScopeButton) {
        BOOL hasRecommended = [self hasRecommendedWindowItems];
        // 没有推荐窗口时精简列表本来就等于全部，这个入口没有意义，藏起来但列表不为空。
        self.windowScopeButton.hidden = !hasRecommended;
        self.windowScopeButton.enabled = hasRecommended;
        self.windowScopeButton.title = self.showAllWindowsInPicker ? @"只看推荐窗口" : @"显示全部窗口";
    }
    if (!self.windowCardNoteLabel) { return; }
    NSMutableString *note = [NSMutableString string];
    [note appendString:captureCard
        ? @"上面的「采集卡设备」提供识别画面；这里选的是译文要跟随的显示窗口，两者是分开的。"
        : @"识别来源就是这里选中的窗口（字幕仍显示在悬浮字幕窗上）。"];
    if (self.windowPickerPlaceholder.length > 0) {
        [note appendFormat:@" %@", self.windowPickerPlaceholder];
    } else if (self.windowPopup.numberOfItems > 0) {
        if (![self hasRecommendedWindowItems]) {
            [note appendString:@" 没有检测到 OBS／QuickTime／全屏游戏窗口，已列出全部窗口。"];
        } else if (self.showAllWindowsInPicker) {
            [note appendFormat:@" 正在显示全部 %lu 个窗口。", (unsigned long)self.windowPopup.numberOfItems];
        } else {
            [note appendString:@" 精简列表：优先 OBS／QuickTime／全屏游戏窗口；浏览器、模拟器等点「显示全部窗口」。"];
        }
    }
    self.windowCardNoteLabel.stringValue = note;
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
    self.captureStatusLabel.stringValue = FYCaptureCardStatusText(input.state, availability, input.activeDeviceName,
        input.state == FYCaptureCardSessionStateRunning ? input.receivedFrameCount : 0,
        input.state == FYCaptureCardSessionStateRunning ? input.skippedFrameCount : 0, input.stateDetail);
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
    FYCapturePermissionAction action=FYCapturePermissionActionForAvailability(availability);
    if (action == FYCapturePermissionActionContinue) { continuation(YES); return; }
    if (action == FYCapturePermissionActionRequest) {
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
    [self updateWindowCardCopy];
    // 换输入源会让"画面区域"的含义完全不同（窗口整窗 ↔ 采集帧适配矩形）：几何重新解析。
    self.displayTargetResolved = NO;
    self.displayTargetAmbiguous = NO;
    self.resolvedDisplayTargetID = 0;
    self.lastDisplayGeometryToken = nil;
    self.translationGeneration += 1;
    [self.translationTaskOwner cancelActiveTask];
    self.inFlight = NO;
    self.captureUnavailable = NO;
    [[self translationState] reset];
    [[self stabilityOwner] reset];
    self.lastOCRedCaptureFrameIndex = 0;
    self.lastPreviewDate = nil;
    [[self inlineCache] clear];
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

- (CGRect)selectedOCRScope {
    if (self.manualOCRScopeCheckbox.state != NSControlStateValueOn) return CGRectMake(0,0,1,1);
    return CGRectMake(self.regionXSlider.doubleValue,self.regionYSlider.doubleValue,self.regionWidthSlider.doubleValue,self.regionHeightSlider.doubleValue);
}

- (void)controlValueChanged:(id)sender {
    if (sender == self.captionTextColorWell) { self.captionTextColorCustomized = YES; }
    if (sender == self.captionThemeControl && !self.captionTextColorCustomized) {
        self.captionTextColorWell.color = [self captionThemeTextColor];
    }
    BOOL batchAppearanceChanged = sender && (sender == self.batchFontSizeSlider ||
        sender == self.batchWidthSlider || sender == self.batchHeightSlider || sender == self.batchTextColorWell);
    if (batchAppearanceChanged) { [self applyBatchAppearanceToLayoutEngine]; }
    if (sender && (sender==self.manualOCRScopeCheckbox || sender==self.regionXSlider || sender==self.regionYSlider || sender==self.regionWidthSlider || sender==self.regionHeightSlider)) {
        self.translationGeneration+=1;
        [self.translationTaskOwner cancelActiveTask];
        [[self translationState] reset];
        [[self stabilityOwner] reset];
        self.inFlight=NO;
        self.lastOCRedCaptureFrameIndex=0;
        [self hideInlineTranslationPanelsForGeometryChange];
        [self.inlineTranslationCache removeAllObjects];
    }
    [self clampRegionSliders];
    [self updateCaptionAppearance];
    if (batchAppearanceChanged && self.lastInlineRenderedTranslations.count > 0 && self.lastInlineRenderedItems.count > 0) {
        NSRect placement = NSZeroRect;
        if ([self inlinePlacementRect:&placement reason:NULL]) {
            self.lastInlineTranslationKey = nil;
            self.lastInlineLayoutResult = nil;
            [self showInlineTranslations:self.lastInlineRenderedTranslations forItems:self.lastInlineRenderedItems placementRect:placement];
        }
    }
    [self updateThemeSummary];
    [self updateOCRPreviewIfVisible];
    if (self.running && sender == self.intervalSlider) {
        [self restartTimerIfRunning];
    }
    [self scheduleSettingsSave];
}

- (void)selectOCRRegion:(id)sender {
    [self refreshDisplayGeometryIfNeeded:YES];
    WindowItem *window = [self displayTargetWindowItem];
    if (!window) {
        NSString *message = [self captureCardInputEnabled] ? @"请先选择游戏画面所在的显示窗口" : @"请先选择要翻译的窗口";
        [self setStatus:message];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = message;
        alert.informativeText = @"在「窗口」列表中选择显示游戏画面的窗口，再点击手动框选。";
        [alert addButtonWithTitle:@"知道了"];
        [alert beginSheetModalForWindow:self.mainWindow completionHandler:nil];
        return;
    }

    NSRect scopeViewport=[self appKitFrameForWindowItem:window];
    if ([self captureCardInputEnabled]) {
        CGSize frameSize = CGSizeZero;
        if (![self.captureCardInput latestFrameSize:&frameSize]) {
            [self setStatus:@"请先连接采集卡并等待画面，再框选 OCR 区域"];
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"采集卡还没有画面";
            alert.informativeText = @"手动 OCR 范围按采集视频保存。先连接采集卡，收到画面后再框选。";
            [alert addButtonWithTitle:@"重连采集卡"];
            [alert addButtonWithTitle:@"取消"];
            __weak typeof(self) weakSelf = self;
            [alert beginSheetModalForWindow:self.mainWindow completionHandler:^(NSModalResponse response) {
                if (response == NSAlertFirstButtonReturn) { [weakSelf reconnectCaptureDevice:nil]; }
            }];
            return;
        }
        if (![self inlinePlacementRect:&scopeViewport reason:NULL]) {
            [self setStatus:@"请先定位视频画面，再框选 OCR 区域"];
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"还没有定位视频画面";
            alert.informativeText = @"先在目标窗口框出采集视频的位置；完成后会继续框选 OCR 区域。";
            [alert addButtonWithTitle:@"定位视频画面"];
            [alert addButtonWithTitle:@"取消"];
            __weak typeof(self) weakSelf = self;
            [alert beginSheetModalForWindow:self.mainWindow completionHandler:^(NSModalResponse response) {
                if (response == NSAlertFirstButtonReturn) {
                    weakSelf.selectOCRRegionAfterCaptureCalibration = YES;
                    [weakSelf beginCaptureCardCalibration:nil];
                    if (!weakSelf.captureCalibrationPanel) {
                        weakSelf.selectOCRRegionAfterCaptureCalibration = NO;
                    }
                }
            }];
            return;
        }
    }
    CGFloat screenTop=NSMaxY(NSScreen.mainScreen.frame);
    CGRect quartzViewport=CGRectMake(NSMinX(scopeViewport),screenTop-NSMaxY(scopeViewport),NSWidth(scopeViewport),NSHeight(scopeViewport));
    NSScreen *targetScreen = [self screenForWindowItem:window] ?: NSScreen.mainScreen;
    NSRect panelFrame = NSIntersectionRect(scopeViewport, targetScreen.frame);
    if (NSWidth(panelFrame) < 80 || NSHeight(panelFrame) < 80) {
        [self setStatus:@"游戏画面未在当前屏幕上，请将它显示出来后重试"];
        return;
    }

    [self hideInterfaceForRegionSelection];
    if (self.regionSelectionKeyMonitor) {
        [NSEvent removeMonitor:self.regionSelectionKeyMonitor];
        self.regionSelectionKeyMonitor = nil;
    }
    [self.regionSelectionPanel close];

    self.regionSelectionPanel = [[FYRegionSelectionPanel alloc] initWithContentRect:panelFrame
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
    selectionView.helpFontSize = self.captionFontSizeSlider.doubleValue;
    selectionView.helpTextColor = [self captionTextColor];

    __weak typeof(self) weakSelf = self;
    selectionView.completion = ^(CGRect selectedRect, CGSize viewSize, BOOL cancelled) {
        AppDelegate *strongSelf = weakSelf;
        if (!strongSelf) { return; }

        if (strongSelf.regionSelectionKeyMonitor) {
            [NSEvent removeMonitor:strongSelf.regionSelectionKeyMonitor];
            strongSelf.regionSelectionKeyMonitor = nil;
        }
        [strongSelf.regionSelectionPanel close];
        strongSelf.regionSelectionPanel = nil;

        if (cancelled) {
            [strongSelf restoreInterfaceAfterRegionSelectionShowingOCRPreview:NO];
            [strongSelf setStatus:@"已取消框选"];
            return;
        }

        CGRect quartzSelection = [strongSelf quartzRectFromSelectionRect:selectedRect panelFrame:panelFrame];
        CGRect clippedSelection = CGRectIntersection(quartzSelection, quartzViewport);

        if (CGRectIsNull(clippedSelection) || clippedSelection.size.width < 24 || clippedSelection.size.height < 24) {
            [strongSelf restoreInterfaceAfterRegionSelectionShowingOCRPreview:NO];
            [strongSelf setStatus:@"框选区域没有落在游戏画面里"];
            return;
        }

        double x = (clippedSelection.origin.x - quartzViewport.origin.x) / quartzViewport.size.width;
        double y = (clippedSelection.origin.y - quartzViewport.origin.y) / quartzViewport.size.height;
        double width = clippedSelection.size.width / quartzViewport.size.width;
        double height = clippedSelection.size.height / quartzViewport.size.height;

        strongSelf.regionXSlider.doubleValue = MAX(0, MIN(1, x));
        strongSelf.regionYSlider.doubleValue = MAX(0, MIN(1, y));
        strongSelf.regionWidthSlider.doubleValue = MAX(0.05, MIN(1, width));
        strongSelf.regionHeightSlider.doubleValue = MAX(0.05, MIN(1, height));
        strongSelf.manualOCRScopeCheckbox.state=NSControlStateValueOn;
        [strongSelf controlValueChanged:strongSelf.manualOCRScopeCheckbox];
        [strongSelf saveSettings:nil];
        [strongSelf restoreInterfaceAfterRegionSelectionShowingOCRPreview:YES];
        [strongSelf setStatus:[NSString stringWithFormat:@"OCR 区域已更新：x %.2f y %.2f w %.2f h %.2f",
                               strongSelf.regionXSlider.doubleValue,
                               strongSelf.regionYSlider.doubleValue,
                               strongSelf.regionWidthSlider.doubleValue,
                               strongSelf.regionHeightSlider.doubleValue]];
    };

    self.regionSelectionPanel.contentView = selectionView;
    [NSApp activateIgnoringOtherApps:YES];
    [self.regionSelectionPanel makeKeyAndOrderFront:nil];
    [self.regionSelectionPanel makeFirstResponder:selectionView];
    self.regionSelectionKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (event.keyCode != 53 || !weakSelf.regionSelectionPanel) { return event; }
        selectionView.completion(CGRectZero, selectionView.bounds.size, YES);
        return nil;
    }];
    [self setStatus:@"在游戏画面内拖动框选 OCR 区域，Esc 取消"];
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
    [self controlValueChanged:self.regionHeightSlider];
}

- (void)useLargeSubtitleRegion:(id)sender {
    self.regionXSlider.doubleValue = 0.02;
    self.regionYSlider.doubleValue = 0.42;
    self.regionWidthSlider.doubleValue = 0.96;
    self.regionHeightSlider.doubleValue = 0.52;
    [self controlValueChanged:self.regionHeightSlider];
}

- (void)useFullWindowRegion:(id)sender {
    self.regionXSlider.doubleValue = 0;
    self.regionYSlider.doubleValue = 0;
    self.regionWidthSlider.doubleValue = 1;
    self.regionHeightSlider.doubleValue = 1;
    [self controlValueChanged:self.regionHeightSlider];
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
        [self setStatus:[self captureCardInputEnabled] ? @"请先选择游戏画面所在的显示窗口" : @"请先选择要翻译的窗口"];
        return;
    }
    if (!captureCard && ![self hasUsableScreenCaptureAccess]) {
        [self handleMissingScreenAccessForStart];
        return;
    }

    self.inFlight = YES;
    NSInteger cycleGeneration = self.translationGeneration;
    // 和实时循环一致：识别与贴译都用**实际承载游戏画面的窗口**。
    [self refreshDisplayGeometryIfNeeded:YES];
    uint32_t windowID = [self displayTargetWindowID];
    if (windowID == 0) {
        self.inFlight = NO;
        [self hideInlineTranslationPanelsForGeometryChange];
        [self setStatus:@"检测到多个可能是游戏画面的窗口，请重新选择显示窗口"];
        return;
    }
    self.ocrDisplayTargetWindowID = windowID;
    self.ocrGeometryGeneration = self.geometryGeneration;
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
    CGRect ocrScope=[self selectedOCRScope];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDate *ocrStart = [NSDate date];
        NSError *error = nil;
        NSArray<OCRTextItem *> *blocks = [FYOCRManager recognizeImage:image topLeftScope:ocrScope recognizer:^NSArray *(CGImageRef cropped,NSError **innerError) {
            return [self recognizeTextItemsInImage:cropped fastOCR:NO languageSegment:languageSegment error:innerError];
        } error:&error];
        NSTimeInterval ocrDuration = [[NSDate date] timeIntervalSinceDate:ocrStart];
        CGImageRelease(image);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (cycleGeneration != self.translationGeneration || windowID != [self displayTargetWindowID] ||
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
                if (cycleGeneration != self.translationGeneration || windowID != [self displayTargetWindowID] ||
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
        @"captionWidth": @(self.captionWidthSlider.doubleValue),
        @"captionTextColor": FYAppearanceColorHex(self.captionTextColorWell.color),
        @"captionTextColorCustomized": @(self.captionTextColorCustomized),
        @"batchFontSize": @(self.batchFontSizeSlider.doubleValue),
        @"batchMaxWidth": @(self.batchWidthSlider.doubleValue),
        @"batchMaxHeight": @(self.batchHeightSlider.doubleValue),
        @"batchTextColor": FYAppearanceColorHex(self.batchTextColorWell.color),
        @"captionTheme": @(self.captionThemeControl.selectedSegment),
        @"stableText": @(self.stableTextCheckbox.state == NSControlStateValueOn),
        @"fastOCR": @(self.fastOCRCheckbox.state == NSControlStateValueOn),
        @"manualOCRScope": @(self.manualOCRScopeCheckbox.state == NSControlStateValueOn),
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
    self.captionWidthSlider.doubleValue = settings[@"captionWidth"] ? [settings[@"captionWidth"] doubleValue] : 900;
    self.captionThemeControl.selectedSegment = settings[@"captionTheme"] ? [settings[@"captionTheme"] integerValue] : 3;
    self.captionTextColorCustomized = [settings[@"captionTextColorCustomized"] boolValue];
    self.captionTextColorWell.color = self.captionTextColorCustomized
        ? FYAppearanceColorFromHex(settings[@"captionTextColor"], [self captionThemeTextColor])
        : [self captionThemeTextColor];
    self.batchFontSizeSlider.doubleValue = settings[@"batchFontSize"] ? [settings[@"batchFontSize"] doubleValue] : 16;
    self.batchWidthSlider.doubleValue = settings[@"batchMaxWidth"] ? [settings[@"batchMaxWidth"] doubleValue] : 560;
    self.batchHeightSlider.doubleValue = settings[@"batchMaxHeight"] ? [settings[@"batchMaxHeight"] doubleValue] : 330;
    self.batchTextColorWell.color = FYAppearanceColorFromHex(settings[@"batchTextColor"], FYAdventureColor(@"ink"));
    [self applyBatchAppearanceToLayoutEngine];
    self.stableTextCheckbox.state = settings[@"stableText"] ? ([settings[@"stableText"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff) : NSControlStateValueOn;
    self.fastOCRCheckbox.state = settings[@"fastOCR"] ? ([settings[@"fastOCR"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff) : NSControlStateValueOff;
    self.manualOCRScopeCheckbox.state=[settings[@"manualOCRScope"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
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
        // 启动时就丢掉旧版（纵坐标错误）的自动映射：不能修了算法还继续读旧结果。
        self.captureCardVideoRects = FYFilterCaptureMappings(savedRects, kCaptureCardMappingVersion);
    }
    if (self.inputSourceSegment == 1) {
        [self refreshCaptureDevices:nil];
        [self updateCaptureCardStatus];
    }
    [self updateWindowCardCopy];
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

    FYPlanInlineTranslations(items.count, self.inlineTranslationCache,
        ^NSString *(NSUInteger index) { return [self inlineTranslationCacheKeyForItem:items[index]]; },
        ^(NSUInteger index, BOOL hit) {
            FYTrace(trace, @"cache", @{@"route": @"inline", @"source": items[index].text ?: @"", @"cache_hit": @(hit)});
        }, translations, pendingIndexes, pendingKeys);
    for (NSNumber *index in pendingIndexes) { [pendingItems addObject:items[index.unsignedIntegerValue]]; }

    if (pendingItems.count == 0) {
        completion(translations, nil);
        return;
    }

    // 长短块分开翻译：短标签要短、正文要完整，缓存键也按类型区分，避免正文复用旧的短译文。
    NSMutableArray<OCRTextItem *> *longItems = [NSMutableArray array], *shortItems = [NSMutableArray array];
    NSMutableArray<NSNumber *> *longIndexes = [NSMutableArray array], *shortIndexes = [NSMutableArray array];
    NSMutableArray<NSString *> *longKeys = [NSMutableArray array], *shortKeys = [NSMutableArray array];
    FYPartitionInlineBatch(pendingItems, pendingIndexes, pendingKeys,
        ^BOOL(NSUInteger i) { return pendingItems[i].blockKind == InlineBlockKindLong; },
        shortItems, shortIndexes, shortKeys, longItems, longIndexes, longKeys);

    FYRunInlineBatches(shortItems.count > 0, longItems.count > 0, translations,
        ^(BOOL isLong, void (^done)(NSError *)) {
            [self translateInlineBatch:isLong ? longItems : shortItems
                              indexes:isLong ? longIndexes : shortIndexes
                                 keys:isLong ? longKeys : shortKeys
                         translations:translations long:isLong completion:done];
        }, completion);
}

// 翻译一批同类型的界面文字块，结果按 indexes 写回共享 translations 数组。
- (void)translateInlineBatch:(NSArray<OCRTextItem *> *)items
                     indexes:(NSArray<NSNumber *> *)indexes
                        keys:(NSArray<NSString *> *)keys
                translations:(NSMutableArray<NSString *> *)translations
                        long:(BOOL)isLong
                  completion:(void (^)(NSError *error))completion {
    NSString *numberedText = FYNumberedTranslationSource(items.count, ^NSString *(NSUInteger index) { return items[index].text; });

    NSString *source = SourceLanguageLabel(self.languageControl.selectedSegment);
    NSString *prompt = FYInlineBatchPrompt(source, isLong);
    NSInteger maxTokens = FYInlineBatchMaxTokens(items.count, isLong);

    [self translateTextRealtime:numberedText systemPrompt:prompt maxTokens:maxTokens completion:^(NSString *translated, NSError *error) {
        if (error) { completion(error); return; }

        NSArray<NSString *> *parsed = [self parseNumberedTranslations:translated expectedCount:items.count];
        completion(FYApplyInlineBatchResults(parsed, items.count, indexes, keys, translations,
            ^(NSString *value, NSString *key) { [self cacheInlineTranslation:value forKey:key]; }));
    }];
}

- (void)cacheInlineTranslation:(NSString *)value forKey:(NSString *)key {
    [[self inlineCache] storeValue:value forKey:key];
}

- (NSArray<NSString *> *)parseNumberedTranslations:(NSString *)text expectedCount:(NSUInteger)count {
    return FYParseNumberedTranslations(text, count);
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
    // 面板已经清掉，"上一帧渲染过的内容"也一起作废：否则几何复核会拿旧窗口/旧页面的
    // 译文按新几何重排出来（换窗口后闪现上一条译文）。
    self.lastInlineRenderedTranslations = nil;
    self.lastInlineRenderedItems = nil;
    self.lastInlineRenderGeometryToken = nil;
    // 边缘入口「还有 N 条译文」属于上一帧的场景，一起收掉。
    [self.inlineOverflowPanel close];
    self.inlineOverflowPanel = nil;
    self.inlineOverflowEntries = @[];
    self.inlineOverflowCount = 0;
    [self closeInlineOverflowChoice];
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
    [self closeExpandedInlineReadingCard];
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
    WindowItem *window = [self displayTargetWindowItem];
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
    // 记住这一帧的内容：几何变化（窗口移动、OBS 编辑器↔全屏投影）时用它按新几何重排，
    // 不再重新请求翻译。译文没变也可以只更新位置。
    if (translations.count > 0 && translations.count == items.count) {
        self.lastInlineRenderedTranslations = [translations copy];
        self.lastInlineRenderedItems = [items copy];
    }
    // 落位区域也进入内容指纹：窗口移动/缩放后即使页面文字没变，也必须重新布局，
    // 否则贴译会停在旧坐标上、跟原文错位（手动拖动过的位置同样要重新夹到可见区域内）。
    // 实际显示目标也进指纹：OBS 编辑器↔全屏投影是**另一个窗口**，同一段文字必须重排。
    NSString *identity = [[self inlineTranslationIdentityForTranslations:translations forItems:items]
                          stringByAppendingFormat:@"|t=%u|vp=%.1f,%.1f,%.1f,%.1f",
                          [self displayTargetWindowID],
                          NSMinX(windowFrame), NSMinY(windowFrame), NSWidth(windowFrame), NSHeight(windowFrame)];
    // 页面文字没变：只把已有面板重新显示出来，绝不 close / 重建。
    // （旧实现每帧 clear + 新建 NSPanel，这正是贴译一闪一闪的原因。）
    if (self.lastInlineTranslationKey && [self.lastInlineTranslationKey isEqualToString:identity] &&
        self.lastInlineLayoutResult) {
        // 内容没变也要推进展开态记账（上一帧的排版结果里还有没有这一块）。
        [self advanceExpandedReadingState];
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
            // 诊断要能看出"到底是什么放不下"：原文框、长卡尺寸、紧凑入口尺寸、逐候选被拒原因
            // （含冲突的是哪一块、交叠多厚），而不是一句"所有候选冲突"。
            FuyiDiagLog(@"    UNPLACEABLE <%@> srcFrame=(%.0f,%.0f,%.0f,%.0f) longCard=(%.0fx%.0f) compactEntry=(%.0fx%.0f) viewport=(%.0f,%.0f,%.0f,%.0f) reason=<%@> rejected=[%@]",
                        Shorten(item.text, 24),
                        placement.sourceFrame.origin.x, placement.sourceFrame.origin.y,
                        placement.sourceFrame.size.width, placement.sourceFrame.size.height,
                        placement.longCardSize.width, placement.longCardSize.height,
                        placement.compactEntrySize.width, placement.compactEntrySize.height,
                        windowFrame.origin.x, windowFrame.origin.y, NSWidth(windowFrame), NSHeight(windowFrame),
                        placement.reason,
                        [placement.rejectedCandidates componentsJoinedByString:@" | "] ?: @"");
            continue;
        }
        // 紧凑入口一律用长卡视图渲染：它可能是"多行但被判成短块"的段落降级出来的，
        // 用短贴片视图会拿不到 labelFrame（引擎没有给紧凑入口算短贴片排版）。
        BOOL wantsLongCard = item.blockKind == InlineBlockKindLong ||
                             placement.mode == FYInlineDisplayModeCompactEntry;
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
        // 诊断行里同时给出「OCR 归一化框」「换算出的原文框」「面板框」：
        // 现场错位时能一眼区分是坐标映射错、还是布局把面板放远了。
        // 紧凑入口额外打出长卡尺寸与入口尺寸，方便判断"是尺寸问题还是真的没地方"。
        if (placement.mode == FYInlineDisplayModeCompactEntry) {
            FuyiDiagLog(@"    COMPACT-ENTRY src=<%@> longCard=(%.0fx%.0f) entry=(%.0fx%.0f) anchor=%ld panel=(%.0f,%.0f,%.0f,%.0f) reason=%@",
                        Shorten(item.text, 24),
                        placement.longCardSize.width, placement.longCardSize.height,
                        placement.compactEntrySize.width, placement.compactEntrySize.height,
                        (long)placement.anchor,
                        panel.frame.origin.x, panel.frame.origin.y, NSWidth(panel.frame), NSHeight(panel.frame),
                        placement.reason);
        }
        FuyiDiagLog(@"    PANEL src=<%@> box=(%.3f,%.3f,%.3f,%.3f) srcFrame=(%.0f,%.0f,%.0f,%.0f) mode=%ld anchor=%ld panel=(%.0f,%.0f,%.0f,%.0f) reason=%@",
                    Shorten(item.text, 24),
                    item.boundingBox.origin.x, item.boundingBox.origin.y,
                    item.boundingBox.size.width, item.boundingBox.size.height,
                    placement.sourceFrame.origin.x, placement.sourceFrame.origin.y,
                    placement.sourceFrame.size.width, placement.sourceFrame.size.height,
                    (long)placement.mode, (long)placement.anchor,
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
    // 记下这次渲染用的几何上下文：文本没变但几何变了时，靠它判断必须重排。
    self.lastInlineRenderGeometryToken = self.lastDisplayGeometryToken ?: @"";
    // 极端降级：确实连折叠入口都贴不到原文旁边的块，在游戏显示区域边缘给一个总入口。
    [self updateInlineOverflowEntryWithPlacements:result.placements
                                            items:itemsByBlockID
                                         viewport:windowFrame
                                      unplaceable:unplaceable];
    // 展开态维护：读卡仍然属于当前页面就保持展开（并再次收起其它贴译）；
    // 连续两帧都见不到这一块才认为它不在当前场景了。
    // 长卡候选组合的逐条结果：现场日志直接区分"文字太长 / 可用空间不足 / 重复块假冲突"。
    for (FYInlinePlacement *placement in result.placements) {
        if (placement.variantDiagnostics.count == 0) { continue; }
        FuyiDiagLog(@"    CARD-VARIANTS <%@> 块=%@",
                    Shorten([placement.block.text stringByReplacingOccurrencesOfString:@"\n" withString:@" "], 20),
                    [placement.variantDiagnostics componentsJoinedByString:@" | "]);
    }
[self advanceExpandedReadingState];
    [self refreshOverlayVisibility:nil];
}

// ── 极端降级：「还有 N 条译文」 ───────────────────────────────────────────
// 只有确实存在"连折叠入口都放不下"的块时才出现；点击打开一个可选列表，
// 选中哪一条就把哪一条的完整译文就地展开。绝不静默丢弃、也不只写日志。
- (void)updateInlineOverflowEntryWithPlacements:(NSArray<FYInlinePlacement *> *)placements
                                          items:(NSDictionary<NSString *, OCRTextItem *> *)itemsByBlockID
                                       viewport:(NSRect)viewport
                                    unplaceable:(NSUInteger)unplaceable {
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (FYInlinePlacement *placement in placements) {
        if (placement.mode != FYInlineDisplayModeUnplaceable) { continue; }
        if (Trim(placement.translation).length == 0) { continue; }
        OCRTextItem *item = itemsByBlockID[placement.sourceBlockID];
        NSString *title = [FYInlineLayoutEngine shortTitleForBlockText:placement.block.text ?: @""];
        if (title.length == 0) { title = self.inlineLayoutEngine.foldedEntryFallbackTitle ?: @"这段译文"; }
        [entries addObject:@{@"blockID": placement.blockID ?: @"",
                             @"source": placement.block.text ?: @"",
                             @"translation": placement.translation ?: @"",
                             @"title": title,
                             @"item": item ?: (id)NSNull.null}];
    }
    self.inlineOverflowEntries = entries;
    self.inlineOverflowCount = entries.count;
    if (entries.count == 0 || self.inlineExpandedReadingPanel) {
        if (self.inlineOverflowPanel) { [self.inlineOverflowPanel orderOut:nil]; self.inlineOverflowPanel.ignoresMouseEvents = YES; }
        [self closeInlineOverflowChoice];
        return;
    }
    if (self.inlineOverflowPanel && self.inlineOverflowPanelCount != entries.count) {
        [self.inlineOverflowPanel close];
        self.inlineOverflowPanel = nil;   // 条数变了要重建（文案里有 N）
    }
    if (!self.inlineOverflowPanel) {
        [self buildInlineOverflowEntryForViewport:viewport];
        self.inlineOverflowPanelCount = entries.count;
    }
    if (!self.inlineOverflowPanel) { return; }
    [self positionInlineOverflowEntryInViewport:viewport];
    if (!self.inlineOverflowPanel.isVisible) { [self.inlineOverflowPanel orderFrontRegardless]; }
    self.inlineOverflowPanel.ignoresMouseEvents = NO;
}

// 边缘入口的尺寸与位置：按文字量尺寸，并**纳入统一避让** ——
// 固定左下角会压住别的贴译（现场已经压到「查看个人资料」那条）。
// 候选顺序：下左/下右/上左/上右/下中/上中/左中/右中；先选完全不遮挡的，
// 都不行时选遮挡面积最小的那个（仍然贴边、可点，不堆叠多个卡片）。
- (void)positionInlineOverflowEntryInViewport:(NSRect)viewport {
    NSPanel *panel = self.inlineOverflowPanel;
    if (!panel || NSWidth(viewport) < 2 || NSHeight(viewport) < 2) { return; }
    CGSize size = panel.frame.size;
    CGFloat margin = MAX((CGFloat)8, self.inlineLayoutEngine.viewportMargin);
    CGFloat minX = NSMinX(viewport) + margin, maxX = NSMaxX(viewport) - margin - size.width;
    CGFloat minY = NSMinY(viewport) + margin, maxY = NSMaxY(viewport) - margin - size.height;
    if (maxX < minX) { maxX = minX; }
    if (maxY < minY) { maxY = minY; }
    CGFloat midX = NSMidX(viewport) - size.width / 2.0;
    CGFloat midY = NSMidY(viewport) - size.height / 2.0;

    NSMutableArray<NSValue *> *obstacles = [NSMutableArray array];
    for (NSPanel *other in [self allInlineOverlayPanels]) {
        if (other == panel || !other.isVisible) { continue; }
        [obstacles addObject:[NSValue valueWithRect:other.frame]];
    }
    if (self.captionPanel && self.captionPanel.isVisible) { [obstacles addObject:[NSValue valueWithRect:self.captionPanel.frame]]; }
    for (FYInlinePlacement *placement in self.lastInlineLayoutResult.placements) {
        if (NSWidth(placement.translationFrame) > 2) { [obstacles addObject:[NSValue valueWithRect:placement.translationFrame]]; }
        if (!CGRectIsEmpty(placement.sourceFrame)) { [obstacles addObject:[NSValue valueWithRect:placement.sourceFrame]]; }
    }
    if (self.inlineExpandedReadingPanel) { [obstacles addObject:[NSValue valueWithRect:self.inlineExpandedReadingPanel.frame]]; }

    NSArray<NSValue *> *positions = @[
        [NSValue valueWithRect:NSMakeRect(minX, minY, size.width, size.height)],
        [NSValue valueWithRect:NSMakeRect(maxX, minY, size.width, size.height)],
        [NSValue valueWithRect:NSMakeRect(minX, maxY, size.width, size.height)],
        [NSValue valueWithRect:NSMakeRect(maxX, maxY, size.width, size.height)],
        [NSValue valueWithRect:NSMakeRect(midX, minY, size.width, size.height)],
        [NSValue valueWithRect:NSMakeRect(midX, maxY, size.width, size.height)],
        [NSValue valueWithRect:NSMakeRect(minX, midY, size.width, size.height)],
        [NSValue valueWithRect:NSMakeRect(maxX, midY, size.width, size.height)]
    ];
    NSRect best = positions.firstObject.rectValue;
    CGFloat bestOverlap = CGFLOAT_MAX;
    for (NSValue *value in positions) {
        NSRect candidate = NSIntegralRect(value.rectValue);
        CGFloat overlap = 0;
        for (NSValue *obstacle in obstacles) {
            CGRect intersection = CGRectIntersection(candidate, obstacle.rectValue);
            if (CGRectIsNull(intersection)) { continue; }
            overlap += intersection.size.width * intersection.size.height;
        }
        if (overlap < bestOverlap - 0.5) { bestOverlap = overlap; best = candidate; }
        if (overlap <= 0.5) { break; }   // 完全不遮挡：直接用
    }
    if (!NSEqualRects(panel.frame, best)) { [panel setFrame:best display:NO]; }
}

- (void)buildInlineOverflowEntryForViewport:(NSRect)viewport {
    NSString *title = [NSString stringWithFormat:@"还有 %lu 条译文 · 查看", (unsigned long)MAX((NSUInteger)1, self.inlineOverflowCount)];
    // 单行入口：不给 hint/action 行，尺寸就按这一行文字量。
    CGSize size = [self.inlineLayoutEngine foldedEntrySizeForViewport:viewport title:title hint:@"" action:@""];
    FYInlinePlacement *placement = [FYInlinePlacement new];
    placement.mode = FYInlineDisplayModeCompactEntry;
    placement.compactEntry = YES;
    placement.entryTitle = title;
    placement.entryHint = @"";
    placement.entryAction = @"";
    placement.panelPadding = 10;
    placement.cornerRadius = 8;
    placement.translationFrame = NSMakeRect(NSMinX(viewport) + 8, NSMinY(viewport) + 8, size.width, size.height);
    NSPanel *panel = [self inlineLongPanelForTranslation:@"" item:nil frame:placement.translationFrame placement:placement];
    if (!panel) { return; }
    panel.ignoresMouseEvents = NO;
    FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
    if ([card isKindOfClass:FYInlineLongCardView.class]) {
        __weak typeof(self) weakSelf = self;
        card.onClick = ^{ [weakSelf showInlineOverflowChooser]; };
        card.titleBarHeight = 0;   // 边缘入口不可拖动，避免和"点击选择"冲突
    }
    self.inlineOverflowPanel = panel;
}

- (void)showInlineOverflowChooser {
    [self closeInlineOverflowChoice];
    if (self.inlineOverflowEntries.count == 0) { return; }
    // 只有一条放不下时直接展开它，不再多一次"选择"步骤。
    if (self.inlineOverflowEntries.count == 1) {
        NSDictionary *only = self.inlineOverflowEntries.firstObject;
        OCRTextItem *item = [only[@"item"] isKindOfClass:OCRTextItem.class] ? only[@"item"] : nil;
        if (!item) {
            item = [[OCRTextItem alloc] init];
            item.text = only[@"source"] ?: @"";
            item.boundingBox = CGRectZero;
            item.lineBoxes = @[];
            item.blockKind = InlineBlockKindLong;
        }
        [self openFullInlineReadingCardForItem:item
                                   translation:only[@"translation"] ?: @""
                                 stableBlockID:only[@"blockID"] ?: @""];
        return;
    }
    NSRect viewport = NSZeroRect;
    BOOL hasViewport = [self inlinePlacementRect:&viewport reason:NULL];
    if (!hasViewport) {
        viewport = self.inlineOverflowPanel ? NSInsetRect(self.inlineOverflowPanel.frame, -60, -60) : NSMakeRect(0, 0, 480, 320);
    }
    CGFloat width = MIN((CGFloat)420, MAX((CGFloat)280, NSWidth(viewport) * 0.5));
    CGFloat rowHeight = 34;
    CGFloat rowSpacing = 6;
    CGFloat footerHeight = 40;
    CGFloat headerHeight = 30;
    CGFloat visibleRows = MIN((CGFloat)self.inlineOverflowEntries.count, 4);
    CGFloat listHeight = MAX(rowHeight, visibleRows * rowHeight + (visibleRows - 1) * rowSpacing);
    CGFloat height = MIN(MAX((CGFloat)160, NSHeight(viewport) - 24), headerHeight + listHeight + footerHeight + 24);
    CGFloat x = MIN(MAX(NSMidX(viewport) - width / 2, NSMinX(viewport) + 10), NSMaxX(viewport) - width - 10);
    CGFloat y = MIN(MAX(NSMidY(viewport) - height / 2, NSMinY(viewport) + 10), NSMaxY(viewport) - height - 10);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSIntegralRect(NSMakeRect(x, y, width, height))
                                                styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.opaque = NO;
    panel.backgroundColor = NSColor.clearColor;
    panel.hasShadow = YES;
    panel.level = NSPopUpMenuWindowLevel + 1;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    CGFloat inset = 12;
    NSFont *choiceFont = [self.inlineLayoutEngine compactEntryFont];
    NSTextField *header = [self label:@"选择要读的译文" font:choiceFont color:[self inlinePanelTextColor]];
    header.frame = NSMakeRect(inset, height - inset - headerHeight + 6, width - inset * 2, headerHeight - 6);
    header.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [container addSubview:header];

    // 列表：**显式给出 documentView 的尺寸**并逐个摆放按钮 —— 过去只把 NSStackView 当
    // documentView、不给尺寸/约束，实测 documentView 为 0×0、按钮被压成 14×12 看不见。
    CGFloat scrollY = inset + footerHeight;
    CGFloat scrollHeight = MAX((CGFloat)rowHeight, height - inset - headerHeight - footerHeight - inset);
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(inset, scrollY, width - inset * 2, scrollHeight)];
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    CGFloat contentWidth = MAX((CGFloat)120, width - inset * 2 - 2);
    CGFloat documentHeight = MAX(scrollHeight, self.inlineOverflowEntries.count * rowHeight +
                                              MAX(0, (NSInteger)self.inlineOverflowEntries.count - 1) * rowSpacing);
    // 用翻转文档视图：第 1 条在 y=0（顶部），配合下面的 scrollToPoint 保证"默认从第一条显示"。
    FlippedDocumentView *document = [[FlippedDocumentView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth, documentHeight)];
    for (NSUInteger index = 0; index < self.inlineOverflowEntries.count; index++) {
        NSDictionary *entry = self.inlineOverflowEntries[index];
        NSButton *button = [NSButton buttonWithTitle:[self overflowRowTitleForEntry:entry]
                                              target:self
                                              action:@selector(openInlineOverflowRow:)];
        button.tag = (NSInteger)index;
        button.bezelStyle = NSBezelStyleRounded;
        button.alignment = NSTextAlignmentLeft;
        button.font = [NSFont systemFontOfSize:12.5];
        button.lineBreakMode = NSLineBreakByTruncatingTail;
        // 翻转文档视图：第 1 条 y=0，往下依次排列（默认就是顶部=第一条）。
        CGFloat y = index * (rowHeight + rowSpacing);
        button.frame = NSMakeRect(0, y, contentWidth, rowHeight);
        button.autoresizingMask = NSViewWidthSizable;
        [document addSubview:button];
    }
    scroll.documentView = document;
    [container addSubview:scroll];

    // 可见的关闭入口（不再只靠 Esc）。
    NSButton *closeButton = [NSButton buttonWithTitle:@"关闭" target:self action:@selector(closeInlineOverflowChoiceAction:)];
    closeButton.bezelStyle = NSBezelStyleRounded;
    closeButton.font = [NSFont systemFontOfSize:12];
    closeButton.frame = NSMakeRect(width - inset - 76, inset - 2, 76, 26);
    closeButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [container addSubview:closeButton];
    NSTextField *hint = [self mutedLabel:@"Esc 也可以关闭"];
    hint.frame = NSMakeRect(inset, inset, MAX((CGFloat)80, width - inset * 2 - 84), 20);
    hint.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [container addSubview:hint];

    [self applyInlineChromeToContent:container cornerRadius:14];
    panel.contentView = container;
    [panel setContentSize:NSMakeSize(width, height)];
    self.inlineOverflowChoicePanel = panel;
    [panel orderFrontRegardless];
    // 首次打开固定从第一条开始（不能把"文档视图默认原点"当第一条）。
    [scroll layoutSubtreeIfNeeded];
    [scroll.contentView scrollToPoint:NSMakePoint(0, 0)];
    [scroll reflectScrolledClipView:scroll.contentView];
    if (!self.inlineOverflowChoiceKeyMonitor) {
        __weak typeof(self) weakSelf = self;
        self.inlineOverflowChoiceKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
            if (event.keyCode != 53) { return event; }
            [weakSelf closeInlineOverflowChoice];
            return nil;
        }];
    }
}

- (void)closeInlineOverflowChoiceAction:(id)sender {
    [self closeInlineOverflowChoice];
}

- (NSString *)overflowRowTitleForEntry:(NSDictionary *)entry {
    NSString *title = entry[@"title"] ?: @"";
    NSString *source = [entry[@"source"] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet].firstObject ?: @"";
    source = Shorten(source, 22);
    return source.length > 0 ? [NSString stringWithFormat:@"%@　（%@）", title, source] : title;
}

- (void)openInlineOverflowRow:(NSButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || (NSUInteger)index >= self.inlineOverflowEntries.count) { return; }
    NSDictionary *entry = self.inlineOverflowEntries[index];
    id item = entry[@"item"];
    OCRTextItem *textItem = [item isKindOfClass:OCRTextItem.class] ? (OCRTextItem *)item : nil;
    if (!textItem) {
        textItem = [[OCRTextItem alloc] init];
        textItem.text = entry[@"source"] ?: @"";
        textItem.boundingBox = CGRectZero;
        textItem.lineBoxes = @[];
        textItem.blockKind = InlineBlockKindLong;
    }
    [self closeInlineOverflowChoice];
    [self openFullInlineReadingCardForItem:textItem
                               translation:entry[@"translation"] ?: @""
                             stableBlockID:entry[@"blockID"] ?: @""];
}

- (void)closeInlineOverflowChoice {
    if (self.inlineOverflowChoiceKeyMonitor) {
        [NSEvent removeMonitor:self.inlineOverflowChoiceKeyMonitor];
        self.inlineOverflowChoiceKeyMonitor = nil;
    }
    [self.inlineOverflowChoicePanel close];
    self.inlineOverflowChoicePanel = nil;
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
static NSString *InlineNormalizeTranslationParagraphs(NSString *text) { return FYInlineNormalizeTranslationParagraphs(text); }

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
    return FYInlineLongCardLineHeight(font.ascender, font.descender, font.leading);
}
// 长卡最小可读高度：标题 + 内边距 + 三行正文。
- (CGFloat)inlineLongCardMinimumHeight {
    return FYInlineLongCardMinimumHeight([self inlineLongCardBodyLineHeight]);
}
// 长卡正文视口高度（给定卡片高度）。
- (CGFloat)inlineLongCardBodyViewportForHeight:(CGFloat)cardHeight {
    return FYInlineLongCardBodyViewport(cardHeight);
}

- (void)applyInlineLongCardBody:(NSString *)translation toLabel:(NSTextField *)label cardWidth:(CGFloat)cardWidth {
    [self applyInlineLongCardBody:translation toLabel:label cardWidth:cardWidth placement:nil];
}

- (void)applyInlineLongCardBody:(NSString *)translation
                        toLabel:(NSTextField *)label
                       cardWidth:(CGFloat)cardWidth
                       placement:(FYInlinePlacement *)placement {
    CGFloat padding = placement.panelPadding > 0 ? placement.panelPadding : 18;
    FYApplyInlineLongCardBody(translation, label, cardWidth, padding,
                             placement.font ?: [self inlineLongCardBodyFont],
                             placement.paragraphStyle ?: [self inlineLongCardBodyStyle], [self inlinePanelTextColor]);
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
    // 紧凑入口的宽度就是引擎量出来的宽度（过去这里硬抬到 160，label 按 140 排版而面板只有 120，
    // 测量与绘制口径不一致）；长卡仍保留 160 的可读下限。
    NSSize cardSize = FYInlineLongCardSize(size, compact);
    CGFloat cardWidth = cardSize.width;
    CGFloat cardHeight = cardSize.height;
    FYInlineLongCardView *card = [[FYInlineLongCardView alloc] initWithFrame:NSMakeRect(0, 0, cardWidth, cardHeight)];
    card.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    card.showsSelectedBadge = selected;
    card.compactEntry = compact;
    if (compact) {
        [self applyInlineCompactEntryChromeToContent:card cornerRadius:8];
    } else {
        [self applyInlineChromeToContent:card cornerRadius:12];
    }

    if (compact) {
        // 折叠入口：块标题 / 收起原因 / 「点击展开 ▾」三行，整卡可点。
        // 三行文案与尺寸都来自布局引擎的测量（同一份字体与文案），所以提示不会被截断，
        // 也不会出现"只有悬停才看得到原因"的情况。
        card.toolTip = @"点击展开完整译文（展开后：卡片上的「收起」、再点一次贴片、或 Esc 都能收起）";
        NSString *title = placement.entryTitle.length > 0 ? placement.entryTitle
            : (self.inlineLayoutEngine.foldedEntryFallbackTitle ?: @"这段译文");
        // nil 才回退默认文案；空字符串表示"这一行不要"（单行总入口）。
        NSString *hint = placement.entryHint != nil ? placement.entryHint
            : (self.inlineLayoutEngine.foldedEntryHintTooLong ?: @"文本过长，已收起");
        NSString *action = placement.entryAction != nil ? placement.entryAction
            : (self.inlineLayoutEngine.compactEntryTitle ?: @"点击展开");
        CGFloat padding = MAX((CGFloat)6, self.inlineLayoutEngine.compactEntryHorizontalPadding);
        FYInstallInlineFoldedEntry(card, cardWidth, padding, title, hint, action,
            [self.inlineLayoutEngine compactEntryFont], [self.inlineLayoutEngine foldedEntryHintFont],
            [self inlinePanelTitleColor], [self inlinePanelTextColor], [self inlinePanelTextColor],
            ^NSTextField *(NSString *text, NSFont *font, NSColor *color) {
                return [self inlineCompactEntryLabel:text font:font color:color];
            });
        return card;
    }
    card.toolTip = @"点击查看原文和语法";

    // 内边距与标题带由布局引擎给出：与测量用的是同一组常量，避免“测出来”和“画出来”不一致。
    CGFloat padding = placement.panelPadding > 0 ? placement.panelPadding : 18;
    // 紧凑修饰（布局为省空间去掉标题带）时不再画标题和分隔线，正文从 padding 开始 ——
    // 否则标题会和正文叠在一起。
    BOOL showsTitleBand = placement.titleBandHeight > 0.5;
    CGFloat titleBand = 24;
    // 注意：FYInlineLongCardView 是 flipped（y=0 在顶部），所以标题在 padding 处、正文在标题下方。
    // 顶部小标题：未选中时不显示「已选中」，避免把预览状态写死。
    // 普通贴译长卡仍是「中文译文」；只有"点入口展开出来的阅读卡"顶部换成这一块自己的标题
    // （取不到可靠标题才用「这段译文」）—— 与折叠入口的标题口径一致。
    NSString *cardTitle = @"中文译文";
    if (placement.expandedReading) {
        cardTitle = placement.entryTitle.length > 0 ? placement.entryTitle
            : (placement.block ? ([FYInlineLayoutEngine shortTitleForBlockText:placement.block.text] ?: nil) : nil);
        if (cardTitle.length == 0) { cardTitle = self.inlineLayoutEngine.foldedEntryFallbackTitle ?: @"这段译文"; }
    }
    if (showsTitleBand) {
        NSTextField *title = [self label:cardTitle font:[self inlinePanelFontOfSize:14 weight:NSFontWeightSemibold] color:[self inlinePanelTitleColor]];
        NSTextField *badge = [self label:@"已选中" font:[self inlinePanelFontOfSize:13] color:[self inlinePanelTextColor]];
        FYInstallInlineLongCardHeader(card, cardWidth, padding, titleBand, selected, title, badge,
                                     FYAdventureColor(@"mint"), [FYAdventureColor(@"rim") colorWithAlphaComponent:0.95]);
    }

    // 正文：清晰内边距 + 舒适行距；超长时在卡内滚动。
    NSRect bodyFrame = FYInlineLongCardBodyFrame(cardWidth, cardHeight, padding, placement.titleBandHeight);
    CGFloat textWidth = NSWidth(bodyFrame);
    NSScrollView *scroll = FYCreateInlineLongCardBodyScroll(translation,
        bodyFrame, cardWidth, padding,
        placement.font ?: [self inlineLongCardBodyFont],
        placement.paragraphStyle ?: [self inlineLongCardBodyStyle], [self inlinePanelTextColor]);
    [card addSubview:scroll];
    // 底部提示：明确"其他贴译已暂时隐藏"和"Esc 收起"，不必靠猜。
    NSTextField *footer = [self label:@"其他贴译已暂时隐藏　·　Esc 收起"
                                 font:[self.inlineLayoutEngine foldedEntryHintFont]
                                color:self.uiMuted];
    footer.lineBreakMode = NSLineBreakByTruncatingTail;
    FYInstallInlineLongCardFooter(card, footer, padding, cardHeight, textWidth);
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
    BOOL compactCopyChanged = NO;
    if (compact && [existing isKindOfClass:FYInlineLongCardView.class]) {
        FYInlineLongCardView *entryCard = (FYInlineLongCardView *)existing;
        NSString *expectedHint = placement.entryHint ?: @"";
        if (entryCard.foldedEntryHintLabel && expectedHint.length > 0 &&
            ![entryCard.foldedEntryHintLabel.stringValue isEqualToString:expectedHint]) {
            compactCopyChanged = YES;
        }
    }
    if (!compactCopyChanged && [existing isKindOfClass:FYInlineLongCardView.class] && NSEqualSizes(existing.frame.size, frame.size) &&
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
            // 已经是这块的展开卡 → 再点一次收起（不需要去找 Esc）。
            NSString *openBlockID = weakSelf.inlineExpandedReadingBlockID;
            NSString *thisBlockID = stableBlockID.length > 0 ? stableBlockID : snapshot.blockID;
            if (weakSelf.inlineExpandedReadingPanel && openBlockID.length > 0 &&
                [openBlockID isEqualToString:thisBlockID]) {
                [weakSelf closeExpandedInlineReadingCard];
                return;
            }
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
    // 优先贴着原文展开：原文下方放得下就放下方，否则上方；都不行才退回显示区域居中。
    // 无论哪种都必须完整落在**游戏显示区域**内（不落到 OBS 控制区、不出画面）。
    CGRect sourceFrame = CGRectZero;
    BOOL hasSourceFrame = NO;
    for (FYInlinePlacement *known in self.lastInlineLayoutResult.placements) {
        if (stableBlockID.length > 0 && [known.blockID isEqualToString:stableBlockID] &&
            !CGRectIsEmpty(known.sourceFrame)) {
            sourceFrame = known.sourceFrame;
            hasSourceFrame = YES;
            break;
        }
    }
    CGFloat minX = NSMinX(placement) + 12, maxX = NSMaxX(placement) - width - 12;
    CGFloat minY = NSMinY(placement) + 12, maxY = NSMaxY(placement) - height - 12;
    CGFloat x = MIN(MAX(NSMidX(placement) - width / 2.0, minX), MAX(minX, maxX));
    CGFloat y = MIN(MAX(NSMidY(placement) - height / 2.0, minY), MAX(minY, maxY));
    if (hasSourceFrame) {
        x = NSMinX(sourceFrame);
        CGFloat below = NSMinY(sourceFrame) - height - 8;
        CGFloat above = NSMaxY(sourceFrame) + 8;
        if (below >= minY) { y = below; }
        else if (above <= maxY) { y = above; }
    }
    x = MIN(MAX(x, minX), MAX(minX, maxX));
    y = MIN(MAX(y, minY), MAX(minY, maxY));
    FYInlinePlacement *cardPlacement = [self inlinePlacementForLongCardFrame:NSIntegralRect(NSMakeRect(x, y, width, height))
                                                                 translation:translation];
    cardPlacement.expandedReading = YES;
    cardPlacement.entryTitle = [FYInlineLayoutEngine shortTitleForBlockText:item.text ?: @""]
        ?: (self.inlineLayoutEngine.foldedEntryFallbackTitle ?: @"这段译文");
    if (stableBlockID.length > 0) { cardPlacement.blockID = stableBlockID; }
    NSPanel *panel = [self inlineLongPanelForTranslation:translation item:item
                                                    frame:cardPlacement.translationFrame
                                                placement:cardPlacement];
    if (!panel) { return; }
    self.inlineExpandedReadingPanel = panel;
    self.inlineExpandedReadingBlockID = cardPlacement.blockID ?: stableBlockID;
    self.inlineExpandedMissingFrames = 0;
    // 展开时临时隐藏其它贴译与折叠入口：只留这一块，避免阅读卡被一堆浮层盖住。
    [self hideOtherInlinePanelsForExpandedReading:panel];
    // 可见的收起入口：只有 Esc 的话用户会认为“展开后收不回去”。
    if ([panel.contentView isKindOfClass:FYInlineLongCardView.class]) {
        FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
        __weak typeof(self) weakSelf = self;
        card.onCollapse = ^{ [weakSelf closeExpandedInlineReadingCard]; };
        [card installCollapseControl];
    }
    // 底部提示与正文让位：展开卡才显示"其他贴译已暂时隐藏 / Esc 收起"。
    if ([panel.contentView isKindOfClass:FYInlineLongCardView.class]) {
        FYInlineLongCardView *reading = (FYInlineLongCardView *)panel.contentView;
        if (reading.expandedFooterLabel) {
            reading.expandedFooterLabel.hidden = NO;
            for (NSView *child in reading.subviews) {
                if (![child isKindOfClass:NSScrollView.class]) { continue; }
                NSRect scrollFrame = child.frame;
                scrollFrame.size.height = MAX((CGFloat)40, NSHeight(scrollFrame) - 16);
                child.frame = scrollFrame;
            }
        }
    }
    // 阅读卡沿用现有标题栏拖动（正文滚动与按钮点击不误触拖动）。
    [self wireInlinePanelDrag:panel placement:cardPlacement];
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

// 按最新映射把展开卡放回可见区域内（尺寸不变，只调整位置；不改内容、不重新翻译）。
- (void)repositionExpandedInlineReadingCardInRect:(NSRect)viewport {
    NSPanel *panel = self.inlineExpandedReadingPanel;
    if (!panel || NSWidth(viewport) < 2 || NSHeight(viewport) < 2) { return; }
    NSRect frame = panel.frame;
    CGFloat width = MIN(NSWidth(frame), MAX((CGFloat)240, NSWidth(viewport) - 24));
    CGFloat height = MIN(NSHeight(frame), MAX((CGFloat)180, NSHeight(viewport) - 24));
    CGFloat x = MIN(MAX(NSMidX(frame) - width / 2.0, NSMinX(viewport) + 12), MAX(NSMinX(viewport) + 12, NSMaxX(viewport) - width - 12));
    CGFloat y = MIN(MAX(NSMidY(frame) - height / 2.0, NSMinY(viewport) + 12), MAX(NSMinY(viewport) + 12, NSMaxY(viewport) - height - 12));
    NSRect target = NSIntegralRect(NSMakeRect(x, y, width, height));
    if (!NSEqualRects(panel.frame, target)) { [panel setFrame:target display:YES]; }
}

// 展开态记账：块还在当前排版结果里就清零，连续 2 帧都不在才收起。
// 必须在所有 dedup 短路**之外**也有一次调用 —— 内容没变/节流短路时不会再走渲染路径，
// 否则"这一块已经在页面上消失"会永远停在第一帧，阅读卡留在画面上不走。
- (void)advanceExpandedReadingState {
    if (!self.inlineExpandedReadingPanel) { return; }
    NSString *blockID = self.inlineExpandedReadingBlockID ?: @"";
    BOOL present = NO;
    for (FYInlinePlacement *placement in self.lastInlineLayoutResult.placements) {
        if (blockID.length > 0 && [placement.blockID isEqualToString:blockID]) { present = YES; break; }
    }
    if (present) {
        self.inlineExpandedMissingFrames = 0;
    } else if (++self.inlineExpandedMissingFrames >= 2) {
        [self closeExpandedInlineReadingCard];
        return;
    }
    if (self.inlineExpandedReadingPanel) {
        [self hideOtherInlinePanelsForExpandedReading:self.inlineExpandedReadingPanel];
    }
}

- (void)closeExpandedInlineReadingCard {
    if (self.inlineExpandedReadingKeyMonitor) {
        [NSEvent removeMonitor:self.inlineExpandedReadingKeyMonitor];
        self.inlineExpandedReadingKeyMonitor = nil;
    }
    [self.inlineExpandedReadingPanel close];
    self.inlineExpandedReadingPanel = nil;
    self.inlineExpandedReadingBlockID = nil;
    self.inlineExpandedMissingFrames = 0;
    // 恢复：用**当前这一帧**的排版结果把该显示的贴译放回来（不复活换页前的旧面板）。
    [self restoreOtherInlinePanelsAfterExpandedReading];
}

// 展开期间：把其它贴译面板与折叠入口收起来，并且不再接收鼠标事件（不能挡住游戏点击）。
- (void)hideOtherInlinePanelsForExpandedReading:(NSPanel *)expandedPanel {
    for (NSPanel *panel in [self allInlineOverlayPanels]) {
        if (panel == expandedPanel) { continue; }
        if (panel.isVisible) { [panel orderOut:nil]; }
        panel.ignoresMouseEvents = YES;
    }
}

// 当前帧里仍然存在的贴译面板（按稳定块身份判断），用于"恢复当前页面状态"。
- (NSArray<NSPanel *> *)inlinePanelsPresentInCurrentLayout {
    NSMutableSet<NSString *> *liveIDs = [NSMutableSet set];
    for (FYInlinePlacement *placement in self.lastInlineLayoutResult.placements) {
        if (placement.mode == FYInlineDisplayModeUnplaceable) { continue; }
        if (placement.translationFrame.size.width < 2) { continue; }
        if (placement.blockID.length > 0) { [liveIDs addObject:placement.blockID]; }
    }
    NSMutableArray<NSPanel *> *panels = [NSMutableArray array];
    for (NSPanel *panel in [self allInlineOverlayPanels]) {
        if (panel == self.inlineExpandedReadingPanel) { continue; }
        if (panel.identifier.length > 0 && [liveIDs containsObject:panel.identifier]) { [panels addObject:panel]; }
    }
    return panels;
}

- (NSArray<NSPanel *> *)allInlineOverlayPanels {
    NSMutableArray<NSPanel *> *panels = [[self.inlineTranslationPanels arrayByAddingObjectsFromArray:self.inlineLongCardPanels] mutableCopy];
    if (self.inlineOverflowPanel) { [panels addObject:self.inlineOverflowPanel]; }
    if (self.inlineOverflowChoicePanel) { [panels addObject:self.inlineOverflowChoicePanel]; }
    return panels;
}

- (void)restoreOtherInlinePanelsAfterExpandedReading {
    for (NSPanel *panel in [self inlinePanelsPresentInCurrentLayout]) {
        panel.ignoresMouseEvents = NO;
    }
    if (self.inlineOverflowPanel) {
        self.inlineOverflowPanel.ignoresMouseEvents = NO;
        if (self.inlineOverflowCount > 0) { [self.inlineOverflowPanel orderFrontRegardless]; }
    }
    [self refreshOverlayVisibility:nil];
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
    return [FYGeometryManager frameForNormalizedBox:item.boundingBox inViewport:windowFrame];
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

- (NSColor *)captionThemeTextColor {
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

- (NSColor *)captionTextColor {
    return self.captionTextColorCustomized && self.captionTextColorWell
        ? self.captionTextColorWell.color : [self captionThemeTextColor];
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
// 多个"像投影"的候选分级：能唯一确定才返回一个，否则返回空数组（= 交给调用方提示重选）。


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

- (void)applyBatchAppearanceToLayoutEngine {
    FYInlineLayoutEngine *engine = [self inlineLayoutEngine];
    CGFloat size = self.batchFontSizeSlider ? self.batchFontSizeSlider.doubleValue : 16;
    CGFloat width = self.batchWidthSlider ? self.batchWidthSlider.doubleValue : 560;
    CGFloat height = self.batchHeightSlider ? self.batchHeightSlider.doubleValue : 330;
    engine.shortFontSize = size;
    engine.coverFontSize = size + 1;
    engine.longBodyFontSize = size + 3;
    engine.minimumLongBodyFontSize = MAX((CGFloat)12, size - 1);
    engine.longTitleFontSize = MAX((CGFloat)12, size - 2);
    engine.compactEntryFontSize = MAX((CGFloat)11, size - 3);
    engine.cardMaxWidth = width;
    engine.shortMaxWidth = width * 360.0 / 560.0;
    engine.cardMaxHeight = height;
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
    return self.batchTextColorWell ? self.batchTextColorWell.color : FYAdventureColor(@"ink");
}
- (NSColor *)inlinePanelTitleColor {
    return [[self inlinePanelTextColor] colorWithAlphaComponent:0.82];
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

// 折叠入口压在原文上：可读性靠**文字颜色 + 描边 + 阴影**，
// 底不透明度一律跟随用户现有设置（不强制高不透明，否则用户调低透明度时它几乎不变）。
- (void)applyInlineCompactEntryChromeToContent:(NSView *)content cornerRadius:(CGFloat)cornerRadius {
    [self applyInlineChromeToContent:content cornerRadius:cornerRadius];
    content.layer.backgroundColor = [self inlinePanelFillColor].CGColor;
    content.layer.borderWidth = 1.8;
    content.layer.borderColor = [self inlinePanelBorderColor].CGColor;
    content.layer.shadowOpacity = 0.45;
    content.layer.shadowRadius = 6;
}

// 压在原文上的小字：墨色 + 浅色描边阴影，低不透明度下也能读清（不改用户透明度设置）。
- (NSTextField *)inlineCompactEntryLabel:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [self label:text font:font color:color];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [[NSColor whiteColor] colorWithAlphaComponent:0.85];
    shadow.shadowBlurRadius = 2.5;
    shadow.shadowOffset = NSMakeSize(0, -1);
    label.shadow = shadow;
    return label;
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
    content.dragHintColor = FYAdventureColor(@"ink");
    content.normalBorderColor = FYAdventureColor(@"line");
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
    // Capturing our own app does not prove that screen-recording access works.
    if (FYWindowOwnerIsYiya([self selectedWindowItem].effectiveOwnerName) || [self selectedWindowOwnerPID] == getpid()) { return NO; }

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

- (WindowItem *)windowItemForWindowID:(uint32_t)windowID {
    if (windowID == 0) { return nil; }
    for (WindowItem *item in self.windows) {
        if (item.windowID == windowID) { return item; }
    }
    return nil;
}

- (WindowItem *)selectedWindowItem {
    return [self windowItemForWindowID:[self selectedWindowID]];
}

#pragma mark - 实际显示目标（用户选择 vs 画面所在窗口）

// 按 **窗口 ID** 查这扇窗口此刻的真实边界（点坐标、屏幕左上角原点）。
// 下拉列表里的 bounds 是刷新那一刻的快照，窗口移动/缩放/OBS 内部预览变化后就会过期；
// 映射与布局一律走这里，查不到时才退回快照。测试可以覆盖它来模拟窗口移动。
- (BOOL)liveBoundsForWindowID:(uint32_t)windowID outBounds:(CGRect *)outBounds {
    return [[self windowManager] liveBoundsForWindowID:windowID outBounds:outBounds];
}

// 同进程的窗口里，哪些"可能承载游戏画面"：
// 普通层、够大、而且不是应用的设置/属性/统计面板。


// 解析"当前实际承载游戏画面的窗口"。
// 返回 0 表示**确定不了**（原窗口已关闭 / 多个投影无法区分）：上层必须隐藏旧贴译并提示重新选择，
// 绝不随便挑一扇窗口继续贴。
//   · 选中窗口仍在屏幕上：它前面的同进程画面窗口明显更大时跟随它（F11 全屏投影/全屏预览）；
//     应用自己的设置弹窗更小，不会被当成分身目标。
//   · 选中窗口不在屏幕上（被投影接管/最小化）：唯一的同进程画面窗口才跟随；
//     有多个时要求明显只有一个"主画面"，否则视为歧义。
- (uint32_t)resolveDisplayTargetWindowIDInWindowList:(NSArray<NSDictionary *> *)windowList
                                           ambiguous:(BOOL *)outAmbiguous
                                                note:(NSString **)outNote {
    return [[self windowManager] resolveDisplayTargetWindowIDInWindowList:windowList selectedID:[self selectedWindowID] ownerPID:[self selectedWindowOwnerPID] ambiguous:outAmbiguous note:outNote];
}

// 实际显示目标窗口 ID。还没解析过时沿用用户选择（离线夹具/首帧），
// 解析过之后以解析结果为准：0 = 确定不了，上层必须提示而不是猜。
- (uint32_t)displayTargetWindowID {
    if (!self.displayTargetResolved) { return [self selectedWindowID]; }
    if (self.displayTargetAmbiguous) { return 0; }
    return self.resolvedDisplayTargetID;
}

// 实际显示目标窗口（带最新几何）。解析不到时退回用户选择，保证"看不出来时行为不变"。
- (WindowItem *)displayTargetWindowItem {
    uint32_t windowID = [self displayTargetWindowID];
    if (windowID == 0) { return nil; }
    // 解析出来的目标可能还没进下拉列表（刚出现的全屏投影）。**必须**返回 ID 与解析目标一致的
    // 对象：过去退回 selectedWindowItem（旧 ID），后续 appKitFrameForWindowItem: 按旧 ID 查坐标，
    // 于是"解析到 9602、却拿到 9601 的框"。
    WindowItem *item = [self windowItemForWindowID:windowID];
    if (!item) { item = [self windowItemForResolvedTargetID:windowID]; }
    if (!item) {
        // 兜底只允许"解析目标 == 用户选择的那个窗口"（ID 一致，是同一扇窗，不算冒充）。
        WindowItem *selectedItem = [self selectedWindowItem];
        if (selectedItem && selectedItem.windowID == windowID) { item = selectedItem; }
    }
    CGRect liveBounds = CGRectZero;
    if ([self liveBoundsForWindowID:windowID outBounds:&liveBounds]) {
        if (!item) {
            item = [[WindowItem alloc] init];
            item.windowID = windowID;
        }
        item.bounds = liveBounds;
    }
    if (item && item.windowID != windowID) { return nil; }   // 兜底：ID 对不上就不使用
    return item;
}

// 目标窗口不在下拉列表时，为这个 ID 现造一个等价对象（查当前窗口列表，含画面外的窗口）。
- (WindowItem *)windowItemForResolvedTargetID:(uint32_t)windowID {
    return [[self windowManager] windowItemForID:windowID];
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

// 一律用**实时边界**换算：窗口移动/缩放后不能继续用下拉列表里的旧快照。
- (NSRect)appKitFrameForWindowItem:(WindowItem *)item {
    CGRect bounds = item.bounds;
    CGRect liveBounds = CGRectZero;
    if ([self liveBoundsForWindowID:item.windowID outBounds:&liveBounds]) { bounds = liveBounds; }
    return [FYGeometryManager appKitFrameForQuartzBounds:bounds mainScreenTop:NSMaxY(NSScreen.mainScreen.frame)];
}

#pragma mark - 采集卡坐标映射

#pragma mark - 采集卡画面区域：按内容自动定位

// 采集卡画面区域的映射版本。
//   1 = 旧版实现：bestRect.origin.y（像素网格、从图像顶部算）被直接加到 AppKit 窗口底部，
//       漏了纵坐标翻转 → 映射整体下移（OBS 预览靠上时，贴译会落到下方控制区）。
//   2 = 当前实现：网格坐标按图像顶部换算回 AppKit 的「距底部」。
// 读取映射时必须校验版本：修了算法也不能继续读取旧版存下的错误结果。
static const NSInteger kCaptureCardMappingVersion = 2;
// 无法取样时的哨兵值：与「相关性很差（负数）」区分开，避免把“完全对不上”当成“测不了”。
static const double kCaptureCardMappingScoreUnavailable = -99;

// 生成「当前采集帧模板」与「目标窗口截屏场景」两份灰度网格（都已零均值/单位方差归一化）。
// 网格来自 FYGrayGridFromImage：**第 0 行是图像顶部**（row-major、自上而下）。
// 调用方负责 free 两个网格；返回 NO 时不产生需要释放的内存。
- (BOOL)buildCaptureGridsWithFrame:(double **)outTempl templateW:(size_t *)outTW templateH:(size_t *)outTH
                             scene:(double **)outScene sceneW:(size_t *)outWW sceneH:(size_t *)outWH
                       videoAspect:(CGFloat *)outAspect
                        sceneWidth:(size_t)sceneWidth
                         forWindow:(WindowItem *)window
                            reason:(NSString **)outReason {
    if (outTempl) { *outTempl = NULL; }
    if (outScene) { *outScene = NULL; }
    CGSize frameSize = CGSizeZero;
    if (![self.captureCardInput latestFrameSize:&frameSize]) {
        if (outReason) { *outReason = @"采集卡暂无画面"; }
        return NO;
    }
    if (![self hasUsableScreenCaptureAccess]) {
        if (outReason) { *outReason = @"需要屏幕录制权限才能自动定位游戏画面"; }
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
    return FYBuildCaptureGrids(frameImage, windowImage, frameSize,
        ^NSRect { return [self appKitFrameForWindowItem:window]; }, sceneWidth,
        outTempl, outTW, outTH, outScene, outWW, outWH, outAspect, outReason);
}

// 自动定位：在目标窗口的**实际截屏**里按内容找出采集画面所在区域。
// 标题栏、工具栏、黑边与画面内容对不上，所以不会被选中；
// 「窗口存在 + 有帧」本身不构成成功，必须比对通过才算。
- (BOOL)autoDetectCaptureCardVideoRectForWindow:(WindowItem *)window reason:(NSString **)outReason {
    if (!window) { if (outReason) { *outReason = @"未选择目标窗口"; } return NO; }
    // 定位失败时不要每轮都重新抓一次整窗：失败的尝试限流，成功了会缓存映射。
    if ([[self locateSchedule] isThrottled]) {
        if (outReason) { *outReason = @"暂时无法定位游戏画面，可调整贴译位置"; }
        return NO;
    }
    NSRect windowFrame = [self appKitFrameForWindowItem:window];
    if (NSWidth(windowFrame) < 40 || NSHeight(windowFrame) < 40) {
        if (outReason) { *outReason = @"目标窗口太小"; }
        return NO;
    }
    double *templ = NULL, *scene = NULL;
    size_t TW = 0, TH = 0, WW = 0, WH = 0;
    CGFloat videoAspect = 1;
    if (![self buildCaptureGridsWithFrame:&templ templateW:&TW templateH:&TH
                                    scene:&scene sceneW:&WW sceneH:&WH
                              videoAspect:&videoAspect
                             sceneWidth:320 forWindow:window reason:outReason]) {
        return NO;
    }

    FYCaptureCandidateResult candidate=FYSelectCaptureCandidate(scene, WW, WH, templ, TW, TH, videoAspect, windowFrame,
        ^BOOL(NSRect *fit) { return [self captureCardEstimatedDisplayRectForWindow:window outRect:fit]; },
        ^NSDictionary *{ return [[self mappingCache] entryForWindowID:window.windowID]; }, kCaptureCardMappingVersion,
        ^(double searchScore, double fitScore) {
            FuyiDiagLog(@"CAPTURE-AUTO-LOCATE prefer-fit searchScore=%.3f fitScore=%.3f", searchScore, fitScore);
        }, ^(double existingScore, double bestScore, double fitScore) {
            FuyiDiagLog(@"CAPTURE-AUTO-LOCATE keep-cached cachedScore=%.3f best=%.3f fitScore=%.3f", existingScore, bestScore, fitScore);
        });
    if (candidate.keepExisting) { free(templ); free(scene); return NO; }
    NSRect bestRect=candidate.bestRect;
    double best=candidate.bestScore, fitScore=candidate.fitScore;
    free(templ);
    free(scene);
    self.lastAutoLocateAttempt = [NSDate date];

    if (best < 0.55) {
        if (outReason) { *outReason = @"暂时无法定位游戏画面"; }
        FuyiDiagLog(@"CAPTURE-AUTO-LOCATE miss confidence=%.3f fitScore=%.3f aspect=%.3f window=%@ grid=%zux%zu",
                    best, fitScore, videoAspect, NSStringFromRect(windowFrame), WW, WH);
        return NO;
    }
    // ⚠️ 坐标翻转：bestRect 来自 FYGrayGridFromImage 的像素网格，**y 从图像顶部往下**；
    // AppKit 的 y 从窗口底部往上。旧代码直接把 bestRect.origin.y 加到 NSMinY(windowFrame)，
    // 等于把「距顶部」当成「距底部」——OBS 预览在窗口上半部时，映射整体下移到下方控制区。
    // 正确换算：先用 (1 - (y + h) / gridH) 得到距底部的比例，再乘窗口高度。
    NSRect rect = FYWindowRectFromCaptureGrid(bestRect, WW, WH, windowFrame);
    [self storeCaptureCardMapping:rect
                      windowFrame:windowFrame
                      videoAspect:videoAspect
                         deviceID:self.selectedCaptureDeviceID
                           source:@"auto"
                       confidence:best
                      forWindowID:window.windowID];
    // 成功就清掉“失败限流”时间戳：旧映射被判失效后必须能立刻重新定位，
    // 否则会出现「映射已作废、却 3 秒不重新定位」的空窗（贴译整段消失）。
    self.lastAutoLocateAttempt = nil;
    FuyiDiagLog(@"CAPTURE-AUTO-LOCATE hit confidence=%.3f fitScore=%.3f window=%@ rect=%@ fracWH=(%.3f,%.3f) grid=%zux%zu",
                best, fitScore, NSStringFromRect(windowFrame), NSStringFromRect(rect),
                NSWidth(rect) / MAX((CGFloat)1, NSWidth(windowFrame)),
                NSHeight(rect) / MAX((CGFloat)1, NSHeight(windowFrame)),
                WW, WH);
    return YES;
}

// 映射变化（重新定位成功 / 旧映射作废）时调用：贴译布局缓存必须一起失效，
// 否则面板会继续停在旧坐标，直到页面文字恰好发生变化才重排。
- (void)resetInlineLayoutCacheAfterMappingChange {
    self.lastInlineTranslationKey = nil;
    self.lastInlineLayoutResult = nil;
    if (self.inlineStableBlockIDs) { [self.inlineStableBlockIDs removeAllObjects]; }
}

// 便宜复核：只把**缓存矩形对应的那一小块当前窗口截屏**与最新采集帧做一次定点比对，
// 不做搜索。OBS 内部预览被拖动/缩放后，即使窗口比例没变，相关系数也会明显下降。
// 返回 kCaptureCardMappingScoreUnavailable 表示**无法取样**（没有帧/没有权限/网格失败）；
// 其余返回值都是真实相关性，可能为负（= 明显对不上）。
- (double)captureCardMappingScoreForWindow:(WindowItem *)window entry:(NSDictionary *)entry {
    if (!window || !entry) { return kCaptureCardMappingScoreUnavailable; }
    double *templ = NULL, *scene = NULL;
    size_t TW = 0, TH = 0, WW = 0, WH = 0;
    CGFloat videoAspect = 1;
    if (![self buildCaptureGridsWithFrame:&templ templateW:&TW templateH:&TH
                                    scene:&scene sceneW:&WW sceneH:&WH
                              videoAspect:&videoAspect sceneWidth:320 forWindow:window reason:NULL]) {
        return kCaptureCardMappingScoreUnavailable;
    }
    return FYConsumeCaptureMappingGrids(entry, scene, WW, WH, templ, TW, TH);
}

static double FYMappingScoreInGrids(NSDictionary *entry, const double *scene, size_t WW, size_t WH,
                                    const double *templ, size_t TW, size_t TH) {
    return FYCaptureMappingScoreInGrids(entry, scene, WW, WH, templ, TW, TH);
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
    NSDictionary *entry = [FYGeometryManager captureMappingForRect:screenRect windowFrame:windowFrame
                                                       videoAspect:videoAspect deviceID:deviceID source:source
                                                        confidence:confidence version:kCaptureCardMappingVersion];
    if (!entry) { return; }
    [[self mappingCache] storeEntry:entry forWindowID:windowID];
    // 刚定位出来的映射先给 2 秒宽限再做定点复核：它是拿**当前**这帧画面算出来的，
    // 立刻复核除了多截一次屏没有任何意义。
    self.lastMappingValidationDate = [NSDate date];
    // 映射变了：让贴译布局缓存与手动位置一起按新映射重算。
    [self resetInlineLayoutCacheAfterMappingChange];
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
    [[self mappingCache] removeWindowID:windowID];
}
- (BOOL)captureCardHasCalibratedVideoRectForWindow:(WindowItem *)window {
    if (!window) { return NO; }
    NSRect rect = NSZeroRect;
    return [self captureCardDisplayRectForWindow:window outRect:&rect reason:NULL];
}
- (NSString *)captureCardCalibrationSummaryForWindow:(WindowItem *)window {
    if (!window) { return @"未选择目标窗口"; }
    NSDictionary *entry = [[self mappingCache] entryForWindowID:window.windowID];
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
    return FYEstimatedCaptureDisplayRect(frameSize, windowFrame, outRect);
}

// 采集卡坐标映射：只有**校准过的视频显示区域**才算有效映射。
// 旧实现把「帧等比居中到整个目标窗口」当成映射并返回成功，等于宣称可靠原位映射 ——
// 有帧、有窗口都不足以证明映射有效，因此这里不再回退到估算。
- (BOOL)captureCardDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect {
    return [self captureCardDisplayRectForWindow:window outRect:outRect reason:NULL];
}
- (BOOL)captureCardDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect reason:(NSString **)outReason {
    if (!window) { if (outReason) { *outReason = @"未选择目标窗口。"; } return NO; }
    NSString *mappingKey = [NSString stringWithFormat:@"%u", window.windowID];
    NSDictionary *entry = [[self mappingCache] entryForWindowID:window.windowID];
    if (!entry) { if (outReason) { *outReason = @"该窗口还没有贴译位置。"; } return NO; }
    // 旧版（mappingVersion < 2）的自动映射纵坐标是错的：作废重定位，不能继续读旧结果。
    // 手动调整（source=manual）一直是 AppKit 坐标，不受这个 bug 影响，保留。
    FYCaptureMappingVersionStatus versionStatus = FYCaptureMappingVersion(entry, kCaptureCardMappingVersion);
    BOOL autoMapping = versionStatus != FYCaptureMappingVersionNonAutomatic;
    if (versionStatus == FYCaptureMappingVersionStaleAutomatic) {
        [[self mappingCache] removeWindowID:window.windowID];
        [self resetInlineLayoutCacheAfterMappingChange];
        self.lastAutoLocateAttempt = nil;   // 允许上层立刻重新定位
        if (outReason) { *outReason = @"旧版自动定位结果已作废，正在重新定位游戏画面"; }
        FuyiDiagLog(@"CAPTURE-MAPPING stale-version dropped key=%@", mappingKey);
        return NO;
    }
    NSRect windowFrame = [self appKitFrameForWindowItem:window];
    NSString *windowReason = [FYGeometryManager captureMappingWindowReason:entry windowFrame:windowFrame];
    if (windowReason) { if (outReason) { *outReason = windowReason; } return NO; }
    // Sampling and state remain in coordinator; policy uses explicit snapshot inputs.
    CGSize frameSize = CGSizeZero;
    BOOL hasFrameSize = [self.captureCardInput latestFrameSize:&frameSize];
    NSString *inputReason = [FYGeometryManager captureMappingInputReason:entry frameSize:frameSize
                                                         hasFrameSize:hasFrameSize deviceID:self.selectedCaptureDeviceID];
    if (inputReason) { if (outReason) { *outReason = inputReason; } return NO; }
    // 自动映射要**适当复核**：OBS 内部预览移动/缩放、面板展开收起时窗口比例可能完全没变，
    // 只看比例会一直拿着错位置。这里限流（≥1.5s 一次）做一次定点比对：
    // 不做全窗口搜索，所以不会每帧昂贵；失败就作废映射并在上层触发重新定位。
    // 手动调整的映射不参与复核（那是用户明确指定的位置）。
    if (autoMapping && [self captureCardInputEnabled]) {
        NSDate *now = [NSDate date];
        BOOL due = [[self validationSchedule] beginValidationAt:now];
        if (due) {

            double score = [self captureCardMappingScoreForWindow:window entry:entry];
            // 阈值 0.30 来自离线标定：位置没变时定点相关性约 0.57，画面移动 ≥5% 就掉到 0.07 以下
            //（大移位甚至为负）。负数同样是“明确对不上”，只有哨兵值才表示取样失败。
            if ([FYGeometryManager captureMappingScoreIsStale:score unavailableValue:kCaptureCardMappingScoreUnavailable]) {
                [[self mappingCache] removeWindowID:window.windowID];
                [self resetInlineLayoutCacheAfterMappingChange];
                self.lastAutoLocateAttempt = nil;   // 允许上层立刻重新定位
                if (outReason) { *outReason = @"游戏画面位置变了，正在重新定位"; }
                FuyiDiagLog(@"CAPTURE-MAPPING stale-picture dropped key=%@ score=%.3f", mappingKey, score);
                return NO;
            }
        }
    }
    NSRect rect = [FYGeometryManager captureMappingRect:entry windowFrame:windowFrame];
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
    WindowItem *window = [self displayTargetWindowItem];
    self.captureCalibrationLabel.stringValue = captureCard
        ? [self captureCardCalibrationSummaryForWindow:window]
        : @"切换到「采集卡」输入源后可以调整贴译位置。";
    self.captureCalibrateButton.enabled = captureCard && window != nil;
    // 「恢复自动定位」只在用户手动调整过之后才有意义。
    NSDictionary *entry = window ? [[self mappingCache] entryForWindowID:window.windowID] : nil;
    self.captureCalibrateClearButton.enabled = captureCard && [entry[@"source"] isEqualToString:@"manual"];
    self.captureCalibrateClearButton.hidden = !self.captureCalibrateClearButton.enabled;
}

// 在目标窗口上盖一层拖框层：用户框出的矩形就是真实的视频显示区域。
- (void)beginCaptureCardCalibration:(id)sender {
    if (![self captureCardInputEnabled]) {
        [self setStatus:@"先切换到「采集卡」输入源，再调整贴译位置。"];
        return;
    }
    WindowItem *window = [self displayTargetWindowItem];
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
        weakSelf.selectOCRRegionAfterCaptureCalibration = NO;
        [weakSelf endCaptureCardCalibration];
        [weakSelf setStatus:@"已取消调整贴译位置。"];
    };
    panel.contentView = view;
    self.captureCalibrationPanel = panel;
    [panel makeKeyAndOrderFront:nil];
    [panel makeFirstResponder:view];
    self.captureCalibrationKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (event.keyCode != 53) { return event; }
        weakSelf.selectOCRRegionAfterCaptureCalibration = NO;
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
        self.selectOCRRegionAfterCaptureCalibration = NO;
        [self setStatus:@"框选区域太小，未保存。"];
        return;
    }
    [self calibrateCaptureCardVideoRect:screenRect windowFrame:windowFrame videoAspect:videoAspect deviceID:deviceID forWindowID:windowID];
    [self scheduleSettingsSave];
    [self updateCaptureCalibrationStatus];
    [self setStatus:[NSString stringWithFormat:@"已按你框选的区域贴译（%.0f×%.0f）。", NSWidth(screenRect), NSHeight(screenRect)]];
    if (self.selectOCRRegionAfterCaptureCalibration) {
        self.selectOCRRegionAfterCaptureCalibration = NO;
        [self selectOCRRegion:nil];
    }
}

- (void)clearCaptureCardCalibration:(id)sender {
    WindowItem *window = [self displayTargetWindowItem];
    if (!window) { return; }
    [self clearCaptureCardCalibrationForWindowID:window.windowID];
    [self scheduleSettingsSave];
    [self updateCaptureCalibrationStatus];
    [self setStatus:@"已恢复自动定位。"];
}

// 当前识别输入源下界面贴译面板应落在哪里。
//   窗口截图：整个目标窗口；采集卡：视频帧适配后的可见矩形。
// 返回 NO 时 outReason 给出明确原因（用于提示，不能静默塞进对白框）。
// 目标窗口定位不了时的原因文案：歧义/窗口关闭优先给"请重新选择"这类可操作提示。
- (NSString *)inlineTargetUnavailableReasonWithFallback:(NSString *)fallback {
    if (self.displayTargetAmbiguous) { return @"检测到多个可能是游戏画面的窗口，请重新选择显示窗口"; }
    if (self.windowSelectionLost && self.windowPickerPlaceholder.length > 0) { return self.windowPickerPlaceholder; }
    return fallback;
}

- (BOOL)inlinePlacementRect:(NSRect *)outRect reason:(NSString **)outReason {
    WindowItem *window = [self displayTargetWindowItem];
    if (![self captureCardInputEnabled]) {
        if (!window) {
            if (outReason) { *outReason = [self inlineTargetUnavailableReasonWithFallback:@"未选择目标窗口，界面文字暂不贴译。"]; }
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
        if (outReason) { *outReason = [self inlineTargetUnavailableReasonWithFallback:@"暂时无法定位游戏画面，可调整贴译位置"]; }
        return NO;
    }
    NSRect mapped = NSZeroRect;
    NSString *mappedReason = nil;
    if ([self captureCardDisplayRectForWindow:window outRect:&mapped reason:&mappedReason]) {
        if (outRect) { *outRect = mapped; }
        return YES;
    }
    FuyiDiagLog(@"CAPTURE-MAPPING unusable reason=<%@>", mappedReason ?: @"未知");
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
    return [FYGeometryManager quartzRectFromSelection:selectionRect panelFrame:panelFrame mainScreenTop:NSMaxY(NSScreen.mainScreen.frame)];
}

- (NSRect)appKitOCRPreviewFrameForWindowItem:(WindowItem *)item {
    NSRect frame = [self appKitFrameForWindowItem:item];
    if ([self captureCardInputEnabled] && ![self captureCardDisplayRectForWindow:item outRect:&frame]) return NSZeroRect;
    CGRect box = CGRectMake(self.regionXSlider.doubleValue, self.regionYSlider.doubleValue, self.regionWidthSlider.doubleValue, self.regionHeightSlider.doubleValue);
    return [FYGeometryManager frameForTopLeftNormalizedBox:box inViewport:frame];
}

- (BOOL)updateOCRPreviewPanel {
    WindowItem *window = [self displayTargetWindowItem];
    if (!window) {
        [self setStatus:[self captureCardInputEnabled] ? @"请先选择游戏画面所在的显示窗口" : @"请先选择要翻译的窗口"];
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
        content.layer.borderColor = [self captionTextColor].CGColor;
        content.layer.borderWidth = 3;
        content.layer.cornerRadius = 8;

        self.ocrPreviewLabel = [self label:@"OCR 识别区域" font:FYUIFont(MAX((CGFloat)12, self.captionFontSizeSlider.doubleValue * 0.5), NSFontWeightBold) color:[self captionTextColor]];
        self.ocrPreviewLabel.wantsLayer = YES;
        self.ocrPreviewLabel.layer.backgroundColor = [FYAppearanceBackdropForText([self captionTextColor]) colorWithAlphaComponent:0.94].CGColor;
        self.ocrPreviewLabel.layer.cornerRadius = 5;
        self.ocrPreviewLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:self.ocrPreviewLabel];
        [NSLayoutConstraint activateConstraints:@[
            [self.ocrPreviewLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:10],
            [self.ocrPreviewLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:8]
        ]];

        self.ocrPreviewPanel.contentView = content;
    }

    self.ocrPreviewPanel.contentView.layer.borderColor = [self captionTextColor].CGColor;
    self.ocrPreviewLabel.font = FYUIFont(MAX((CGFloat)12, self.captionFontSizeSlider.doubleValue * 0.5), NSFontWeightBold);
    self.ocrPreviewLabel.textColor = [self captionTextColor];
    self.ocrPreviewLabel.layer.backgroundColor = [FYAppearanceBackdropForText([self captionTextColor]) colorWithAlphaComponent:0.94].CGColor;
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

    CGImageRef cropped = FYCopyCapturedRegion(image, CGRectMake(x, y, width, height));
    CGImageRelease(image);
    return cropped;
}

- (NSString *)recognizeTextInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment error:(NSError **)error {
    return [[self ocrManager] recognizeTextInImage:image fastOCR:fastOCR languageSegment:languageSegment error:error];
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
    return [FYOCRManager recognizeEnlargedImage:image visionRegion:CGRectMake(x, y, width, height)
        recognizer:^NSString *(CGImageRef scaled, NSArray<OCRTextItem *> **items, NSError **recognitionError) {
            return [self recognizeTextBlocksInImage:scaled fastOCR:fastOCR languageSegment:languageSegment blocks:items error:recognitionError];
        } blocks:outBlocks error:error];
}

- (NSString *)recognizeTextBlocksInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment blocks:(NSArray<OCRTextItem *> **)outBlocks error:(NSError **)error {
    NSArray<OCRTextItem *> *items = [self recognizeTextItemsInImage:image fastOCR:fastOCR languageSegment:languageSegment error:error];
    NSSet<NSString *> *rendered = RenderedTranslationSet(self.captionTextLabel.stringValue, self.inlineTranslationCache);
    return [FYOCRManager postprocessedTextForItems:items renderedTexts:rendered blocks:outBlocks];
}

- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment error:(NSError **)error {
    return [[self ocrManager] recognizeTextItemsInImage:image fastOCR:fastOCR languageSegment:languageSegment error:error];
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
    NSString *key = FYTranslationCacheKey(generation, serviceGeneration, identity.sentenceID, identity.version, text, systemPrompt);
    NSString *cached = [self.dialogueTranslationCache valueForKey:key];
    if (cached) {
        FYTrace(trace, @"cache", @{@"route": @"dialogue", @"cache_hit": @YES, @"sentence_id": identity.sentenceID ?: @"", @"version": @(identity.version)});
        completion(cached, nil);
        return;
    }
    FYTrace(trace, @"cache", @{@"route": @"dialogue", @"cache_hit": @NO, @"reason": key ? @"key_or_value_miss" : @"no_sentence_identity", @"sentence_id": identity.sentenceID ?: @"", @"version": @(identity.version)});
    [self translateTextRealtime:text systemPrompt:systemPrompt maxTokens:240 completion:^(NSString *translated, NSError *error) {
        if (key && !error && FYTranslationCacheCanStore(generation, self.translationGeneration,
                                                       serviceGeneration, self.serviceTestGeneration, translated)) {
            if (!self.dialogueTranslationCache) { self.dialogueTranslationCache = [FYTranslationCache new]; }
            [self.dialogueTranslationCache storeValue:translated forKey:key];
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
        NSError *urlError=nil;
        FYChatCompletionsURLWithError(self.baseURLField.stringValue,&urlError);
        if (urlError) error=[NSError errorWithDomain:error.domain code:error.code userInfo:@{NSLocalizedDescriptionKey:urlError.localizedDescription, NSUnderlyingErrorKey:urlError}];
        completion(nil, error);
        return;
    }

    // 实时路径传“实时模型”（默认 Flash）；快照/整屏留空，走界面上的“模型名”
    NSString *model = Trim(modelOverride);
    if (model.length == 0) { model = Trim(self.modelField.stringValue); }
    if (model.length == 0) { model = @"gpt-4.1-mini"; }

    NSError *jsonError = nil;
    NSMutableURLRequest *request = [FYTranslationManager requestWithURL:url apiKey:apiKey model:model
        sourceText:text systemPrompt:(systemPrompt ?: [self systemPrompt]) maxTokens:maxTokens
        disableReasoning:[self isDeepSeekRequest] error:&jsonError];
    if (!request) {
        FYTrace(trace, @"request_complete", @{@"reason": @"serialization_error", @"success": @NO, @"error_code": @(jsonError.code)});
        completion(nil, jsonError);
        return;
    }

    NSInteger generation = self.translationGeneration;
    uint32_t diagnosticWindowID = [self displayTargetWindowID];
    void (^deliver)(NSString *, NSError *) = ^(NSString *translated, NSError *error) {
        [[FYRuntimeDiagnostics shared] recordEvent:@"translation" fields:@{@"window_id": @(diagnosticWindowID), @"generation": @(generation), @"success": @(!error), @"error_code": @(error.code)}];
        FYTrace(trace, @"request_complete", @{@"success": @(!error), @"error_code": @(error.code), @"translation": error ? @"" : (translated ?: @"")});
        FYDeliverTranslationOnMain(generation, ^NSInteger { return self.translationGeneration; },
            translated, error, completion, ^{
                FYTrace(trace, @"caption_drop", @{@"reason": @"generation_changed_before_delivery"});
            });
    };

    NSDate *httpStart = [NSDate date];
    NSURLSessionDataTask *task = [FYTranslationManager taskWithRequest:request session:NSURLSession.sharedSession observer:^(NSURLResponse *response, NSError *error) {
        FuyiDiagLog(@"    HTTP %ld in %.2fs err=<%@>", (long)[(NSHTTPURLResponse *)response statusCode],
                    [[NSDate date] timeIntervalSinceDate:httpStart], error.localizedDescription ?: @"");
        [[FYRuntimeDiagnostics shared] recordEvent:@"http" fields:@{@"window_id": @(diagnosticWindowID), @"generation": @(generation), @"http_status": @([(NSHTTPURLResponse *)response statusCode]), @"error_code": @(error.code), @"elapsed_ms": @([[NSDate date] timeIntervalSinceDate:httpStart] * 1000)}];
        FYTrace(trace, @"http_complete", @{@"http_status": @([(NSHTTPURLResponse *)response statusCode]), @"elapsed_ms": @([[NSDate date] timeIntervalSinceDate:httpStart] * 1000), @"error_code": @(error.code)});
    } completion:deliver];
    self.activeTranslationTask = task;
    FYTrace(trace, @"request_submit", @{@"source": Trim(text), @"generation": @(generation)});
    [task resume];
}

- (NSURL *)chatCompletionsURL { return FYChatCompletionsURL(self.baseURLField.stringValue); }

- (BOOL)isDeepSeekRequest { return FYIsDeepSeekService(self.baseURLField.stringValue, self.modelField.stringValue); }

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
static BOOL ModalSurroundingsAreDimmer(unsigned char *pixels, size_t width, size_t height, size_t bytesPerRow, CGRect rect) { return FYOCRModalSurroundingsAreDimmer(pixels,width,height,bytesPerRow,rect); }

// 检测到的亮矩形够不够格当“弹窗”。抽成函数是为了能直接测：
// 既要**够大**，也要**水平居中** —— 弹窗是居中的，普通界面里的大亮块（照片、插图）
// 往往偏在一边。实测「我的房间」那张房间照片 x=0.15..0.57（中心 0.36）被误判成弹窗，
// 12 条文字被裁到 4 条，底部说明整段消失。
static BOOL ModalRectQualifiesForCropping(CGRect rect) { return FYOCRModalRectQualifiesForCropping(rect); }

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
        if (!exclusions) { return blocks; }
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
        GrayBufferRelease(&buffer);
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

    return [FYOCRManager items:blocks inModalRegion:modalRect exclusions:exclusionValues];
}

- (NSInteger)effectiveModeSegment {
    return self.detectedModeSegment;
}

// 同样的判别结果连续出现两次才切换，避免单帧抖动导致模式来回跳
- (NSInteger)stableContentModeForBlocks:(NSArray<OCRTextItem *> *)blocks {
    NSInteger detected = DetectContentModeForBlocks(blocks, self.detectedModeSegment);

    return [[self modeStability] observeMode:detected];
}

- (NSString *)systemPromptForMode:(NSInteger)modeSegment {
    NSString *source = SourceLanguageLabel(self.languageControl.selectedSegment);
    if (modeSegment == 1) {
        return [NSString stringWithFormat:@"你是一个游戏界面与公告文本翻译器。把用户发来的%@ OCR 文本翻译成简体中文。只输出译文，不解释。保留标题、日期、正文、按钮等自然结构；去掉重复、残缺、装饰性或背景噪声文字；菜单和按钮要短，公告正文要完整准确。", source];
    }

    return [NSString stringWithFormat:@"你是一个游戏字幕实时翻译器。把用户发来的%@翻译成自然、准确、口语化的简体中文。只输出译文，不解释，不加引号。保留人名和专有名词。遇到多行文本，按原意合并成适合字幕阅读的短句。", source];
}

#pragma mark - State helpers
- (FYInlineTranslationCache *)inlineCache {
    if (!_inlineCacheOwner) _inlineCacheOwner=[FYInlineTranslationCache new];
    return _inlineCacheOwner;
}
- (NSMutableDictionary *)inlineTranslationCache { return [self inlineCache].entries; }
- (void)setInlineTranslationCache:(NSMutableDictionary *)value { [self inlineCache].entries=value; }
- (FYContentModeStability *)modeStability {
    if (!_contentModeStability) _contentModeStability=[FYContentModeStability new];
    return _contentModeStability;
}
- (NSInteger)detectedModeSegment { return [self modeStability].detectedMode; }
- (void)setDetectedModeSegment:(NSInteger)value { [self modeStability].detectedMode=value; }
- (NSInteger)candidateModeSegment { return [self modeStability].candidateMode; }
- (void)setCandidateModeSegment:(NSInteger)value { [self modeStability].candidateMode=value; }
- (NSInteger)candidateModeHits { return [self modeStability].candidateHits; }
- (void)setCandidateModeHits:(NSInteger)value { [self modeStability].candidateHits=value; }
- (FYAutoLocateSchedule *)locateSchedule {
    if (!_autoLocateSchedule) _autoLocateSchedule=[FYAutoLocateSchedule new];
    return _autoLocateSchedule;
}
- (NSDate *)lastAutoLocateAttempt { return [self locateSchedule].lastAttemptDate; }
- (void)setLastAutoLocateAttempt:(NSDate *)value { [self locateSchedule].lastAttemptDate=value; }
- (FYCaptureMappingCache *)mappingCache {
    if (!_captureMappingCache) _captureMappingCache=[FYCaptureMappingCache new];
    return _captureMappingCache;
}
- (NSMutableDictionary *)captureCardVideoRects { return [self mappingCache].entries; }
- (void)setCaptureCardVideoRects:(NSMutableDictionary *)value { [self mappingCache].entries=value; }
- (FYMappingValidationSchedule *)validationSchedule {
    if (!_mappingValidationSchedule) _mappingValidationSchedule=[FYMappingValidationSchedule new];
    return _mappingValidationSchedule;
}
- (NSDate *)lastMappingValidationDate { return [self validationSchedule].lastValidationDate; }
- (void)setLastMappingValidationDate:(NSDate *)value { [self validationSchedule].lastValidationDate=value; }
- (FYTranslationRunState *)translationState {
    if (!_translationRunState) _translationRunState=[FYTranslationRunState new];
    return _translationRunState;
}
- (NSString *)lastTranslatedNormalizedText { return [self translationState].lastTranslatedText; }
- (void)setLastTranslatedNormalizedText:(NSString *)value { [self translationState].lastTranslatedText=value; }
- (NSString *)lastSubmittedNormalizedText { return [self translationState].lastSubmittedText; }
- (void)setLastSubmittedNormalizedText:(NSString *)value { [self translationState].lastSubmittedText=value; }
- (NSDate *)lastTranslationAttemptDate { return [self translationState].lastAttemptDate; }
- (void)setLastTranslationAttemptDate:(NSDate *)value { [self translationState].lastAttemptDate=value; }

- (void)restartTimerIfRunning {
    if (!self.running) { return; }

    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:MAX(0.5, self.intervalSlider.doubleValue)
                                                  target:self
                                                selector:@selector(timerFired:)
                                                userInfo:nil
                                                 repeats:YES];
}

- (FYOCRStabilityOwner *)stabilityOwner {
    if (!_ocrStabilityOwner) _ocrStabilityOwner=[FYOCRStabilityOwner new];
    return _ocrStabilityOwner;
}
- (NSString *)stableCandidate { return [self stabilityOwner].candidate; }
- (void)setStableCandidate:(NSString *)value { [self stabilityOwner].candidate=value; }
- (NSInteger)stableCandidateCount { return [self stabilityOwner].count; }
- (void)setStableCandidateCount:(NSInteger)value { [self stabilityOwner].count=value; }
- (BOOL)isStableText:(NSString *)normalized {
    return [[self stabilityOwner] observe:normalized equivalent:^BOOL(NSString *current, NSString *previous) {
        return [self isSameSubtitleText:current comparedTo:previous];
    }];
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
    return FYDisplayableTranslation(translated, sourceText,
        ^NSString *(NSString *value) { return Trim(value); },
        ^NSString *(NSString *value) { return NormalizeForComparison(value); },
        ^BOOL(NSString *current, NSString *previous) { return [self isSameSubtitleText:current comparedTo:previous]; },
        ^BOOL(NSString *line) { return self.languageControl.selectedSegment == 0 && ContainsJapaneseText(line); });
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
    if (self.captionPanel && self.captionWidthSlider) {
        NSRect frame = self.captionPanel.frame;
        NSRect visible = (self.captionPanel.screen ?: NSScreen.mainScreen).visibleFrame;
        CGFloat width = MIN(self.captionWidthSlider.doubleValue, MAX((CGFloat)240, NSWidth(visible)));
        if (fabs(NSWidth(frame) - width) >= 1) {
            frame.size.width = width;
            frame.origin.x = MIN(MAX(frame.origin.x, NSMinX(visible)), NSMaxX(visible) - width);
            [self.captionPanel setFrame:frame display:YES animate:NO];
        }
    }
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
