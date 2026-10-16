#import "FYCollectionRenderer.h"
#import "../learning/FYLearningViews.h"
#import "../learning/FYSavedWordReferenceView.h"
#import "../learning/FYLearningCoordinator.h"

@implementation FYCollectionRenderer
+ (NSView *)makeVocabularyPageWithReceiver:(id<FYCollectionRenderSource>)receiver {
    NSStackView *page = [receiver verticalStack];
    page.spacing = 14;

    NSStackView *header = [receiver horizontalStack];
    NSStackView *titleCol = [receiver verticalStack];
    titleCol.spacing = 4;
    receiver.learningCollectionTitle=[receiver label:@"从原句留下来的词" font:FYUIFont(20, NSFontWeightSemibold) color:receiver.uiInk];
    [titleCol addArrangedSubview:receiver.learningCollectionTitle];
    receiver.learningCollectionCount=[receiver mutedLabel:@"0 个收藏"];
    [titleCol addArrangedSubview:receiver.learningCollectionCount];
    [titleCol.widthAnchor constraintGreaterThanOrEqualToConstant:210].active=YES;
    [header addArrangedSubview:titleCol];
    [header addArrangedSubview:[receiver spacer]];
    NSButton *goPick = [receiver workspaceButton:@"选词收藏" action:@selector(backToSourcePage:) primary:NO];
    [header addArrangedSubview:goPick];
    [page addArrangedSubview:header];

    NSStackView *tabs=[receiver horizontalStack];tabs.spacing=8;
    NSMutableArray *tabButtons=[NSMutableArray new];
    NSArray *tabTitles=@[@"词语",@"语法",@"句子",@"复习"];
    for(NSInteger index=0;index<4;index++){
        NSButton *button=[receiver workspaceButton:tabTitles[index] action:@selector(selectLearningCollection:) primary:NO];
        button.tag=index;[tabs addArrangedSubview:button];[tabButtons addObject:button];
    }
    receiver.learningCollectionTabs=tabButtons;[page addArrangedSubview:tabs];
    receiver.learningCollectionHost=[receiver verticalStack];[page addArrangedSubview:receiver.learningCollectionHost];
    NSStackView *words=[receiver verticalStack];words.spacing=12;

    receiver.vocabularyListLabel = [receiver label:@"暂无收藏" font:FYUIFont(13, NSFontWeightRegular) color:receiver.uiMuted];
    receiver.vocabularyListLabel.maximumNumberOfLines = 0;
    receiver.vocabularyListLabel.lineBreakMode = NSLineBreakByWordWrapping;
    NSStackView *empty = [receiver verticalStack];
    [empty addArrangedSubview:receiver.vocabularyListLabel];
    receiver.vocabularyEmptyCard = [receiver cardWithStack:empty];
    receiver.vocabularyListLabel.alignment = NSTextAlignmentCenter;
    [words addArrangedSubview:receiver.vocabularyEmptyCard];

    receiver.wordCardStack = [receiver verticalStack];
    receiver.wordCardStack.spacing = 12;
    [words addArrangedSubview:receiver.wordCardStack];

    // —— 简单复习（辅助入口）——
    NSStackView *reviewCard = [receiver verticalStack];
    reviewCard.spacing = 10;
    [reviewCard addArrangedSubview:[receiver cardTitle:@"简单复习"]];
    receiver.reviewPromptLabel = [receiver mutedLabel:@"点「下一个词」开始遮义复习"];
    [reviewCard addArrangedSubview:receiver.reviewPromptLabel];
    receiver.reviewWordLabel = [receiver label:@"" font:FYUIFont(18, NSFontWeightBold) color:receiver.uiInk];
    receiver.reviewWordLabel.hidden = YES;
    [reviewCard addArrangedSubview:receiver.reviewWordLabel];
    receiver.reviewMeaningLabel = [receiver label:@"" font:FYUIFont(13, NSFontWeightRegular) color:receiver.uiInk];
    receiver.reviewMeaningLabel.maximumNumberOfLines = 0;
    receiver.reviewMeaningLabel.lineBreakMode = NSLineBreakByWordWrapping;
    receiver.reviewMeaningLabel.hidden = YES;
    [reviewCard addArrangedSubview:receiver.reviewMeaningLabel];
    NSStackView *reviewButtons = [receiver horizontalStack];
    receiver.revealButton = [NSButton buttonWithTitle:@"揭晓释义" target:[receiver collectionActionTarget] action:@selector(revealReviewMeaning:)];
    receiver.revealButton.bezelStyle = NSBezelStyleRounded;
    receiver.knownButton = [NSButton buttonWithTitle:@"记住了" target:[receiver collectionActionTarget] action:@selector(markReviewKnown:)];
    receiver.knownButton.bezelStyle = NSBezelStyleRounded;
    receiver.notYetButton = [NSButton buttonWithTitle:@"还不熟" target:[receiver collectionActionTarget] action:@selector(markReviewLearning:)];
    receiver.notYetButton.bezelStyle = NSBezelStyleRounded;
    NSButton *nextWord = [NSButton buttonWithTitle:@"下一个词" target:[receiver collectionActionTarget] action:@selector(nextReviewWord:)];
    nextWord.bezelStyle = NSBezelStyleRounded;
    NSButton *removeWord = [NSButton buttonWithTitle:@"取消收藏" target:[receiver collectionActionTarget] action:@selector(removeReviewWord:)];
    removeWord.bezelStyle = NSBezelStyleRounded;
    [reviewButtons addArrangedSubview:receiver.revealButton];
    [reviewButtons addArrangedSubview:receiver.knownButton];
    [reviewButtons addArrangedSubview:receiver.notYetButton];
    [reviewCard addArrangedSubview:reviewButtons];
    NSStackView *reviewNavigation=[receiver horizontalStack];
    [reviewNavigation addArrangedSubview:nextWord];[reviewNavigation addArrangedSubview:removeWord];
    [reviewCard addArrangedSubview:reviewNavigation];
    NSView *reviewSection=[receiver cardWithStack:reviewCard];

    // —— 已收藏语法卡片 ——
    NSStackView *savedGrammarCard = [receiver verticalStack];
    savedGrammarCard.spacing = 10;
    [savedGrammarCard addArrangedSubview:[receiver cardTitle:@"已收藏语法"]];
    receiver.grammarBookmarkListLabel = [receiver mutedLabel:@"暂无收藏。在实时翻译或查句弹窗中收藏语法。"];
    receiver.grammarBookmarkListLabel.maximumNumberOfLines = 0;
    receiver.grammarBookmarkListLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [savedGrammarCard addArrangedSubview:receiver.grammarBookmarkListLabel];
    receiver.savedGrammarCardStack = [receiver verticalStack];
    receiver.savedGrammarCardStack.spacing = 12;
    [savedGrammarCard addArrangedSubview:receiver.savedGrammarCardStack];
    NSView *grammarSection=[receiver cardWithStack:savedGrammarCard];
    NSStackView *sentences=[receiver verticalStack];[sentences addArrangedSubview:[receiver cardTitle:@"已收藏句子"]];
    receiver.savedSentenceStack=[receiver verticalStack];[sentences addArrangedSubview:receiver.savedSentenceStack];
    receiver.learningCollectionSections=@[words,grammarSection,[receiver cardWithStack:sentences],reviewSection];
    [receiver selectLearningCollection:tabButtons.firstObject];

    return page;
}

