#import "FYLearningViews.h"

void FYMountLearningPage(NSArray<NSView *> *pages, NSView *host, NSInteger index) {
    if (index < 0 || index >= (NSInteger)pages.count) return;
    if (pages[index].superview != host) {
        for (NSView *page in pages) [page removeFromSuperview];
        NSView *page=pages[index]; page.translatesAutoresizingMaskIntoConstraints=NO;
        [host addSubview:page];
        [NSLayoutConstraint activateConstraints:@[
            [page.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
            [page.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
            [page.topAnchor constraintEqualToAnchor:host.topAnchor],
            [page.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
        ]];
    }
}
void FYUpdateLearningPageSelection(NSArray<NSView *> *pages, NSArray<NSButton *> *buttons, NSInteger index) {
    for (NSInteger i=0; i<(NSInteger)pages.count; i++) {
        pages[i].hidden=i!=index;
        buttons[i].state=i==index ? NSControlStateValueOn : NSControlStateValueOff;
        buttons[i].needsDisplay=YES;
    }
}

@interface FYCapturePreviewView ()
@property(nonatomic, strong) NSLayoutConstraint *aspectConstraint;
@end
@implementation FYCapturePreviewView
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric); }
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) { [self updateAspectConstraint]; }
    return self;
}
- (void)updateAspectConstraint {
    NSSize size = self.image.size;
    CGFloat ratio = size.width > 0 && size.height > 0 ? size.height / size.width : 9.0 / 16.0;
    if (self.aspectConstraint && fabs(self.aspectConstraint.multiplier - ratio) < 0.000001) { return; }
    self.aspectConstraint.active = NO;
    // An upper bound permits spare width for tall captures at the height cap;
    // an equality would instead pull the window narrower to satisfy the ratio.
    self.aspectConstraint = [self.heightAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:ratio];
    self.aspectConstraint.active = YES;
}
- (void)setImage:(NSImage *)image {
    [super setImage:image];
    [self updateAspectConstraint];
}
@end

