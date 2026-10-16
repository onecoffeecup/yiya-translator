#pragma once
#import <AppKit/AppKit.h>
#import "../learning/FYStudyChatView.h"
#import "FYDisplayedSentenceState.h"
#import "FYWordSelectionController.h"
#import "FYLiveReadingCoordinator.h"
#import "FYLiveReadingRenderer.h"
#import "FYInlineTranslationListCoordinator.h"
#import "FYInlineTranslationListRenderer.h"
#import "FYLivePageBuilder.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

// Explicit context, peer actions and view factories; no application type dependency.
@protocol FYMainWindowControllerHost <NSObject, NSWindowDelegate, NSTextFieldDelegate>
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
@property(nonatomic, copy) NSString *referenceActiveWord;
@property(nonatomic) NSInteger referenceRequestGeneration;
@property(nonatomic) BOOL sourceHoverSuspended;
@property(nonatomic, strong) NSTextField *vocabularyStatusLabel;
- (NSView *)makeRunSettingsPage;
- (NSView *)makeVocabularyPage;
- (void)clearAnalysisDisplay;
- (void)refreshLearningSource;
- (void)refreshLearningStatus;
- (void)refreshHistory;
- (void)refreshVocabularyList;
- (void)clearArrangedSubviews:(NSStackView *)stack;
- (NSView *)translationCard;
- (NSStackView *)verticalStack;
- (NSStackView *)horizontalStack;
- (NSView *)rowWithLabel:(NSString *)label view:(NSView *)view;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSTextField *)textField:(NSString *)placeholder;
- (NSView *)spacer;
- (NSView *)separator;
- (NSColor *)uiInk;
- (NSColor *)uiMuted;
- (NSColor *)uiAccent;
- (NSView *)cardWithStack:(NSStackView *)stack;
- (void)pinFullWidth:(NSView *)view toStack:(NSStackView *)stack;
- (NSTextField *)cardTitle:(NSString *)text;
- (NSTextField *)mutedLabel:(NSString *)text;
- (FYInlineBlockSnapshot *)inlineSnapshotForBlock:(FYInlineTextBlock *)block
                                      translation:(NSString *)translation
                                    stableBlockID:(NSString *)stableBlockID;
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot;
- (NSView *)makeAppearancePage;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
- (NSTextField *)chipLabel:(NSString *)text;
- (void)refreshLiveChips;
- (void)applyGrammarTabSelection;
- (NSView *)makeHistoryPage;
- (NSView *)makeIntegratedGrammarCard;
- (void)refreshSourceHoverTips;
- (FYStudyChatView *)makeStudyChatViewForOverlay:(BOOL)overlay;
@end