+ (NSView *)makeHistoryPageWithReceiver:(id<FYCollectionRenderSource>)receiver {
    NSStackView *page = [receiver verticalStack]; page.spacing = 18;
    NSStackView *header = [receiver horizontalStack];
    [header addArrangedSubview:[receiver mutedLabel:@"最近 5 条对白 · 选择一句，回到实时页查看语法"]];
    [header addArrangedSubview:[receiver spacer]];
    [header addArrangedSubview:[receiver workspaceButton:@"刷新台词" action:@selector(refreshHistoryAction:) primary:NO]];
    [page addArrangedSubview:header];
    receiver.historyListStack = [receiver verticalStack]; receiver.historyListStack.spacing = 12;
    [page addArrangedSubview:receiver.historyListStack];
    [page addArrangedSubview:[receiver mutedLabel:@"完整原句与译文一起保留。相同对白的识别波动合并展示。"]];
    return page;
}

+ (void)updateSummaryWithReceiver:(id<FYCollectionRenderSource>)receiver {
    NSArray *titles=@[@"从原句留下来的词",@"留下来的语法",@"想再读一遍的句子",@"带着原句复习"];
    NSInteger index=receiver.learningCollectionIndex;
    if(index<0 || index>=4){return;}
    receiver.learningCollectionTitle.stringValue=titles[index];
    NSUInteger count=index==1?receiver.grammarBookmarks.count:index==2?receiver.savedSentences.count:receiver.reviewList.count;
    receiver.learningCollectionCount.stringValue=[NSString stringWithFormat:index==3?@"%lu 个词可复习":@"%lu 个收藏",(unsigned long)count];
}

