#import "FYInlineCardRenderer.h"
#import "../FYInlineLayout.h"

@implementation FYInlineCardRenderer
- (InlinePanelLayout)inlinePanelLayoutFromPlacement:(FYInlinePlacement *)placement {
    InlinePanelLayout layout;
    layout.frame = placement.translationFrame;
    layout.labelFrame = placement.labelFrame;
    layout.font = placement.font;
    layout.cornerRadius = placement.cornerRadius;
    return layout;
}

- (NSParagraphStyle *)inlineLongCardBodyStyleWithSource:(id<FYInlineCardRenderSource>)source {
    // 段落样式由布局引擎给出：测量与绘制必须完全同一份。
    return [source.inlineLayoutEngine longBodyParagraphStyle];
}

- (NSFont *)inlineLongCardBodyFontWithSource:(id<FYInlineCardRenderSource>)source {
    // 长卡正文用正常阅读字重；层级靠标题（半粗）和内边距来体现，不靠把正文加粗。
    return [source.inlineLayoutEngine longBodyFont];
}

- (CGFloat)inlineLongCardBodyLineHeightWithSource:(id<FYInlineCardRenderSource>)source {
    NSFont *font = [source inlineLongCardBodyFont];
    return FYInlineLongCardLineHeight(font.ascender, font.descender, font.leading);
}

- (CGFloat)inlineLongCardMinimumHeightWithSource:(id<FYInlineCardRenderSource>)source {
    return FYInlineLongCardMinimumHeight([source inlineLongCardBodyLineHeight]);
}

- (CGFloat)inlineLongCardBodyViewportForHeight:(CGFloat)cardHeight {
    return FYInlineLongCardBodyViewport(cardHeight);
}

- (void)applyInlineLongCardBody:(NSString *)translation
                        toLabel:(NSTextField *)label
                       cardWidth:(CGFloat)cardWidth
                       placement:(FYInlinePlacement *)placement source:(id<FYInlineCardRenderSource>)source {
    CGFloat padding = placement.panelPadding > 0 ? placement.panelPadding : 18;
    FYApplyInlineLongCardBody(translation, label, cardWidth, padding,
                             placement.font ?: [source inlineLongCardBodyFont],
                             placement.paragraphStyle ?: [source inlineLongCardBodyStyle], [source inlinePanelTextColor]);
}

