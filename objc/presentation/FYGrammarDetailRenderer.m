#import "FYGrammarDetailRenderer.h"
#import "../learning/FYLearningCoordinator.h"
#import "../learning/FYLearningViews.h"
#import "FYPresentationText.h"
#import <QuartzCore/QuartzCore.h>
@implementation FYGrammarDetailRenderer

+ (void)renderGrammarDetailAtIndex:(NSInteger)index source:(id<FYGrammarDetailSource>)source {
    source.grammarPageAnalyzeButton.title = @"重新分析";
    FYGrammarItem *item = source.currentAnalysis.grammar[index];
    source.grammarDetailNameLabel.stringValue = item.name;
    source.grammarDetailLevelLabel.stringValue = item.referenceLevel.length
        ? [NSString stringWithFormat:@"参考 %@%@", item.referenceLevel, item.levelVerified ? @"" : @" · 待核实"] : @"等级待核实";
    source.grammarResultsLabel.hidden = YES;
    // 一句解释
    source.grammarDetailBodyLabel.hidden = NO;
    source.grammarDetailBodyLabel.stringValue = item.meaning.length ? item.meaning : @"这条语法暂无可核实的释义。";
    // 横向短字段：接续 / 语体（全部来自真实分析结果）
    [source clearArrangedSubviews:source.grammarDetailFields];
    NSMutableArray<NSArray *> *fields = [NSMutableArray array];
    if (item.connection.length) { [fields addObject:@[@"接续", item.connection]]; }
    if (item.registerNote.length) { [fields addObject:@[@"语体", item.registerNote]]; }
    if (fields.count == 0) { [fields addObject:@[@"接续", @"待补充"]]; }
    for (NSArray *field in fields) {
        NSStackView *chip = [source verticalStack]; chip.spacing = 2;
        [chip addArrangedSubview:[source mutedLabel:field[0]]];
        NSTextField *value = [source label:field[1] font:FYUIFont(13, NSFontWeightRegular) color:source.uiInk];
        value.maximumNumberOfLines = 3;
        [chip addArrangedSubview:value];
        [chip.widthAnchor constraintGreaterThanOrEqualToConstant:104].active = YES;
        [source.grammarDetailFields addArrangedSubview:chip];
    }
    // 用法或例句块
    [source clearArrangedSubviews:source.grammarUsageBlock];
    if (item.explanation.length) {
        [source.grammarUsageBlock addArrangedSubview:[source mutedLabel:@"本句用法"]];
        NSTextField *usage = [source label:item.explanation font:FYUIFont(13, NSFontWeightRegular) color:source.uiInk];
        usage.maximumNumberOfLines = 4;
        [source.grammarUsageBlock addArrangedSubview:usage];
    }
    NSString *example = Trim(source.grammarExampleLabel.stringValue);
    if (example.length && ![example isEqualToString:@"还没有例句。"]) {
        [source.grammarUsageBlock addArrangedSubview:[source mutedLabel:@"例句"]];
        NSTextField *exampleLabel = [source label:example font:FYUIFont(13, NSFontWeightRegular) color:source.uiInk];
        exampleLabel.maximumNumberOfLines = 4;
        [source.grammarUsageBlock addArrangedSubview:exampleLabel];
    }
    if (item.levelSourceTitle.length) {
        [source.grammarUsageBlock addArrangedSubview:[source mutedLabel:[NSString stringWithFormat:@"解释由 AI 生成；等级参考：%@", item.levelSourceTitle]]];
    }
    source.grammarSourceLinkButton.hidden = item.levelSourceURL.length == 0;
    source.grammarSourceLinkButton.toolTip = item.levelSourceURL;
    source.grammarDetailBookmarkButton.hidden = NO;
    source.grammarDetailBookmarkButton.enabled = YES;
    source.grammarDetailBookmarkButton.tag = index;
    source.grammarDetailBookmarkButton.title = [source bookmarkForCurrentGrammar] ? @"已收藏 · 取消收藏" : @"收藏此语法";
    [source updateGrammarActionControlsForQuick:NO];
}

+ (void)highlightGrammarMatchesWithSource:(id<FYGrammarDetailSource>)source {
    NSColor *hl = source.uiSelected;
    [source applyHighlight:hl toTextView:source.learningSourceTextView];
    [source applyHighlight:hl toTextView:source.grammarSourceTextView];
    [source refreshSourceHoverTips];
}