+ (void)selectCollection:(NSButton *)sender receiver:(id<FYCollectionRenderSource>)receiver {
    NSInteger index=sender.tag;if(index<0 || index>=(NSInteger)receiver.learningCollectionSections.count){return;}
    receiver.learningCollectionIndex=index;
    [receiver clearArrangedSubviews:receiver.learningCollectionHost];
    [receiver.learningCollectionHost addArrangedSubview:receiver.learningCollectionSections[index]];
    for(NSButton *button in receiver.learningCollectionTabs){button.state=button.tag==index?NSControlStateValueOn:NSControlStateValueOff;button.needsDisplay=YES;}
    [receiver updateLearningCollectionSummary];
}

+ (void)rebuildWordCardsWithReceiver:(id<FYCollectionRenderSource>)receiver {
    if (!receiver.revealedMeanings) { receiver.revealedMeanings = [NSMutableDictionary dictionary]; }
    NSInteger generation = ++receiver.wordCardsGeneration;
    [receiver clearArrangedSubviews:receiver.wordCardStack];
    for (NSUInteger i = 0; i < receiver.reviewList.count; i++) {
        FYVocabularyEntry *entry = receiver.reviewList[i];
        NSStackView *card = [receiver verticalStack];
        card.spacing = 6;
        NSStackView *titleRow = [receiver horizontalStack];
        NSString *lemma = entry.lemma.length > 0 ? entry.lemma : entry.surface;
        [titleRow addArrangedSubview:[receiver label:lemma font:FYUIFont(16, NSFontWeightBold) color:receiver.uiInk]];
        if (entry.reading.length > 0) {
            [titleRow addArrangedSubview:[receiver label:[NSString stringWithFormat:@"（%@）", entry.reading] font:FYUIFont(13, NSFontWeightRegular) color:receiver.uiMuted]];
        } else {
            [titleRow addArrangedSubview:[receiver mutedLabel:@"读音待补充"]];
        }
        [titleRow addArrangedSubview:[receiver spacer]];
        [card addArrangedSubview:titleRow];
        BOOL revealed = receiver.revealedMeanings[entry.vocabularyID]==nil || [receiver.revealedMeanings[entry.vocabularyID] boolValue];
        NSTextField *meaningLabel = [receiver label:(revealed ? (entry.meaning.length > 0 ? entry.meaning : @"释义待补充") : @"释义已遮住，先回忆它的意思。")
                                         font:FYUIFont(14, NSFontWeightRegular) color:receiver.uiInk];
        meaningLabel.maximumNumberOfLines = 0;
        meaningLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [card addArrangedSubview:meaningLabel];
        NSStackView *summaryActions=[receiver horizontalStack];
        NSButton *details=[receiver workspaceButton:[receiver.expandedWordCards containsObject:entry.vocabularyID]?@"收起详情":@"查看详情" action:@selector(toggleSavedWordDetails:) primary:NO];details.identifier=entry.vocabularyID;
        NSButton *toggle=[receiver workspaceButton:revealed?@"遮住释义":@"揭晓释义" action:@selector(toggleWordMeaning:) primary:NO];
        toggle.tag=i;toggle.identifier=entry.vocabularyID;
        [summaryActions addArrangedSubview:details];[summaryActions addArrangedSubview:toggle];[card addArrangedSubview:summaryActions];
        NSStackView *detail=[receiver verticalStack];detail.spacing=10;detail.hidden=![receiver.expandedWordCards containsObject:entry.vocabularyID];
        [card addArrangedSubview:detail];
        [detail addArrangedSubview:[receiver separator]];
        [detail addArrangedSubview:[receiver mutedLabel:entry.completionSource==FYCompletionSourceAI?@"释义来源 · AI 建议":@"释义来源 · 手动录入"]];
        NSTextField *sourceLabel = [receiver label:@"来源原句：—" font:FYUIFont(12, NSFontWeightRegular) color:receiver.uiMuted];
        sourceLabel.maximumNumberOfLines = 0;
        sourceLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [detail addArrangedSubview:sourceLabel];
        [detail addArrangedSubview:[receiver mutedLabel:[NSString stringWithFormat:@"遇到的词形：%@ · 自评：%@", entry.surface, entry.reviewStatus == FYReviewStatusKnown ? @"记住了" : @"还不熟"]]];
        NSButton *exampleButton = [NSButton buttonWithTitle:@"下一个来源例句" target:[receiver collectionActionTarget] action:@selector(nextWordExample:)];
        exampleButton.identifier = entry.vocabularyID; exampleButton.hidden = YES;
        [detail addArrangedSubview:exampleButton];
        NSString *vocabularyID = entry.vocabularyID;
        [receiver loadExamplesForWord:vocabularyID generation:generation sourceLabel:sourceLabel exampleButton:exampleButton];
        NSStackView *actions = [receiver horizontalStack];
        NSButton *mastered = [NSButton buttonWithTitle:(entry.reviewStatus == FYReviewStatusKnown ? @"标记还不熟" : @"标记记住了") target:[receiver collectionActionTarget] action:@selector(toggleWordMastered:)];
        mastered.bezelStyle = NSBezelStyleRounded;
        mastered.tag = i; mastered.identifier = entry.vocabularyID;
        NSButton *remove = [NSButton buttonWithTitle:@"取消收藏" target:[receiver collectionActionTarget] action:@selector(removeWordCard:)];
        remove.bezelStyle = NSBezelStyleRounded;
        remove.tag = i; remove.identifier = entry.vocabularyID;
        [actions addArrangedSubview:mastered];
        [detail addArrangedSubview:actions];
        NSStackView *management=[receiver horizontalStack];
        NSButton *reference=[receiver workspaceButton:@"用法与等级参考" action:@selector(showSavedWordReference:) primary:NO];
        reference.identifier=entry.vocabularyID;
        [management addArrangedSubview:reference];
        [management addArrangedSubview:remove];
        [detail addArrangedSubview:management];
        FYSavedWordReferenceView *savedReference=[FYSavedWordReferenceView new];savedReference.hidden=YES;
        [detail addArrangedSubview:savedReference];
        [receiver.wordCardStack addArrangedSubview:[receiver cardWithStack:card]];
    }
}

