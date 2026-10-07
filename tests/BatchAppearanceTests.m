#import "LearningAppTestSupport.h"

// All panels remain hidden. Fictional text, fixed geometry, no capture or requests.
@interface BatchAppearanceTestApp : AppDelegate
@property(nonatomic) NSUInteger renderCount;
@property(nonatomic) NSUInteger captionRefreshCount;
@property(nonatomic) NSUInteger ocrRefreshCount;
@property(nonatomic) NSUInteger saveCount;
@property(nonatomic) BOOL renderPanels;
@property(nonatomic) CGFloat renderedWidth;
@property(nonatomic, copy) NSArray *renderedText;
@property(nonatomic, strong) FYInlineLayoutResult *previousAtRender;
@end
@implementation BatchAppearanceTestApp
- (BOOL)inlinePlacementRect:(NSRect *)rect reason:(NSString **)reason {
    if (rect) { *rect = NSMakeRect(0, 0, 1200, 800); }
    return YES;
}
- (uint32_t)displayTargetWindowID { return 42; }
- (void)updateCaptionAppearance { self.captionRefreshCount++; }
- (void)updateOCRPreviewIfVisible { self.ocrRefreshCount++; }
- (void)scheduleSettingsSave { self.saveCount++; }
- (void)refreshOverlayVisibility:(id)sender {}
- (void)startInlineModifierMonitor {}
- (void)updateInlineOverflowEntryWithPlacements:(NSArray *)placements items:(NSDictionary *)items viewport:(NSRect)viewport unplaceable:(NSUInteger)count {}
- (void)showInlineTranslations:(NSArray *)translations forItems:(NSArray *)items placementRect:(NSRect)rect {
    self.renderCount++;
    self.renderedWidth = self.inlineLayoutEngine.cardMaxWidth;
    self.renderedText = translations;
    self.previousAtRender = self.lastInlineLayoutResult;
    if (self.renderPanels) { [super showInlineTranslations:translations forItems:items placementRect:rect]; }
}
@end

static BatchAppearanceTestApp *TestApp(void) {
    BatchAppearanceTestApp *app = [BatchAppearanceTestApp new];
    app.batchFontSizeSlider = [app sliderWithMin:13 max:30 value:16 action:@selector(controlValueChanged:)];
    app.batchWidthSlider = [app sliderWithMin:240 max:720 value:560 action:@selector(controlValueChanged:)];
    app.batchHeightSlider = [app sliderWithMin:160 max:500 value:330 action:@selector(controlValueChanged:)];
    app.batchTextColorWell = [NSColorWell new];
    app.batchTextColorWell.color = FYAdventureColor(@"ink");
    [app applyBatchAppearanceToLayoutEngine];
    return app;
}

static OCRTextItem *Item(NSString *text, CGRect box, BOOL longBody) {
    OCRTextItem *item = [OCRTextItem new];
    item.text = text;
    item.boundingBox = box;
    item.lineBoxes = @[[NSValue valueWithRect:box]];
    item.lineTexts = @[text];
    item.blockKind = longBody ? InlineBlockKindLong : InlineBlockKindShort;
    return item;
}

static void TrackFor(NSTimeInterval interval) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:interval];
    while (limit.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runMode:NSEventTrackingRunLoopMode beforeDate:limit];
    }
}

