#import "FYLearningViews.h"
#import "../FYLocalFont.h"

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
        for (NSLayoutConstraint *constraint in self.columnWidths) { constraint.priority = self.columnWidthPriority > 0 ? self.columnWidthPriority : 749; }
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
    CGFloat imageWidth = !self.navigation && self.image && self.imagePosition == NSImageLeft ? 24 : 0;
    return NSMakeSize(text.width + imageWidth + (self.navigation ? 70 : 26), self.navigation ? 48 : 34);
}
- (void)setTitle:(NSString *)title { [super setTitle:title]; [self invalidateIntrinsicContentSize]; self.needsDisplay = YES; }
- (void)setImage:(NSImage *)image { [super setImage:image]; [self invalidateIntrinsicContentSize]; self.needsDisplay = YES; }
- (void)setImagePosition:(NSCellImagePosition)position { [super setImagePosition:position]; [self invalidateIntrinsicContentSize]; self.needsDisplay = YES; }
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
    BOOL hasImage = !self.navigation && self.image && self.imagePosition == NSImageLeft;
    CGFloat textX = self.navigation ? 59 : (NSWidth(self.bounds)-size.width-(hasImage ? 24 : 0))/2;
    if (hasImage) {
        [self.image drawInRect:NSMakeRect(textX, NSMidY(rect)-8-(pressed?1:0), 16, 16)
            fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:self.enabled?1:.5 respectFlipped:YES hints:nil];
        textX += 24;
    }
    [self.title drawAtPoint:NSMakePoint(textX,NSMidY(rect)-size.height/2-(pressed?1:0)) withAttributes:attributes];
    if(self.window.firstResponder==self){[NSGraphicsContext saveGraphicsState];NSSetFocusRingStyle(NSFocusRingOnly);[shape fill];[NSGraphicsContext restoreGraphicsState];}

}
@end

static NSColor *FYSubtitleUIColor(NSUInteger rgb) {
    return [NSColor colorWithSRGBRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];
}
NSColor *FYSubtitleThemeBackground(NSInteger index, CGFloat alpha) {
    NSColor *color = FYSubtitleUIColor(index == 0 ? 0x000000 : index == 1 ? 0xFFFFFF : index == 2 ? 0xFFDBED : 0xFFF8EC);
    return [color colorWithAlphaComponent:MIN(MAX(alpha, 0), 1)];
}
NSColor *FYSubtitleThemeText(NSInteger index) {
    return FYSubtitleUIColor(index == 0 ? 0xFFFFFF : index == 1 ? 0x141414 : index == 2 ? 0x381A2E : 0x593E2B);
}
NSColor *FYSubtitleThemeBorder(NSInteger index) {
    NSUInteger rgb = index == 0 ? 0x747474 : index == 1 ? 0xADA69C : index == 2 ? 0xD39DB4 : 0xBAA181;
    return [NSColor colorWithSRGBRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:.85];
}

