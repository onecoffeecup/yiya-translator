#import "FYStudyPresentationController.h"
#import "../app/FYAppSupport.h"

@interface FYStudyPresentationController ()
@property(nonatomic, strong) NSSecureTextField *apiKeyField;
@property(nonatomic, strong) NSTextField *baseURLField;
@property(nonatomic, strong) NSPanel *captionPanel;
@property(nonatomic, strong) FYCaptureCardInput *captureCardInput;
@property(nonatomic, strong) NSArray<FYGrammarBookmark *> *grammarBookmarks;
@property(nonatomic, strong) FYGrammarCatalog *grammarCatalog;
@property(nonatomic, strong) NSSegmentedControl *languageControl;
@property(nonatomic, strong) FYLearningCoordinator *learningCoordinator;
@property(nonatomic, strong) NSTextField *learningModelField;
@property(nonatomic, strong) FYSelectableSourceTextView *learningSourceTextView;
@property(nonatomic, strong) FYLearningStore *learningStore;
@property(nonatomic, strong) NSTextField *learningTranslationLabel;
@property(nonatomic, strong) NSWindow *mainWindow;
@property(nonatomic, strong) NSTextField *modelField;
@property(nonatomic, strong) FYGrammarActionState *quickGrammarActions;
@property(nonatomic) NSUInteger quickSourceHoverGeneration;
@property(nonatomic) BOOL running;
@property(nonatomic, copy) NSArray<FYRequestIdentity *> *savedSentences;
@property(nonatomic) BOOL selectingCaptureRegion;
@end

@implementation FYStudyPresentationController
- (id)studyActionTarget { return self.host; }

@dynamic inlineBlockSnapshot, inlineReturnSnapshot, inlineReturnSourceText, quickSentenceID, quickSentenceSource, quickSentenceTranslation, quickSentenceVersion, quickSentenceRequested, quickSentenceGeneration, quickSentenceIsInlineBlock, studyChatOverlayRequested, quickSelectedGrammarIndex;
@synthesize studyNavigationCoordinator = _studyNavigationCoordinator;
- (FYStudyNavigationCoordinator *)studyNavigationCoordinator { if(!_studyNavigationCoordinator){_studyNavigationCoordinator=[FYStudyNavigationCoordinator new];}return _studyNavigationCoordinator; }
- (FYInlineBlockSnapshot *)inlineBlockSnapshot { return self.studyNavigationCoordinator.inlineBlockSnapshot; }
- (void)setInlineBlockSnapshot:(FYInlineBlockSnapshot *)value { self.studyNavigationCoordinator.inlineBlockSnapshot=value; }
- (FYInlineBlockSnapshot *)inlineReturnSnapshot { return self.studyNavigationCoordinator.inlineReturnSnapshot; }
- (void)setInlineReturnSnapshot:(FYInlineBlockSnapshot *)value { self.studyNavigationCoordinator.inlineReturnSnapshot=value; }
- (NSString *)inlineReturnSourceText { return self.studyNavigationCoordinator.inlineReturnSourceText; }
- (void)setInlineReturnSourceText:(NSString *)value { self.studyNavigationCoordinator.inlineReturnSourceText=value; }
- (NSString *)quickSentenceID { return self.studyNavigationCoordinator.quickSentenceID; }
- (void)setQuickSentenceID:(NSString *)value { self.studyNavigationCoordinator.quickSentenceID=value; }
- (NSString *)quickSentenceSource { return self.studyNavigationCoordinator.quickSentenceSource; }
- (void)setQuickSentenceSource:(NSString *)value { self.studyNavigationCoordinator.quickSentenceSource=value; }
- (NSString *)quickSentenceTranslation { return self.studyNavigationCoordinator.quickSentenceTranslation; }
- (void)setQuickSentenceTranslation:(NSString *)value { self.studyNavigationCoordinator.quickSentenceTranslation=value; }
- (NSInteger)quickSentenceVersion { return self.studyNavigationCoordinator.quickSentenceVersion; }
- (void)setQuickSentenceVersion:(NSInteger)value { self.studyNavigationCoordinator.quickSentenceVersion=value; }
- (BOOL)quickSentenceRequested { return self.studyNavigationCoordinator.quickSentenceRequested; }
- (void)setQuickSentenceRequested:(BOOL)value { self.studyNavigationCoordinator.quickSentenceRequested=value; }
- (NSInteger)quickSentenceGeneration { return self.studyNavigationCoordinator.quickSentenceGeneration; }
- (void)setQuickSentenceGeneration:(NSInteger)value { self.studyNavigationCoordinator.quickSentenceGeneration=value; }
- (BOOL)quickSentenceIsInlineBlock { return self.studyNavigationCoordinator.quickSentenceIsInlineBlock; }
- (void)setQuickSentenceIsInlineBlock:(BOOL)value { self.studyNavigationCoordinator.quickSentenceIsInlineBlock=value; }
- (BOOL)studyChatOverlayRequested { return self.studyNavigationCoordinator.studyChatOverlayRequested; }
- (void)setStudyChatOverlayRequested:(BOOL)value { self.studyNavigationCoordinator.studyChatOverlayRequested=value; }
- (NSInteger)quickSelectedGrammarIndex { return self.studyNavigationCoordinator.quickSelectedGrammarIndex; }
- (void)setQuickSelectedGrammarIndex:(NSInteger)value { self.studyNavigationCoordinator.quickSelectedGrammarIndex=value; }
- (void)hideStudyChatPanel { [self.studyChatPanel orderOut:nil]; }
- (BOOL)hasQuickSentencePanel { return self.quickSentencePanel!=nil; }
- (void)centerQuickSentencePanel { [self.quickSentencePanel center]; }
- (void)focusQuickSentencePanel { [self.quickSentencePanel makeKeyWindow]; }
- (void)activateStudyWorkspace { [self selectPageAtIndex:0];[self.mainWindow makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES]; }
- (NSUInteger)studyInlineInputEpoch { return self.captureCardInput.sessionEpoch; }
- (void)clearStudyChatDrafts { [self.mainStudyChatView setDraftText:@""];[self.overlayStudyChatView setDraftText:@""]; }