+ (void)renderHistoryRowsWithReceiver:(id<FYCollectionRenderSource>)receiver {
        NSDateFormatter *time = [NSDateFormatter new]; time.dateFormat = @"HH:mm";
        for (NSUInteger i = 0; i < receiver.historyRecords.count; i++) {
            FYSentenceRecord *record = receiver.historyRecords[i];
            NSStackView *row = [receiver horizontalStack]; row.spacing = 18;
            NSStackView *text = [receiver verticalStack]; text.spacing = 5;
            [text addArrangedSubview:[receiver label:record.latestText font:FYUIFont(14, NSFontWeightRegular) color:receiver.uiInk]];
            [text addArrangedSubview:[receiver mutedLabel:record.latestTranslation.length ? record.latestTranslation : @"暂无该句译文"]];
            NSString *kind = record.kind == FYSentenceKindDialogue ? @"对白" : record.kind == FYSentenceKindOption ? @"选项" : record.kind == FYSentenceKindUI ? @"界面" : @"快照";
            [text addArrangedSubview:[receiver mutedLabel:[NSString stringWithFormat:@"%@ · %@ · 版本 %ld", kind, [time stringFromDate:record.occurredAt], (long)record.latestVersion]]];
            [row addArrangedSubview:text];
            NSButton *analyze = [receiver workspaceButton:@"查看与分析 ↗" action:@selector(openHistoryAnalysis:) primary:NO];
            analyze.tag = i; analyze.identifier = record.sentenceID;
            [row addArrangedSubview:analyze];
            NSStackView *historyCard = [receiver verticalStack]; [historyCard addArrangedSubview:row];
            [receiver.historyListStack addArrangedSubview:[receiver cardWithStack:historyCard]];
        }
}