@implementation FYLearningStackView
- (void)addArrangedSubview:(NSView *)view {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [super addArrangedSubview:view];
    if (![view isKindOfClass:NSButton.class]) {
        [view.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
    }
}
@end

@interface FYLearningFlexView : NSView
@end
@implementation FYLearningFlexView
- (NSSize)intrinsicContentSize { return NSMakeSize(0, 0); }
@end
@interface FYLearningRowView ()
@property(nonatomic, strong) FYLearningFlexView *flex;
@end
@implementation FYLearningRowView
- (void)addArrangedSubview:(NSView *)view {
    if (self.flex) { [self removeArrangedSubview:self.flex]; [self.flex removeFromSuperview]; self.flex = nil; }
    [super addArrangedSubview:view];
    if ([view isKindOfClass:NSButton.class]) {
        [view setContentHuggingPriority:999 forOrientation:NSLayoutConstraintOrientationHorizontal];
    } else if ([view isKindOfClass:NSStackView.class]) {
        [view setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    BOOL onlyButtons = YES;
    for (NSView *child in self.arrangedSubviews) { if (![child isKindOfClass:NSButton.class]) { onlyButtons = NO; break; } }
    if (onlyButtons) {
        self.flex = [FYLearningFlexView new];
        [self.flex setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [super addArrangedSubview:self.flex];
    }
}
@end

@interface FYLearningColumnsView ()
@property(nonatomic, copy) NSArray<NSLayoutConstraint *> *columnWidths;
@property(nonatomic) BOOL compact;
@end
@implementation FYLearningColumnsView
- (void)addArrangedSubview:(NSView *)view {
    [super addArrangedSubview:view];
    [self updateColumns];
}
- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [self updateColumns];
}
- (void)updateColumns {
    if (self.arrangedSubviews.count != 2) { return; }
    BOOL compact = self.bounds.size.width > 0 && self.bounds.size.width < (self.compactWidth > 0 ? self.compactWidth : 800);
    if (self.columnWidths && compact == self.compact) { return; }
    [NSLayoutConstraint deactivateConstraints:self.columnWidths ?: @[]];
    self.compact = compact;
    self.distribution = NSStackViewDistributionFill;
    self.orientation = compact ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
    self.alignment = compact ? NSLayoutAttributeLeading : NSLayoutAttributeTop;
    NSView *left = self.arrangedSubviews[0], *right = self.arrangedSubviews[1];
    if (compact) {
        self.columnWidths = @[[left.widthAnchor constraintEqualToAnchor:self.widthAnchor],
                              [right.widthAnchor constraintEqualToAnchor:self.widthAnchor]];
    } else {
        CGFloat fraction = self.leftFraction > 0 ? self.leftFraction : 0.524;
        self.columnWidths = @[[left.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:fraction constant:-self.spacing * fraction],
                              [right.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:1-fraction constant:-self.spacing * (1-fraction)]];
        // Allow the window to shrink first; the compact layout then takes over.
        for (NSLayoutConstraint *constraint in self.columnWidths) { constraint.priority = 749; }
    }
    [NSLayoutConstraint activateConstraints:self.columnWidths];
}
@end

@interface FYWorkspaceButton ()
@property(nonatomic, strong) NSTrackingArea *hoverTracking;
@property(nonatomic) BOOL hovered;
@end
@implementation FYWorkspaceButton
- (NSSize)intrinsicContentSize {
    NSSize text = [self.title sizeWithAttributes:@{NSFontAttributeName:self.font ?: FYUIFont(12, NSFontWeightRegular)}];
    return NSMakeSize(text.width + (self.navigation ? 70 : 26), self.navigation ? 48 : 34);
}
- (void)setTitle:(NSString *)title { [super setTitle:title]; [self invalidateIntrinsicContentSize]; self.needsDisplay = YES; }
- (void)setEnabled:(BOOL)enabled { [super setEnabled:enabled]; self.needsDisplay = YES; }
- (void)setState:(NSControlStateValue)state { [super setState:state]; self.needsDisplay=YES; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas]; if(self.hoverTracking)[self removeTrackingArea:self.hoverTracking];
    self.hoverTracking=[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:self.hoverTracking];
}
- (void)mouseEntered:(NSEvent *)event {self.hovered=YES;self.needsDisplay=YES;}
- (void)mouseExited:(NSEvent *)event {self.hovered=NO;self.needsDisplay=YES;}
- (void)drawRect:(NSRect)dirtyRect {
    BOOL selected=self.state==NSControlStateValueOn, pressed=self.highlighted;
    NSColor *background=FYAdventureColor(self.primary||self.accent?@"leaf":selected?@"mint":self.navigation?@"shell":@"paper");
    if(self.hovered&&self.enabled)background=[background blendedColorWithFraction:.16 ofColor:FYAdventureColor(@"leaf")];
    if(pressed)background=[background blendedColorWithFraction:.22 ofColor:FYAdventureColor(@"orangeShade")];
    NSRect rect=NSInsetRect(self.bounds,2,2);
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:rect xRadius:NSHeight(rect)/2 yRadius:NSHeight(rect)/2];
    [[background colorWithAlphaComponent:self.enabled?1:.55] setFill];[shape fill];
    if(!self.navigation && !self.primary && !self.accent){[FYAdventureColor(@"line") setStroke];shape.lineWidth=1;[shape stroke];}
    if(self.navigation){
        if(selected){[FYAdventureColor(@"orangeShade") setFill];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2,NSMidY(rect)-12,4,24) xRadius:2 yRadius:2] fill];}
        FYDrawAdventureArt(self.artworkIndex,NSMakeRect(13,NSMidY(rect)-17,34,34));
    }
    NSDictionary *attributes=@{NSFontAttributeName:self.font ?: FYUIFont(13,NSFontWeightRegular),NSForegroundColorAttributeName:[FYAdventureColor(@"ink") colorWithAlphaComponent:self.enabled?1:.5]};
    NSSize size=[self.title sizeWithAttributes:attributes];
    [self.title drawAtPoint:NSMakePoint(self.navigation?59:(NSWidth(self.bounds)-size.width)/2,NSMidY(rect)-size.height/2-(pressed?1:0)) withAttributes:attributes];
    if(self.window.firstResponder==self){[NSGraphicsContext saveGraphicsState];NSSetFocusRingStyle(NSFocusRingOnly);[shape fill];[NSGraphicsContext restoreGraphicsState];}

}
@end

