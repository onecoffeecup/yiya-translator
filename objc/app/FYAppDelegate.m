#import "FYAppDelegateInternal.h"
#import "../FYAppDiagnostics.h"

@implementation AppDelegate

// Implemented by explicit compatibility categories; do not synthesize duplicate state.
// Runtime compatibility
@dynamic activeTranslationTask, autoLocateSchedule, candidateModeHits, candidateModeSegment, captionPanelVisibleBeforeRegionSelection, captureCalibrationKeyMonitor;
@dynamic captureCalibrationPanel, captureCardInput, captureCardVideoRects, captureDeviceListLoaded, captureMappingCache, captureQueue;
@dynamic captureUnavailable, contentRouter, contentTranslationDisplayTarget, contentTranslationGeometryGeneration, contentTranslationMode, contentTranslationOperations;
@dynamic contentTranslationRevision, contentTranslationText, contentTranslationUIItems, detectedModeSegment, dialogueTranslationCache, displayTargetAmbiguous;
@dynamic displayTargetResolved, geometryGeneration, inFlight, inlineCacheOwner, inlineFrameStabilizer, inlineGeometryPending;
@dynamic inlineGrouper, inlineOCRPendingCount, inlineOCRPendingText, inlinePendingGroupedCount, inlinePendingGroupedTexts, inlineTranslationCache;
@dynamic inlineTranslationSerial, inputSourceSegment, lastAutoLocateAttempt, lastDisplayGeometryToken, lastDisplayTargetProbeDate, lastMappingValidationDate;
@dynamic lastOCRedCaptureFrameIndex, lastPreviewCaptureFrameIndex, lastPreviewDate, lastSubmittedNormalizedText, lastTranslatedNormalizedText, lastTranslationAttemptDate;
@dynamic lastWindowRecoveryAttemptDate, mappingValidationSchedule, ocrDisplayTargetWindowID, ocrGeometryGeneration, ocrManager, ocrPreviewLabel;
@dynamic ocrPreviewPanel, ocrPreviewVisibleBeforeRegionSelection, ocrRefinementContext, ocrRefinementStabilizer, ocrStabilityOwner, overlayOwnerPIDSnapshot;
@dynamic overlayWindowSnapshot, pendingInlineLongBatch, previewInFlight, previewQueue, previewRenderSerial, previewRequestSerial;
@dynamic previewTimer, regionSelectionKeyMonitor, regionSelectionPanel, resolvedDisplayTargetID, running, screenAccessRequestedDuringSession;
@dynamic selectOCRRegionAfterCaptureCalibration, selectedCaptureDeviceID, selectingCaptureRegion, showAllWindowsInPicker, stableCandidate, stableCandidateCount;
@dynamic timer, translationCount, translationGeneration, translationRunState, translationTaskOwner, windowManager;
@dynamic windowPickerPlaceholder, windowSelectionLost, windows;
// Overlay compatibility
@dynamic batchAppearanceTimer, captionAppearancePreviewBrand, captionAppearancePreviewContainer, captionAppearancePreviewPanel, captionAppearancePreviewText, captionBrandLabel;
@dynamic captionContainer, captionDockHasAnchor, captionDockPanel, captionHideButton, captionPanel, captionPanelShownByUser;
@dynamic captionSuppressedForUIMode, captionTextLabel, inlineDraggingPanel, inlineExpandedMissingFrames, inlineExpandedReadingBlockID, inlineExpandedReadingKeyMonitor;
@dynamic inlineExpandedReadingPanel, inlineLayoutEngine, inlineLongCardPanels, inlineManualOffsetAge, inlineManualOffsets, inlineModifierTimer;
@dynamic inlineOptionDragArmed, inlineOverflowCandidateCount, inlineOverflowCandidateFrames, inlineOverflowChoiceKeyMonitor, inlineOverflowChoicePanel, inlineOverflowCount;
@dynamic inlineOverflowEmptySince, inlineOverflowEntries, inlineOverflowPanel, inlineOverflowPanelCount, inlinePanelsByBlockID, inlineStableBlockIDs;
@dynamic inlineTranslationPanels, lastInlineCompactEntryCount, lastInlineLayoutBoxes, lastInlineLayoutContentKey, lastInlineLayoutDebugContext, lastInlineLayoutDebugViewport;
@dynamic lastInlineLayoutGeometryKey, lastInlineLayoutResult, lastInlineRenderGeometryToken, lastInlineRenderedItems, lastInlineRenderedTranslations, lastInlineTranslationKey;
@dynamic lastInlineUnplaceableCount;
// Presentation compatibility
@dynamic analysisRequestGeneration, analyzeButton, chatContextGeneration, chatResolvingSource, currentAnalysis, currentWindowLabel;
@dynamic displayedSentenceID, displayedSourceText, displayedTranslation, displayedVersion, expandedWordCards, followLatestButton;
@dynamic followupRequestGeneration, framePreview, grammarActions, grammarAnalysisError, grammarBackToSourceButton, grammarBookmarkListLabel;
@dynamic grammarBookmarkPopup, grammarBookmarkStack, grammarBookmarks, grammarDetailBodyLabel, grammarDetailBookmarkButton, grammarDetailFields;
@dynamic grammarDetailLevelLabel, grammarDetailNameLabel, grammarEmptyAnalyzeButton, grammarEmptyHint, grammarEmptyPane, grammarEmptyTitle;
@dynamic grammarExampleLabel, grammarExamplesPane, grammarExpandButton, grammarExpandedLabel, grammarFollowupControls, grammarFollowupDisclosure;
@dynamic grammarFollowupResultLabel, grammarFollowupStack, grammarFollowupToggle, grammarOtherEmptyLabel, grammarOtherStack, grammarPageAnalyzeButton;
@dynamic grammarPinnedLabel, grammarPointsPane, grammarQuestionField, grammarReferenceNote, grammarResultsLabel, grammarReviewButton;
@dynamic grammarSelector, grammarSourceLabel, grammarSourceLinkButton, grammarSourceTextView, grammarStatusLabel, grammarStructureCard;
@dynamic grammarTabButtons, grammarTabRow, grammarTabUnderlines, grammarUsageBlock, headerDescriptionLabel, headerTitleLabel;
@dynamic historyListStack, historyPopup, historyRecords, inlineBlockSnapshot, inlineReturnButton, inlineReturnSnapshot;
@dynamic inlineReturnSourceText, inlineTranslationListCard, inlineTranslationListCount, inlineTranslationListSignature, inlineTranslationListSnapshots, inlineTranslationListStack;
@dynamic knownButton, latestSourceLabel, latestTranslationLabel, learningAnalysisBusy, learningCollectionCount, learningCollectionHost;
@dynamic learningCollectionIndex, learningCollectionSections, learningCollectionTabs, learningCollectionTitle, learningPageHost, learningPinnedLabel;
@dynamic learningSourceTextView, learningTranslationLabel, lemmaField, liveChipAutoTranslate, liveChipPauseFollow, liveChipRecognition;
@dynamic liveErrorLabel, liveLevelTag, liveScreenDialogueLabel, liveScreenSpeakerLabel, liveSourceEmptyLabel, liveSourceSelectionHintLabel;
@dynamic mainChatToggle, mainChatWantsVisible, mainChatWidth, mainStructureButtons, mainStructureScrollView, mainStudyChatView;
@dynamic mainWindow, mainWindowContentWidth, mainWindowMinimumWidth, mainWindowVisibleBeforeRegionSelection, mainWorkspaceRoot, meaningField;
@dynamic notYetButton, ocrDurationLabel, overlayStudyChatView, pageButtons, pages, pinSentenceButton;
@dynamic previewAspectConstraint, previewPlaceholder, quickAnalysisGeneration, quickGrammarActions, quickGrammarBookmarkButton, quickGrammarBookmarkPending;
@dynamic quickGrammarBookmarkStatus, quickGrammarChoices, quickGrammarDetailCard, quickGrammarExpandButton, quickGrammarReviewButton, quickGrammarReviewStatus;
@dynamic quickGrammarStack, quickSelectedGrammarButton, quickSelectedGrammarIndex, quickSentenceAnalysis, quickSentenceAnalysisError, quickSentenceAnalysisSource;
@dynamic quickSentenceAnalysisTranslation, quickSentenceAnalyzer, quickSentenceAnalyzing, quickSentenceBookmarkButton, quickSentenceGeneration, quickSentenceID;
@dynamic quickSentenceIsInlineBlock, quickSentencePanel, quickSentenceRequested, quickSentenceScrollOffset, quickSentenceSource, quickSentenceTranslation;
@dynamic quickSentenceVersion, quickSourceHoverGeneration, quickSourceTextView, quickStructureButtons, quickStructureScrollView, readingField;
@dynamic referenceActiveWord, referenceCard, referenceDetailStack, referenceDictionary, referenceEntryPopup, referenceMoreExamples;
@dynamic referenceRecords, referenceRequestGeneration, referenceSearchField, referenceSensePopup, referenceStack, referenceTabs;
@dynamic revealButton, revealedMeanings, reviewIndex, reviewList, reviewMeaningLabel, reviewPromptLabel;
@dynamic reviewWordLabel, reviewingEntry, runButton, runStateLabel, savedGrammarCardStack, savedSentenceStack;
@dynamic savedSentences, savingVocabulary, selectedGrammarIndex, selectedGrammarTab, selectedPage, sentenceBookmarkPending;
@dynamic sentenceInsightLabel, sentenceInsightStack, sentenceStructureStack, sourceHoverCache, sourceHoverGeneration, sourceHoverSuspended;
@dynamic sourceReadingHeight, sourceReadingMinimumHeight, statusLabel, studyChatOverlayRequested, studyChatPanel, studyChatSession;
@dynamic translationCountLabel, translationDurationLabel, translationReadingMinimumHeight, vocabCompletionFromAI, vocabSelectionGeneration, vocabularyEmptyCard;
@dynamic vocabularyExamplesLabel, vocabularyExamplesList, vocabularyExamplesPopup, vocabularyListLabel, vocabularySelectionLabel, vocabularyStatusLabel;
@dynamic wordCardStack, wordCardsGeneration, wordExampleIndices, wordPickArea, wordPickSurfaceLabel, workspaceWidth;
// Settings compatibility
@dynamic credentialLoadFailed, diagnosticMailService, diagnosticStatusLabel, exportingDiagnostics, lastDiagnosticCheckDate, loadingSettings;
@dynamic persistedAPIKey, saveTimer, serviceTestGeneration, serviceTestTaskOwner;

#pragma mark - Capture and translation runtime ownership

- (FYTranslationRuntimeController *)translationRuntimeController {
    if (!_translationRuntimeController) { _translationRuntimeController = [[FYTranslationRuntimeController alloc] initWithHost:self]; }
    return _translationRuntimeController;
}

- (FYCaptureRuntimeController *)captureRuntimeController {
    if (!_captureRuntimeController) { _captureRuntimeController = [[FYCaptureRuntimeController alloc] initWithHost:self]; }
    return _captureRuntimeController;
}

#pragma mark - Subtitle and inline overlay ownership

- (FYSubtitlePresenter *)subtitlePresenter {
    if (!_subtitlePresenter) { _subtitlePresenter = [[FYSubtitlePresenter alloc] initWithHost:self]; }
    return _subtitlePresenter;
}

- (FYInlineOverlayController *)inlineOverlayController {
    if (!_inlineOverlayController) { _inlineOverlayController = [[FYInlineOverlayController alloc] initWithHost:self]; }
    return _inlineOverlayController;
}

#pragma mark - Presentation controller ownership and compatibility actions

- (FYMainWindowController *)mainWindowController {
    if (!_mainWindowController) { _mainWindowController = [[FYMainWindowController alloc] initWithHost:self]; }
    return _mainWindowController;
}

- (FYCollectionController *)collectionController {
    if (!_collectionController) { _collectionController = [[FYCollectionController alloc] initWithHost:self]; }
    return _collectionController;
}

