#import "FYMainWindowController.h"
// Legacy native shell helpers are implementation details, not public dependencies.
#import "../app/FYAppSupport.h"

@interface FYMainWindowController ()
@property(nonatomic, strong) NSButton *analyzeButton;
@property(nonatomic, strong) NSPanel *captionAppearancePreviewPanel;
@property(nonatomic, strong) FYAnalysisResult *currentAnalysis;
@property(nonatomic, strong) NSButton *grammarPageAnalyzeButton;
@property(nonatomic, strong) NSTextField *grammarPinnedLabel;
@property(nonatomic, strong) NSTextField *grammarSourceLabel;
@property(nonatomic, strong) NSTextView *grammarSourceTextView;
@property(nonatomic, strong) FYJapaneseTokenizer *japaneseTokenizer;
@property(nonatomic, strong) FYInlineLayoutResult *lastInlineLayoutResult;
@property(nonatomic) BOOL learningAnalysisBusy;
@property(nonatomic, strong) FYLearningCoordinator *learningCoordinator;
@property(nonatomic, strong) FYStudyChatView *mainStudyChatView;
@property(nonatomic) BOOL sourceHoverSuspended;
@property(nonatomic, strong) NSTextField *vocabularyStatusLabel;
@end

@implementation FYMainWindowController

@synthesize livePageBuilder = _livePageBuilder;
- (FYLivePageBuilder *)livePageBuilder { if(!_livePageBuilder){_livePageBuilder=[FYLivePageBuilder new];}return _livePageBuilder; }
- (id)livePageActionTarget { return self.host; }
- (void)installLivePageVocabularyStatusLabel:(NSTextField *)field { self.vocabularyStatusLabel=field; }


@dynamic inlineTranslationListSignature, inlineTranslationListSnapshots;
@synthesize inlineTranslationListCoordinator = _inlineTranslationListCoordinator;
@synthesize inlineTranslationListRenderer = _inlineTranslationListRenderer;
- (FYInlineTranslationListCoordinator *)inlineTranslationListCoordinator { if(!_inlineTranslationListCoordinator){_inlineTranslationListCoordinator=[FYInlineTranslationListCoordinator new];}return _inlineTranslationListCoordinator; }
- (FYInlineTranslationListRenderer *)inlineTranslationListRenderer { if(!_inlineTranslationListRenderer){_inlineTranslationListRenderer=[FYInlineTranslationListRenderer new];}return _inlineTranslationListRenderer; }
- (NSString *)inlineTranslationListSignature { return self.inlineTranslationListCoordinator.inlineTranslationListSignature; }
- (void)setInlineTranslationListSignature:(NSString *)value { self.inlineTranslationListCoordinator.inlineTranslationListSignature=value; }
- (NSArray<FYInlineBlockSnapshot *> *)inlineTranslationListSnapshots { return self.inlineTranslationListCoordinator.inlineTranslationListSnapshots; }
- (void)setInlineTranslationListSnapshots:(NSArray<FYInlineBlockSnapshot *> *)value { self.inlineTranslationListCoordinator.inlineTranslationListSnapshots=value; }
- (NSView *)makeInlineTranslationListCard { return [self.inlineTranslationListRenderer makeCardWithReceiver:self]; }
- (void)refreshInlineTranslationList { [self.inlineTranslationListCoordinator refreshWithReceiver:self]; }
- (void)openInlineTranslationRow:(NSButton *)sender { NSInteger index=sender.tag;[self.inlineTranslationListCoordinator openRowAtIndex:index receiver:self]; }
- (BOOL)isInlineTranslationListReady { return self.inlineTranslationListStack && self.inlineTranslationListCard; }
- (void)setInlineTranslationListHidden:(BOOL)hidden { self.inlineTranslationListCard.hidden=hidden; }
- (void)clearInlineTranslationListRows { [self clearArrangedSubviews:self.inlineTranslationListStack]; }
- (void)updateInlineTranslationListCountText:(NSString *)text { self.inlineTranslationListCount.stringValue=text; }
- (void)appendInlineTranslationListRowForPlacement:(FYInlinePlacement *)placement currentSnapshots:(NSArray<FYInlineBlockSnapshot *> *)snapshots { [self.inlineTranslationListRenderer appendRowForPlacement:placement currentSnapshots:snapshots receiver:self]; }
- (NSFont *)inlineTranslationListFontOfSize:(CGFloat)size { return FYUIFont(size,NSFontWeightRegular); }


