// AppDelegate UI composition. Kept separate from capture/translation logic.
- (NSView *)workspaceSection:(NSStackView *)stack {
    NSView *section = [self card];
    ((FYAdventurePanel *)section).fillColor = FYAdventureColor(@"reading");
    [section addSubview:stack]; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:section.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:section.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:section.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:section.bottomAnchor constant:-12]]];
    return section;
}
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary {
    FYWorkspaceButton *button = [FYWorkspaceButton buttonWithTitle:title target:self action:action];
    button.bordered = NO; button.primary = primary;
    if(action==@selector(analyzeCurrentSentence:) || action==@selector(toggleLearningPin:) ||
       action==@selector(showQuickSentence:) || action==@selector(showStudyChatOverlay:)) {
        button.primary=NO;button.accent=YES;
    }
    button.font = FYFontForText(title, 12, primary ? NSFontWeightSemibold : NSFontWeightRegular);
    [button.heightAnchor constraintEqualToConstant:34].active = YES;
    return button;
}

// 小标签/胶囊（状态标签、等级标签）：浅绿底 + 深灰字，12 圆角内的高 22 胶囊。
- (NSTextField *)chipLabel:(NSString *)text {
    NSTextField *chip = [self label:text font:FYUIFont(12, NSFontWeightMedium) color:self.uiInk];
    chip.alignment = NSTextAlignmentCenter;
    chip.wantsLayer = YES;
    chip.layer.cornerRadius = 11;
    chip.layer.backgroundColor = FYAdventureColor(@"mint").CGColor;
    chip.layer.borderWidth = 1;
    chip.layer.borderColor = FYAdventureColor(@"line").CGColor;
    [chip.heightAnchor constraintEqualToConstant:22].active = YES;
    [chip.widthAnchor constraintGreaterThanOrEqualToConstant:64].active = YES;
    return chip;
}

- (void)setChip:(NSTextField *)chip active:(BOOL)active {
    if (!chip) { return; }
    chip.layer.backgroundColor = (active ? FYAdventureColor(@"mint") : FYAdventureColor(@"shell")).CGColor;
    chip.layer.borderColor = (active ? FYAdventureColor(@"line") : FYAdventureColor(@"rim")).CGColor;
    chip.textColor = active ? self.uiInk : self.uiMuted;
}

- (void)refreshLiveChips {
    [self setChip:self.liveChipRecognition active:self.running];
    [self setChip:self.liveChipAutoTranslate active:[self autoContentModeEnabled]];
    [self setChip:self.liveChipPauseFollow active:self.learningCoordinator.isPinned];
}

// 信息网格单元：小标签 + 深灰正文。