- (NSView *)inlineLongCardContentForTranslation:(NSString *)translation
                                           size:(NSSize)size
                                       selected:(BOOL)selected
                                        compact:(BOOL)compact
                                      placement:(FYInlinePlacement *)placement source:(id<FYInlineCardRenderSource>)source {
    // 紧凑入口的宽度就是引擎量出来的宽度（过去这里硬抬到 160，label 按 140 排版而面板只有 120，
    // 测量与绘制口径不一致）；长卡仍保留 160 的可读下限。
    NSSize cardSize = FYInlineLongCardSize(size, compact);
    CGFloat cardWidth = cardSize.width;
    CGFloat cardHeight = cardSize.height;
    FYInlineLongCardView *card = [[FYInlineLongCardView alloc] initWithFrame:NSMakeRect(0, 0, cardWidth, cardHeight)];
    card.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    card.showsSelectedBadge = selected;
    card.compactEntry = compact;
    // 内容创建时即按真实标题带划分拖动区；显式卡框入口也不能沿用旧的 55pt。
    card.titleBarHeight = compact ? 0 : ((placement.panelPadding > 0 ? placement.panelPadding : 18) + placement.titleBandHeight);
    if (compact) {
        [source applyInlineCompactEntryChromeToContent:card cornerRadius:8];
    } else {
        [source applyInlineChromeToContent:card cornerRadius:12];
    }

    if (compact) {
        // 折叠入口：块标题 / 收起原因 / 「点击展开 ▾」三行，整卡可点。
        // 三行文案与尺寸都来自布局引擎的测量（同一份字体与文案），所以提示不会被截断，
        // 也不会出现"只有悬停才看得到原因"的情况。
        card.toolTip = @"点击展开完整译文（展开后：卡片上的「收起」、再点一次贴片、或 Esc 都能收起）";
        NSString *title = placement.entryTitle.length > 0 ? placement.entryTitle
            : (source.inlineLayoutEngine.foldedEntryFallbackTitle ?: @"这段译文");
        // nil 才回退默认文案；空字符串表示"这一行不要"（单行总入口）。
        NSString *hint = placement.entryHint != nil ? placement.entryHint
            : (source.inlineLayoutEngine.foldedEntryHintTooLong ?: @"文本过长，已收起");
        NSString *action = placement.entryAction != nil ? placement.entryAction
            : (source.inlineLayoutEngine.compactEntryTitle ?: @"点击展开");
        CGFloat padding = MAX((CGFloat)6, source.inlineLayoutEngine.compactEntryHorizontalPadding);
        FYInstallInlineFoldedEntry(card, cardWidth, padding, title, hint, action,
            [source.inlineLayoutEngine compactEntryFont], [source.inlineLayoutEngine foldedEntryHintFont],
            [source inlinePanelTitleColor], [source inlinePanelTextColor], [source inlinePanelTextColor],
            ^NSTextField *(NSString *text, NSFont *font, NSColor *color) {
                return [source inlineCompactEntryLabel:text font:font color:color];
            });
        return card;
    }
    card.toolTip = @"点击查看原文和语法";

    // 内边距与标题带由布局引擎给出：与测量用的是同一组常量，避免“测出来”和“画出来”不一致。
    CGFloat padding = placement.panelPadding > 0 ? placement.panelPadding : 18;
    // 普通贴译不画标题或分隔线，正文从 padding 开始；展开阅读保留标题带。
    BOOL showsTitleBand = placement.expandedReading && placement.titleBandHeight > 0.5;
    CGFloat titleBand = 24;
    // 注意：FYInlineLongCardView 是 flipped（y=0 在顶部），所以标题在 padding 处、正文在标题下方。
    // 顶部小标题：未选中时不显示「已选中」，避免把预览状态写死。
    if (showsTitleBand) {
        NSString *cardTitle = placement.entryTitle.length > 0 ? placement.entryTitle
            : (placement.block ? ([source inlineCardTitleForBlockText:placement.block.text] ?: nil) : nil);
        if (cardTitle.length == 0) { cardTitle = source.inlineLayoutEngine.foldedEntryFallbackTitle ?: @"这段译文"; }
        NSTextField *title = [source label:cardTitle font:[source inlinePanelFontOfSize:14 weight:NSFontWeightSemibold] color:[source inlinePanelTitleColor]];
        NSTextField *badge = [source label:@"已选中" font:[source inlinePanelFontOfSize:13] color:[source inlineCardInkColor]];
        FYInstallInlineLongCardHeader(card, cardWidth, padding, titleBand, selected, title, badge,
                                     [source inlineCardMintColor], [[source inlineCardRimColor] colorWithAlphaComponent:0.95]);
    }

    // 正文：清晰内边距 + 舒适行距；超长时在卡内滚动。
    NSRect bodyFrame = FYInlineLongCardBodyFrame(cardWidth, cardHeight, padding, placement.titleBandHeight);
    CGFloat textWidth = NSWidth(bodyFrame);
    NSScrollView *scroll = FYCreateInlineLongCardBodyScroll(translation,
        bodyFrame, cardWidth, padding,
        placement.font ?: [source inlineLongCardBodyFont],
        placement.paragraphStyle ?: [source inlineLongCardBodyStyle], [source inlinePanelTextColor]);
    [card addSubview:scroll];
    // 底部提示：明确"其他贴译已暂时隐藏"和"Esc 收起"，不必靠猜。
    NSTextField *footer = [source label:@"其他贴译已暂时隐藏　·　Esc 收起"
                                 font:[source.inlineLayoutEngine foldedEntryHintFont]
                                color:[source inlinePanelTitleColor]];
    footer.lineBreakMode = NSLineBreakByTruncatingTail;
    FYInstallInlineLongCardFooter(card, footer, padding, cardHeight, textWidth);
    return card;
}

- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(NSRect)frame translation:(NSString *)translation expandedReading:(BOOL)expandedReading source:(id<FYInlineCardRenderSource>)source {
    FYInlinePlacement *placement = [FYInlinePlacement new];
    placement.mode = FYInlineDisplayModeScrollingCard;
    placement.panelPadding = 18;
    placement.expandedReading = expandedReading;
    placement.titleBandHeight = expandedReading ? (24 + 13) : 0;
    placement.cornerRadius = 12;
    placement.font = [source.inlineLayoutEngine longBodyFont];
    placement.paragraphStyle = [source.inlineLayoutEngine longBodyParagraphStyle];
    placement.translation = translation ?: @"";
    placement.translationFrame = frame;
    placement.measuredContentHeight = [source.inlineLayoutEngine measuredBodyHeight:translation placement:placement width:NSWidth(frame)] + 4;
    placement.bodyViewportFrame = FYInlineLongCardBodyFrame(NSWidth(frame), NSHeight(frame), placement.panelPadding, placement.titleBandHeight);
    placement.bodyViewportHeight = NSHeight(placement.bodyViewportFrame);
    placement.scrollable = placement.measuredContentHeight > placement.bodyViewportHeight + 0.5;
    return placement;
}

- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame placement:(FYInlinePlacement *)placement source:(id<FYInlineCardRenderSource>)source {
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
    panel.contentView = [source inlineLongCardContentForTranslation:translation size:frame.size
                                                        selected:[source inlineHostBlockID:placement.blockID isSelectedForItem:item]
                                                         compact:placement.compactEntry
                                                       placement:placement];
    [source inlineCardWirePanelThroughHost:panel item:item translation:translation frame:frame stableBlockID:placement.blockID];
    return panel;
}

- (void)updateInlineLongCard:(NSPanel *)panel
                 translation:(NSString *)translation
                        item:(OCRTextItem *)item
                       frame:(NSRect)frame
                     compact:(BOOL)compact
                   placement:(FYInlinePlacement *)placement source:(id<FYInlineCardRenderSource>)source {
    if (!placement) { placement = [source inlinePlacementForLongCardFrame:frame translation:translation]; }
    if (!NSEqualRects(panel.frame, frame)) { [panel setFrame:frame display:NO]; }
    NSView *existing = panel.contentView;
    NSScrollView *existingScroll = nil;
    for (NSView *child in existing.subviews) {
        if ([child isKindOfClass:NSScrollView.class]) { existingScroll = (NSScrollView *)child; break; }
    }
    CGFloat bodyPadding = placement.panelPadding > 0 ? placement.panelPadding : 18;
    NSRect expectedBodyFrame = FYInlineLongCardBodyFrame(NSWidth(frame), NSHeight(frame), bodyPadding, placement.titleBandHeight);
    BOOL bodyGeometryMatches = compact || (existingScroll && NSEqualRects(existingScroll.frame, expectedBodyFrame));
    BOOL selected = [source inlineHostBlockID:placement.blockID isSelectedForItem:item];
    BOOL compactCopyChanged = NO;
    if (compact && [existing isKindOfClass:FYInlineLongCardView.class]) {
        FYInlineLongCardView *entryCard = (FYInlineLongCardView *)existing;
        NSString *expectedHint = placement.entryHint ?: @"";
        if (entryCard.foldedEntryHintLabel && expectedHint.length > 0 &&
            ![entryCard.foldedEntryHintLabel.stringValue isEqualToString:expectedHint]) {
            compactCopyChanged = YES;
        }
        NSTextField *title = [entryCard.subviews.firstObject isKindOfClass:NSTextField.class]
            ? (NSTextField *)entryCard.subviews.firstObject : nil;
        compactCopyChanged = compactCopyChanged || ![title.font isEqual:[source.inlineLayoutEngine compactEntryFont]] ||
            (entryCard.foldedEntryHintLabel && ![entryCard.foldedEntryHintLabel.font isEqual:[source.inlineLayoutEngine foldedEntryHintFont]]);
    }
    if (!compactCopyChanged && bodyGeometryMatches && [existing isKindOfClass:FYInlineLongCardView.class] && NSEqualSizes(existing.frame.size, frame.size) &&
        [(FYInlineLongCardView *)existing showsSelectedBadge] == selected &&
        [(FYInlineLongCardView *)existing compactEntry] == compact) {
        // 尺寸与选中态都没变：只换正文，保留滚动视图与点击目标，避免重建导致的闪烁与事件丢失。
        NSScrollView *scroll = nil;
        for (NSView *child in existing.subviews) { if ([child isKindOfClass:NSScrollView.class]) { scroll = (NSScrollView *)child; break; } }
        NSView *document = scroll.documentView;
        if ([document isKindOfClass:NSTextField.class]) {
            NSTextField *label = (NSTextField *)document;
            // 用同一份字体/段落样式重新测量：卡片尺寸没变但文章更长时，文档必须跟着长高。
            [source applyInlineLongCardBody:translation toLabel:label cardWidth:NSWidth(frame) placement:placement];
            NSPoint origin = scroll.contentView.bounds.origin;
            CGFloat maxY = MAX((CGFloat)0, NSHeight(label.frame) - NSHeight(scroll.contentView.bounds));
            if (origin.y > maxY) {
                origin.y = maxY;
                [scroll.contentView scrollToPoint:origin];
                [scroll reflectScrolledClipView:scroll.contentView];
            }
        }
    } else {
        panel.contentView = [source inlineLongCardContentForTranslation:translation size:frame.size selected:selected compact:compact placement:placement];
    }
    [source inlineCardWirePanelThroughHost:panel item:item translation:translation frame:frame stableBlockID:placement.blockID];
    [panel displayIfNeeded];
}