@synthesize liveReadingCoordinator = _liveReadingCoordinator;
@synthesize liveReadingRenderer = _liveReadingRenderer;
- (FYLiveReadingCoordinator *)liveReadingCoordinator { if(!_liveReadingCoordinator){_liveReadingCoordinator=[FYLiveReadingCoordinator new];}return _liveReadingCoordinator; }
- (FYLiveReadingRenderer *)liveReadingRenderer { if(!_liveReadingRenderer){_liveReadingRenderer=[FYLiveReadingRenderer new];}return _liveReadingRenderer; }
- (void)refreshLearningSource { [self.liveReadingCoordinator refreshLearningSourceWithReceiver:self]; }
- (nullable NSString *)currentSentenceLevelTag { return [self.liveReadingCoordinator currentSentenceLevelTagWithReceiver:self]; }
- (NSAttributedString *)liveReadingText:(NSString *)text japanese:(BOOL)japanese { return [self.liveReadingRenderer liveReadingText:text japanese:japanese receiver:self]; }
- (void)updateLiveSourceReadingHeight { [self.liveReadingRenderer updateLiveSourceReadingHeightWithReceiver:self]; }
- (void)refreshLiveDialoguePresentation:(NSString *)source { [self.liveReadingRenderer refreshLiveDialoguePresentation:source receiver:self]; }
- (void)refreshLearningStatus { [self.liveReadingRenderer refreshLearningStatusWithReceiver:self]; }
- (NSString *)currentLiveSourceText { return self.learningSourceTextView.string; }
- (NSString *)currentLiveGrammarSourceText { return self.grammarSourceTextView.string; }
- (void)setLiveSourceReadingText:(NSString *)text { [self.learningSourceTextView.textStorage setAttributedString:[self liveReadingText:text japanese:YES]]; }
- (void)setLiveGrammarSourceText:(NSString *)text { self.grammarSourceTextView.string=text; }
- (void)setLiveSourceEmptyHidden:(BOOL)hidden { self.liveSourceEmptyLabel.hidden=hidden; }
- (void)setLiveSourceScrollHidden:(BOOL)hidden { self.learningSourceTextView.enclosingScrollView.hidden=hidden; }
- (void)setLiveSourceHintHidden:(BOOL)hidden { self.liveSourceSelectionHintLabel.hidden=hidden; }
- (void)setLiveSourceMinimumHeight:(CGFloat)height { self.sourceReadingMinimumHeight.constant=height; }
- (void)setLiveTranslationMinimumHeight:(CGFloat)height { self.translationReadingMinimumHeight.constant=height; }
- (void)setLiveTranslationReadingText:(NSString *)text { self.learningTranslationLabel.attributedStringValue=[self liveReadingText:text japanese:NO]; }
- (void)setLiveTranslationWaitingHint:(NSString *)hint { self.learningTranslationLabel.attributedStringValue=[[NSAttributedString alloc]initWithString:hint attributes:@{NSFontAttributeName:FYUIFont(14,NSFontWeightRegular),NSForegroundColorAttributeName:self.uiMuted}]; }
- (void)layoutLiveReadingWindow { [self.mainWindow.contentView layoutSubtreeIfNeeded]; }
- (void)setLiveGrammarTranslationHint:(NSString *)text { self.grammarSourceLabel.stringValue=text; }
- (void)liveHostRefreshLearningStatus { [self.host refreshLearningStatus]; }
- (NSFont *)liveReadingJapaneseFontOfSize:(CGFloat)size { return FYJapaneseFont(size); }
- (NSFont *)liveReadingUIFontOfSize:(CGFloat)size { return FYUIFont(size,NSFontWeightRegular); }


