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
- (NSView *)grammarInfoCellWithLabel:(NSString *)labelText value:(NSString *)valueText {
    NSStackView *cell = [self verticalStack];
    cell.spacing = 4;
    [cell addArrangedSubview:[self mutedLabel:labelText]];
    NSTextField *value = [self label:valueText.length ? valueText : @"—" font:FYUIFont(13, NSFontWeightRegular) color:self.uiInk];
    value.maximumNumberOfLines = 3;
    value.lineBreakMode = NSLineBreakByWordWrapping;
    [cell addArrangedSubview:value];
    NSView *box = [self card];
    box.wantsLayer = YES;
    ((FYAdventurePanel *)box).fillColor = FYAdventureColor(@"shell");
    ((FYAdventurePanel *)box).edgeColor = FYAdventureColor(@"rim");
    [box addSubview:cell];
    cell.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [cell.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:12],
        [cell.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-12],
        [cell.topAnchor constraintEqualToAnchor:box.topAnchor constant:10],
        [cell.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-10]]];
    return box;
}

- (void)selectGrammarTab:(NSButton *)sender {
    self.selectedGrammarTab = sender.tag;
    [self applyGrammarTabSelection];
}

- (void)applyGrammarTabSelection {
    NSArray<NSString *> *titles = @[@"整句理解", @"语法点", @"例句"];
    for (NSUInteger index = 0; index < self.grammarTabButtons.count; index++) {
        NSButton *tab = self.grammarTabButtons[index];
        BOOL active = index == (NSUInteger)self.selectedGrammarTab;
        tab.contentTintColor = active ? self.uiInk : self.uiMuted;
        tab.font = FYUIFont(13, active ? NSFontWeightSemibold : NSFontWeightRegular);
        tab.title = titles[index];
        NSView *underline = index < self.grammarTabUnderlines.count ? self.grammarTabUnderlines[index] : nil;
        underline.layer.backgroundColor = (active ? FYAdventureColor(@"leaf") : NSColor.clearColor).CGColor;
    }
    BOOL hasResult = self.currentAnalysis != nil;
    BOOL emptyGrammar = hasResult && self.selectedGrammarTab == 1 && self.currentAnalysis.grammar.count == 0;
    BOOL showEmpty = !hasResult || emptyGrammar;
    self.grammarTabRow.hidden = !hasResult;
    self.grammarStatusLabel.hidden = !hasResult;
    self.grammarReferenceNote.hidden = !hasResult;
    self.grammarEmptyPane.hidden = !showEmpty;
    self.sentenceInsightStack.hidden = !hasResult || self.selectedGrammarTab != 0;
    self.grammarPointsPane.hidden = showEmpty || self.selectedGrammarTab != 1;
    self.grammarExamplesPane.hidden = !hasResult || self.selectedGrammarTab != 2;

    BOOL hasSentence = self.learningCoordinator.currentSentenceID.length > 0 && self.learningCoordinator.currentSourceText.length > 0;
    NSString *title = @"这句话还没有分析";
    NSString *hint = @"分析后，查看语法含义、接续和本句用法。";
    NSString *action = emptyGrammar ? @"重新分析" : @"分析此句";
    if (self.learningAnalysisBusy) {
        title = @"正在分析这句话";
        hint = @"正在整理语法点、接续和本句用法…";
        action = @"分析中…";
    } else if (!hasSentence) {
        title = @"等待一句原文";
        hint = @"开始翻译，或从最近台词中选择一句，再来查看语法。";
    } else if (self.grammarAnalysisError.length) {
        title = @"这次分析没有完成";
        hint = [NSString stringWithFormat:@"%@\n请检查原句或翻译服务后重试。", self.grammarAnalysisError];
        action = @"重试分析";
    } else if (emptyGrammar) {
        title = @"这句没有识别到语法点";
        hint = @"可以切换到「整句理解」查看解释，或重新分析。";
    }
    self.grammarEmptyTitle.stringValue = title;
    self.grammarEmptyHint.stringValue = hint;
    self.grammarEmptyAnalyzeButton.title = action;
    self.grammarEmptyAnalyzeButton.enabled = hasSentence && !self.learningAnalysisBusy;
}