@implementation FYSubtitleModeButton
- (BOOL)isFlipped { return YES; }
- (NSSize)intrinsicContentSize { return NSMakeSize(120,40); }
- (void)setState:(NSControlStateValue)state { [super setState:state]; self.needsDisplay=YES; }
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,.5,.5) xRadius:8 yRadius:8];
    BOOL selected=self.state==NSControlStateValueOn;
    if(selected){[FYAdventureColor(@"paper") setFill];[shape fill];[FYSubtitleUIColor(0xD9CBB9) setStroke];[shape stroke];}
    NSDictionary *attributes=@{NSFontAttributeName:FYUIFont(14,NSFontWeightBold),NSForegroundColorAttributeName:FYAdventureColor(selected?@"ink":@"muted")};
    NSSize size=[self.title sizeWithAttributes:attributes];
    [self.title drawAtPoint:NSMakePoint((NSWidth(self.bounds)-size.width)/2,(NSHeight(self.bounds)-size.height)/2) withAttributes:attributes];
    if(self.highlighted){[[FYAdventureColor(@"ink") colorWithAlphaComponent:.06] setFill];[shape fill];}
    if(self.window.firstResponder==self){[NSGraphicsContext saveGraphicsState];NSSetFocusRingStyle(NSFocusRingOnly);[shape fill];[NSGraphicsContext restoreGraphicsState];}
}
@end
@implementation FYSubtitleDisclosureButton
- (BOOL)isFlipped { return YES; }
- (NSSize)intrinsicContentSize { return NSMakeSize(105,28); }
- (void)setState:(NSControlStateValue)state { [super setState:state];self.needsDisplay=YES; }
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *chevron=[NSBezierPath bezierPath];chevron.lineWidth=1.4;chevron.lineCapStyle=NSLineCapStyleRound;
    if(self.state==NSControlStateValueOn){[chevron moveToPoint:NSMakePoint(4,11)];[chevron lineToPoint:NSMakePoint(8,15)];[chevron lineToPoint:NSMakePoint(12,11)];}
    else {[chevron moveToPoint:NSMakePoint(5,9)];[chevron lineToPoint:NSMakePoint(9,13)];[chevron lineToPoint:NSMakePoint(5,17)];}
    [FYAdventureColor(@"ink") setStroke];[chevron stroke];
    [self.title drawAtPoint:NSMakePoint(20,4) withAttributes:@{NSFontAttributeName:FYUIFont(13,NSFontWeightRegular),NSForegroundColorAttributeName:FYAdventureColor(@"ink")}];
    if(self.window.firstResponder==self){[NSGraphicsContext saveGraphicsState];NSSetFocusRingStyle(NSFocusRingOnly);NSRectFill(self.bounds);[NSGraphicsContext restoreGraphicsState];}
}
@end
@implementation FYSubtitleSliderCell
- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped {
    NSRect track=NSMakeRect(NSMinX(rect),NSMidY(rect)-3.5,NSWidth(rect),7);
    [FYSubtitleUIColor(0x3B3B3B) setFill];[[NSBezierPath bezierPathWithRoundedRect:track xRadius:3.5 yRadius:3.5] fill];
    CGFloat fraction=(self.doubleValue-self.minValue)/MAX(.001,self.maxValue-self.minValue);
    track.size.width*=MIN(1,MAX(0,fraction));[FYSubtitleUIColor(0x8B9C62) setFill];[[NSBezierPath bezierPathWithRoundedRect:track xRadius:3.5 yRadius:3.5] fill];
}
- (void)drawKnob:(NSRect)rect {
    NSRect knob=NSMakeRect(NSMidX(rect)-7,NSMidY(rect)-7,14,14);
    [FYSubtitleUIColor(0x8B9C62) setFill];[[NSBezierPath bezierPathWithOvalInRect:knob] fill];
}
@end
@implementation FYSubtitleColorWell
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0,0,0,0); }
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *outline=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,.5,.5) xRadius:7 yRadius:7];
    [FYAdventureColor(@"paper") setFill];[outline fill];[FYSubtitleUIColor(0xBAA181) setStroke];[outline stroke];
    [self.color setFill];[[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,4,4) xRadius:3 yRadius:3] fill];
    if(self.window.firstResponder==self){[NSGraphicsContext saveGraphicsState];NSSetFocusRingStyle(NSFocusRingOnly);[outline fill];[NSGraphicsContext restoreGraphicsState];}
}
@end
@implementation FYSubtitleFollowButton
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0,0,0,0); }
@end