@synthesize displayedSentenceState = _displayedSentenceState;
@synthesize wordSelectionController = _wordSelectionController;
@dynamic displayedSentenceID, displayedSourceText, displayedTranslation, displayedVersion, vocabSelectionGeneration, savingVocabulary, vocabCompletionFromAI;
- (FYDisplayedSentenceState *)displayedSentenceState { if(!_displayedSentenceState){_displayedSentenceState=[FYDisplayedSentenceState new];}return _displayedSentenceState; }
- (FYWordSelectionController *)wordSelectionController { if(!_wordSelectionController){_wordSelectionController=[FYWordSelectionController new];}return _wordSelectionController; }
- (NSString *)displayedSentenceID { return self.displayedSentenceState.displayedSentenceID; }
- (void)setDisplayedSentenceID:(NSString *)value { self.displayedSentenceState.displayedSentenceID=value; }
- (NSString *)displayedSourceText { return self.displayedSentenceState.displayedSourceText; }
- (void)setDisplayedSourceText:(NSString *)value { self.displayedSentenceState.displayedSourceText=value; }
- (NSString *)displayedTranslation { return self.displayedSentenceState.displayedTranslation; }
- (void)setDisplayedTranslation:(NSString *)value { self.displayedSentenceState.displayedTranslation=value; }
- (NSInteger)displayedVersion { return self.displayedSentenceState.displayedVersion; }
- (void)setDisplayedVersion:(NSInteger)value { self.displayedSentenceState.displayedVersion=value; }
- (NSInteger)vocabSelectionGeneration { return self.wordSelectionController.vocabSelectionGeneration; }
- (void)setVocabSelectionGeneration:(NSInteger)value { self.wordSelectionController.vocabSelectionGeneration=value; }
- (BOOL)savingVocabulary { return self.wordSelectionController.savingVocabulary; }
- (void)setSavingVocabulary:(BOOL)value { self.wordSelectionController.savingVocabulary=value; }
- (BOOL)vocabCompletionFromAI { return self.wordSelectionController.vocabCompletionFromAI; }
- (void)setVocabCompletionFromAI:(BOOL)value { self.wordSelectionController.vocabCompletionFromAI=value; }
- (NSString *)wordSelectionText { return self.learningSourceTextView.string; }
- (NSRange)wordSelectionRange { return self.learningSourceTextView.selectedRange; }
- (BOOL)wordSelectionTracking { return self.learningSourceTextView.trackingSelection; }
- (NSString *)wordLemmaInput { return self.lemmaField.stringValue; }
- (NSString *)wordReadingInput { return self.readingField.stringValue; }
- (NSString *)wordMeaningInput { return self.meaningField.stringValue; }
- (void)setWordSelectionRange:(NSRange)range { self.learningSourceTextView.selectedRange=range; }
- (void)setWordPickHidden:(BOOL)hidden { self.wordPickArea.hidden=hidden; }
- (void)setWordLemma:(NSString *)value { self.lemmaField.stringValue=value; }
- (void)setWordReading:(NSString *)value { self.readingField.stringValue=value; }
- (void)setWordMeaning:(NSString *)value { self.meaningField.stringValue=value; }
- (void)setWordStatus:(NSString *)value { self.vocabularyStatusLabel.stringValue=value; }
- (void)setWordSelectionLabel:(NSString *)value { self.vocabularySelectionLabel.stringValue=value; }
- (void)setWordSurfaceLabel:(NSString *)value { self.wordPickSurfaceLabel.stringValue=value; }
- (void)wordHostRefreshLearningStatus { [self.host refreshLearningStatus]; }
- (void)wordHostRefreshLearningSource { [self.host refreshLearningSource]; }
- (void)toggleLearningPin:(id)sender { [self.wordSelectionController toggleLearningPin:sender source:self]; }
- (void)vocabularyFormChanged:(id)sender { [self.wordSelectionController vocabularyFormChanged:sender source:self]; }
- (void)freezeLearningSentenceForSelection { [self.wordSelectionController freezeLearningSentenceForSelectionWithSource:self]; }
- (void)selectWordAtCharacterIndex:(NSUInteger)characterIndex { [self.wordSelectionController selectWordAtCharacterIndex:characterIndex source:self]; }
- (void)updateWordPickForSelection { [self.wordSelectionController updateWordPickForSelectionWithSource:self]; }
- (void)closeWordPick:(id)sender { [self.wordSelectionController closeWordPick:sender source:self]; }
- (void)pinLearningSentence:(id)sender { [self.wordSelectionController pinLearningSentence:sender source:self]; }
- (void)followLatestSentence:(id)sender { [self.wordSelectionController followLatestSentence:sender source:self]; }
- (NSString *)selectedLearningText { return [self.wordSelectionController selectedLearningTextWithSource:self]; }
- (void)bookmarkSelectedVocabulary:(id)sender { [self.wordSelectionController bookmarkSelectedVocabulary:sender source:self]; }
- (void)completeSelectedVocabulary:(id)sender { [self.wordSelectionController completeSelectedVocabulary:sender source:self]; }
- (void)syncCoordinatorToDisplayed { [self.wordSelectionController syncCoordinatorToDisplayedWithSource:self]; }

