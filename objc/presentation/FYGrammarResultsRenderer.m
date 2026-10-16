#import "FYGrammarResultsRenderer.h"
#import "../learning/FYLearningCoordinator.h"
#import "../learning/FYLearningViews.h"
#import <QuartzCore/QuartzCore.h>
@implementation FYGrammarResultsRenderer

+ (void)setAnalyzeBusy:(BOOL)busy receiver:(id<FYGrammarResultsSource>)receiver {
    receiver.learningAnalysisBusy = busy;
    receiver.grammarPageAnalyzeButton.title = busy ? @"分析中…" : (receiver.currentAnalysis ? @"重新分析" : @"分析此句");
    receiver.analyzeButton.enabled = !busy;
    if (receiver.grammarPageAnalyzeButton) { receiver.grammarPageAnalyzeButton.enabled = !busy; }
    if (busy) { receiver.grammarStatusLabel.stringValue = @"正在分析…"; }
    [receiver applyGrammarTabSelection];
}

+ (void)refreshGrammarResultsWithReceiver:(id<FYGrammarResultsSource>)receiver {
    FYAnalysisResult *result = receiver.currentAnalysis;
    receiver.grammarAnalysisError = nil;
    [receiver updateGrammarActionControlsForQuick:NO];
    receiver.grammarStructureCard.hidden = result == nil;
    receiver.grammarDetailFields.hidden = result == nil;
    receiver.grammarStatusLabel.textColor = receiver.uiMuted;
    receiver.sentenceInsightLabel.stringValue = result.sentenceNote ?: @"";
    NSString *levelTag = [receiver currentSentenceLevelTag];
    receiver.liveLevelTag.stringValue = levelTag ?: @"";
    receiver.liveLevelTag.hidden = levelTag.length == 0;
    CGFloat keptStructureOffset = [receiver structureScrollOffsetForQuick:NO];
    [receiver clearArrangedSubviews:receiver.sentenceStructureStack];
    NSView *structure=[receiver structureViewForAnalysis:result source:receiver.learningCoordinator.currentSourceText quick:NO];
    if(structure){[receiver.sentenceStructureStack addArrangedSubview:structure];}
    else if(result){[receiver.sentenceStructureStack addArrangedSubview:[receiver mutedLabel:@"本次解析没有整句结构图，可重新分析获取。"]];}
    receiver.sentenceInsightStack.hidden = !result;
    for (NSControl *control in receiver.grammarFollowupControls) { control.enabled = result.grammar.count > 0 && [receiver analysisMatchesCurrentSentence]; }
    receiver.followupRequestGeneration += 1;
    [receiver clearArrangedSubviews:receiver.grammarOtherStack];
    receiver.grammarFollowupResultLabel.stringValue = @"";
    if (!result || result.grammar.count == 0) {
        receiver.grammarDetailBodyLabel.hidden = NO;
        receiver.grammarStatusLabel.stringValue = result ? @"没有识别到语法" : @"尚未分析";
        receiver.grammarDetailNameLabel.stringValue = result ? @"没有识别结果" : @"尚未分析";
        receiver.grammarDetailLevelLabel.stringValue = @"";
        receiver.grammarDetailBodyLabel.stringValue = result
            ? @"这一句没有识别到可高亮的语法（可能是基础表达）。"
            : @"请在实时翻译页选中一句并点「分析此句」。";
        receiver.grammarDetailBookmarkButton.hidden = YES;
        [receiver clearArrangedSubviews:receiver.grammarDetailFields];
        receiver.grammarSourceLinkButton.hidden = YES;
        receiver.grammarOtherEmptyLabel.stringValue = @"没有其他识别结果。";
        [receiver clearGrammarHighlight];
        [receiver applyGrammarTabSelection];
        return;
    }
    if (receiver.selectedGrammarIndex < 0 || receiver.selectedGrammarIndex >= (NSInteger)result.grammar.count) {
        receiver.selectedGrammarIndex = 0;
    }
    receiver.grammarStatusLabel.stringValue = [NSString stringWithFormat:@"识别到 %lu 条语法", (unsigned long)result.grammar.count];
    [receiver renderGrammarDetailAtIndex:receiver.selectedGrammarIndex];
    receiver.grammarOtherEmptyLabel.stringValue = @"选择一项查看含义、接续与命中位置。";
    for (NSUInteger i = 0; i < result.grammar.count; i++) {
        FYGrammarItem *item = result.grammar[i];
        NSString *level = item.referenceLevel.length ? [NSString stringWithFormat:@"参考 %@%@", item.referenceLevel, item.levelVerified ? @"" : @" · 待核实"] : @"等级待核实";
        NSString *title = item.name;
        NSButton *button = [receiver workspaceButton:title action:@selector(selectGrammarItem:) primary:NO];
        button.toolTip = level; button.state = i == (NSUInteger)receiver.selectedGrammarIndex ? NSControlStateValueOn : NSControlStateValueOff;
        button.bezelStyle = NSBezelStyleRegularSquare;
        button.bordered = NO;
        button.alignment = NSTextAlignmentLeft;
        button.font = FYUIFont(14, NSFontWeightRegular);
        button.wantsLayer = YES;
        button.layer.cornerRadius = 5;
        button.layer.backgroundColor = (i == (NSUInteger)receiver.selectedGrammarIndex ? receiver.uiSelected : receiver.uiSurface).CGColor;
        button.tag = i;
        button.lineBreakMode = NSLineBreakByTruncatingTail;
        button.cell.truncatesLastVisibleLine = YES;
        [receiver.grammarOtherStack addArrangedSubview:button];
        [button.widthAnchor constraintEqualToAnchor:receiver.grammarOtherStack.widthAnchor].active = YES;
    }
    [receiver highlightGrammarMatches];
    [receiver applyGrammarTabSelection];
    [receiver restoreStructureScrollOffset:keptStructureOffset quick:NO];
}