@implementation FYSubtitleStyleButton
- (BOOL)isFlipped { return YES; }
- (NSSize)intrinsicContentSize { return NSMakeSize(110, 92); }
- (void)setState:(NSControlStateValue)state { [super setState:state]; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)dirtyRect {
    BOOL selected = self.state == NSControlStateValueOn;
    NSRect frame = NSInsetRect(self.bounds, 2, 2);
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:frame xRadius:12 yRadius:12];
    [(selected ? FYSubtitleUIColor(0xF5F6EB) : FYAdventureColor(@"paper")) setFill]; [outline fill];
    [FYSubtitleUIColor(selected ? 0x82935A : 0xDED7CD) setStroke]; outline.lineWidth = selected ? 2 : 1; [outline stroke];
    NSRect sample = NSMakeRect(10, 10, MAX(1, NSWidth(self.bounds)-20), 49);
    [FYSubtitleThemeBackground(self.themeIndex, 1) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:sample xRadius:7 yRadius:7] fill];
    NSDictionary *attributes = @{NSFontAttributeName:FYUIFont(15, NSFontWeightRegular), NSForegroundColorAttributeName:FYSubtitleThemeText(self.themeIndex)};
    NSSize size = [@"读懂这一句" sizeWithAttributes:attributes];
    [@"读懂这一句" drawAtPoint:NSMakePoint(NSMidX(sample)-size.width/2, NSMidY(sample)-size.height/2) withAttributes:attributes];
    [self.title drawInRect:NSMakeRect(10, 66, MAX(1, NSWidth(self.bounds)-34), 20) withAttributes:@{NSFontAttributeName:FYUIFont(12, NSFontWeightRegular),NSForegroundColorAttributeName:FYAdventureColor(@"ink")}];
    if (selected) {
        NSRect mark = NSMakeRect(NSWidth(self.bounds)-25, 67, 16, 16);
        [FYSubtitleUIColor(0x667840) setFill]; [[NSBezierPath bezierPathWithOvalInRect:mark] fill];
        NSBezierPath *check = [NSBezierPath bezierPath]; check.lineWidth = 1.5;
        [check moveToPoint:NSMakePoint(NSMinX(mark)+3, NSMinY(mark)+8)];
        [check lineToPoint:NSMakePoint(NSMinX(mark)+6, NSMinY(mark)+11)];
        [check lineToPoint:NSMakePoint(NSMinX(mark)+12, NSMinY(mark)+4)];
        [NSColor.whiteColor setStroke]; [check stroke];
    }
    if (self.highlighted) { [[FYAdventureColor(@"ink") colorWithAlphaComponent:.06] setFill]; [outline fill]; }
    if (self.window.firstResponder == self) { [NSGraphicsContext saveGraphicsState]; NSSetFocusRingStyle(NSFocusRingOnly); [outline fill]; [NSGraphicsContext restoreGraphicsState]; }
}
@end