- (instancetype)initWithHost:(id<FYMainWindowControllerHost>)host {
    if ((self = [super init])) { _host = host; }
    return self;
}

// Explicit peer adapters. Every property has one owning controller.
- (NSButton *)analyzeButton { return self.host.analyzeButton; }
- (void)setAnalyzeButton:(NSButton *)value { self.host.analyzeButton = value; }
- (NSPanel *)captionAppearancePreviewPanel { return self.host.captionAppearancePreviewPanel; }
- (void)setCaptionAppearancePreviewPanel:(NSPanel *)value { self.host.captionAppearancePreviewPanel = value; }
- (FYAnalysisResult *)currentAnalysis { return self.host.currentAnalysis; }
- (void)setCurrentAnalysis:(FYAnalysisResult *)value { self.host.currentAnalysis = value; }
- (NSButton *)grammarPageAnalyzeButton { return self.host.grammarPageAnalyzeButton; }
- (void)setGrammarPageAnalyzeButton:(NSButton *)value { self.host.grammarPageAnalyzeButton = value; }
- (NSTextField *)grammarPinnedLabel { return self.host.grammarPinnedLabel; }
- (void)setGrammarPinnedLabel:(NSTextField *)value { self.host.grammarPinnedLabel = value; }
- (NSTextField *)grammarSourceLabel { return self.host.grammarSourceLabel; }
- (void)setGrammarSourceLabel:(NSTextField *)value { self.host.grammarSourceLabel = value; }
- (NSTextView *)grammarSourceTextView { return self.host.grammarSourceTextView; }
- (void)setGrammarSourceTextView:(NSTextView *)value { self.host.grammarSourceTextView = value; }
- (FYJapaneseTokenizer *)japaneseTokenizer { return self.host.japaneseTokenizer; }
- (void)setJapaneseTokenizer:(FYJapaneseTokenizer *)value { self.host.japaneseTokenizer = value; }
- (FYInlineLayoutResult *)lastInlineLayoutResult { return self.host.lastInlineLayoutResult; }
- (void)setLastInlineLayoutResult:(FYInlineLayoutResult *)value { self.host.lastInlineLayoutResult = value; }
- (BOOL)learningAnalysisBusy { return self.host.learningAnalysisBusy; }
- (void)setLearningAnalysisBusy:(BOOL)value { self.host.learningAnalysisBusy = value; }
- (FYLearningCoordinator *)learningCoordinator { return self.host.learningCoordinator; }
- (void)setLearningCoordinator:(FYLearningCoordinator *)value { self.host.learningCoordinator = value; }
- (FYStudyChatView *)mainStudyChatView { return self.host.mainStudyChatView; }
- (void)setMainStudyChatView:(FYStudyChatView *)value { self.host.mainStudyChatView = value; }
- (NSString *)referenceActiveWord { return self.host.referenceActiveWord; }
- (void)setReferenceActiveWord:(NSString *)value { self.host.referenceActiveWord = value; }
- (NSInteger)referenceRequestGeneration { return self.host.referenceRequestGeneration; }
- (void)setReferenceRequestGeneration:(NSInteger)value { self.host.referenceRequestGeneration = value; }
- (BOOL)sourceHoverSuspended { return self.host.sourceHoverSuspended; }
- (void)setSourceHoverSuspended:(BOOL)value { self.host.sourceHoverSuspended = value; }
- (NSTextField *)vocabularyStatusLabel { return self.host.vocabularyStatusLabel; }
- (void)setVocabularyStatusLabel:(NSTextField *)value { self.host.vocabularyStatusLabel = value; }

