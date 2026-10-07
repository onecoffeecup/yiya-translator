// Explicit grammar actions shared by the workspace and quick reading surface.
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick {
    FYGrammarActionState *state = quick ? self.quickGrammarActions : self.grammarActions;
    if (!state) {
        state = [FYGrammarActionState new];
        if (quick) { self.quickGrammarActions = state; } else { self.grammarActions = state; }
    }
    NSString *source = quick ? self.quickSentenceSource : self.learningCoordinator.currentSourceText;
    NSString *translation = quick ? self.quickSentenceTranslation : self.learningCoordinator.currentTranslation;
    NSString *sentenceID = quick ? self.quickSentenceID : self.learningCoordinator.currentSentenceID;
    NSInteger version = quick ? self.quickSentenceVersion : self.learningCoordinator.currentVersion;
    NSString *model = Trim(self.learningModelField.stringValue);
    if (!model.length) { model = self.modelField.stringValue ?: @""; }
    NSString *base = self.baseURLField.stringValue ?: @"", *key = self.apiKeyField.stringValue ?: @"";
    NSArray *identity = @[sentenceID ?: @"", @(version), source ?: @"", translation ?: @"", base, model];
    NSString *context = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:identity options:0 error:NULL] encoding:NSUTF8StringEncoding];
    if (![state.context isEqualToString:context] || ![state.analyzer.apiKey isEqualToString:key]) {
        [state reset]; state.context = context;
    }
    state.analyzer.baseURL = base; state.analyzer.model = model; state.analyzer.apiKey = key;
    state.analyzer.catalog = self.grammarCatalog;
    if (!state.analyzer.transport) { state.analyzer.transport = (quick ? self.quickSentenceAnalyzer : self.learningAnalyzer).transport; }
    return state;
}

- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick {
    if (quick) {
        if (![self.quickSentenceSource isEqualToString:self.quickSentenceAnalysisSource]) { return nil; }
        return [FYLearningCoordinator grammarItemInList:self.quickSentenceAnalysis.grammar index:self.quickSelectedGrammarIndex fallbackToFirst:NO];
    }
    return [self analysisMatchesCurrentSentence] ? [self selectedGrammarItem] : nil;
}

- (void)updateGrammarActionControlsForQuick:(BOOL)quick {
    FYGrammarActionState *state = [self grammarActionsForQuick:quick];
    FYGrammarItem *item = [self grammarActionItemForQuick:quick];
    NSButton *expand = quick ? self.quickGrammarExpandButton : self.grammarExpandButton;
    BOOL busy = item && [state.pending containsObject:item];
    expand.hidden = item == nil; expand.enabled = item != nil && !busy;
    expand.title = busy ? @"正在展开…" : (state.expandedItem == item && item ? @"收起解释" : (item && [state.errors objectForKey:item] ? @"重试解释" : @"展开解释"));
    expand.accessibilityHelp = @"按需补充选中语法的接续、当前句用法和例句";
    if (!quick) {
        self.grammarExpandedLabel.hidden = !item || state.expandedItem != item;
        self.grammarExpandedLabel.stringValue = item ? ([state.explanations objectForKey:item] ?: [state.errors objectForKey:item] ?: @"正在补充接续、用法与例句…") : @"";
    }
    FYAnalysisResult *result = quick ? self.quickSentenceAnalysis : self.currentAnalysis;
    BOOL applicable = quick ? [self.quickSentenceSource isEqualToString:self.quickSentenceAnalysisSource] : [self analysisMatchesCurrentSentence];
    NSButton *review = quick ? self.quickGrammarReviewButton : self.grammarReviewButton;
    review.hidden = !result || !applicable;
    review.enabled = result && applicable && !state.reviewing && !(quick ? self.quickSentenceAnalyzing : self.learningAnalysisBusy);
    review.title = state.reviewing ? @"正在复核…" : @"深度复核";
    if (quick) {
        self.quickGrammarReviewStatus.stringValue = state.reviewStatus ?: @"";
        self.quickGrammarReviewStatus.hidden = !state.reviewStatus.length;
    }
}

- (void)refreshQuickGrammarActionDetail {
    FYGrammarItem *item = [self grammarActionItemForQuick:YES];
    if (!item || !self.quickGrammarStack) { return; }
    NSScrollView *scroll = self.quickGrammarStack.enclosingScrollView;
    NSPoint position = scroll.contentView.bounds.origin;
    [self.quickGrammarStack removeArrangedSubview:self.quickGrammarDetailCard];
    [self.quickGrammarDetailCard removeFromSuperview];
    self.quickGrammarDetailCard = [self quickGrammarDetailForItem:item];
    [self.quickGrammarStack addArrangedSubview:self.quickGrammarDetailCard];
    [self.quickSentencePanel.contentView layoutSubtreeIfNeeded];
    position.y = MIN(position.y, MAX(0, NSHeight(scroll.documentView.frame)-NSHeight(scroll.contentView.bounds)));
    [scroll.contentView scrollToPoint:position]; [scroll reflectScrolledClipView:scroll.contentView];
}

