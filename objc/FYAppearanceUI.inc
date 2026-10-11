// Concentrated subtitle settings: independent palettes and sample-only previews.
- (NSView *)makeAppearancePage {
    self.appearanceValueLabels = [NSMapTable strongToStrongObjectsMapTable];
    self.appearanceSamples = @[]; self.appearanceColorStateLabels = @[]; self.appearanceThemeLabels = @[];
    NSStackView *page = [self verticalStack]; page.spacing = 22;
    self.appearanceModeControl = [self segmentedWithLabels:@[@"长对白字幕", @"界面贴译"] action:@selector(selectAppearanceMode:)];
    self.appearanceModeControl.selectedSegment = 1;
    self.appearanceModeControl.accessibilityLabel = @"设置的字幕类型";
    FYAdventurePanel *tabSurface = [FYAdventurePanel new]; tabSurface.fillColor = FYAppearanceColorFromHex(@"#EEE7DC",self.uiMuted);
    tabSurface.edgeColor = FYAppearanceColorFromHex(@"#DED7CD",self.uiBorder);
    [tabSurface.widthAnchor constraintEqualToConstant:252].active=YES;[tabSurface.heightAnchor constraintEqualToConstant:50].active=YES;
    NSMutableArray *modeButtons=[NSMutableArray array];
    for(NSInteger i=0;i<2;i++){
        FYSubtitleModeButton *button=[FYSubtitleModeButton buttonWithTitle:i==0?@"长对白字幕":@"界面贴译" target:self action:@selector(selectAppearanceMode:)];
        button.tag=i;button.bordered=NO;[button setButtonType:NSButtonTypePushOnPushOff];button.frame=NSMakeRect(4+i*124,5,120,40);
        [tabSurface addSubview:button];[modeButtons addObject:button];
    }
    self.appearanceModeButtons=modeButtons;
    NSStackView *tabs = [self horizontalStack];
    [tabs addArrangedSubview:tabSurface]; [tabs addArrangedSubview:[self spacer]];
    [page addArrangedSubview:tabs];
    self.captionOpacitySlider = [self sliderWithMin:0 max:.95 value:.58 action:@selector(controlValueChanged:)];
    [self styleAppearanceSlider:self.captionOpacitySlider];
    self.captionOpacitySlider.accessibilityLabel = @"背景不透明度";
    NSStackView *common=[self horizontalStack];common.spacing=20;
    NSStackView *opacityLabels=[self verticalStack];opacityLabels.spacing=2;
    [opacityLabels addArrangedSubview:[self label:@"背景不透明度" font:FYUIFont(14,NSFontWeightRegular) color:self.uiInk]];
    [opacityLabels addArrangedSubview:[self mutedLabel:@"长对白与贴译共用"]];[opacityLabels.widthAnchor constraintEqualToConstant:150].active=YES;
    [common addArrangedSubview:opacityLabels];[common addArrangedSubview:self.captionOpacitySlider];
    [self.captionOpacitySlider.widthAnchor constraintLessThanOrEqualToConstant:260].active=YES;
    [self.captionOpacitySlider.widthAnchor constraintGreaterThanOrEqualToConstant:60].active=YES;
    // 260 pt is preferred; narrow windows may shorten the slider to its 60 pt
    // minimum instead of making the outer window grow to fit this row.
    NSLayoutConstraint *opacityWidth=[self.captionOpacitySlider.widthAnchor constraintEqualToConstant:260];opacityWidth.priority=NSLayoutPriorityDefaultLow;opacityWidth.active=YES;
    NSTextField *opacityValue=[self label:@"58%" font:FYUIFont(14,NSFontWeightRegular) color:self.uiInk];
    [opacityValue.widthAnchor constraintEqualToConstant:44].active=YES;[self.appearanceValueLabels setObject:opacityValue forKey:self.captionOpacitySlider];
    [common addArrangedSubview:opacityValue];[common addArrangedSubview:[self spacer]];
    NSView *opacityCard=[self cardWithStack:common];opacityCard.identifier=@"appearance-opacity-row";
    ((FYAdventurePanel *)opacityCard).edgeColor=FYAppearanceColorFromHex(@"#DED7CD",self.uiBorder);[page addArrangedSubview:opacityCard];
    self.appearanceEditors = @[[self captionCard], [self batchCaptionCard]];
    for (NSView *editor in self.appearanceEditors) { [page addArrangedSubview:editor]; }
    [page addArrangedSubview:[self mutedLabel:@"配色和字号分别设置 · 字体沿用圆体"]];
    [self updateSubtitleAppearancePage];
    return page;
}

