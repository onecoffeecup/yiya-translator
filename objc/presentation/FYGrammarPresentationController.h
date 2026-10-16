#pragma once
#import <AppKit/AppKit.h>
@class FYSelectableSourceTextView, FYStudyOverlayPanel;
#import "FYGrammarInteractionCoordinator.h"
#import "FYGrammarScrollRenderer.h"
#import "FYGrammarDetailRenderer.h"
#import "FYGrammarResultsRenderer.h"
#import "FYGrammarPageBuilder.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

// Explicit context, peer actions and view factories; no application type dependency.
@protocol FYGrammarPresentationControllerHost <NSObject, NSWindowDelegate, NSTextFieldDelegate>
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
- (void)syncLearningAnalyzerConfig;
- (void)selectPageAtIndex:(NSInteger)index;
- (void)syncCoordinatorToDisplayed;
- (nullable NSString *)currentSentenceLevelTag;
- (void)refreshLearningStatus;
- (void)clearArrangedSubviews:(NSStackView *)stack;
- (void)refreshGrammarBookmarks:(id)sender;
- (NSStackView *)verticalStack;
- (NSStackView *)horizontalStack;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSTextField *)textField:(NSString *)placeholder;
- (NSView *)spacer;
- (NSColor *)uiInk;
- (NSColor *)uiMuted;
- (NSColor *)uiBorder;
- (NSColor *)uiAccent;
- (NSColor *)uiSelected;
- (NSColor *)uiSurface;
- (NSView *)card;
- (NSView *)cardWithStack:(NSStackView *)stack;
- (NSTextField *)cardTitle:(NSString *)text;
- (NSTextField *)mutedLabel:(NSString *)text;
- (NSScrollView *)quickSentenceScrollView;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
- (void)refreshSourceHoverTips;
- (NSView *)quickGrammarDetailForItem:(FYGrammarItem *)item;
- (NSTextField *)quickReadingLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color;
- (void)renderQuickSentence;
@end