// Owns window views and ephemeral state. Persistence remains in learning services.
@interface FYMainWindowController : NSObject <FYWordSelectionSource,FYLiveReadingSource,FYLiveReadingRenderSource,FYInlineTranslationListSource,FYInlineTranslationListRenderSource,FYLivePageSource>
@property(nonatomic,strong,readonly) FYLivePageBuilder *livePageBuilder;
@property(nonatomic,strong,readonly) FYInlineTranslationListCoordinator *inlineTranslationListCoordinator;
@property(nonatomic,strong,readonly) FYInlineTranslationListRenderer *inlineTranslationListRenderer;
@property(nonatomic,strong,readonly) FYLiveReadingCoordinator *liveReadingCoordinator;
@property(nonatomic,strong,readonly) FYLiveReadingRenderer *liveReadingRenderer;
@property(nonatomic,strong,readonly) FYDisplayedSentenceState *displayedSentenceState;
@property(nonatomic,strong,readonly) FYWordSelectionController *wordSelectionController;
@property(nonatomic, weak) id<FYMainWindowControllerHost> host;
- (instancetype)initWithHost:(id<FYMainWindowControllerHost>)host;
@property(nonatomic, strong) NSTextField *currentWindowLabel;
@property(nonatomic, copy) NSString *displayedSentenceID;
@property(nonatomic, copy) NSString *displayedSourceText;
@property(nonatomic, copy, nullable) NSString *displayedTranslation;
@property(nonatomic) NSInteger displayedVersion;
@property(nonatomic, strong) NSButton *followLatestButton;
@property(nonatomic, strong) NSImageView *framePreview;
@property(nonatomic, strong) NSTextField *headerDescriptionLabel;
@property(nonatomic, strong) NSTextField *headerTitleLabel;
@property(nonatomic, strong) NSView *inlineTranslationListCard;
@property(nonatomic, strong) NSTextField *inlineTranslationListCount;
@property(nonatomic, copy) NSString *inlineTranslationListSignature;
@property(nonatomic, copy) NSArray<FYInlineBlockSnapshot *> *inlineTranslationListSnapshots;
@property(nonatomic, strong) NSStackView *inlineTranslationListStack;
@property(nonatomic, strong) NSTextField *latestSourceLabel;
@property(nonatomic, strong) NSTextField *latestTranslationLabel;
@property(nonatomic, strong) NSView *learningPageHost;
@property(nonatomic, strong) NSTextField *learningPinnedLabel;
@property(nonatomic, strong) FYSelectableSourceTextView *learningSourceTextView;
@property(nonatomic, strong) NSTextField *learningTranslationLabel;
@property(nonatomic, strong) NSTextField *lemmaField;
@property(nonatomic, strong) NSTextField *liveChipAutoTranslate;
@property(nonatomic, strong) NSTextField *liveChipPauseFollow;
@property(nonatomic, strong) NSTextField *liveChipRecognition;
@property(nonatomic, strong) NSTextField *liveErrorLabel;
@property(nonatomic, strong) NSTextField *liveLevelTag;
@property(nonatomic, strong) NSTextField *liveScreenDialogueLabel;
@property(nonatomic, strong) NSTextField *liveScreenSpeakerLabel;
@property(nonatomic, strong) NSTextField *liveSourceEmptyLabel;
@property(nonatomic, strong) NSTextField *liveSourceSelectionHintLabel;
@property(nonatomic, strong) NSButton *mainChatToggle;
@property(nonatomic) BOOL mainChatWantsVisible;
@property(nonatomic, strong) NSLayoutConstraint *mainChatWidth;
@property(nonatomic, strong) NSWindow *mainWindow;
@property(nonatomic, strong) NSLayoutConstraint *mainWindowContentWidth;
@property(nonatomic, strong) NSLayoutConstraint *mainWindowMinimumWidth;
@property(nonatomic) BOOL mainWindowVisibleBeforeRegionSelection;
@property(nonatomic, strong) NSStackView *mainWorkspaceRoot;
@property(nonatomic, strong) NSTextField *meaningField;
@property(nonatomic, strong) NSTextField *ocrDurationLabel;
@property(nonatomic, strong) NSArray<NSButton *> *pageButtons;
@property(nonatomic, strong) NSArray<NSView *> *pages;
@property(nonatomic, strong) NSButton *pinSentenceButton;
@property(nonatomic, strong) NSLayoutConstraint *previewAspectConstraint;
@property(nonatomic, strong) NSTextField *previewPlaceholder;
@property(nonatomic, strong) NSTextField *readingField;
@property(nonatomic, strong) NSButton *runButton;
@property(nonatomic, strong) NSTextField *runStateLabel;
@property(nonatomic) BOOL savingVocabulary;
@property(nonatomic) NSInteger selectedPage;
@property(nonatomic, strong) NSLayoutConstraint *sourceReadingHeight;
@property(nonatomic, strong) NSLayoutConstraint *sourceReadingMinimumHeight;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSTextField *translationCountLabel;
@property(nonatomic, strong) NSTextField *translationDurationLabel;
@property(nonatomic, strong) NSLayoutConstraint *translationReadingMinimumHeight;
@property(nonatomic) BOOL vocabCompletionFromAI;
@property(nonatomic) NSInteger vocabSelectionGeneration;
@property(nonatomic, strong) NSTextField *vocabularySelectionLabel;
@property(nonatomic, strong) NSStackView *wordPickArea;
@property(nonatomic, strong) NSTextField *wordPickSurfaceLabel;
@property(nonatomic, strong) NSLayoutConstraint *workspaceWidth;
- (void)createMainWindow;
- (NSView *)makeSidebar;
- (NSView *)makeRunHeader;
- (NSScrollView *)makePageScrollWithContent:(NSView *)content;
- (void)selectPage:(NSButton *)sender;
- (void)selectPageAtIndex:(NSInteger)index;
- (NSView *)makeLivePage;
- (NSView *)makeInlineTranslationListCard;
- (void)refreshInlineTranslationList;
- (void)openInlineTranslationRow:(NSButton *)sender;
- (void)toggleLearningPin:(id)sender;
- (void)vocabularyFormChanged:(id)sender;
- (void)freezeLearningSentenceForSelection;
- (void)selectWordAtCharacterIndex:(NSUInteger)characterIndex;
- (void)updateWordPickForSelection;
- (void)closeWordPick:(id)sender;
- (void)pinLearningSentence:(id)sender;
- (void)followLatestSentence:(id)sender;
- (NSString *)selectedLearningText;
- (void)bookmarkSelectedVocabulary:(id)sender;
- (void)completeSelectedVocabulary:(id)sender;
- (NSAttributedString *)liveReadingText:(NSString *)text japanese:(BOOL)japanese;
- (void)updateLiveSourceReadingHeight;
- (void)refreshLearningSource;
- (void)syncCoordinatorToDisplayed;
- (void)splitSpeakerAndBody:(NSString *)text speaker:(NSString * _Nullable * _Nullable)outSpeaker body:(NSString * _Nullable * _Nullable)outBody;
- (nullable NSString *)currentSentenceLevelTag;
- (void)refreshLiveDialoguePresentation:(NSString *)source;
- (void)refreshLearningStatus;
- (void)toggleMainStudyChat:(id)sender;
- (void)updateMainChatForWindowWidth;
- (void)updateMainChatToggle;
- (void)windowDidResize:(NSNotification *)notification;
@end
#pragma clang diagnostic pop