+ (void)clearAnalysisDisplayWithReceiver:(id<FYGrammarResultsSource>)receiver {
    [receiver.grammarActions reset];
    receiver.grammarExpandButton.hidden = YES; receiver.grammarExpandedLabel.hidden = YES;
    receiver.grammarReviewButton.hidden = YES;
    receiver.analysisRequestGeneration += 1;
    receiver.followupRequestGeneration += 1;
    receiver.currentAnalysis = nil;
    receiver.grammarAnalysisError = nil;
    [receiver setAnalyzeBusy:NO];
    [receiver clearArrangedSubviews:receiver.grammarDetailFields];
    receiver.grammarDetailBodyLabel.hidden = NO;
    receiver.grammarSourceLinkButton.hidden = YES;
    receiver.grammarStatusLabel.stringValue = @"尚未分析";
    receiver.currentAnalysis = nil;
    receiver.sentenceInsightLabel.stringValue = @""; receiver.sentenceInsightStack.hidden = YES;
    receiver.grammarStatusLabel.textColor = receiver.uiMuted;
    for (NSControl *control in receiver.grammarFollowupControls) { control.enabled = NO; }
    receiver.selectedGrammarIndex = 0;
    receiver.grammarResultsLabel.stringValue = @"";
    receiver.grammarFollowupResultLabel.stringValue = @"";
    [receiver clearArrangedSubviews:receiver.grammarOtherStack];
    receiver.grammarDetailNameLabel.stringValue = @"尚未分析";
    receiver.grammarDetailLevelLabel.stringValue = @"";
    receiver.grammarDetailBodyLabel.stringValue = @"分析句子后，这里显示选中语法的含义、接续、当前句用法与资料来源。";
    receiver.grammarDetailBookmarkButton.hidden = YES;
    receiver.grammarOtherEmptyLabel.stringValue = @"分析后这里列出这一句的其他语法。";
    [receiver clearGrammarHighlight];
}