- (void)styleAppearanceSlider:(NSSlider *)slider {
    double minimum=slider.minValue,maximum=slider.maxValue,value=slider.doubleValue;id target=slider.target;SEL action=slider.action;
    slider.cell=[FYSubtitleSliderCell new];slider.minValue=minimum;slider.maxValue=maximum;slider.doubleValue=value;slider.target=target;slider.action=action;slider.continuous=YES;
    [slider.heightAnchor constraintEqualToConstant:22].active=YES;
}

- (NSView *)appearanceSliderRow:(NSString *)title slider:(NSSlider *)slider {
    [self styleAppearanceSlider:slider];
    NSStackView *field = [self verticalStack]; field.spacing = 7;
    NSStackView *heading = [self horizontalStack];
    [heading addArrangedSubview:[self label:title font:FYUIFont(13,NSFontWeightRegular) color:self.uiInk]]; [heading addArrangedSubview:[self spacer]];
    NSTextField *value = [self label:@"" font:FYUIFont(13,NSFontWeightRegular) color:self.uiInk]; [heading addArrangedSubview:value];
    [self.appearanceValueLabels setObject:value forKey:slider];
    slider.accessibilityLabel = title;
    [field addArrangedSubview:heading]; [field addArrangedSubview:slider];
    return field;
}