- (NSView *)makeRunSettingsPage { return [self.host makeRunSettingsPage]; }
- (NSView *)makeVocabularyPage { return [self.host makeVocabularyPage]; }
- (void)clearAnalysisDisplay { [self.host clearAnalysisDisplay]; }
- (void)refreshHistory { [self.host refreshHistory]; }
- (void)refreshVocabularyList { [self.host refreshVocabularyList]; }
- (void)clearArrangedSubviews:(NSStackView *)stack { [self.host clearArrangedSubviews:stack]; }
- (NSView *)translationCard { return [self.host translationCard]; }
- (NSStackView *)verticalStack { return [self.host verticalStack]; }
- (NSStackView *)horizontalStack { return [self.host horizontalStack]; }
- (NSView *)rowWithLabel:(NSString *)label view:(NSView *)view { return [self.host rowWithLabel:label view:view]; }
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color { return [self.host label:text font:font color:color]; }
- (NSTextField *)textField:(NSString *)placeholder { return [self.host textField:placeholder]; }
- (NSView *)spacer { return [self.host spacer]; }
- (NSView *)separator { return [self.host separator]; }
- (NSColor *)uiInk { return [self.host uiInk]; }
- (NSColor *)uiMuted { return [self.host uiMuted]; }
- (NSColor *)uiAccent { return [self.host uiAccent]; }
- (NSView *)cardWithStack:(NSStackView *)stack { return [self.host cardWithStack:stack]; }
- (void)pinFullWidth:(NSView *)view toStack:(NSStackView *)stack { [self.host pinFullWidth:view toStack:stack]; }
- (NSTextField *)cardTitle:(NSString *)text { return [self.host cardTitle:text]; }
- (NSTextField *)mutedLabel:(NSString *)text { return [self.host mutedLabel:text]; }
- (FYInlineBlockSnapshot *)inlineSnapshotForBlock:(FYInlineTextBlock *)block
                                      translation:(NSString *)translation
                                    stableBlockID:(NSString *)stableBlockID { return [self.host inlineSnapshotForBlock:block translation:translation stableBlockID:stableBlockID]; }
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot { [self.host openInlineLearningWithSnapshot:snapshot]; }
- (NSView *)makeAppearancePage { return [self.host makeAppearancePage]; }
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary { return [self.host workspaceButton:title action:action primary:primary]; }
- (NSTextField *)chipLabel:(NSString *)text { return [self.host chipLabel:text]; }
- (void)refreshLiveChips { [self.host refreshLiveChips]; }
- (void)applyGrammarTabSelection { [self.host applyGrammarTabSelection]; }
- (NSView *)makeHistoryPage { return [self.host makeHistoryPage]; }
- (NSView *)makeIntegratedGrammarCard { return [self.host makeIntegratedGrammarCard]; }
- (void)refreshSourceHoverTips { [self.host refreshSourceHoverTips]; }
- (FYStudyChatView *)makeStudyChatViewForOverlay:(BOOL)overlay { return [self.host makeStudyChatViewForOverlay:overlay]; }