- (void)toggleGrammarExplanation:(NSButton *)sender {
    BOOL quick = sender.tag == 1;
    FYGrammarItem *item = [self grammarActionItemForQuick:quick];
    if (!item) { return; }
    FYGrammarActionState *state = [self grammarActionsForQuick:quick];
    if ([state.pending containsObject:item]) { return; }
    if (state.expandedItem == item && ![state.errors objectForKey:item]) {
        state.expandedItem = nil;
    } else {
        state.expandedItem = item;
        if (![state.explanations objectForKey:item]) {
            [state.errors removeObjectForKey:item]; [state.pending addObject:item];
            NSInteger generation = state.generation;
            NSString *source = quick ? self.quickSentenceSource : self.learningCoordinator.currentSourceText;
            NSString *translation = quick ? self.quickSentenceTranslation : self.learningCoordinator.currentTranslation;
            [state.analyzer expandedExplanationForGrammar:item sentenceText:source translation:translation completion:^(NSString *answer, NSError *error) {
                if (generation != state.generation) { return; }
                if ([self grammarActionsForQuick:quick] != state || generation != state.generation) { return; }
                [state.pending removeObject:item];
                if (error || !Trim(answer).length) {
                    [state.errors setObject:[NSString stringWithFormat:@"解释未完成：%@；点击重试。", error.localizedDescription ?: @"返回内容为空"] forKey:item];
                } else { [state.explanations setObject:answer forKey:item]; }
                if (quick) { [self refreshQuickGrammarActionDetail]; }
                [self updateGrammarActionControlsForQuick:quick];
            }];
        }
    }
    if (quick) { [self refreshQuickGrammarActionDetail]; }
    [self updateGrammarActionControlsForQuick:quick];
}

- (void)updateGrammarReviewDisplayForQuick:(BOOL)quick preservingPosition:(void (^)(void))updates {
    NSScrollView *before = quick ? [self quickSentenceScrollView] : self.grammarReviewButton.enclosingScrollView;
    NSPoint position = before.contentView.bounds.origin;
    updates();
    // Quick reading replaces its entire document on success. Restore into the
    // new scroll view after layout, using the position at this update, not the
    // request's starting position (the reader may have scrolled while waiting).
    NSScrollView *after = quick ? [self quickSentenceScrollView] : self.grammarReviewButton.enclosingScrollView;
    if (!before || !after) { return; }
    [after.window.contentView layoutSubtreeIfNeeded];
    [after.superview layoutSubtreeIfNeeded];
    [after.documentView layoutSubtreeIfNeeded];
    CGFloat maxY = MAX(0, NSHeight(after.documentView.frame)-NSHeight(after.contentView.bounds));
    CGFloat maxX = MAX(0, NSWidth(after.documentView.frame)-NSWidth(after.contentView.bounds));
    [after.contentView scrollToPoint:NSMakePoint(MIN(MAX(0,position.x),maxX), MIN(MAX(0,position.y),maxY))];
    [after reflectScrolledClipView:after.contentView];
}

- (void)reviewGrammarSentence:(NSButton *)sender {
    BOOL quick = sender.tag == 1;
    FYAnalysisResult *existing = quick ? self.quickSentenceAnalysis : self.currentAnalysis;
    if (!existing || (!quick && ![self analysisMatchesCurrentSentence]) || (quick && ![self.quickSentenceSource isEqualToString:self.quickSentenceAnalysisSource])) { return; }
    FYGrammarActionState *state = [self grammarActionsForQuick:quick];
    if (state.reviewing || (quick ? self.quickSentenceAnalyzing : self.learningAnalysisBusy)) { return; }
    state.reviewing = YES; state.reviewStatus = @"正在补查遗漏与疑点，已有解释仍可阅读。";
    NSInteger generation = state.generation;
    [self updateGrammarReviewDisplayForQuick:quick preservingPosition:^{
        if (!quick) { [self.learningCoordinator pinCurrent]; [self refreshLearningStatus]; self.grammarStatusLabel.stringValue = state.reviewStatus; }
        [self updateGrammarActionControlsForQuick:quick];
    }];
    void (^finish)(FYAnalysisResult *, NSError *) = ^(FYAnalysisResult *result, NSError *error) {
        if (generation != state.generation) { return; }
        if ([self grammarActionsForQuick:quick] != state || generation != state.generation) { return; }
        state.reviewing = NO;
        [self updateGrammarReviewDisplayForQuick:quick preservingPosition:^{
            if (error) { state.reviewStatus = [NSString stringWithFormat:@"复核失败：%@；已有结果已保留，可重试。", error.localizedDescription]; }
            else {
                NSUInteger added = result.grammar.count > existing.grammar.count ? result.grammar.count-existing.grammar.count : 0;
                state.reviewStatus = added ? [NSString stringWithFormat:@"复核完成 · 补充了 %lu 条语法", (unsigned long)added] : @"复核完成 · 本次没有新增语法";
                if (quick) { self.quickSentenceAnalysis = result; [self renderQuickSentence]; }
                else { self.currentAnalysis = result; [self refreshGrammarResults]; }
            }
            if (!quick) { self.grammarStatusLabel.stringValue = state.reviewStatus; }
            [self updateGrammarActionControlsForQuick:quick];
        }];
    };
    if (quick) {
        [state.analyzer reviewSentence:self.quickSentenceSource translation:self.quickSentenceTranslation existingResult:existing completion:finish];
    } else { [self syncLearningAnalyzerConfig]; [self.learningCoordinator reviewCurrentAnalysis:existing completion:finish]; }
}