+ (void)renderGrammarRowsWithReceiver:(id<FYCollectionRenderSource>)receiver {
        for (FYGrammarBookmark *bookmark in receiver.grammarBookmarks) {
            NSStackView *card = [receiver verticalStack]; card.spacing = 8;
            NSStackView *heading = [receiver horizontalStack];
            [heading addArrangedSubview:[receiver cardTitle:bookmark.name]];
            FYGrammarCatalogEntry *catalog = bookmark.catalogID.length ? [receiver.grammarCatalog entryForID:bookmark.catalogID] : [receiver.grammarCatalog entryForName:bookmark.name];
            [heading addArrangedSubview:[receiver mutedLabel:catalog.referenceLevel.length ? [NSString stringWithFormat:@"参考 %@ · %@", catalog.referenceLevel, [catalog.levelReviewStatus isEqualToString:@"verified"] ? @"已核实" : @"待核实"] : @"等级待核实"]];
            [card addArrangedSubview:heading];
            [card addArrangedSubview:[receiver label:bookmark.sourceTextSnapshot font:FYUIFont(14, NSFontWeightRegular) color:receiver.uiInk]];
            [card addArrangedSubview:[receiver mutedLabel:bookmark.translationSnapshot.length ? bookmark.translationSnapshot : @"暂无该句译文"]];
            NSButton *remove = [NSButton buttonWithTitle:@"取消收藏" target:[receiver collectionActionTarget] action:@selector(deleteGrammarBookmark:)];
            remove.identifier = bookmark.bookmarkID; [card addArrangedSubview:remove];
            [receiver.savedGrammarCardStack addArrangedSubview:[receiver cardWithStack:card]];
        }
}

+ (void)renderSentenceRows:(NSArray<FYRequestIdentity *> *)identities receiver:(id<FYCollectionRenderSource>)receiver {
        if(!identities.count){[receiver.savedSentenceStack addArrangedSubview:[receiver mutedLabel:@"在查句弹窗中收藏想复习的句子。"]];}
        for(NSUInteger index=0;index<identities.count;index++){
            FYRequestIdentity *identity=identities[index];NSStackView *card=[receiver verticalStack];
            [card addArrangedSubview:[receiver label:identity.sourceText font:FYUIFont(14, NSFontWeightRegular) color:receiver.uiInk]];
            [card addArrangedSubview:[receiver mutedLabel:identity.translation ?: @""]];NSStackView *row=[receiver horizontalStack];
            for(NSString *title in @[@"查看句子结构",@"取消收藏"]){NSButton *button=[receiver workspaceButton:title action:[title isEqualToString:@"取消收藏"]?@selector(removeSavedSentence:):@selector(openSavedSentence:) primary:NO];button.tag=index;button.identifier=[NSString stringWithFormat:@"%@:%ld",identity.sentenceID,(long)identity.version];[row addArrangedSubview:button];}
            [card addArrangedSubview:row];[receiver.savedSentenceStack addArrangedSubview:[receiver cardWithStack:card]];
        }
}

+ (void)updateDetailsButton:(NSButton *)sender expanded:(BOOL)expanded {
    // Update the existing card in place; do not rebuild the list or reset scroll.
    NSStackView *card=(NSStackView *)sender.superview.superview;
    card.arrangedSubviews.lastObject.hidden=expanded;sender.title=expanded?@"查看详情":@"收起详情";
}

+ (void)updateMeaningButton:(NSButton *)sender entry:(FYVocabularyEntry *)entry revealed:(BOOL)revealed {
    NSStackView *card=(NSStackView *)sender.superview.superview;
    NSTextField *meaning=(NSTextField *)card.arrangedSubviews[1];
    meaning.stringValue=revealed?(entry.meaning.length?entry.meaning:@"释义待补充"):@"释义已遮住，先回忆它的意思。";
    sender.title=revealed?@"遮住释义":@"揭晓释义";
}

@end