- (void)createMainWindow {
    self.mainWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(140, 120, 1320, 1000)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    self.mainWindow.title = @"译芽";
    self.mainWindow.backgroundColor = FYAdventureColor(@"shell");
    self.mainWindow.minSize = NSMakeSize(720, 660);
    self.mainWindow.contentMinSize = NSMakeSize(720, 660);
    self.mainWindow.delegate = self.host;
    self.mainWindow.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];

    NSStackView *root = [[NSStackView alloc] init];
    root.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    root.spacing = 0;
    // 收起侧栏时把隐藏的聊天视图从布局中摘除，释放出的宽度直接给中间内容，不留空白占位。
    root.detachesHiddenViews = YES;
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *sidebar = [self makeSidebar];
    NSView *right = [[NSView alloc] init];
    right.translatesAutoresizingMaskIntoConstraints = NO;
    right.wantsLayer = YES;
    right.layer.backgroundColor = FYAdventureColor(@"canvas").CGColor;
    NSView *header = [self makeRunHeader];
    NSView *pageHost = [[NSView alloc] init];
    pageHost.translatesAutoresizingMaskIntoConstraints = NO;
    [right addSubview:header];
    [right addSubview:pageHost];

    NSScrollView *livePage = [self makePageScrollWithContent:[self makeLivePage]];
    NSScrollView *historyPage = [self makePageScrollWithContent:[self makeHistoryPage]];
    NSScrollView *vocabularyPage = [self makePageScrollWithContent:[self makeVocabularyPage]];
    NSScrollView *runSettingsPage = [self makePageScrollWithContent:[self makeRunSettingsPage]];
    NSScrollView *appearancePage = [self makePageScrollWithContent:[self makeAppearancePage]];
    NSScrollView *servicePage = [self makePageScrollWithContent:[self translationCard]];
    self.pages = @[livePage, historyPage, vocabularyPage, runSettingsPage, appearancePage, servicePage];
    // Only the selected page participates in layout. Hidden settings pages must
    // not impose their intrinsic minimum width on a learning page.
    self.learningPageHost = pageHost;

    [root addArrangedSubview:sidebar];
    [root addArrangedSubview:right];
    self.mainStudyChatView=[self makeStudyChatViewForOverlay:NO];
    [root addArrangedSubview:self.mainStudyChatView];
    self.mainChatWantsVisible = YES;
    self.workspaceWidth=[right.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-510];
    self.mainChatWidth=[self.mainStudyChatView.widthAnchor constraintEqualToConstant:320];

    self.mainWorkspaceRoot=root;
    FYFrameDrivenContentView *frameHost=[[FYFrameDrivenContentView alloc] initWithFrame:self.mainWindow.contentView.bounds];
    NSView *windowHost=frameHost.layoutContent;
    self.mainWindowContentWidth=frameHost.layoutWidth;
    windowHost.wantsLayer=YES;windowHost.layer.backgroundColor=FYAdventureColor(@"canvas").CGColor;
    FYAdventureBanner *banner=[FYAdventureBanner new];
    banner.translatesAutoresizingMaskIntoConstraints=NO;
    [windowHost addSubview:banner];
    [windowHost addSubview:root];
    [NSLayoutConstraint activateConstraints:@[[banner.leadingAnchor constraintEqualToAnchor:windowHost.leadingAnchor],
        [banner.trailingAnchor constraintEqualToAnchor:windowHost.trailingAnchor],
        [banner.topAnchor constraintEqualToAnchor:windowHost.topAnchor],
        [banner.heightAnchor constraintEqualToConstant:72]]];
    self.mainWindow.contentView = frameHost;
    self.mainWindowMinimumWidth = [frameHost.widthAnchor constraintGreaterThanOrEqualToConstant:1100];
    [NSLayoutConstraint activateConstraints:@[
        self.mainWindowMinimumWidth,
        [frameHost.heightAnchor constraintGreaterThanOrEqualToConstant:660]
    ]];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:windowHost.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:windowHost.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:banner.bottomAnchor],
        [root.bottomAnchor constraintEqualToAnchor:windowHost.bottomAnchor],
        [sidebar.widthAnchor constraintEqualToConstant:190],
        self.workspaceWidth, self.mainChatWidth,
        [self.mainStudyChatView.heightAnchor constraintEqualToAnchor:root.heightAnchor],
        [right.heightAnchor constraintEqualToAnchor:root.heightAnchor],
        [sidebar.heightAnchor constraintEqualToAnchor:root.heightAnchor],
        [header.leadingAnchor constraintEqualToAnchor:right.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:right.trailingAnchor],
        [header.topAnchor constraintEqualToAnchor:right.topAnchor],
        [header.heightAnchor constraintEqualToConstant:88],
        [pageHost.leadingAnchor constraintEqualToAnchor:right.leadingAnchor],
        [pageHost.trailingAnchor constraintEqualToAnchor:right.trailingAnchor],
        [pageHost.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [pageHost.bottomAnchor constraintEqualToAnchor:right.bottomAnchor]
    ]];
    [self updateMainChatToggle];
    [self selectPageAtIndex:0];
}