// These sample surfaces mirror the approved HTML's scene/source/card hierarchy.
// They contain native selectable text and never enter the OCR or translation pipeline.
@interface FYSubtitleSampleSurface : FYAdventurePanel
@end
@implementation FYSubtitleSampleSurface
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,.5,.5) xRadius:8 yRadius:8];
    [self.fillColor setFill];[shape fill];[self.edgeColor setStroke];[shape stroke];
}
@end
@interface FYSubtitleAppearancePreview ()
@property(nonatomic, strong) NSTextField *sceneLabel;
@property(nonatomic, strong) NSTextField *sampleFlag;
@property(nonatomic, strong) FYSubtitleSampleSurface *sampleFlagSurface;
@property(nonatomic, strong) NSTextField *sourceLabel;
@property(nonatomic, strong) NSTextField *noteLabel;
@property(nonatomic, strong) NSTextField *brandLabel;
@property(nonatomic, strong) NSTextField *translationLabel;
@property(nonatomic, strong) NSScrollView *translationScroll;
@property(nonatomic, copy) NSArray<NSTextField *> *shortLabels;
@property(nonatomic, copy) NSArray<FYAdventurePanel *> *sourcePanels;
@property(nonatomic, copy) NSArray<FYAdventurePanel *> *translationSurfaces;
@end
@implementation FYSubtitleAppearancePreview
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.fillColor=FYSubtitleUIColor(0xDBE4D3);self.edgeColor=FYSubtitleUIColor(0xB7C3AD);
        _subtitleFill=FYSubtitleThemeBackground(3,.58);_subtitleInk=FYSubtitleThemeText(3);_subtitleBorder=FYSubtitleThemeBorder(3);
        _subtitleSize=16;_subtitleWidth=560;_subtitleHeight=330;
        self.sceneLabel=[self sampleLabel:@"" japanese:YES];[self addSubview:self.sceneLabel];
        self.sampleFlagSurface=[FYSubtitleSampleSurface new];self.sampleFlagSurface.fillColor=[FYSubtitleUIColor(0xFAFCF6) colorWithAlphaComponent:.84];self.sampleFlagSurface.edgeColor=NSColor.clearColor;
        self.sampleFlag=[self sampleLabel:@"示例画面" japanese:NO];self.sampleFlag.font=FYUIFont(11,NSFontWeightRegular);self.sampleFlag.textColor=FYSubtitleUIColor(0x4D5D45);
        [self.sampleFlagSurface addSubview:self.sampleFlag];[self addSubview:self.sampleFlagSurface];
        NSMutableArray *sources=[NSMutableArray array];
        for(NSUInteger i=0;i<2;i++){
            FYSubtitleSampleSurface *panel=[FYSubtitleSampleSurface new];panel.fillColor=[FYSubtitleUIColor(0xFCFCF7) colorWithAlphaComponent:.56];panel.edgeColor=[FYSubtitleUIColor(0x839774) colorWithAlphaComponent:.4];
            [self addSubview:panel];[sources addObject:panel];
        }
        self.sourcePanels=sources;
        self.sourceLabel=[self sampleLabel:@"" japanese:YES];[sources[0] addSubview:self.sourceLabel];
        self.noteLabel=[self sampleLabel:@"今日のメモ" japanese:YES];self.noteLabel.font=FYJapaneseFont(11);self.noteLabel.textColor=FYSubtitleUIColor(0x64715C);[sources[1] addSubview:self.noteLabel];
        NSMutableArray *surfaces=[NSMutableArray array];
        for(NSUInteger i=0;i<3;i++){FYSubtitleSampleSurface *panel=[FYSubtitleSampleSurface new];[surfaces addObject:panel];}
        self.translationSurfaces=surfaces;
        self.translationLabel=[self sampleLabel:@"放学后去图书馆吧。\n上次借的书，也该还了。" japanese:NO];
        self.translationScroll=[NSScrollView new];self.translationScroll.drawsBackground=NO;self.translationScroll.hasVerticalScroller=YES;self.translationScroll.autohidesScrollers=YES;
        self.translationScroll.scrollerStyle=NSScrollerStyleOverlay;self.translationScroll.documentView=self.translationLabel;[surfaces.lastObject addSubview:self.translationScroll];
        self.brandLabel=[self sampleLabel:@"译芽 · 当前译文" japanese:NO];[surfaces.lastObject addSubview:self.brandLabel];
        self.shortLabels=@[[self sampleLabel:@"回家" japanese:NO],[self sampleLabel:@"去图书馆" japanese:NO]];
        for(NSUInteger i=0;i<2;i++){[surfaces[i] addSubview:self.shortLabels[i]];[sources[0] addSubview:surfaces[i]];}
        [self refreshSample];
    }
    return self;
}
- (NSTextField *)sampleLabel:(NSString *)text japanese:(BOOL)japanese {
    NSTextField *label=[NSTextField wrappingLabelWithString:text];label.font=japanese?FYJapaneseFont(13):FYUIFont(13,NSFontWeightRegular);
    label.textColor=FYAdventureColor(@"ink");label.selectable=YES;label.maximumNumberOfLines=0;label.lineBreakMode=NSLineBreakByCharWrapping;return label;
}
- (void)setFrameSize:(NSSize)size {
    BOOL changed=fabs(NSWidth(self.frame)-size.width)>1;[super setFrameSize:size];
    if(changed)[self invalidateIntrinsicContentSize];self.needsLayout=YES;
}
- (CGFloat)previewCardFraction {
    CGFloat minimum=self.inlineMode?240:360,maximum=self.inlineMode?720:1200;
    return .6+MIN(1,MAX(0,(self.subtitleWidth-minimum)/(maximum-minimum)))*.4;
}
- (CGFloat)bodyWidthForWidth:(CGFloat)width {
    CGFloat inner=MAX(1,width-34);
    if(self.inlineMode)inner=MAX(1,(inner-12)*1.2/2.2-24);
    return MAX(1,inner*[self previewCardFraction]);
}
- (CGFloat)textHeight:(NSTextField *)label width:(CGFloat)width {
    return ceil([label.cell cellSizeForBounds:NSMakeRect(0,0,MAX(1,width),CGFLOAT_MAX)].height);
}
- (CGFloat)bodyHeightForWidth:(CGFloat)width {
    CGFloat padding=self.inlineMode?11:15;
    CGFloat textHeight=[self textHeight:self.translationLabel width:[self bodyWidthForWidth:width]-padding*2];
    CGFloat natural=textHeight+(self.inlineMode?20:50);
    return self.inlineMode?MIN(natural,MAX(60,self.subtitleHeight*.46)):MAX(natural,self.subtitleHeight*.46);
}
- (CGFloat)shortHeight:(NSTextField *)label { return ceil(label.cell.cellSize.height)+12; }
- (CGFloat)inlineSourceHeightForWidth:(CGFloat)width {
    CGFloat shortHeight=[self shortHeight:self.shortLabels[0]]+[self shortHeight:self.shortLabels[1]]+10;
    return MAX(38+shortHeight+12,40+[self bodyHeightForWidth:width]+12);
}
- (NSSize)intrinsicContentSize {
    CGFloat width=NSWidth(self.bounds)>0?NSWidth(self.bounds):380;
    CGFloat height=self.inlineMode?65+[self inlineSourceHeightForWidth:width]+17:
        67+[self textHeight:self.sourceLabel width:width-60]+24+25+[self bodyHeightForWidth:width]+17;
    return NSMakeSize(NSViewNoIntrinsicMetric,MAX(self.inlineMode?275:294,height));
}
- (void)refreshSample {
    self.fillColor=FYSubtitleUIColor(0xDBE4D3);
    BOOL heightExample=self.inlineMode && self.showsHeightLimitExample;
    self.sampleFlag.stringValue=heightExample?@"长文示例":@"示例画面";
    // A maximum cannot be demonstrated with text shorter than its smallest limit.
    // Keep the approved two-sentence scene unless the user opens size settings.
    self.translationLabel.stringValue=heightExample?
        @"放学后去图书馆吧。\n上次借的书，也该还了。\n先把书放进书包里，\n再检查一下借书卡。\n如果图书馆还没关门，\n我们就去看看新书。\n你可以挑一本小说，\n我想找找旅行的书。\n读到喜欢的段落时，\n记得把页码记下来。\n等到夕阳照进窗边，\n我们再一起回家吧。":
        @"放学后去图书馆吧。\n上次借的书，也该还了。";
    self.sceneLabel.stringValue=self.inlineMode?@"春 · 4月10日":@"放課後 · 図書室";self.sceneLabel.font=FYJapaneseFont(12);self.sceneLabel.textColor=FYSubtitleUIColor(0x465844);
    self.sourceLabel.stringValue=self.inlineMode?@"放課後の予定":@"放課後、図書館に寄って帰ろう。\n前に借りた本も、そろそろ返さないとね。";
    self.sourceLabel.font=FYJapaneseFont(self.inlineMode?11:13);self.sourceLabel.textColor=FYSubtitleUIColor(self.inlineMode?0x64715C:0x40533E);
    NSMutableParagraphStyle *sourceStyle=[NSMutableParagraphStyle new];sourceStyle.minimumLineHeight=sourceStyle.maximumLineHeight=self.inlineMode?16.5:22.1;
    self.sourceLabel.attributedStringValue=[[NSAttributedString alloc] initWithString:self.sourceLabel.stringValue attributes:@{NSFontAttributeName:self.sourceLabel.font,NSForegroundColorAttributeName:self.sourceLabel.textColor,NSParagraphStyleAttributeName:sourceStyle}];
    self.sourcePanels[1].hidden=!self.inlineMode;self.noteLabel.hidden=!self.inlineMode;
    self.brandLabel.hidden=self.inlineMode;self.brandLabel.font=FYUIFont(11,NSFontWeightRegular);self.brandLabel.textColor=[self.subtitleInk colorWithAlphaComponent:.78];
    // The agreed demo is scaled to fit the sample, independently of real game font measurement.
    CGFloat size=self.inlineMode?self.subtitleSize:MAX(18,self.subtitleSize*.72);
    NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new];paragraph.minimumLineHeight=size*1.55;paragraph.maximumLineHeight=size*1.55;
    self.translationLabel.attributedStringValue=[[NSAttributedString alloc] initWithString:self.translationLabel.stringValue attributes:@{NSFontAttributeName:FYUIFont(size,NSFontWeightRegular),NSForegroundColorAttributeName:self.subtitleInk,NSParagraphStyleAttributeName:paragraph}];
    self.translationLabel.font=FYUIFont(size,NSFontWeightRegular);self.translationLabel.textColor=self.subtitleInk;
    for(NSUInteger i=0;i<3;i++){FYAdventurePanel *surface=self.translationSurfaces[i];surface.fillColor=self.subtitleFill;surface.edgeColor=self.subtitleBorder;surface.hidden=!self.inlineMode&&i<2;}
    for(NSTextField *label in self.shortLabels){
        NSMutableParagraphStyle *shortStyle=[NSMutableParagraphStyle new];shortStyle.minimumLineHeight=self.subtitleSize*1.55;shortStyle.maximumLineHeight=self.subtitleSize*1.55;
        label.attributedStringValue=[[NSAttributedString alloc] initWithString:label.stringValue attributes:@{NSFontAttributeName:FYUIFont(self.subtitleSize,NSFontWeightRegular),NSForegroundColorAttributeName:self.subtitleInk,NSParagraphStyleAttributeName:shortStyle}];
        label.font=FYUIFont(self.subtitleSize,NSFontWeightRegular);label.textColor=self.subtitleInk;
    }
    NSView *bodyParent=self.inlineMode?self.sourcePanels[1]:self;
    if(self.translationSurfaces.lastObject.superview!=bodyParent){[self.translationSurfaces.lastObject removeFromSuperview];[bodyParent addSubview:self.translationSurfaces.lastObject];}
    [self invalidateIntrinsicContentSize];self.needsLayout=YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    if(!self.inlineMode){
        NSGradient *gradient=[[NSGradient alloc] initWithColorsAndLocations:FYSubtitleUIColor(0xCFDFD0),0.0,FYSubtitleUIColor(0xE7E7D4),.45,FYSubtitleUIColor(0xD4D7CB),1.0,nil];
        [gradient drawInBezierPath:[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:12 yRadius:12] angle:145];
    }
    [[FYSubtitleUIColor(0x4E6244) colorWithAlphaComponent:.22] setStroke];
    NSBezierPath *rule=[NSBezierPath bezierPath];[rule moveToPoint:NSMakePoint(17,49)];[rule lineToPoint:NSMakePoint(NSWidth(self.bounds)-17,49)];[rule stroke];
}
- (void)layout {
    [super layout];CGFloat width=NSWidth(self.bounds),inner=MAX(1,width-34);
    self.sceneLabel.frame=NSMakeRect(17,17,MAX(1,inner-90),20);
    self.sampleFlagSurface.frame=NSMakeRect(width-77,17,60,20);self.sampleFlag.frame=NSMakeRect(6,2,48,16);
    CGFloat bodyWidth=[self bodyWidthForWidth:width],bodyHeight=[self bodyHeightForWidth:width];FYAdventurePanel *body=self.translationSurfaces.lastObject;
    if(self.inlineMode){
        CGFloat left=(inner-12)/2.2,right=(inner-12)*1.2/2.2,sourceHeight=[self inlineSourceHeightForWidth:width];
        self.sourcePanels[0].frame=NSMakeRect(17,65,left,sourceHeight);self.sourcePanels[1].frame=NSMakeRect(17+left+12,65,right,sourceHeight);
        self.sourceLabel.frame=NSMakeRect(12,12,MAX(1,left-24),17);self.noteLabel.frame=NSMakeRect(12,12,MAX(1,right-24),17);
        CGFloat y=38;
        for(NSUInteger i=0;i<2;i++){
            NSTextField *label=self.shortLabels[i];CGFloat shortWidth=MIN(left-24,ceil(label.cell.cellSize.width)+22),height=[self shortHeight:label];
            self.translationSurfaces[i].frame=NSMakeRect(12,y,shortWidth,height);label.frame=NSMakeRect(10,5,MAX(1,shortWidth-20),height-10);y+=height+10;
        }
        body.frame=NSMakeRect(12,40,bodyWidth,bodyHeight);
    }else{
        CGFloat sourceHeight=[self textHeight:self.sourceLabel width:inner-24]+24;
        self.sourcePanels[0].frame=NSMakeRect(17,67,inner,sourceHeight);self.sourceLabel.frame=NSMakeRect(12,12,inner-24,sourceHeight-24);
        body.frame=NSMakeRect((width-bodyWidth)/2,67+sourceHeight+25,bodyWidth,bodyHeight);
    }
    CGFloat padding=self.inlineMode?11:15,top=self.inlineMode?9:36;
    self.brandLabel.frame=NSMakeRect(15,12,MAX(1,bodyWidth-30),17);
    self.translationScroll.frame=NSMakeRect(padding,top,MAX(1,bodyWidth-padding*2),MAX(1,bodyHeight-top-(self.inlineMode?9:12)));
    CGFloat textWidth=NSWidth(self.translationScroll.contentView.bounds);
    self.translationLabel.frame=NSMakeRect(0,0,textWidth,MAX(NSHeight(self.translationScroll.contentView.bounds),[self textHeight:self.translationLabel width:textWidth]));
    CGFloat topOrigin=self.translationLabel.isFlipped?0:MAX(0,NSHeight(self.translationLabel.frame)-NSHeight(self.translationScroll.contentView.bounds));
    [self.translationScroll.contentView scrollToPoint:NSMakePoint(0,topOrigin)];
}
@end