- (FYGrammarPresentationController *)grammarPresentationController {
    if (!_grammarPresentationController) { _grammarPresentationController = [[FYGrammarPresentationController alloc] initWithHost:self]; }
    return _grammarPresentationController;
}

- (FYStudyPresentationController *)studyPresentationController {
    if (!_studyPresentationController) { _studyPresentationController = [[FYStudyPresentationController alloc] initWithHost:self]; }
    return _studyPresentationController;
}

- (FYReferencePresentationController *)referencePresentationController {
    if (!_referencePresentationController) { _referencePresentationController = [[FYReferencePresentationController alloc] initWithHost:self]; }
    return _referencePresentationController;
}

#pragma mark - Extracted settings and diagnostics owners

- (FYSettingsStore *)settingsStore {
    if (!_settingsStore) { _settingsStore = [[FYSettingsStore alloc] initWithDefaults:(id)NSUserDefaults.standardUserDefaults]; }
    return _settingsStore;
}
- (FYTranslationConfiguration *)translationConfiguration {
    return [[FYTranslationConfiguration alloc] initWithBaseURL:self.baseURLField.stringValue model:self.modelField.stringValue
        learningModel:self.learningModelField.stringValue apiKey:self.apiKeyField.stringValue];
}
- (FYServiceTestController *)serviceTestController {
    if (!_serviceTestController) { _serviceTestController = [FYServiceTestController new]; }
    return _serviceTestController;
}
- (FYDiagnosticsController *)diagnosticsController {
    if (!_diagnosticsController) {
        _diagnosticsController = [FYDiagnosticsController new];
        __weak typeof(self) weakSelf = self;
        _diagnosticsController.statusHandler = ^(NSString *status) { [weakSelf setStatus:status]; };
    }
    return _diagnosticsController;
}

// 贴译相关的可变状态在 init 里就建好：既可以由 applicationDidFinishLaunching 复用，
// 也让「直接 alloc/init 的 AppDelegate」（隔离测试、命令行工具）不会拿到 nil 字典。

- (void)createApplicationMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *applicationItem = [[NSMenuItem alloc] initWithTitle:@"译芽" action:nil keyEquivalent:@""];
    NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@"译芽"];
#ifdef FY_ENABLE_UPDATES
    self.appUpdater = [FYAppUpdater new];
    [self.appUpdater addItemsToApplicationMenu:applicationMenu];
#endif
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出译芽" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    quit.target = NSApp;
    [applicationMenu addItem:quit];
    applicationItem.submenu = applicationMenu;
    [mainMenu addItem:applicationItem];
    NSMenuItem *editItem=[[NSMenuItem alloc] initWithTitle:@"编辑" action:nil keyEquivalent:@""];
    NSMenu *editMenu=[[NSMenu alloc] initWithTitle:@"编辑"];
    for(NSArray *command in @[@[@"撤销",@"undo:",@"z"],@[@"重做",@"redo:",@"Z"],@[@"剪切",@"cut:",@"x"],@[@"复制",@"copy:",@"c"],@[@"粘贴",@"paste:",@"v"],@[@"全选",@"selectAll:",@"a"]]){
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:command[0] action:NSSelectorFromString(command[1]) keyEquivalent:command[2]];
        item.keyEquivalentModifierMask=NSEventModifierFlagCommand; // nil target routes to the focused editor.
        [editMenu addItem:item];
    }
    editItem.submenu=editMenu;[mainMenu addItem:editItem];
    NSApp.mainMenu = mainMenu;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    FYRemoveOwnedLegacyDiagnosticFiles();
    self.globalShortcuts=[FYGlobalShortcuts new];
    __weak typeof(self) shortcutOwner=self;
    self.globalShortcuts.onAction=^(NSInteger action){
        typeof(self) owner=shortcutOwner;if(![owner translationTargetIsForeground]){return;}
        if(action==1){[owner toggleCaptionCollapsed:nil];}
        else if(action==2){owner.quickSentenceRequested?[owner closeStudyOverlay:nil]:[owner showQuickSentence:nil];}
        else if(action==3){owner.studyChatOverlayRequested?[owner closeStudyOverlay:nil]:[owner showStudyChatOverlay:nil];}
    };
    [self.globalShortcuts start];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self createApplicationMenu];
    self.windows = [NSMutableArray array];
    self.inlineTranslationPanels = [NSMutableArray array];
    self.inlineLongCardPanels = [NSMutableArray array];
    self.inlinePanelsByBlockID = [NSMutableDictionary dictionary];
    self.inlineManualOffsets = [NSMutableDictionary dictionary];
    self.inlineManualOffsetAge = [NSMutableDictionary dictionary];
    self.inlineStableBlockIDs = [NSMutableDictionary dictionary];
    self.inlineTranslationCache = [NSMutableDictionary dictionary];
    self.inlineFrameStabilizer = [FYInlineOCRFrameStabilizer new];
    self.lastTranslatedNormalizedText = @"";
    self.lastSubmittedNormalizedText = @"";
    self.stableCandidate = @"";

    [self createMainWindow];
    [self createCaptionWindow];
    [self loadSettings];
    [self setupLearning];
    [self refreshWindows:nil];
    [self updateCaptionWindowWithText:@"" status:@"已暂停"];

    [self.mainWindow makeKeyAndOrderFront:nil];
    [self updateMainChatForWindowWidth];
    NSNotificationCenter *workspaceCenter = NSWorkspace.sharedWorkspace.notificationCenter;
    for (NSString *name in @[NSWorkspaceDidActivateApplicationNotification, NSWorkspaceDidHideApplicationNotification, NSWorkspaceActiveSpaceDidChangeNotification]) {
        [workspaceCenter addObserver:self selector:@selector(refreshOverlayVisibility:) name:name object:nil];
    }
    self.overlayVisibilityTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refreshOverlayVisibility:) userInfo:nil repeats:YES];
    [self refreshOverlayVisibility:nil];
    [NSApp activateIgnoringOtherApps:YES];
#ifdef FY_ENABLE_UPDATES
    [self.appUpdater start];
#endif
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    if (!visible) {
        [self.mainWindow makeKeyAndOrderFront:nil];
        FYCrashLifecycle(@"reopened-window");
    }
    return YES;
}

#pragma mark - Learning setup

- (NSURL *)learningCatalogURL {
    return [[NSBundle mainBundle] URLForResource:@"grammar-catalog" withExtension:@"json" subdirectory:@"learning"];
}

- (void)setupLearning {
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *directory = [appSupport stringByAppendingPathComponent:@"com.nanami.fuyi"];
    NSString *databasePath = [directory stringByAppendingPathComponent:@"learning.sqlite3"];
    self.learningStore = [[FYLearningStore alloc] initWithDatabasePath:databasePath];
    [self.learningStore configureHistoryRetentionWithLimit:FYRecentSentenceLimit completion:^(NSError *error) {
        if (error) { self.grammarStatusLabel.stringValue = [NSString stringWithFormat:@"清理历史台词失败：%@", error.localizedDescription]; }
    }];
    [self.learningStore openWithCompletion:^(NSError *error) {
        if (error) { self.grammarStatusLabel.stringValue = [NSString stringWithFormat:@"学习数据库打开失败：%@", error.localizedDescription]; }
    }];

    self.learningAnalyzer = [[FYLearningAnalyzer alloc] init];
    [self syncLearningAnalyzerConfig];

    self.grammarCatalog = [[FYGrammarCatalog alloc] initWithURL:[self learningCatalogURL]];
    NSError *catalogError = nil;
    if (![self.grammarCatalog loadWithError:&catalogError]) {
        self.grammarStatusLabel.stringValue = [NSString stringWithFormat:@"等级资料加载失败：%@", catalogError.localizedDescription];
    }
    self.learningAnalyzer.catalog = self.grammarCatalog;

    self.japaneseTokenizer = [[FYJapaneseTokenizer alloc] init];
    self.learningCoordinator = [[FYLearningCoordinator alloc] initWithStore:self.learningStore
                                                                  analyzer:self.learningAnalyzer
                                                                 tokenizer:self.japaneseTokenizer
                                                                   catalog:self.grammarCatalog];
    __weak typeof(self) weakSelf = self;
    self.learningCoordinator.persistenceErrorHandler = ^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.grammarStatusLabel.stringValue = [NSString stringWithFormat:@"学习记录保存失败：%@", error.localizedDescription];
        });
    };
    self.learningCoordinator.learningEnabled = YES;
    [self refreshHistory];
    [self refreshVocabularyList];
    [self refreshGrammarBookmarks:nil];
}

- (void)syncLearningAnalyzerConfig {
    FYTranslationConfiguration *config = [self translationConfiguration];
    self.learningAnalyzer.baseURL = config.baseURL;
    self.learningAnalyzer.apiKey = config.apiKey;
    NSString *learningModel = Trim(config.learningModel);
    if (learningModel.length == 0) { learningModel = Trim(config.model); }
    self.learningAnalyzer.model = learningModel;
}

- (NSString *)bundledLicenseNotes {
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"LICENSE-NOTES" withExtension:@"txt" subdirectory:@"learning"];
    if (!url) {
        return @"未找到随包的资料说明文件（App 未正确打包 resources/learning）。";
    }
    NSError *readError = nil;
    NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&readError];
    if (!text) { return @"无法读取资料说明文件，请重新安装译芽。"; }
    return text.length > 0 ? text : @"资料说明文件为空。";
}

- (NSScrollView *)makeLicenseNotesView {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,560,240)];
    scroll.identifier = @"reference-license-notes";
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.borderType = NSNoBorder;
    scroll.backgroundColor = FYAdventureColor(@"panel");
    NSTextView *text = [[NSTextView alloc] initWithFrame:scroll.contentView.bounds];
    text.editable = NO;
    text.selectable = YES;
    text.font = FYUIFont(13, NSFontWeightRegular);
    text.textColor = FYAdventureColor(@"ink");
    text.backgroundColor = scroll.backgroundColor;
    text.textContainerInset = NSMakeSize(12,12);
    text.minSize = NSMakeSize(0,0);
    text.maxSize = NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX);
    text.verticallyResizable = YES;
    text.horizontallyResizable = NO;
    text.autoresizingMask = NSViewWidthSizable;
    text.textContainer.containerSize = NSMakeSize(NSWidth(scroll.contentView.bounds),CGFLOAT_MAX);
    text.textContainer.widthTracksTextView = YES;
    text.accessibilityLabel = @"资料来源与许可正文";
    scroll.documentView = text;
    text.string = [self bundledLicenseNotes];
    [scroll.heightAnchor constraintEqualToConstant:240].active = YES;
    return scroll;
}

#pragma mark - UI

// 「界面译文」集中查看：画面里放不下的贴译（暂不可放置 / 改用紧凑入口）在这里全部列出，
// 每条保留原文、完整译文与稳定块身份，并可一键打开该块的原文与语法。
// 没有需要集中查看的内容时整张卡片隐藏，不影响正常画面与截图。

// 重建集中查看列表。签名相同就不重建，避免每帧重排整页。

- (NSView *)makeRunSettingsPage {
    NSStackView *page = [self verticalStack];
    page.spacing = 14;
    NSStackView *settings = [self verticalStack];
    settings.spacing = 10;
    [settings addArrangedSubview:[self cardTitle:@"识别与画面来源"]];
    [settings addArrangedSubview:[self recognitionCard]];
    [settings addArrangedSubview:[self windowCard]];
    [page addArrangedSubview:[self cardWithStack:settings]];

    NSStackView *status = [self verticalStack];
    [status addArrangedSubview:[self cardTitle:@"运行状态"]];
    self.statusLabel = [self label:@"已暂停" font:FYUIFont(12, NSFontWeightRegular) color:self.uiMuted];
    self.statusLabel.maximumNumberOfLines = 2;
    [status addArrangedSubview:self.statusLabel];
    [status addArrangedSubview:self.ocrDurationLabel];
    [status addArrangedSubview:self.translationDurationLabel];
    [status addArrangedSubview:self.translationCountLabel];
    [status addArrangedSubview:[self separator]];
    [status addArrangedSubview:[self permissionControls]];
    [page addArrangedSubview:[self cardWithStack:status]];
    [page addArrangedSubview:[self cardWithStack:(NSStackView *)[self diagnosticControls]]];
    return page;
}