- (NSView *)makeSidebar {
    FYAdventurePanel *view=[FYAdventurePanel new];view.fillColor=FYAdventureColor(@"shell");
    view.translatesAutoresizingMaskIntoConstraints=NO;
    NSStackView *stack=[NSStackView new];stack.orientation=NSUserInterfaceLayoutOrientationVertical;
    stack.alignment=NSLayoutAttributeLeading;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;
    [view addSubview:stack];
    NSMutableArray *buttons=[NSMutableArray array];
    for(NSString *name in @[@"实时翻译",@"最近台词",@"单词学习",@"运行设置",@"字幕外观",@"翻译服务"]){
        if(buttons.count==3){NSView *line=[self separator];[stack addArrangedSubview:line];[line.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;}
        FYWorkspaceButton *button=[FYWorkspaceButton buttonWithTitle:name target:self.host action:@selector(selectPage:)];
        button.tag=buttons.count;button.navigation=YES;button.artworkIndex=buttons.count;
        button.bordered=NO;button.font=FYUIFont(15, NSFontWeightSemibold);
        button.accessibilityLabel=name;
        [stack addArrangedSubview:button];[button.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
        [button.heightAnchor constraintEqualToConstant:48].active=YES;[buttons addObject:button];
    }
    self.pageButtons=buttons;
    FYAdventureArtView *tree=[FYAdventureArtView new];tree.artwork=8;tree.translatesAutoresizingMaskIntoConstraints=NO;
    [view addSubview:tree];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:view.topAnchor constant:24],
        [tree.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:10],
        [tree.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-10],
        [tree.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-16],
        [tree.topAnchor constraintGreaterThanOrEqualToAnchor:stack.bottomAnchor constant:12],
        [tree.heightAnchor constraintGreaterThanOrEqualToConstant:0]]];
    NSLayoutConstraint *treeHeight=[tree.heightAnchor constraintEqualToConstant:166];treeHeight.priority=749;treeHeight.active=YES;
    return view;
}

- (NSView *)makeRunHeader {
    NSView *header = [[NSView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    NSStackView *content = [self horizontalStack];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:content];
    NSStackView *titles = [self verticalStack];
    titles.spacing = 4;
    self.headerTitleLabel = [self label:@"实时翻译" font:FYUIFont(27, NSFontWeightSemibold) color:[NSColor labelColor]];
    [titles addArrangedSubview:self.headerTitleLabel];
    self.headerDescriptionLabel = [self mutedLabel:@"画面、原句与学习入口放在一起"];
    [titles addArrangedSubview:self.headerDescriptionLabel];
    self.currentWindowLabel = [self label:@"当前窗口：未选择" font:FYUIFont(12, NSFontWeightRegular) color:[NSColor secondaryLabelColor]];
    self.currentWindowLabel.maximumNumberOfLines = 1;
    self.currentWindowLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [titles.widthAnchor constraintGreaterThanOrEqualToConstant:140].active = YES;
    self.headerDescriptionLabel.maximumNumberOfLines = 1;
    self.headerDescriptionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.headerDescriptionLabel setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [content addArrangedSubview:titles];
    [content addArrangedSubview:[self spacer]];
    self.runStateLabel = [self label:@"● 已暂停" font:FYUIFont(12, NSFontWeightSemibold) color:[NSColor secondaryLabelColor]];
    self.runStateLabel.maximumNumberOfLines=1;
    [self.runStateLabel setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [content addArrangedSubview:self.runStateLabel];
    self.runButton = [self workspaceButton:@"开始翻译" action:@selector(toggleRunning:) primary:YES];
    self.runButton.bezelStyle = NSBezelStyleRounded;
    self.runButton.bezelColor = self.uiAccent;
    self.runButton.contentTintColor = NSColor.whiteColor;
    [content addArrangedSubview:self.runButton];
    // 唯一的 AI 侧栏显隐开关：固定在主内容区头部（不随内容滚动、不属于侧栏），
    // 收起后依然可见，窄窗口下也不会被挤掉。
    self.mainChatToggle=[self workspaceButton:@"收起 AI 伙伴" action:@selector(toggleMainStudyChat:) primary:NO];
    self.mainChatToggle.accessibilityLabel=@"显示或隐藏 AI 伙伴侧栏";
    [self.mainChatToggle setContentHuggingPriority:999 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.mainChatToggle setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [content addArrangedSubview:self.mainChatToggle];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [content.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [content.centerYAnchor constraintEqualToAnchor:header.centerYAnchor]
    ]];
    return header;
}

- (NSScrollView *)makePageScrollWithContent:(NSView *)content {
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    NSView *document = [[FlippedDocumentView alloc] init];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = document;
    [document addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:16],
        [content.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-16],
        [content.topAnchor constraintEqualToAnchor:document.topAnchor constant:8],
        [content.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-16],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor]
    ]];
    return scroll;
}

