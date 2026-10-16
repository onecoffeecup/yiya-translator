#import "FYSubtitlePresenter.h"

@interface FYSubtitlePresenter ()
@property(nonatomic, strong) NSSlider *captionFontSizeSlider;
@property(nonatomic, strong) NSSlider *captionHeightSlider;
@property(nonatomic, strong) NSSlider *captionOpacitySlider;
@property(nonatomic) BOOL captionTextColorCustomized;
@property(nonatomic, strong) NSColorWell *captionTextColorWell;
@property(nonatomic, strong) NSSegmentedControl *captionThemeControl;
@property(nonatomic, strong) NSSlider *captionWidthSlider;
@property(nonatomic) NSInteger detectedModeSegment;
@property(nonatomic, strong) NSWindow *mainWindow;
@property(nonatomic) BOOL running;
@end

@implementation FYSubtitlePresenter
- (instancetype)initWithHost:(id<FYSubtitlePresenterHost>)host {
    if ((self = [super init])) { _host = host; }
    return self;
}

// Peer adapters preserve a single source of state and injectable host boundaries.
- (NSSlider *)captionFontSizeSlider { return self.host.captionFontSizeSlider; }
- (void)setCaptionFontSizeSlider:(NSSlider *)value { self.host.captionFontSizeSlider = value; }
- (NSSlider *)captionHeightSlider { return self.host.captionHeightSlider; }
- (void)setCaptionHeightSlider:(NSSlider *)value { self.host.captionHeightSlider = value; }
- (NSSlider *)captionOpacitySlider { return self.host.captionOpacitySlider; }
- (void)setCaptionOpacitySlider:(NSSlider *)value { self.host.captionOpacitySlider = value; }
- (BOOL)captionTextColorCustomized { return self.host.captionTextColorCustomized; }
- (void)setCaptionTextColorCustomized:(BOOL)value { self.host.captionTextColorCustomized = value; }
- (NSColorWell *)captionTextColorWell { return self.host.captionTextColorWell; }
- (void)setCaptionTextColorWell:(NSColorWell *)value { self.host.captionTextColorWell = value; }
- (NSSegmentedControl *)captionThemeControl { return self.host.captionThemeControl; }
- (void)setCaptionThemeControl:(NSSegmentedControl *)value { self.host.captionThemeControl = value; }
- (NSSlider *)captionWidthSlider { return self.host.captionWidthSlider; }
- (void)setCaptionWidthSlider:(NSSlider *)value { self.host.captionWidthSlider = value; }
- (NSInteger)detectedModeSegment { return self.host.detectedModeSegment; }
- (void)setDetectedModeSegment:(NSInteger)value { self.host.detectedModeSegment = value; }
- (NSWindow *)mainWindow { return self.host.mainWindow; }
- (void)setMainWindow:(NSWindow *)value { self.host.mainWindow = value; }
- (BOOL)running { return self.host.running; }
- (void)setRunning:(BOOL)value { self.host.running = value; }

- (void)configureStudyOverlay:(NSPanel *)panel { [self.host configureStudyOverlay:panel]; }
- (NSStackView *)horizontalStack { return [self.host horizontalStack]; }
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color { return [self.host label:text font:font color:color]; }
- (NSView *)card { return [self.host card]; }
- (void)refreshOverlayVisibility:(id)sender { [self.host refreshOverlayVisibility:sender]; }
- (void)refreshInlinePanelAppearance { [self.host refreshInlinePanelAppearance]; }
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary { return [self.host workspaceButton:title action:action primary:primary]; }
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
    self.captionHideButton = [FYWorkspaceButton buttonWithTitle:@"⌄" target:self.host action:@selector(hideCaptionPanel:)];
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
    if (uiMode) { [self setCaptionDisplayText:@""]; }
    [self refreshOverlayVisibility:nil];
}

- (BOOL)captionPanelShouldBeHidden {
    return self.detectedModeSegment == ContentModeUI;
}

- (NSInteger)captionThemeIndex {
    NSInteger index = self.captionThemeControl ? self.captionThemeControl.selectedSegment : 3;
    if (index < 0 || index > 3) { index = 3; }
    return index;
}

- (NSColor *)captionBackgroundColorWithAlpha:(CGFloat)alpha {
    return FYSubtitleThemeBackground([self captionThemeIndex], MIN(alpha, .98));
}

- (NSColor *)captionThemeTextColor {
    return FYSubtitleThemeText([self captionThemeIndex]);
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
    return FYSubtitleThemeBorder([self captionThemeIndex]);
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
    [self setCaptionDisplayText:cleanText];
    [self.host updateCaptionAppearance];
}

- (void)setCaptionDisplayText:(NSString *)text {
    // AppKit keeps the shared field editor alive even after a panel is hidden.
    // Replacing its text then selects the entire new value, leaving an inactive
    // highlight on the next caption without another click. End only this
    // label's edit/selection session; native selection remains available.
    if (self.captionTextLabel.currentEditor) { [self.captionPanel endEditingFor:self.captionTextLabel]; }
    self.captionTextLabel.stringValue = text ?: @"";
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

- (void)toggleCaptionCollapsed:(id)sender {self.captionPanelShownByUser?[self hideCaptionPanel:sender]:[self showCaptionPanel:sender];}

- (void)createCaptionDock {
    self.captionDockPanel=[[FYStudyOverlayPanel alloc] initWithContentRect:NSMakeRect(0,0,260,46) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    [self configureStudyOverlay:self.captionDockPanel];
    NSStackView *row=[self horizontalStack];row.spacing=8;row.translatesAutoresizingMaskIntoConstraints=NO;
    [row addArrangedSubview:[self workspaceButton:@"⌃ 译芽" action:@selector(showCaptionPanel:) primary:NO]];
    [row addArrangedSubview:[self workspaceButton:@"查句" action:@selector(showQuickSentence:) primary:NO]];
    [row addArrangedSubview:[self workspaceButton:@"问 AI" action:@selector(showStudyChatOverlay:) primary:NO]];
    NSView *card=[self card];[card addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:10],[row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10],[row.topAnchor constraintEqualToAnchor:card.topAnchor constant:6],[row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-6]]];
    card.translatesAutoresizingMaskIntoConstraints=YES;
    card.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    card.frame=NSMakeRect(0,0,260,46);
    self.captionDockPanel.contentView=card;
}

@end