#include "../FYAppearanceUI.inc"

- (void)focusWindowSelection:(id)sender {
    [self selectPageAtIndex:3];
    [self.mainWindow makeFirstResponder:self.windowPopup];
    [self.windowPopup performClick:nil];
}

#include "../FYWorkspaceUI.inc"

#pragma mark - Learning actions

// 切句时清理旧分析、旧高亮、旧语法列表与旧追问内容。

// 局部更新选中态：结构图节点高亮、左侧语法列表高亮、详情、原文命中高亮。
// 不触碰结构图本身，所以横向滚动位置、页面纵向位置都保持不动；被点的节点原地不动（已可见就不动）。

// 结构图的横向偏移：重建前后用它保持位置（有效范围由文档宽度约束）。

// 展示用：把 OCR 文本里单独占一行的说话人名字拆出来，不改动用于选择/收藏的原文。

// 等级标签只取语法点自带的可核实参考等级；没有就隐藏，不编造整句等级。

- (void)clearArrangedSubviews:(NSStackView *)stack {
    for (NSView *view in stack.arrangedSubviews.copy) {
        [stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}

#pragma mark - 收藏管理（语法收藏 / 词条例句）

- (NSArray<NSString *> *)textsFromItems:(NSArray<OCRTextItem *> *)items {
    NSMutableArray<NSString *> *texts = [NSMutableArray arrayWithCapacity:items.count];
    for (OCRTextItem *item in items) {
        [texts addObject:item.text ?: @""];
    }
    return texts;
}

- (void)bindTranslations:(NSArray<NSString *> *)translations toIdentities:(NSArray<FYRequestIdentity *> *)identities {
    if (!translations || translations.count == 0) { return; }
    NSUInteger count = MIN(translations.count, identities.count);
    for (NSUInteger index = 0; index < count; index++) {
        FYRequestIdentity *identity = identities[index];
        NSString *translation = translations[index];
        if (identity && identity.sentenceID.length > 0 && translation.length > 0) {
            [self.learningCoordinator setTranslation:translation forIdentity:identity];
        }
    }
}

- (void)selectCaptionSwatch:(NSButton *)sender {
    self.captionTextColorCustomized = NO;
    self.captionThemeControl.selectedSegment = sender.tag;
    [self controlValueChanged:self.captionThemeControl];
}

- (void)resetCaptionTextColor:(id)sender {
    self.captionTextColorCustomized = NO;
    self.captionTextColorWell.color = [self captionThemeTextColor];
    [self controlValueChanged:self.captionThemeControl];
}

- (void)updateThemeSummary {
    self.themeSummaryLabel.stringValue = [NSString stringWithFormat:@"%.0f pt / %.0f%%",
                                           self.captionFontSizeSlider.doubleValue,
                                           self.captionOpacitySlider.doubleValue * 100];
    [self updateSubtitleAppearancePage];
}

- (NSView *)permissionControls {
    // 只有一个入口：先本机检查，缺哪个权限就打开对应的系统设置页。
    NSStackView *stack = [self verticalStack];
    [stack addArrangedSubview:[self label:@"权限" font:FYUIFont(15, NSFontWeightBold) color:[NSColor labelColor]]];
    __weak typeof(self) weakSelf = self;
    NSButton *oneButton = [NSButton buttonWithTitle:@"检查并打开权限设置" target:self action:@selector(openPermissionSettings:)];
    oneButton.bezelStyle = NSBezelStyleRounded;
    (void)weakSelf;
    [stack addArrangedSubview:oneButton];
    self.permissionStatusLabel = [self mutedLabel:@""];
    [stack addArrangedSubview:self.permissionStatusLabel];
    return stack;
}

// 单一权限入口：检测屏幕录制（采集卡模式下再看相机），打开需要处理的那一页。
- (void)openPermissionSettings:(id)sender {
    BOOL screenOK = [self hasScreenAccess];
    FYCaptureCardAvailability camera = [[FYCaptureCardInput new] availability];
    BOOL cameraNeeded = [self captureCardInputEnabled];
    NSString *state = [NSString stringWithFormat:@"屏幕录制：%@%@", screenOK ? @"已授权" : @"未授权",
                       cameraNeeded ? [NSString stringWithFormat:@" · 相机：%@", FYCaptureCardAvailabilityLabel(camera)] : @""];
    self.permissionStatusLabel.stringValue = state;
    [self setStatus:state];
    NSURL *url = nil;
    if (!screenOK) {
        url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"];
    } else if (cameraNeeded && camera != FYCaptureCardAvailabilityAuthorized) {
        url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"];
    }
    if (url) { [NSWorkspace.sharedWorkspace openURL:url]; }
}

- (NSView *)recognitionCard {
    NSStackView *stack = [self verticalStack];
    [stack addArrangedSubview:[self label:@"识别方式" font:FYUIFont(15, NSFontWeightBold) color:[NSColor labelColor]]];

    self.languageControl = [self segmentedWithLabels:@[@"日语", @"英语"] action:@selector(controlValueChanged:)];

    [stack addArrangedSubview:[self settingsRowWithLabel:@"原文语言" view:self.languageControl]];
    return stack;
}

- (NSView *)windowCard {
    NSStackView *stack = [self verticalStack];
    [stack addArrangedSubview:[self separator]];
    [stack addArrangedSubview:[self label:@"画面来源" font:FYUIFont(15, NSFontWeightBold) color:[NSColor labelColor]]];

    // —— 识别输入源：OCR 从哪里取画面 ——
    self.inputSourceControl = [self segmentedWithLabels:@[@"窗口截图", @"采集卡"] action:@selector(inputSourceChanged:)];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"识别输入源" view:self.inputSourceControl]];
    self.inputSourceHintLabel = [self mutedLabel:@""];
    self.inputSourceHintLabel.maximumNumberOfLines = 3;
    self.inputSourceHintLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [stack addArrangedSubview:self.inputSourceHintLabel];

    // 采集卡专属控件整块收在一个容器里：窗口截图模式下整块隐藏，不再一次摊开"一坨"。
    NSStackView *captureControls = [self verticalStack];
    captureControls.spacing = 8;
    NSStackView *deviceRow = [self horizontalStack];
    self.captureDevicePopup = [[NSPopUpButton alloc] init];
    self.captureDevicePopup.target = self;
    self.captureDevicePopup.action = @selector(captureDeviceChanged:);
    [self.captureDevicePopup addItemWithTitle:@"点「刷新设备」检测采集卡"];
    self.captureDevicePopup.enabled = NO;
    NSButton *refreshDevicesButton = [NSButton buttonWithTitle:@"刷新设备" target:self action:@selector(refreshCaptureDevices:)];
    refreshDevicesButton.bezelStyle = NSBezelStyleRounded;
    NSButton *reconnectCaptureButton = [NSButton buttonWithTitle:@"重连采集卡" target:self action:@selector(reconnectCaptureDevice:)];
    reconnectCaptureButton.bezelStyle = NSBezelStyleRounded;
    [deviceRow addArrangedSubview:self.captureDevicePopup];
    [deviceRow addArrangedSubview:refreshDevicesButton];
    [deviceRow addArrangedSubview:reconnectCaptureButton];
    [captureControls addArrangedSubview:[self settingsRowWithLabel:@"采集卡设备" view:deviceRow]];

    self.captureStatusLabel = [self mutedLabel:@"采集卡未启动"];
    self.captureStatusLabel.maximumNumberOfLines = 4;
    self.captureStatusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [captureControls addArrangedSubview:self.captureStatusLabel];

    // —— 画面区域校准：真正决定「视频像素 → 屏幕」映射的就是这里框选的结果 ——
    NSStackView *calibrationRow = [self horizontalStack];
    self.captureCalibrateButton = [NSButton buttonWithTitle:@"调整贴译位置" target:self action:@selector(beginCaptureCardCalibration:)];
    self.captureCalibrateButton.bezelStyle = NSBezelStyleRounded;
    self.captureCalibrateClearButton = [NSButton buttonWithTitle:@"恢复自动定位" target:self action:@selector(clearCaptureCardCalibration:)];
    self.captureCalibrateClearButton.bezelStyle = NSBezelStyleRounded;
    [calibrationRow addArrangedSubview:self.captureCalibrateButton];
    [calibrationRow addArrangedSubview:self.captureCalibrateClearButton];
    [captureControls addArrangedSubview:[self settingsRowWithLabel:@"贴译位置" view:calibrationRow]];
    self.captureCalibrationLabel = [self mutedLabel:@""];
    self.captureCalibrationLabel.maximumNumberOfLines = 3;
    self.captureCalibrationLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [captureControls addArrangedSubview:self.captureCalibrationLabel];
    // 只有"已被明确拒绝"时系统才不会再次弹窗，这时才需要这个手动入口。
    self.captureSettingsButton = [NSButton buttonWithTitle:@"打开相机权限设置" target:self action:@selector(openCameraAccessSettings:)];
    self.captureSettingsButton.bezelStyle = NSBezelStyleRounded;
    NSStackView *settingsRow = [self horizontalStack];
    [settingsRow addArrangedSubview:self.captureSettingsButton];
    [captureControls addArrangedSubview:settingsRow];
    self.captureSettingsButton.hidden = YES;

    NSStackView *captureNotes = [self verticalStack];
    captureNotes.spacing = 4;
    [captureNotes addArrangedSubview:[self mutedLabel:@"只读取视频，不使用麦克风，也不采集屏幕音频。"]];
    [captureNotes addArrangedSubview:[self mutedLabel:@"不会自动改用内置或手机摄像头；设备不存在、被占用或权限被拒绝时会明确提示。"]];
    [captureNotes addArrangedSubview:[self mutedLabel:@"界面文字会按采集画面在目标窗口里的实际显示区域原位贴译；自动定位不到时可用「调整贴译位置」手动框一次。"]];
    self.captureCardControlsView = captureControls;
    [stack addArrangedSubview:captureControls];

    [stack addArrangedSubview:[self separator]];
    // 这个选择的**用途**随识别输入源变化：采集卡模式下它只决定译文跟随谁；
    // 窗口截图模式下它同时决定 OCR 从哪个窗口取画面。名称与说明必须跟着变，
    // 不能一概叫「字幕显示窗口」（用户看不出和上面采集来源的区别）。
    self.windowCardTitleLabel = [self label:@"要翻译的窗口" font:FYUIFont(15, NSFontWeightBold) color:[NSColor labelColor]];
    [stack addArrangedSubview:self.windowCardTitleLabel];

    NSStackView *windowRow = [self horizontalStack];
    self.windowPopup = [[NSPopUpButton alloc] init];
    self.windowPopup.target = self;
    self.windowPopup.action = @selector(windowSelectionChanged:);
    // 这一行现在有三个控件（下拉 + 刷新 + 显示全部）：必须允许它们横向压缩，
    // 否则窄窗口下这一行的最小宽度会把整个窗口顶宽（PreviewLayoutTests 抓到的回归）。
    [self.windowPopup.widthAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;
    [self.windowPopup setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSButton *refreshButton = [NSButton buttonWithTitle:@"刷新窗口" target:self action:@selector(refreshWindows:)];
    refreshButton.bezelStyle = NSBezelStyleRounded;
    [refreshButton setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.windowScopeButton = [NSButton buttonWithTitle:@"显示全部窗口" target:self action:@selector(toggleWindowListScope:)];
    self.windowScopeButton.bezelStyle = NSBezelStyleRounded;
    [self.windowScopeButton setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    [windowRow addArrangedSubview:self.windowPopup];
    [windowRow addArrangedSubview:refreshButton];
    [windowRow addArrangedSubview:self.windowScopeButton];
    [stack addArrangedSubview:[self settingsRowWithLabel:@"窗口" view:windowRow]];
    self.windowCardHintLabel = [self mutedLabel:@"这个窗口既是识别画面的来源，也是字幕和贴译跟随的位置；换窗口会重新识别。"];
    self.windowCardHintLabel.maximumNumberOfLines = 3;
    self.windowCardHintLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [stack addArrangedSubview:self.windowCardHintLabel];
    self.windowCardNoteLabel = [self mutedLabel:@""];
    self.windowCardNoteLabel.maximumNumberOfLines = 3;
    self.windowCardNoteLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [stack addArrangedSubview:self.windowCardNoteLabel];

    self.manualOCRScopeCheckbox=[NSButton checkboxWithTitle:@"仅翻译手动框选区域（默认关闭）" target:self action:@selector(controlValueChanged:)];
    self.manualOCRScopeCheckbox.state=NSControlStateValueOff;
    [stack addArrangedSubview:self.manualOCRScopeCheckbox];
    NSTextField *scopeHint=[self mutedLabel:@"关闭时自动识别整画面；开启后实时翻译和当前界面只读框内。这不是视频画面校准。"];
    scopeHint.maximumNumberOfLines=0;
    [stack addArrangedSubview:scopeHint];
    NSStackView *regionButtonRow = [self verticalStack];
    [regionButtonRow addArrangedSubview:[NSButton buttonWithTitle:@"手动框选 OCR 区域" target:self action:@selector(selectOCRRegion:)]];
    [regionButtonRow addArrangedSubview:[NSButton buttonWithTitle:@"显示 OCR 框" target:self action:@selector(showOCRPreview:)]];
    [regionButtonRow addArrangedSubview:[NSButton buttonWithTitle:@"隐藏 OCR 框" target:self action:@selector(hideOCRPreview:)]];
    NSStackView *advanced = [self verticalStack];
    [advanced addArrangedSubview:regionButtonRow];

    self.regionXSlider = [self sliderWithMin:0 max:1 value:0.05 action:@selector(controlValueChanged:)];
    self.regionYSlider = [self sliderWithMin:0 max:1 value:0.52 action:@selector(controlValueChanged:)];
    self.regionWidthSlider = [self sliderWithMin:0.05 max:1 value:0.90 action:@selector(controlValueChanged:)];
    self.regionHeightSlider = [self sliderWithMin:0.05 max:1 value:0.42 action:@selector(controlValueChanged:)];

    // 框选之后可以用这四个滑块微调；比例值以窗口左上角为原点
    NSStackView *fineTuneRow = [self verticalStack];
    NSArray<NSString *> *fineTuneNames = @[@"X", @"Y", @"宽", @"高"];
    NSArray<NSSlider *> *fineTuneSliders = @[self.regionXSlider, self.regionYSlider, self.regionWidthSlider, self.regionHeightSlider];
    for (NSUInteger index = 0; index < fineTuneSliders.count; index++) {
        NSSlider *slider = fineTuneSliders[index];
        slider.controlSize = NSControlSizeSmall;
        [fineTuneRow addArrangedSubview:[self settingsRowWithLabel:fineTuneNames[index] view:slider]];
    }
    [advanced addArrangedSubview:[self settingsRowWithLabel:@"区域微调" view:fineTuneRow]];

    NSStackView *regionPresetRow = [self horizontalStack];
    [regionPresetRow addArrangedSubview:[NSButton buttonWithTitle:@"底部字幕" target:self action:@selector(useDefaultSubtitleRegion:)]];
    [regionPresetRow addArrangedSubview:[NSButton buttonWithTitle:@"大字幕" target:self action:@selector(useLargeSubtitleRegion:)]];
    [regionPresetRow addArrangedSubview:[NSButton buttonWithTitle:@"整窗" target:self action:@selector(useFullWindowRegion:)]];
    [regionPresetRow addArrangedSubview:[NSButton buttonWithTitle:@"界面全文" target:self action:@selector(useInterfaceFullWindowPreset:)]];
    [advanced addArrangedSubview:regionPresetRow];
    [stack addArrangedSubview:[self disclosureWithTitle:@"调整识别区域" content:advanced]];
    return stack;
}

- (NSView *)translationCard {
    FYTranslationServiceView *service=[[FYTranslationServiceView alloc] initWithLicenseView:[self makeLicenseNotesView]];
    self.translationServiceView=service;
    // Runtime adapters retain the same native fields used by persistence and tests.
    self.baseURLField=service.baseURLField; self.modelField=service.modelField;
    self.apiKeyField=service.apiKeyField; self.learningModelField=service.learningModelField;
    self.serviceTestPresentation=service.testPresentation;
    self.serviceTestButton=service.testPresentation.button; self.serviceStatusIcon=service.testPresentation.icon;
    self.serviceStatusLabel=service.testPresentation.statusLabel; self.serviceTestModelLabel=service.testPresentation.modelLabel;
    self.serviceTestMessageLabel=service.testPresentation.messageLabel; self.serviceErrorLabel=service.testPresentation.errorLabel;
    self.serviceTestResultLabel=service.testPresentation.resultLabel; self.serviceTestResultPanel=service.testPresentation.panel;
    __weak AppDelegate *weakSelf=self;
    service.onSettingsChanged=^{ [weakSelf serviceSettingsChanged]; };
    service.onTextChanged=^(NSNotification *notification){ [weakSelf controlTextDidChange:notification]; };
    service.onEditingEnded=^(NSNotification *notification){ [weakSelf controlTextDidEndEditing:notification]; };
    service.onTest=^{ [weakSelf testTranslation:nil]; };
    service.onPasteKey=^{ [weakSelf pasteAPIKeyFromClipboard:nil]; };
    service.onClearKey=^{ [weakSelf clearAPIKey:nil]; };
    service.onShowLicenses=^{ [weakSelf showReferenceLicenses:nil]; };
    [self updateServiceTestModelLabel];
    return service.view;
}

- (NSView *)captionCard {
    self.captionFontSizeSlider = [self sliderWithMin:18 max:56 value:30 action:@selector(controlValueChanged:)];
    self.captionHeightSlider = [self sliderWithMin:120 max:340 value:180 action:@selector(controlValueChanged:)];
    self.captionWidthSlider = [self sliderWithMin:360 max:1200 value:900 action:@selector(controlValueChanged:)];
    self.captionThemeControl = [self segmentedWithLabels:@[@"黑底白字", @"白底黑字", @"粉底深字", @"译芽花境"] action:@selector(controlValueChanged:)];
    self.captionThemeControl.selectedSegment = 3;
    self.captionTextColorWell = [[FYSubtitleColorWell alloc] init];
    self.captionTextColorWell.color = FYAdventureColor(@"ink");
    self.captionTextColorWell.target = self;
    self.captionTextColorWell.action = @selector(controlValueChanged:);
    self.captionTextColorWell.colorWellStyle = NSColorWellStyleMinimal;
    [self.captionTextColorWell.widthAnchor constraintEqualToConstant:48].active = YES;
    [self.captionTextColorWell.heightAnchor constraintEqualToConstant:32].active = YES;
    return [self subtitleAppearanceEditor:NO];
}

- (NSView *)batchCaptionCard {
    self.batchFontSizeSlider = [self sliderWithMin:13 max:30 value:16 action:@selector(controlValueChanged:)];
    self.batchWidthSlider = [self sliderWithMin:240 max:720 value:560 action:@selector(controlValueChanged:)];
    self.batchHeightSlider = [self sliderWithMin:160 max:500 value:330 action:@selector(controlValueChanged:)];
    self.batchTextColorWell = [[FYSubtitleColorWell alloc] init];
    self.batchTextColorWell.color = FYAdventureColor(@"ink");
    self.batchTextColorWell.target = self;
    self.batchTextColorWell.action = @selector(controlValueChanged:);
    self.batchTextColorWell.colorWellStyle = NSColorWellStyleMinimal;
    [self.batchTextColorWell.widthAnchor constraintEqualToConstant:48].active = YES;
    [self.batchTextColorWell.heightAnchor constraintEqualToConstant:32].active = YES;
    self.batchThemeControl = [self segmentedWithLabels:@[@"黑底白字", @"白底黑字", @"粉底深字", @"译芽花境"] action:@selector(controlValueChanged:)];
    self.batchThemeControl.selectedSegment = 3;
    return [self subtitleAppearanceEditor:YES];
}

- (NSStackView *)verticalStack {
    NSStackView *stack = [[FYLearningStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.distribution = NSStackViewDistributionFill;
    [stack setContentHuggingPriority:750 forOrientation:NSLayoutConstraintOrientationVertical];
    return stack;
}

- (NSStackView *)horizontalStack {
    NSStackView *stack = [[FYLearningRowView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.distribution = NSStackViewDistributionFill;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = 10;
    return stack;
}

// Settings use labels above controls so fixed input/action widths do not
// resize the outer window when the AI sidebar leaves a narrow workspace.
- (NSView *)settingsRowWithLabel:(NSString *)label view:(NSView *)view {
    NSStackView *row = [self verticalStack]; row.spacing = 6;
    [row addArrangedSubview:[self label:label font:FYUIFont(13, NSFontWeightRegular) color:[NSColor secondaryLabelColor]]];
    view.accessibilityLabel = label;
    [row addArrangedSubview:view];
    return row;
}

- (NSView *)rowWithLabel:(NSString *)label view:(NSView *)view {
    NSStackView *row = [self horizontalStack];
    NSTextField *labelView = [self label:label font:FYUIFont(13, NSFontWeightRegular) color:[NSColor secondaryLabelColor]];
    [labelView.widthAnchor constraintEqualToConstant:88].active = YES;
    view.accessibilityLabel = label;
    [view.widthAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;
    [view setContentHuggingPriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addArrangedSubview:labelView];
    [row addArrangedSubview:view];
    return row;
}

- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.font = font;
    label.textColor = [color isEqual:NSColor.labelColor] ? FYAdventureColor(@"ink") : [color isEqual:NSColor.secondaryLabelColor] ? FYAdventureColor(@"muted") : color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.maximumNumberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    [label setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

- (NSTextField *)textField:(NSString *)placeholder {
    NSTextField *field = [[NSTextField alloc] init];
    field.placeholderString = placeholder;
    field.font = FYUIFont(13, NSFontWeightRegular);
    field.textColor = FYAdventureColor(@"ink");
    field.target = self;
    field.action = @selector(controlValueChanged:);
    field.delegate = self;
    return field;
}

- (NSView *)disclosureWithTitle:(NSString *)title content:(NSView *)content {
    NSStackView *container = [self verticalStack];
    NSButton *button = [NSButton buttonWithTitle:title target:self action:@selector(toggleDisclosure:)];
    button.bezelStyle = NSBezelStyleRounded;
    [button setButtonType:NSButtonTypePushOnPushOff];
    button.state = NSControlStateValueOff;
    if (!self.disclosureViews) { self.disclosureViews = [NSMutableArray array]; }
    button.tag = self.disclosureViews.count;
    [self.disclosureViews addObject:content];
    content.hidden = YES;
    [container addArrangedSubview:button];
    [container addArrangedSubview:content];
    return container;
}

- (void)toggleDisclosure:(NSButton *)sender {
    NSView *content = self.disclosureViews[sender.tag];
    content.hidden = sender.state != NSControlStateValueOn;
}

- (NSSlider *)sliderWithMin:(double)min max:(double)max value:(double)value action:(SEL)action {
    NSSlider *slider = [NSSlider sliderWithValue:value minValue:min maxValue:max target:self action:action];
    slider.continuous = YES;
    return slider;
}

- (NSSegmentedControl *)segmentedWithLabels:(NSArray<NSString *> *)labels action:(SEL)action {
    NSSegmentedControl *control = [[NSSegmentedControl alloc] init];
    control.segmentCount = labels.count;
    control.segmentStyle = NSSegmentStyleRounded;
    control.trackingMode = NSSegmentSwitchTrackingSelectOne;
    control.target = self;
    control.action = action;
    for (NSInteger i = 0; i < labels.count; i++) {
        [control setLabel:labels[i] forSegment:i];
    }
    control.selectedSegment = 0;
    return control;
}

- (NSView *)spacer {
    NSView *view = [[NSView alloc] init];
    [view setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return view;
}

- (NSView *)separator {
    NSBox *box = [[NSBox alloc] init];
    box.boxType = NSBoxSeparator;
    return box;
}

#pragma mark - UI theme helpers

- (NSColor *)uiInk { return FYAdventureColor(@"ink"); }
- (NSColor *)uiMuted { return FYAdventureColor(@"muted"); }
- (NSColor *)uiBorder { return FYAdventureColor(@"rim"); }
- (NSColor *)uiAccent { return FYAdventureColor(@"teal"); }
- (NSColor *)uiSelected { return FYAdventureColor(@"mint"); }
- (NSColor *)uiSurface { return FYAdventureColor(@"paper"); }

- (NSView *)card {
    FYAdventurePanel *card=[FYAdventurePanel new];
    card.translatesAutoresizingMaskIntoConstraints=NO;
    return card;
}

// 用统一卡片包裹内容，内边距 20。
- (NSView *)cardWithStack:(NSStackView *)stack {
    NSView *card = [self card];
    stack.edgeInsets = NSEdgeInsetsMake(0, 0, 0, 0);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card setContentHuggingPriority:750 forOrientation:NSLayoutConstraintOrientationVertical];
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14]
    ]];
    return card;
}

// 让子视图占满父 stack 的宽度（stack.alignment=Leading 时卡片需要显式拉伸）。
- (void)pinFullWidth:(NSView *)view toStack:(NSStackView *)stack {
    [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}

- (NSTextField *)cardTitle:(NSString *)text {
    return [self label:text font:FYUIFont(17, NSFontWeightSemibold) color:self.uiInk];
}

- (NSTextField *)mutedLabel:(NSString *)text {
    return [self label:text font:FYUIFont(12, NSFontWeightRegular) color:self.uiMuted];
}

#include "../FYDiagnosticsUI.inc"

#pragma mark - Actions

// 目标窗口的所属进程。用 IncludingWindow 查询，**即使目标此刻不在屏幕上也要能查到**：
// OBS 的「全屏预览／预览投影」会把主窗口挤进独立空间，那时按窗口号反查不到所有者，
// 前后台规则就会误判成"目标不在前台"而把字幕窗藏起来。

// 纯策略：什么时候该显示浮窗。
// 原规则要求"选中的那个窗口本身在屏幕上且它的应用在前台"，遇到 OBS 全屏预览/投影时，
// 主窗口被投影窗接管、不再出现在屏幕上的窗口列表里，于是字幕被误隐藏。
// 现在改成：目标应用在前台，且（目标窗口在屏幕上，或该应用在屏幕上还有别的窗口）就算前台。
// 目标应用不在前台、或整个应用没有窗口在屏幕上（切到别的空间／最小化）仍然隐藏。
- (BOOL)targetQualifiesForOverlayWithFrontmostPID:(pid_t)frontPID
                                        targetPID:(pid_t)targetPID
                                   targetOnScreen:(BOOL)targetOnScreen
                         ownerHasOnScreenWindow:(BOOL)ownerHasOnScreenWindow
                            interactingWithOverlay:(BOOL)interactingWithOverlay {
    // 自己正在操作的辅助面板也算在目标上前台，避免点按钮时浮窗自己消失。
    return FYTargetQualifiesForOverlay(frontPID, targetPID, targetOnScreen, ownerHasOnScreenWindow, interactingWithOverlay);
}

// 纯策略：浮窗层级跟随目标应用自己用的最高层级。
// 实测 OBS 的预览/投影窗口在 101（NSPopUpMenuWindowLevel），固定用
// NSFloatingWindowLevel(3) 会被它压住。只按目标应用的窗口取层级，上限 102，
// 不越过系统的屏幕保护/告警层级。
- (NSWindowLevel)overlayLevelForTargetPID:(pid_t)targetPID inWindowList:(NSArray<NSDictionary *> *)windows {
    return FYOverlayLevelForTarget(targetPID, windows);
}

// Visibility is independent of OCR completion: late replies cannot raise overlays above another app.
- (BOOL)translationTargetIsForeground {
    if (![self selectedWindowID]) { return NO; }
    NSArray *visibleWindows = self.overlayWindowSnapshot ?: [self onScreenWindowInfos];
    return [self translationTargetIsForegroundWithWindowList:visibleWindows];
}

- (BOOL)translationTargetIsForegroundWithWindowList:(NSArray<NSDictionary *> *)visibleWindows {
    uint32_t selectedID = [self selectedWindowID];
    if (!selectedID) { return NO; }
    // 可见性也跟着**实际显示目标**走：OBS 切到全屏投影后画面在投影窗口上，
    // 如果继续拿编辑器窗口判断，就会出现"贴译跟过去了、字幕却以为目标不在了"的错配。
    uint32_t windowID = selectedID;
    if (self.displayTargetResolved) {
        if (self.displayTargetAmbiguous || self.resolvedDisplayTargetID == 0) { return NO; }
        windowID = self.resolvedDisplayTargetID;
    }
    pid_t frontPID = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    // Some AppKit controls activate the owner even in an auxiliary panel.
    // Keep explicitly used game panels visible; opening the main app still hides them.
    NSWindow *key = NSApp.keyWindow;
    BOOL interactingWithOverlay = frontPID == getpid() && key.isVisible &&
        (key == self.captionPanel || key == self.captionDockPanel || key == self.studyChatPanel || key == self.quickSentencePanel);
    FYWindowVisibilitySnapshot visibility=FYWindowVisibilityInList(windowID, [self selectedWindowOwnerPID], visibleWindows);
    return [self targetQualifiesForOverlayWithFrontmostPID:frontPID
                                                targetPID:visibility.targetPID
                                           targetOnScreen:visibility.targetOnScreen
                                 ownerHasOnScreenWindow:visibility.ownerHasOnScreenWindow
                                    interactingWithOverlay:interactingWithOverlay];
}

- (void)refreshOverlayVisibility:(id)sender {
    [self refreshPreviewVisibility:nil];
    NSArray *previousWindows = self.overlayWindowSnapshot;
    NSNumber *previousPID = self.overlayOwnerPIDSnapshot;
    self.overlayWindowSnapshot = [self selectedWindowID] ? ([self onScreenWindowInfos] ?: @[]) : @[];
    self.overlayOwnerPIDSnapshot = nil;
    self.overlayOwnerPIDSnapshot = @([self selectedWindowOwnerPID]);
    @try {
    // 0.5 秒一次的几何复核（内部还有 0.4 秒限流）：翻译在途时 OCR 循环不推进，
    // 这条轮询保证"切到全屏投影"能在一拍之内被发现，而不是等下次 OCR 回调。
    // 正在手动框选识别区域时不重排，避免和用户的操作抢面板。
    if (self.running && !self.selectingCaptureRegion) { [self refreshDisplayGeometryIfNeeded:NO]; }
    [self expireInlineOverflowEntryIfNeeded];
    // 仍然走可覆盖的 translationTargetIsForeground（测试沿用同一个接缝）。
    BOOL targetActive = !self.selectingCaptureRegion && [self translationTargetIsForeground];
    NSArray *visibleWindows = self.overlayWindowSnapshot;
    NSWindowLevel overlayLevel = [self overlayLevelForTargetPID:[self selectedWindowOwnerPID] inWindowList:visibleWindows];
    [[FYInlineLayoutDebug shared] refreshVisible:targetActive && !self.inlineGeometryPending level:overlayLevel];
    BOOL showCaption = targetActive && self.captionPanelShownByUser && !self.captionSuppressedForUIMode;
    self.captionPanel.level = showCaption ? overlayLevel : NSNormalWindowLevel;
    if (showCaption) {
        if (!self.captionPanel.isVisible) { [self.captionPanel orderFrontRegardless]; }
    } else if (self.captionPanel.isVisible) { [self.captionPanel orderOut:nil]; }
    BOOL showDock=targetActive && !self.captionPanelShownByUser && !self.captionSuppressedForUIMode;
    self.captionDockPanel.level = overlayLevel;
    if(showDock){
        if(!self.captionDockHasAnchor){[self anchorCaptionDockToCaption];}
        [self.captionDockPanel orderFrontRegardless];
    }else{[self.captionDockPanel orderOut:nil];}
    for(NSPanel *overlay in @[self.studyChatPanel ?: (id)NSNull.null,self.quickSentencePanel ?: (id)NSNull.null]){
        if(![overlay isKindOfClass:NSPanel.class]){continue;}
        overlay.level = overlayLevel;
        BOOL requested=overlay==self.studyChatPanel?self.studyChatOverlayRequested:self.quickSentenceRequested;
        if(targetActive && requested){[overlay orderFrontRegardless];}else{
            if(overlay==self.quickSentencePanel){[self.quickSourceTextView dismissSourceHover];}
            [overlay orderOut:nil];
        }
    }
    NSMutableArray<NSPanel *> *overlays = [[self.inlineTranslationPanels arrayByAddingObjectsFromArray:self.inlineLongCardPanels] mutableCopy];
    if (self.inlineOverflowPanel) { [overlays addObject:self.inlineOverflowPanel]; }
    if (self.inlineOverflowChoicePanel) { [overlays addObject:self.inlineOverflowChoicePanel]; }
    if (self.inlineExpandedReadingPanel) { [overlays addObject:self.inlineExpandedReadingPanel]; }
    // 阅读卡展开期间：其它贴译与折叠入口**保持隐藏**，只留当前展开的那一块
    // （否则每帧的可见性刷新会把它们又排到前面，阅读卡被盖住、遮挡游戏点击）。
    BOOL expanded = self.inlineExpandedReadingPanel != nil;
    for (NSPanel *panel in overlays) {
        panel.level = overlayLevel;
        BOOL hasContent = panel != self.inlineOverflowPanel || self.inlineOverflowCount > 0;
        if (hasContent && !self.inlineGeometryPending && FYOverlayShouldShow(targetActive, expanded, panel == self.inlineExpandedReadingPanel)) {
            if (!panel.isVisible) { [panel orderFrontRegardless]; }
        } else if (panel.isVisible) {
            [panel orderOut:nil];
        }
    }
    } @finally {
        self.overlayWindowSnapshot = previousWindows;
        self.overlayOwnerPIDSnapshot = previousPID;
    }
}

// 界面模式下字幕窗本来就不该显示

// 精简列表：推荐窗口 + **始终保留当前选中的窗口**（浏览器、模拟器也照样保留）。
// 没有推荐窗口时退回全部窗口 —— 绝不给用户一个空的、什么都选不了的列表。

// 菜单项的稳定基础名（不含重复序号）：应用名与标题相同就只留一个，避免「Finder · Finder」。

// 「应用名 · 窗口标题」，同一应用的重复名称补 (2)(3)…，保证每一项都能区分。

// 重建下拉框。核心约束：**按窗口 ID 绑定**，刷新/排序/切换精简↔全部都不改选择，也不自动跳到第一项。

// 精简↔全部只换显示范围：选择按 ID 保留，不触发"换窗口"重置。

// 按 ID 选中某一项（列表必须已经重建过）。找不到就返回 NO，绝不按标题猜。

// 把贴译面板从旧位置收起来（不销毁）：实际显示目标/画面区域变了、或者定位暂时不可用时，
// 绝不能把面板继续留在旧坐标上冒充"跟着走"。

// 几何复核：**和文本有没有变化无关**。
// 「文本未变化」的提前返回分支过去直接 return，把窗口边界检查、映射有效性检查和贴译重排
// 一起跳过了 —— 这就是同一句台词时切到全屏投影、贴译不跟随的根因。
// 成本控制：窗口列表最多 0.4 秒查一次（force=YES 用于用户主动刷新/换窗口），
// 画面区域的定点复核另有 2 秒限流（见 captureCardDisplayRectForWindow:），不做每帧全窗搜索。

// 窗口选择卡片的文案随「识别输入源」变化：
//   · 采集卡：这里只决定译文跟随谁 → 「游戏画面所在窗口」
//   · 窗口截图：这里同时决定 OCR 从哪取画面 → 「要翻译的窗口」
// 两者不能共用一个含糊的「字幕显示窗口」，否则用户分不清采集设备与显示窗口。

#pragma mark - 采集卡输入

// 相机权限按需申请：已授权直接继续；尚未决定时弹一次系统提示；已被拒绝只提示设置入口。
// 仍然由用户点击「开始翻译／重连采集卡」触发，不会在启动或空闲时自己弹窗。

// 采集卡模式下界面译文的呈现：按顺序取前几条，拼成字幕窗文本。

// 只列外接采集设备；不做默认回退，也不会因此启动任何设备。

// 切源/换设备/停止：作废所有在途结果与旧帧，清掉只能属于旧来源的产物。

// 开始/重连采集会话。权限、设备缺失或被占用都返回 NO 并给出明确状态，绝不改用其他设备。

- (void)controlValueChanged:(id)sender {
    if (sender == self.captionTextColorWell) { self.captionTextColorCustomized = YES; }
    if (sender == self.captionThemeControl && !self.captionTextColorCustomized) {
        self.captionTextColorWell.color = [self captionThemeTextColor];
    }
    if (sender == self.batchTextColorWell) { self.batchTextColorCustomized = YES; }
    if (sender == self.batchThemeControl && !self.batchTextColorCustomized) {
        self.batchTextColorWell.color = [self inlineThemeTextColor];
    }
    BOOL batchAppearanceChanged = sender && (sender == self.batchFontSizeSlider ||
        sender == self.batchWidthSlider || sender == self.batchHeightSlider || sender == self.batchTextColorWell || sender == self.batchThemeControl);
    if (batchAppearanceChanged) {
        // 连续滑条只提交最新尺寸；不要在每个鼠标事件里测量、避让并刷新所有窗口。
        // 字色只影响绘制，原位更新即可，保留字号、选区和滚动位置。
        [self applyBatchAppearanceToLayoutEngine];
        if (sender == self.batchTextColorWell || sender == self.batchThemeControl) {
            if (sender == self.batchThemeControl) { [self refreshInlinePanelAppearance]; }
            [self refreshInlinePanelTextAppearance];
        } else {
            [self scheduleBatchAppearanceLayout];
        }
        [self updateSubtitleAppearancePage];
        [self scheduleSettingsSave];
        return;
    }
    if (sender && (sender==self.manualOCRScopeCheckbox || sender==self.regionXSlider || sender==self.regionYSlider || sender==self.regionWidthSlider || sender==self.regionHeightSlider)) {
        [self advanceTranslationGeneration];
        [[self translationState] reset];
        [[self stabilityOwner] reset];
        self.inFlight=NO;
        self.lastOCRedCaptureFrameIndex=0;
        [self hideInlineTranslationPanelsForGeometryChange];
        [self.inlineTranslationCache removeAllObjects];
    }
    [self clampRegionSliders];
    [self updateCaptionAppearance];
    [self updateThemeSummary];
    [self updateOCRPreviewIfVisible];
    [self scheduleSettingsSave];
}

- (void)scheduleBatchAppearanceLayout {
    BOOL hasScene = self.lastInlineRenderedTranslations.count > 0 && self.lastInlineRenderedItems.count > 0;
    if (self.batchAppearanceTimer || (!hasScene && !self.inlineExpandedReadingPanel)) { return; }
    __weak typeof(self) weakSelf = self;
    self.batchAppearanceTimer = [NSTimer timerWithTimeInterval:1.0 / 30.0 repeats:NO block:^(NSTimer *timer) {
        AppDelegate *app = weakSelf;
        app.batchAppearanceTimer = nil;
        NSRect placement = NSZeroRect;
        // 读取执行时的内容和几何：停止、换页或换窗口后不恢复旧字幕。
        if ([app inlinePlacementRect:&placement reason:NULL]) {
            if (app.lastInlineRenderedTranslations.count > 0 && app.lastInlineRenderedItems.count > 0) {
                [app showInlineTranslations:app.lastInlineRenderedTranslations forItems:app.lastInlineRenderedItems placementRect:placement];
            }
            [app refreshExpandedInlineReadingCardAppearanceInRect:placement];
        }
    }];
    // AppKit 的滑条在事件跟踪模式中运行；普通模式的 timer 会等到松手才刷新。
    [NSRunLoop.mainRunLoop addTimer:self.batchAppearanceTimer forMode:NSRunLoopCommonModes];
}

- (void)useDefaultSubtitleRegion:(id)sender {
    self.regionXSlider.doubleValue = 0.05;
    self.regionYSlider.doubleValue = 0.52;
    self.regionWidthSlider.doubleValue = 0.90;
    self.regionHeightSlider.doubleValue = 0.42;
    [self controlValueChanged:self.regionHeightSlider];
}

- (void)useLargeSubtitleRegion:(id)sender {
    self.regionXSlider.doubleValue = 0.02;
    self.regionYSlider.doubleValue = 0.42;
    self.regionWidthSlider.doubleValue = 0.96;
    self.regionHeightSlider.doubleValue = 0.52;
    [self controlValueChanged:self.regionHeightSlider];
}

- (void)useFullWindowRegion:(id)sender {
    self.regionXSlider.doubleValue = 0;
    self.regionYSlider.doubleValue = 0;
    self.regionWidthSlider.doubleValue = 1;
    self.regionHeightSlider.doubleValue = 1;
    [self controlValueChanged:self.regionHeightSlider];
}

- (void)useInterfaceFullWindowPreset:(id)sender {
    self.detectedModeSegment = ContentModeUI;
    self.candidateModeSegment = -1;
    self.candidateModeHits = 0;
    [self controlValueChanged:nil];
    [self useFullWindowRegion:nil];
    [self restartTimerIfRunning];
    [self setStatus:@"已切换为界面全文模式"];
}

- (void)requestScreenAccess:(id)sender {
    if ([self hasScreenAccess]) {
        [self setStatus:@"屏幕录制权限已可用"];
        return;
    }

    self.screenAccessRequestedDuringSession = YES;
    BOOL granted = CGRequestScreenCaptureAccess();
    if (granted || [self hasScreenAccess]) {
        [self setStatus:@"屏幕录制权限已可用"];
    } else {
        [self setStatus:@"已打开授权；勾选“译芽”后点“重启 App”"];
        [self openScreenAccessSettings:nil];
    }
}

- (void)checkScreenAccess:(id)sender {
    if ([self canCaptureSelectedWindowOnce]) {
        [self setStatus:@"窗口捕获可用，可以开始翻译"];
        return;
    }

    if ([self hasScreenAccess]) {
        [self setStatus:@"权限已授予，但目标窗口无法截取；请刷新并重新选择窗口"];
    } else {
        [self setStatus:@"权限还未生效；授权后请点“重启 App”"];
    }
}

- (void)relaunchApp:(id)sender {
    NSURL *bundleURL = [self preferredBundleURLForRelaunch];
    if (!bundleURL) {
        [self setStatus:@"找不到 App 路径，请手动退出后重开"];
        return;
    }

    [self setStatus:@"正在重启 App"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:bundleURL
                                              configuration:configuration
                                          completionHandler:nil];
        [NSApp terminate:nil];
    });
}

- (void)openScreenAccessSettings:(id)sender {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)invalidateServiceTest {
    __weak typeof(self) weakSelf = self;
    [[self serviceTestController] invalidateWhileRunning:self.running status:^(NSString *status) { [weakSelf setStatus:status]; }];
}

- (NSString *)configuredTranslationModel {
    return Trim(self.modelField.stringValue);
}

- (void)updateServiceTestModelLabel {
    NSString *model=[self configuredTranslationModel];
    self.serviceTestModelLabel.stringValue = [NSString stringWithFormat:@"测试模型：%@ · 与实时字幕一致", model.length ? model : @"尚未填写"];
}

- (void)presentServiceTestState:(NSString *)state error:(NSString *)error result:(NSString *)result {
    [self serviceTestController].pending = [state isEqualToString:@"pending"];
    if (!self.serviceTestPresentation) self.serviceTestPresentation=[FYTranslationServiceTestPresentation new];
    FYTranslationServiceTestPresentation *presentation=self.serviceTestPresentation;
    // Also bind synthetic controls used by the headless production-chain tests.
    presentation.button=self.serviceTestButton; presentation.icon=self.serviceStatusIcon;
    presentation.statusLabel=self.serviceStatusLabel; presentation.modelLabel=self.serviceTestModelLabel;
    presentation.messageLabel=self.serviceTestMessageLabel; presentation.errorLabel=self.serviceErrorLabel;
    presentation.resultLabel=self.serviceTestResultLabel; presentation.panel=self.serviceTestResultPanel;
    [presentation presentState:state error:error result:result];
}

- (void)testTranslation:(id)sender {
    NSString *sample = self.languageControl.selectedSegment == 1
        ? @"Would you like to walk home together today?" : @"今日は一緒に帰りませんか？";
    __weak typeof(self) weakSelf = self;
    [[self serviceTestController] testSample:sample transport:^(NSString *source, void (^done)(NSString *, NSError *)) {
        [weakSelf updateServiceTestModelLabel];
        [weakSelf translateText:source systemPrompt:[weakSelf systemPrompt] maxTokens:240 modelOverride:nil
            longText:NO serviceTest:YES completion:done];
    } isRunning:^BOOL { return weakSelf.running; }
      status:^(NSString *status) { [weakSelf setStatus:status]; }
      present:^(NSString *state, NSString *error, NSString *result) { [weakSelf presentServiceTestState:state error:error result:result]; }
      sanitize:^NSString *(NSString *translated, NSString *source) { return [weakSelf displayableTranslation:translated sourceText:source]; }];
}

- (void)applyTranslationServicePreset:(NSString *)identifier model:(NSString *)model {
    if (self.translationServiceView) { [self.translationServiceView applyPreset:identifier model:model]; return; }
    NSDictionary *preset=FYTranslationServicePreset(identifier);
    if (!preset) return;
    self.baseURLField.stringValue=preset[@"url"]; self.modelField.stringValue=model ?: preset[@"model"];
    [self serviceSettingsChanged];
}
- (void)useDeepSeekPreset:(id)sender { [self applyTranslationServicePreset:@"deepseek" model:FYTranslationServicePreset(@"deepseek")[@"models"][1]]; }
- (void)useDeepSeekFlashPreset:(id)sender { [self applyTranslationServicePreset:@"deepseek" model:FYTranslationServicePreset(@"deepseek")[@"model"]]; }
- (void)useOpenAIPreset:(id)sender { [self applyTranslationServicePreset:@"openai" model:FYTranslationServicePreset(@"openai")[@"model"]]; }

- (void)pasteAPIKeyFromClipboard:(id)sender {
    NSString *clipboardText = Trim([[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]);
    if (clipboardText.length == 0) {
        [self setStatus:@"剪贴板里没有可粘贴的文本"];
        return;
    }

    self.apiKeyField.stringValue = clipboardText;
    self.credentialLoadFailed = NO;
    [self setStatus:@"API Key 已从剪贴板填入"];
    [self serviceSettingsChanged];
}

- (void)clearAPIKey:(id)sender {
    self.apiKeyField.stringValue = @"";
    self.credentialLoadFailed = NO;
    [self setStatus:@"API Key 已清空"];
    [self serviceSettingsChanged];
}

- (FYSettingsSnapshot *)settingsSnapshot {
    NSMutableDictionary *settings = [@{
        @"language": @(self.languageControl.selectedSegment),
        @"regionX": @(self.regionXSlider.doubleValue),
        @"regionY": @(self.regionYSlider.doubleValue),
        @"regionWidth": @(self.regionWidthSlider.doubleValue),
        @"regionHeight": @(self.regionHeightSlider.doubleValue),
        @"manualOCRScope": @(self.manualOCRScopeCheckbox.state == NSControlStateValueOn),
        @"baseURL": self.baseURLField.stringValue ?: @"",
        @"model": self.modelField.stringValue ?: @"",
        @"learningModel": self.learningModelField.stringValue ?: @"",
        // 识别输入源（0 = 窗口截图，1 = 采集卡）与上次选择的采集卡设备。
        // 只记硬件标识用于恢复选择，不写入日志；启动时不会因此自动开始采集。
        @"inputSource": @(self.inputSourceSegment == 1 ? 1 : 0),
        @"captureDeviceID": self.selectedCaptureDeviceID ?: @"",
        // 采集卡画面区域校准（只存几何与设备标识，不存画面）。
        @"captureVideoRects": self.captureCardVideoRects ?: @{}
    } mutableCopy];
    if (self.translationServiceView) [settings addEntriesFromDictionary:[self.translationServiceView settingsDictionary]];
    [settings addEntriesFromDictionary:[self subtitleAppearanceSettings]];
    return [[FYSettingsSnapshot alloc] initWithValues:settings];
}

- (void)saveSettings:(id)sender {
    [[self settingsStore] cancelScheduledSave];
    if (self.loadingSettings) { return; }
    FYSettingsSaveResult result = [[self settingsStore] saveSnapshot:[self settingsSnapshot]
        apiKey:self.apiKeyField.stringValue ?: @""];
    if (result == FYSettingsCredentialReadBlocked) {
        [self presentServiceTestState:@"untested" error:@"无法读取本机 API Key 文件，设置未保存。请检查文件访问权限。" result:nil];
    } else if (result == FYSettingsCredentialWriteFailed) {
        [self presentServiceTestState:@"untested" error:@"API Key 无法保存到本机文件，设置未保存。请检查文件访问权限。" result:nil];
    }
}

- (void)scheduleSettingsSave {
    __weak typeof(self) weakSelf = self;
    [[self settingsStore] scheduleSave:^{ [weakSelf saveSettings:nil]; }];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    id field = notification.object;
    if (field == self.lemmaField || field == self.readingField || field == self.meaningField) {
        [self vocabularyFormChanged:field]; return;
    }
    if (field == self.apiKeyField) { self.credentialLoadFailed = NO; }
    [self scheduleSettingsSave];
    if (field == self.baseURLField || field == self.modelField || field == self.apiKeyField) {
        [self invalidateServiceTest];
        [self presentServiceTestState:@"untested" error:nil result:nil];
        [self updateServiceTestModelLabel];
    }
    if (field == self.learningModelField || field == self.baseURLField || field == self.modelField || field == self.apiKeyField) {
        [self syncLearningAnalyzerConfig];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.lemmaField || notification.object == self.readingField || notification.object == self.meaningField) { return; }
    [self saveSettings:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    FYCrashLifecycle(@"normal-termination");
    [self.batchAppearanceTimer invalidate];
    self.batchAppearanceTimer = nil;
    [self.overlayVisibilityTimer invalidate];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self saveSettings:nil];
    [self stop];
    [self invalidateServiceTest];
    [self.globalShortcuts stop];
    [self.studyChatSession cancel];
    [self cancelQuickSentenceAnalysis];
    [self.learningAnalyzer cancelAll];
}

- (void)serviceSettingsChanged {
    [self invalidateServiceTest];
    [self presentServiceTestState:@"untested" error:nil result:nil];
    [self updateServiceTestModelLabel];
    [self syncLearningAnalyzerConfig];
    [self saveSettings:nil];
}

- (void)loadSettings {
    self.loadingSettings = YES;
    NSDictionary *settings = [[self settingsStore] load].values;
    self.languageControl.selectedSegment = [settings[@"language"] integerValue] ?: 0;
    // 内容模式已彻底固定为自动判别：忽略旧存档里的手动模式（mode / autoModeEnabled / manualMode），
    // 每次启动都从对白开始，由判别逻辑按画面连续两帧一致来切换。
    self.detectedModeSegment = ContentModeDialogue;
    self.candidateModeSegment = -1;
    self.candidateModeHits = 0;
    self.captionPanelShownByUser = YES;
    self.regionXSlider.doubleValue = settings[@"regionX"] ? [settings[@"regionX"] doubleValue] : 0.05;
    self.regionYSlider.doubleValue = settings[@"regionY"] ? [settings[@"regionY"] doubleValue] : 0.52;
    self.regionWidthSlider.doubleValue = settings[@"regionWidth"] ? [settings[@"regionWidth"] doubleValue] : 0.90;
    self.regionHeightSlider.doubleValue = settings[@"regionHeight"] ? [settings[@"regionHeight"] doubleValue] : 0.42;
    [self loadSubtitleAppearanceSettings:settings];
    self.manualOCRScopeCheckbox.state=[settings[@"manualOCRScope"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.baseURLField.stringValue = settings[@"baseURL"] ?: @"https://api.openai.com/v1";
    self.modelField.stringValue = FYTranslationModelForSettings(settings);
    self.learningModelField.stringValue = settings[@"learningModel"] ?: @"";
    [self.translationServiceView loadSettings:settings];
    [self updateServiceTestModelLabel];
    self.apiKeyField.stringValue = self.persistedAPIKey ?: @"";
    if (self.credentialLoadFailed) {
        [self presentServiceTestState:@"untested" error:@"无法读取本机 API Key 文件；原文件已保留。请检查文件访问权限。" result:nil];
    }
    // 识别输入源与采集卡设备：只恢复选择，不自动启动采集（权限也不会在这里申请）。
    self.inputSourceSegment = [settings[@"inputSource"] integerValue] == 1 ? 1 : 0;
    if (self.inputSourceControl) { self.inputSourceControl.selectedSegment = self.inputSourceSegment; }
    self.selectedCaptureDeviceID = settings[@"captureDeviceID"];
    NSDictionary *savedRects = settings[@"captureVideoRects"];
    if ([savedRects isKindOfClass:NSDictionary.class] && savedRects.count > 0) {
        // 启动时就丢掉旧版（纵坐标错误）的自动映射：不能修了算法还继续读旧结果。
        self.captureCardVideoRects = FYFilterCaptureMappings(savedRects, kCaptureCardMappingVersion);
    }
    if (self.inputSourceSegment == 1) {
        [self refreshCaptureDevices:nil];
        [self updateCaptureCardStatus];
    }
    [self updateWindowCardCopy];
    [self clampRegionSliders];
    [self updateCaptionAppearance];
    [self updateThemeSummary];
    self.loadingSettings = NO;
}

// 把 OCR 行喂给独立分组器，再映射回应用的 OCRTextItem（字段语义保持不变）。
// 几何判定、联合去重与长短分类都在 FYInlineGrouper 里，这里不重复堆条件。

// 把应用的原文项转成布局器的输入块（分类用已经判定好的 blockKind，
// 身份沿用 inlineBlockIdentityForItem: 的格式，保证点击/选中绑定不变）。

// Main-thread only: filtering reads the current languageControl selection.

// Main-thread only; both production OCR callbacks return to the main queue.

// 按钮/导航类小标签（詳細・戻る・閉じる…）。
// 它们值得翻；阅读顺序中排到最后，让正文先参与布局。

// 翻译一批同类型的界面文字块，结果按 indexes 写回共享 translations 数组。

// 内容指纹：译文 + 原文 + 位置。三者都没变就说明这一帧没有任何变化。

// 就地更新一个已有贴译面板（不销毁、不重建窗口 → 不会闪）

// placementRect：贴译面板的落位区域。窗口截图模式是整个目标窗口；
// 采集卡模式是「视频帧等比适配到目标显示窗口」后的可见矩形（见 captureCardDisplayRectForWindow:）。
//
// 布局流程（本帧统一安排，不逐张盲找空位）：
//   ① 全部原文块 + 待显示译文交给 FYInlineLayoutEngine：每块只生成有限候选，
//      先剔除超出可见区域／遮挡其它原文块／与本帧其它译文冲突／离原文过远／低于可读下限的候选；
//   ② 面板按**块身份**复用：位置或文字变了就地更新，只有模式切换才重建内容视图；
//   ③ 没有合法位置的块不伪造位置，只统计降级数量（提示走主界面状态区，不写字幕框）。

// ── 极端降级：「还有 N 条译文」 ───────────────────────────────────────────
// 只有确实存在"连折叠入口都放不下"的块时才出现；点击打开一个可选列表，
// 选中哪一条就把哪一条的完整译文就地展开。绝不静默丢弃、也不只写日志。

// 边缘入口的尺寸与位置：按文字量尺寸，并**纳入统一避让** ——
// 固定左下角会压住别的贴译（现场已经压到「查看个人资料」那条）。
// 候选顺序：下左/下右/上左/上右/下中/上中/左中/右中；先选完全不遮挡的，
// 都不行时选遮挡面积最小的那个（仍然贴边、可点，不堆叠多个卡片）。

// 键 = 归一化文本 + **归一化**原文框中心的粗分桶（0.01 ≈ 11px@1080）。
// 用归一化坐标而不是显示坐标：窗口移动/缩放时框的归一化位置不变，手动位置才能跟着窗口走；
// 键里带文本与位置，所以换页后即使出现别的块也不会继承偏移；抖动落进相邻桶时按邻域查找。

// 拖动结束：记录「相对原文锚点」的偏移，并把面板夹回可见区域。

// 把拖动行为绑到面板上：长卡走标题栏，短贴片按住 Option 才可拖。

// 按住 Option：短贴片从「鼠标穿透」切到「可拖动」并显示反馈；松开恢复穿透。
// 拖动过程中保持不变，避免松手瞬间面板变穿透、事件落到游戏上。

// 布局结果 → 面板排版（新建与原地更新共用同一份测量结果）。

// 该块是否是当前正在学习（已选中）的块。
// 必须按块身份（原文 + 行框）判断：同一段文字出现在别处时不能算选中。
// 选中判定：先用布局器匹配出来的**稳定身份**比，再退回本帧原始身份。
// 这样 OCR 框抖动 1px 时，面板身份与选中态一起保持稳定（稳定身份来自 FYInlineBlockMatcher，
// 仍然带真实行框与输入源/代次边界，不是纯文本身份）。

// 译文段落归一化：OCR 的单行折行不该变成译文段落 ——
// 单个换行并回同一段，空行保留为真正的段落分隔。
static NSString *InlineNormalizeTranslationParagraphs(NSString *text) { return FYInlineNormalizeTranslationParagraphs(text); }

// 长卡正文的字体与段落样式：测量与绘制必须用同一份，
// 否则换文后文档高度不更新（滚到底看不全），行距也不会真正生效。

// 长卡正文的单行高度（含行距）：用来保证"至少三行可读正文"。

// 普通贴译长卡最小可读高度：内边距 + 三行正文。

// 长卡正文视口高度（给定卡片高度）。

// 普通贴译只显示正文；展开阅读卡保留标题（奶油底、深棕圆体、浅棕细边、轻柔阴影）。

// 显式给定卡框时补齐绘制参数（测试与「展开完整阅读卡」用）：
// 字体/段落样式/内边距仍取自布局引擎，测量口径与 ShowInlineTranslations 完全一致。

// 兼容入口（独立验收测试仍在用）：不带 compact 的调用按完整长卡处理。

// 由当前块生成不可变学习快照（含原始行框、内容身份与采集代次）。
// 块身份：原文 + 真实行框（跨帧稳定、不用随机 UUID）。
// 相同文字出现在不同位置时身份不同 —— 不能用纯文本当身份。

// stableBlockID：布局器跨帧匹配出来的块身份。点击/选中/学习快照都用它，
// 保证 OCR 框轻微抖动后面板、选中态与学习卡指向同一块；为空时退回本帧原始身份。

// 由布局器的块（而非 OCRTextItem）生成快照：集中查看列表用它保留每块的原文、译文与稳定身份。

// 紧凑入口 → 打开完整阅读卡（窗口内的浮层，卡内滚动，点击进入学习）。

// 设置滑条只改变同一张阅读卡的框与排版，保留正文、滚动视图、收起按钮及块身份。

// 按最新映射把展开卡放回可见区域内（尺寸不变，只调整位置；不改内容、不重新翻译）。

// 展开态记账：块还在当前排版结果里就清零，连续 2 帧都不在才收起。
// 必须在所有 dedup 短路**之外**也有一次调用 —— 内容没变/节流短路时不会再走渲染路径，
// 否则"这一块已经在页面上消失"会永远停在第一帧，阅读卡留在画面上不走。

// 展开期间：把其它贴译面板与折叠入口收起来，并且不再接收鼠标事件（不能挡住游戏点击）。

// 当前帧里仍然存在的贴译面板（按稳定块身份判断），用于"恢复当前页面状态"。

#pragma mark - 长卡片 → 语法学习 → AI 返回

// 「点长卡片进入学习」的文字入口（保留给测试与外部调用）：没有行框时也能工作。

// 点长卡片进入学习：用不可变块快照打开学习卡；换块时建立独立上下文。

// 换块时把独立 AI 会话切到新块：清空上一块的消息与未发送草稿，绑定新块引用。

// 「‹ 返回语法」：从独立 AI 恢复同一快照的语法卡；已完成分析不重跑，滚动位置恢复。

- (NSRect)appKitFrameForOCRItem:(OCRTextItem *)item inWindowFrame:(NSRect)windowFrame {
    return [FYGeometryManager frameForNormalizedBox:item.boundingBox inViewport:windowFrame];
}

// 贴译默认奶油棕，使用自身的主题选择；长对白切换主题不改变贴译。
// 分组器：几何判定在独立组件里，这里只注入“按钮词”这一项项目内约定。

// 布局引擎：字体由主题注入，保证“测量与绘制共用同一份字体+段落样式”。
// 多个"像投影"的候选分级：能唯一确定才返回一个，否则返回空数组（= 交给调用方提示重选）。

// 贴译背景不透明度：直接跟随现有「背景透明度」设置（与字幕同一数值），
// 不新增第二套透明度设置，也不重置用户已有偏好。文字颜色始终完全不透明。

// 透明度设置变化后，已经显示出来的贴译立即更新：只改背景，不动文字与位置。

// 中文使用项目规定的华文圆体（短贴片正常字重；长卡正文与预览一致用粗圆体）。

// 贴译外观：奶油近实底 + 浅棕细边 + 平滑圆角 + 轻柔阴影（与字幕主题无关）。

// 折叠入口压在原文上：可读性靠**文字颜色 + 描边 + 阴影**，
// 底不透明度一律跟随用户现有设置（不强制高不透明，否则用户调低透明度时它几乎不变）。

// 压在原文上的小字：墨色 + 浅色描边阴影，低不透明度下也能读清（不改用户透明度设置）。

#pragma mark - Capture and OCR

- (NSURL *)preferredBundleURLForRelaunch {
    NSString *installedPath = [@"~/Applications/译芽.app" stringByExpandingTildeInPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:installedPath]) {
        return [NSURL fileURLWithPath:installedPath];
    }

    NSURL *currentBundleURL = NSBundle.mainBundle.bundleURL;
    return [currentBundleURL.pathExtension.lowercaseString isEqualToString:@"app"] ? currentBundleURL : nil;
}

// 按 **窗口 ID** 查这扇窗口此刻的真实边界（点坐标、屏幕左上角原点）。
// 下拉列表里的 bounds 是刷新那一刻的快照，窗口移动/缩放/OBS 内部预览变化后就会过期；
// 映射与布局一律走这里，查不到时才退回快照。测试可以覆盖它来模拟窗口移动。

// 同进程的窗口里，哪些"可能承载游戏画面"：
// 普通层、够大、而且不是应用的设置/属性/统计面板。

// 解析"当前实际承载游戏画面的窗口"。
// 返回 0 表示**确定不了**（原窗口已关闭 / 多个投影无法区分）：上层必须隐藏旧贴译并提示重新选择，
// 绝不随便挑一扇窗口继续贴。
//   · 选中窗口仍在屏幕上：它前面的同进程画面窗口明显更大时跟随它（F11 全屏投影/全屏预览）；
//     应用自己的设置弹窗更小，不会被当成分身目标。
//   · 选中窗口不在屏幕上（被投影接管/最小化）：唯一的同进程画面窗口才跟随；
//     有多个时要求明显只有一个"主画面"，否则视为歧义。

// 实际显示目标窗口 ID。还没解析过时沿用用户选择（离线夹具/首帧），
// 解析过之后以解析结果为准：0 = 确定不了，上层必须提示而不是猜。

// 实际显示目标窗口（带最新几何）。解析不到时退回用户选择，保证"看不出来时行为不变"。

// 目标窗口不在下拉列表时，为这个 ID 现造一个等价对象（查当前窗口列表，含画面外的窗口）。

// 一律用**实时边界**换算：窗口移动/缩放后不能继续用下拉列表里的旧快照。

// 采集卡画面区域的映射版本。
//   1 = 旧版实现：bestRect.origin.y（像素网格、从图像顶部算）被直接加到 AppKit 窗口底部，
//       漏了纵坐标翻转 → 映射整体下移（OBS 预览靠上时，贴译会落到下方控制区）。
//   2 = 网格坐标按图像顶部换算回 AppKit 的「距底部」，比对仍使用角点取样。
//   3 = 模板与候选都按像素单元面积比对，保留细字笔画；旧自动结果重新定位。
// 读取映射时必须校验版本：修了算法也不能继续读取旧版存下的错误结果。
const NSInteger kCaptureCardMappingVersion = 3;
// 无法取样时的哨兵值：与「相关性很差（负数）」区分开，避免把“完全对不上”当成“测不了”。
const double kCaptureCardMappingScoreUnavailable = -99;

// 生成「当前采集帧模板」与「目标窗口截屏场景」两份灰度网格（都已零均值/单位方差归一化）。
// 网格来自 FYGrayGridFromImage：**第 0 行是图像顶部**（row-major、自上而下）。
// 调用方负责 free 两个网格；返回 NO 时不产生需要释放的内存。

// 自动定位：在目标窗口的**实际截屏**里按内容找出采集画面所在区域。
// 标题栏、工具栏、黑边与画面内容对不上，所以不会被选中；
// 「窗口存在 + 有帧」本身不构成成功，必须比对通过才算。

// 映射变化（重新定位成功 / 旧映射作废）时调用：贴译布局缓存必须一起失效，
// 否则面板会继续停在旧坐标，直到页面文字恰好发生变化才重排。

// 便宜复核：只把**缓存矩形对应的那一小块当前窗口截屏**与最新采集帧做一次定点比对，
// 不做搜索。OBS 内部预览被拖动/缩放后，即使窗口比例没变，相关系数也会明显下降。
// 返回 kCaptureCardMappingScoreUnavailable 表示**无法取样**（没有帧/没有权限/网格失败）；
// 其余返回值都是真实相关性，可能为负（= 明显对不上）。

static double FYMappingScoreInGrids(NSDictionary *entry, const double *scene, size_t WW, size_t WH,
                                    const double *templ, size_t TW, size_t TH) {
    return FYCaptureMappingScoreInGrids(entry, scene, WW, WH, templ, TW, TH);
}

// 写入某个显示窗口的采集卡画面区域。
// 存**相对窗口的归一化矩形** + 校准时的窗口比例与视频比例 + 设备标识：
//   窗口移动 → 归一化映射仍正确；
//   等比缩放 → 仍正确；
//   窗口比例变化 / 画面比例变化 / 换设备 → 判定失效并提示重新校准。

// 用户手动调整（次要入口）：来源记为 manual，自动定位不再覆盖它。

// 整窗等比估算：只用来解释「为什么位置会有偏差」，**不是有效映射**。
// 窗口有标题栏、工具栏、OBS 面板或画面被裁剪时，这个估算会整体偏移。

// 采集卡坐标映射：只有**校准过的视频显示区域**才算有效映射。
// 旧实现把「帧等比居中到整个目标窗口」当成映射并返回成功，等于宣称可靠原位映射 ——
// 有帧、有窗口都不足以证明映射有效，因此这里不再回退到估算。

// 在目标窗口上盖一层拖框层：用户框出的矩形就是真实的视频显示区域。

// 当前识别输入源下界面贴译面板应落在哪里。
//   窗口截图：整个目标窗口；采集卡：视频帧适配后的可见矩形。
// 返回 NO 时 outReason 给出明确原因（用于提示，不能静默塞进对白框）。
// 目标窗口定位不了时的原因文案：歧义/窗口关闭优先给"请重新选择"这类可操作提示。

// 定位失败时只在**主界面状态区**给一句简短提示。
// 不写字幕框（字幕框只放对白译文，不能被提示覆盖），也不解释实现细节。

// 对白模式需要整段文本，界面模式需要每块的坐标；这里一次请求同时给出两者
// 把画面中的一小块裁出来放大（2 倍）再识别，用于“自动贴合文字”。
// 放大能显著改善小字号识别，也能在小控件压掉一点文字时更容易读出剩余部分。

// OCR may change elsewhere in the frame while the dialogue identity stays the
// same. Reuse its successful translation so a pinned sentence cannot drift
// through repeated model paraphrases. A new occurrence/version or changed
// service/run gets a fresh request; failed requests remain retryable.

// All translation routes resolve the same field at the transport boundary.

// 同一句文本重复出现时，隔多久才允许再请求一次翻译。
// 界面模式要短：界面是用户在动，等久了会明显觉得“卡住不动”。

// 保留对普通亮色页面的保护：仅在同时识别到面板、暗背景和底部关闭按钮时隐藏背景。

// 同样的判别结果连续出现两次才切换，避免单帧抖动导致模式来回跳

#pragma mark - State helpers

// Default clock is unchanged. Replay overrides only this seam to exercise the
// real throttling policy without waiting wall-clock seconds.

- (void)setStatus:(NSString *)status {
    if (self.statusLabel) { self.statusLabel.stringValue = status ?: @""; }
}

- (void)updateRunState {
    if (!self.runStateLabel) { return; }
    self.runStateLabel.stringValue = !self.running ? @"● 已暂停" :
        (self.captureUnavailable ? @"● 等待目标窗口" : @"● 正在翻译");
    self.runStateLabel.textColor = !self.running ? [NSColor secondaryLabelColor] :
        (self.captureUnavailable ? [NSColor systemOrangeColor] :
         [NSColor colorWithRed:0.09 green:0.51 blue:0.43 alpha:1]);
    [self refreshLiveChips];
}

- (void)updateTranslationCount {
    self.translationCountLabel.stringValue = [NSString stringWithFormat:@"翻译轮次  %ld", (long)self.translationCount];
}

- (void)showError:(NSString *)error {
    if (self.liveErrorLabel) {
        self.liveErrorLabel.stringValue = error ?: @"";
        self.liveErrorLabel.hidden = Trim(error).length == 0;
    }
}

- (void)updateCurrentWindowLabel {
    if (!self.currentWindowLabel) { return; }
    NSString *name = self.windowPopup.selectedItem.title ?: @"未选择";
    self.currentWindowLabel.stringValue = [NSString stringWithFormat:@"当前窗口：%@", name];
}

@end

@implementation AppDelegate (FYPresentationHost)
@end