@dynamic quickAnalysisGeneration, quickSentenceAnalyzing, quickSentenceAnalysis, quickSentenceAnalysisError, quickSentenceAnalysisSource, quickSentenceAnalysisTranslation, quickSentenceAnalyzer, sentenceBookmarkPending, quickGrammarBookmarkPending;
@synthesize quickSentenceCoordinator = _quickSentenceCoordinator;
- (FYQuickSentenceCoordinator *)quickSentenceCoordinator { if(!_quickSentenceCoordinator){_quickSentenceCoordinator=[FYQuickSentenceCoordinator new];}return _quickSentenceCoordinator; }
- (NSInteger)quickAnalysisGeneration { return self.quickSentenceCoordinator.quickAnalysisGeneration; }
- (void)setQuickAnalysisGeneration:(NSInteger)value { self.quickSentenceCoordinator.quickAnalysisGeneration=value; }
- (BOOL)quickSentenceAnalyzing { return self.quickSentenceCoordinator.quickSentenceAnalyzing; }
- (void)setQuickSentenceAnalyzing:(BOOL)value { self.quickSentenceCoordinator.quickSentenceAnalyzing=value; }
- (FYAnalysisResult *)quickSentenceAnalysis { return self.quickSentenceCoordinator.quickSentenceAnalysis; }
- (void)setQuickSentenceAnalysis:(FYAnalysisResult *)value { self.quickSentenceCoordinator.quickSentenceAnalysis=value; }
- (NSString *)quickSentenceAnalysisError { return self.quickSentenceCoordinator.quickSentenceAnalysisError; }
- (void)setQuickSentenceAnalysisError:(NSString *)value { self.quickSentenceCoordinator.quickSentenceAnalysisError=value; }
- (NSString *)quickSentenceAnalysisSource { return self.quickSentenceCoordinator.quickSentenceAnalysisSource; }
- (void)setQuickSentenceAnalysisSource:(NSString *)value { self.quickSentenceCoordinator.quickSentenceAnalysisSource=value; }
- (NSString *)quickSentenceAnalysisTranslation { return self.quickSentenceCoordinator.quickSentenceAnalysisTranslation; }
- (void)setQuickSentenceAnalysisTranslation:(NSString *)value { self.quickSentenceCoordinator.quickSentenceAnalysisTranslation=value; }
- (FYLearningAnalyzer *)quickSentenceAnalyzer { return self.quickSentenceCoordinator.quickSentenceAnalyzer; }
- (void)setQuickSentenceAnalyzer:(FYLearningAnalyzer *)value { self.quickSentenceCoordinator.quickSentenceAnalyzer=value; }
- (BOOL)sentenceBookmarkPending { return self.quickSentenceCoordinator.sentenceBookmarkPending; }
- (void)setSentenceBookmarkPending:(BOOL)value { self.quickSentenceCoordinator.sentenceBookmarkPending=value; }
- (BOOL)quickGrammarBookmarkPending { return self.quickSentenceCoordinator.quickGrammarBookmarkPending; }
- (void)setQuickGrammarBookmarkPending:(BOOL)value { self.quickSentenceCoordinator.quickGrammarBookmarkPending=value; }
- (void)disableQuickSentenceBookmarkAction { self.quickSentenceBookmarkButton.enabled=NO; }
- (void)setQuickBookmarkStatusText:(NSString *)text { self.quickGrammarBookmarkStatus.stringValue=text; }
- (void)configureQuickSentenceAnalyzer:(FYLearningAnalyzer *)analyzer {
    analyzer.baseURL=self.baseURLField.stringValue ?: @"";analyzer.apiKey=self.apiKeyField.stringValue ?: @"";
    NSString *model=Trim(self.learningModelField.stringValue);
    analyzer.model=model.length?model:self.modelField.stringValue;analyzer.catalog=self.grammarCatalog;
}

