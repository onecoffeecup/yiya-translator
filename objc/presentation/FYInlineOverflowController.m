#import "FYInlineOverflowController.h"
#import "FYFlippedDocumentView.h"
#import "../FYInlineLayout.h"

@implementation FYInlineOverflowController
- (void)positionInlineOverflowEntryInViewport:(NSRect)viewport source:(id<FYInlineOverflowNativeSource>)source {
    NSPanel *panel = source.inlineOverflowPanel;
    if (!panel || NSWidth(viewport) < 2 || NSHeight(viewport) < 2) { return; }
    CGSize size = panel.frame.size;
    CGFloat margin = MAX((CGFloat)8, source.inlineLayoutEngine.viewportMargin);
    CGFloat minX = NSMinX(viewport) + margin, maxX = NSMaxX(viewport) - margin - size.width;
    CGFloat minY = NSMinY(viewport) + margin, maxY = NSMaxY(viewport) - margin - size.height;
    if (maxX < minX) { maxX = minX; }
    if (maxY < minY) { maxY = minY; }
    CGFloat midX = NSMidX(viewport) - size.width / 2.0;
    CGFloat midY = NSMidY(viewport) - size.height / 2.0;

    NSMutableArray<NSValue *> *obstacles = [NSMutableArray array];
    for (NSPanel *other in [source allInlineOverlayPanels]) {
        if (other == panel || !other.isVisible) { continue; }
        [obstacles addObject:[NSValue valueWithRect:other.frame]];
    }
    if (source.captionPanel && source.captionPanel.isVisible) { [obstacles addObject:[NSValue valueWithRect:source.captionPanel.frame]]; }
    for (FYInlinePlacement *placement in source.lastInlineLayoutResult.placements) {
        if (NSWidth(placement.translationFrame) > 2) { [obstacles addObject:[NSValue valueWithRect:placement.translationFrame]]; }
        if (!CGRectIsEmpty(placement.sourceFrame)) { [obstacles addObject:[NSValue valueWithRect:placement.sourceFrame]]; }
    }
    if (source.inlineExpandedReadingPanel) { [obstacles addObject:[NSValue valueWithRect:source.inlineExpandedReadingPanel.frame]]; }

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

- (void)buildInlineOverflowEntryForViewport:(NSRect)viewport source:(id<FYInlineOverflowNativeSource>)source {
    NSString *title = [NSString stringWithFormat:@"还有 %lu 条译文 · 查看", (unsigned long)MAX((NSUInteger)1, source.inlineOverflowCount)];
    // 单行入口：不给 hint/action 行，尺寸就按这一行文字量。
    CGSize size = [source.inlineLayoutEngine foldedEntrySizeForViewport:viewport title:title hint:@"" action:@""];
    FYInlinePlacement *placement = [FYInlinePlacement new];
    placement.mode = FYInlineDisplayModeCompactEntry;
    placement.compactEntry = YES;
    placement.entryTitle = title;
    placement.entryHint = @"";
    placement.entryAction = @"";
    placement.panelPadding = 10;
    placement.cornerRadius = 8;
    placement.translationFrame = NSMakeRect(NSMinX(viewport) + 8, NSMinY(viewport) + 8, size.width, size.height);
    NSPanel *panel = [source inlineLongPanelForTranslation:@"" item:nil frame:placement.translationFrame placement:placement];
    if (!panel) { return; }
    panel.ignoresMouseEvents = NO;
    FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
    if ([card isKindOfClass:FYInlineLongCardView.class]) {
        __weak id<FYInlineOverflowNativeSource> weakSelf = source;
        card.onClick = ^{ [weakSelf showInlineOverflowChooser]; };
        card.titleBarHeight = 0;   // 边缘入口不可拖动，避免和"点击选择"冲突
    }
    source.inlineOverflowPanel = panel;
}

- (void)showInlineOverflowListWithSource:(id<FYInlineOverflowNativeSource>)source {
    NSRect viewport = NSZeroRect;
    BOOL hasViewport = [source inlinePlacementRect:&viewport reason:NULL];
    if (!hasViewport) {
        viewport = source.inlineOverflowPanel ? NSInsetRect(source.inlineOverflowPanel.frame, -60, -60) : NSMakeRect(0, 0, 480, 320);
    }
    CGFloat width = MIN((CGFloat)420, MAX((CGFloat)280, NSWidth(viewport) * 0.5));
    CGFloat rowHeight = 34;
    CGFloat rowSpacing = 6;
    CGFloat footerHeight = 40;
    CGFloat headerHeight = 30;
    CGFloat visibleRows = MIN((CGFloat)source.inlineOverflowEntries.count, 4);
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
    NSFont *choiceFont = [source.inlineLayoutEngine compactEntryFont];
    NSTextField *header = [source label:@"选择要读的译文" font:choiceFont color:[source inlineOverflowChooserInkColor]];
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
    CGFloat documentHeight = MAX(scrollHeight, source.inlineOverflowEntries.count * rowHeight +
                                              MAX(0, (NSInteger)source.inlineOverflowEntries.count - 1) * rowSpacing);
    // 用翻转文档视图：第 1 条在 y=0（顶部），配合下面的 scrollToPoint 保证"默认从第一条显示"。
    FlippedDocumentView *document = [[FlippedDocumentView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth, documentHeight)];
    for (NSUInteger index = 0; index < source.inlineOverflowEntries.count; index++) {
        NSDictionary *entry = source.inlineOverflowEntries[index];
        NSButton *button = [NSButton buttonWithTitle:[source overflowRowTitleForEntry:entry]
                                              target:[source inlineOverflowActionTarget]
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
    NSButton *closeButton = [NSButton buttonWithTitle:@"关闭" target:[source inlineOverflowActionTarget] action:@selector(closeInlineOverflowChoiceAction:)];
    closeButton.bezelStyle = NSBezelStyleRounded;
    closeButton.font = [NSFont systemFontOfSize:12];
    closeButton.frame = NSMakeRect(width - inset - 76, inset - 2, 76, 26);
    closeButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [container addSubview:closeButton];
    NSTextField *hint = [source mutedLabel:@"Esc 也可以关闭"];
    hint.frame = NSMakeRect(inset, inset, MAX((CGFloat)80, width - inset * 2 - 84), 20);
    hint.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [container addSubview:hint];

    [source applyInlineChromeToContent:container cornerRadius:14];
    // The chooser is a native reading list with its own cream surface; retain
    // its button contrast and frozen identities while overlay palettes change.
    container.layer.backgroundColor = [source inlineOverflowChooserCreamColor].CGColor;
    container.layer.borderColor = [source inlineOverflowChooserLineColor].CGColor;
    panel.contentView = container;
    [panel setContentSize:NSMakeSize(width, height)];
    source.inlineOverflowChoicePanel = panel;
    [panel orderFrontRegardless];
    // 首次打开固定从第一条开始（不能把"文档视图默认原点"当第一条）。
    [scroll layoutSubtreeIfNeeded];
    [scroll.contentView scrollToPoint:NSMakePoint(0, 0)];
    [scroll reflectScrolledClipView:scroll.contentView];
    if (!source.inlineOverflowChoiceKeyMonitor) {
        __weak id<FYInlineOverflowNativeSource> weakSelf = source;
        source.inlineOverflowChoiceKeyMonitor = [source installInlineOverflowMonitorWithHandler:^NSEvent *(NSEvent *event) {
            if (event.keyCode != 53) { return event; }
            [weakSelf closeInlineOverflowChoice];
            return nil;
        }];
    }
}

- (void)resizeInlineOverflowEntryWithTitle:(NSString *)title viewport:(NSRect)viewport source:(id<FYInlineOverflowNativeSource>)source {
            FYInlineLongCardView *card = (FYInlineLongCardView *)source.inlineOverflowPanel.contentView;
            NSTextField *label = [card.subviews.firstObject isKindOfClass:NSTextField.class]
                ? (NSTextField *)card.subviews.firstObject : nil;
            CGSize size = [source.inlineLayoutEngine foldedEntrySizeForViewport:viewport title:title hint:@"" action:@""];
            NSRect frame = source.inlineOverflowPanel.frame;
            frame.size = size;
            [source.inlineOverflowPanel setFrame:frame display:NO];
            card.frame = NSMakeRect(0, 0, size.width, size.height);
            label.frame = NSMakeRect(NSMinX(label.frame), NSMinY(label.frame),
                                     MAX((CGFloat)60, size.width - NSMinX(label.frame) * 2), NSHeight(label.frame));
            label.stringValue = title;
            [source.inlineOverflowPanel displayIfNeeded];
}

- (void)closeInlineOverflowChoiceWithSource:(id<FYInlineOverflowNativeSource>)source {
    if (source.inlineOverflowChoiceKeyMonitor) {
        [source removeInlineOverflowMonitor:source.inlineOverflowChoiceKeyMonitor];
        source.inlineOverflowChoiceKeyMonitor = nil;
    }
    [source.inlineOverflowChoicePanel close];
    source.inlineOverflowChoicePanel = nil;
}
@end