- (void)selectPage:(NSButton *)sender {
    [self selectPageAtIndex:sender.tag];
}

- (void)selectPageAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.pages.count) { return; }
    FYMountLearningPage(self.pages, self.learningPageHost, index);
    self.selectedPage = index;
    [self updateMainChatForWindowWidth];
    if (index != 4) { [self.captionAppearancePreviewPanel orderOut:nil]; }
    self.headerTitleLabel.stringValue = @[@"实时翻译", @"最近台词", @"单词学习", @"运行设置", @"字幕外观", @"翻译服务"][index];
    self.headerDescriptionLabel.stringValue = @[@"读懂当前对白，再看懂它的语法。", @"把之前没看懂的对白，再读一遍。", @"收藏词语，带着原句复习", @"选择画面来源并调整识别方式", @"选一种配色，看看它在游戏里的样子。", @"配置翻译与学习分析服务"][index];
    // This one-line hint may truncate on every page; it must not enlarge the
    // window when the appearance page is mounted in a narrow workspace.
    [self.headerDescriptionLabel setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.currentWindowLabel.hidden = index != 0;
    if (index == 1) { [self refreshHistory]; }
    if (index == 2) { [self refreshVocabularyList]; }
    FYUpdateLearningPageSelection(self.pages, self.pageButtons, index);
}

- (NSView *)makeLivePage { return [self.livePageBuilder makePageWithReceiver:self]; }





































- (void)splitSpeakerAndBody:(NSString *)text speaker:(NSString * _Nullable * _Nullable)outSpeaker body:(NSString * _Nullable * _Nullable)outBody {
    [FYOCRManager splitSpeakerAndBody:text speaker:outSpeaker body:outBody];
}







- (void)toggleMainStudyChat:(id)sender {
    // 单一显隐状态：隐藏侧栏不销毁会话，聊天记录和草稿保持原样。
    self.mainChatWantsVisible = self.mainStudyChatView.hidden;
    [self updateMainChatForWindowWidth];
    [self.mainWindow.contentView layoutSubtreeIfNeeded];
}

- (void)updateMainChatForWindowWidth {
    if (!self.mainWindow || !self.mainStudyChatView || !self.workspaceWidth) { return; }
    // Resizing never changes the chosen layout. With the rail open, a shared
    // minimum keeps reading and settings usable without page-dependent jumps.
    BOOL showChat = self.mainChatWantsVisible;
    if (self.mainStudyChatView.hidden != !showChat) {
        self.mainStudyChatView.hidden = !showChat;
    }
    self.mainChatWidth.active = showChat;
    self.workspaceWidth.constant = showChat ? -510 : -190;
    CGFloat minimumWidth = showChat ? 1100 : 720;
    self.mainWindowMinimumWidth.constant = minimumWidth;
    NSSize contentMinimum = self.mainWindow.contentMinSize;
    if (contentMinimum.width != minimumWidth) {
        contentMinimum.width = minimumWidth;
        self.mainWindow.contentMinSize = contentMinimum;
    }
    [self updateMainChatToggle];
}

- (void)updateMainChatToggle {
    if (!self.mainChatToggle) { return; }
    self.mainChatToggle.title = self.mainStudyChatView.hidden ? @"展开 AI 伙伴" : @"收起 AI 伙伴";
    self.mainChatToggle.enabled = YES;
    self.mainChatToggle.toolTip = self.mainStudyChatView.hidden ? @"展开 AI 伙伴；空间不足时会放宽窗口" : @"收起后可把窗口缩得更窄";
}

- (void)windowDidResize:(NSNotification *)notification {
    if (notification.object != self.mainWindow) { return; }
    [self updateMainChatForWindowWidth];
    [self.mainWindow.contentView layoutSubtreeIfNeeded];
    [self updateLiveSourceReadingHeight];
}

@end
