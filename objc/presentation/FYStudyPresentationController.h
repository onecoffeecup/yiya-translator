#pragma once
#import <AppKit/AppKit.h>
@class FYCaptureCardInput,FYSelectableSourceTextView,FYStudyChatView,FYStudyOverlayPanel;
#import "FYStudyChatContextCoordinator.h"
#import "FYQuickSentenceCoordinator.h"
#import "FYStudyNavigationCoordinator.h"
#import "FYStudyChatRenderer.h"
#import "FYQuickSentenceRenderer.h"
#import "FYStudyScrollRenderer.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

// Explicit context, peer actions and view factories; no application type dependency.
@protocol FYStudyPresentationControllerHost <NSObject, NSWindowDelegate, NSTextFieldDelegate>
@property(nonatomic) NSInteger analysisRequestGeneration;
@property(nonatomic, strong) NSSecureTextField *apiKeyField;
@property(nonatomic, strong) NSTextField *baseURLField;
@property(nonatomic, strong) NSPanel *captionPanel;
@property(nonatomic, strong) FYCaptureCardInput *captureCardInput;
@property(nonatomic, strong) FYAnalysisResult *currentAnalysis;
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
@property(nonatomic) NSInteger selectedGrammarIndex;
@property(nonatomic) BOOL selectingCaptureRegion;
- (void)selectPageAtIndex:(NSInteger)index;
- (void)setAnalyzeBusy:(BOOL)busy;
- (void)analyzeCurrentSentence:(id)sender;
- (void)refreshGrammarResults;
- (BOOL)analysisMatchesCurrentSentence;
- (void)clearAnalysisDisplay;
- (CGFloat)structureScrollOffsetForQuick:(BOOL)quick;
- (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick;
- (void)refreshLearningSource;
- (void)refreshLearningStatus;
- (void)refreshGrammarBookmarks:(id)sender;
- (NSStackView *)verticalStack;
- (NSStackView *)horizontalStack;
- (NSView *)spacer;
- (NSView *)separator;
- (NSColor *)uiInk;
- (NSColor *)uiMuted;
- (NSColor *)uiBorder;
- (NSColor *)uiAccent;
- (NSColor *)uiSelected;
- (NSColor *)uiSurface;
- (NSView *)card;
- (NSTextField *)mutedLabel:(NSString *)text;
- (BOOL)translationTargetIsForeground;
- (void)refreshOverlayVisibility:(id)sender;
- (BOOL)captureCardInputEnabled;
- (uint32_t)selectedWindowID;
- (NSInteger)effectiveModeSegment;
- (void)showError:(NSString *)error;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
- (void)refreshQuickSentenceHoverTips;
- (void)captureLatestStudySentenceWithCompletion:(void (^)(NSString *,NSError *))completion;
- (NSView *)structureViewForAnalysis:(FYAnalysisResult *)analysis source:(NSString *)source quick:(BOOL)quick;
- (void)refreshSavedSentences;
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick;
- (void)updateGrammarActionControlsForQuick:(BOOL)quick;
@end

// Owns study views and ephemeral state. Persistence remains in learning services.
@interface FYStudyPresentationController : NSObject <FYStudyChatContextSource,FYQuickSentenceAnalysisSource,FYQuickSentenceBookmarkSource,FYStudyQuickNavigationSource,FYStudyInlineNavigationSource,FYStudyInlineTextSource,FYStudyChatBindingSource,FYStudyWorkspaceNavigationSource,FYStudyChatRenderSource,FYQuickSentenceRenderSource,FYStudyScrollRenderSource>
@property(nonatomic,strong,readonly) FYStudyNavigationCoordinator *studyNavigationCoordinator;
@property(nonatomic,strong,readonly) FYQuickSentenceCoordinator *quickSentenceCoordinator;
@property(nonatomic,strong,readonly) FYStudyChatContextCoordinator *studyChatContextCoordinator;
@property(nonatomic, weak) id<FYStudyPresentationControllerHost> host;
- (instancetype)initWithHost:(id<FYStudyPresentationControllerHost>)host;
@property(nonatomic) NSInteger chatContextGeneration;
@property(nonatomic) BOOL chatResolvingSource;
@property(nonatomic, strong) FYInlineBlockSnapshot *inlineBlockSnapshot;
@property(nonatomic, strong) NSButton *inlineReturnButton;
@property(nonatomic, strong) FYInlineBlockSnapshot *inlineReturnSnapshot;
@property(nonatomic, copy) NSString *inlineReturnSourceText;
@property(nonatomic, strong) FYStudyChatView *mainStudyChatView;
@property(nonatomic, strong) FYStudyChatView *overlayStudyChatView;
@property(nonatomic) NSInteger quickAnalysisGeneration;
@property(nonatomic, strong) NSButton *quickGrammarBookmarkButton;
@property(nonatomic) BOOL quickGrammarBookmarkPending;
@property(nonatomic, strong) NSTextField *quickGrammarBookmarkStatus;
@property(nonatomic, copy) NSArray<NSButton *> *quickGrammarChoices;
@property(nonatomic, strong) NSView *quickGrammarDetailCard;
@property(nonatomic, strong) NSButton *quickGrammarExpandButton;
@property(nonatomic, strong) NSButton *quickGrammarReviewButton;
@property(nonatomic, strong) NSTextField *quickGrammarReviewStatus;
@property(nonatomic, strong) NSStackView *quickGrammarStack;
@property(nonatomic, strong) NSButton *quickSelectedGrammarButton;
@property(nonatomic) NSInteger quickSelectedGrammarIndex;
@property(nonatomic, strong) FYAnalysisResult *quickSentenceAnalysis;
@property(nonatomic, copy) NSString *quickSentenceAnalysisError;
@property(nonatomic, copy) NSString *quickSentenceAnalysisSource;
@property(nonatomic, copy) NSString *quickSentenceAnalysisTranslation;
@property(nonatomic, strong) FYLearningAnalyzer *quickSentenceAnalyzer;
@property(nonatomic) BOOL quickSentenceAnalyzing;
@property(nonatomic, strong) NSButton *quickSentenceBookmarkButton;
@property(nonatomic) NSInteger quickSentenceGeneration;
@property(nonatomic, copy) NSString *quickSentenceID;
@property(nonatomic) BOOL quickSentenceIsInlineBlock;
@property(nonatomic, strong) FYStudyOverlayPanel *quickSentencePanel;
@property(nonatomic) BOOL quickSentenceRequested;
@property(nonatomic) CGFloat quickSentenceScrollOffset;
@property(nonatomic, copy) NSString *quickSentenceSource;
@property(nonatomic, copy) NSString *quickSentenceTranslation;
@property(nonatomic) NSInteger quickSentenceVersion;
@property(nonatomic, strong) FYSelectableSourceTextView *quickSourceTextView;
@property(nonatomic, copy) NSArray<NSButton *> *quickStructureButtons;
@property(nonatomic, strong) NSScrollView *quickStructureScrollView;
@property(nonatomic) BOOL sentenceBookmarkPending;
@property(nonatomic) BOOL studyChatOverlayRequested;
@property(nonatomic, strong) FYStudyOverlayPanel *studyChatPanel;
@property(nonatomic, strong) FYStudyChatSession *studyChatSession;
- (void)ensureStudyChatSession;
- (FYStudyChatView *)makeStudyChatViewForOverlay:(BOOL)overlay;
- (void)referenceLatestStudySentence:(id)sender;
- (void)resolveLatestStudyIdentity:(void (^)(FYRequestIdentity *))completion;
- (void)resolveLatestStudySentence:(void (^)(NSString *,NSString *))completion;
- (void)askQuickSentence:(id)sender;
- (void)refreshStudyChatViews;
- (void)sendStudyChat:(NSString *)text;
- (void)configureStudyOverlay:(NSPanel *)panel;
- (void)showStudyChatOverlay:(id)sender;
- (void)closeStudyOverlay:(id)sender;
- (void)cancelQuickSentenceAnalysis;
- (void)analyzeQuickSentence:(id)sender;
- (void)showQuickSentence:(id)sender;
- (void)selectQuickStructure:(NSButton *)sender;
- (BOOL)quickSentenceIsBookmarked;
- (void)bookmarkQuickSentence:(id)sender;
- (FYGrammarBookmark *)quickGrammarBookmark;
- (void)updateQuickGrammarBookmark;
- (void)bookmarkQuickGrammar:(id)sender;
- (NSView *)quickGrammarDetailForItem:(FYGrammarItem *)item;
- (void)selectQuickGrammar:(NSButton *)sender;
- (NSTextField *)quickReadingLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color;
- (NSView *)quickReadingCard:(NSStackView *)stack tinted:(BOOL)tinted;
- (void)renderQuickSentence;
- (void)openStudyWorkspace:(id)sender;
- (void)openInlineLearningForBlockText:(NSString *)source translation:(NSString *)translation;
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot;
- (void)bindInlineStudyChatToSource:(NSString *)source translation:(NSString *)translation;
- (void)returnFromStudyChatToInlineLearning:(id)sender;
- (NSScrollView *)quickSentenceScrollView;
- (void)captureQuickSentenceScrollPosition;
- (void)restoreQuickSentenceScrollPosition;
- (void)updateInlineReturnButtonVisibility;
@end
#pragma clang diagnostic pop