+ (void)applyGrammarTabSelectionWithReceiver:(id<FYGrammarResultsSource>)receiver {
    NSArray<NSString *> *titles = @[@"整句理解", @"语法点", @"例句"];
    for (NSUInteger index = 0; index < receiver.grammarTabButtons.count; index++) {
        NSButton *tab = receiver.grammarTabButtons[index];
        BOOL active = index == (NSUInteger)receiver.selectedGrammarTab;
        tab.contentTintColor = active ? receiver.uiInk : receiver.uiMuted;
        tab.font = FYUIFont(13, active ? NSFontWeightSemibold : NSFontWeightRegular);
        tab.title = titles[index];
        NSView *underline = index < receiver.grammarTabUnderlines.count ? receiver.grammarTabUnderlines[index] : nil;
        underline.layer.backgroundColor = (active ? FYAdventureColor(@"leaf") : NSColor.clearColor).CGColor;
    }
    BOOL hasResult = receiver.currentAnalysis != nil;
    [receiver updateGrammarActionControlsForQuick:NO];
    BOOL emptyGrammar = hasResult && receiver.selectedGrammarTab == 1 && receiver.currentAnalysis.grammar.count == 0;
    BOOL showEmpty = !hasResult || emptyGrammar;
    receiver.grammarTabRow.hidden = !hasResult;
    receiver.grammarStatusLabel.hidden = !hasResult;
    receiver.grammarReferenceNote.hidden = !hasResult;
    receiver.grammarEmptyPane.hidden = !showEmpty;
    receiver.sentenceInsightStack.hidden = !hasResult || receiver.selectedGrammarTab != 0;
    receiver.grammarPointsPane.hidden = showEmpty || receiver.selectedGrammarTab != 1;
    receiver.grammarExamplesPane.hidden = !hasResult || receiver.selectedGrammarTab != 2;

    BOOL hasSentence = receiver.learningCoordinator.currentSentenceID.length > 0 && receiver.learningCoordinator.currentSourceText.length > 0;
    NSString *title = @"这句话还没有分析";
    NSString *hint = @"分析后，查看语法含义、接续和本句用法。";
    NSString *action = emptyGrammar ? @"重新分析" : @"分析此句";
    if (receiver.learningAnalysisBusy) {
        title = @"正在分析这句话";
        hint = @"正在整理语法点、接续和本句用法…";
        action = @"分析中…";
    } else if (!hasSentence) {
        title = @"等待一句原文";
        hint = @"开始翻译，或从最近台词中选择一句，再来查看语法。";
    } else if (receiver.grammarAnalysisError.length) {
        title = @"这次分析没有完成";
        hint = [NSString stringWithFormat:@"%@\n请检查原句或翻译服务后重试。", receiver.grammarAnalysisError];
        action = @"重试分析";
    } else if (emptyGrammar) {
        title = @"这句没有识别到语法点";
        hint = @"可以切换到「整句理解」查看解释，或重新分析。";
    }
    receiver.grammarEmptyTitle.stringValue = title;
    receiver.grammarEmptyHint.stringValue = hint;
    receiver.grammarEmptyAnalyzeButton.title = action;
    receiver.grammarEmptyAnalyzeButton.enabled = hasSentence && !receiver.learningAnalysisBusy;
}

+ (void)toggleGrammarFollowupWithReceiver:(id<FYGrammarResultsSource>)receiver {
    // 主界面已移除追问入口（追问统一走右侧 AI 伙伴）；方法保留，供复用同一套逻辑的入口调用。
    if (!receiver.grammarFollowupDisclosure) { return; }
    BOOL willShow = receiver.grammarFollowupDisclosure.hidden;
    receiver.grammarFollowupDisclosure.hidden = !willShow;
    if (receiver.grammarFollowupToggle) {
        receiver.grammarFollowupToggle.title = willShow ? @"收起追问" : @"追问";
        receiver.grammarFollowupToggle.state = willShow ? NSControlStateValueOn : NSControlStateValueOff;
    }
}
@end