void FYConfigureSourceTextView(NSTextView *textView, NSScrollView *scrollView, CGFloat fontSize) {
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.borderType = NSNoBorder;
    scrollView.drawsBackground = NO;
    textView.frame = NSMakeRect(0, 0, 300, 100);
    textView.autoresizingMask = NSViewWidthSizable;
    textView.minSize = NSMakeSize(0, 0);
    textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;
    textView.textContainer.widthTracksTextView = YES;
    textView.textContainer.containerSize = NSMakeSize(300, CGFLOAT_MAX);
    textView.textContainerInset = NSMakeSize(0, 6);
    textView.font = FYJapaneseFont(fontSize);
    textView.textColor=FYAdventureColor(@"ink");
    textView.insertionPointColor=FYAdventureColor(@"ink");
    textView.drawsBackground = NO;
    textView.editable = NO;
    textView.selectable = YES;
    textView.richText = NO;
    textView.automaticQuoteSubstitutionEnabled = NO;
    scrollView.documentView = textView;
    textView.frame = NSMakeRect(0, 0, scrollView.contentView.bounds.size.width, 100);
}

NSAttributedStringKey const FYSourceHoverAttributeName = @"FYSourceHover";

@interface FYSourceHoverPanel : NSPanel
@end
@implementation FYSourceHoverPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface FYSelectableSourceTextView ()
@property(nonatomic, readwrite) BOOL trackingSelection;
@property(nonatomic, strong) NSTrackingArea *sourceHoverTracking;
@property(nonatomic, strong) NSTimer *sourceHoverTimer;
@property(nonatomic, strong) FYSourceHoverPanel *sourceHoverPanel;
@property(nonatomic, copy) NSString *sourceHoverText;
@property(nonatomic) NSRange sourceHoverRange;
@property(nonatomic) NSRect sourceHoverAnchor;

