#import "FYInlineLayout.h"

NSRect FYInlineLongCardBodyFrame(CGFloat width, CGFloat height, CGFloat padding, CGFloat titleBandHeight) {
    CGFloat titleBand = 24;
    BOOL showsTitleBand = titleBandHeight > 0.5;
    CGFloat top = titleBandHeight > 0 ? padding + titleBandHeight : (showsTitleBand ? padding + titleBand + 13 : padding);
    return NSMakeRect(padding, top, MAX((CGFloat)80, width - padding * 2), MAX((CGFloat)24, height - top - padding));
}
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
    [card addSubview:title];
    if (selected) {
        NSView *badgeBox = [[NSView alloc] initWithFrame:NSMakeRect(cardWidth - padding - 72, padding, 72, titleBand + 2)];
        card.selectedBadgeBox = badgeBox;
        badgeBox.wantsLayer = YES;
        badgeBox.layer.backgroundColor = badgeColor.CGColor;
        badgeBox.layer.cornerRadius = (titleBand + 2) / 2.0;
        badge.alignment = NSTextAlignmentCenter;
        badge.frame = NSMakeRect(0, 4, 72, titleBand - 6);
        [badgeBox addSubview:badge];
        [card addSubview:badgeBox];
    }
    NSView *rule = [[NSView alloc] initWithFrame:NSMakeRect(padding, padding + titleBand + 2, cardWidth - padding * 2, 1)];
    rule.wantsLayer = YES;
    rule.layer.backgroundColor = ruleColor.CGColor;
    [card addSubview:rule];
}

void FYInstallInlineFoldedEntry(FYInlineLongCardView *card, CGFloat cardWidth, CGFloat padding,
    NSString *title, NSString *hint, NSString *action, NSFont *titleFont, NSFont *hintFont,
    NSColor *titleColor, NSColor *hintColor, NSColor *actionColor,
    NSTextField *(^labelFactory)(NSString *, NSFont *, NSColor *)) {
        CGFloat innerWidth = MAX((CGFloat)60, cardWidth - padding * 2);
        CGFloat titleHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading);
        CGFloat hintHeight = ceil(hintFont.ascender - hintFont.descender + hintFont.leading);
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
    NSRect measured = [translation boundingRectWithSize:NSMakeSize(textWidth, CGFLOAT_MAX)
                                                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                             attributes:@{NSFontAttributeName:font, NSParagraphStyleAttributeName:style}];
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
    CGFloat distance = hypot(point.x - self.pressPoint.x, point.y - self.pressPoint.y);
    if (distance > 4.0) {
        self.pressMovedBeyondThreshold = YES;
        if (self.collapsePressed) {
            // 按下后又拖走：取消这次收起（按钮不误触）。
            self.collapsePressed = NO;
            self.collapseButton.highlighted = NO;
        }
    }
}
- (void)mouseUp:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.collapsePressed) {
        self.collapsePressed = NO;
        self.collapseButton.highlighted = NO;
        if (!self.pressMovedBeyondThreshold && [self pointIsInCollapseControl:point]) {
            [self handleCollapseControl:self.collapseButton];
        }
        return;
    }
    if (self.pressMovedBeyondThreshold) { return; }   // 拖动结束不触发学习
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



CGFloat FYInlineLongCardLineHeight(CGFloat ascender, CGFloat descender, CGFloat leading) { return ceil(ascender - descender + leading) + 8; }
CGFloat FYInlineLongCardMinimumHeight(CGFloat lineHeight) { return 18 * 2 + (24 + 13) + lineHeight * 3.0; }
CGFloat FYInlineLongCardBodyViewport(CGFloat cardHeight) { return MAX(0, cardHeight - 18 * 2 - (24 + 13)); }

NSSize FYInlineLongCardSize(NSSize proposed, BOOL compact) {
    return NSMakeSize(compact ? MAX((CGFloat)60, proposed.width) : MAX((CGFloat)160, proposed.width),
                      MAX(compact ? (CGFloat)28 : (CGFloat)34, proposed.height));
}

#pragma mark - 通用小工具

static NSString *FYInlineTrim(NSString *value) {
    if (!value) { return @""; }
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

NSString *FYInlineNormalizeTranslationParagraphs(NSString *text) {
    if (text.length == 0) { return @""; }
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSString *> *paragraphs = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    for (NSString *raw in lines) {
        NSString *line = FYInlineTrim(raw);
        if (line.length == 0) {
            if (current.length > 0) { [paragraphs addObject:[current copy]]; [current setString:@""]; }
            continue;
        }
        [current appendString:line];
    }
    if (current.length > 0) { [paragraphs addObject:[current copy]]; }
    return [paragraphs componentsJoinedByString:@"\n\n"];
}

/// 比较用归一化：只去空白，**保留标点**（标点是证据，不能被抹掉）。
static NSString *FYInlineNormalize(NSString *value) {
    NSString *trimmed = FYInlineTrim(value);
    NSMutableString *result = [NSMutableString stringWithCapacity:trimmed.length];
    NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSUInteger index = 0; index < trimmed.length; index++) {
        unichar character = [trimmed characterAtIndex:index];
        if (character == 0x3000 || [spaces characterIsMember:character]) { continue; }
        [result appendFormat:@"%C", character];
    }
    return result;
}

static CGFloat FYInlineClamp(CGFloat value, CGFloat low, CGFloat high) {
    if (high < low) { return low; }
    return MIN(MAX(value, low), high);
}

static BOOL FYInlineRectContainsRect(CGRect outer, CGRect inner) {
    return CGRectGetMinX(inner) >= CGRectGetMinX(outer) - 0.5 && CGRectGetMaxX(inner) <= CGRectGetMaxX(outer) + 0.5 &&
           CGRectGetMinY(inner) >= CGRectGetMinY(outer) - 0.5 && CGRectGetMaxY(inner) <= CGRectGetMaxY(outer) + 0.5;
}

static CGFloat FYInlineMedian(NSArray<NSNumber *> *values) {
    if (values.count == 0) { return 0; }
    NSArray<NSNumber *> *sorted = [values sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [a compare:b];
    }];
    return sorted[sorted.count / 2].doubleValue;
}

static BOOL FYInlineLineEndsSentence(NSString *text) {
    NSString *trimmed = FYInlineTrim(text);
    if (trimmed.length == 0) { return NO; }
    unichar last = [trimmed characterAtIndex:trimmed.length - 1];
    return last == L'。' || last == L'！' || last == L'？' || last == L'!' || last == L'?' ||
           last == L'．' || last == L'.' || last == L'」' || last == L'』' || last == L')' || last == L'）';
}

static BOOL FYInlineHasSentencePunctuation(NSString *text) {
    NSCharacterSet *set = [NSCharacterSet characterSetWithCharactersInString:@"。、，．，！？!?…「」『』（）()"];
    return [(text ?: @"") rangeOfCharacterFromSet:set].location != NSNotFound;
}

#pragma mark - FYInlineTextLine

@implementation FYInlineTextLine
+ (instancetype)lineWithText:(NSString *)text rect:(CGRect)rect confidence:(CGFloat)confidence sourceIndex:(NSInteger)sourceIndex {
    FYInlineTextLine *line = [FYInlineTextLine new];
    line.text = text ?: @"";
    line.rect = rect;
    line.confidence = confidence;
    line.sourceIndex = sourceIndex;
    return line;
}
@end

#pragma mark - FYInlineTextBlock

@implementation FYInlineTextBlock
- (NSInteger)lineCount { return (NSInteger)self.lineTexts.count; }
- (instancetype)init {
    self = [super init];
    if (self) {
        _text = @"";
        _lineTexts = @[];
        _lineBoxes = @[];
        _lineConfidences = @[];
        _sourceIndices = @[];
        _groupingConfidence = 1.0;
    }
    return self;
}
@end

#pragma mark - FYInlineLayoutRequest

@implementation FYInlineLayoutRequest
+ (instancetype)requestWithBlock:(FYInlineTextBlock *)block translation:(NSString *)translation sourceFrame:(CGRect)sourceFrame {
    FYInlineLayoutRequest *request = [FYInlineLayoutRequest new];
    request.block = block;
    request.translation = translation ?: @"";
    request.sourceFrame = sourceFrame;
    return request;
}
@end

#pragma mark - FYInlinePlacement

@implementation FYInlinePlacement
- (instancetype)init {
    self = [super init];
    if (self) {
        _blockID = @"";
        _sourceBlockID = @"";
        _translation = @"";
        _reason = @"";
        _rejectedCandidates = @[];
    }
    return self;
}
@end

#pragma mark - FYInlineLayoutResult

@interface FYInlineLayoutResult ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, FYInlinePlacement *> *byBlockID;
@end