@dynamic chatContextGeneration, chatResolvingSource;
@synthesize studyChatContextCoordinator = _studyChatContextCoordinator;
- (FYStudyChatContextCoordinator *)studyChatContextCoordinator { if(!_studyChatContextCoordinator){_studyChatContextCoordinator=[FYStudyChatContextCoordinator new];}return _studyChatContextCoordinator; }
- (NSInteger)chatContextGeneration { return self.studyChatContextCoordinator.chatContextGeneration; }
- (void)setChatContextGeneration:(NSInteger)value { self.studyChatContextCoordinator.chatContextGeneration=value; }
- (BOOL)chatResolvingSource { return self.studyChatContextCoordinator.chatResolvingSource; }
- (void)setChatResolvingSource:(BOOL)value { self.studyChatContextCoordinator.chatResolvingSource=value; }
- (BOOL)studyChatUsesDialogueMode { return [self effectiveModeSegment]==ContentModeDialogue; }
- (NSInteger)studyChatLanguageSegment { return self.languageControl.selectedSegment; }
- (NSString *)studyChatFallbackSource { return self.learningSourceTextView.string; }
- (NSString *)studyChatFallbackTranslation { return self.learningTranslationLabel.stringValue; }
- (void)clearStudyChatReturnSnapshot { self.inlineReturnSnapshot=nil;[self updateInlineReturnButtonVisibility]; }
- (void)restoreStudyChatDraftText:(NSString *)text { [self.mainStudyChatView restoreDraftText:text];[self.overlayStudyChatView restoreDraftText:text]; }
- (void)configureStudyChatAnalyzer:(FYLearningAnalyzer *)analyzer {
    analyzer.baseURL=self.baseURLField.stringValue ?: @"";analyzer.apiKey=self.apiKeyField.stringValue ?: @"";
    NSString *model=Trim(self.learningModelField.stringValue);analyzer.model=model.length?model:self.modelField.stringValue;
}
- (instancetype)initWithHost:(id<FYStudyPresentationControllerHost>)host {
    if ((self = [super init])) { _host = host; }
    return self;
}

