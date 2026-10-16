#import "FYGrammarPresentationController.h"
#import "FYGrammarPageBuilder.h"
#import "FYGrammarResultsRenderer.h"
#import "FYGrammarDetailRenderer.h"
#import "FYGrammarScrollRenderer.h"
#import "../learning/FYLearningViews.h"
#import "../learning/FYStudyOverlayPanel.h"
#import "FYPresentationText.h"
#import <QuartzCore/QuartzCore.h>

@interface FYGrammarPresentationController ()
@property(nonatomic, strong) NSSecureTextField *apiKeyField;
@property(nonatomic, strong) NSTextField *baseURLField;
@property(nonatomic, strong) NSArray<FYGrammarBookmark *> *grammarBookmarks;
@property(nonatomic, strong) FYGrammarCatalog *grammarCatalog;
@property(nonatomic, strong) FYLearningAnalyzer *learningAnalyzer;
@property(nonatomic, strong) FYLearningCoordinator *learningCoordinator;
@property(nonatomic, strong) NSTextField *learningModelField;
@property(nonatomic, strong) FYSelectableSourceTextView *learningSourceTextView;
@property(nonatomic, strong) FYLearningStore *learningStore;
@property(nonatomic, strong) NSTextField *liveLevelTag;
@property(nonatomic, strong) NSTextField *modelField;
@property(nonatomic, strong) NSView *quickGrammarDetailCard;
@property(nonatomic, strong) NSButton *quickGrammarExpandButton;
@property(nonatomic, strong) NSButton *quickGrammarReviewButton;
@property(nonatomic, strong) NSTextField *quickGrammarReviewStatus;
@property(nonatomic, strong) NSStackView *quickGrammarStack;
@property(nonatomic) NSInteger quickSelectedGrammarIndex;
@property(nonatomic, strong) FYAnalysisResult *quickSentenceAnalysis;
@property(nonatomic, copy) NSString *quickSentenceAnalysisSource;
@property(nonatomic, strong) FYLearningAnalyzer *quickSentenceAnalyzer;
@property(nonatomic) BOOL quickSentenceAnalyzing;
@property(nonatomic, copy) NSString *quickSentenceID;
@property(nonatomic, strong) FYStudyOverlayPanel *quickSentencePanel;
@property(nonatomic, copy) NSString *quickSentenceSource;
@property(nonatomic, copy) NSString *quickSentenceTranslation;
@property(nonatomic) NSInteger quickSentenceVersion;
@property(nonatomic, copy) NSArray<NSButton *> *quickStructureButtons;
@property(nonatomic, strong) NSScrollView *quickStructureScrollView;
@end

@implementation FYGrammarPresentationController

- (BOOL)grammarBookmarkActionEnabled { return self.grammarDetailBookmarkButton.enabled; }
- (void)setGrammarBookmarkActionEnabled:(BOOL)enabled { self.grammarDetailBookmarkButton.enabled = enabled; }

- (id)grammarControlTarget { return self.host; }

