#import "FYInlineOverlayViews.h"
#import "FYInlineTextMeasurer.h"
#import "FYInlineTextUtilities.h"


void FYInstallInlineLongCardFooter(FYInlineLongCardView *card, NSTextField *footer, CGFloat padding, CGFloat height, CGFloat textWidth) {
    footer.frame = NSMakeRect(padding, height - padding - 14, textWidth, 14);
    footer.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    footer.hidden = YES;
    [card addSubview:footer];
    card.expandedFooterLabel = footer;
}

void FYInstallInlineLongCardHeader(FYInlineLongCardView *card, CGFloat cardWidth, CGFloat padding,
    CGFloat titleBand, BOOL selected, NSTextField *title, NSTextField *badge, NSColor *badgeColor, NSColor *ruleColor) {
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    title.frame = NSMakeRect(padding, padding + 2, cardWidth - padding * 2 - 70, titleBand);
    title.autoresizingMask = NSViewWidthSizable;
    [card addSubview:title];
    if (selected) {
        NSView *badgeBox = [[NSView alloc] initWithFrame:NSMakeRect(cardWidth - padding - 72, padding, 72, titleBand + 2)];
        card.selectedBadgeBox = badgeBox;
        badgeBox.autoresizingMask = NSViewMinXMargin;
        badgeBox.wantsLayer = YES;
        badgeBox.layer.backgroundColor = badgeColor.CGColor;
        badgeBox.layer.cornerRadius = (titleBand + 2) / 2.0;
        badge.alignment = NSTextAlignmentCenter;
        badge.frame = NSMakeRect(0, 4, 72, titleBand - 6);
        [badgeBox addSubview:badge];
        [card addSubview:badgeBox];
    }
    NSView *rule = [[NSView alloc] initWithFrame:NSMakeRect(padding, padding + titleBand + 2, cardWidth - padding * 2, 1)];
    rule.autoresizingMask = NSViewWidthSizable;
    rule.wantsLayer = YES;
    rule.layer.backgroundColor = ruleColor.CGColor;
    [card addSubview:rule];
}

void FYInstallInlineFoldedEntry(FYInlineLongCardView *card, CGFloat cardWidth, CGFloat padding,
    NSString *title, NSString *hint, NSString *action, NSFont *titleFont, NSFont *hintFont,
    NSColor *titleColor, NSColor *hintColor, NSColor *actionColor,
    NSTextField *(^labelFactory)(NSString *, NSFont *, NSColor *)) {
        CGFloat innerWidth = MAX((CGFloat)60, cardWidth - padding * 2);
        CGFloat titleHeight = FYInlineCeiledFontLineHeight(titleFont);
        CGFloat hintHeight = FYInlineCeiledFontLineHeight(hintFont);
        CGFloat actionHeight = titleHeight;
        CGFloat y = padding;
        NSTextField *titleLabel = labelFactory(title, titleFont, titleColor);
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        titleLabel.frame = NSMakeRect(padding, y, innerWidth, titleHeight);
        [card addSubview:titleLabel];
        y += titleHeight + 2;
        // 提示行：不截断（宽度由引擎按这行字量出来），也不隐藏在 tooltip 里；空文案不占位。
        NSTextField *hintLabel = nil;
        if (hint.length > 0) {
            hintLabel = labelFactory(hint, hintFont, hintColor);
            hintLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            hintLabel.frame = NSMakeRect(padding, y, innerWidth, hintHeight);
            [card addSubview:hintLabel];
            y += hintHeight + 3;
        }
        NSTextField *actionLabel = nil;
        if (action.length > 0) {
            actionLabel = labelFactory([action stringByAppendingString:@" ▾"], titleFont, actionColor);
            actionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            actionLabel.frame = NSMakeRect(padding, y, innerWidth, actionHeight);
            [card addSubview:actionLabel];
        }
        card.foldedEntryHintLabel = hintLabel;
        card.foldedEntryActionLabel = actionLabel;
}

void FYApplyInlineLongCardBody(NSString *translation, NSTextField *label, CGFloat cardWidth, CGFloat padding,
                               NSFont *font, NSParagraphStyle *style, NSColor *textColor) {
    translation = FYInlineNormalizeTranslationParagraphs(translation);
    CGFloat textWidth = MAX((CGFloat)80, cardWidth - padding * 2);
    NSRect measured = FYInlineMeasureTextWithAttributes(translation, NSMakeSize(textWidth, CGFLOAT_MAX), FYInlineTextAttributes(font, style));
    label.font = font;
    label.attributedStringValue = [[NSAttributedString alloc] initWithString:translation ?: @""
        attributes:@{NSFontAttributeName:font, NSForegroundColorAttributeName:textColor, NSParagraphStyleAttributeName:style}];
    label.frame = NSMakeRect(0, 0, textWidth, MAX((CGFloat)22, ceil(NSHeight(measured)) + 4));
}

NSScrollView *FYCreateInlineLongCardBodyScroll(NSString *translation, NSRect viewport, CGFloat cardWidth,
                                             CGFloat padding, NSFont *font, NSParagraphStyle *style, NSColor *textColor) {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(viewport), 22)];
    FYApplyInlineLongCardBody(translation, label, cardWidth, padding, font, style, textColor);
    label.selectable = NO;
    label.editable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.maximumNumberOfLines = 0;
    label.usesSingleLineMode = NO;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.cell.wraps = YES;
    label.cell.scrollable = NO;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:viewport];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.scrollerStyle = NSScrollerStyleOverlay;
    scroll.borderType = NSNoBorder;
    scroll.documentView = label;
    return scroll;
}

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
    self.layer.borderColor = (showsDragHint ? self.dragHintColor : self.normalBorderColor).CGColor;
    self.toolTip = showsDragHint ? @"按住 Option 拖动可调整贴译位置" : nil;
}
- (void)mouseDown:(NSEvent *)event {
    if (!self.dragEnabled) { return; }
    if (self.onDragBegan) { self.onDragBegan(); }
    if (self.windowDragEnabled && self.window) { [self.window performWindowDragWithEvent:event]; }
    if (self.onDragEnded) { self.onDragEnded(); }
}
@end