- (void)updateInlinePanel:(NSPanel *)panel
              translation:(NSString *)translation
               sourceText:(NSString *)sourceText
              sourceFrame:(NSRect)sourceFrame
              windowFrame:(NSRect)windowFrame
                   layout:(InlinePanelLayout)layout source:(id<FYInlineCardRenderSource>)source {
    NSView *content = panel.contentView;
    NSView *firstSubview = content.subviews.firstObject;
    if (!content || ![firstSubview isKindOfClass:NSTextField.class]) { return; }
    NSTextField *label = (NSTextField *)firstSubview;

    // 先改窗口尺寸（display:NO 不立即重画），再改文字，最后一次性显示，避免中间态闪一下
    if (!NSEqualRects(panel.frame, layout.frame)) { [panel setFrame:layout.frame display:NO]; }
    if (!NSEqualRects(content.frame, NSMakeRect(0, 0, NSWidth(layout.frame), NSHeight(layout.frame)))) {
        content.frame = NSMakeRect(0, 0, NSWidth(layout.frame), NSHeight(layout.frame));
    }
    if (![label.stringValue isEqualToString:translation] || ![label.font isEqual:layout.font]) {
        label.font = layout.font;
        label.attributedStringValue = [source inlinePanelAttributedText:translation font:layout.font];
    }
    if (!NSEqualRects(label.frame, layout.labelFrame)) { label.frame = layout.labelFrame; }
    [source applyInlineChromeToContent:content cornerRadius:layout.cornerRadius];
    [panel displayIfNeeded];
}

- (NSAttributedString *)inlinePanelAttributedText:(NSString *)translation font:(NSFont *)font source:(id<FYInlineCardRenderSource>)source {
    NSParagraphStyle *paragraphStyle = [source.inlineLayoutEngine shortParagraphStyle];
    return [[NSAttributedString alloc] initWithString:translation
                                           attributes:@{NSFontAttributeName: font,
                                                        NSForegroundColorAttributeName: [source inlinePanelTextColor],
                                                        NSParagraphStyleAttributeName: paragraphStyle}];
}

- (void)applyInlineChromeToContent:(NSView *)content cornerRadius:(CGFloat)cornerRadius source:(id<FYInlineCardRenderSource>)source {
    content.wantsLayer = YES;
    content.layer.backgroundColor = [source inlinePanelFillColor].CGColor;
    content.layer.cornerRadius = cornerRadius;
    content.layer.borderWidth = 1.5;
    content.layer.borderColor = [source inlinePanelBorderColor].CGColor;
    content.layer.shadowColor = [source inlineCardLineColor].CGColor;
    content.layer.shadowOpacity = 0.32;
    content.layer.shadowRadius = 7;
    content.layer.shadowOffset = CGSizeMake(0, -2);
    content.layer.masksToBounds = NO;
}

- (void)applyInlineCompactEntryChromeToContent:(NSView *)content cornerRadius:(CGFloat)cornerRadius source:(id<FYInlineCardRenderSource>)source {
    [source applyInlineChromeToContent:content cornerRadius:cornerRadius];
    content.layer.backgroundColor = [source inlinePanelFillColor].CGColor;
    content.layer.borderWidth = 1.8;
    content.layer.borderColor = [source inlinePanelBorderColor].CGColor;
    content.layer.shadowOpacity = 0.45;
    content.layer.shadowRadius = 6;
}

- (NSTextField *)inlineCompactEntryLabel:(NSString *)text font:(NSFont *)font color:(NSColor *)color source:(id<FYInlineCardRenderSource>)source {
    NSTextField *label = [source label:text font:font color:color];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [[NSColor whiteColor] colorWithAlphaComponent:0.85];
    shadow.shadowBlurRadius = 2.5;
    shadow.shadowOffset = NSMakeSize(0, -1);
    label.shadow = shadow;
    return label;
}