@dynamic analysisRequestGeneration, followupRequestGeneration, learningAnalysisBusy, grammarAnalysisError, currentAnalysis, grammarActions, quickGrammarActions;
@synthesize grammarInteractionCoordinator = _grammarInteractionCoordinator;
- (FYGrammarInteractionCoordinator *)grammarInteractionCoordinator { if(!_grammarInteractionCoordinator){_grammarInteractionCoordinator=[FYGrammarInteractionCoordinator new];}return _grammarInteractionCoordinator; }
- (NSInteger)analysisRequestGeneration { return self.grammarInteractionCoordinator.analysisRequestGeneration; }
- (void)setAnalysisRequestGeneration:(NSInteger)value { self.grammarInteractionCoordinator.analysisRequestGeneration=value; }
- (NSInteger)followupRequestGeneration { return self.grammarInteractionCoordinator.followupRequestGeneration; }
- (void)setFollowupRequestGeneration:(NSInteger)value { self.grammarInteractionCoordinator.followupRequestGeneration=value; }
- (BOOL)learningAnalysisBusy { return self.grammarInteractionCoordinator.learningAnalysisBusy; }
- (void)setLearningAnalysisBusy:(BOOL)value { self.grammarInteractionCoordinator.learningAnalysisBusy=value; }
- (NSString *)grammarAnalysisError { return self.grammarInteractionCoordinator.grammarAnalysisError; }
- (void)setGrammarAnalysisError:(NSString *)value { self.grammarInteractionCoordinator.grammarAnalysisError=value; }
- (FYAnalysisResult *)currentAnalysis { return self.grammarInteractionCoordinator.currentAnalysis; }
- (void)setCurrentAnalysis:(FYAnalysisResult *)value { self.grammarInteractionCoordinator.currentAnalysis=value; }
- (FYGrammarActionState *)grammarActions { return self.grammarInteractionCoordinator.grammarActions; }
- (void)setGrammarActions:(FYGrammarActionState *)value { self.grammarInteractionCoordinator.grammarActions=value; }
- (FYGrammarActionState *)quickGrammarActions { return self.grammarInteractionCoordinator.quickGrammarActions; }
- (void)setQuickGrammarActions:(FYGrammarActionState *)value { self.grammarInteractionCoordinator.quickGrammarActions=value; }
- (void)analyzeCurrentSentence:(id)sender { [self.grammarInteractionCoordinator analyzeCurrentSentenceWithReceiver:self]; }
- (void)requestGrammarFollowupExample:(BOOL)example { [self.grammarInteractionCoordinator requestGrammarFollowupExample:example receiver:self]; }
- (void)requestGrammarQuestion:(NSString *)question { [self.grammarInteractionCoordinator requestGrammarQuestion:question receiver:self]; }
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick { return [self.grammarInteractionCoordinator grammarActionsForQuick:quick receiver:self]; }
- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick { return [self.grammarInteractionCoordinator grammarActionItemForQuick:quick receiver:self]; }
- (void)toggleGrammarExplanation:(NSButton *)sender { BOOL quick=sender.tag==1;[self.grammarInteractionCoordinator toggleGrammarExplanationForQuick:quick receiver:self]; }
- (void)reviewGrammarSentence:(NSButton *)sender { BOOL quick=sender.tag==1;[self.grammarInteractionCoordinator reviewGrammarSentenceForQuick:quick receiver:self]; }
- (FYGrammarServiceConfiguration *)grammarServiceConfiguration {
    NSString *model=Trim(self.learningModelField.stringValue);if(!model.length){model=self.modelField.stringValue?:@"";}
    NSString *base=self.baseURLField.stringValue?:@"",*key=self.apiKeyField.stringValue?:@"";
    return [[FYGrammarServiceConfiguration alloc]initWithBaseURL:base model:model apiKey:key];
}
- (void)setGrammarStatusText:(NSString *)text { self.grammarStatusLabel.stringValue=text; }
- (void)setGrammarStatusToErrorColor { self.grammarStatusLabel.textColor=NSColor.systemRedColor; }
- (void)setGrammarDetailNameText:(NSString *)text { self.grammarDetailNameLabel.stringValue=text; }
- (void)setGrammarDetailBodyText:(NSString *)text { self.grammarDetailBodyLabel.stringValue=text; }
- (void)setGrammarFollowupText:(NSString *)text { self.grammarFollowupResultLabel.stringValue=text; }
- (void)setGrammarQuickAnalysisResult:(FYAnalysisResult *)result { self.quickSentenceAnalysis=result; }

- (instancetype)initWithHost:(id<FYGrammarPresentationControllerHost>)host {
    if ((self = [super init])) { _host = host; }
    return self;
}

