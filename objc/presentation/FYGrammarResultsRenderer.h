#pragma once
#import <AppKit/AppKit.h>
#import "../learning/FYLearningModels.h"
#import "../FYGrammarActionState.h"
@class FYLearningCoordinator;
// Explicit access to original owners. No state is stored by the renderer.
@protocol FYGrammarResultsModelSource <NSObject>
- (FYAnalysisResult *)currentAnalysis;
- (void)setCurrentAnalysis:(FYAnalysisResult *)value;
- (FYGrammarActionState *)grammarActions;
- (NSString *)grammarAnalysisError;
- (void)setGrammarAnalysisError:(NSString *)value;
- (NSInteger)analysisRequestGeneration;
- (void)setAnalysisRequestGeneration:(NSInteger)value;
- (NSInteger)followupRequestGeneration;
- (void)setFollowupRequestGeneration:(NSInteger)value;
- (BOOL)learningAnalysisBusy;
- (void)setLearningAnalysisBusy:(BOOL)value;
- (NSInteger)selectedGrammarIndex;
- (void)setSelectedGrammarIndex:(NSInteger)value;
- (NSInteger)selectedGrammarTab;
- (FYLearningCoordinator *)learningCoordinator;
@end
@protocol FYGrammarResultsViews <NSObject>
- (NSButton *)analyzeButton;
- (NSTextField *)grammarDetailBodyLabel;
- (NSButton *)grammarDetailBookmarkButton;
- (NSStackView *)grammarDetailFields;
- (NSTextField *)grammarDetailLevelLabel;
- (NSTextField *)grammarDetailNameLabel;
- (NSButton *)grammarEmptyAnalyzeButton;
- (NSTextField *)grammarEmptyHint;
- (NSView *)grammarEmptyPane;
- (NSTextField *)grammarEmptyTitle;
- (NSView *)grammarExamplesPane;
- (NSButton *)grammarExpandButton;
- (NSTextField *)grammarExpandedLabel;
- (NSArray<NSControl *> *)grammarFollowupControls;
- (NSView *)grammarFollowupDisclosure;
- (NSTextField *)grammarFollowupResultLabel;
- (NSButton *)grammarFollowupToggle;
- (NSTextField *)grammarOtherEmptyLabel;
- (NSStackView *)grammarOtherStack;
- (NSButton *)grammarPageAnalyzeButton;
- (NSView *)grammarPointsPane;
- (NSTextField *)grammarReferenceNote;
- (NSTextField *)grammarResultsLabel;
- (NSButton *)grammarReviewButton;
- (NSButton *)grammarSourceLinkButton;
- (NSTextField *)grammarStatusLabel;
- (NSView *)grammarStructureCard;
- (NSArray<NSButton *> *)grammarTabButtons;
- (NSView *)grammarTabRow;
- (NSArray<NSView *> *)grammarTabUnderlines;
- (NSTextField *)liveLevelTag;
- (NSTextField *)sentenceInsightLabel;
- (NSStackView *)sentenceInsightStack;
- (NSStackView *)sentenceStructureStack;
@end
@protocol FYGrammarResultsNativeActions <NSObject>
- (NSColor *)uiMuted;
- (NSColor *)uiSelected;
- (NSColor *)uiSurface;
- (NSColor *)uiInk;
- (void)setAnalyzeBusy:(BOOL)busy;
- (void)applyGrammarTabSelection;
- (void)updateGrammarActionControlsForQuick:(BOOL)quick;
- (NSString *)currentSentenceLevelTag;
- (CGFloat)structureScrollOffsetForQuick:(BOOL)quick;
- (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick;
- (void)clearArrangedSubviews:(NSStackView *)stack;
- (NSView *)structureViewForAnalysis:(FYAnalysisResult *)analysis source:(NSString *)source quick:(BOOL)quick;
- (NSTextField *)mutedLabel:(NSString *)text;
- (BOOL)analysisMatchesCurrentSentence;
- (void)clearGrammarHighlight;
- (void)highlightGrammarMatches;
- (void)renderGrammarDetailAtIndex:(NSInteger)index;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
@end
@protocol FYGrammarResultsSource <FYGrammarResultsModelSource,FYGrammarResultsViews,FYGrammarResultsNativeActions>
@end
@interface FYGrammarResultsRenderer : NSObject
+ (void)setAnalyzeBusy:(BOOL)busy receiver:(id<FYGrammarResultsSource>)receiver;
+ (void)refreshGrammarResultsWithReceiver:(id<FYGrammarResultsSource>)receiver;
+ (void)clearAnalysisDisplayWithReceiver:(id<FYGrammarResultsSource>)receiver;
+ (void)applyGrammarTabSelectionWithReceiver:(id<FYGrammarResultsSource>)receiver;
+ (void)toggleGrammarFollowupWithReceiver:(id<FYGrammarResultsSource>)receiver;
@end