@implementation FYInlineLayoutResult
- (instancetype)init {
    self = [super init];
    if (self) {
        _placements = @[];
        _visiblePlacements = @[];
        _unplaceableBlockIDs = @[];
        _compactEntryBlockIDs = @[];
        _byBlockID = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)setPlacements:(NSArray<FYInlinePlacement *> *)placements {
    _placements = [placements copy] ?: @[];
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    NSMutableArray *visible = [NSMutableArray array];
    NSMutableArray *unplaceable = [NSMutableArray array];
    NSMutableArray *compact = [NSMutableArray array];
    for (FYInlinePlacement *placement in _placements) {
        if (placement.blockID.length > 0) { map[placement.blockID] = placement; }
        if (placement.mode == FYInlineDisplayModeUnplaceable) {
            [unplaceable addObject:placement.blockID];
        } else {
            [visible addObject:placement];
        }
        if (placement.mode == FYInlineDisplayModeCompactEntry) { [compact addObject:placement.blockID]; }
    }
    self.byBlockID = map;
    _visiblePlacements = visible;
    _unplaceableBlockIDs = unplaceable;
    _compactEntryBlockIDs = compact;
}
- (FYInlinePlacement *)placementForBlockID:(NSString *)blockID {
    if (blockID.length == 0) { return nil; }
    return self.byBlockID[blockID];
}
@end

#pragma mark - FYInlineGrouper

@implementation FYInlineGrouper

+ (instancetype)defaultGrouper {
    FYInlineGrouper *grouper = [FYInlineGrouper new];
    grouper.maxBlockHeightFraction = 0.55;
    grouper.minimumCharacters = 2;
    return grouper;
}

#pragma mark 去重

- (NSArray<FYInlineTextLine *> *)deduplicatedLines:(NSArray<FYInlineTextLine *> *)lines {
    NSMutableArray<FYInlineTextLine *> *kept = [NSMutableArray array];
    for (FYInlineTextLine *line in lines ?: @[]) {
        NSString *normalized = FYInlineNormalize(line.text);
        if (normalized.length == 0) { continue; }
        BOOL duplicate = NO;
        for (NSUInteger index = 0; index < kept.count; index++) {
            FYInlineTextLine *existing = kept[index];
            if (![FYInlineNormalize(existing.text) isEqualToString:normalized]) { continue; }
            // 文字相同还不够：必须**同一处**才算重复识别。
            // 不同位置的同文内容要各自保留（例如两篇文章里的同一句话）。
            CGFloat overlap = [FYInlineBlockMatcher overlapRatio:line.rect right:existing.rect];
            if (overlap < 0.5) { continue; }
            duplicate = YES;
            if (line.confidence > existing.confidence) { kept[index] = line; }
            break;
        }
        if (!duplicate) { [kept addObject:line]; }
    }
    return kept;
}

#pragma mark 阅读顺序

- (NSArray<FYInlineTextLine *> *)readingOrderForLines:(NSArray<FYInlineTextLine *> *)lines {
    NSMutableArray<NSNumber *> *heights = [NSMutableArray array];
    for (FYInlineTextLine *line in lines) { [heights addObject:@(MAX((CGFloat)0.004, line.rect.size.height))]; }
    CGFloat rowTolerance = MAX((CGFloat)0.006, FYInlineMedian(heights) * 0.5);
    return [lines sortedArrayUsingComparator:^NSComparisonResult(FYInlineTextLine *left, FYInlineTextLine *right) {
        // Vision 归一化坐标 y 向上：y 大 = 更靠上，先读。
        CGFloat leftTop = CGRectGetMaxY(left.rect);
        CGFloat rightTop = CGRectGetMaxY(right.rect);
        if (fabs(leftTop - rightTop) > rowTolerance) {
            return leftTop > rightTop ? NSOrderedAscending : NSOrderedDescending;
        }
        if (left.rect.origin.x < right.rect.origin.x) { return NSOrderedAscending; }
        if (left.rect.origin.x > right.rect.origin.x) { return NSOrderedDescending; }
        return NSOrderedSame;
    }];
}

#pragma mark 合并判定

- (CGFloat)representativeLineHeightForBlock:(FYInlineTextBlock *)block {
    NSMutableArray<NSNumber *> *heights = [NSMutableArray array];
    for (NSValue *value in block.lineBoxes) { [heights addObject:@(MAX((CGFloat)0.004, value.rectValue.size.height))]; }
    if (heights.count == 0) { [heights addObject:@(0.03)]; }
    return FYInlineMedian(heights);
}

- (BOOL)line:(FYInlineTextLine *)line isSameLineAsRect:(CGRect)reference rectHeight:(CGFloat)referenceHeight {
    CGFloat maxHeight = MAX(line.rect.size.height, referenceHeight);
    return fabs(CGRectGetMidY(line.rect) - CGRectGetMidY(reference)) < maxHeight * 0.45;
}

/// 合并判定。返回 YES/NO、把握程度与原因（原因用于诊断）。
- (BOOL)shouldMergeLine:(FYInlineTextLine *)line
               intoBlock:(FYInlineTextBlock *)block
              confidence:(CGFloat *)outConfidence
                  reason:(NSString **)outReason {
    CGRect itemBox = line.rect;
    CGRect blockBox = block.lineBoxes.lastObject ? [block.lineBoxes.lastObject rectValue] : block.boundingBox;
    CGRect combined = CGRectUnion(block.boundingBox, itemBox);
    CGFloat repHeight = [self representativeLineHeightForBlock:block];
    NSString *itemText = FYInlineNormalize(line.text);
    NSString *blockText = FYInlineNormalize(block.lineTexts.lastObject ?: block.text);

    if (combined.size.height > self.maxBlockHeightFraction) {
        if (outReason) { *outReason = @"合并后整块过高"; }
        return NO;
    }

    // —— 横向关系 ——
    CGFloat overlapLeft = MAX(CGRectGetMinX(itemBox), CGRectGetMinX(blockBox));
    CGFloat overlapRight = MIN(CGRectGetMaxX(itemBox), CGRectGetMaxX(blockBox));
    CGFloat overlapWidth = MAX((CGFloat)0, overlapRight - overlapLeft);
    CGFloat minWidth = MAX((CGFloat)0.001, MIN(itemBox.size.width, blockBox.size.width));
    CGFloat overlapRatio = overlapWidth / minWidth;
    CGFloat horizontalGap = 0;
    if (CGRectGetMaxX(blockBox) < CGRectGetMinX(itemBox)) {
        horizontalGap = CGRectGetMinX(itemBox) - CGRectGetMaxX(blockBox);
    } else if (CGRectGetMaxX(itemBox) < CGRectGetMinX(blockBox)) {
        horizontalGap = CGRectGetMinX(blockBox) - CGRectGetMaxX(itemBox);
    } else {
        horizontalGap = -overlapWidth;
    }
    CGFloat leftDelta = fabs(CGRectGetMinX(itemBox) - CGRectGetMinX(blockBox));
    CGFloat centerDelta = fabs(CGRectGetMidX(itemBox) - CGRectGetMidX(blockBox));

    // 列间空隙：明显超过一个行高就不是同一栏，绝不跨栏拼段。
    if (horizontalGap > MAX((CGFloat)0.010, repHeight * 1.5) && overlapRatio < 0.15) {
        if (outReason) { *outReason = @"横向间隔超过一列间隙"; }
        return NO;
    }

    CGFloat maxHeight = MAX(itemBox.size.height, blockBox.size.height);
    BOOL sameLine = [self line:line isSameLineAsRect:blockBox rectHeight:[self representativeLineHeightForBlock:block]];
    BOOL itemSmall = itemText.length <= 6 && itemBox.size.width < 0.16 && itemBox.size.height < 0.035;
    BOOL blockSmall = blockText.length <= 6 && blockBox.size.width < 0.16 && blockBox.size.height < 0.035;

    // ① 同一行被 OCR 切开的片段（几何判定，不针对文案写死）。
    BOOL splitFragment = sameLine && itemSmall && blockSmall && horizontalGap >= -0.006 &&
                         horizontalGap < MAX((CGFloat)0.010, MIN((CGFloat)0.030, maxHeight * 0.9));
    if (splitFragment) {
        if (outConfidence) { *outConfidence = 0.90; }
        if (outReason) { *outReason = @"同一行相邻片段"; }
        return YES;
    }
    if (itemSmall && blockSmall) {
        if (outReason) { *outReason = @"两个独立短条目"; }
        return NO;
    }
    BOOL paragraphish = itemText.length >= 8 || blockText.length >= 8 ||
                        itemBox.size.width > 0.18 || blockBox.size.width > 0.18;
    // 同一行的“续写”只允许很小的缝：实测两栏排版 0.018 的栏距（约 20px/1080）如果按
    // 旧阈值 0.022 会被当成一行，左右两栏就并成一块了。阈值按局部行高取（<0.4 倍行高）。
    CGFloat sameLineGap = MAX((CGFloat)0.005, MIN((CGFloat)0.014, maxHeight * 0.40));
    if (sameLine && paragraphish && horizontalGap >= -0.006 && horizontalGap < sameLineGap) {
        if (outConfidence) { *outConfidence = 0.80; }
        if (outReason) { *outReason = @"同一行相邻正文"; }
        return YES;
    }
    if (sameLine) {
        if (outReason) { *outReason = @"同一行但间隔过大"; }
        return NO;
    }

    // —— 纵向关系：同列 + 字号相近才谈合并 ——
    BOOL aligned = leftDelta <= MAX((CGFloat)0.008, repHeight * 0.7) ||
                   (overlapRatio >= 0.55 && centerDelta <= MAX((CGFloat)0.012, repHeight * 0.9));
    if (!aligned) {
        if (outReason) { *outReason = @"左右未对齐（不同栏或不同缩进层级）"; }
        return NO;
    }
    // 字号判定用**块的稳定行高（中位数）**做参照，而不是最后一行：
    // OCR 对含拉丁字符/符号的行常常量出偏小的框高（真实采集帧里 +Karen+ 就是 .030 对 .047），
    // 用单行高度会把同一段正文拆开。阈值 0.5 仍能拦住标题（约 0.44）与正文。
    CGFloat referenceHeight = MAX(repHeight, blockBox.size.height);
    CGFloat heightRatio = (MIN(itemBox.size.height, referenceHeight) /
                           MAX((CGFloat)0.0001, MAX(itemBox.size.height, referenceHeight)));
    if (heightRatio < 0.5) {
        if (outReason) { *outReason = @"字号相差明显（标题与正文）"; }
        return NO;
    }

    CGFloat verticalGap = 0;
    if (CGRectGetMinY(blockBox) >= CGRectGetMaxY(itemBox)) {
        verticalGap = CGRectGetMinY(blockBox) - CGRectGetMaxY(itemBox);
    } else if (CGRectGetMinY(itemBox) >= CGRectGetMaxY(blockBox)) {
        verticalGap = CGRectGetMinY(itemBox) - CGRectGetMaxY(blockBox);
    }

    CGFloat widthRatio = (itemBox.size.width > 0 && blockBox.size.width > 0)
        ? MIN(itemBox.size.width, blockBox.size.width) / MAX(itemBox.size.width, blockBox.size.width) : (CGFloat)0;
    BOOL punctuation = FYInlineHasSentencePunctuation(line.text) ||
                       FYInlineHasSentencePunctuation(block.lineTexts.lastObject ?: block.text);
    CGFloat longestPair = MAX((CGFloat)itemText.length, (CGFloat)blockText.length);
    // 规则排列的独立条目：两行都短、宽度相近、且都没有句读 —— 这是菜单/设置列表的样子。
    BOOL entryLike = itemText.length <= 16 && blockText.length <= 16 && widthRatio >= 0.70 && !punctuation;

    // ② 折行合并：间距远小于一个行高（≤0.45 倍代表行高）说明是同段的换行。
    //    证据用文本量：正文折行的行明显长于菜单标签（菜单条目之间不会贴这么紧）。
    CGFloat wrapGap = MAX((CGFloat)0.004, repHeight * 0.45);
    if (verticalGap <= wrapGap) {
        BOOL wrapEvidence = longestPair >= 10 || punctuation;
        if (wrapEvidence && paragraphish) {
            if (outConfidence) { *outConfidence = 0.88; }
            if (outReason) { *outReason = @"同一段落折行（行距小于半行高）"; }
            return YES;
        }
        if (outReason) { *outReason = @"行距很近但没有正文证据（更像两条独立短条目）"; }
        return NO;
    }

    // ③ 段落／条目区间：0.45–1.6 倍代表行高。
    //    真实邮件正文的段间空行约 0.85–1.15 倍行高且带句读；等间距设置列表约 1.0 倍行高、
    //    没有句读。所以这一档必须有**强正文证据**（句读，或明显更长的行），否则按独立条目分开。
    CGFloat paragraphGap = MAX(wrapGap, repHeight * 1.6);
    if (verticalGap <= paragraphGap) {
        BOOL strongProse = punctuation || longestPair >= 24;
        if (strongProse && !entryLike) {
            if (outConfidence) { *outConfidence = 0.62; }
            if (outReason) { *outReason = @"同栏正文段落（间隔在一倍行高量级且有正文证据）"; }
            return YES;
        }
        if (outReason) { *outReason = @"间隔落在条目区间且缺少正文证据"; }
        return NO;
    }
    if (outReason) { *outReason = @"间隔超过段落上限或缺少正文证据"; }
    return NO;
}

#pragma mark 分组

/// 行距是否接近"实排"：正文按列宽折行时，行与行之间只有很小的空隙；
/// 菜单/按钮列表的行距通常接近甚至超过行高。用两者的比值判定，不写死像素或字号。
- (BOOL)linesLookTightlyStacked:(NSArray<FYInlineTextLine *> *)lines {
    if (lines.count < 3) { return NO; }
    NSArray<FYInlineTextLine *> *sorted = [lines sortedArrayUsingComparator:^NSComparisonResult(FYInlineTextLine *left, FYInlineTextLine *right) {
        CGFloat leftTop = CGRectGetMaxY(left.rect);
        CGFloat rightTop = CGRectGetMaxY(right.rect);
        if (fabs(leftTop - rightTop) > 1e-6) { return leftTop > rightTop ? NSOrderedAscending : NSOrderedDescending; }
        return left.rect.origin.x < right.rect.origin.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    CGFloat gapSum = 0, heightSum = 0;
    NSUInteger pairs = 0;
    for (NSUInteger index = 0; index + 1 < sorted.count; index++) {
        CGRect upper = sorted[index].rect;
        CGRect lower = sorted[index + 1].rect;
        CGFloat gap = NSMinY(upper) - CGRectGetMaxY(lower);
        if (gap < 0) { gap = 0; }
        gapSum += gap;
        heightSum += MIN(NSHeight(upper), NSHeight(lower));
        pairs += 1;
    }
    if (pairs == 0) { return NO; }
    CGFloat averageGap = gapSum / (CGFloat)pairs;
    CGFloat averageHeight = heightSum / (CGFloat)pairs;
    if (averageHeight <= 0.0001) { return NO; }
    return averageGap <= averageHeight * 0.55;
}

- (FYInlineBlockKind)kindForLines:(NSArray<FYInlineTextLine *> *)lines normalized:(NSString *)normalizedText {    NSUInteger lineCount = lines.count;
    if (lineCount == 0) { return FYInlineBlockKindShort; }
    NSString *normalized = normalizedText ?: @"";
    CGFloat width = 0, height = 0;
    for (FYInlineTextLine *line in lines) {
        width = MAX(width, line.rect.size.width);
        height = MAX(height, line.rect.size.height);
    }
    BOOL wide = width > 0.24;
    BOOL tall = height > 0.075;

    if (lineCount == 1) {
        // 单行只有文本本身足够长才算正文；宽度单独不构成正文证据（宽而短的按钮要保持穿透）。
        if (self.shortLabelDetector && self.shortLabelDetector(normalized)) { return FYInlineBlockKindShort; }
        if (normalized.length >= 16) { return FYInlineBlockKindLong; }
        return FYInlineBlockKindShort;
    }
    // 规则排列的短条目列表保持短贴片。但「每行 ≤14 字」**不等于**按钮列表：
    // OCR 会按列宽把一段正文切成若干短行（现场：五行喜好正文每行 8~12 字、左对齐、
    // 行距只有 0.45 倍行高、最大行宽 0.239 刚好低于 0.24），旧判据把它当按钮列表，
    // 于是既没有长卡、也没有紧凑入口，整段正文从画面消失。
    // 段落证据：行数够多 + 每行都是较长的片段 + 行距接近"实排"。
    BOOL buttonList = YES;
    for (FYInlineTextLine *line in lines) {
        if (FYInlineNormalize(line.text).length > 14) { buttonList = NO; break; }
    }
    if (buttonList && !wide && !tall) {
        NSUInteger totalLength = normalized.length;
        CGFloat averageLength = lineCount > 0 ? (CGFloat)totalLength / (CGFloat)lineCount : 0;
        if (lineCount >= 4 && totalLength >= 24 && averageLength >= 9 &&
            [self linesLookTightlyStacked:lines]) {
            return FYInlineBlockKindLong;
        }
        return FYInlineBlockKindShort;
    }

    BOOL continuity = NO;
    for (NSUInteger index = 0; index + 1 < lines.count; index++) {
        if (!FYInlineLineEndsSentence(lines[index].text)) { continuity = YES; break; }
    }
    if ((continuity || normalized.length >= 26) && (wide || tall || normalized.length >= 20)) {
        return FYInlineBlockKindLong;
    }
    return FYInlineBlockKindShort;
}

- (NSArray<FYInlineTextBlock *> *)blocksFromLines:(NSArray<FYInlineTextLine *> *)lines {
    NSArray<FYInlineTextLine *> *deduplicated = [self deduplicatedLines:lines];
    NSMutableArray<FYInlineTextLine *> *filtered = [NSMutableArray array];
    for (FYInlineTextLine *line in deduplicated) {
        NSString *text = FYInlineTrim(line.text);
        if ((NSInteger)FYInlineNormalize(text).length < self.minimumCharacters) { continue; }
        line.text = text;
        [filtered addObject:line];
    }
    NSArray<FYInlineTextLine *> *ordered = [self readingOrderForLines:filtered];

    NSMutableArray<FYInlineTextBlock *> *blocks = [NSMutableArray array];
    for (FYInlineTextLine *line in ordered) {
        NSString *text = FYInlineTrim(line.text);
        FYInlineTextBlock *target = nil;
        BOOL merge = NO;
        CGFloat confidence = 1.0;
        for (FYInlineTextBlock *block in [blocks reverseObjectEnumerator]) {
            CGFloat found = 0;
            NSString *blockReason = nil;
            if ([self shouldMergeLine:line intoBlock:block confidence:&found reason:&blockReason]) {
                target = block;
                merge = YES;
                confidence = found;
                break;
            }
        }
        if (!merge || !target) {
            FYInlineTextBlock *block = [FYInlineTextBlock new];
            block.text = text;
            block.boundingBox = line.rect;
            block.lineTexts = @[text];
            block.lineBoxes = @[@(line.rect)];
            block.lineConfidences = @[@(line.confidence)];
            block.sourceIndices = @[@(line.sourceIndex)];
            block.groupingConfidence = 1.0;
            [blocks addObject:block];
            continue;
        }

        BOOL sameLine = [self line:line isSameLineAsRect:[target.lineBoxes.lastObject rectValue]
                                            rectHeight:[target.lineBoxes.lastObject rectValue].size.height];
        NSString *separator = sameLine ? @" " : @"\n";
        target.text = [target.text stringByAppendingFormat:@"%@%@", separator, text];
        target.boundingBox = CGRectUnion(target.boundingBox, line.rect);
        target.lineTexts = [target.lineTexts arrayByAddingObject:text];
        target.lineBoxes = [target.lineBoxes arrayByAddingObject:@(line.rect)];
        target.lineConfidences = [target.lineConfidences arrayByAddingObject:@(line.confidence)];
        target.sourceIndices = [target.sourceIndices arrayByAddingObject:@(line.sourceIndex)];
        target.groupingConfidence = MIN(target.groupingConfidence, confidence);
    }

    // 分类 + 稳定身份 + 阅读顺序。
    NSMutableArray<FYInlineTextBlock *> *result = [NSMutableArray array];
    for (NSUInteger index = 0; index < blocks.count; index++) {
        FYInlineTextBlock *block = blocks[index];
        NSMutableArray<FYInlineTextLine *> *blockLines = [NSMutableArray array];
        for (NSUInteger lineIndex = 0; lineIndex < block.lineBoxes.count; lineIndex++) {
            FYInlineTextLine *line = [FYInlineTextLine new];
            line.text = block.lineTexts[lineIndex];
            line.rect = [block.lineBoxes[lineIndex] rectValue];
            line.confidence = [block.lineConfidences[lineIndex] doubleValue];
            line.sourceIndex = [block.sourceIndices[lineIndex] integerValue];
            [blockLines addObject:line];
        }
        block.kind = [self kindForLines:blockLines normalized:FYInlineNormalize(block.text)];
        block.blockID = [FYInlineBlockMatcher blockIDForText:block.text lineBoxes:block.lineBoxes];
        block.readingOrder = (NSInteger)index;
        [result addObject:block];
    }
    return result;
}

@end

#pragma mark - FYInlineBlockMatcher

@implementation FYInlineBlockMatcher

+ (NSString *)blockIDForText:(NSString *)text lineBoxes:(NSArray<NSValue *> *)lineBoxes {
    NSMutableString *key = [NSMutableString stringWithString:FYInlineNormalize(text)];
    for (NSValue *value in lineBoxes) {
        CGRect rect = value.rectValue;
        [key appendFormat:@"|%.3f,%.3f,%.3f,%.3f", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
    }
    return [key copy];
}

+ (NSString *)normalizedForSimilarity:(NSString *)text {
    return FYInlineNormalize(text);
}

+ (CGFloat)textSimilarity:(NSString *)left right:(NSString *)right {
    NSString *a = FYInlineNormalize(left);
    NSString *b = FYInlineNormalize(right);
    if (a.length == 0 || b.length == 0) { return 0; }
    if ([a isEqualToString:b]) { return 1.0; }
    if (a.length < 2 || b.length < 2) { return 0; }
    NSMutableDictionary<NSString *, NSNumber *> *bigrams = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index + 1 < a.length; index++) {
        NSString *gram = [a substringWithRange:NSMakeRange(index, 2)];
        bigrams[gram] = @(bigrams[gram].integerValue + 1);
    }
    NSUInteger matches = 0;
    for (NSUInteger index = 0; index + 1 < b.length; index++) {
        NSString *gram = [b substringWithRange:NSMakeRange(index, 2)];
        NSInteger count = bigrams[gram].integerValue;
        if (count > 0) {
            matches += 1;
            bigrams[gram] = @(count - 1);
        }
    }
    return (CGFloat)(2.0 * matches) / (CGFloat)((a.length - 1) + (b.length - 1));
}

+ (CGFloat)overlapRatio:(CGRect)left right:(CGRect)right {
    CGRect hit = CGRectIntersection(left, right);
    if (CGRectIsNull(hit) || CGRectIsEmpty(hit)) { return 0; }
    CGFloat hitArea = hit.size.width * hit.size.height;
    CGFloat smaller = MIN(left.size.width * left.size.height, right.size.height * right.size.width);
    if (smaller <= 0) { return 0; }
    return hitArea / smaller;
}

+ (NSString *)stableBlockIDForBlock:(FYInlineTextBlock *)block
                               text:(NSString *)text
                        sourceFrame:(CGRect)sourceFrame
                     previousResult:(FYInlineLayoutResult *)previous {
    if (!previous || previous.placements.count == 0) { return nil; }
    NSString *normalized = FYInlineNormalize(text);
    FYInlinePlacement *best = nil;
    CGFloat bestScore = 0;
    for (FYInlinePlacement *placement in previous.placements) {
        if (placement.blockID.length == 0) { continue; }
        CGFloat similarity = [self textSimilarity:normalized right:placement.block.text ?: placement.translation];
        BOOL sameText = similarity >= 0.999;
        if (similarity < 0.62) { continue; }
        CGFloat overlap = [self overlapRatio:sourceFrame right:placement.sourceFrame];
        if (overlap < 0.20) { continue; }
        CGFloat sizeRatio = MIN(NSWidth(sourceFrame), NSWidth(placement.sourceFrame)) /
                            MAX((CGFloat)0.001, MAX(NSWidth(sourceFrame), NSWidth(placement.sourceFrame)));
        if (sizeRatio < 0.55) { continue; }
        CGFloat score = overlap * (sameText ? 2.0 : 1.0) + similarity;
        if (score > bestScore) { bestScore = score; best = placement; }
    }
    return best.blockID;
}

@end

#pragma mark - 候选位置

@interface FYInlineCandidate : NSObject
@property (nonatomic) FYInlineAnchor anchor;
@property (nonatomic) CGRect frame;
@property (nonatomic) CGFloat distance;
@property (nonatomic) NSInteger anchorRank;
@property (nonatomic) BOOL compact;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *rejection;   // 非空 = 有静态问题（严重程度见 hardRejection）
@property (nonatomic) CGFloat occlusionDepth;   // 与其它原文块的最大交叠厚度（pt）
@property (nonatomic) BOOL hardRejection;       // 超界/离原文过远：任何情况都不接受
@property (nonatomic) BOOL scrollable;
@property (nonatomic) CGFloat measuredContentHeight;
@property (nonatomic) CGFloat bodyViewportHeight;
@end

@implementation FYInlineCandidate
@end

#pragma mark - FYInlineLayoutEngine

@interface FYInlineLayoutEngine ()
@property (nonatomic) NSUInteger revision;
@end

@implementation FYInlineLayoutEngine

+ (instancetype)defaultEngine {
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine new];
    engine.shortFontSize = 16;
    engine.coverFontSize = 17;
    engine.longBodyFontSize = 19;
    engine.longTitleFontSize = 14;
    engine.longLineSpacing = 8;
    engine.minimumBodyLines = 3;
    engine.cardMaxWidth = 560;
    engine.cardWidthFraction = 0.52;
    engine.cardWideFraction = 0.62;
    engine.cardMaxHeight = 330;
    engine.cardHeightFraction = 0.55;
    engine.minimumLongBodyFontSize = 15;
    engine.minimumCardWidth = 160;
    engine.viewportMargin = 8;
    engine.panelGap = 4;
    engine.compactEntryHeight = 34;
    engine.compactEntryTitle = @"点击展开";
    engine.compactEntryFontSize = 13;
    engine.compactEntryHorizontalPadding = 10;
    engine.foldedEntryFallbackTitle = @"这段译文";
    engine.foldedEntryHintTooLong = @"文本过长，已收起";
    engine.foldedEntryHintCrowded = @"空间不足，已收起";
    engine.stabilityTolerance = 3;
    engine.shortWidthFraction = 0.42;
    engine.shortMaxWidth = 360;
    return engine;
}

#pragma mark 字体与段落样式（测量与绘制共用）

- (NSFont *)fontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
    if (self.fontProvider) { return self.fontProvider(size, weight); }
    NSString *name = weight >= NSFontWeightSemibold ? @"STYuanti-SC-Bold" : @"STYuanti-SC-Regular";
    return [NSFont fontWithName:name size:size] ?: [NSFont systemFontOfSize:size weight:weight];
}

- (NSParagraphStyle *)paragraphStyleWithLineSpacing:(CGFloat)lineSpacing {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByCharWrapping;
    style.lineSpacing = lineSpacing;
    return style;
}

- (CGFloat)measuredHeightForText:(NSString *)text
                           width:(CGFloat)width
                            font:(NSFont *)font
                           style:(NSParagraphStyle *)style {
    if (width <= 4 || text.length == 0) { return 0; }
    NSRect measured = [text boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
                                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                      attributes:@{NSFontAttributeName: font, NSParagraphStyleAttributeName: style}];
    return ceil(NSHeight(measured));
}

- (CGFloat)longCardLineHeight:(FYInlinePlacement *)placement {
    NSFont *font = placement.font ?: [self fontOfSize:self.longBodyFontSize weight:NSFontWeightRegular];
    return ceil(font.ascender - font.descender + font.leading) + self.longLineSpacing;
}

- (CGFloat)minimumCardHeight {
    CGFloat padding = 18;
    CGFloat titleBand = 24 + 13;
    NSFont *font = [self fontOfSize:self.longBodyFontSize weight:NSFontWeightRegular];
    CGFloat lineHeight = ceil(font.ascender - font.descender + font.leading) + self.longLineSpacing;
    return padding * 2 + titleBand + lineHeight * MAX((CGFloat)1, (CGFloat)self.minimumBodyLines);
}

- (NSFont *)shortBodyFontForCover:(BOOL)cover {
    return [self fontOfSize:(cover ? self.coverFontSize : self.shortFontSize) weight:NSFontWeightRegular];
}
- (NSParagraphStyle *)shortParagraphStyle {
    return [self paragraphStyleWithLineSpacing:3];
}
- (NSFont *)longBodyFont {
    return [self fontOfSize:self.longBodyFontSize weight:NSFontWeightRegular];
}
- (NSParagraphStyle *)longBodyParagraphStyle {
    return [self paragraphStyleWithLineSpacing:self.longLineSpacing];
}
- (NSFont *)longTitleFont {
    return [self fontOfSize:self.longTitleFontSize weight:NSFontWeightSemibold];
}
- (NSFont *)compactEntryFont {
    return [self fontOfSize:self.compactEntryFontSize weight:NSFontWeightSemibold];
}
- (NSFont *)foldedEntryHintFont {
    return [self fontOfSize:MAX((CGFloat)11, self.compactEntryFontSize - 1) weight:NSFontWeightRegular];
}

/// 从块文本里取"短标题"：只有首行确实像标题（短、且不含句读、不是整段的第一句）才用。
/// 取不到就返回 nil，让调用方用占位标题 —— 这里绝不调用 AI 生成标题。
+ (NSString *)shortTitleForBlockText:(NSString *)text {
    NSString *trimmed = FYInlineTrim(text);
    if (trimmed.length == 0) { return nil; }
    NSArray<NSString *> *lines = [trimmed componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSString *first = FYInlineTrim(lines.firstObject);
    if (first.length == 0) { return nil; }
    // 单行块：本身就是一句短标题/短标签。
    if (lines.count == 1) {
        return first.length <= 14 ? first : nil;
    }
    if (first.length > 12) { return nil; }
    // 以句读/省略号结尾的首行是正文的第一句，不是标题。
    NSCharacterSet *sentenceEnds = [NSCharacterSet characterSetWithCharactersInString:@"。、，．，,！？!?…‥・"];
    unichar last = [first characterAtIndex:first.length - 1];
    if ([sentenceEnds characterIsMember:last]) { return nil; }
    return first;
}

/// 折叠入口的尺寸：标题 / 提示 / 动作三行按各自字体测量，取最宽的一行 + 内边距；
/// 高度 = 三行文字高 + 行距 + 上下内边距。**与长卡宽度无关**。
- (CGSize)foldedEntrySizeForViewport:(CGRect)viewport title:(NSString *)title hint:(NSString *)hint {
    return [self foldedEntrySizeForViewport:viewport title:title hint:hint action:nil];
}

- (CGSize)foldedEntrySizeForViewport:(CGRect)viewport title:(NSString *)title hint:(NSString *)hint
                              action:(NSString *)actionOverride {
    NSString *entryTitle = (title != nil && title.length > 0) ? title : (self.foldedEntryFallbackTitle ?: @"这段译文");
    // nil = 没指定（用默认文案）；空字符串 = 明确不要这一行（例如单行总入口）。
    NSString *entryHint = (hint != nil) ? hint : (self.foldedEntryHintTooLong ?: @"文本过长，已收起");
    // nil = 用默认动作文案；空串 = 明确没有动作行（单行总入口）。
    NSString *action = (actionOverride != nil) ? actionOverride
        : (self.compactEntryTitle.length > 0 ? self.compactEntryTitle : @"点击展开");
    NSFont *titleFont = [self compactEntryFont];
    NSFont *hintFont = [self foldedEntryHintFont];
    CGFloat titleWidth = ceil(NSWidth([entryTitle boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
                                                               options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                            attributes:@{NSFontAttributeName: titleFont}]));
    CGFloat hintWidth = entryHint.length > 0
        ? ceil(NSWidth([entryHint boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
                                              options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                           attributes:@{NSFontAttributeName: hintFont}]))
        : 0;
    // 动作行额外留出「＋向下箭头」的宽度。
    CGFloat actionWidth = action.length > 0
        ? ceil(NSWidth([action boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
                                            options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                         attributes:@{NSFontAttributeName: titleFont}])) + 18
        : 0;
    CGFloat contentWidth = MAX(titleWidth, MAX(hintWidth, actionWidth));
    CGFloat padding = MAX((CGFloat)6, self.compactEntryHorizontalPadding);
    CGFloat maxWidth = MAX((CGFloat)110, NSWidth(viewport) - self.viewportMargin * 2);
    CGFloat width = FYInlineClamp(contentWidth + padding * 2 + 4, MIN((CGFloat)110, maxWidth), maxWidth);
    CGFloat titleHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading);
    CGFloat hintHeight = ceil(hintFont.ascender - hintFont.descender + hintFont.leading);
    // 空行（例如"还有 N 条译文 · 查看"这种单行总入口）不占高度、不占宽度。
    CGFloat rows = titleHeight;
    if (entryHint.length > 0) { rows += hintHeight + 2; }
    if (action.length > 0) { rows += titleHeight + 3; }
    CGFloat height = MAX(MAX((CGFloat)44, self.compactEntryHeight), rows + 14);
    return CGSizeMake(width, height);
}

// 紧凑入口按**内容**测量：标题文字宽度 + 左右内边距，高度不低于 compactEntryHeight。
// 以前它沿用长卡宽度（几百点的一条），结果这个本可以塞进正文里的小入口到处放不下，
// 长正文整块从画面上消失 —— 尺寸必须由"要看的那行字"决定，而不是卡片有多宽。
- (CGSize)compactEntrySizeForViewport:(CGRect)viewport {
    // 与折叠入口同一份测量（默认标题/提示），避免两套尺寸口径。
    return [self foldedEntrySizeForViewport:viewport title:nil hint:nil];
}

/// 折叠入口要有具体文案才知道该量多宽：块标题 + 收起原因。
- (void)applyFoldedEntryCopyToPlacement:(FYInlinePlacement *)placement crowded:(BOOL)crowded {
    NSString *title = [FYInlineLayoutEngine shortTitleForBlockText:placement.block.text];
    placement.entryTitle = title.length > 0 ? title : (self.foldedEntryFallbackTitle ?: @"这段译文");
    placement.entryHint = crowded ? (self.foldedEntryHintCrowded ?: @"空间不足，已收起")
                                  : (self.foldedEntryHintTooLong ?: @"文本过长，已收起");
    placement.entryAction = self.compactEntryTitle.length > 0 ? self.compactEntryTitle : @"点击展开";
    placement.entryReasonCrowded = crowded;
}

- (CGFloat)measuredBodyHeight:(NSString *)translation placement:(FYInlinePlacement *)placement width:(CGFloat)width {
    CGFloat textWidth = MAX((CGFloat)80, width - placement.panelPadding * 2);
    return [self measuredHeightForText:translation width:textWidth font:placement.font style:placement.paragraphStyle];
}

#pragma mark 短贴片

- (FYInlinePlacement *)basePlacementForRequest:(FYInlineLayoutRequest *)request
                                    stableID:(NSString *)stableID
                                    viewport:(CGRect)viewport {
    FYInlinePlacement *placement = [FYInlinePlacement new];
    placement.blockID = stableID;
    placement.sourceBlockID = request.block.blockID;
    placement.block = request.block;
    placement.translation = request.translation;
    placement.readingOrder = request.block.readingOrder;
    placement.sourceFrame = request.sourceFrame;
    placement.groupingConfidence = request.block.groupingConfidence;
    placement.matchedPreviousFrame = ![stableID isEqualToString:request.block.blockID];
    placement.panelPadding = 10;
    placement.titleBandHeight = 0;
    placement.cornerRadius = 7;
    return placement;
}

- (void)prepareShortPlacement:(FYInlinePlacement *)placement
                    sourceText:(NSString *)sourceText
                      viewport:(CGRect)viewport {
    NSString *normalizedSource = FYInlineNormalize(sourceText);
    BOOL hasLineBreak = [sourceText rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound;
    BOOL cover = hasLineBreak || normalizedSource.length >= 18 ||
                 (normalizedSource.length >= 12 && NSHeight(placement.sourceFrame) > NSHeight(viewport) * 0.055);
    CGFloat fontSize = cover ? self.coverFontSize : self.shortFontSize;
    CGFloat paddingX = cover ? 12 : 10;
    CGFloat paddingY = cover ? 6 : 5;
    NSFont *font = [self fontOfSize:fontSize weight:NSFontWeightRegular];
    NSParagraphStyle *style = [self shortParagraphStyle];
    placement.font = font;
    placement.paragraphStyle = style;
    placement.panelPadding = paddingY;
    placement.titleBandHeight = 0;
    placement.cornerRadius = 7;

    CGFloat maxWidth = MIN(NSWidth(viewport) - 16, MAX((CGFloat)90, MIN(self.shortMaxWidth, NSWidth(viewport) * self.shortWidthFraction)));
    maxWidth = MAX((CGFloat)80, maxWidth);
    NSDictionary *attributes = @{NSFontAttributeName: font, NSParagraphStyleAttributeName: style};
    NSRect natural = [placement.translation boundingRectWithSize:NSMakeSize(10000, CGFLOAT_MAX)
                                                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                      attributes:attributes];
    if (!cover) {
        maxWidth = MIN(maxWidth, MAX((CGFloat)48, ceil(NSWidth(natural)) + paddingX * 2 + 4));
    }
    CGFloat width = maxWidth;
    CGFloat textWidth = MAX((CGFloat)20, width - paddingX * 2 - 4);
    CGFloat textHeight = [self measuredHeightForText:placement.translation width:textWidth font:font style:style];
    CGFloat maximumHeight = MAX((CGFloat)40, NSHeight(viewport) - 16);
    // 最小高度改为贴合单行文字：字号 + 行距 + 内边距 × 2，避免单行文本边框过高
    CGFloat minimumHeight = ceil(font.ascender - font.descender + font.leading) + paddingY * 2 + 4;
    CGFloat height = MIN(MAX(textHeight + paddingY * 2 + 4, minimumHeight), maximumHeight);
    placement.measuredContentHeight = textHeight;
    placement.bodyViewportHeight = MAX(0, height - paddingY * 2);
    placement.scrollable = NO;
    placement.labelFrame = NSMakeRect(paddingX, height - paddingY - MIN(height - paddingY * 2, textHeight + 4),
                                      width - paddingX * 2, MIN(height - paddingY * 2, textHeight + 4));
    placement.translationFrame = NSMakeRect(0, 0, width, height);
    placement.reason = cover ? @"短贴片按长原文覆盖式尺寸" : @"短贴片贴合译文宽度";
}

#pragma mark 长阅读卡

/// 长卡测量：从原文宽度出发尝试有限几个宽度，选第一个能完整容纳译文的宽度；
/// 都放不下就用最宽的那个并在卡内滚动。高度按**完整译文**计算，优先贴合内容、减少空白，
/// 短译文按实际正文高度收紧；超过三行的译文仍保留三行可读下限。
- (void)prepareLongPlacement:(FYInlinePlacement *)placement
             widthCandidates:(NSArray<NSNumber *> *)widths
                  windowInner:(CGFloat)windowInner
                         cap:(CGFloat)cap
                    minHeight:(CGFloat)minimumHeight {
    // 修饰（内边距/标题带/圆角）必须沿用调用方已经按**候选组合**设定好的值：
    // 这里过去硬编码 18 / 37，把"紧凑修饰"这一维候选悄悄覆盖掉，
    // 于是「减少标题与留白」的候选等于没试，只剩缩字号一条路（明明有空间也会判放不下）。
    CGFloat padding = placement.panelPadding > 0 ? placement.panelPadding : 18;
    CGFloat titleBand = placement.titleBandHeight >= 0 ? placement.titleBandHeight : (24 + 13);

    // 卡高 = 正文文档高 + 内边距 + 标题带。以前漏加了 chrome，导致中等长度的译文
    // 明明能一屏放下却被迫滚动、卡片高度也没真正贴合内容。
    // 文档高统一按 +4 的排版余量算，与 applyInlineLongCardBody 的文档高度同一口径。
    CGFloat chrome = padding * 2 + titleBand;
    CGFloat capBody = MAX(0, cap - chrome);
    CGFloat chosenWidth = widths.firstObject.doubleValue;
    CGFloat chosenContent = 0;
    BOOL fits = NO;
    for (NSUInteger index = 0; index < widths.count; index++) {
        CGFloat width = widths[index].doubleValue;
        CGFloat content = [self measuredBodyHeight:placement.translation placement:placement width:width] + 4;
        chosenWidth = width;
        chosenContent = content;
        if (content <= capBody) { fits = YES; break; }
    }
    CGFloat contentHeight = chosenContent + chrome;
    // 三行是长文滚动时的可读下限，不是所有长卡的固定高度。短译文只占一两行时，
    // 以实际测量高度为准，同时至少留出完整的一行，避免出现只有标题的细条。
    CGFloat readableMinimum = MIN(minimumHeight,
                                  MAX(chrome + [self longCardLineHeight:placement], contentHeight));
    CGFloat height = fits ? contentHeight : cap;
    height = FYInlineClamp(height, MIN(readableMinimum, windowInner), MIN(cap, windowInner));
    CGFloat viewportHeight = MAX(0, height - chrome);
    placement.translationFrame = NSMakeRect(0, 0, chosenWidth, height);
    placement.measuredContentHeight = chosenContent;
    placement.bodyViewportHeight = viewportHeight;
    placement.scrollable = chosenContent > viewportHeight + 0.5;
    placement.bodyViewportFrame = NSMakeRect(padding, padding + titleBand, MAX((CGFloat)80, chosenWidth - padding * 2),
                                             viewportHeight);
    // 诊断用：长卡本身的尺寸（紧凑入口做不出来时，现场日志要能看出卡有多大）。
    placement.longCardSize = NSMakeSize(chosenWidth, height);
    placement.compactEntrySize = CGSizeZero;
}

#pragma mark 候选生成

- (NSArray<FYInlineCandidate *> *)candidatesForPlacement:(FYInlinePlacement *)placement
                                                viewport:(CGRect)viewport
                                           compactEntry:(BOOL)compact
                                                 widths:(NSArray<NSNumber *> *)widths {
    NSMutableArray<FYInlineCandidate *> *candidates = [NSMutableArray array];
    CGFloat gap = self.panelGap;
    CGRect source = placement.sourceFrame;
    CGFloat minX = NSMinX(viewport) + self.viewportMargin;
    CGFloat maxX = NSMaxX(viewport) - self.viewportMargin;
    CGFloat width = widths.firstObject.doubleValue;
    CGFloat height = NSHeight(placement.translationFrame) > 0 ? NSHeight(placement.translationFrame) : self.compactEntryHeight;
    if (compact) { height = MAX(self.compactEntryHeight, height); }

    void (^add)(FYInlineAnchor, CGFloat, CGFloat, NSInteger, NSString *) = ^(FYInlineAnchor anchor, CGFloat x, CGFloat y, NSInteger rank, NSString *name) {
        FYInlineCandidate *candidate = [FYInlineCandidate new];
        candidate.anchor = anchor;
        candidate.anchorRank = rank;
        candidate.compact = compact;
        candidate.name = name;
        candidate.frame = NSMakeRect(x, y, width, height);
        candidate.measuredContentHeight = placement.measuredContentHeight;
        candidate.bodyViewportHeight = placement.bodyViewportHeight;
        candidate.scrollable = placement.scrollable;
        candidate.distance = MAX(0, MAX(CGRectGetMinY(source) - CGRectGetMaxY(candidate.frame),
                                        CGRectGetMinY(candidate.frame) - CGRectGetMaxY(source)));
        [candidates addObject:candidate];
    };

    CGFloat anchorX = FYInlineClamp(NSMinX(source), minX, MAX(minX, maxX - width));
    if (compact) {
        // 紧凑入口优先放在**它所属正文自身**的范围里：
        // 覆盖自己的一小部分正文是允许的（原文块之间仍然互不遮挡），
        // 这样标题、菜单、其它贴片再挤，这块正文也不会连入口都放不下。
        CGFloat inset = MIN((CGFloat)4, MAX(0, (NSHeight(source) - height) / 2.0));
        add(FYInlineAnchorOverlay, anchorX, NSMinY(source) + inset, 0, @"正文内·底部");
        add(FYInlineAnchorOverlay, anchorX, NSMaxY(source) - height - inset, 1, @"正文内·顶部");
        add(FYInlineAnchorOverlay, anchorX, CGRectGetMidY(source) - height / 2.0, 2, @"正文内·居中");
    }

    // 近邻位置：根据原文在 viewport 中的位置动态调整优先级。
    // 原文靠近底部时优先上方，靠近顶部时优先下方，避免"明明有空位却显示空间不足"。
    NSInteger rank = compact ? 3 : 0;
    CGFloat sourceBottom = CGRectGetMinY(source);
    CGFloat sourceTop = CGRectGetMaxY(source);
    CGFloat viewportBottom = CGRectGetMinY(viewport);
    CGFloat viewportTop = CGRectGetMaxY(viewport);
    CGFloat viewportHeight = NSHeight(viewport);

    // 计算原文中心点在 viewport 中的相对位置（0.0 = 底部，1.0 = 顶部）
    CGFloat sourceMidY = CGRectGetMidY(source);
    CGFloat relativePosition = viewportHeight > 0 ? (sourceMidY - viewportBottom) / viewportHeight : 0.5;

    // 判定空间充足性：下方/上方是否有足够空间放置候选
    CGFloat spaceBelow = sourceBottom - viewportBottom;
    CGFloat spaceAbove = viewportTop - sourceTop;
    CGFloat requiredSpace = height + gap + 8;  // 需要的最小空间（含间隙和余量）

    BOOL hasSpaceBelow = spaceBelow >= requiredSpace;
    BOOL hasSpaceAbove = spaceAbove >= requiredSpace;

    // 动态排序：优先尝试空间充足的方向
    if (!hasSpaceBelow && hasSpaceAbove) {
        // 下方空间不足，上方空间充足 → 上方优先
        add(FYInlineAnchorAbove, anchorX, CGRectGetMaxY(source) + gap, rank++, @"原文上方");
        add(FYInlineAnchorBelow, anchorX, CGRectGetMinY(source) - height - gap, rank++, @"原文下方");
    } else if (hasSpaceBelow && !hasSpaceAbove) {
        // 上方空间不足，下方空间充足 → 下方优先
        add(FYInlineAnchorBelow, anchorX, CGRectGetMinY(source) - height - gap, rank++, @"原文下方");
        add(FYInlineAnchorAbove, anchorX, CGRectGetMaxY(source) + gap, rank++, @"原文上方");
    } else if (relativePosition < 0.35) {
        // 原文在底部 1/3 区域且两侧空间都不足 → 上方优先
        add(FYInlineAnchorAbove, anchorX, CGRectGetMaxY(source) + gap, rank++, @"原文上方");
        add(FYInlineAnchorBelow, anchorX, CGRectGetMinY(source) - height - gap, rank++, @"原文下方");
    } else if (relativePosition > 0.65) {
        // 原文在顶部 1/3 区域 → 下方优先
        add(FYInlineAnchorBelow, anchorX, CGRectGetMinY(source) - height - gap, rank++, @"原文下方");
        add(FYInlineAnchorAbove, anchorX, CGRectGetMaxY(source) + gap, rank++, @"原文上方");
    } else {
        // 原文在中间区域 → 保持原有下方优先策略
        add(FYInlineAnchorBelow, anchorX, CGRectGetMinY(source) - height - gap, rank++, @"原文下方");
        add(FYInlineAnchorAbove, anchorX, CGRectGetMaxY(source) + gap, rank++, @"原文上方");
    }

    add(FYInlineAnchorRight, CGRectGetMaxX(source) + gap, CGRectGetMidY(source) - height / 2.0, rank++, @"原文右侧");
    add(FYInlineAnchorLeft, CGRectGetMinX(source) - gap - width, CGRectGetMidY(source) - height / 2.0, rank++, @"原文左侧");
    add(FYInlineAnchorOverlay, anchorX, CGRectGetMidY(source) - height / 2.0, rank, @"覆盖原文自身");

    return candidates;
}

#pragma mark 候选合法性

// 其它原文块与自己是**同一段文字**（归一化后完全相同）而且框高度重合时，
// 它不该被当成"另一个文本块"来挡自己的候选 —— 那是同一处文字被识别两次造成的假冲突。
// 刻意要求文字**完全相同**：像「一つ目の見出し」/「二つ目の見出し」这种只差一两个字的
// 相邻条目是两块真文字，互相遮挡仍然非法（既有套件专门守这条）。
static BOOL FYInlineSourceLooksDuplicated(NSString *selfText, NSString *otherText,
                                          CGRect selfRect, CGRect otherRect) {
    NSString *left = FYInlineNormalize(selfText ?: @"");
    NSString *right = FYInlineNormalize(otherText ?: @"");
    if (left.length < 2 || ![left isEqualToString:right]) { return NO; }
    CGFloat selfArea = NSWidth(selfRect) * NSHeight(selfRect);
    CGFloat otherArea = NSWidth(otherRect) * NSHeight(otherRect);
    CGFloat minArea = MIN(selfArea, otherArea);
    if (minArea <= 1) { return NO; }
    CGRect hit = CGRectIntersection(selfRect, otherRect);
    if (CGRectIsNull(hit) || CGRectIsEmpty(hit)) { return NO; }
    return (hit.size.width * hit.size.height) / minArea >= 0.6;
}

- (void)filterCandidates:(NSArray<FYInlineCandidate *> *)candidates
                placement:(FYInlinePlacement *)placement
                 viewport:(CGRect)viewport
            otherSources:(NSArray<NSValue *> *)otherSources
           sourceIndices:(NSArray<NSNumber *> *)sourceIndices
              selfIndex:(NSUInteger)selfIndex
               report:(NSMutableArray<NSString *> *)report {
    [self filterCandidates:candidates placement:placement viewport:viewport
              otherSources:otherSources sourceIndices:sourceIndices sourceTexts:nil
                 selfIndex:selfIndex report:report];
}

- (void)filterCandidates:(NSArray<FYInlineCandidate *> *)candidates
                placement:(FYInlinePlacement *)placement
                 viewport:(CGRect)viewport
            otherSources:(NSArray<NSValue *> *)otherSources
           sourceIndices:(NSArray<NSNumber *> *)sourceIndices
             sourceTexts:(NSArray<NSString *> *)sourceTexts
                selfIndex:(NSUInteger)selfIndex
                   report:(NSMutableArray<NSString *> *)report {
    NSString *selfText = FYInlineNormalize(placement.block.text ?: @"");
    for (FYInlineCandidate *candidate in candidates) {
        if (!FYInlineRectContainsRect(viewport, candidate.frame)) {
            candidate.rejection = @"超出可见区域";
            candidate.hardRejection = YES;
            continue;
        }
        if (candidate.anchor != FYInlineAnchorOverlay) {
            // 位移有界：不许漂到别的条目附近。
            CGFloat maxDrift = MAX(NSHeight(placement.sourceFrame), NSHeight(candidate.frame)) + self.panelGap + 4;
            if (candidate.distance > maxDrift) {
                candidate.rejection = @"离原文过远";
                candidate.hardRejection = YES;
                continue;
            }
        }
        // 覆盖自身正文是允许的；压到**别的**块才不合法。这里只记下最大交叠厚度：
        // 是否真的非法由统一安排阶段结合「上一帧是否用同一个锚定方向」判定，
        // 这样 1~3px 的抖动不会让贴片在下方/上方之间来回跳。
        // 放宽遮挡容忍度：≤10pt 的轻微交叠视为可接受（避免密集文本场景下"明明有空间却显示空间不足"）。
        for (NSUInteger index = 0; index < otherSources.count; index++) {
            if (index == selfIndex) { continue; }
            CGRect other = otherSources[index].rectValue;
            if (NSWidth(other) < 2 || NSHeight(other) < 2) { continue; }
            if (!CGRectIntersectsRect(candidate.frame, other)) { continue; }
            NSString *otherText = index < sourceTexts.count ? sourceTexts[index] : nil;
            if (FYInlineSourceLooksDuplicated(selfText, FYInlineNormalize(otherText ?: @""),
                                              placement.sourceFrame, other)) {
                // 记一条诊断，但不计为遮挡：重复框不该让这一块失去位置。
                if (candidate.occlusionDepth <= 0) {
                    candidate.rejection = [NSString stringWithFormat:@"与第 %@ 个原文块几乎重合（疑似重复识别，不计为遮挡）",
                                           sourceIndices[index]];
                }
                continue;
            }
            CGRect hit = CGRectIntersection(candidate.frame, other);
            CGFloat depth = (hit.size.width > 0 && hit.size.height > 0) ? MIN(hit.size.width, hit.size.height) : 0;
            if (depth > candidate.occlusionDepth) {
                candidate.occlusionDepth = depth;
                candidate.rejection = [NSString stringWithFormat:@"遮挡第 %@ 个原文块（%ld×%ld，交叠 %.0fpt）",
                                       sourceIndices[index], (long)lround(hit.size.width), (long)lround(hit.size.height), depth];
            }
        }
    }
    for (FYInlineCandidate *candidate in candidates) {
        if (candidate.rejection.length > 0) {
            [report addObject:[NSString stringWithFormat:@"%@：%@", candidate.name, candidate.rejection]];
        }
    }
}

#pragma mark 细缝消解

/// 候选与其它原文块只差 1~容差 点的细缝时：不直接接受重叠，也不因此换锚点，
/// 而是沿垂直方向做 ≤ 容差 的微移把它消掉 —— 既严格不遮挡别的块，又保持锚定方向与位置稳定。
- (FYInlineCandidate *)candidate:(FYInlineCandidate *)candidate
          resolvingSliverWithin:(CGFloat)tolerance
                       viewport:(CGRect)viewport
                     placement:(FYInlinePlacement *)placement
                   otherSources:(NSArray<NSValue *> *)otherSources
                    placedFrames:(NSArray<NSValue *> *)placedFrames {
    if (candidate.occlusionDepth <= 0 || candidate.occlusionDepth > tolerance) { return nil; }
    CGFloat step = candidate.occlusionDepth + 0.5;
    for (NSNumber *shift in @[@(step), @(-step)]) {
        CGRect moved = NSOffsetRect(candidate.frame, 0, shift.doubleValue);
        if (fabs(shift.doubleValue) > tolerance + 0.5) { continue; }
        if (!FYInlineRectContainsRect(viewport, moved)) { continue; }
        if (candidate.anchor != FYInlineAnchorOverlay) {
            CGFloat maxDrift = MAX(NSHeight(placement.sourceFrame), NSHeight(moved)) + self.panelGap + 4;
            CGFloat distance = MAX(0, MAX(CGRectGetMinY(placement.sourceFrame) - CGRectGetMaxY(moved),
                                          CGRectGetMinY(moved) - CGRectGetMaxY(placement.sourceFrame)));
            if (distance > maxDrift) { continue; }
        }
        BOOL blocked = NO;
        for (NSValue *value in otherSources) {
            if (CGRectIntersectsRect(moved, value.rectValue)) { blocked = YES; break; }
        }
        if (blocked) { continue; }
        for (NSValue *value in placedFrames) {
            if (CGRectIntersectsRect(moved, value.rectValue)) { blocked = YES; break; }
        }
        if (blocked) { continue; }
        FYInlineCandidate *resolved = [FYInlineCandidate new];
        resolved.anchor = candidate.anchor;
        resolved.anchorRank = candidate.anchorRank;
        resolved.compact = candidate.compact;
        resolved.name = candidate.name;
        resolved.frame = moved;
        resolved.distance = candidate.distance;
        resolved.scrollable = candidate.scrollable;
        resolved.measuredContentHeight = candidate.measuredContentHeight;
        resolved.bodyViewportHeight = candidate.bodyViewportHeight;
        resolved.occlusionDepth = 0;
        return resolved;
    }
    return nil;
}

#pragma mark 评分

- (CGFloat)scoreForCandidate:(FYInlineCandidate *)candidate
                   placement:(FYInlinePlacement *)placement
                    previous:(FYInlinePlacement *)previous
              columnAnchors:(NSDictionary<NSNumber *, NSNumber *> *)columnAnchors
                    columnKey:(NSNumber *)columnKey {
    CGFloat score = candidate.anchorRank * 42.0 + candidate.distance;
    if (previous) {
        if (previous.anchor == candidate.anchor) { score -= 30.0; }
        CGRect previousFrame = previous.translationFrame;
        score += fabs(CGRectGetMidY(previousFrame) - CGRectGetMidY(candidate.frame)) * 0.35;
        score += fabs(CGRectGetMidX(previousFrame) - CGRectGetMidX(candidate.frame)) * 0.15;
    }
    NSNumber *columnAnchor = columnAnchors[columnKey];
    if (columnAnchor && columnAnchor.integerValue == (NSInteger)candidate.anchor) { score -= 24.0; }
    if (columnAnchor && columnAnchor.integerValue != (NSInteger)candidate.anchor) { score += 14.0; }
    return score;
}

- (NSNumber *)columnKeyForSourceFrame:(CGRect)sourceFrame viewport:(CGRect)viewport {
    CGFloat x = NSWidth(viewport) > 0 ? (NSMidX(sourceFrame) - NSMinX(viewport)) / NSWidth(viewport) : 0.5;
    return @((NSInteger)floor(FYInlineClamp(x, 0, 0.999) * 4.0));   // 画面横向 4 等分作为“列”的粗分桶
}

#pragma mark 主入口

// 长卡候选组合要"先试正常排版、再逐档退让"：每一轮按当前候选算一遍完整布局，
// 仍然是折叠/放不下的长块就把候选序号 +1 再算一遍（有限轮、只前进、不回退）。
// 这样"固定规格卡片放不下"不会再被当成"译文放不下"，也不会无限缩字。
- (FYInlineLayoutResult *)layoutRequests:(NSArray<FYInlineLayoutRequest *> *)requests
                                viewport:(CGRect)viewport
                                previous:(FYInlineLayoutResult *)previous {
    NSMutableDictionary<NSString *, NSNumber *> *variantIndexes = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *attemptLog = [NSMutableDictionary dictionary];
    FYInlineLayoutResult *result = nil;
    NSUInteger maximumRounds = 12;
    for (NSUInteger round = 0; round < maximumRounds; round++) {
        result = [self layoutRequestsOnce:requests viewport:viewport previous:previous
                           variantIndexes:variantIndexes attemptLog:attemptLog];
        BOOL progressed = NO;
        for (FYInlinePlacement *placement in result.placements) {
            if (placement.block.kind != FYInlineBlockKindLong) { continue; }
            BOOL degraded = placement.mode == FYInlineDisplayModeCompactEntry ||
                            placement.mode == FYInlineDisplayModeUnplaceable;
            if (!degraded) { continue; }
            FYInlineLayoutRequest *request = nil;
            for (FYInlineLayoutRequest *candidate in requests) {
                if ([candidate.block.blockID isEqualToString:placement.block.blockID]) { request = candidate; break; }
            }
            if (!request) { continue; }
            NSUInteger used = variantIndexes[placement.blockID].unsignedIntegerValue;
            NSUInteger count = [self longCardVariantsForRequest:request viewport:viewport].count;
            if (used + 1 < count) {
                variantIndexes[placement.blockID] = @(used + 1);
                progressed = YES;
            }
        }
        if (!progressed) { break; }
    }
    // 把候选尝试记录写回结果（诊断：每个候选的宽/字号/卡尺寸/失败原因/冲突块）。
    for (FYInlinePlacement *placement in result.placements) {
        NSArray<NSString *> *lines = attemptLog[placement.blockID];
        placement.variantDiagnostics = lines ?: @[];
        self.lastVariantDiagnostics = [lines copy] ?: @[];
    }
    return result;
}

- (FYInlineLayoutResult *)layoutRequestsOnce:(NSArray<FYInlineLayoutRequest *> *)requests
                                    viewport:(CGRect)viewport
                                    previous:(FYInlineLayoutResult *)previous
                              variantIndexes:(NSDictionary<NSString *, NSNumber *> *)variantIndexes
                                  attemptLog:(NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *)attemptLog {
    FYInlineLayoutResult *result = [FYInlineLayoutResult new];
    if (NSWidth(viewport) < 2 || NSHeight(viewport) < 2 || requests.count == 0) {
        result.placements = @[];
        result.changedFromPrevious = previous != nil && previous.placements.count > 0;
        result.revision = ++self.revision;
        return result;
    }

    NSMutableArray<NSValue *> *sourceFrames = [NSMutableArray array];
    NSMutableArray<NSNumber *> *sourceIndices = [NSMutableArray array];
    NSMutableArray<NSString *> *sourceTexts = [NSMutableArray array];
    for (NSUInteger index = 0; index < requests.count; index++) {
        [sourceFrames addObject:[NSValue valueWithRect:requests[index].sourceFrame]];
        [sourceIndices addObject:@(index + 1)];
        [sourceTexts addObject:FYInlineNormalize(requests[index].block.text ?: @"")];
    }

    // ① 帧间身份稳定 + 单块测量 + 候选生成
    NSMutableArray<FYInlinePlacement *> *placements = [NSMutableArray array];
    NSMutableArray<NSArray<FYInlineCandidate *> *> *candidateLists = [NSMutableArray array];
    NSMutableSet<NSString *> *claimedPreviousIDs = [NSMutableSet set];
    for (NSUInteger requestIndex = 0; requestIndex < requests.count; requestIndex++) {
        FYInlineLayoutRequest *request = requests[requestIndex];
        NSString *stableID = nil;
        if (previous) {
            stableID = [FYInlineBlockMatcher stableBlockIDForBlock:request.block
                                                              text:request.block.text
                                                       sourceFrame:request.sourceFrame
                                                    previousResult:previous];
            if (stableID.length > 0 && [claimedPreviousIDs containsObject:stableID]) { stableID = nil; }
            if (stableID.length > 0) { [claimedPreviousIDs addObject:stableID]; }
        }
        if (stableID.length == 0) { stableID = request.block.blockID; }
        FYInlinePlacement *placement = [self basePlacementForRequest:request stableID:stableID viewport:viewport];
        placement.blockID = stableID;

        NSMutableArray<NSString *> *report = [NSMutableArray array];
        if (request.translation.length == 0) {
            placement.mode = FYInlineDisplayModeUnplaceable;
            placement.reason = @"没有译文可显示";
            placement.rejectedCandidates = report;
            [placements addObject:placement];
            [candidateLists addObject:@[]];
            continue;
        }

        BOOL compact = NO;
        if (request.block.kind == FYInlineBlockKindLong) {
            NSArray<NSDictionary *> *variants = [self longCardVariantsForRequest:request viewport:viewport];
            NSUInteger variantIndex = variantIndexes[stableID].unsignedIntegerValue;
            if (variantIndex > 0 && variantIndex < variants.count) { placement.chosenVariant = variantIndex; }
            NSDictionary *variant = variants.count > 0 ? variants[MIN(placement.chosenVariant, variants.count - 1)] : nil;
            compact = [self prepareLongPlacementForRequest:request placement:placement viewport:viewport variant:variant];
            NSString *attempt = [NSString stringWithFormat:
                @"候选#%lu 宽%.0f 字号%.0f 修饰=%@ 卡=%.0fx%.0f 正文高%.0f 滚动=%@",
                (unsigned long)(placement.chosenVariant + 1), placement.longCardSize.width,
                placement.chosenBodyFontSize, variant[@"chrome"] ?: @"-",
                placement.longCardSize.width, placement.longCardSize.height,
                placement.measuredContentHeight, placement.scrollable ? @"是" : @"否"];
            NSMutableArray<NSString *> *lines = attemptLog[stableID];
            if (!lines) { lines = [NSMutableArray array]; attemptLog[stableID] = lines; }
            [lines addObject:[attempt stringByAppendingFormat:@" → %@", compact ? @"候选判定：画面放不下可读正文，改用折叠入口" : @"可排版，进入落位搜索"]];
        } else {
            [self prepareShortPlacement:placement sourceText:request.block.text viewport:viewport];
        }
        if (request.manuallyPlaced) {
            // 用户拖动过的块：位置＝原文锚点 + 手动偏移，只夹到可见区域内；
            // 不参与候选评分，也不因为它压到别的原文块就被拉回去（那是用户的选择）。
            NSRect frame = placement.translationFrame;
            frame.origin.x = NSMinX(request.sourceFrame) + request.manualOffset.width;
            frame.origin.y = NSMinY(request.sourceFrame) + request.manualOffset.height;
            frame.origin.x = FYInlineClamp(frame.origin.x, NSMinX(viewport) + self.viewportMargin,
                                           MAX(NSMinX(viewport) + self.viewportMargin,
                                               NSMaxX(viewport) - self.viewportMargin - NSWidth(frame)));
            frame.origin.y = FYInlineClamp(frame.origin.y, NSMinY(viewport) + self.viewportMargin,
                                           MAX(NSMinY(viewport) + self.viewportMargin,
                                               NSMaxY(viewport) - self.viewportMargin - NSHeight(frame)));
            placement.translationFrame = NSIntegralRect(frame);
            placement.manuallyPlaced = YES;
            placement.anchor = FYInlineAnchorManual;
            placement.compactEntry = compact;
            if (compact) {
                placement.mode = FYInlineDisplayModeCompactEntry;
            } else if (request.block.kind == FYInlineBlockKindLong) {
                placement.mode = placement.scrollable ? FYInlineDisplayModeScrollingCard : FYInlineDisplayModeFullCard;
            } else {
                placement.mode = FYInlineDisplayModeShortLabel;
            }
            placement.reason = [NSString stringWithFormat:@"手动位置（相对原文锚点 %.0f, %.0f）",
                                placement.translationFrame.origin.x - NSMinX(request.sourceFrame),
                                placement.translationFrame.origin.y - NSMinY(request.sourceFrame)];
            [placements addObject:placement];
            [candidateLists addObject:@[]];
            continue;
        }
        // 紧凑入口的候选同样要过边界与冲突检查：没有合法位置就标记“暂不可放置”。
        NSArray<FYInlineCandidate *> *candidates = [self candidatesForPlacement:placement viewport:viewport
                                                                   compactEntry:compact
                                                                         widths:@[@(NSWidth(placement.translationFrame))]];
        [self filterCandidates:candidates placement:placement viewport:viewport
                  otherSources:sourceFrames sourceIndices:sourceIndices
                    sourceTexts:sourceTexts selfIndex:requestIndex report:report];
        placement.rejectedCandidates = report;
        [candidateLists addObject:candidates];
        [placements addObject:placement];
    }

    // ② 统一安排：先处理"注定只能降级的长正文"，再按候选最少（最受限），最后按阅读顺序；
    //    合法优先，冲突的候选直接不可用 —— 不靠降低评分来允许跨栏或压扁。
    NSMutableArray<NSNumber *> *order = [NSMutableArray array];
    for (NSUInteger index = 0; index < placements.count; index++) { [order addObject:@(index)]; }
    [order sortUsingComparator:^NSComparisonResult(NSNumber *left, NSNumber *right) {
        NSUInteger leftIndex = left.unsignedIntegerValue, rightIndex = right.unsignedIntegerValue;
        NSUInteger leftLegal = 0, rightLegal = 0;
        for (FYInlineCandidate *candidate in candidateLists[leftIndex]) { if (!candidate.hardRejection && candidate.occlusionDepth <= 0) { leftLegal++; } }
        for (FYInlineCandidate *candidate in candidateLists[rightIndex]) { if (!candidate.hardRejection && candidate.occlusionDepth <= 0) { rightLegal++; } }
        // 长正文一个合法长卡候选都没有 = 只能靠紧凑入口。它必须排在可调整的短贴片之前，
        // 否则小贴片会先把它附近（以及它自己那一片）的空地占满，入口再也放不下，
        // 整段正文就从画面上消失 —— 短贴片至少还有"覆盖自身/左右"这些可选项。
        FYInlinePlacement *leftPlacement = placements[leftIndex];
        FYInlinePlacement *rightPlacement = placements[rightIndex];
        BOOL leftAtRisk = leftPlacement.block.kind == FYInlineBlockKindLong && leftLegal == 0;
        BOOL rightAtRisk = rightPlacement.block.kind == FYInlineBlockKindLong && rightLegal == 0;
        if (leftAtRisk != rightAtRisk) { return leftAtRisk ? NSOrderedAscending : NSOrderedDescending; }
        if (leftLegal != rightLegal) { return leftLegal < rightLegal ? NSOrderedAscending : NSOrderedDescending; }
        return leftIndex < rightIndex ? NSOrderedAscending : NSOrderedDescending;
    }];

    NSMutableArray<NSValue *> *placedFrames = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, NSNumber *> *columnAnchors = [NSMutableDictionary dictionary];
    for (NSNumber *number in order) {
        NSUInteger index = number.unsignedIntegerValue;
        FYInlinePlacement *placement = placements[index];
        if (placement.mode == FYInlineDisplayModeUnplaceable) { continue; }
        if (placement.manuallyPlaced) {
            // 手动位置先占位，后面的候选会避开它。
            [placedFrames addObject:[NSValue valueWithRect:placement.translationFrame]];
            continue;
        }
        NSArray<FYInlineCandidate *> *candidates = candidateLists[index];
        FYInlinePlacement *previousPlacement = [previous placementForBlockID:placement.blockID];
        NSNumber *columnKey = [self columnKeyForSourceFrame:placement.sourceFrame viewport:viewport];

        // 合法性与帧间稳定在此合流：
        //   · 压到别的原文块/别的译文一律非法；
        //   · 但 1~stabilityTolerance 点的细缝先尝试“微移消解”，避免 OCR 抖动让锚点翻面。
        FYInlineCandidate *chosen = nil;
        for (FYInlineCandidate *loopCandidate in candidates) {
            if (loopCandidate.hardRejection) { continue; }
            FYInlineCandidate *candidate = loopCandidate;
            FYInlineCandidate *usable = candidate;
            if (candidate.occlusionDepth > 0) {
                // 仅在容差内微移，不能让卡片覆盖其它原文。
                usable = [self candidate:candidate resolvingSliverWithin:self.stabilityTolerance
                                viewport:viewport placement:placement
                            otherSources:sourceFrames placedFrames:placedFrames];
                if (!usable) { continue; }
            }
            BOOL conflict = NO;
            for (NSValue *value in placedFrames) {
                CGRect hit = CGRectIntersection(value.rectValue, usable.frame);
                if (CGRectIsNull(hit) || CGRectIsEmpty(hit)) { continue; }
                if (MIN(hit.size.width, hit.size.height) > 0) { conflict = YES; break; }
            }
            if (conflict) {
                FYInlineCandidate *resolved = [self candidate:usable resolvingSliverWithin:self.stabilityTolerance
                                                     viewport:viewport placement:placement
                                                 otherSources:sourceFrames placedFrames:placedFrames];
                if (resolved) { usable = resolved; } else { continue; }
            }
            if (!chosen || [self scoreForCandidate:usable placement:placement previous:previousPlacement
                                     columnAnchors:columnAnchors columnKey:columnKey] <
                           [self scoreForCandidate:chosen placement:placement previous:previousPlacement
                                     columnAnchors:columnAnchors columnKey:columnKey]) {
                chosen = usable;
            }
        }

        if (!chosen) {
            // ③ 明确降级：先给紧凑入口，再不行标记“暂不可放置”，绝不强盖别的条目。
            // 多行块（含被分类判成"短"的段落）同样要走到这里：现场五行喜好正文就是被
            // 当成短块、又没有入口，整段从画面消失的。
            NSUInteger blockLineCount = MAX(placement.block.lineCount, (NSInteger)placement.block.lineBoxes.count);
            BOOL canDegradeToEntry = placement.block.kind == FYInlineBlockKindLong ||
                                     blockLineCount >= 3;
            if (canDegradeToEntry) {
                NSMutableArray<NSString *> *compactReport = [placement.rejectedCandidates mutableCopy] ?: [NSMutableArray array];
                // 紧凑入口必须先按内容量好尺寸，再找位置：沿用长卡宽度会让这个本可以很小
                // 的入口到处放不下，于是整段正文从画面上消失。
                // 收起原因按**实际原因**给：译文本身超出可读高度（要滚动/顶到高度上限）才算"文本过长"；
                // 卡片尺寸其实放得下、只是四周被别的原文块或贴译占满，那是"空间不足"。
                CGFloat cardHeightCap = MIN(self.cardMaxHeight, NSHeight(viewport) * self.cardHeightFraction);
                BOOL textTooLong = placement.scrollable ||
                                   NSHeight(placement.translationFrame) >= cardHeightCap - 0.5;
                [self applyFoldedEntryCopyToPlacement:placement crowded:!textTooLong];
                CGSize compactSize = [self foldedEntrySizeForViewport:viewport
                                                                title:placement.entryTitle
                                                                 hint:placement.entryHint];
                placement.compactEntrySize = compactSize;
                placement.compactEntry = YES;
                placement.translationFrame = NSMakeRect(0, 0, compactSize.width, compactSize.height);
                FYInlineCandidate *compact = [self bestCompactCandidateForPlacement:placement viewport:viewport
                                                                      placedFrames:placedFrames sourceFrames:sourceFrames
                                                                     sourceIndices:sourceIndices sourceTexts:sourceTexts
                                                                         selfIndex:index report:compactReport];
                placement.rejectedCandidates = compactReport;
                if (compact) {
                    placement.mode = FYInlineDisplayModeCompactEntry;
                    placement.anchor = FYInlineAnchorCompactEntry;
                    placement.compactEntry = YES;
                    placement.translationFrame = compact.frame;
                    placement.reason = [NSString stringWithFormat:
                        @"没有合法的贴译位置：改为折叠入口紧凑入口（%.0f×%.0f，按内容测量）：%@",
                        NSWidth(compact.frame), NSHeight(compact.frame), placement.entryHint ?: @""];
                    [self appendVariantOutcomeForPlacement:placement
                                                    attempt:attemptLog
                                                     reason:[NSString stringWithFormat:@"折叠（%@）",
                                                             placement.entryReasonCrowded ? @"可用空间不足/重复块占位" : @"文字太长"]
                                                     rejected:placement.rejectedCandidates];
                } else {
                    placement.mode = FYInlineDisplayModeUnplaceable;
                    placement.reason = [NSString stringWithFormat:
                        @"所有候选都会遮挡其它原文块或互相冲突：长卡 %.0f×%.0f、紧凑入口 %.0f×%.0f 都放不下（译文仍在主界面列出）",
                        placement.longCardSize.width, placement.longCardSize.height,
                        placement.compactEntrySize.width, placement.compactEntrySize.height];
                    placement.translationFrame = NSZeroRect;
                }
            } else {
                placement.mode = FYInlineDisplayModeUnplaceable;
                placement.reason = @"所有候选都会遮挡其它原文块或互相冲突：本块暂不可放置（译文仍在主界面列出）";
                placement.translationFrame = NSZeroRect;
            }
        } else {
            placement.translationFrame = chosen.frame;
            placement.anchor = chosen.anchor;
            if (placement.compactEntry) {
                placement.mode = FYInlineDisplayModeCompactEntry;
            } else if (placement.block.kind == FYInlineBlockKindLong) {
                placement.mode = placement.scrollable ? FYInlineDisplayModeScrollingCard : FYInlineDisplayModeFullCard;
            } else {
                placement.mode = FYInlineDisplayModeShortLabel;
            }
            if (placement.compactEntry) {
                placement.reason = [NSString stringWithFormat:@"%@：画面放不下可读的三行正文，这里给「查看译文」紧凑入口", chosen.name];
                [placedFrames addObject:[NSValue valueWithRect:placement.translationFrame]];
                continue;
            }
            placement.bodyViewportHeight = chosen.bodyViewportHeight;
            placement.reason = [NSString stringWithFormat:@"%@，%@", chosen.name,
                                placement.mode == FYInlineDisplayModeScrollingCard ? @"正文超出视口、卡内滚动" :
                                (placement.mode == FYInlineDisplayModeFullCard ? @"完整正文一屏可见" : @"贴合译文宽度")];
            if (placement.block.kind == FYInlineBlockKindLong && !placement.scrollable) {
                placement.reason = [NSString stringWithFormat:@"%@，按完整译文计算高度", chosen.name];
            }
            columnAnchors[columnKey] = @((NSInteger)chosen.anchor);
        }
        if (!CGRectIsEmpty(placement.translationFrame)) {
            [placedFrames addObject:[NSValue valueWithRect:placement.translationFrame]];
        }
    }

    result.placements = placements;
    result.revision = ++self.revision;
    result.changedFromPrevious = [self result:result differsFromPrevious:previous];
    return result;
}

/// 把这一轮候选的失败原因（含冲突块）补进诊断记录。
- (void)appendVariantOutcomeForPlacement:(FYInlinePlacement *)placement
                                 attempt:(NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *)attemptLog
                                  reason:(NSString *)reason
                                rejected:(NSArray<NSString *> *)rejected {
    if (!placement.blockID) { return; }
    NSMutableArray<NSString *> *lines = attemptLog[placement.blockID];
    if (!lines) { lines = [NSMutableArray array]; attemptLog[placement.blockID] = lines; }
    NSString *conflict = @"无";
    for (NSString *line in rejected) {
        if ([line containsString:@"遮挡"] || [line containsString:@"超出"] || [line containsString:@"冲突"]) {
            conflict = line;
            break;
        }
    }
    [lines addObject:[NSString stringWithFormat:@"    ↳ %@；首个冲突：%@", reason, conflict]];
}

/// 长卡的有限候选组合：宽度 × 修饰（内边距/标题带）× 字号。
/// 顺序按优先级：贴合原文宽度 → 减少标题与留白 → 逐档缩字（不低于 minimumLongBodyFontSize）。
/// 有可读正文空间而全文较长时允许卡内滚动，不因此折叠。
- (NSArray<NSDictionary *> *)longCardVariantsForRequest:(FYInlineLayoutRequest *)request viewport:(CGRect)viewport {
    NSMutableArray<NSDictionary *> *variants = [NSMutableArray array];
    NSArray<NSNumber *> *widths = [self cardWidthCandidatesForSource:request.sourceFrame viewport:viewport];
    NSMutableArray<NSNumber *> *fontSizes = [NSMutableArray array];
    CGFloat floorSize = MAX((CGFloat)10, self.minimumLongBodyFontSize);
    for (CGFloat size = self.longBodyFontSize; size >= floorSize - 0.01; size -= 2) {
        [fontSizes addObject:@(size)];
    }
    if (fontSizes.count == 0) { [fontSizes addObject:@(self.longBodyFontSize)]; }
    for (NSNumber *widthValue in widths) {
        // 每个宽度先试"完整修饰 + 原字号"，修饰压缩优先于缩字。
        [variants addObject:@{@"width": widthValue, @"padding": @18, @"titleBand": @(24 + 13),
                              @"fontSize": fontSizes.firstObject, @"chrome": @"完整"}];
        for (NSNumber *fontSize in fontSizes) {
            [variants addObject:@{@"width": widthValue, @"padding": @12, @"titleBand": @0,
                                  @"fontSize": fontSize, @"chrome": @"紧凑"}];
        }
    }
    return variants;
}

- (void)applyLongCardVariant:(NSDictionary *)variant toPlacement:(FYInlinePlacement *)placement {
    CGFloat padding = [variant[@"padding"] doubleValue];
    CGFloat titleBand = [variant[@"titleBand"] doubleValue];
    CGFloat fontSize = [variant[@"fontSize"] doubleValue];
    placement.panelPadding = padding;
    placement.titleBandHeight = titleBand;
    placement.cornerRadius = titleBand > 0 ? 12 : 10;
    placement.font = [self fontOfSize:fontSize weight:NSFontWeightRegular];
    placement.paragraphStyle = [self paragraphStyleWithLineSpacing:self.longLineSpacing];
    placement.chosenBodyFontSize = fontSize;
}

/// 长卡的宽度与高度测量。返回 YES 表示这一块只能给紧凑入口
/// （画面连可读的三行正文都放不下）。
- (BOOL)prepareLongPlacementForRequest:(FYInlineLayoutRequest *)request
                             placement:(FYInlinePlacement *)placement
                              viewport:(CGRect)viewport {
    return [self prepareLongPlacementForRequest:request placement:placement viewport:viewport variant:nil];
}

- (BOOL)prepareLongPlacementForRequest:(FYInlineLayoutRequest *)request
                             placement:(FYInlinePlacement *)placement
                              viewport:(CGRect)viewport
                               variant:(NSDictionary *)variant {
    if (variant) {
        [self applyLongCardVariant:variant toPlacement:placement];
    } else {
        NSFont *font = [self fontOfSize:self.longBodyFontSize weight:NSFontWeightRegular];
        placement.font = font;
        placement.paragraphStyle = [self paragraphStyleWithLineSpacing:self.longLineSpacing];
        placement.panelPadding = 18;
        placement.titleBandHeight = 24 + 13;
        placement.cornerRadius = 12;
        placement.chosenBodyFontSize = self.longBodyFontSize;
    }

    CGFloat minimumHeight = [self minimumCardHeight];
    CGFloat windowInner = NSHeight(viewport) - 24;
    if (windowInner < minimumHeight) {
        // 连三行正文都放不下：给明确的紧凑入口，不生成细条、不静默丢弃。
        // 尺寸按「查看译文」这行字测量（与绘制共用 compactEntryTitle / compactEntryFont），
        // 不再继承长卡宽度 —— 否则这个入口本身就经常放不下。
        // 连三行可读正文都放不下：这是**空间**不足，不是文本过长。
        [self applyFoldedEntryCopyToPlacement:placement crowded:YES];
        CGSize compactSize = [self foldedEntrySizeForViewport:viewport title:placement.entryTitle hint:placement.entryHint];
        placement.compactEntrySize = compactSize;
        placement.longCardSize = CGSizeZero;
        placement.translationFrame = NSMakeRect(0, 0, compactSize.width, compactSize.height);
        placement.mode = FYInlineDisplayModeCompactEntry;
        placement.compactEntry = YES;
        placement.scrollable = NO;
        placement.measuredContentHeight = [self measuredBodyHeight:placement.translation placement:placement
                                                             width:MAX((CGFloat)180, NSWidth(request.sourceFrame))];
        placement.bodyViewportHeight = 0;
        placement.reason = @"画面放不下可读的三行正文：使用紧凑入口";
        return YES;
    }
    NSArray<NSNumber *> *widths = nil;
    if (variant[@"width"]) {
        widths = @[variant[@"width"]];
    } else {
        widths = [self cardWidthCandidatesForSource:request.sourceFrame viewport:viewport];
    }
    CGFloat cap = MIN(self.cardMaxHeight, NSHeight(viewport) * self.cardHeightFraction);
    // 基准宽度放不下完整译文时，允许再试一个更宽的有限候选（减少不必要的滚动），
    // 但绝不靠缩小字号去塞。
    if (!variant[@"width"] &&
        [self measuredBodyHeight:placement.translation placement:placement width:widths.firstObject.doubleValue] > cap) {
        widths = [self cardWidthCandidatesForSource:request.sourceFrame viewport:viewport wide:YES];
    }
    [self prepareLongPlacement:placement widthCandidates:widths windowInner:windowInner cap:cap
                     minHeight:minimumHeight];
    return NO;
}

- (NSArray<NSNumber *> *)cardWidthCandidatesForSource:(CGRect)sourceFrame viewport:(CGRect)viewport wide:(BOOL)wide {
    // 过去这里只有一个宽度、并且把下限抬到 300/260 —— "固定规格卡片放不下"于是被当成
    // "译文放不下"，明明原文区域只有 244pt 宽也生成 300pt 的卡，最后判定空间不足去折叠。
    // 现在按原文区域给出**有限、可解释**的宽度候选：贴合原文 → 略宽 → 更宽，
    // 一律不得超过可用宽度，也不低于可读下限。
    CGFloat available = MIN(MAX((CGFloat)200, NSWidth(viewport) - 24), self.cardMaxWidth);
    CGFloat fraction = wide ? self.cardWideFraction : self.cardWidthFraction;
    CGFloat widest = MIN(available, NSWidth(viewport) * fraction);
    // 贴合原文区域：直接用原文宽度（只做 0.5pt 收敛），宽原文的行为与过去完全一致，
    // 窄原文不再被硬抬到 300pt。稳定策略不靠"量化宽度"，靠候选序号只前进不回退。
    CGFloat sourceWidth = round(NSWidth(sourceFrame) * 2.0) / 2.0;
    NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
    void (^addWidth)(CGFloat) = ^(CGFloat width) {
        CGFloat clamped = FYInlineClamp(width, self.minimumCardWidth, MAX(self.minimumCardWidth, MIN(widest, available)));
        clamped = round(clamped);
        for (NSNumber *existing in widths) { if (fabs(existing.doubleValue - clamped) < 1.0) { return; } }
        [widths addObject:@(clamped)];
    };
    addWidth(sourceWidth);                                  // ① 贴合原文区域
    addWidth(MAX(sourceWidth * 1.25, sourceWidth + 24));    // ② 略宽一档（减少滚动）
    addWidth(MAX(sourceWidth * 1.6, 320));                  // ③ 旧版基准宽度，只在前两档都放不下时用
    return widths;
}

- (NSArray<NSNumber *> *)cardWidthCandidatesForSource:(CGRect)sourceFrame viewport:(CGRect)viewport {
    return [self cardWidthCandidatesForSource:sourceFrame viewport:viewport wide:NO];
}

- (FYInlineCandidate *)bestCompactCandidateForPlacement:(FYInlinePlacement *)placement
                                               viewport:(CGRect)viewport
                                           placedFrames:(NSArray<NSValue *> *)placedFrames
                                           sourceFrames:(NSArray<NSValue *> *)sourceFrames
                                          sourceIndices:(NSArray<NSNumber *> *)sourceIndices
                                            sourceTexts:(NSArray<NSString *> *)sourceTexts
                                              selfIndex:(NSUInteger)selfIndex
                                                 report:(NSMutableArray<NSString *> *)report {
    // 入口尺寸在调用前已经按内容量好（placement.translationFrame），这里只做候选与合法性。
    NSArray<FYInlineCandidate *> *candidates = [self candidatesForPlacement:placement viewport:viewport compactEntry:YES
                                                                       widths:@[@(NSWidth(placement.translationFrame))]];
    [self filterCandidates:candidates placement:placement viewport:viewport otherSources:sourceFrames
             sourceIndices:sourceIndices sourceTexts:sourceTexts selfIndex:selfIndex report:report];
    FYInlineCandidate *best = nil;
    for (FYInlineCandidate *candidate in candidates) {
        if (candidate.hardRejection) { continue; }
        FYInlineCandidate *usable = candidate;
        if (candidate.occlusionDepth > 0) {
            // 与主路径同一套细缝消解：只允许 1~容差 点的抖动缝，靠微移消掉而不是接受遮挡。
            usable = [self candidate:candidate resolvingSliverWithin:self.stabilityTolerance
                            viewport:viewport placement:placement
                        otherSources:sourceFrames placedFrames:placedFrames];
            if (!usable) { continue; }
        }
        BOOL conflict = NO;
        for (NSValue *value in placedFrames) {
            CGRect hit = CGRectIntersection(value.rectValue, usable.frame);
            if (CGRectIsNull(hit) || CGRectIsEmpty(hit) || MIN(hit.size.width, hit.size.height) <= 0) { continue; }
            conflict = YES;
            [report addObject:[NSString stringWithFormat:@"%@：与已放置的译文面板冲突（%@）",
                               candidate.name, NSStringFromRect(value.rectValue)]];
            break;
        }
        if (conflict) { continue; }
        if (!best || candidate.anchorRank < best.anchorRank) { best = usable; }
    }
    return best;
}

- (BOOL)result:(FYInlineLayoutResult *)result differsFromPrevious:(FYInlineLayoutResult *)previous {
    if (!previous) { return YES; }
    if (previous.placements.count != result.placements.count) { return YES; }
    for (NSUInteger index = 0; index < result.placements.count; index++) {
        FYInlinePlacement *now = result.placements[index];
        FYInlinePlacement *before = previous.placements[index];
        if (![now.blockID isEqualToString:before.blockID]) { return YES; }
        if (now.mode != before.mode) { return YES; }
        if (![now.translation isEqualToString:before.translation]) { return YES; }
        if (!NSEqualRects(now.translationFrame, before.translationFrame)) { return YES; }
        if (fabs(now.measuredContentHeight - before.measuredContentHeight) > 0.5) { return YES; }
    }
    return NO;
}

@end