// Explicit peer adapters. Every property has one owning controller.
- (NSSecureTextField *)apiKeyField { return self.host.apiKeyField; }
- (void)setApiKeyField:(NSSecureTextField *)value { self.host.apiKeyField = value; }
- (NSTextField *)baseURLField { return self.host.baseURLField; }
- (void)setBaseURLField:(NSTextField *)value { self.host.baseURLField = value; }
- (NSArray<FYGrammarBookmark *> *)grammarBookmarks { return self.host.grammarBookmarks; }
- (void)setGrammarBookmarks:(NSArray<FYGrammarBookmark *> *)value { self.host.grammarBookmarks = value; }
- (FYGrammarCatalog *)grammarCatalog { return self.host.grammarCatalog; }
- (void)setGrammarCatalog:(FYGrammarCatalog *)value { self.host.grammarCatalog = value; }
- (FYLearningAnalyzer *)learningAnalyzer { return self.host.learningAnalyzer; }
- (void)setLearningAnalyzer:(FYLearningAnalyzer *)value { self.host.learningAnalyzer = value; }
- (FYLearningCoordinator *)learningCoordinator { return self.host.learningCoordinator; }
- (void)setLearningCoordinator:(FYLearningCoordinator *)value { self.host.learningCoordinator = value; }
- (NSTextField *)learningModelField { return self.host.learningModelField; }
- (void)setLearningModelField:(NSTextField *)value { self.host.learningModelField = value; }
- (FYSelectableSourceTextView *)learningSourceTextView { return self.host.learningSourceTextView; }
- (void)setLearningSourceTextView:(FYSelectableSourceTextView *)value { self.host.learningSourceTextView = value; }
- (FYLearningStore *)learningStore { return self.host.learningStore; }
- (void)setLearningStore:(FYLearningStore *)value { self.host.learningStore = value; }
- (NSTextField *)liveLevelTag { return self.host.liveLevelTag; }
- (void)setLiveLevelTag:(NSTextField *)value { self.host.liveLevelTag = value; }
- (NSTextField *)modelField { return self.host.modelField; }
- (void)setModelField:(NSTextField *)value { self.host.modelField = value; }
- (NSView *)quickGrammarDetailCard { return self.host.quickGrammarDetailCard; }
- (void)setQuickGrammarDetailCard:(NSView *)value { self.host.quickGrammarDetailCard = value; }
- (NSButton *)quickGrammarExpandButton { return self.host.quickGrammarExpandButton; }
- (void)setQuickGrammarExpandButton:(NSButton *)value { self.host.quickGrammarExpandButton = value; }
- (NSButton *)quickGrammarReviewButton { return self.host.quickGrammarReviewButton; }
- (void)setQuickGrammarReviewButton:(NSButton *)value { self.host.quickGrammarReviewButton = value; }
- (NSTextField *)quickGrammarReviewStatus { return self.host.quickGrammarReviewStatus; }
- (void)setQuickGrammarReviewStatus:(NSTextField *)value { self.host.quickGrammarReviewStatus = value; }
- (NSStackView *)quickGrammarStack { return self.host.quickGrammarStack; }
- (void)setQuickGrammarStack:(NSStackView *)value { self.host.quickGrammarStack = value; }
- (NSInteger)quickSelectedGrammarIndex { return self.host.quickSelectedGrammarIndex; }
- (void)setQuickSelectedGrammarIndex:(NSInteger)value { self.host.quickSelectedGrammarIndex = value; }
- (FYAnalysisResult *)quickSentenceAnalysis { return self.host.quickSentenceAnalysis; }
- (void)setQuickSentenceAnalysis:(FYAnalysisResult *)value { self.host.quickSentenceAnalysis = value; }
- (NSString *)quickSentenceAnalysisSource { return self.host.quickSentenceAnalysisSource; }
- (void)setQuickSentenceAnalysisSource:(NSString *)value { self.host.quickSentenceAnalysisSource = value; }
- (FYLearningAnalyzer *)quickSentenceAnalyzer { return self.host.quickSentenceAnalyzer; }
- (void)setQuickSentenceAnalyzer:(FYLearningAnalyzer *)value { self.host.quickSentenceAnalyzer = value; }
- (BOOL)quickSentenceAnalyzing { return self.host.quickSentenceAnalyzing; }
- (void)setQuickSentenceAnalyzing:(BOOL)value { self.host.quickSentenceAnalyzing = value; }
- (NSString *)quickSentenceID { return self.host.quickSentenceID; }
- (void)setQuickSentenceID:(NSString *)value { self.host.quickSentenceID = value; }
- (FYStudyOverlayPanel *)quickSentencePanel { return self.host.quickSentencePanel; }
- (void)setQuickSentencePanel:(FYStudyOverlayPanel *)value { self.host.quickSentencePanel = value; }
- (NSString *)quickSentenceSource { return self.host.quickSentenceSource; }
- (void)setQuickSentenceSource:(NSString *)value { self.host.quickSentenceSource = value; }
- (NSString *)quickSentenceTranslation { return self.host.quickSentenceTranslation; }
- (void)setQuickSentenceTranslation:(NSString *)value { self.host.quickSentenceTranslation = value; }
- (NSInteger)quickSentenceVersion { return self.host.quickSentenceVersion; }
- (void)setQuickSentenceVersion:(NSInteger)value { self.host.quickSentenceVersion = value; }
- (NSArray<NSButton *> *)quickStructureButtons { return self.host.quickStructureButtons; }
- (void)setQuickStructureButtons:(NSArray<NSButton *> *)value { self.host.quickStructureButtons = value; }
- (NSScrollView *)quickStructureScrollView { return self.host.quickStructureScrollView; }
- (void)setQuickStructureScrollView:(NSScrollView *)value { self.host.quickStructureScrollView = value; }