- (NSPanel *)inlinePanelForTranslation:(NSString *)translation sourceText:(NSString *)sourceText sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame layout:(InlinePanelLayout)layout source:(id<FYInlineCardRenderSource>)source {

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
    content.dragHintColor = [source inlinePanelTextColor];
    content.normalBorderColor = [source inlinePanelBorderColor];
    content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    content.wantsLayer = YES;
    [source applyInlineChromeToContent:content cornerRadius:layout.cornerRadius];

    NSTextField *label = [source label:translation font:layout.font color:[source inlinePanelTextColor]];
    label.frame = layout.labelFrame;
    label.attributedStringValue = [source inlinePanelAttributedText:translation font:layout.font];
    label.maximumNumberOfLines = 0;
    label.lineBreakMode = NSLineBreakByCharWrapping;
    label.usesSingleLineMode = NO;
    label.cell.wraps = YES;
    label.cell.scrollable = NO;
    [content addSubview:label];

    panel.contentView = content;
    return panel;
}

- (void)refreshInlinePanelAppearanceWithSource:(id<FYInlineCardRenderSource>)source {
    NSColor *fill = [source inlinePanelFillColor];
    NSMutableArray<NSPanel *> *panels = [source.inlineTranslationPanels mutableCopy] ?: [NSMutableArray array];
    [panels addObjectsFromArray:source.inlineLongCardPanels ?: @[]];
    if (source.inlineExpandedReadingPanel) { [panels addObject:source.inlineExpandedReadingPanel]; }
    if (source.inlineOverflowPanel) { [panels addObject:source.inlineOverflowPanel]; }
    for (NSPanel *panel in panels) {
        NSView *content = panel.contentView;
        if (content.layer) { content.layer.backgroundColor = fill.CGColor; content.layer.borderColor = [source inlinePanelBorderColor].CGColor; }
        if ([content isKindOfClass:FYInlinePatchView.class]) {
            FYInlinePatchView *patch = (FYInlinePatchView *)content;
            patch.normalBorderColor = [source inlinePanelBorderColor]; patch.dragHintColor = [source inlinePanelTextColor];
            patch.showsDragHint = patch.showsDragHint;
        }
    }
}

- (void)applyInlineTextColor:(NSColor *)color toView:(NSView *)view source:(id<FYInlineCardRenderSource>)source {
    if ([view isKindOfClass:NSTextField.class]) {
        NSTextField *label = (NSTextField *)view;
        NSAttributedString *current = label.attributedStringValue;
        // 正文用富文本设置颜色，textColor 属性可能仍是 AppKit 默认的半透明标签色。
        NSColor *oldColor = current.length > 0 ? [current attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] : nil;
        oldColor = oldColor ?: label.textColor;
        CGFloat alpha = oldColor ? oldColor.alphaComponent : 1;
        NSColor *textColor = fabs(alpha - color.alphaComponent) < 0.001 ? color : [color colorWithAlphaComponent:alpha];
        if (![oldColor isEqual:textColor] || ![label.textColor isEqual:textColor]) {
            NSMutableAttributedString *text = [current mutableCopy];
            [text addAttribute:NSForegroundColorAttributeName value:textColor range:NSMakeRange(0, text.length)];
            label.textColor = textColor;
            label.attributedStringValue = text;
        }
    }
    for (NSView *child in view.subviews) {
        if ([view isKindOfClass:FYInlineLongCardView.class] && child == ((FYInlineLongCardView *)view).selectedBadgeBox) { continue; }
        [source applyInlineTextColor:color toView:child];
    }
}

- (void)refreshInlinePanelTextAppearanceWithSource:(id<FYInlineCardRenderSource>)source {
    NSMutableArray<NSPanel *> *panels = [source.inlineTranslationPanels mutableCopy] ?: [NSMutableArray array];
    [panels addObjectsFromArray:source.inlineLongCardPanels ?: @[]];
    if (source.inlineExpandedReadingPanel) { [panels addObject:source.inlineExpandedReadingPanel]; }
    if (source.inlineOverflowPanel) { [panels addObject:source.inlineOverflowPanel]; }
    for (NSPanel *panel in panels) {
        [source applyInlineTextColor:[source inlinePanelTextColor] toView:panel.contentView];
    }
}
@end