NSImage *FYAdventureSymbolImage(NSString *symbol, NSColor *color) {
    return [NSImage imageWithSize:NSMakeSize(20,20) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [color setStroke];
        NSBezierPath *path = [NSBezierPath bezierPath];
        path.lineWidth = 1.7; path.lineCapStyle = NSLineCapStyleRound; path.lineJoinStyle = NSLineJoinStyleRound;
        if ([symbol isEqualToString:@"play"]) {
            [path moveToPoint:NSMakePoint(6,4)]; [path lineToPoint:NSMakePoint(16,10)];
            [path lineToPoint:NSMakePoint(6,16)]; [path closePath];
        } else if ([symbol isEqualToString:@"model"]) {
            [path moveToPoint:NSMakePoint(5,7)]; [path lineToPoint:NSMakePoint(10,4)];
            [path lineToPoint:NSMakePoint(15,7)]; [path lineToPoint:NSMakePoint(15,13)];
            [path lineToPoint:NSMakePoint(10,16)]; [path lineToPoint:NSMakePoint(5,13)]; [path closePath];
            [path moveToPoint:NSMakePoint(5,13)]; [path lineToPoint:NSMakePoint(10,10)];
            [path lineToPoint:NSMakePoint(15,13)]; [path moveToPoint:NSMakePoint(10,10)]; [path lineToPoint:NSMakePoint(10,4)];
        } else {
            [path appendBezierPathWithOvalInRect:NSMakeRect(2,2,16,16)];
            if ([symbol isEqualToString:@"success"]) {
                [path moveToPoint:NSMakePoint(6,10)]; [path lineToPoint:NSMakePoint(9,7)]; [path lineToPoint:NSMakePoint(14,13)];
            } else if ([symbol isEqualToString:@"error"]) {
                [path moveToPoint:NSMakePoint(10,13)]; [path lineToPoint:NSMakePoint(10,9)];
                [path moveToPoint:NSMakePoint(10,6)]; [path lineToPoint:NSMakePoint(10,6.2)];
            } else if ([symbol isEqualToString:@"pending"]) {
                [path moveToPoint:NSMakePoint(10,14)]; [path lineToPoint:NSMakePoint(10,10)]; [path lineToPoint:NSMakePoint(13,8)];
            }
        }
        [path stroke]; return YES;
    }];
}

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
        // A source block may live in the quick-sentence reading document rather
        // than its own scroll view. Any enclosing scroll must dismiss the card.
        for(NSView *ancestor=self.superview;ancestor;ancestor=ancestor.superview){
            if(![ancestor isKindOfClass:NSScrollView.class]){continue;}
            NSClipView *clip=((NSScrollView *)ancestor).contentView;
            clip.postsBoundsChangedNotifications=YES;
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sourceHoverGeometryChanged:) name:NSViewBoundsDidChangeNotification object:clip];
        }
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