- (NSView *)makeHistoryPage {
    NSStackView *page = [self verticalStack]; page.spacing = 18;
    NSStackView *header = [self horizontalStack];
    [header addArrangedSubview:[self mutedLabel:@"最近 5 条对白 · 选择一句，回到实时页查看语法"]];
    [header addArrangedSubview:[self spacer]];
    [header addArrangedSubview:[self workspaceButton:@"刷新台词" action:@selector(refreshHistoryAction:) primary:NO]];
    [page addArrangedSubview:header];
    self.historyListStack = [self verticalStack]; self.historyListStack.spacing = 12;
    [page addArrangedSubview:self.historyListStack];
    [page addArrangedSubview:[self mutedLabel:@"完整原句与译文一起保留。相同对白的识别波动合并展示。"]];
    return page;
}

- (NSView *)makeIntegratedGrammarCard {
    NSStackView *content = [self verticalStack]; content.spacing = 16;

    // 标题栏
    // 标题与页签合为一行：左「这一句的语法」+ 页签，右侧只保留固定/跟随与状态。
    NSStackView *header = [self horizontalStack];
    header.spacing = 14;
    [header addArrangedSubview:[self cardTitle:@"这一句的语法"]];
    NSStackView *tabRow = [self horizontalStack]; tabRow.spacing = 14;
    NSMutableArray *tabButtons = [NSMutableArray array];
    NSMutableArray *tabUnderlines = [NSMutableArray array];
    for (NSString *title in @[@"整句理解", @"语法点", @"例句"]) {
        NSButton *tab = [NSButton buttonWithTitle:title target:self action:@selector(selectGrammarTab:)];
        tab.bordered = NO; tab.tag = tabButtons.count;
        tab.font = FYUIFont(13, NSFontWeightRegular);
        tab.contentTintColor = self.uiMuted;
        NSView *underline = [[NSView alloc] init];
        underline.wantsLayer = YES;
        underline.layer.cornerRadius = 1;
        underline.layer.backgroundColor = NSColor.clearColor.CGColor;
        [underline.heightAnchor constraintEqualToConstant:2].active = YES;
        NSStackView *wrapper = [self verticalStack]; wrapper.spacing = 3;
        [wrapper addArrangedSubview:tab];
        [wrapper addArrangedSubview:underline];
        [underline.widthAnchor constraintEqualToAnchor:wrapper.widthAnchor].active = YES;
        [wrapper setContentHuggingPriority:999 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [tabRow addArrangedSubview:wrapper];
        [tabButtons addObject:tab];
        [tabUnderlines addObject:underline];
    }
    [tabRow setContentHuggingPriority:999 forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.grammarTabButtons = tabButtons;
    self.grammarTabUnderlines = tabUnderlines;
    self.grammarTabRow = tabRow;
    [header addArrangedSubview:tabRow];
    [header addArrangedSubview:[self spacer]];
    self.grammarPinnedLabel = [self mutedLabel:@""];
    [header addArrangedSubview:self.grammarPinnedLabel];
    self.grammarStatusLabel = [self mutedLabel:@"尚未分析"];
    [header addArrangedSubview:self.grammarStatusLabel];
    [content addArrangedSubview:header];

    // 分析前只呈现一份提示和一个动作，不提前展开空列表、详情与追问。
    NSView *empty = [NSView new];
    NSStackView *emptyContent = [NSStackView new];
    emptyContent.orientation = NSUserInterfaceLayoutOrientationVertical;
    emptyContent.alignment = NSLayoutAttributeCenterX;
    emptyContent.spacing = 10;
    emptyContent.translatesAutoresizingMaskIntoConstraints = NO;
    self.grammarEmptyTitle = [self label:@"" font:FYUIFont(16, NSFontWeightSemibold) color:self.uiInk];
    self.grammarEmptyHint = [self mutedLabel:@""];
    for (NSTextField *label in @[self.grammarEmptyTitle, self.grammarEmptyHint]) {
        label.alignment = NSTextAlignmentCenter;
        label.maximumNumberOfLines = 0;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [emptyContent addArrangedSubview:label];
        [label.widthAnchor constraintEqualToAnchor:emptyContent.widthAnchor].active = YES;
    }
    self.grammarEmptyAnalyzeButton = [self workspaceButton:@"分析此句" action:@selector(analyzeCurrentSentence:) primary:YES];
    [emptyContent addArrangedSubview:self.grammarEmptyAnalyzeButton];
    [emptyContent setCustomSpacing:16 afterView:self.grammarEmptyHint];
    [empty addSubview:emptyContent];
    [NSLayoutConstraint activateConstraints:@[
        [emptyContent.leadingAnchor constraintEqualToAnchor:empty.leadingAnchor constant:12],
        [emptyContent.trailingAnchor constraintEqualToAnchor:empty.trailingAnchor constant:-12],
        [emptyContent.topAnchor constraintEqualToAnchor:empty.topAnchor constant:12],
        [emptyContent.bottomAnchor constraintEqualToAnchor:empty.bottomAnchor constant:-16]
    ]];
    self.grammarEmptyPane = empty;
    [content addArrangedSubview:empty];

    // 隐藏的镜像视图：学习同步仍在使用这些属性，只是不在界面上重复展示原句。
    self.grammarSourceLabel = [self mutedLabel:@""];
    self.grammarSourceTextView = [NSTextView new];
    self.grammarSourceTextView.font = FYJapaneseFont(22);
    self.grammarBackToSourceButton = [self workspaceButton:@"返回原句选词" action:@selector(backToSourcePage:) primary:NO];
    self.grammarResultsLabel = [self mutedLabel:@""]; self.grammarResultsLabel.hidden = YES;
    self.grammarSourceLabel.hidden = YES;

    // —— Tab 0：整句理解 ——
    self.sentenceInsightStack = [self verticalStack]; self.sentenceInsightStack.spacing = 8;
    self.sentenceStructureStack = [self verticalStack]; self.sentenceStructureStack.spacing = 8;
    self.sentenceInsightLabel = [self label:@"" font:FYUIFont(14, NSFontWeightRegular) color:self.uiInk];
    self.sentenceInsightLabel.maximumNumberOfLines = 6;
    self.sentenceInsightLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self.sentenceInsightStack addArrangedSubview:self.sentenceInsightLabel];
    [content addArrangedSubview:self.sentenceInsightStack];

    // —— 句子结构图（紧凑胶囊节点，独立于左右两栏）——
    NSView *structureCard = [self card];
    ((FYAdventurePanel *)structureCard).fillColor = FYAdventureColor(@"paper");
    ((FYAdventurePanel *)structureCard).edgeColor = FYAdventureColor(@"line");
    [structureCard addSubview:self.sentenceStructureStack];
    self.sentenceStructureStack.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.sentenceStructureStack.leadingAnchor constraintEqualToAnchor:structureCard.leadingAnchor constant:14],
        [self.sentenceStructureStack.trailingAnchor constraintEqualToAnchor:structureCard.trailingAnchor constant:-14],
        [self.sentenceStructureStack.topAnchor constraintEqualToAnchor:structureCard.topAnchor constant:12],
        [self.sentenceStructureStack.bottomAnchor constraintEqualToAnchor:structureCard.bottomAnchor constant:-12]]];
    structureCard.hidden = YES;
    self.grammarStructureCard = structureCard;
    [content addArrangedSubview:structureCard];

    // —— Tab 1：语法点（左窄栏列表约两成 + 右详情；右侧不再套大边框）——
    NSStackView *columns = [self horizontalStack];
    columns.spacing = 20;
    columns.alignment = NSLayoutAttributeTop;
    NSStackView *left = [self verticalStack]; left.spacing = 6;
    // 列表上方不再重复标题与说明；grammarOtherEmptyLabel 保留属性但不加入界面。
    self.grammarOtherEmptyLabel = [self mutedLabel:@""];
    self.grammarOtherStack = [self verticalStack]; self.grammarOtherStack.spacing = 6;
    [left addArrangedSubview:self.grammarOtherStack];
    NSLayoutConstraint *listFraction = [left.widthAnchor constraintEqualToAnchor:columns.widthAnchor multiplier:0.2];
    listFraction.priority = 500;
    NSLayoutConstraint *listMinWidth = [left.widthAnchor constraintGreaterThanOrEqualToConstant:110];
    listMinWidth.priority = 500;
    listMinWidth.active = YES;

    NSStackView *detail = [self verticalStack]; detail.spacing = 12;
    // 1) 语法名 + 等级
    NSStackView *detailHeader = [self horizontalStack];
    self.grammarDetailNameLabel = [self label:@"尚未分析" font:FYUIFont(17, NSFontWeightSemibold) color:self.uiInk];
    self.grammarDetailLevelLabel = [self mutedLabel:@""];
    [detailHeader addArrangedSubview:self.grammarDetailNameLabel];
    [detailHeader addArrangedSubview:[self spacer]];
    [detailHeader addArrangedSubview:self.grammarDetailLevelLabel];
    [detail addArrangedSubview:detailHeader];
    // 2) 一句解释
    self.grammarDetailBodyLabel = [self label:@"点击「查看分析」，查看含义、接续和本句用法。" font:FYUIFont(14, NSFontWeightRegular) color:self.uiInk];
    self.grammarDetailBodyLabel.maximumNumberOfLines = 4;
    self.grammarDetailBodyLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [detail addArrangedSubview:self.grammarDetailBodyLabel];
    // 3) 横向短字段
    self.grammarDetailFields = [self horizontalStack];
    self.grammarDetailFields.spacing = 18;
    self.grammarDetailFields.alignment = NSLayoutAttributeTop;
    [detail addArrangedSubview:self.grammarDetailFields];
    // 4) 用法或例句块
    self.grammarUsageBlock = [self verticalStack]; self.grammarUsageBlock.spacing = 6;
    [detail addArrangedSubview:self.grammarUsageBlock];
    // 5) 底部操作行：收藏、来源与重新分析（主界面追问统一走右侧 AI 伙伴，这里不再重复入口）
    NSStackView *detailActions = [self horizontalStack];
    self.grammarDetailBookmarkButton = [self workspaceButton:@"收藏此语法" action:@selector(bookmarkSelectedGrammar:) primary:NO];
    self.grammarDetailBookmarkButton.hidden = YES;
    [detailActions addArrangedSubview:self.grammarDetailBookmarkButton];
    self.grammarSourceLinkButton = [NSButton buttonWithTitle:@"查看等级参考来源 ↗" target:self action:@selector(openGrammarSource:)];
    self.grammarSourceLinkButton.bordered = NO; self.grammarSourceLinkButton.contentTintColor = self.uiAccent; self.grammarSourceLinkButton.hidden = YES;
    [detailActions addArrangedSubview:self.grammarSourceLinkButton];
    [detailActions addArrangedSubview:[self spacer]];
    self.grammarPageAnalyzeButton = [self workspaceButton:@"查看分析" action:@selector(analyzeCurrentSentence:) primary:NO];
    ((FYWorkspaceButton *)self.grammarPageAnalyzeButton).accent = YES;
    self.grammarPageAnalyzeButton.enabled = NO;
    self.analyzeButton = self.grammarPageAnalyzeButton;
    [detailActions addArrangedSubview:self.grammarPageAnalyzeButton];
    [detail addArrangedSubview:detailActions];

    // 主界面不再有「继续追问」入口：追问统一用右侧 AI 伙伴。
    // 这里的控件与逻辑保留（浮动学习卡的「问 AI」共享同一套聊天/隔离逻辑），只是不排进主界面布局。
    NSStackView *followup = [self verticalStack]; followup.spacing = 10;
    followup.hidden = YES;
    NSStackView *suggestions = [self horizontalStack];
    [suggestions addArrangedSubview:[self workspaceButton:@"解释简单一点" action:@selector(simplerExplanationForGrammar:) primary:NO]];
    [suggestions addArrangedSubview:[self workspaceButton:@"这句话是什么语气？" action:@selector(askGrammarTone:) primary:NO]];
    [followup addArrangedSubview:suggestions];
    NSStackView *ask = [self horizontalStack];
    self.grammarQuestionField = [self textField:@"还有哪里没看懂？"];
    self.grammarQuestionField.bezeled = NO; self.grammarQuestionField.wantsLayer = YES;
    self.grammarQuestionField.layer.backgroundColor = FYAdventureColor(@"reading").CGColor;
    self.grammarQuestionField.layer.cornerRadius = 7; self.grammarQuestionField.layer.borderWidth = 1;
    self.grammarQuestionField.layer.borderColor = self.uiBorder.CGColor;
    self.grammarQuestionField.target = self; self.grammarQuestionField.action = @selector(askGrammarQuestion:);
    [self.grammarQuestionField.heightAnchor constraintEqualToConstant:34].active = YES;
    [ask addArrangedSubview:self.grammarQuestionField];
    NSButton *question = [self workspaceButton:@"提问" action:@selector(askGrammarQuestion:) primary:YES];
    [ask addArrangedSubview:question];
    [followup addArrangedSubview:ask];
    self.grammarFollowupResultLabel = [self label:@"" font:FYUIFont(13, NSFontWeightRegular) color:self.uiInk];
    self.grammarFollowupResultLabel.maximumNumberOfLines = 6;
    [followup addArrangedSubview:self.grammarFollowupResultLabel];
    self.grammarFollowupControls = @[suggestions.arrangedSubviews[0], suggestions.arrangedSubviews[1], question, self.grammarQuestionField];
    for (NSControl *control in self.grammarFollowupControls) { control.enabled = NO; }
    self.grammarFollowupDisclosure = followup;
    // 刻意不 addArrangedSubview：主界面没有入口，避免留下不可达的追问面板。

    [columns addArrangedSubview:left];
    [columns addArrangedSubview:detail];
    listFraction.active = YES;
    [detail setContentHuggingPriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.grammarPointsPane = columns;
    [content addArrangedSubview:columns];

    // —— Tab 2：例句 ——
    NSStackView *examples = [self verticalStack]; examples.spacing = 10;
    [examples addArrangedSubview:[self mutedLabel:@"例句由 AI 按需生成，用于对照当前语法点。"]];
    self.grammarExampleLabel = [self label:@"还没有例句。" font:FYUIFont(14, NSFontWeightRegular) color:self.uiInk];
    self.grammarExampleLabel.maximumNumberOfLines = 8;
    self.grammarExampleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    NSView *exampleCard = [self cardWithStack:({
        NSStackView *inner = [self verticalStack]; inner.spacing = 6;
        [inner addArrangedSubview:self.grammarExampleLabel];
        inner;
    })];
    ((FYAdventurePanel *)exampleCard).fillColor = FYAdventureColor(@"shell");
    ((FYAdventurePanel *)exampleCard).edgeColor = FYAdventureColor(@"rim");
    [examples addArrangedSubview:exampleCard];
    [examples addArrangedSubview:[self workspaceButton:@"生成一个例句" action:@selector(exampleSentenceForGrammar:) primary:NO]];
    self.grammarExamplesPane = examples;
    [content addArrangedSubview:examples];

    self.selectedGrammarTab = 1;
    self.grammarReferenceNote = [self mutedLabel:@"语法解释与等级供学习参考；分析与追问按需生成。"];
    [content addArrangedSubview:self.grammarReferenceNote];
    [self applyGrammarTabSelection];
    NSView *card = [self cardWithStack:content]; card.identifier = @"integrated-grammar-card";
    return card;
}