- (void)syncLearningAnalyzerConfig { [self.host syncLearningAnalyzerConfig]; }
- (void)selectPageAtIndex:(NSInteger)index { [self.host selectPageAtIndex:index]; }
- (void)syncCoordinatorToDisplayed { [self.host syncCoordinatorToDisplayed]; }
- (nullable NSString *)currentSentenceLevelTag { return [self.host currentSentenceLevelTag]; }
- (void)refreshLearningStatus { [self.host refreshLearningStatus]; }
- (void)clearArrangedSubviews:(NSStackView *)stack { [self.host clearArrangedSubviews:stack]; }
- (void)refreshGrammarBookmarks:(id)sender { [self.host refreshGrammarBookmarks:sender]; }
- (NSStackView *)verticalStack { return [self.host verticalStack]; }
- (NSStackView *)horizontalStack { return [self.host horizontalStack]; }
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color { return [self.host label:text font:font color:color]; }
- (NSTextField *)textField:(NSString *)placeholder { return [self.host textField:placeholder]; }
- (NSView *)spacer { return [self.host spacer]; }
- (NSColor *)uiInk { return [self.host uiInk]; }
- (NSColor *)uiMuted { return [self.host uiMuted]; }
- (NSColor *)uiBorder { return [self.host uiBorder]; }
- (NSColor *)uiAccent { return [self.host uiAccent]; }
- (NSColor *)uiSelected { return [self.host uiSelected]; }
- (NSColor *)uiSurface { return [self.host uiSurface]; }
- (NSView *)card { return [self.host card]; }
- (NSView *)cardWithStack:(NSStackView *)stack { return [self.host cardWithStack:stack]; }
- (NSTextField *)cardTitle:(NSString *)text { return [self.host cardTitle:text]; }
- (NSTextField *)mutedLabel:(NSString *)text { return [self.host mutedLabel:text]; }
- (NSScrollView *)quickSentenceScrollView { return [self.host quickSentenceScrollView]; }
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary { return [self.host workspaceButton:title action:action primary:primary]; }
- (void)refreshSourceHoverTips { [self.host refreshSourceHoverTips]; }
- (NSView *)quickGrammarDetailForItem:(FYGrammarItem *)item { return [self.host quickGrammarDetailForItem:item]; }
- (NSTextField *)quickReadingLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color { return [self.host quickReadingLabel:text size:size weight:weight color:color]; }
- (void)renderQuickSentence { [self.host renderQuickSentence]; }

- (void)grammarSelectorChanged:(id)sender {
    // 追问与收藏均按 selector 当前选中项执行；无需额外处理。
}

- (void)setAnalyzeBusy:(BOOL)busy { [FYGrammarResultsRenderer setAnalyzeBusy:busy receiver:self]; }



- (void)refreshGrammarResults { [FYGrammarResultsRenderer refreshGrammarResultsWithReceiver:self]; }

- (void)renderGrammarDetailAtIndex:(NSInteger)index { [FYGrammarDetailRenderer renderGrammarDetailAtIndex:index source:self]; }