- (NSView *)subtitleAppearanceEditor:(BOOL)inlineMode {
    NSStackView *editor = [self verticalStack]; editor.spacing = 13;
    editor.identifier = inlineMode ? @"appearance-inline-editor" : @"appearance-dialogue-editor";
    NSStackView *sectionHeading=[self horizontalStack];sectionHeading.spacing=12;
    [sectionHeading addArrangedSubview:[self label:inlineMode ? @"界面贴译" : @"长对白字幕" font:FYUIFont(18,NSFontWeightBold) color:self.uiInk]];
    [sectionHeading addArrangedSubview:[self mutedLabel:inlineMode ? @"短贴片与长卡共用配色" : @"单条悬浮译文"]];[sectionHeading addArrangedSubview:[self spacer]];
    [editor addArrangedSubview:sectionHeading];
    NSArray *names = @[@"黑底白字", @"白底黑字", @"粉底深字", @"译芽花境"];
    FYLearningColumnsView *palettes = [FYLearningColumnsView new];
    palettes.spacing = 10; palettes.leftFraction = .5; palettes.compactWidth = 560;
    palettes.identifier = inlineMode ? @"appearance-inline-palettes" : @"appearance-dialogue-palettes";
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSInteger pair=0; pair<2; pair++) {
        NSStackView *row = [NSStackView new]; row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.distribution = NSStackViewDistributionFillEqually; row.spacing = 10;
        for (NSInteger slot=0; slot<2; slot++) {
            NSInteger index=pair*2+slot;
            FYSubtitleStyleButton *button = [FYSubtitleStyleButton buttonWithTitle:names[index] target:self
                action:inlineMode ? @selector(selectBatchSwatch:) : @selector(selectCaptionSwatch:)];
            button.bordered = NO; button.font = FYUIFont(12, NSFontWeightRegular);
            [button setButtonType:NSButtonTypePushOnPushOff];
            button.tag = index; button.themeIndex = index; button.accessibilityLabel = names[index];
            [button.heightAnchor constraintEqualToConstant:92].active = YES;
            [row addArrangedSubview:button]; [buttons addObject:button];
        }
        [palettes addArrangedSubview:row];
    }
    if (inlineMode) { self.batchThemeSwatches = buttons; } else { self.themeSwatches = buttons; }
    [editor addArrangedSubview:palettes];

    NSStackView *controls = [self verticalStack]; controls.spacing = 16;
    [controls addArrangedSubview:[self appearanceSliderRow:@"译文字号" slider:inlineMode ? self.batchFontSizeSlider : self.captionFontSizeSlider]];
    NSStackView *color = [self verticalStack]; color.spacing = 6;
    NSStackView *colorHeading = [self horizontalStack];
    [colorHeading addArrangedSubview:[self label:@"译文字色" font:FYUIFont(13,NSFontWeightRegular) color:self.uiInk]]; [colorHeading addArrangedSubview:[self spacer]];
    NSTextField *colorState = [self mutedLabel:@"跟随样式"]; [colorHeading addArrangedSubview:colorState];
    self.appearanceColorStateLabels = [self.appearanceColorStateLabels arrayByAddingObject:colorState];
    [color addArrangedSubview:colorHeading];
    NSStackView *colorRow = [self horizontalStack];colorRow.spacing=8;
    NSColorWell *well = inlineMode ? self.batchTextColorWell : self.captionTextColorWell;
    well.accessibilityLabel = inlineMode ? @"贴译自定义字色" : @"长对白自定义字色";
    [colorRow addArrangedSubview:well];
    FYSubtitleFollowButton *follow=[FYSubtitleFollowButton buttonWithTitle:@"跟随样式" target:self action:inlineMode ? @selector(resetBatchTextColor:) : @selector(resetCaptionTextColor:)];
    follow.bordered=NO;follow.font=FYUIFont(12,NSFontWeightRegular);
    [follow.widthAnchor constraintEqualToConstant:70].active=YES;[follow.heightAnchor constraintEqualToConstant:32].active=YES;
    [colorRow addArrangedSubview:follow];[colorRow addArrangedSubview:[self spacer]];
    [color addArrangedSubview:colorRow]; [controls addArrangedSubview:color];
    NSStackView *dimensions = [self verticalStack]; dimensions.spacing = 14;
    dimensions.identifier=inlineMode?@"appearance-inline-dimensions":@"appearance-dialogue-dimensions";
    [dimensions addArrangedSubview:[self appearanceSliderRow:inlineMode ? @"最大宽度" : @"字幕框宽度" slider:inlineMode ? self.batchWidthSlider : self.captionWidthSlider]];
    [dimensions addArrangedSubview:[self appearanceSliderRow:inlineMode ? @"长卡最大高度" : @"字幕框最小高度" slider:inlineMode ? self.batchHeightSlider : self.captionHeightSlider]];
    if (inlineMode) {
        [dimensions addArrangedSubview:[self mutedLabel:@"右侧用长文演示高度上限，超出部分可滚动阅读。"]];
    } else {
        [dimensions addArrangedSubview:[self workspaceButton:@"打开字幕预览" action:@selector(showCaptionAppearancePreview:) primary:NO]];
    }
    NSStackView *disclosure=[self verticalStack];disclosure.spacing=12;
    NSBox *rule=(NSBox *)[self separator];rule.borderColor=FYAppearanceColorFromHex(@"#DED7CD",self.uiBorder);[disclosure addArrangedSubview:rule];
    FYSubtitleDisclosureButton *dimensionButton=[FYSubtitleDisclosureButton buttonWithTitle:@"尺寸设置" target:self action:@selector(toggleSubtitleDimensions:)];
    dimensionButton.bordered=NO;[dimensionButton setButtonType:NSButtonTypePushOnPushOff];dimensionButton.tag=self.disclosureViews.count;
    if(!self.disclosureViews)self.disclosureViews=[NSMutableArray array];[self.disclosureViews addObject:dimensions];dimensions.hidden=YES;
    [disclosure addArrangedSubview:dimensionButton];[disclosure addArrangedSubview:dimensions];[controls addArrangedSubview:disclosure];

    NSStackView *preview = [self verticalStack]; preview.spacing = 8;
    NSStackView *previewHeading = [self horizontalStack];
    [previewHeading addArrangedSubview:[self label:@"即时预览" font:FYUIFont(14,NSFontWeightSemibold) color:self.uiInk]];
    [previewHeading addArrangedSubview:[self spacer]];
    NSTextField *theme = [self mutedLabel:@"译芽花境"]; [previewHeading addArrangedSubview:theme];
    self.appearanceThemeLabels = [self.appearanceThemeLabels arrayByAddingObject:theme];
    [preview addArrangedSubview:previewHeading];
    FYSubtitleAppearancePreview *sample = [FYSubtitleAppearancePreview new]; sample.inlineMode = inlineMode;
    sample.identifier = inlineMode ? @"appearance-inline-preview" : @"appearance-dialogue-preview";
    sample.accessibilityLabel = inlineMode ? @"界面贴译样式效果，示例文字" : @"长对白样式效果，示例文字";
    self.appearanceSamples = [self.appearanceSamples arrayByAddingObject:sample]; [preview addArrangedSubview:sample];
    [preview addArrangedSubview:[self mutedLabel:inlineMode ? @"短贴片与长卡同步更新，普通贴译只显示译文。" : @"长句自然换行；字幕仅在目标应用前台时显示。"]];
    FYLearningColumnsView *columns = [FYLearningColumnsView new];
    columns.spacing = 22; columns.leftFraction = 1.0/3; columns.compactWidth = 592;columns.columnWidthPriority=999;
    columns.identifier = inlineMode ? @"appearance-inline-columns" : @"appearance-dialogue-columns";
    [columns addArrangedSubview:controls]; [columns addArrangedSubview:preview];
    [columns setCustomSpacing:22 afterView:controls];
    [editor setCustomSpacing:22 afterView:palettes];
    [editor addArrangedSubview:columns];
    return editor;
}