+ (void)applyHighlight:(NSColor *)color toTextView:(NSTextView *)textView source:(id<FYGrammarDetailSource>)source {
    if (!textView) { return; }
    NSString *text = textView.string ?: @"";
    [textView.textStorage removeAttribute:NSBackgroundColorAttributeName range:NSMakeRange(0, text.length)];
    if (!color || !source.currentAnalysis) { return; }
    if (![source analysisMatchesCurrentSentence]) { return; }
    for (FYGrammarItem *item in [FYLearningCoordinator applicableGrammarItems:source.currentAnalysis.grammar text:text]) {
        NSColor *highlight = item == [source selectedGrammarItem] ? [source.uiAccent colorWithAlphaComponent:0.23] : color;
        [textView.textStorage addAttribute:NSBackgroundColorAttributeName value:highlight range:item.matchedRange];
    }
}

+ (void)clearGrammarHighlightWithSource:(id<FYGrammarDetailSource>)source {
    [source applyHighlight:nil toTextView:source.learningSourceTextView];
    [source applyHighlight:nil toTextView:source.grammarSourceTextView];
    [source refreshSourceHoverTips];
}

+ (void)applyGrammarSelectionLocallyWithSource:(id<FYGrammarDetailSource>)source {
    for (NSButton *node in source.mainStructureButtons) {
        node.layer.backgroundColor = (node.tag == source.selectedGrammarIndex ? source.uiSelected : FYAdventureColor(@"paper")).CGColor;
    }
    for (NSView *view in source.grammarOtherStack.arrangedSubviews) {
        if (![view isKindOfClass:NSButton.class]) { continue; }
        NSButton *button = (NSButton *)view;
        BOOL on = (NSInteger)button.tag == source.selectedGrammarIndex;
        button.state = on ? NSControlStateValueOn : NSControlStateValueOff;
        button.layer.backgroundColor = (on ? source.uiSelected : source.uiSurface).CGColor;
    }
    if (source.selectedGrammarIndex >= 0 && source.selectedGrammarIndex < (NSInteger)source.currentAnalysis.grammar.count) {
        [source renderGrammarDetailAtIndex:source.selectedGrammarIndex];
    }
    [source highlightGrammarMatches];
}

+ (void)updateGrammarActionControlsForQuick:(BOOL)quick source:(id<FYGrammarDetailSource>)source {
    FYGrammarActionState *state = [source grammarActionsForQuick:quick];
    FYGrammarItem *item = [source grammarActionItemForQuick:quick];
    NSButton *expand = quick ? source.quickGrammarExpandButton : source.grammarExpandButton;
    BOOL busy = item && [state.pending containsObject:item];
    expand.hidden = item == nil; expand.enabled = item != nil && !busy;
    expand.title = busy ? @"正在展开…" : (state.expandedItem == item && item ? @"收起解释" : (item && [state.errors objectForKey:item] ? @"重试解释" : @"展开解释"));
    expand.accessibilityHelp = @"按需补充选中语法的接续、当前句用法和例句";
    if (!quick) {
        source.grammarExpandedLabel.hidden = !item || state.expandedItem != item;
        source.grammarExpandedLabel.stringValue = item ? ([state.explanations objectForKey:item] ?: [state.errors objectForKey:item] ?: @"正在补充接续、用法与例句…") : @"";
    }
    FYAnalysisResult *result = quick ? source.quickSentenceAnalysis : source.currentAnalysis;
    BOOL applicable = quick ? [source.quickSentenceSource isEqualToString:source.quickSentenceAnalysisSource] : [source analysisMatchesCurrentSentence];
    NSButton *review = quick ? source.quickGrammarReviewButton : source.grammarReviewButton;
    review.hidden = !result || !applicable;
    review.enabled = result && applicable && !state.reviewing && !(quick ? source.quickSentenceAnalyzing : source.learningAnalysisBusy);
    review.title = state.reviewing ? @"正在复核…" : @"深度复核";
    if (quick) {
        source.quickGrammarReviewStatus.stringValue = state.reviewStatus ?: @"";
        source.quickGrammarReviewStatus.hidden = !state.reviewStatus.length;
    }
}
@end
