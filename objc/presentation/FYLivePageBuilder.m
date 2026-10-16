#import "FYLivePageBuilder.h"

@implementation FYLivePageBuilder
- (NSView *)makePageWithReceiver:(id<FYLivePageSource>)receiver {
    NSStackView *page = [receiver verticalStack];
    page.spacing = 12;
    page.alignment = NSLayoutAttributeWidth;

    // 1) 游戏实时画面区
    NSStackView *screen = [receiver verticalStack];
    screen.spacing = 12;
    NSStackView *screenHeader = [receiver horizontalStack];
    [screenHeader addArrangedSubview:[receiver cardTitle:@"实时画面"]];
    [screenHeader addArrangedSubview:[receiver spacer]];
    [screenHeader addArrangedSubview:receiver.currentWindowLabel];
    [screen addArrangedSubview:screenHeader];

    NSView *previewShadow = [[NSView alloc] init];
    previewShadow.wantsLayer = YES;
    previewShadow.layer.backgroundColor = NSColor.clearColor.CGColor;
    previewShadow.layer.cornerRadius = 12;
    previewShadow.layer.shadowColor = FYAdventureColor(@"line").CGColor;
    previewShadow.layer.shadowOpacity = 0.35;
    previewShadow.layer.shadowRadius = 10;
    previewShadow.layer.shadowOffset = CGSizeMake(0, -3);
    NSView *preview = [[NSView alloc] init];
    preview.wantsLayer = YES;
    preview.layer.backgroundColor = FYAdventureColor(@"reading").CGColor;
    preview.layer.cornerRadius = 12;
    preview.layer.masksToBounds = YES;
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    [previewShadow addSubview:preview];
    [NSLayoutConstraint activateConstraints:@[
        [preview.leadingAnchor constraintEqualToAnchor:previewShadow.leadingAnchor],
        [preview.trailingAnchor constraintEqualToAnchor:previewShadow.trailingAnchor],
        [preview.topAnchor constraintEqualToAnchor:previewShadow.topAnchor],
        [preview.bottomAnchor constraintEqualToAnchor:previewShadow.bottomAnchor]]];
    FYCapturePreviewView *capturePreview = [[FYCapturePreviewView alloc] init];
    receiver.framePreview = capturePreview;
    receiver.framePreview.imageScaling = NSImageScaleProportionallyUpOrDown;
    [receiver.framePreview setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [receiver.framePreview setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    receiver.framePreview.translatesAutoresizingMaskIntoConstraints = NO;
    [preview addSubview:receiver.framePreview];
    receiver.previewPlaceholder = [receiver label:@"选择窗口并开始翻译后显示画面" font:FYUIFont(13, NSFontWeightRegular) color:receiver.uiMuted];
    [preview addSubview:receiver.previewPlaceholder];
    [screen addArrangedSubview:previewShadow];
    [previewShadow.heightAnchor constraintGreaterThanOrEqualToConstant:1].active = YES;
    [previewShadow.heightAnchor constraintLessThanOrEqualToConstant:480].active = YES;
    NSLayoutConstraint *preferredPreviewHeight = [previewShadow.heightAnchor constraintEqualToConstant:480];
    preferredPreviewHeight.priority = 500;
    preferredPreviewHeight.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [receiver.framePreview.leadingAnchor constraintEqualToAnchor:preview.leadingAnchor],
        [receiver.framePreview.trailingAnchor constraintEqualToAnchor:preview.trailingAnchor],
        [receiver.framePreview.topAnchor constraintEqualToAnchor:preview.topAnchor],
        [receiver.framePreview.bottomAnchor constraintEqualToAnchor:preview.bottomAnchor],
        [receiver.previewPlaceholder.centerXAnchor constraintEqualToAnchor:preview.centerXAnchor],
        [receiver.previewPlaceholder.centerYAnchor constraintEqualToAnchor:preview.centerYAnchor]]];
    // 「翻译当前界面」入口已移除：它会把整屏文字汇总到字幕框，不符合实时翻译流程。
    // 只移除入口；截图 / OCR / 翻译方法仍被其他地方使用，保持不动。
    // 状态胶囊对象保留（refreshLiveChips 仍引用），只是不再排进布局。
    receiver.liveChipRecognition = [receiver chipLabel:@"识别中"];
    receiver.liveChipAutoTranslate = [receiver chipLabel:@"自动翻译"];
    receiver.liveChipPauseFollow = [receiver chipLabel:@"暂停跟读"];
    NSStackView *metrics = [receiver horizontalStack];
    receiver.ocrDurationLabel = [receiver label:@"最近识别 —" font:FYUIFont(12, NSFontWeightRegular) color:receiver.uiMuted];
    receiver.translationDurationLabel = [receiver label:@"翻译耗时 —" font:FYUIFont(12, NSFontWeightRegular) color:receiver.uiMuted];
    receiver.translationCountLabel = [receiver label:@"翻译轮次 0" font:FYUIFont(12, NSFontWeightRegular) color:receiver.uiMuted];
    [metrics addArrangedSubview:receiver.ocrDurationLabel];
    [metrics addArrangedSubview:receiver.translationDurationLabel];
    [metrics addArrangedSubview:receiver.translationCountLabel];
    metrics.hidden = YES;
    receiver.liveErrorLabel = [receiver label:@"" font:FYUIFont(12, NSFontWeightRegular) color:[NSColor systemRedColor]];
    receiver.liveErrorLabel.maximumNumberOfLines = 2;
    receiver.liveErrorLabel.hidden = YES;
    [screen addArrangedSubview:receiver.liveErrorLabel];
    [page addArrangedSubview:[receiver cardWithStack:screen]];

    // 2) 中文翻译卡片：先读译文，再按需看原文。
    NSStackView *translationBlock = [receiver verticalStack];
    translationBlock.spacing = 12;
    NSStackView *translationTitleRow = [receiver horizontalStack];
    [translationTitleRow addArrangedSubview:[receiver mutedLabel:@"中文翻译"]];
    [translationTitleRow addArrangedSubview:[receiver spacer]];
    [translationBlock addArrangedSubview:translationTitleRow];
    receiver.learningTranslationLabel = [receiver label:@"开始翻译后，译文会显示在这里。" font:FYUIFont(14, NSFontWeightRegular) color:receiver.uiMuted];
    receiver.learningTranslationLabel.selectable = YES;
    // Keep attributed speaker/body fonts when AppKit opens the selection editor.
    receiver.learningTranslationLabel.allowsEditingTextAttributes = YES;
    receiver.learningTranslationLabel.maximumNumberOfLines = 0;
    receiver.learningTranslationLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [translationBlock addArrangedSubview:receiver.learningTranslationLabel];
    NSView *translationCardOuter = [receiver cardWithStack:translationBlock];
    ((FYAdventurePanel *)translationCardOuter).fillColor = FYAdventureColor(@"cream");
    ((FYAdventurePanel *)translationCardOuter).edgeColor = FYAdventureColor(@"line");
    receiver.translationReadingMinimumHeight = [translationCardOuter.heightAnchor constraintGreaterThanOrEqualToConstant:104];
    receiver.translationReadingMinimumHeight.active = YES;
    [page addArrangedSubview:translationCardOuter];

    // 3) 当前对白卡片：保留完整原文与原生字符索引。
    NSStackView *sentence = [receiver verticalStack];
    sentence.spacing = 8;
    NSStackView *sentenceTitleRow = [receiver horizontalStack];
    [sentenceTitleRow addArrangedSubview:[receiver mutedLabel:@"当前对白"]];
    [sentenceTitleRow addArrangedSubview:[receiver spacer]];
    receiver.liveLevelTag = [receiver chipLabel:@"N3"];
    receiver.liveLevelTag.hidden = YES;
    [sentenceTitleRow addArrangedSubview:receiver.liveLevelTag];
    [sentence addArrangedSubview:sentenceTitleRow];
    receiver.liveSourceEmptyLabel = [receiver label:@"等待识别当前对白，识别后可选词学习。" font:FYUIFont(14, NSFontWeightRegular) color:receiver.uiMuted];
    [sentence addArrangedSubview:receiver.liveSourceEmptyLabel];
    NSScrollView *learningScroll = [[NSScrollView alloc] init];
    receiver.learningSourceTextView = [[FYSelectableSourceTextView alloc] init];
    FYConfigureSourceTextView(receiver.learningSourceTextView, learningScroll, 19);
    NSMutableParagraphStyle *sourceStyle = [NSMutableParagraphStyle new]; sourceStyle.lineSpacing = 0;
    receiver.learningSourceTextView.defaultParagraphStyle = sourceStyle;
    [sentence addArrangedSubview:learningScroll];
    learningScroll.hidden = YES;
    receiver.sourceReadingHeight = [learningScroll.heightAnchor constraintEqualToConstant:48];
    receiver.sourceReadingHeight.active = YES;
    [self wireSourceSelectionWithReceiver:receiver];
    receiver.liveSourceSelectionHintLabel = [receiver label:@"点击选词，或按住拖拽选择词语／短语" font:FYUIFont(11, NSFontWeightRegular) color:receiver.uiMuted];
    receiver.liveSourceSelectionHintLabel.hidden = YES;
    [sentence addArrangedSubview:receiver.liveSourceSelectionHintLabel];
    // 固定此句 / 跟随最新：真正可点击的入口。
    // 未固定显示「固定此句」；固定后显示「跟随最新」，点击解除固定并切回最新识别内容。
    // 固定期间有新台词由 learningPinnedLabel 提示「已固定 · 有新台词」。
    receiver.pinSentenceButton = [receiver workspaceButton:@"固定此句" action:@selector(toggleLearningPin:) primary:NO];
    receiver.pinSentenceButton.bezelStyle = NSBezelStyleRounded;
    receiver.pinSentenceButton.enabled = NO;
    receiver.followLatestButton = [NSButton buttonWithTitle:@"跟随最新" target:[receiver livePageActionTarget] action:@selector(followLatestSentence:)];
    receiver.followLatestButton.bezelStyle = NSBezelStyleRounded;
    receiver.followLatestButton.hidden = YES;
    receiver.learningPinnedLabel = [receiver mutedLabel:@"跟随最新"];
    [sentenceTitleRow addArrangedSubview:receiver.pinSentenceButton];
    [sentenceTitleRow addArrangedSubview:receiver.learningPinnedLabel];
    receiver.wordPickArea = [receiver verticalStack];
    receiver.wordPickArea.spacing = 10;
    receiver.wordPickArea.hidden = YES;
    NSStackView *pickTitleRow = [receiver horizontalStack];
    receiver.wordPickSurfaceLabel = [receiver label:@"" font:FYUIFont(15, NSFontWeightBold) color:receiver.uiInk];
    [pickTitleRow addArrangedSubview:receiver.wordPickSurfaceLabel];
    [pickTitleRow addArrangedSubview:[receiver spacer]];
    NSButton *pickClose = [NSButton buttonWithTitle:@"关闭" target:[receiver livePageActionTarget] action:@selector(closeWordPick:)];
    pickClose.bezelStyle = NSBezelStyleRounded;
    [pickTitleRow addArrangedSubview:pickClose];
    [receiver.wordPickArea addArrangedSubview:pickTitleRow];
    receiver.lemmaField = [receiver textField:@"原形（可留空）"];
    receiver.readingField = [receiver textField:@"读音（可留空）"];
    receiver.meaningField = [receiver textField:@"释义（可留空）"];
    for (NSTextField *field in @[receiver.lemmaField, receiver.readingField, receiver.meaningField]) {
        field.action = @selector(vocabularyFormChanged:);
    }
    [receiver.wordPickArea addArrangedSubview:[receiver rowWithLabel:@"原形" view:receiver.lemmaField]];
    [receiver.wordPickArea addArrangedSubview:[receiver rowWithLabel:@"读音" view:receiver.readingField]];
    [receiver.wordPickArea addArrangedSubview:[receiver rowWithLabel:@"释义" view:receiver.meaningField]];
    receiver.vocabularySelectionLabel = [receiver label:@"" font:FYUIFont(12, NSFontWeightRegular) color:receiver.uiMuted];
    [receiver.wordPickArea addArrangedSubview:receiver.vocabularySelectionLabel];
    NSStackView *pickButtons = [receiver horizontalStack];
    NSButton *completeWord = [NSButton buttonWithTitle:@"补全读音与释义" target:[receiver livePageActionTarget] action:@selector(completeSelectedVocabulary:)];
    completeWord.bezelStyle = NSBezelStyleRounded;
    NSButton *saveWord = [NSButton buttonWithTitle:@"收藏词条" target:[receiver livePageActionTarget] action:@selector(bookmarkSelectedVocabulary:)];
    saveWord.bezelStyle = NSBezelStyleRounded;
    [pickButtons addArrangedSubview:completeWord];
    [pickButtons addArrangedSubview:saveWord];
    [receiver.wordPickArea addArrangedSubview:pickButtons];
    [receiver installLivePageVocabularyStatusLabel:[receiver label:@"" font:FYUIFont(12, NSFontWeightRegular) color:receiver.uiMuted]];
    [receiver.wordPickArea addArrangedSubview:receiver.vocabularyStatusLabel];
    [sentence addArrangedSubview:receiver.wordPickArea];
    // Minimum card heights leave their spare space below the reading content,
    // rather than stretching the heading row toward the middle.
    for (NSStackView *readingStack in @[translationBlock, sentence]) {
        for (NSView *view in readingStack.arrangedSubviews) {
            [view setContentHuggingPriority:999 forOrientation:NSLayoutConstraintOrientationVertical];
        }
        NSView *space = [NSView new];
        NSView *lastContent = readingStack.arrangedSubviews.lastObject;
        [readingStack addArrangedSubview:space];
        [readingStack setCustomSpacing:0 afterView:lastContent];
        [space.heightAnchor constraintGreaterThanOrEqualToConstant:0].active = YES;
        NSLayoutConstraint *collapsedSpace = [space.heightAnchor constraintEqualToConstant:0];
        collapsedSpace.priority = 1;
        collapsedSpace.active = YES;
    }
    NSView *sourceCard = [receiver cardWithStack:sentence];
    ((FYAdventurePanel *)sourceCard).fillColor = FYAdventureColor(@"paper");
    ((FYAdventurePanel *)sourceCard).edgeColor = FYAdventureColor(@"line");
    receiver.sourceReadingMinimumHeight = [sourceCard.heightAnchor constraintGreaterThanOrEqualToConstant:104];
    receiver.sourceReadingMinimumHeight.active = YES;
    [page addArrangedSubview:sourceCard];

    [page addArrangedSubview:[receiver makeInlineTranslationListCard]];

    [page addArrangedSubview:[receiver makeIntegratedGrammarCard]];
    return page;
}

- (id)wireSourceSelectionWithReceiver:(id<FYLivePageSelectionSource>)receiver {
    __weak id<FYLivePageSelectionSource> weakSelf = receiver;
    receiver.learningSourceTextView.willBeginSelection = ^{ [weakSelf freezeLearningSentenceForSelection]; };
    receiver.learningSourceTextView.didFinishSelection = ^{ [weakSelf updateWordPickForSelection]; };
    receiver.learningSourceTextView.didClickAtCharacterIndex = ^(NSUInteger characterIndex) {
        [weakSelf selectWordAtCharacterIndex:characterIndex];
    };
    return [[NSNotificationCenter defaultCenter] addObserverForName:NSTextViewDidChangeSelectionNotification
                                                      object:receiver.learningSourceTextView
                                                       queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(NSNotification *note) {
        if (weakSelf.learningSourceTextView.trackingSelection) { return; }
        weakSelf.lemmaField.stringValue = @"";
        weakSelf.readingField.stringValue = @"";
        weakSelf.meaningField.stringValue = @"";
        weakSelf.vocabCompletionFromAI = NO;
        weakSelf.vocabSelectionGeneration += 1;
        [weakSelf updateWordPickForSelection];
    }];
}
@end