static NSScrollView *BodyScroll(NSView *view) {
    for (NSView *child in view.subviews) {
        if ([child isKindOfClass:NSScrollView.class]) { return (NSScrollView *)child; }
    }
    return nil;
}

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    BatchAppearanceTestApp *app = TestApp();
    NSArray *items = @[Item(@"架空通知", CGRectMake(.5,.4,.35,.15), YES)];
    app.lastInlineRenderedItems = items;
    app.lastInlineRenderedTranslations = @[@"虚构通知内容"];
    FYInlineLayoutResult *previous = [FYInlineLayoutResult new];
    app.lastInlineLayoutResult = previous;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    NSTimer *firstTimer = nil;
    for (NSUInteger i = 0; i < 120; i++) {
        app.batchWidthSlider.doubleValue = 240 + i * 4;
        [app controlValueChanged:app.batchWidthSlider];
        if (!firstTimer) { firstTimer = app.batchAppearanceTimer; }
        Require(app.batchAppearanceTimer == firstTimer, @"drag events share one pending render");
    }
    double callbacksMS = (CFAbsoluteTimeGetCurrent() - start) * 1000;
    Require(app.renderCount == 0 && app.lastInlineLayoutResult == previous, @"slider callbacks keep previous placements and do not synchronously relayout");
    Require(app.captionRefreshCount == 0 && app.ocrRefreshCount == 0 && app.saveCount == 120, @"batch changes avoid unrelated caption/OCR work and still save settings");
    TrackFor(.08);
    Require(app.renderCount == 1 && !app.batchAppearanceTimer && app.renderedWidth == 716, @"event tracking renders only the latest value without waiting for mouse-up");
    Require(app.previousAtRender == previous, @"relayout retains previous block identities and anchors");

    app.batchHeightSlider.doubleValue = 420;
    [app controlValueChanged:app.batchHeightSlider];
    app.lastInlineRenderedTranslations = @[@"换页后的虚构通知"];
    TrackFor(.08);
    Require([app.renderedText.firstObject isEqualToString:@"换页后的虚构通知"], @"pending render reads the current scene");
    [app controlValueChanged:app.batchWidthSlider];
    NSUInteger count = app.renderCount;
    [app clearInlineTranslationPanels];
    TrackFor(.08);
    Require(app.renderCount == count && !app.batchAppearanceTimer, @"stop or scene clear cancels pending render and cannot revive old subtitles");
    NSLog(@"PASS: 120 slider callbacks %.2f ms, coalesced render in tracking mode, latest value, cached placements, scene cancellation", callbacksMS);

    BatchAppearanceTestApp *real = TestApp();
    real.renderPanels = YES;
    NSArray *scene = @[
        Item(@"架空菜单", CGRectMake(.06,.72,.1,.03), NO),
        Item(@"架空文章\n虚构正文", CGRectMake(.5,.34,.32,.26), YES)
    ];
    NSString *body = [@"虚构通知：调整字幕后继续阅读。" stringByPaddingToLength:400 withString:@"完整内容保留在阅读卡内，可以滚动阅读。" startingAtIndex:0];
    NSArray *text = @[@"虚构菜单", body];
    [real showInlineTranslations:text forItems:scene placementRect:NSMakeRect(0,0,1200,800)];
    Require(real.inlineTranslationPanels.count == 1 && real.inlineLongCardPanels.count == 1, @"fixture has a short label and long reading card");
    NSPanel *shortPanel = real.inlineTranslationPanels.firstObject;
    NSPanel *longPanel = real.inlineLongCardPanels.firstObject;
    FYInlineLayoutResult *before = real.lastInlineLayoutResult;
    NSString *shortID = shortPanel.identifier;
    NSString *longID = longPanel.identifier;
    real.batchFontSizeSlider.doubleValue = 24;
    [real controlValueChanged:real.batchFontSizeSlider];
    TrackFor(.1);
    Require(real.lastInlineLayoutResult != before && real.previousAtRender == before, @"font change invalidates unchanged-text shortcut while retaining prior layout for matching");
    Require([shortID isEqualToString:real.inlineTranslationPanels.firstObject.identifier] && [longID isEqualToString:real.inlineLongCardPanels.firstObject.identifier], @"style changes keep block identities");
    Require(real.inlineTranslationPanels.firstObject == shortPanel && real.inlineLongCardPanels.firstObject == longPanel, @"style changes reuse existing windows");
    NSTextField *shortLabel = (NSTextField *)shortPanel.contentView.subviews.firstObject;
    Require(shortLabel.font.pointSize >= 24, @"same-text short label receives updated font");
    NSScrollView *scroll = BodyScroll(longPanel.contentView);
    NSTextField *bodyLabel = (NSTextField *)scroll.documentView;
    Require(bodyLabel.font.pointSize >= real.inlineLayoutEngine.minimumLongBodyFontSize, @"long-card body uses the new font range");
    [scroll.contentView scrollToPoint:NSMakePoint(0, 40)];
    NSPoint scrollOrigin = scroll.contentView.bounds.origin;
    NSRect shortFrame = shortPanel.frame, longFrame = longPanel.frame;
    CGFloat shortSize = shortLabel.font.pointSize, bodySize = bodyLabel.font.pointSize;
    NSView *shortView = shortPanel.contentView, *longView = longPanel.contentView;
    before = real.lastInlineLayoutResult;
    count = real.renderCount;
    real.batchTextColorWell.color = [NSColor colorWithSRGBRed:.22 green:.36 blue:.45 alpha:1];
    [real controlValueChanged:real.batchTextColorWell];
    TrackFor(.08);
    Require(real.renderCount == count && real.lastInlineLayoutResult == before && !real.batchAppearanceTimer, @"color changes require no geometry calculation");
    Require(shortPanel.contentView == shortView && longPanel.contentView == longView && NSEqualRects(shortPanel.frame,shortFrame) && NSEqualRects(longPanel.frame,longFrame), @"color changes preserve content views and window frames");
    Require(NSEqualPoints(scrollOrigin,scroll.contentView.bounds.origin) && shortLabel.font.pointSize == shortSize && bodyLabel.font.pointSize == bodySize, @"color changes preserve fonts and reading position");
    Require([shortLabel.textColor isEqual:real.batchTextColorWell.color] && [bodyLabel.textColor isEqual:real.batchTextColorWell.color], @"short and long text receive the selected color");
    NSTextField *title = (NSTextField *)longPanel.contentView.subviews.firstObject;
    Require(fabs(title.textColor.alphaComponent - .82) < .001, @"title keeps its secondary color alpha");
    [real showInlineTranslations:text forItems:scene placementRect:NSMakeRect(0,0,1200,800)];
    Require(real.lastInlineLayoutResult == before, @"unchanged styles and text still use the cached layout");
    [real clearInlineTranslationPanels];
    NSLog(@"PASS: same-text font updates, stable panel reuse, immediate color changes, preserved geometry and scroll, unchanged-layout fast path");
} return 0; }