- (void)openGrammarSource:(id)sender {
    NSURL *url = [NSURL URLWithString:[self selectedGrammarItem].levelSourceURL ?: @""];
    if ([url.scheme.lowercaseString isEqualToString:@"https"] || [url.scheme.lowercaseString isEqualToString:@"http"]) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (FYGrammarBookmark *)bookmarkForCurrentGrammar {
    FYGrammarItem *item = [self selectedGrammarItem];
    return [FYLearningCoordinator bookmarkInList:self.grammarBookmarks grammarName:item.name
        sentenceID:self.currentAnalysis.sentenceID version:self.currentAnalysis.version];
}

- (BOOL)analysisMatchesCurrentSentence {
    return self.currentAnalysis && [FYLearningCoordinator analysisMatchesSentenceID:self.currentAnalysis.sentenceID version:self.currentAnalysis.version
        currentSentenceID:self.learningCoordinator.currentSentenceID currentVersion:self.learningCoordinator.currentVersion];
}

- (void)highlightGrammarMatches { [FYGrammarDetailRenderer highlightGrammarMatchesWithSource:self]; }

- (void)applyHighlight:(NSColor *)color toTextView:(NSTextView *)textView { [FYGrammarDetailRenderer applyHighlight:color toTextView:textView source:self]; }

- (void)clearGrammarHighlight { [FYGrammarDetailRenderer clearGrammarHighlightWithSource:self]; }

- (void)clearAnalysisDisplay { [FYGrammarResultsRenderer clearAnalysisDisplayWithReceiver:self]; }

- (void)bookmarkGrammarItem:(NSButton *)sender { [FYGrammarInteractionCoordinator bookmarkGrammarItemWithIndexProvider:^NSInteger { return sender.tag; } receiver:self]; }

- (void)bookmarkSelectedGrammar:(id)sender { [FYGrammarInteractionCoordinator bookmarkSelectedGrammarWithReceiver:self]; }

- (void)selectGrammarItem:(NSButton *)sender {
    if (!self.currentAnalysis) { return; }
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)self.currentAnalysis.grammar.count) { return; }
    self.selectedGrammarIndex = index;
    self.grammarActions.expandedItem = nil;
    // 只更新高亮与详情：重建结构图会连带新建 NSScrollView，横向滚动位置会丢。
    [self applyGrammarSelectionLocally];
}

- (void)applyGrammarSelectionLocally { [FYGrammarDetailRenderer applyGrammarSelectionLocallyWithSource:self]; }

- (CGFloat)structureScrollOffsetForQuick:(BOOL)quick { return [FYGrammarScrollRenderer structureScrollOffsetForQuick:quick source:self]; }

- (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick { [FYGrammarScrollRenderer restoreStructureScrollOffset:offset quick:quick source:self]; }

- (FYGrammarItem *)selectedGrammarItem {
    return [FYLearningCoordinator grammarItemInList:self.currentAnalysis.grammar index:self.selectedGrammarIndex fallbackToFirst:YES];
}

- (void)backToSourcePage:(id)sender {
    [self selectPageAtIndex:0];
}

- (void)simplerExplanationForGrammar:(id)sender { [self requestGrammarFollowupExample:NO]; }

- (void)exampleSentenceForGrammar:(id)sender { [self requestGrammarFollowupExample:YES]; }



- (NSView *)structureViewForAnalysis:(FYAnalysisResult *)analysis source:(NSString *)source quick:(BOOL)quick { return [FYGrammarPageBuilder structureViewForAnalysis:analysis source:source quick:quick receiver:self]; }

- (void)selectMainStructure:(NSButton *)sender {
    if(sender.tag>=0){[self selectGrammarItem:sender];}
    else{self.grammarStatusLabel.stringValue=@"该片段的含义见结构图，未对应独立的语法条目。";}
}

- (NSView *)grammarInfoCellWithLabel:(NSString *)labelText value:(NSString *)valueText { return [FYGrammarPageBuilder grammarInfoCellWithLabel:labelText value:valueText receiver:self]; }

- (void)selectGrammarTab:(NSButton *)sender {
    self.selectedGrammarTab = sender.tag;
    [self applyGrammarTabSelection];
}

- (void)applyGrammarTabSelection { [FYGrammarResultsRenderer applyGrammarTabSelectionWithReceiver:self]; }

- (NSView *)makeIntegratedGrammarCard { return [FYGrammarPageBuilder makeIntegratedGrammarCardWithReceiver:self]; }

- (void)toggleGrammarFollowup:(id)sender { [FYGrammarResultsRenderer toggleGrammarFollowupWithReceiver:self]; }

- (void)askGrammarTone:(id)sender {
    [self requestGrammarQuestion:@"这句话是什么语气？请结合原句说明。"];
}

- (void)askGrammarQuestion:(id)sender {
    NSString *question = Trim(self.grammarQuestionField.stringValue);
    if (question.length) { [self requestGrammarQuestion:question]; }
}







- (void)updateGrammarActionControlsForQuick:(BOOL)quick { [FYGrammarDetailRenderer updateGrammarActionControlsForQuick:quick source:self]; }

- (void)refreshQuickGrammarActionDetail { [FYGrammarScrollRenderer refreshQuickGrammarActionDetailWithSource:self]; }



- (void)updateGrammarReviewDisplayForQuick:(BOOL)quick preservingPosition:(void (^)(void))updates { [FYGrammarScrollRenderer updateGrammarReviewDisplayForQuick:quick preservingPosition:updates source:self]; }



@end