// Explicit peer adapters. Every property has one owning controller.
- (NSInteger)analysisRequestGeneration { return self.host.analysisRequestGeneration; }
- (void)setAnalysisRequestGeneration:(NSInteger)value { self.host.analysisRequestGeneration = value; }
- (NSSecureTextField *)apiKeyField { return self.host.apiKeyField; }
- (void)setApiKeyField:(NSSecureTextField *)value { self.host.apiKeyField = value; }
- (NSTextField *)baseURLField { return self.host.baseURLField; }
- (void)setBaseURLField:(NSTextField *)value { self.host.baseURLField = value; }
- (NSPanel *)captionPanel { return self.host.captionPanel; }
- (void)setCaptionPanel:(NSPanel *)value { self.host.captionPanel = value; }
- (FYCaptureCardInput *)captureCardInput { return self.host.captureCardInput; }
- (void)setCaptureCardInput:(FYCaptureCardInput *)value { self.host.captureCardInput = value; }
- (FYAnalysisResult *)currentAnalysis { return self.host.currentAnalysis; }
- (void)setCurrentAnalysis:(FYAnalysisResult *)value { self.host.currentAnalysis = value; }
- (NSArray<FYGrammarBookmark *> *)grammarBookmarks { return self.host.grammarBookmarks; }
- (void)setGrammarBookmarks:(NSArray<FYGrammarBookmark *> *)value { self.host.grammarBookmarks = value; }
- (FYGrammarCatalog *)grammarCatalog { return self.host.grammarCatalog; }
- (void)setGrammarCatalog:(FYGrammarCatalog *)value { self.host.grammarCatalog = value; }
- (NSSegmentedControl *)languageControl { return self.host.languageControl; }
- (void)setLanguageControl:(NSSegmentedControl *)value { self.host.languageControl = value; }
- (FYLearningCoordinator *)learningCoordinator { return self.host.learningCoordinator; }
- (void)setLearningCoordinator:(FYLearningCoordinator *)value { self.host.learningCoordinator = value; }
- (NSTextField *)learningModelField { return self.host.learningModelField; }
- (void)setLearningModelField:(NSTextField *)value { self.host.learningModelField = value; }
- (FYSelectableSourceTextView *)learningSourceTextView { return self.host.learningSourceTextView; }
- (void)setLearningSourceTextView:(FYSelectableSourceTextView *)value { self.host.learningSourceTextView = value; }
- (FYLearningStore *)learningStore { return self.host.learningStore; }
- (void)setLearningStore:(FYLearningStore *)value { self.host.learningStore = value; }
- (NSTextField *)learningTranslationLabel { return self.host.learningTranslationLabel; }
- (void)setLearningTranslationLabel:(NSTextField *)value { self.host.learningTranslationLabel = value; }
- (NSWindow *)mainWindow { return self.host.mainWindow; }
- (void)setMainWindow:(NSWindow *)value { self.host.mainWindow = value; }
- (NSTextField *)modelField { return self.host.modelField; }
- (void)setModelField:(NSTextField *)value { self.host.modelField = value; }
- (FYGrammarActionState *)quickGrammarActions { return self.host.quickGrammarActions; }
- (void)setQuickGrammarActions:(FYGrammarActionState *)value { self.host.quickGrammarActions = value; }
- (NSUInteger)quickSourceHoverGeneration { return self.host.quickSourceHoverGeneration; }
- (void)setQuickSourceHoverGeneration:(NSUInteger)value { self.host.quickSourceHoverGeneration = value; }
- (BOOL)running { return self.host.running; }
- (void)setRunning:(BOOL)value { self.host.running = value; }
- (NSArray<FYRequestIdentity *> *)savedSentences { return self.host.savedSentences; }
- (void)setSavedSentences:(NSArray<FYRequestIdentity *> *)value { self.host.savedSentences = value; }
- (NSInteger)selectedGrammarIndex { return self.host.selectedGrammarIndex; }
- (void)setSelectedGrammarIndex:(NSInteger)value { self.host.selectedGrammarIndex = value; }
- (BOOL)selectingCaptureRegion { return self.host.selectingCaptureRegion; }
- (void)setSelectingCaptureRegion:(BOOL)value { self.host.selectingCaptureRegion = value; }