// Owns grammar views and ephemeral state. Persistence remains in learning services.
@interface FYGrammarPresentationController : NSObject <FYGrammarInteractionSource, FYGrammarScrollSource, FYGrammarDetailSource, FYGrammarResultsSource, FYGrammarPageSource, FYGrammarBookmarkSource>
@property(nonatomic,strong,readonly) FYGrammarInteractionCoordinator *grammarInteractionCoordinator;
@property(nonatomic, weak) id<FYGrammarPresentationControllerHost> host;
- (instancetype)initWithHost:(id<FYGrammarPresentationControllerHost>)host;
@property(nonatomic) NSInteger analysisRequestGeneration;
@property(nonatomic, strong) NSButton *analyzeButton;
@property(nonatomic, strong) FYAnalysisResult *currentAnalysis;
@property(nonatomic) NSInteger followupRequestGeneration;
@property(nonatomic, strong) FYGrammarActionState *grammarActions;
@property(nonatomic, copy) NSString *grammarAnalysisError;
@property(nonatomic, strong) NSButton *grammarBackToSourceButton;
@property(nonatomic, strong) NSTextField *grammarDetailBodyLabel;
@property(nonatomic, strong) NSButton *grammarDetailBookmarkButton;
@property(nonatomic, strong) NSStackView *grammarDetailFields;
@property(nonatomic, strong) NSTextField *grammarDetailLevelLabel;
@property(nonatomic, strong) NSTextField *grammarDetailNameLabel;
@property(nonatomic, strong) NSButton *grammarEmptyAnalyzeButton;
@property(nonatomic, strong) NSTextField *grammarEmptyHint;
@property(nonatomic, strong) NSView *grammarEmptyPane;
@property(nonatomic, strong) NSTextField *grammarEmptyTitle;
@property(nonatomic, strong) NSTextField *grammarExampleLabel;
@property(nonatomic, strong) NSView *grammarExamplesPane;
@property(nonatomic, strong) NSButton *grammarExpandButton;
@property(nonatomic, strong) NSTextField *grammarExpandedLabel;
@property(nonatomic, strong) NSArray<NSControl *> *grammarFollowupControls;
@property(nonatomic, strong) NSView *grammarFollowupDisclosure;
@property(nonatomic, strong) NSTextField *grammarFollowupResultLabel;
@property(nonatomic, strong) NSStackView *grammarFollowupStack;
@property(nonatomic, strong) NSButton *grammarFollowupToggle;
@property(nonatomic, strong) NSTextField *grammarOtherEmptyLabel;
@property(nonatomic, strong) NSStackView *grammarOtherStack;
@property(nonatomic, strong) NSButton *grammarPageAnalyzeButton;
@property(nonatomic, strong) NSTextField *grammarPinnedLabel;
@property(nonatomic, strong) NSView *grammarPointsPane;
@property(nonatomic, strong) NSTextField *grammarQuestionField;
@property(nonatomic, strong) NSTextField *grammarReferenceNote;
@property(nonatomic, strong) NSTextField *grammarResultsLabel;
@property(nonatomic, strong) NSButton *grammarReviewButton;
@property(nonatomic, strong) NSPopUpButton *grammarSelector;
@property(nonatomic, strong) NSTextField *grammarSourceLabel;
@property(nonatomic, strong) NSButton *grammarSourceLinkButton;
@property(nonatomic, strong) NSTextView *grammarSourceTextView;
@property(nonatomic, strong) NSTextField *grammarStatusLabel;
@property(nonatomic, strong) NSView *grammarStructureCard;
@property(nonatomic, copy) NSArray<NSButton *> *grammarTabButtons;
@property(nonatomic, strong) NSView *grammarTabRow;
@property(nonatomic, copy) NSArray<NSView *> *grammarTabUnderlines;
@property(nonatomic, strong) NSStackView *grammarUsageBlock;
@property(nonatomic) BOOL learningAnalysisBusy;
@property(nonatomic, copy) NSArray<NSButton *> *mainStructureButtons;
@property(nonatomic, strong) NSScrollView *mainStructureScrollView;
@property(nonatomic, strong) FYGrammarActionState *quickGrammarActions;
@property(nonatomic) NSInteger selectedGrammarIndex;
@property(nonatomic) NSInteger selectedGrammarTab;
@property(nonatomic, strong) NSTextField *sentenceInsightLabel;
@property(nonatomic, strong) NSStackView *sentenceInsightStack;
@property(nonatomic, strong) NSStackView *sentenceStructureStack;
- (void)grammarSelectorChanged:(id)sender;
- (void)setAnalyzeBusy:(BOOL)busy;
- (void)analyzeCurrentSentence:(id)sender;
- (void)refreshGrammarResults;
- (void)renderGrammarDetailAtIndex:(NSInteger)index;
- (void)openGrammarSource:(id)sender;
- (FYGrammarBookmark *)bookmarkForCurrentGrammar;
- (BOOL)analysisMatchesCurrentSentence;
- (void)highlightGrammarMatches;
- (void)applyHighlight:(NSColor *)color toTextView:(NSTextView *)textView;
- (void)clearGrammarHighlight;
- (void)clearAnalysisDisplay;
- (void)bookmarkGrammarItem:(NSButton *)sender;
- (void)bookmarkSelectedGrammar:(id)sender;
- (void)selectGrammarItem:(NSButton *)sender;
- (void)applyGrammarSelectionLocally;
- (CGFloat)structureScrollOffsetForQuick:(BOOL)quick;
- (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick;
- (FYGrammarItem *)selectedGrammarItem;
- (void)backToSourcePage:(id)sender;
- (void)simplerExplanationForGrammar:(id)sender;
- (void)exampleSentenceForGrammar:(id)sender;
- (void)requestGrammarFollowupExample:(BOOL)example;
- (NSView *)structureViewForAnalysis:(FYAnalysisResult *)analysis source:(NSString *)source quick:(BOOL)quick;
- (void)selectMainStructure:(NSButton *)sender;
- (NSView *)grammarInfoCellWithLabel:(NSString *)labelText value:(NSString *)valueText;
- (void)selectGrammarTab:(NSButton *)sender;
- (void)applyGrammarTabSelection;
- (NSView *)makeIntegratedGrammarCard;
- (void)toggleGrammarFollowup:(id)sender;
- (void)askGrammarTone:(id)sender;
- (void)askGrammarQuestion:(id)sender;
- (void)requestGrammarQuestion:(NSString *)question;
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick;
- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick;
- (void)updateGrammarActionControlsForQuick:(BOOL)quick;
- (void)refreshQuickGrammarActionDetail;
- (void)toggleGrammarExplanation:(NSButton *)sender;
- (void)updateGrammarReviewDisplayForQuick:(BOOL)quick preservingPosition:(void (^)(void))updates;
- (void)reviewGrammarSentence:(NSButton *)sender;
@end
#pragma clang diagnostic pop
