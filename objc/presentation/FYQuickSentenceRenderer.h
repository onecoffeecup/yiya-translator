#pragma once
#import <AppKit/AppKit.h>
#import "../FYGrammarActionState.h"
#import "FYInlineBlockSnapshot.h"
@class FYStudyChatView,FYStudyOverlayPanel,FYSelectableSourceTextView,FYStudyChatSession;
@protocol FYQuickSentenceRenderSource <NSObject>
- (NSPanel *)captionPanel;
- (FYGrammarActionState *)quickGrammarActions;
- (NSButton *)quickGrammarBookmarkButton;
- (void)setQuickGrammarBookmarkButton:(NSButton *)value;
- (BOOL)quickGrammarBookmarkPending;
- (NSTextField *)quickGrammarBookmarkStatus;
- (void)setQuickGrammarBookmarkStatus:(NSTextField *)value;
- (NSArray<NSButton *> *)quickGrammarChoices;
- (void)setQuickGrammarChoices:(NSArray<NSButton *> *)value;
- (NSView *)quickGrammarDetailCard;
- (void)setQuickGrammarDetailCard:(NSView *)value;
- (NSButton *)quickGrammarExpandButton;
- (void)setQuickGrammarExpandButton:(NSButton *)value;
- (NSButton *)quickGrammarReviewButton;
- (void)setQuickGrammarReviewButton:(NSButton *)value;
- (NSTextField *)quickGrammarReviewStatus;
- (void)setQuickGrammarReviewStatus:(NSTextField *)value;
- (NSStackView *)quickGrammarStack;
- (void)setQuickGrammarStack:(NSStackView *)value;
- (NSButton *)quickSelectedGrammarButton;
- (void)setQuickSelectedGrammarButton:(NSButton *)value;
- (NSInteger)quickSelectedGrammarIndex;
- (void)setQuickSelectedGrammarIndex:(NSInteger)value;
- (FYAnalysisResult *)quickSentenceAnalysis;
- (NSString *)quickSentenceAnalysisError;
- (NSString *)quickSentenceAnalysisSource;
- (BOOL)quickSentenceAnalyzing;
- (NSButton *)quickSentenceBookmarkButton;
- (void)setQuickSentenceBookmarkButton:(NSButton *)value;
- (NSString *)quickSentenceID;
- (BOOL)quickSentenceIsInlineBlock;
- (FYStudyOverlayPanel *)quickSentencePanel;
- (void)setQuickSentencePanel:(FYStudyOverlayPanel *)value;
- (NSString *)quickSentenceSource;
- (NSString *)quickSentenceTranslation;
- (NSUInteger)quickSourceHoverGeneration;
- (void)setQuickSourceHoverGeneration:(NSUInteger)value;
- (FYSelectableSourceTextView *)quickSourceTextView;
- (void)setQuickSourceTextView:(FYSelectableSourceTextView *)value;
- (NSArray<NSButton *> *)quickStructureButtons;
- (BOOL)sentenceBookmarkPending;
- (NSColor *)uiAccent;
- (NSColor *)uiBorder;
- (NSColor *)uiInk;
- (NSColor *)uiMuted;
- (NSColor *)uiSelected;
- (NSView *)card;
- (void)closeStudyOverlay:(id)sender;
- (void)configureStudyOverlay:(NSPanel *)panel;
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick;
- (NSStackView *)horizontalStack;
- (NSTextField *)mutedLabel:(NSString *)text;
- (FYGrammarBookmark *)quickGrammarBookmark;
- (NSView *)quickGrammarDetailForItem:(FYGrammarItem *)item;
- (NSView *)quickReadingCard:(NSStackView *)stack tinted:(BOOL)tinted;
- (NSTextField *)quickReadingLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color;
- (BOOL)quickSentenceIsBookmarked;
- (void)refreshOverlayVisibility:(id)sender;
- (void)refreshQuickSentenceHoverTips;
- (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick;
- (void)selectQuickGrammar:(NSButton *)sender;
- (NSView *)separator;
- (NSView *)spacer;
- (CGFloat)structureScrollOffsetForQuick:(BOOL)quick;
- (NSView *)structureViewForAnalysis:(FYAnalysisResult *)analysis source:(NSString *)source quick:(BOOL)quick;
- (void)updateGrammarActionControlsForQuick:(BOOL)quick;
- (void)updateQuickGrammarBookmark;
- (NSStackView *)verticalStack;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
- (id)studyActionTarget;
@end

// Stateless native renderer; the original Study receiver owns every view.
@interface FYQuickSentenceRenderer : NSObject
+ (void)selectQuickStructure:(NSButton *)sender receiver:(id<FYQuickSentenceRenderSource>)receiver;
+ (void)updateQuickGrammarBookmarkWithReceiver:(id<FYQuickSentenceRenderSource>)receiver;
+ (NSView *)quickGrammarDetailForItem:(FYGrammarItem *)item receiver:(id<FYQuickSentenceRenderSource>)receiver;
+ (void)selectQuickGrammar:(NSButton *)sender receiver:(id<FYQuickSentenceRenderSource>)receiver;
+ (NSTextField *)quickReadingLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color receiver:(id<FYQuickSentenceRenderSource>)receiver;
+ (NSView *)quickReadingCard:(NSStackView *)stack tinted:(BOOL)tinted receiver:(id<FYQuickSentenceRenderSource>)receiver;
+ (void)renderQuickSentenceWithReceiver:(id<FYQuickSentenceRenderSource>)receiver;
@end