- (void)selectPageAtIndex:(NSInteger)index { [self.host selectPageAtIndex:index]; }
- (void)setAnalyzeBusy:(BOOL)busy { [self.host setAnalyzeBusy:busy]; }
- (void)analyzeCurrentSentence:(id)sender { [self.host analyzeCurrentSentence:sender]; }
- (void)refreshGrammarResults { [self.host refreshGrammarResults]; }
- (BOOL)analysisMatchesCurrentSentence { return [self.host analysisMatchesCurrentSentence]; }
- (void)clearAnalysisDisplay { [self.host clearAnalysisDisplay]; }
- (CGFloat)structureScrollOffsetForQuick:(BOOL)quick { return [self.host structureScrollOffsetForQuick:quick]; }
- (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick { [self.host restoreStructureScrollOffset:offset quick:quick]; }
- (void)refreshLearningSource { [self.host refreshLearningSource]; }
- (void)refreshLearningStatus { [self.host refreshLearningStatus]; }
- (void)refreshGrammarBookmarks:(id)sender { [self.host refreshGrammarBookmarks:sender]; }
- (NSStackView *)verticalStack { return [self.host verticalStack]; }
- (NSStackView *)horizontalStack { return [self.host horizontalStack]; }
- (NSView *)spacer { return [self.host spacer]; }
- (NSView *)separator { return [self.host separator]; }
- (NSColor *)uiInk { return [self.host uiInk]; }
- (NSColor *)uiMuted { return [self.host uiMuted]; }
- (NSColor *)uiBorder { return [self.host uiBorder]; }
- (NSColor *)uiAccent { return [self.host uiAccent]; }
- (NSColor *)uiSelected { return [self.host uiSelected]; }
- (NSColor *)uiSurface { return [self.host uiSurface]; }
- (NSView *)card { return [self.host card]; }
- (NSTextField *)mutedLabel:(NSString *)text { return [self.host mutedLabel:text]; }
- (BOOL)translationTargetIsForeground { return [self.host translationTargetIsForeground]; }
- (void)refreshOverlayVisibility:(id)sender { [self.host refreshOverlayVisibility:sender]; }
- (BOOL)captureCardInputEnabled { return [self.host captureCardInputEnabled]; }
- (uint32_t)selectedWindowID { return [self.host selectedWindowID]; }
- (NSInteger)effectiveModeSegment { return [self.host effectiveModeSegment]; }
- (void)showError:(NSString *)error { [self.host showError:error]; }
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary { return [self.host workspaceButton:title action:action primary:primary]; }
- (void)refreshQuickSentenceHoverTips { [self.host refreshQuickSentenceHoverTips]; }
- (void)captureLatestStudySentenceWithCompletion:(void (^)(NSString *,NSError *))completion { [self.host captureLatestStudySentenceWithCompletion:completion]; }
- (NSView *)structureViewForAnalysis:(FYAnalysisResult *)analysis source:(NSString *)source quick:(BOOL)quick { return [self.host structureViewForAnalysis:analysis source:source quick:quick]; }
- (void)refreshSavedSentences { [self.host refreshSavedSentences]; }
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick { return [self.host grammarActionsForQuick:quick]; }
- (void)updateGrammarActionControlsForQuick:(BOOL)quick { [self.host updateGrammarActionControlsForQuick:quick]; }

- (void)ensureStudyChatSession {
    if(self.studyChatSession){return;}
    self.studyChatSession=[FYStudyChatSession new];
    __weak typeof(self) weakSelf=self;
    self.studyChatSession.onChange=^{[weakSelf refreshStudyChatViews];};
}

- (FYStudyChatView *)makeStudyChatViewForOverlay:(BOOL)overlay { return [FYStudyChatRenderer makeStudyChatViewForOverlay:overlay receiver:self]; }

- (void)referenceLatestStudySentence:(id)sender { [self.studyChatContextCoordinator referenceLatestWithReceiver:self]; }

- (void)resolveLatestStudyIdentity:(void (^)(FYRequestIdentity *))completion { [self.studyChatContextCoordinator resolveLatestIdentity:completion receiver:self]; }

- (void)resolveLatestStudySentence:(void (^)(NSString *,NSString *))completion { [self.studyChatContextCoordinator resolveLatestSentence:completion receiver:self]; }

- (void)askQuickSentence:(id)sender { [self.studyNavigationCoordinator askQuickSentence:sender receiver:self]; }

- (void)refreshStudyChatViews { [FYStudyChatRenderer refreshStudyChatViewsWithReceiver:self]; }

- (void)sendStudyChat:(NSString *)text { [self.studyChatContextCoordinator send:text receiver:self]; }

- (void)configureStudyOverlay:(NSPanel *)panel { [FYStudyChatRenderer configureStudyOverlay:panel receiver:self]; }

- (void)showStudyChatOverlay:(id)sender {
    if(![self translationTargetIsForeground]){return;}
    [self ensureStudyChatSession];if(!self.studyChatSession.source.length){[self referenceLatestStudySentence:nil];}
    if(!self.studyChatPanel){
        self.studyChatPanel=[[FYStudyOverlayPanel alloc] initWithContentRect:NSMakeRect(0,0,340,660) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        [self configureStudyOverlay:self.studyChatPanel];self.overlayStudyChatView=[self makeStudyChatViewForOverlay:YES];
        NSView *host=[[NSView alloc] initWithFrame:NSMakeRect(0,0,340,660)];
        host.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
        [host addSubview:self.overlayStudyChatView];
        [NSLayoutConstraint activateConstraints:@[
            [self.overlayStudyChatView.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
            [self.overlayStudyChatView.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
            [self.overlayStudyChatView.topAnchor constraintEqualToAnchor:host.topAnchor],
            [self.overlayStudyChatView.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
        ]];
        self.studyChatPanel.contentView=host;
        self.studyChatPanel.minSize=NSMakeSize(340,500);
        self.studyChatPanel.maxSize=NSMakeSize(4096,4096);
        NSScreen *screen=self.captionPanel.screen ?: NSScreen.mainScreen;NSRect frame=screen.visibleFrame;
        [self.studyChatPanel setFrame:NSMakeRect(NSMaxX(frame)-360,NSMinY(frame)+24,340,MIN(720,NSHeight(frame)-48)) display:YES];
        __weak typeof(self) weakSelf=self;self.studyChatPanel.onEscape=^{[weakSelf closeStudyOverlay:nil];};
    }
    [self updateInlineReturnButtonVisibility];
    self.studyChatOverlayRequested=YES;self.quickSentenceRequested=NO;self.quickSentenceGeneration++;[self.quickSourceTextView dismissSourceHover];[self cancelQuickSentenceAnalysis];[self.quickSentencePanel orderOut:nil];
    [self refreshStudyChatViews];[self.studyChatPanel orderFrontRegardless];[self.studyChatPanel makeKeyWindow];[self.overlayStudyChatView focusInput];
}

- (void)closeStudyOverlay:(id)sender {
    self.studyChatOverlayRequested=NO;self.quickSentenceRequested=NO;self.quickSentenceGeneration++;[self cancelQuickSentenceAnalysis];
    [self.quickSourceTextView dismissSourceHover];
    [self.studyChatPanel orderOut:nil];[self.quickSentencePanel orderOut:nil];
    // 关闭/Esc 回到游戏，清除「返回语法」关系，避免残留指向旧块的返回入口。
    self.inlineReturnSnapshot=nil;[self updateInlineReturnButtonVisibility];
    [self refreshOverlayVisibility:nil];
}

- (void)cancelQuickSentenceAnalysis { [self.quickSentenceCoordinator cancelAnalysisWithReceiver:self]; }

- (void)analyzeQuickSentence:(id)sender { [self.quickSentenceCoordinator analyzeWithReceiver:self]; }

- (void)showQuickSentence:(id)sender { [self.studyNavigationCoordinator showQuickSentenceWithReceiver:self]; }

- (void)selectQuickStructure:(NSButton *)sender { [FYQuickSentenceRenderer selectQuickStructure:sender receiver:self]; }

- (BOOL)quickSentenceIsBookmarked { return [self.quickSentenceCoordinator sentenceIsBookmarkedWithReceiver:self]; }

- (void)bookmarkQuickSentence:(id)sender { [self.quickSentenceCoordinator bookmarkSentenceWithReceiver:self]; }

- (FYGrammarBookmark *)quickGrammarBookmark { return [self.quickSentenceCoordinator grammarBookmarkWithReceiver:self]; }

- (void)updateQuickGrammarBookmark { [FYQuickSentenceRenderer updateQuickGrammarBookmarkWithReceiver:self]; }

- (void)bookmarkQuickGrammar:(id)sender { [self.quickSentenceCoordinator bookmarkGrammarWithReceiver:self]; }

- (NSView *)quickGrammarDetailForItem:(FYGrammarItem *)item { return [FYQuickSentenceRenderer quickGrammarDetailForItem:item receiver:self]; }

- (void)selectQuickGrammar:(NSButton *)sender { [FYQuickSentenceRenderer selectQuickGrammar:sender receiver:self]; }

- (NSTextField *)quickReadingLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color { return [FYQuickSentenceRenderer quickReadingLabel:text size:size weight:weight color:color receiver:self]; }

- (NSView *)quickReadingCard:(NSStackView *)stack tinted:(BOOL)tinted { return [FYQuickSentenceRenderer quickReadingCard:stack tinted:tinted receiver:self]; }

- (void)renderQuickSentence { [FYQuickSentenceRenderer renderQuickSentenceWithReceiver:self]; }

- (void)openStudyWorkspace:(id)sender { [self.studyNavigationCoordinator openWorkspaceWithReceiver:self]; }

- (void)openInlineLearningForBlockText:(NSString *)source translation:(NSString *)translation { [self.studyNavigationCoordinator openInlineText:source translation:translation receiver:self]; }

- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot { [self.studyNavigationCoordinator openInlineSnapshot:snapshot receiver:self]; }

- (void)bindInlineStudyChatToSource:(NSString *)source translation:(NSString *)translation { [self.studyNavigationCoordinator bindInlineChatToSource:source translation:translation receiver:self]; }

- (void)returnFromStudyChatToInlineLearning:(id)sender { [self.studyNavigationCoordinator returnFromChatWithReceiver:self]; }

- (NSScrollView *)quickSentenceScrollView { return [FYStudyScrollRenderer quickSentenceScrollViewWithReceiver:self]; }

- (void)captureQuickSentenceScrollPosition { [FYStudyScrollRenderer captureQuickSentenceScrollPositionWithReceiver:self]; }

- (void)restoreQuickSentenceScrollPosition { [FYStudyScrollRenderer restoreQuickSentenceScrollPositionWithReceiver:self]; }

- (void)updateInlineReturnButtonVisibility { [FYStudyChatRenderer updateInlineReturnButtonVisibilityWithReceiver:self]; }

@end