@implementation FYInlineLongCardView
@synthesize pressState = _pressState;
@dynamic pressPoint, pressMovedBeyondThreshold, collapsePressed, titleBarHeight;
- (FYInlineCardPressState *)pressState {
    if (!_pressState) { _pressState = [FYInlineCardPressState new]; }
    return _pressState;
}
- (NSPoint)pressPoint { return self.pressState.pressPoint; }
- (void)setPressPoint:(NSPoint)value { self.pressState.pressPoint = value; }
- (BOOL)pressMovedBeyondThreshold { return self.pressState.pressMovedBeyondThreshold; }
- (void)setPressMovedBeyondThreshold:(BOOL)value { self.pressState.pressMovedBeyondThreshold = value; }
- (BOOL)collapsePressed { return self.pressState.collapsePressed; }
- (void)setCollapsePressed:(BOOL)value { self.pressState.collapsePressed = value; }
- (CGFloat)titleBarHeight { return self.pressState.titleBarHeight; }
- (void)setTitleBarHeight:(CGFloat)value { self.pressState.titleBarHeight = value; }
- (void)setCollapseControlHighlighted:(BOOL)value { self.collapseButton.highlighted = value; }
- (void)performCollapseAfterPressRelease { [self handleCollapseControl:self.collapseButton]; }
- (void)performClickAfterPressRelease { if (self.onClick) { self.onClick(); } }

- (BOOL)isFlipped { return YES; }
// 命中测试直接返回卡片本身：内部文本不会吞掉「打开学习」的点击。
// 「收起」按钮不交给 NSButton 自己命中 —— 实测 NSButton.hitTest: 对"自建 frame 的按钮"
// 会返回 nil（同一个卡片里 buttonWithTitle: 建的按钮却正常），于是按钮点不到、卡收不起来。
// 改成卡片自己在 mouseDown/mouseUp 里判定按钮区域，行为完全可控（见 pointIsInCollapseControl:）。
- (NSView *)hitTest:(NSPoint)point {
    if (self.hidden) { return nil; }
    NSPoint local = [self convertPoint:point fromView:self.superview];
    if (!NSPointInRect(local, self.bounds)) { return nil; }
    return self;
}

// 浮层窗口通常不是 key window：没有这个，第一次点击会被系统吃掉去激活窗口。
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

// 点是否落在「收起」按钮上（按钮 frame 与卡片同一坐标系）。
- (BOOL)pointIsInCollapseControl:(NSPoint)localPoint {
    NSButton *button = self.collapseButton;
    if (!button || button.hidden) { return NO; }
    return NSPointInRect(localPoint, NSInsetRect(button.frame, -2, -2));
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
    if (self) { _pressState = [FYInlineCardPressState new]; _pressState.titleBarHeight = 55; _windowDragEnabled = YES; }
    return self;
}
// 标题栏：内边距 + 标题带（flipped 坐标下 y 小的一侧）。
- (BOOL)pointIsInTitleBar:(NSPoint)localPoint {
    return [self.pressState pointIsInTitleBar:localPoint stateSource:self];
}
- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    [self.pressState beginPressAtPoint:point stateSource:self];
    // 「收起」按钮区域：按下先高亮，松手（没拖走）才真的收起。
    if ([self pointIsInCollapseControl:point]) {
        self.collapsePressed = YES;
        self.collapseButton.highlighted = YES;
        return;
    }
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
    [self.pressState dragPressToPoint:point stateSource:self nativeActions:self];
}
- (void)mouseUp:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    [self.pressState releasePressAtPoint:point stateSource:self nativeActions:self];
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas.copy) { [self removeTrackingArea:area]; }
    NSTrackingArea *tracking = [[NSTrackingArea alloc] initWithRect:self.bounds options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect) owner:self userInfo:nil];
    [self addTrackingArea:tracking];
}
- (void)mouseEntered:(NSEvent *)event { if (self.onHover) { self.onHover(YES); } }
- (void)mouseExited:(NSEvent *)event { if (self.onHover) { self.onHover(NO); } }

// 在标题栏右侧装上「收起」按钮。展开卡没有别的收起入口（只有 Esc）时用户会以为收不回去，
// 所以这里给一个看得见、点得到的按钮；展开后再点同一个贴片也能收起。
- (void)installCollapseControl {
    if (_collapseButton) { return; }
    CGFloat padding = 14;
    CGFloat width = 62, height = 24;
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(NSWidth(self.bounds) - padding - width, padding, width, height)];
    button.title = @"收起";
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeSmall;
    button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    button.target = self;
    button.action = @selector(handleCollapseControl:);
    button.autoresizingMask = NSViewMinXMargin;
    button.toolTip = @"收起这张展开的译文卡（也可再点一次贴片或按 Esc）";
    [self addSubview:button];
    _showsCollapseControl = YES;
    _collapseButton = button;
    // 「已选中」标识往左让位，避免和收起按钮叠在一起。
    if (self.selectedBadgeBox) {
        self.selectedBadgeBox.frame = NSOffsetRect(self.selectedBadgeBox.frame, -(width + 6), 0);
    }
}
- (void)handleCollapseControl:(id)sender {
    if (self.onCollapse) { self.onCollapse(); }
}
@end








