#pragma once
#import <AppKit/AppKit.h>
#import "../learning/FYLearningModels.h"
#import "../FYGrammarActionState.h"
@class FYSelectableSourceTextView;
@protocol FYGrammarDetailModelSource <NSObject>
- (FYAnalysisResult *)currentAnalysis;
- (FYAnalysisResult *)quickSentenceAnalysis;
- (NSString *)quickSentenceSource;
- (NSString *)quickSentenceAnalysisSource;
- (NSInteger)selectedGrammarIndex;
- (BOOL)quickSentenceAnalyzing;
- (BOOL)learningAnalysisBusy;
- (BOOL)analysisMatchesCurrentSentence;
- (FYGrammarItem *)selectedGrammarItem;
- (FYGrammarBookmark *)bookmarkForCurrentGrammar;
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick;
- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick;
@end
@protocol FYGrammarDetailViews <NSObject>
- (NSButton *)grammarPageAnalyzeButton;
- (NSTextField *)grammarDetailNameLabel;
- (NSTextField *)grammarDetailLevelLabel;
- (NSTextField *)grammarResultsLabel;
- (NSTextField *)grammarDetailBodyLabel;
- (NSStackView *)grammarDetailFields;
- (NSStackView *)grammarUsageBlock;
- (NSTextField *)grammarExampleLabel;
- (NSButton *)grammarSourceLinkButton;
- (NSButton *)grammarDetailBookmarkButton;
- (FYSelectableSourceTextView *)learningSourceTextView;
- (NSTextView *)grammarSourceTextView;
- (NSArray<NSButton *> *)mainStructureButtons;
- (NSStackView *)grammarOtherStack;
- (NSButton *)quickGrammarExpandButton;
- (NSButton *)grammarExpandButton;
- (NSTextField *)grammarExpandedLabel;
- (NSButton *)quickGrammarReviewButton;
- (NSButton *)grammarReviewButton;
- (NSTextField *)quickGrammarReviewStatus;
@end
@protocol FYGrammarDetailNativeActions <NSObject>
- (NSColor *)uiInk;
- (NSColor *)uiAccent;
- (NSColor *)uiSelected;
- (NSColor *)uiSurface;
- (NSStackView *)verticalStack;
- (NSTextField *)mutedLabel:(NSString *)text;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (void)clearArrangedSubviews:(NSStackView *)stack;
- (void)refreshSourceHoverTips;
- (void)renderGrammarDetailAtIndex:(NSInteger)index;
- (void)highlightGrammarMatches;
- (void)applyHighlight:(NSColor *)color toTextView:(NSTextView *)textView;
- (void)updateGrammarActionControlsForQuick:(BOOL)quick;
@end
@protocol FYGrammarDetailSource <FYGrammarDetailModelSource,FYGrammarDetailViews,FYGrammarDetailNativeActions>
@end
// Native selected-item presentation only. Original controller/services own all state and views.
@interface FYGrammarDetailRenderer : NSObject
+ (void)renderGrammarDetailAtIndex:(NSInteger)index source:(id<FYGrammarDetailSource>)source;
+ (void)highlightGrammarMatchesWithSource:(id<FYGrammarDetailSource>)source;
+ (void)applyHighlight:(NSColor *)color toTextView:(NSTextView *)textView source:(id<FYGrammarDetailSource>)source;
+ (void)clearGrammarHighlightWithSource:(id<FYGrammarDetailSource>)source;
+ (void)applyGrammarSelectionLocallyWithSource:(id<FYGrammarDetailSource>)source;
+ (void)updateGrammarActionControlsForQuick:(BOOL)quick source:(id<FYGrammarDetailSource>)source;
@end