- (void)toggleSubtitleDimensions:(NSButton *)sender {
    [self toggleDisclosure:sender];
    if ([self.disclosureViews[sender.tag].identifier isEqualToString:@"appearance-inline-dimensions"]) {
        FYSubtitleAppearancePreview *sample=self.appearanceSamples[1];
        sample.showsHeightLimitExample=sender.state==NSControlStateValueOn;
        [sample refreshSample];
    }
}

- (void)selectAppearanceMode:(id)sender {
    if([sender isKindOfClass:NSButton.class])self.appearanceModeControl.selectedSegment=[sender tag];
    [self updateSubtitleAppearancePage];
    if (self.appearanceModeControl.selectedSegment == 1) { [self.captionAppearancePreviewPanel orderOut:nil]; }
    [self scheduleSettingsSave];
}
- (void)selectBatchSwatch:(NSButton *)sender {
    self.batchTextColorCustomized = NO; self.batchThemeControl.selectedSegment = sender.tag;
    [self controlValueChanged:self.batchThemeControl];
}
- (void)resetBatchTextColor:(id)sender {
    self.batchTextColorCustomized = NO; self.batchTextColorWell.color = [self inlineThemeTextColor];
    [self controlValueChanged:self.batchThemeControl];
}
- (NSInteger)inlineThemeIndex {
    NSInteger index = self.batchThemeControl ? self.batchThemeControl.selectedSegment : 3;
    return index>=0 && index<=3 ? index : 3;
}
- (NSColor *)inlineThemeTextColor { return FYSubtitleThemeText([self inlineThemeIndex]); }

- (void)updateSubtitleAppearancePage {
    NSInteger mode = self.appearanceModeControl.selectedSegment == 0 ? 0 : 1;
    for(NSButton *button in self.appearanceModeButtons)button.state=button.tag==mode?NSControlStateValueOn:NSControlStateValueOff;
    for (NSUInteger i=0; i<self.appearanceEditors.count; i++) { self.appearanceEditors[i].hidden = i != mode; }
    for (NSControl *control in self.appearanceValueLabels.keyEnumerator) {
        NSTextField *value = [self.appearanceValueLabels objectForKey:control];
        value.stringValue = control == self.captionOpacitySlider ? [NSString stringWithFormat:@"%.0f%%",control.doubleValue*100] :
            [NSString stringWithFormat:@"%.0f pt",control.doubleValue];
    }
    NSArray *names = @[@"黑底白字", @"白底黑字", @"粉底深字", @"译芽花境"];
    for (NSUInteger i=0; i<self.appearanceSamples.count; i++) {
        BOOL inlineMode = i==1; NSInteger index = inlineMode ? [self inlineThemeIndex] : [self captionThemeIndex];
        NSArray<NSButton *> *buttons = inlineMode ? self.batchThemeSwatches : self.themeSwatches;
        for (NSButton *button in buttons) { button.state = button.tag==index ? NSControlStateValueOn : NSControlStateValueOff; }
        self.appearanceColorStateLabels[i].stringValue = (inlineMode ? self.batchTextColorCustomized : self.captionTextColorCustomized) ? @"自定义" : @"跟随样式";
        self.appearanceThemeLabels[i].stringValue = names[index];
        FYSubtitleAppearancePreview *sample = self.appearanceSamples[i];
        sample.subtitleFill = inlineMode ? [self inlinePanelFillColor] : [self captionBackgroundColorWithAlpha:self.captionOpacitySlider.doubleValue];
        sample.subtitleInk = inlineMode ? [self inlinePanelTextColor] : [self captionTextColor];
        sample.subtitleBorder = inlineMode ? [self inlinePanelBorderColor] : [self captionBorderColor];
        sample.subtitleSize = inlineMode ? self.batchFontSizeSlider.doubleValue : self.captionFontSizeSlider.doubleValue;
        sample.subtitleWidth = inlineMode ? self.batchWidthSlider.doubleValue : self.captionWidthSlider.doubleValue;
        sample.subtitleHeight = inlineMode ? self.batchHeightSlider.doubleValue : self.captionHeightSlider.doubleValue;
        [sample refreshSample];
    }
}

