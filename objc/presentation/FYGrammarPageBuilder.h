#pragma once
#import <AppKit/AppKit.h>
#import "../learning/FYLearningModels.h"
@protocol FYGrammarPageViews <NSObject>
- (NSInteger)selectedGrammarIndex;
- (NSInteger)quickSelectedGrammarIndex;
- (NSInteger)selectedGrammarTab;
- (void)setSelectedGrammarTab:(NSInteger)value;
- (NSButton *)analyzeButton;
- (void)setAnalyzeButton:(NSButton *)value;
- (NSButton *)grammarBackToSourceButton;
- (void)setGrammarBackToSourceButton:(NSButton *)value;
- (NSTextField *)grammarDetailBodyLabel;
- (void)setGrammarDetailBodyLabel:(NSTextField *)value;
- (NSButton *)grammarDetailBookmarkButton;
- (void)setGrammarDetailBookmarkButton:(NSButton *)value;
- (NSStackView *)grammarDetailFields;
- (void)setGrammarDetailFields:(NSStackView *)value;
- (NSTextField *)grammarDetailLevelLabel;
- (void)setGrammarDetailLevelLabel:(NSTextField *)value;
- (NSTextField *)grammarDetailNameLabel;
- (void)setGrammarDetailNameLabel:(NSTextField *)value;
- (NSButton *)grammarEmptyAnalyzeButton;
- (void)setGrammarEmptyAnalyzeButton:(NSButton *)value;
- (NSTextField *)grammarEmptyHint;
- (void)setGrammarEmptyHint:(NSTextField *)value;
- (NSView *)grammarEmptyPane;
- (void)setGrammarEmptyPane:(NSView *)value;
- (NSTextField *)grammarEmptyTitle;
- (void)setGrammarEmptyTitle:(NSTextField *)value;
- (NSTextField *)grammarExampleLabel;
- (void)setGrammarExampleLabel:(NSTextField *)value;
- (NSView *)grammarExamplesPane;
- (void)setGrammarExamplesPane:(NSView *)value;
- (NSButton *)grammarExpandButton;
- (void)setGrammarExpandButton:(NSButton *)value;
- (NSTextField *)grammarExpandedLabel;
- (void)setGrammarExpandedLabel:(NSTextField *)value;
- (NSArray<NSControl *> *)grammarFollowupControls;
- (void)setGrammarFollowupControls:(NSArray<NSControl *> *)value;
- (NSView *)grammarFollowupDisclosure;
- (void)setGrammarFollowupDisclosure:(NSView *)value;
- (NSTextField *)grammarFollowupResultLabel;
- (void)setGrammarFollowupResultLabel:(NSTextField *)value;
- (NSTextField *)grammarOtherEmptyLabel;
- (void)setGrammarOtherEmptyLabel:(NSTextField *)value;
- (NSStackView *)grammarOtherStack;
- (void)setGrammarOtherStack:(NSStackView *)value;
- (NSButton *)grammarPageAnalyzeButton;
- (void)setGrammarPageAnalyzeButton:(NSButton *)value;
- (NSTextField *)grammarPinnedLabel;
- (void)setGrammarPinnedLabel:(NSTextField *)value;
- (NSView *)grammarPointsPane;
- (void)setGrammarPointsPane:(NSView *)value;
- (NSTextField *)grammarQuestionField;
- (void)setGrammarQuestionField:(NSTextField *)value;
- (NSTextField *)grammarReferenceNote;
- (void)setGrammarReferenceNote:(NSTextField *)value;
- (NSTextField *)grammarResultsLabel;
- (void)setGrammarResultsLabel:(NSTextField *)value;
- (NSButton *)grammarReviewButton;
- (void)setGrammarReviewButton:(NSButton *)value;
- (NSTextField *)grammarSourceLabel;
- (void)setGrammarSourceLabel:(NSTextField *)value;
- (NSButton *)grammarSourceLinkButton;
- (void)setGrammarSourceLinkButton:(NSButton *)value;
- (NSTextView *)grammarSourceTextView;
- (void)setGrammarSourceTextView:(NSTextView *)value;
- (NSTextField *)grammarStatusLabel;
- (void)setGrammarStatusLabel:(NSTextField *)value;
- (NSView *)grammarStructureCard;
- (void)setGrammarStructureCard:(NSView *)value;
- (NSArray<NSButton *> *)grammarTabButtons;
- (void)setGrammarTabButtons:(NSArray<NSButton *> *)value;
- (NSView *)grammarTabRow;
- (void)setGrammarTabRow:(NSView *)value;
- (NSArray<NSView *> *)grammarTabUnderlines;
- (void)setGrammarTabUnderlines:(NSArray<NSView *> *)value;
- (NSStackView *)grammarUsageBlock;
- (void)setGrammarUsageBlock:(NSStackView *)value;
- (NSArray<NSButton *> *)mainStructureButtons;
- (void)setMainStructureButtons:(NSArray<NSButton *> *)value;
- (NSScrollView *)mainStructureScrollView;
- (void)setMainStructureScrollView:(NSScrollView *)value;
- (NSArray<NSButton *> *)quickStructureButtons;
- (void)setQuickStructureButtons:(NSArray<NSButton *> *)value;
- (NSScrollView *)quickStructureScrollView;
- (void)setQuickStructureScrollView:(NSScrollView *)value;
- (NSTextField *)sentenceInsightLabel;
- (void)setSentenceInsightLabel:(NSTextField *)value;
- (NSStackView *)sentenceInsightStack;
- (void)setSentenceInsightStack:(NSStackView *)value;
- (NSStackView *)sentenceStructureStack;
- (void)setSentenceStructureStack:(NSStackView *)value;
@end
@protocol FYGrammarPageFactories <NSObject>
// Opaque original native action target; used only as the SDK button target.
- (id)grammarControlTarget;
- (NSColor *)uiInk;
- (NSColor *)uiMuted;
- (NSColor *)uiBorder;
- (NSColor *)uiSelected;
- (NSColor *)uiSurface;
- (NSColor *)uiAccent;
- (NSStackView *)verticalStack;
- (NSStackView *)horizontalStack;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSTextField *)mutedLabel:(NSString *)text;
- (NSTextField *)cardTitle:(NSString *)text;
- (NSTextField *)textField:(NSString *)placeholder;
- (NSView *)spacer;
- (NSView *)card;
- (NSView *)cardWithStack:(NSStackView *)stack;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
- (NSTextField *)quickReadingLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color;
- (void)applyGrammarTabSelection;
@end
@protocol FYGrammarPageSource <FYGrammarPageViews,FYGrammarPageFactories>
@end
// Complete original native graph construction. No views, target or state are stored here.
@interface FYGrammarPageBuilder : NSObject
+ (NSView *)structureViewForAnalysis:(FYAnalysisResult *)analysis source:(NSString *)source quick:(BOOL)quick receiver:(id<FYGrammarPageSource>)receiver;
+ (NSView *)grammarInfoCellWithLabel:(NSString *)labelText value:(NSString *)valueText receiver:(id<FYGrammarPageSource>)receiver;
+ (NSView *)makeIntegratedGrammarCardWithReceiver:(id<FYGrammarPageSource>)receiver;
@end