@end
@implementation FYSelectableSourceTextView
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_sourceHoverTimer invalidate];
    [_sourceHoverPanel orderOut:nil];
}
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self dismissSourceHover];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if(self.window){
        for(NSString *name in @[NSWindowDidResignKeyNotification,NSWindowWillCloseNotification,NSWindowDidMoveNotification,NSWindowDidResizeNotification]){
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sourceHoverGeometryChanged:) name:name object:self.window];
        }
        NSClipView *clip=self.enclosingScrollView.contentView;
        clip.postsBoundsChangedNotifications=YES;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sourceHoverGeometryChanged:) name:NSViewBoundsDidChangeNotification object:clip];
    }
}
- (void)sourceHoverGeometryChanged:(NSNotification *)note { [self dismissSourceHover]; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if(self.sourceHoverTracking){[self removeTrackingArea:self.sourceHoverTracking];}
    self.sourceHoverTracking=[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseMoved|NSTrackingMouseEnteredAndExited|NSTrackingActiveInActiveApp|NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:self.sourceHoverTracking];
}
- (void)dismissSourceHover {
    [self.sourceHoverTimer invalidate];self.sourceHoverTimer=nil;
    [self.sourceHoverPanel.parentWindow removeChildWindow:self.sourceHoverPanel];
    [self.sourceHoverPanel orderOut:nil];self.sourceHoverText=nil;
}
- (void)setEditable:(BOOL)editable {
    [self dismissSourceHover];[super setEditable:editable];
}
- (void)mouseExited:(NSEvent *)event { [self dismissSourceHover];[super mouseExited:event]; }
- (void)mouseMoved:(NSEvent *)event {
    [super mouseMoved:event];
    if(self.editable || self.trackingSelection || !self.window || !self.string.length){[self dismissSourceHover];return;}
    NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];
    point.x-=self.textContainerOrigin.x;point.y-=self.textContainerOrigin.y;
    NSLayoutManager *layout=self.layoutManager;
    [layout ensureLayoutForTextContainer:self.textContainer];
    if(!layout.numberOfGlyphs){[self dismissSourceHover];return;}
    NSUInteger glyph=[layout glyphIndexForPoint:point inTextContainer:self.textContainer];
    if(glyph>=layout.numberOfGlyphs){[self dismissSourceHover];return;}
    NSRect glyphRect=[layout boundingRectForGlyphRange:NSMakeRange(glyph,1) inTextContainer:self.textContainer];
    if(!NSPointInRect(point,glyphRect)){[self dismissSourceHover];return;}
    NSUInteger character=[layout characterIndexForGlyphAtIndex:glyph];
    NSRange range;NSString *tip=[self.textStorage attribute:FYSourceHoverAttributeName atIndex:character effectiveRange:&range];
    if(!tip.length){[self dismissSourceHover];return;}
    if([tip isEqualToString:self.sourceHoverText] && NSEqualRanges(range,self.sourceHoverRange)){return;}
    [self dismissSourceHover];self.sourceHoverText=tip;self.sourceHoverRange=range;
    glyphRect.origin.x+=self.textContainerOrigin.x;glyphRect.origin.y+=self.textContainerOrigin.y;
    self.sourceHoverAnchor=[self.window convertRectToScreen:[self convertRect:glyphRect toView:nil]];
    __weak typeof(self) weakSelf=self;
    self.sourceHoverTimer=[NSTimer scheduledTimerWithTimeInterval:0.45 repeats:NO block:^(NSTimer *timer){
        [weakSelf showSourceHoverCard];
    }];
}
- (void)showSourceHoverCard {
    NSString *tip=self.sourceHoverText;
    if(!tip.length || self.editable || self.trackingSelection || !self.window.isVisible){return;}
    NSArray<NSString *> *lines=[tip componentsSeparatedByString:@"\n"];
    NSString *title=lines.firstObject ?: @"";
    NSString *footer=lines.count>1?lines.lastObject:@"";
    NSString *body=lines.count>2?[[lines subarrayWithRange:NSMakeRange(1,lines.count-2)] componentsJoinedByString:@"\n"]:@"";
    // Hover is a brief preview; full explanations remain in the grammar detail.
    if(body.length>180){body=[[body substringToIndex:[body rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,180)].length] stringByAppendingString:@"…（完整解释见详情）"];}
    NSArray *bodyLines=[body componentsSeparatedByString:@"\n"];
    if(bodyLines.count>5){body=[[[bodyLines subarrayWithRange:NSMakeRange(0,5)] componentsJoinedByString:@"\n"] stringByAppendingString:@"…（完整解释见详情）"];}
    CGFloat width=320;
    NSDictionary *bodyAttrs=@{NSFontAttributeName:FYUIFont(14, NSFontWeightRegular),NSForegroundColorAttributeName:FYAdventureColor(@"ink")};
    CGFloat titleHeight=ceil([title boundingRectWithSize:NSMakeSize(width-32,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:FYUIFont(16, NSFontWeightSemibold)}].size.height);
    CGFloat bodyHeight=MAX(20,ceil([body boundingRectWithSize:NSMakeSize(width-32,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:bodyAttrs].size.height)+8);
    CGFloat footerHeight=ceil([footer boundingRectWithSize:NSMakeSize(width-32,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:FYUIFont(12, NSFontWeightRegular)}].size.height)+4;
    NSRect screen=self.window.screen.visibleFrame;
    CGFloat height=MIN(titleHeight+bodyHeight+footerHeight+64,MIN(360,NSHeight(screen)-24));
    bodyHeight=MAX(20,height-titleHeight-footerHeight-64);
    if(!self.sourceHoverPanel){
        self.sourceHoverPanel=[[FYSourceHoverPanel alloc] initWithContentRect:NSMakeRect(0,0,width,height) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        self.sourceHoverPanel.opaque=NO;self.sourceHoverPanel.backgroundColor=NSColor.clearColor;self.sourceHoverPanel.hasShadow=NO;
        self.sourceHoverPanel.ignoresMouseEvents=YES;self.sourceHoverPanel.hidesOnDeactivate=YES;
        self.sourceHoverPanel.releasedWhenClosed=NO;
    }
    FYAdventurePanel *card=[[FYAdventurePanel alloc] initWithFrame:NSMakeRect(0,0,width,height)];card.edgeColor=FYAdventureColor(@"ink");
    FYAdventurePanel *header=[[FYAdventurePanel alloc] initWithFrame:NSMakeRect(8,height-titleHeight-24,width-16,titleHeight+16)];header.fillColor=FYAdventureColor(@"mint");header.edgeColor=FYAdventureColor(@"mint");[card addSubview:header];
    NSTextField *heading=[NSTextField wrappingLabelWithString:title];heading.font=FYUIFont(16, NSFontWeightSemibold);heading.textColor=FYAdventureColor(@"ink");heading.frame=NSMakeRect(16,height-titleHeight-16,width-32,titleHeight);[card addSubview:heading];
    NSTextField *explanation=[NSTextField wrappingLabelWithString:body];explanation.font=bodyAttrs[NSFontAttributeName];explanation.textColor=FYAdventureColor(@"ink");explanation.frame=NSMakeRect(16,footerHeight+24,width-32,bodyHeight);[card addSubview:explanation];
    NSTextField *source=[NSTextField wrappingLabelWithString:footer];source.font=FYUIFont(12, NSFontWeightRegular);source.textColor=FYAdventureColor(@"muted");source.frame=NSMakeRect(16,12,width-32,footerHeight);[card addSubview:source];
    self.sourceHoverPanel.contentView=card;
    CGFloat x=MIN(MAX(NSMinX(self.sourceHoverAnchor)-8,NSMinX(screen)+8),NSMaxX(screen)-width-8);
    CGFloat y=NSMinY(self.sourceHoverAnchor)-height-8;
    if(y<NSMinY(screen)+8){y=NSMaxY(self.sourceHoverAnchor)+8;}
    y=MIN(MAX(y,NSMinY(screen)+8),NSMaxY(screen)-height-8);
    [self.sourceHoverPanel setFrame:NSMakeRect(x,y,width,height) display:YES];
    [self.window addChildWindow:self.sourceHoverPanel ordered:NSWindowAbove];
    [self.sourceHoverPanel orderFront:nil];
}
- (void)mouseDown:(NSEvent *)event {
    [self dismissSourceHover];
    self.trackingSelection=YES;
    if (self.willBeginSelection) { self.willBeginSelection(); }
    // In the read-only learning view, dragging is for selecting, not exporting text.
    if (!self.editable && event.clickCount==1 && !(event.modifierFlags & NSEventModifierFlagShift)) {
        self.selectedRange=NSMakeRange(self.selectedRange.location,0);
    }
    [super mouseDown:event];
    self.trackingSelection=NO;
    if (self.didFinishSelection) { self.didFinishSelection(); }
    // NSTextView consumes the tracking loop, including mouse-up, in mouseDown.
    if (event.clickCount == 1 && self.selectedRange.length == 0 && self.didClickAtCharacterIndex) {
        NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        point.x -= self.textContainerOrigin.x;
        point.y -= self.textContainerOrigin.y;
        NSLayoutManager *layout = self.layoutManager;
        if (layout.numberOfGlyphs == 0) { return; }
        NSUInteger glyph = [layout glyphIndexForPoint:point inTextContainer:self.textContainer];
        if (glyph >= layout.numberOfGlyphs) { return; }
        NSRect rect = [layout boundingRectForGlyphRange:NSMakeRange(glyph, 1) inTextContainer:self.textContainer];
        if (!NSPointInRect(point, rect)) { return; } // Whitespace must not select a nearby word.
        NSUInteger character = [layout characterIndexForGlyphAtIndex:glyph];
        if (character < self.string.length) { self.didClickAtCharacterIndex(character); }
    }
}
- (void)selectAll:(nullable id)sender {
    if (self.willBeginSelection) { self.willBeginSelection(); }
    [super selectAll:sender];
}
// 只读的可选文本视图在部分路径下 writeSelectionToPasteboard: 会直接失败，
// 表现为「Cmd+C 看起来成功、剪贴板却是空的」。这里按标准语义显式写入选区文本。
- (NSArray<NSPasteboardType> *)writablePasteboardTypes {
    return @[NSPasteboardTypeString];
}
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pasteboard types:(NSArray<NSPasteboardType> *)types {
    NSString *text = self.string ?: @"";
    NSRange range = self.selectedRange;
    if (range.length == 0 || NSMaxRange(range) > text.length) {
        return [super writeSelectionToPasteboard:pasteboard types:types];
    }
    [pasteboard declareTypes:@[NSPasteboardTypeString] owner:nil];
    return [pasteboard setString:[text substringWithRange:range] forType:NSPasteboardTypeString];
}
- (void)copy:(nullable id)sender {
    NSString *text = self.string ?: @"";
    NSRange range = self.selectedRange;
    if (range.length == 0 || NSMaxRange(range) > text.length) { return; }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[NSPasteboardTypeString] owner:nil];
    [pasteboard setString:[text substringWithRange:range] forType:NSPasteboardTypeString];
    [self dismissSourceHover];
}
- (void)keyDown:(NSEvent *)event {
    [self dismissSourceHover];
    if (event.modifierFlags & NSEventModifierFlagShift) {
        if (self.willBeginSelection) { self.willBeginSelection(); }
    }
    [super keyDown:event];
}
@end