- (NSDictionary *)subtitleAppearanceSettings {
    return @{@"captionOpacity":@(self.captionOpacitySlider.doubleValue), @"captionFontSize":@(self.captionFontSizeSlider.doubleValue),
        @"captionHeight":@(self.captionHeightSlider.doubleValue), @"captionWidth":@(self.captionWidthSlider.doubleValue),
        @"captionTextColor":FYAppearanceColorHex(self.captionTextColorWell.color), @"captionTextColorCustomized":@(self.captionTextColorCustomized),
        @"captionTheme":@([self captionThemeIndex]), @"batchFontSize":@(self.batchFontSizeSlider.doubleValue),
        @"batchMaxWidth":@(self.batchWidthSlider.doubleValue), @"batchMaxHeight":@(self.batchHeightSlider.doubleValue),
        @"batchTextColor":FYAppearanceColorHex(self.batchTextColorWell.color), @"batchTextColorCustomized":@(self.batchTextColorCustomized),
        @"batchTheme":@([self inlineThemeIndex]), @"appearanceMode":@(self.appearanceModeControl.selectedSegment==0 ? 0 : 1)};
}
- (void)loadSubtitleAppearanceSettings:(NSDictionary *)settings {
    self.captionOpacitySlider.doubleValue = settings[@"captionOpacity"] ? [settings[@"captionOpacity"] doubleValue] : .58;
    self.captionFontSizeSlider.doubleValue = settings[@"captionFontSize"] ? [settings[@"captionFontSize"] doubleValue] : 30;
    self.captionHeightSlider.doubleValue = settings[@"captionHeight"] ? [settings[@"captionHeight"] doubleValue] : 180;
    self.captionWidthSlider.doubleValue = settings[@"captionWidth"] ? [settings[@"captionWidth"] doubleValue] : 900;
    self.captionThemeControl.selectedSegment = settings[@"captionTheme"] ? [settings[@"captionTheme"] integerValue] : 3;
    self.captionThemeControl.selectedSegment = [self captionThemeIndex];
    self.captionTextColorCustomized = [settings[@"captionTextColorCustomized"] boolValue];
    self.captionTextColorWell.color = self.captionTextColorCustomized ? FYAppearanceColorFromHex(settings[@"captionTextColor"],[self captionThemeTextColor]) : [self captionThemeTextColor];
    self.batchFontSizeSlider.doubleValue = settings[@"batchFontSize"] ? [settings[@"batchFontSize"] doubleValue] : 16;
    self.batchWidthSlider.doubleValue = settings[@"batchMaxWidth"] ? [settings[@"batchMaxWidth"] doubleValue] : 560;
    self.batchHeightSlider.doubleValue = settings[@"batchMaxHeight"] ? [settings[@"batchMaxHeight"] doubleValue] : 330;
    self.batchThemeControl.selectedSegment = settings[@"batchTheme"] ? [settings[@"batchTheme"] integerValue] : 3;
    self.batchThemeControl.selectedSegment = [self inlineThemeIndex];
    NSColor *saved = FYAppearanceColorFromHex(settings[@"batchTextColor"],[self inlineThemeTextColor]);
    // Old versions had a color well but no customized flag. Preserve a user's non-default color.
    self.batchTextColorCustomized = settings[@"batchTextColorCustomized"] ? [settings[@"batchTextColorCustomized"] boolValue] :
        ![FYAppearanceColorHex(saved) isEqualToString:FYAppearanceColorHex([self inlineThemeTextColor])];
    self.batchTextColorWell.color = self.batchTextColorCustomized ? saved : [self inlineThemeTextColor];
    self.appearanceModeControl.selectedSegment = settings[@"appearanceMode"] && [settings[@"appearanceMode"] integerValue]==0 ? 0 : 1;
    [self applyBatchAppearanceToLayoutEngine];
}
