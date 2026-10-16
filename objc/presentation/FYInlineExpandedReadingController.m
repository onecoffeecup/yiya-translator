#import "FYInlineExpandedReadingController.h"
#import "../FYInlineLayout.h"
#import "../inline/FYInlineOverlayViews.h"

@implementation FYInlineExpandedReadingController
- (NSSize)expandedInlineReadingSizeForTranslation:(NSString *)translation viewport:(NSRect)viewport source:(id<FYInlineExpandedReadingSource>)source {
    CGFloat width = floor(MIN(MAX((CGFloat)160, source.inlineLayoutEngine.cardMaxWidth), MAX((CGFloat)1, NSWidth(viewport) - 24)));
    FYInlinePlacement *measured = [source inlinePlacementForLongCardFrame:NSMakeRect(0, 0, width, 0)
                                                         translation:translation expandedReading:YES];
    CGFloat naturalHeight = measured.measuredContentHeight + measured.panelPadding * 2 + measured.titleBandHeight + 16;
    CGFloat height = floor(MIN(MAX((CGFloat)160, naturalHeight),
        MIN(source.inlineLayoutEngine.cardMaxHeight, MAX((CGFloat)1, NSHeight(viewport) - 24))));
    return NSMakeSize(width, height);
}

- (void)refreshExpandedInlineReadingCardAppearanceInRect:(NSRect)viewport source:(id<FYInlineExpandedReadingSource>)source {
    NSPanel *panel = source.inlineExpandedReadingPanel;
    if (!panel || ![panel.contentView isKindOfClass:FYInlineLongCardView.class] || NSWidth(viewport) < 2 || NSHeight(viewport) < 2) { return; }
    FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
    NSScrollView *scroll = nil;
    for (NSView *child in card.subviews) {
        if ([child isKindOfClass:NSScrollView.class]) { scroll = (NSScrollView *)child; break; }
    }
    if (![scroll.documentView isKindOfClass:NSTextField.class]) { return; }
    NSTextField *label = (NSTextField *)scroll.documentView;
    NSString *translation = label.stringValue;
    CGFloat offsetFromTop = 0;
    if (!card.expandedFooterLabel.hidden) {
        offsetFromTop = label.isFlipped ? NSMinY(scroll.contentView.bounds)
            : MAX((CGFloat)0, NSHeight(label.frame) - NSMaxY(scroll.contentView.bounds));
    }
    NSSize size = [source expandedInlineReadingSizeForTranslation:translation viewport:viewport];
    NSRect frame = panel.frame;
    CGFloat x = MIN(MAX(NSMidX(frame) - size.width / 2, NSMinX(viewport) + 12), MAX(NSMinX(viewport) + 12, NSMaxX(viewport) - size.width - 12));
    CGFloat y = MIN(MAX(NSMaxY(frame) - size.height, NSMinY(viewport) + 12), MAX(NSMinY(viewport) + 12, NSMaxY(viewport) - size.height - 12));
    NSRect target = NSMakeRect(round(x), round(y), size.width, size.height);
    if (!NSEqualRects(frame, target)) { [panel setFrame:target display:NO]; }
    FYInlinePlacement *placement = [source inlinePlacementForLongCardFrame:target translation:translation expandedReading:YES];
    NSRect bodyFrame = placement.bodyViewportFrame;
    bodyFrame.size.height = MAX((CGFloat)40, NSHeight(bodyFrame) - 16);
    scroll.frame = bodyFrame;
    [source applyInlineLongCardBody:translation toLabel:label cardWidth:size.width placement:placement];
    CGFloat maxOrigin = MAX((CGFloat)0, NSHeight(label.frame) - NSHeight(scroll.contentView.bounds));
    CGFloat origin = label.isFlipped ? offsetFromTop : maxOrigin - offsetFromTop;
    [scroll.contentView scrollToPoint:NSMakePoint(0, MIN(maxOrigin, MAX((CGFloat)0, origin)))];
    [scroll reflectScrolledClipView:scroll.contentView];
    card.expandedFooterLabel.hidden = NO;
    panel.contentView.needsDisplay = YES;
}

- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item
                             translation:(NSString *)translation
                           stableBlockID:(NSString *)stableBlockID source:(id<FYInlineExpandedReadingSource>)source {
    NSRect placement = NSZeroRect;
    if (![source inlinePlacementRect:&placement reason:NULL]) { return; }
    [source closeExpandedInlineReadingCard];
    NSSize size = [source expandedInlineReadingSizeForTranslation:translation viewport:placement];
    CGFloat width = size.width, height = size.height;
    // 优先贴着原文展开：原文下方放得下就放下方，否则上方；都不行才退回显示区域居中。
    // 无论哪种都必须完整落在**游戏显示区域**内（不落到 OBS 控制区、不出画面）。
    CGRect sourceFrame = CGRectZero;
    BOOL hasSourceFrame = NO;
    for (FYInlinePlacement *known in source.lastInlineLayoutResult.placements) {
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
    FYInlinePlacement *cardPlacement = [source inlinePlacementForLongCardFrame:NSIntegralRect(NSMakeRect(x, y, width, height))
                                                                 translation:translation expandedReading:YES];
    cardPlacement.entryTitle = [FYInlineLayoutEngine shortTitleForBlockText:item.text ?: @""]
        ?: (source.inlineLayoutEngine.foldedEntryFallbackTitle ?: @"这段译文");
    if (stableBlockID.length > 0) { cardPlacement.blockID = stableBlockID; }
    NSPanel *panel = [source inlineLongPanelForTranslation:translation item:item
                                                    frame:cardPlacement.translationFrame
                                                placement:cardPlacement];
    if (!panel) { return; }
    source.inlineExpandedReadingPanel = panel;
    source.inlineExpandedReadingBlockID = cardPlacement.blockID ?: stableBlockID;
    source.inlineExpandedMissingFrames = 0;
    // 展开时临时隐藏其它贴译与折叠入口：只留这一块，避免阅读卡被一堆浮层盖住。
    [source hideOtherInlinePanelsForExpandedReading:panel];
    // 可见的收起入口：只有 Esc 的话用户会认为“展开后收不回去”。
    if ([panel.contentView isKindOfClass:FYInlineLongCardView.class]) {
        FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
        __weak id<FYInlineExpandedReadingSource> weakSelf = source;
        card.onCollapse = ^{ [weakSelf closeExpandedInlineReadingCard]; };
        [card installCollapseControl];
    }
    [source refreshExpandedInlineReadingCardAppearanceInRect:placement];
    // 阅读卡沿用现有标题栏拖动（正文滚动与按钮点击不误触拖动）。
    [source wireInlinePanelDrag:panel placement:cardPlacement];
    [panel orderFrontRegardless];
    __weak id<FYInlineExpandedReadingSource> weakSelf = source;
    if (!source.inlineExpandedReadingKeyMonitor) {
        source.inlineExpandedReadingKeyMonitor = [source installInlineExpandedReadingMonitorWithHandler:^NSEvent *(NSEvent *event) {
            if (event.keyCode != 53) { return event; }
            [weakSelf closeExpandedInlineReadingCard];
            return nil;
        }];
    }
}

- (void)repositionExpandedInlineReadingCardInRect:(NSRect)viewport source:(id<FYInlineExpandedReadingSource>)source {
    NSPanel *panel = source.inlineExpandedReadingPanel;
    if (!panel || NSWidth(viewport) < 2 || NSHeight(viewport) < 2) { return; }
    NSRect frame = panel.frame;
    CGFloat width = MIN(NSWidth(frame), MAX((CGFloat)240, NSWidth(viewport) - 24));
    CGFloat height = MIN(NSHeight(frame), MAX((CGFloat)180, NSHeight(viewport) - 24));
    CGFloat x = MIN(MAX(NSMidX(frame) - width / 2.0, NSMinX(viewport) + 12), MAX(NSMinX(viewport) + 12, NSMaxX(viewport) - width - 12));
    CGFloat y = MIN(MAX(NSMidY(frame) - height / 2.0, NSMinY(viewport) + 12), MAX(NSMinY(viewport) + 12, NSMaxY(viewport) - height - 12));
    NSRect target = NSIntegralRect(NSMakeRect(x, y, width, height));
    if (!NSEqualRects(panel.frame, target)) { [panel setFrame:target display:YES]; }
}

- (void)advanceExpandedReadingStateWithSource:(id<FYInlineExpandedReadingSource>)source {
    if (!source.inlineExpandedReadingPanel) { return; }
    NSString *blockID = source.inlineExpandedReadingBlockID ?: @"";
    BOOL present = NO;
    for (FYInlinePlacement *placement in source.lastInlineLayoutResult.placements) {
        if (blockID.length > 0 && [placement.blockID isEqualToString:blockID]) { present = YES; break; }
    }
    if (present) {
        source.inlineExpandedMissingFrames = 0;
    } else if (++source.inlineExpandedMissingFrames >= 2) {
        [source closeExpandedInlineReadingCard];
        return;
    }
    if (source.inlineExpandedReadingPanel) {
        [source hideOtherInlinePanelsForExpandedReading:source.inlineExpandedReadingPanel];
    }
}

- (void)closeExpandedInlineReadingCardWithSource:(id<FYInlineExpandedReadingSource>)source {
    if (source.inlineExpandedReadingKeyMonitor) {
        [source removeInlineExpandedReadingMonitor:source.inlineExpandedReadingKeyMonitor];
        source.inlineExpandedReadingKeyMonitor = nil;
    }
    [source.inlineExpandedReadingPanel close];
    source.inlineExpandedReadingPanel = nil;
    source.inlineExpandedReadingBlockID = nil;
    source.inlineExpandedMissingFrames = 0;
    // 恢复：用**当前这一帧**的排版结果把该显示的贴译放回来（不复活换页前的旧面板）。
    [source restoreOtherInlinePanelsAfterExpandedReading];
}
@end