#pragma mark - Yiya cream-and-brown theme
NSFont *FYUIFont(CGFloat size, NSFontWeight weight) {
    NSString *name=weight>=NSFontWeightSemibold?@"STYuanti-SC-Bold":@"STYuanti-SC-Regular";
    return [NSFont fontWithName:name size:size] ?: [NSFont systemFontOfSize:size weight:weight];
}
NSFont *FYJapaneseFont(CGFloat size) {
    return [NSFont fontWithName:@"HiraMaruProN-W4" size:size] ?: [NSFont fontWithName:@"HiraginoSans-W3" size:size] ?: FYUIFont(size,NSFontWeightRegular);
}
NSFont *FYFontForText(NSString *text,CGFloat size,NSFontWeight weight) {
    for(NSUInteger i=0;i<text.length;i++){unichar c=[text characterAtIndex:i];if((c>=0x3040&&c<=0x30ff)||(c>=0xff66&&c<=0xff9f))return FYJapaneseFont(size);}
    return FYUIFont(size,weight);
}
NSColor *FYAdventureColor(NSString *token) {
    static NSDictionary *palette; static dispatch_once_t once;
    dispatch_once(&once, ^{ palette = @{@"ink":@0x593E2B, @"shell":@0xF4EEE3,
        @"paper":@0xFCF9F3, @"rim":@0xDED0BB, @"mint":@0xE9EDCC,
        @"teal":@0x593E2B, @"orange":@0xCADAA6, @"orangeShade":@0xB7CB8B,
        @"cream":@0xFFF8EC, @"quiet":@0x75604E, @"reading":@0xF1E3CB,
        @"muted":@0x75604E, @"canvas":@0xF9F4EB, @"ai":@0xF8F0E7,
        @"leaf":@0xCADAA6, @"line":@0xBAA181}; });
    NSUInteger rgb = [palette[token] unsignedIntegerValue];
    return [NSColor colorWithSRGBRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];
}
NSBezierPath *FYAdventureOutline(NSRect rect, CGFloat corner) {
    CGFloat radius=MIN(MAX(12,corner),MIN(NSWidth(rect),NSHeight(rect))/2);
    return [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
}
static NSImage *FYThemeImage(NSString *name) {
    NSString *relative=[@"ui/yiya/art" stringByAppendingPathComponent:name];
    NSString *path=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:relative];
    if(![NSFileManager.defaultManager fileExistsAtPath:path])path=[@"resources" stringByAppendingPathComponent:relative];
    return [[NSImage alloc] initWithContentsOfFile:path];
}
void FYDrawAdventureArt(NSInteger artwork, NSRect destination) {
    static NSImage *atlas,*sakura;static dispatch_once_t once;
    dispatch_once(&once,^{atlas=FYThemeImage(@"ui-reference-atlas.png");atlas.size=NSMakeSize(1600,1040);sakura=FYThemeImage(@"sakura-cat-v1.png");});
    if(artwork<0||artwork>9)return;
    [NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext.imageInterpolation=NSImageInterpolationNone;
    if(artwork==8){
        CGFloat side=MIN(NSWidth(destination),NSHeight(destination));
        NSRect r=NSMakeRect(NSMidX(destination)-side/2,NSMidY(destination)-side/2,side,side);
        [sakura drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    }else{
        // Only independent decorative regions are rendered; never the reference UI or game scene.
        NSRect regions[]={{{43,140},{65,61}},{{42,220},{69,61}},{{42,294},{70,67}},{{39,400},{76,70}},{{40,486},{74,68}},{{42,565},{73,69}},{{38,7},{87,78}},{{1438,118},{147,109}},{{0,0},{0,0}},{{1382,18},{202,60}}};
        NSRect source=regions[artwork];CGFloat scale=MIN(NSWidth(destination)/NSWidth(source),NSHeight(destination)/NSHeight(source));
        NSRect target=NSMakeRect(NSMidX(destination)-NSWidth(source)*scale/2,NSMidY(destination)-NSHeight(source)*scale/2,NSWidth(source)*scale,NSHeight(source)*scale);
        source.origin.y=1040-NSMaxY(source);
        [atlas drawInRect:target fromRect:source operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    }
    [NSGraphicsContext restoreGraphicsState];
}
@implementation FYAdventurePanel
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])) { _fillColor=FYAdventureColor(@"paper");_edgeColor=FYAdventureColor(@"rim");self.wantsLayer=YES; }
    return self;
}
- (void)setFillColor:(NSColor *)color {_fillColor=color;self.needsDisplay=YES;}
- (void)setEdgeColor:(NSColor *)color {_edgeColor=color;self.needsDisplay=YES;}
- (void)drawRect:(NSRect)dirtyRect {
    NSRect rect=NSInsetRect(self.bounds,1,1);
    if(self.speechBubble)rect=NSInsetRect(rect,4,0);
    NSBezierPath *path=FYAdventureOutline(rect,9);
    [self.fillColor setFill];[path fill];[self.edgeColor setStroke];path.lineWidth=1;[path stroke];
    if(self.speechBubble){
        NSBezierPath *tail=[NSBezierPath bezierPath];CGFloat y=NSMaxY(rect)-MIN(25,NSHeight(rect)/2);
        [tail moveToPoint:NSMakePoint(NSMinX(rect)+1,y+6)];[tail lineToPoint:NSMakePoint(NSMinX(rect)-4,y)];
        [tail lineToPoint:NSMakePoint(NSMinX(rect)+1,y-6)];[tail closePath];[self.fillColor setFill];[tail fill];
    }
}
@end
@implementation FYAdventureArtView
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (BOOL)isAccessibilityElement { return NO; }
- (void)drawRect:(NSRect)dirtyRect { FYDrawAdventureArt(self.artwork,self.bounds); }
@end
@implementation FYAdventureBanner
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (BOOL)isAccessibilityElement { return NO; }
- (void)drawRect:(NSRect)dirtyRect {
    [FYAdventureColor(@"canvas") setFill];NSRectFill(self.bounds);
    CGFloat w=NSWidth(self.bounds),h=NSHeight(self.bounds);
    FYDrawAdventureArt(6,NSMakeRect(24,9,57,52));
    [@"译芽" drawAtPoint:NSMakePoint(99,19) withAttributes:@{NSFontAttributeName:FYUIFont(32,NSFontWeightBold),NSForegroundColorAttributeName:FYAdventureColor(@"ink")}];
    [@"Yiya!  |  在游戏里，读懂日语" drawAtPoint:NSMakePoint(184,25) withAttributes:@{NSFontAttributeName:FYUIFont(18,NSFontWeightSemibold),NSForegroundColorAttributeName:FYAdventureColor(@"ink")}];
    if(w>820)FYDrawAdventureArt(9,NSMakeRect(w-178,15,146,h-25));
    [FYAdventureColor(@"rim") setFill];NSRectFill(NSMakeRect(0,0,w,1));
}

@end
@implementation FYAdventureStack
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *path=FYAdventureOutline(NSInsetRect(self.bounds,1,1),9);
    [(self.fillColor ?: FYAdventureColor(@"shell")) setFill];[path fill];
    [FYAdventureColor(@"rim") setStroke];[path stroke];
}
@end