- (void)toggleGrammarFollowup:(id)sender {
    // 主界面已移除追问入口（追问统一走右侧 AI 伙伴）；方法保留，供复用同一套逻辑的入口调用。
    if (!self.grammarFollowupDisclosure) { return; }
    BOOL willShow = self.grammarFollowupDisclosure.hidden;
    self.grammarFollowupDisclosure.hidden = !willShow;
    if (self.grammarFollowupToggle) {
        self.grammarFollowupToggle.title = willShow ? @"收起追问" : @"追问";
        self.grammarFollowupToggle.state = willShow ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)askGrammarTone:(id)sender {
    [self requestGrammarQuestion:@"这句话是什么语气？请结合原句说明。"];
}
- (void)askGrammarQuestion:(id)sender {
    NSString *question = Trim(self.grammarQuestionField.stringValue);
    if (question.length) { [self requestGrammarQuestion:question]; }
}
- (void)requestGrammarQuestion:(NSString *)question {
    FYGrammarItem *item = [self selectedGrammarItem];
    if (!item || ![self analysisMatchesCurrentSentence]) {
        self.grammarFollowupResultLabel.stringValue = @"请先分析当前句子，再选择语法点。"; return;
    }
    NSInteger generation = ++self.followupRequestGeneration;
    NSString *sentenceID = self.currentAnalysis.sentenceID;
    NSInteger version = self.currentAnalysis.version;
    self.grammarFollowupResultLabel.stringValue = @"正在生成…";
    [self.learningAnalyzer answerQuestion:question grammar:item sentenceText:self.learningCoordinator.currentSourceText translation:self.learningCoordinator.currentTranslation completion:^(NSString *answer, NSError *error) {
        if (generation != self.followupRequestGeneration || item != [self selectedGrammarItem] ||
            ![sentenceID isEqualToString:self.learningCoordinator.currentSentenceID] || version != self.learningCoordinator.currentVersion) { return; }
        self.grammarFollowupResultLabel.stringValue = error ? [NSString stringWithFormat:@"生成失败：%@；可以重新提问。", error.localizedDescription] : [NSString stringWithFormat:@"AI 建议\n%@", answer ?: @""];
    }];
}