#pragma mark - Naturally sized source reading
@implementation FYSourceReadingView
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])){
        _textView=[[FYSelectableSourceTextView alloc] initWithFrame:self.bounds];
        _textView.editable=NO;_textView.selectable=YES;_textView.richText=NO;
        _textView.drawsBackground=NO;_textView.verticallyResizable=NO;_textView.horizontallyResizable=NO;
        _textView.textContainerInset=NSZeroSize;_textView.textContainer.lineFragmentPadding=0;
        _textView.textContainer.widthTracksTextView=YES;
        _textView.textContainer.containerSize=NSMakeSize(MAX(1,NSWidth(frame)),CGFLOAT_MAX);
        _textView.automaticQuoteSubstitutionEnabled=NO;
        [self addSubview:_textView];
        [self setContentHuggingPriority:999 forOrientation:NSLayoutConstraintOrientationVertical];
        [self setContentCompressionResistancePriority:999 forOrientation:NSLayoutConstraintOrientationVertical];
    }
    return self;
}
- (void)setFrameSize:(NSSize)size {
    CGFloat previousWidth=NSWidth(self.bounds);[super setFrameSize:size];
    self.textView.frame=self.bounds;
    if(fabs(previousWidth-size.width)>.1){[self invalidateIntrinsicContentSize];}
}
- (NSSize)intrinsicContentSize {
    CGFloat width=MAX(1,NSWidth(self.bounds));
    self.textView.textContainer.containerSize=NSMakeSize(width,CGFLOAT_MAX);
    [self.textView.layoutManager ensureLayoutForTextContainer:self.textView.textContainer];
    CGFloat height=ceil(NSHeight([self.textView.layoutManager usedRectForTextContainer:self.textView.textContainer]))+2;
    return NSMakeSize(NSViewNoIntrinsicMetric,MAX(26,height));
}
- (void)layout {
    [super layout];self.textView.frame=self.bounds;
}
@end

#pragma mark - Yiya cream-and-brown theme
NSFont *FYUIFont(CGFloat size, NSFontWeight weight) {
    NSString *name=weight>=NSFontWeightSemibold?@"STYuanti-SC-Bold":@"STYuanti-SC-Regular";
    return FYLocalFontNamed(name, size) ?: [NSFont systemFontOfSize:size weight:weight];
}
NSFont *FYJapaneseFont(CGFloat size) {
    return FYLocalFontNamed(@"HiraMaruProN-W4", size) ?: FYLocalFontNamed(@"HiraginoSans-W3", size) ?: FYUIFont(size,NSFontWeightRegular);
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
        @"leaf":@0xCADAA6, @"line":@0xBAA181,
        @"serviceSuccess":@0x48613B, @"serviceSuccessSoft":@0xF0F3E4,
        @"serviceError":@0x9C453E, @"serviceErrorSoft":@0xF8EAE4}; });
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
